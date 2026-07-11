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
/// engaged even when the tonal chain is bypassed, so summed voices (8 drums +
/// bio synth + poly + sampler) can never hard-clip the output into harsh
/// digital distortion. Transparent at normal levels — it only catches peaks.
///
/// Controls:
/// - isEnabled: bypass the tonal chain (EQ); the safety limiter remains on
/// - targetLUFS: auto-gain target (-14 streaming, -9 club, -23 broadcast)
/// - preset: tonal character (balanced / warm / bright / transparent)
@MainActor @Observable
final class AutoMixChain {

    // MARK: - Observable state

    var isEnabled: Bool = true {
        didSet { applyBypass() }
    }
    var targetLUFS: Float = -14 {          // Spotify / Apple Music standard
        didSet { updateAutoGain() }
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
    nonisolated static func steadyGainDB(current: Float, targetLUFS: Float, lufsReading: Float,
                             maxDB: Float = 6,
                             boostCoeff: Float = 0.05, cutCoeff: Float = 0.18,
                             deadZoneDB: Float = 0.4) -> Float {
        let raw = Swift.min(Swift.max(targetLUFS - lufsReading, -maxDB), maxDB)
        let delta = raw - current
        guard Swift.abs(delta) >= deadZoneDB else { return current }   // hold — no micro-pumping
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
