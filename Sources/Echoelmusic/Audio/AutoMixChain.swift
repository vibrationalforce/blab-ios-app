#if canImport(AVFoundation)
import AVFoundation
import Accelerate
import AudioToolbox
import Observation

/// Transparent mastering chain inserted between masterMixer and mainMixerNode.
/// Makes any improv session sound release-ready without user intervention.
///
/// Graph after install: masterMixer → EQ → gainNode → limiter → mainMixerNode
///
/// The final stage is an always-on Apple PeakLimiter brick-wall: it stays
/// engaged even when the tonal chain is bypassed, so the summed voices can never
/// hard-clip the output into harsh digital distortion. Transparent at normal
/// levels — it only catches peaks.
/// (⛔ This sentence used to enumerate them as "8 drums + bio synth + poly +
/// sampler". The drums were removed in #166/#167 and make no sound at all today,
/// so the example named a load this stage cannot receive. The claim does not
/// depend on the count, so it is stated without one rather than re-counted —
/// a number here would only go stale again.)
///
/// Controls:
/// - isEnabled: bypass the tonal chain (EQ); the safety limiter remains on
/// - targetLUFS: auto-gain target, resolved from the ONE stored loudness setting
///   (`StudioDefaultKeys.loudnessTarget` → `LoudnessTarget`), NOT a free number:
///   No target (nil, unity) · Streaming −14 · Podcast −16 · Broadcast EBU −23 ·
///   Cinema −24 LUFS. The correction it applies is clamped to ±6 dB.
///   (⛔ This line said "-14 streaming, -9 club, -23 broadcast". There is no club
///   target and there never was a −9 case in `LoudnessTarget`; podcast and cinema
///   were missing. It is the line a session reads before touching the target, and
///   it named a value the picker cannot produce.)
/// - preset: tonal character (balanced / warm / bright / transparent)
@MainActor @Observable
final class AutoMixChain {

    // MARK: - Observable state

    var isEnabled: Bool = true {
        didSet { applyBypass() }
    }
    /// The master auto-gain target — resolved from the ONE stored loudness setting the export
    /// path already uses, so the picker in the Master panel now moves both stages.
    ///
    /// It used to be a stored `Float = -14` with **no writer anywhere**. That made "No target"
    /// a half-truth: it disabled the EXPORT normalisation (fixed 2026-07-27) while this stage
    /// had already pulled the whole live signal toward −14 — and `RetroCapture` taps
    /// `mainMixerNode`, i.e. DOWNSTREAM of this gain, so every captured file carried it baked
    /// in before the export switch was even consulted.
    ///
    /// COMPUTED, not stored, deliberately: a stored mirror needs a writer, and every
    /// half-threaded fix in this repo has been a writer someone forgot. One source, no
    /// synchronisation. The 5 Hz auto-gain timer re-reads it, so a picker change takes effect
    /// within ~200 ms and then eases — no `didSet` needed and no click.
    ///
    /// `nil` = the user chose "No target": hold the level where the mix puts it. The safety
    /// limiter is a separate, always-on stage and stays on.
    /// NOT observation-tracked. `@Observable` instruments STORED properties only, so a
    /// SwiftUI body reading this would never be re-rendered when the key changes. Nothing
    /// reads it from a view today — if you need one, bind
    /// `@AppStorage(StudioDefaultKeys.loudnessTarget.key)`, never this property.
    var targetLUFS: Float? { Self.resolvedTarget(from: .standard) }

    /// The resolution itself, pulled out as a pure, injectable seam so the WIRING is
    /// testable and not just the arithmetic. That distinction is the whole reason this bug
    /// lived so long: `steadyGainDB` was well covered while the −14 that actually reached it
    /// came from a stored property nothing asserted. Same move as
    /// `SingleExport.normalizeGainDB` for the export half of this fix.
    ///
    /// `StudioDefaultKeys.loudnessTarget.value` is the CANONICAL FRESH-INSTALL value, not a
    /// registered one — nothing calls `UserDefaults.register(defaults:)` for it, `@AppStorage`
    /// defaults are per-declaration and never written to the store. So on a fresh install
    /// `string(forKey:)` returns nil and this `??` is doing all the work; do not delete it
    /// believing a registration covers it.
    nonisolated static func resolvedTarget(from defaults: UserDefaults) -> Float? {
        let raw = defaults.string(forKey: StudioDefaultKeys.loudnessTarget.key)
            ?? StudioDefaultKeys.loudnessTarget.value
        return LoudnessTarget.resolvedLUFS(rawValue: raw)
    }
    private(set) var lufsReading: Float = -60
    private(set) var isInstalled: Bool = false

    // MARK: - Preset

    enum Preset: Equatable { case balanced, warm, bright, transparent }
    var preset: Preset = .balanced {
        didSet { applyPreset() }
    }

    // MARK: - AVAudio nodes

    @ObservationIgnored private let eq      = AVAudioUnitEQ(numberOfBands: 4)
    @ObservationIgnored private let gainNode = AVAudioMixerNode()
    /// Always-on brick-wall safety limiter (Apple PeakLimiter) — the final
    /// stage, prevents the summed master from clipping into harsh distortion.
    @ObservationIgnored private let limiter: AVAudioUnitEffect = {
        var desc = AudioComponentDescription()
        desc.componentType = kAudioUnitType_Effect
        desc.componentSubType = kAudioUnitSubType_PeakLimiter
        desc.componentManufacturer = kAudioUnitManufacturer_Apple
        desc.componentFlags = 0
        desc.componentFlagsMask = 0
        return AVAudioUnitEffect(audioComponentDescription: desc)
    }()

    // MARK: - LUFS meter (via metering timer reading masterLevel RMS)
    @ObservationIgnored private var masterLevelRef: (() -> Float)?
    @ObservationIgnored private var lufsTimer: Timer?

    // MARK: - Install

    /// Call from setupMasterEngine() BEFORE engine.start().
    /// Replaces the direct masterMixer → mainMixerNode connection.
    func insert(
        into engine: AVAudioEngine,
        from source: AVAudioNode,
        to destination: AVAudioNode,
        format: AVAudioFormat
    ) {
        engine.attach(eq)
        engine.attach(gainNode)
        engine.attach(limiter)

        engine.connect(source,   to: eq,       format: format)
        engine.connect(eq,       to: gainNode, format: format)
        engine.connect(gainNode, to: limiter,  format: format)
        engine.connect(limiter,  to: destination, format: format)

        configureEQ()
        isInstalled = true
        log.audio("AutoMixChain inserted — EQ → gainNode → limiter → mainMixer")
    }

    /// Provide a closure that returns the current master RMS (0-1 linear).
    /// AutoMixChain uses this to compute LUFS and drive auto-gain.
    func connectMeter(_ getter: @escaping () -> Float) {
        masterLevelRef = getter
        lufsTimer?.invalidate()
        lufsTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateLUFS() }
        }
    }

    // MARK: - LUFS update (called every 200ms on main thread)

    private func updateLUFS() {
        guard let getter = masterLevelRef else { return }
        let rmsLinear = getter() / 3.0          // undo the *3 scaling in AudioEngine meter
        guard rmsLinear > 0.0001 else {
            lufsReading = -60
            return
        }
        // BS.1770 approximation: LUFS ≈ dBFS - 0.1 (K-weighting offset)
        let dBFS = 20 * Foundation.log10(rmsLinear)
        lufsReading = dBFS - 0.1
        updateAutoGain()
    }

    /// The smoothed auto-gain, in dB — eased toward the target each 200 ms tick so the
    /// master level settles instead of chasing every momentary reading (the old "die
    /// Levels bewegen sich ständig" pumping). Starts at unity (0 dB).
    @ObservationIgnored private var smoothedGainDB: Float = 0

    /// PROFI-PEGEL (founder 2026-07-11: "EchoelSynth rudimentär bei den Levels"). One
    /// pure, deterministic step of the smoothed auto-gain in the dB domain — no AVAudio,
    /// so it is unit-testable. The correction is:
    ///  • NARROWED to ±`maxDB` (was ±12 dB → 0.25–4×, which let sparse vs. dense passages
    ///    swing the master a full ±12 dB and pump),
    ///  • EASED with a one-pole toward the target — ASYMMETRIC: slow when BOOSTING a quiet
    ///    passage (a gap/held note must not pump up), a touch quicker when TAMING a loud
    ///    one (so a sudden chord is caught) — the fast brick-wall stays the PeakLimiter's
    ///    job, not this stage's,
    ///  • held inside a small `deadZoneDB` so tiny deviations never nudge the level.
    /// Returns the next smoothed gain in dB.
    ///
    /// `targetLUFS` is OPTIONAL: `nil` means "No target" and resolves to a raw correction of
    /// 0 dB, i.e. the stage eases back to unity through the SAME one-pole instead of snapping
    /// — toggling the control must not click. The always-on PeakLimiter is a separate stage
    /// and is unaffected, so "no target" never means "no clipping protection".
    nonisolated static func steadyGainDB(current: Float, targetLUFS: Float?, lufsReading: Float,
                             maxDB: Float = 6,
                             boostCoeff: Float = 0.05, cutCoeff: Float = 0.18,
                             deadZoneDB: Float = 0.4) -> Float {
        let raw = targetLUFS.map { Swift.min(Swift.max($0 - lufsReading, -maxDB), maxDB) } ?? 0
        let delta = raw - current
        guard Swift.abs(delta) >= deadZoneDB else {
            // WITH a target, holding inside the dead zone is the anti-pumping rule.
            // WITHOUT one there is nothing to hold against: the same guard would park a
            // PERMANENT residual of up to ±deadZoneDB (±0.4 dB ≈ ±4.7 % linear) — so "no
            // target" would still be applying a gain, just a smaller lie. Land on exact
            // unity instead, which is also what the export half of this control does
            // (`SingleExport.normalizeGainDB` returns exactly 0 for nil). The step taken
            // here is by definition < deadZoneDB, so it cannot click.
            return targetLUFS == nil ? 0 : current
        }
        let coeff = delta > 0 ? boostCoeff : cutCoeff                  // slow to boost, quicker to cut
        return current + delta * Swift.min(Swift.max(coeff, 0), 1)
    }

    private func updateAutoGain() {
        guard isInstalled, lufsReading > -59 else { return }
        smoothedGainDB = Self.steadyGainDB(current: smoothedGainDB,
                                           targetLUFS: targetLUFS, lufsReading: lufsReading)
        let linearGain = Foundation.pow(10.0, Double(smoothedGainDB) / 20.0)
        gainNode.outputVolume = Float(Swift.min(Swift.max(linearGain, 0.5), 2.0))
    }

    // MARK: - Node configuration

    private func configureEQ() {
        // Master curve retuned 2026-06-23 from an FFT of a real take: the mix was
        // sub-dominated and dark (20–60 Hz ~+15 dB over the low-mids, almost nothing
        // above 8 kHz). The old "balanced" preset made it worse — a low-shelf BOOST
        // (boom) + a presence DIP (darker). The new curve trims rumble, tames the
        // boom, restores presence and opens the air so the body's take reads clear.

        // Band 0: High-pass 45 Hz — trim deep, non-musical rumble (felt sub stays).
        eq.bands[0].filterType  = .highPass
        eq.bands[0].frequency   = 45
        eq.bands[0].bypass      = false

        // Band 1: Low-shelf CUT -1.5 dB at 140 Hz — tame the boom/mud that swamped
        // the mids (was a +1.5 dB boost).
        eq.bands[1].filterType  = .lowShelf
        eq.bands[1].frequency   = 140
        eq.bands[1].gain        = -1.5
        eq.bands[1].bypass      = false

        // Band 2: Presence boost +1.5 dB at 2.8 kHz (clarity/definition). Trimmed 2026-07-07
        // (warmth pass) from +2 dB so the master doesn't push voices forward/cold.
        eq.bands[2].filterType  = .parametric
        eq.bands[2].frequency   = 2800
        eq.bands[2].bandwidth   = 1.5
        eq.bands[2].gain        = 1.5
        eq.bands[2].bypass      = false

        // Band 3: Air shelf +2.5 dB at 9 kHz (openness). Trimmed 2026-07-07 (warmth pass)
        // from +3.5 dB — the glassy 9 kHz air was what made bright voices read cold.
        eq.bands[3].filterType  = .highShelf
        eq.bands[3].frequency   = 9000
        eq.bands[3].gain        = 2.5
        eq.bands[3].bypass      = false
    }

    // MARK: - Preset switching

    private func applyPreset() {
        // Gains are (low-shelf @140, presence @2.8k, air @9k). Balanced = the new
        // clear default; warm leans back toward body/low-mids; bright pushes
        // presence + air; transparent is flat.
        switch preset {
        case .balanced:
            eq.bands[1].gain = -1.5
            eq.bands[2].gain =  1.5
            eq.bands[3].gain =  2.5
        case .warm:
            eq.bands[1].gain =  1.5
            eq.bands[2].gain =  0.5
            eq.bands[3].gain =  1.5
        case .bright:
            eq.bands[1].gain = -2.5
            eq.bands[2].gain =  3.0
            eq.bands[3].gain =  5.0
        case .transparent:
            eq.bands[1].gain =  0
            eq.bands[2].gain =  0
            eq.bands[3].gain =  0
        }
    }

    // MARK: - Bypass

    private func applyBypass() {
        eq.bypass = !isEnabled
        if !isEnabled {
            gainNode.outputVolume = 1.0
            smoothedGainDB = 0            // re-enabling eases from unity, no jump
        }
        log.audio("AutoMixChain \(isEnabled ? "enabled" : "bypassed")")
    }
}
#endif
