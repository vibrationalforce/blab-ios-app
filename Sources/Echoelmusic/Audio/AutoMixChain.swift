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
/// sampler". #166/#167 removed the drum apparatus, so the example named a load
/// this stage cannot receive: `PatternEngine.onStep` fires, but the only
/// assignment to it repo-wide is `BeatPlayer`'s `pattern.onStep = nil`, and the
/// three drum voice files are deleted. **No PERCUSSION can be produced.** Said
/// that precisely rather than "the drums make no sound", which is refutable in
/// two lines: `LaneVoiceKind` maps `case .drums` to `.poly`, so a persisted lane
/// carrying the retired instrument deliberately still sounds — as a synth. The
/// claim above does not depend on the count, so it is stated without one rather
/// than re-counted; a number here would only go stale again.)
///
/// Controls:
/// - isEnabled: bypass the tonal chain (EQ); the safety limiter remains on
/// - targetLUFS: auto-gain target, resolved from the ONE stored loudness setting
///   (`StudioDefaultKeys.loudnessTarget` → `LoudnessTarget`), NOT a free number:
///   No target (nil, unity) · Streaming −14 · Podcast −16 · Broadcast EBU −23 ·
///   Cinema −24 LUFS. The correction it applies is clamped to ±6 dB.
///   (⛔ This line said "-14 streaming, -9 club, -23 broadcast". There is no club
///   target and no −9 case in `LoudnessTarget`; podcast and cinema were missing.
///   It is the line a session reads before touching the target, and it named a
///   value the picker cannot produce. Deliberately PRESENT TENSE: the first fix
///   wrote "there never was a −9 case", and this is a shallow clone — `git log -S`
///   cannot reach behind the graft, so the history half was unprovable. The same
///   correction is made elsewhere in `CLAUDE.md`; an unbacked "always was" is the
///   kind of sentence nobody can later refute.)
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
    /// synchronisation. The auto-gain timer snapshots it once per measurement tick (see
    /// `tickTarget`), so a picker change takes effect within ~200 ms and then eases — no
    /// `didSet` needed.
    ///
    /// ⛔ THIS LINE ENDED "and no click" UNTIL #404, and that was the false half. Easing does
    /// not by itself make a change inaudible: what reaches the audio is a STAIRCASE of
    /// `AVAudioMixerNode.outputVolume` writes, and each stair is a discontinuity at a render
    /// boundary. At the old rate the first stair after a target change was up to −11.7 % of
    /// amplitude — a click, and then another every 200 ms while it converged. The stairs are
    /// now 10× finer (see `subSteps`); "no click" is still not something a comment should
    /// promise without a number next to it.
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

    /// The LAST node of the chain — the limiter's output, i.e. the signal after EQ,
    /// auto-gain and the brick-wall limiter have all done their work.
    ///
    /// Exposed for ONE purpose (#316b): so the master meter tap can sit here instead of
    /// on `masterMixer`, which is upstream of everything this chain does. A readout taken
    /// before the stage whose job is to bound it is not a readout of what leaves the
    /// device — that was the #316 defect, disclosed on screen and deferred to here.
    ///
    /// `nil` until `insert` has run, so a caller can fall back to the pre-chain node
    /// rather than tapping an unattached node (which would trap).
    ///
    /// ⚠️ IT IS NOT THE VERY LAST GAIN. `mainMixerNode.outputVolume` (the −1 dBFS safety
    /// trim) is applied AFTER this node, downstream, and a tap here cannot see it. The
    /// caller must account for it — as a dB offset, which is exact: the trim is a linear
    /// gain, and both K-weighted loudness and peak shift by exactly 20·log10(trim).
    var chainOutputNode: AVAudioNode? { isInstalled ? limiter : nil }

    /// Provide a closure that returns the current master RMS (0-1 linear).
    /// AutoMixChain uses this to compute LUFS and drive auto-gain.
    ///
    /// ⭐ ONE TIMER, TWO RATES (#404): it fires at `easeInterval` (20 ms) and only every
    /// `subSteps`-th tick re-READS the meter. The measurement rate is unchanged — `lufsReading`
    /// still publishes at 5 Hz, which matters because it IS observation-tracked and feeds the
    /// loudness readout; raising it would put a 50 Hz write in front of a SwiftUI body, i.e.
    /// the menu-freeze law. Only the GAIN APPLICATION runs at 50 Hz, and it writes
    /// `smoothedGainDB` (`@ObservationIgnored`) plus one `Float` on a mixer node — nothing a
    /// view observes.
    ///
    /// ⛔ `MainActor.assumeIsolated`, NOT `Task { @MainActor }` — and the first version of this
    /// commit got that wrong at 50 Hz, which is the rate `HARNESS_LEDGER` records as a proven
    /// dead-end (the 10.76.48 menu freeze was a per-frame main-actor task submission). The
    /// timer is installed from a `@MainActor` method onto the main run loop, so the block
    /// ALREADY runs on the main thread and the hop bought nothing but an allocation. It also
    /// bought a real hazard the ledger does not name: `Task` submissions are enqueued, not
    /// inline, so under main-thread load ten 20 ms sub-steps can bunch into one runloop turn —
    /// reassembling the very staircase this change exists to break apart. Precedent for the
    /// synchronous form at a HIGHER rate: `AudioEngine`'s 60 Hz meter poll.
    ///
    /// ⚠️ `assumeIsolated` TRAPS (SIGTRAP) if the handler is not literally on the main queue —
    /// see the note in `PatternEngine`. Safe here only because `Timer.scheduledTimer` installs
    /// on the run loop of the calling thread and the one caller is `AudioEngine.start()`. If
    /// this ever moves to a `DispatchSourceTimer` or a background queue, the form must change
    /// with it.
    func connectMeter(_ getter: @escaping () -> Float) {
        masterLevelRef = getter
        lufsTimer?.invalidate()
        easeTick = 0
        tickTarget = targetLUFS
        lufsTimer = Timer.scheduledTimer(withTimeInterval: Self.easeInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.easeTick += 1
                if self.easeTick >= Self.subSteps {
                    self.easeTick = 0
                    self.updateLUFS()
                    self.tickTarget = self.targetLUFS
                }
                self.updateAutoGain()
            }
        }
    }

    /// The loudness target resolved ONCE per measurement tick, and eased toward for the ten
    /// applications that follow it.
    ///
    /// Two reasons, and the second is the one that matters. (1) `targetLUFS` is COMPUTED — it
    /// hits `UserDefaults.string(forKey:)` plus a String-raw-value enum init on every read, and
    /// the #404 rate change silently took that from 5×/s to 50×/s on the main thread. (2) The
    /// exactness argument in `subSteps` holds only if the target is CONSTANT across a window.
    /// Re-resolving mid-window made that contingent on the user not touching the picker; a
    /// snapshot makes it structural. A picker change is still picked up within one tick.
    @ObservationIgnored private var tickTarget: Float?

    /// How often the gain is APPLIED. See `subSteps` for why this is not the measurement rate.
    ///
    /// `nonisolated` deliberately: this class is `@MainActor`, and Xcode's toolchain isolates
    /// even an immutable `static let` to the actor (CLAUDE.md records the exact error). Both
    /// constants are read from a non-isolated test method and one of them is a default argument
    /// of a `nonisolated` function — without this the blocking bundle would not compile.
    nonisolated static let easeInterval: TimeInterval = 0.02

    /// How many gain applications happen per measurement — the whole #404 fix in one number.
    ///
    /// ⭐ WHY: `gainNode` is an `AVAudioMixerNode`, and `outputVolume` has **no DOCUMENTED
    /// ramp** — no ramped-set API exists on it, unlike `AUParameter`'s explicit `.ramp` event.
    /// If a write lands whole at the next render quantum, then at the old
    /// one-application-per-200-ms rate a 6 dB correction moved the master **1.08 dB in a single
    /// render boundary, an instantaneous −11.7 % of amplitude**; the worst legal delta (±6 dB
    /// target, ∓6 dB current) gave 2.16 dB = −22.0 %. On a sustained pad that is a click, and
    /// because the one-pole keeps stepping every 200 ms while it converges it is a BURST of
    /// clicks — which is what "teilweise extremes Knacken" sounds like, and why it is
    /// intermittent: it only happens while the level is actually moving.
    ///
    /// ⛔ THE FIRST VERSION OF THIS DOC WROTE "has no ramp" AS A FACT, in a commit whose own
    /// headline was "measured, not guessed". It is not established. Apple's mixer AUs have
    /// historically interpolated gain across a render slice precisely to avoid zipper noise —
    /// undocumented implementation behaviour that has changed across OS versions. If it holds,
    /// the pre-#404 step was a ~100 dB/s ramp over one 10.7 ms slice, i.e. inaudible, and this
    /// change buys nothing (it also costs nothing). **The decisive experiment is already in the
    /// repo:** `RetroCapture` taps `mainMixerNode`, DOWNSTREAM of `gainNode` — record while
    /// moving the loudness-target picker and look at a sustained pad's envelope. A literal
    /// staircase on a 200 ms grid settles it; a smooth ramp retires this diagnosis.
    ///
    /// ⚠️ THE TIME CONSTANT IS UNCHANGED EXACTLY — but only while `|delta| > deadZoneDB`, which
    /// is the whole of the correction range that matters. Applying a one-pole coefficient `c`
    /// once is identical to applying `1 − (1−c)^(1/n)` n times against the SAME target, because
    /// both leave `(1−c)` of the distance; and `updateLUFS` runs only on the wrapping tick, so
    /// the target really is constant across each window of ten. The founder's tuned
    /// anti-pumping feel (slow to boost, quicker to cut) therefore lands on the identical value
    /// at every 200 ms boundary; only the staircase inside gets 10× finer. Same 6 dB cut now
    /// steps 0.118 dB = −1.35 %.
    ///
    /// ⛔ "bit-for-bit" STOOD HERE AND WAS FALSE IN A NARROW BAND. `steadyGainDB`'s dead-zone
    /// hold is now evaluated per sub-step, so for `|delta|` in `[0.400, 0.478)` dB on the cut
    /// path (`[0.400, 0.419)` on boost) the hold can engage part-way through a window where it
    /// was previously all-or-nothing. The stage then parks on a residual up to
    /// `deadZoneDB × c` = 0.072 dB larger. Inaudible, and in the safer direction — but an
    /// absolute word with a counter-example is exactly what this repo keeps paying to undo.
    ///
    /// ⚠️ AND THIS IS A MECHANISM, NOT A CONFIRMED DIAGNOSIS. The founder's report is
    /// "teilweise extremes Knacken" on v10.79.369 with no log attached; the arithmetic above
    /// proves this stage CAN click and by how much, not that it is the only source — and the
    /// ⛔ above says the premise itself is unverified. Do not close #404 on this commit: a
    /// device listen, and a `echoel_diag.log` from a crackling session, are what close it.
    nonisolated static let subSteps = 10

    /// The shipped per-application coefficients, hoisted so the two numbers have ONE home
    /// instead of living as call-site literals a source scan has to match character for
    /// character — and so the `pow` runs once at static-init rather than 50×/s.
    nonisolated static let boostSubStep: Float = subStepped(0.05)
    nonisolated static let cutSubStep: Float = subStepped(0.18)

    /// Counts applications since the last measurement. Not observation-tracked: it changes
    /// 50×/s and nothing may re-render on it.
    @ObservationIgnored private var easeTick = 0

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
        // NOT `updateAutoGain()` here any more — the caller applies the gain on EVERY tick,
        // this one included. Calling it here too would double-step the measurement tick.
    }

    /// The smoothed auto-gain, in dB — eased toward the target every 20 ms (ten sub-steps per
    /// 200 ms measurement window since #404; it was one whole step per 200 ms) so the
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
            // (`SingleExport.normalizeGainDB` returns exactly 0 for nil).
            //
            // ⛔ THIS COMMENT ENDED "The step taken here is by definition < deadZoneDB, so it
            // cannot click" AND THAT IS THE LARGEST SINGLE STEP THIS FILE PRODUCES. It is up
            // to 0.4 dB (+4.7 % of amplitude) in ONE application — 1.7× the worst case
            // `subSteps` engineers away, 2.7× the mark the guard calls inaudible, and 80 % of
            // its click ceiling. It squeaks under only because the ceiling is 0.5. So: an
            // unnumbered inaudibility promise, in the same file whose #404 block strikes
            // exactly that habit. KEPT rather than sub-stepped, deliberately — easing the last
            // 0.4 dB would make "No target" take up to a further 200 ms to reach EXACT unity,
            // and a residual gain under a control that says "no target" is the #183 lie this
            // branch exists to end. The step is real, it is one-shot, and it fires only when
            // the user themselves moves the picker; that is a different thing from a burst
            // that happens while they are listening.
            return targetLUFS == nil ? 0 : current
        }
        let coeff = delta > 0 ? boostCoeff : cutCoeff                  // slow to boost, quicker to cut
        return current + delta * Swift.min(Swift.max(coeff, 0), 1)
    }

    /// One SUB-step of the ease. The coefficients are the shipped ones spread over `subSteps`
    /// applications; `deadZoneDB` is deliberately NOT spread — it is a hold threshold, not a
    /// rate, and dividing it would let a deviation the founder chose to ignore start creeping.
    private func updateAutoGain() {
        // `isEnabled` belongs here: without it the timer overwrote `applyBypass`'s
        // neutralisation on the next tick, so "AutoMix off" was a lying control that held for
        // 200 ms — and #404 would have shortened that to 20 ms. Found by review, not by ear.
        guard isInstalled, isEnabled, lufsReading > -59 else { return }
        smoothedGainDB = Self.steadyGainDB(current: smoothedGainDB,
                                           targetLUFS: tickTarget, lufsReading: lufsReading,
                                           boostCoeff: Self.boostSubStep,
                                           cutCoeff: Self.cutSubStep)
        let linearGain = Foundation.pow(10.0, Double(smoothedGainDB) / 20.0)
        // `clamped(to:)`, not `min(max(…))`: this is the line that actually writes the mixer,
        // and the first #404 commit fixed the idiom in `subStepped` while leaving it here —
        // condemning `min(max(…))` fifteen lines above a surviving `min(max(…))` on the more
        // dangerous of the two. NaN here is silence, and CLAUDE.md names it a shipped cause.
        gainNode.outputVolume = Float(linearGain.clamped(to: 0.5...2.0))
    }

    /// The per-application coefficient that reproduces a whole-tick coefficient `c` over
    /// `subSteps` applications: `1 − (1−c)^(1/n)`.
    ///
    /// Pure and `nonisolated` so the equivalence is a TEST and not a claim in a comment —
    /// this repo has paid for the difference. Guarded on both ends because a coefficient
    /// outside 0…1 would either stall the ease (≤0) or overshoot past the target (>1), and
    /// `pow` of a negative base is NaN, which would silence the master.
    ///
    /// ⚠️ `clamped(to:)`, NOT `min(max(…))`: the latter passes NaN straight through (CLAUDE.md
    /// names it a shipped permanent-silence cause), and a NaN here would land on
    /// `outputVolume`. The first version of this function had exactly that bug.
    nonisolated static func subStepped(_ coeff: Float, over n: Int = subSteps) -> Float {
        guard n > 1 else { return coeff.clamped(to: 0...1) }
        let c = Double(coeff.clamped(to: 0...1))
        // Double, then narrowed: `Foundation.pow` is the Double overload here, and doing the
        // root in Float would lose precision exactly where the equivalence above is asserted.
        return Float(1 - Foundation.pow(1 - c, 1 / Double(n)))
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
