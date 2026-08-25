#if canImport(AVFoundation)
import Foundation
import AVFoundation
import Combine
import Accelerate
import Observation

/// Central audio engine for bio-reactive synthesis
@MainActor
@Observable
public final class AudioEngine {

    // MARK: - Observed Properties

    var isRunning: Bool = false
    // ⛔ `var spatialAudioEnabled: Bool = false` STOOD HERE AND WAS DELETED (#756). Measured
    // across `Sources/` AND `Tests/`: exactly ONE occurrence, its own declaration. No reader,
    // no writer, not persisted, no UserDefaults key, and no spatial code anywhere else in this
    // file. It was not a switch that had lost its UI — it was a switch that never had one.
    //
    // ⚠️ DELETED RATHER THAN REGISTERED, and the difference matters here. The doorless
    // surfaces this repo deliberately keeps (`ImmersiveStageView`, `BroadcastView`,
    // `AudioLanePlayer`) are kept because something PERSISTED can still reach them, so cutting
    // them turns "obviously absent" into "silently mute". Nothing persists this flag, so there
    // is nothing to keep alive — what it did instead was MISDIRECT: Echoel really does have a
    // spatial output, and it is nowhere near this class. It is `Sync/ADMOSCSender` streaming
    // `/adm/obj/{n}/*` over the network, with `DSP/BinauralPanner` for the cues; the stage
    // surface is `Studio/ImmersiveStageView`, doorless on purpose (ship-gate 4 makes
    // light/space "demonstrable, not required for v1"). A plausible-looking hook on the audio
    // engine invites the next session to wire in-engine spatial audio that duplicates a
    // capability the app already ships somewhere else.
    //
    // ⚠️ NO GUARD PINS ITS ABSENCE, deliberately (#364). A test forbidding the name would
    // forbid someone genuinely building in-engine spatial audio one day — which is legitimate
    // work. This comment is the record; if the property comes back it should come back with a
    // reader, a writer and a door, and this block should go with it.
    var inputMonitoringEnabled: Bool = false
    var masterLevel: Float = 0.0
    var masterLevelR: Float = 0.0

    /// Self-healing: set when the engine could not be (re)started after exhausting
    /// automatic recovery, so the UI can offer a "tap to retry" affordance instead
    /// of silently showing "stopped". Cleared on a successful start.
    var degraded: Bool = false
    /// Last audio failure reason (for the degraded affordance / diagnostics).
    var lastAudioError: String?
    /// The engine was paused by an AUDIO SESSION INTERRUPTION (Siri, an alarm banner,
    /// a call) and has not been successfully resumed since.
    ///
    /// This exists because an interruption looks exactly like a deliberate stop from the
    /// inside — both leave `isRunning == false` — and the two must heal differently. A
    /// deliberate stop must NEVER self-heal (it would resurrect a silent engine in the
    /// background); an interrupted one MUST, because iOS does not guarantee an `.ended`
    /// notification at all, and the interruptions this app actually meets take it to
    /// `.inactive` rather than `.background`, so the scene-phase resume never fires
    /// either. Without this flag the failure is silent, total and unrecoverable without
    /// a relaunch — on a live instrument, the worst class of bug there is.
    var wasInterrupted: Bool = false

    // MARK: - Self-healing recovery state (MainActor-confined)

    /// App-layer hook fired when the audio OUTPUT device disappears (headphones
    /// unplugged / BT lost). The app wires the transport-stop cascade here so a
    /// playing arrangement PAUSES instead of resuming on the loudspeaker (HIG).
    /// Called on the MainActor (the route observer runs on the main queue).
    @ObservationIgnored var onOutputDeviceLost: (() -> Void)?

    /// WHY a stop happened, not merely THAT one did.
    ///
    /// ⛔ THE BUG THIS EXISTS TO FIX (device log 2475, v10.79.358, founder: *"Ich hab keinen
    /// Sound alles stumm"*). One flag was answering two different questions, and they have
    /// opposite correct answers for the same event:
    ///   1. "May a self-healing path resurrect this engine?" — for the 2.5.4 idle stop: NO.
    ///      Resurrecting it in the background re-creates the silent-audio state the stop
    ///      just removed (audio-thread review 2026-07-16, F1/F2).
    ///   2. "May coming back to the FOREGROUND start it again?" — for the same idle stop:
    ///      YES, emphatically. That is the entire point of stopping only while idle.
    /// `intentionallyStopped` said no to both. So: app backgrounded with nothing playing →
    /// idle stop → flag set → foreground → the resume gate refused → the user pressed Start
    /// and got a running transport, a running generator, moving visuals and TOTAL SILENCE,
    /// with no way back short of relaunch. The log shows it exactly: `scene: idle audio
    /// engine stopped (2.5.4)` at 629 s, and no `scene: audio resumed` afterwards, ever.
    ///
    /// The flag's NAME is what hid it. "Intentionally" reads as "the user meant it" — and
    /// the resume gate was written against that reading. But grep the two `stop()` callers:
    /// both are the idle rule (`EchoelmusicApp.swift`, the `.background` branch and the
    /// `background-idle` transport subscriber). **There is no user-initiated engine stop in
    /// this app at all.** The gate was therefore suppressing resume on behalf of an intent
    /// nobody had ever expressed.
    /// ⚠️ Deliberately has NO `.none` case — "not stopped" is `stopReason == nil`. A `.none`
    /// case would be passable to `stop(reason:)`, and a stop that recorded "no reason" would
    /// leave `intentionallyStopped` false, letting a self-healing path restart the engine in
    /// the background: the 2.5.4 rejection signature, reintroduced by a typo. Optionality
    /// makes that state unrepresentable instead of merely discouraged.
    enum StopReason {
        /// Guideline 2.5.4: backgrounded with nothing audible. Must NOT self-heal (that is
        /// the rejection signature) and MUST resume when the app returns to the foreground.
        case idleBackground
        /// The user asked for silence. Must neither self-heal nor resume by itself.
        ///
        /// ⚠️ NO PRODUCTION CONSTRUCTOR TODAY, and that is stated rather than hidden. It is
        /// kept because the distinction is the whole content of this type: without it the
        /// next user-facing stop (#179, #204) reintroduces exactly the bug above by reusing
        /// the idle path. `Tests/CISmoke/AudioEngineStopReasonTests.swift` pins both
        /// directions — including that the two predicates DISAGREE on `.idleBackground` —
        /// so this case cannot quietly become equivalent to it.
        case user
    }

    /// `nil` while running, or before the first stop.
    @ObservationIgnored private var stopReason: StopReason?

    /// Whether a SELF-HEALING path may restart the engine. BOTH stop reasons suppress it —
    /// bit-identical to the old stored flag, so all six guards that read it keep today's
    /// behaviour exactly. Only the foreground-resume gate changed.
    private var intentionallyStopped: Bool { Self.selfHealSuppressed(after: stopReason) }

    /// Whether returning to the FOREGROUND may start the engine again. This is the half that
    /// was wrong: an idle-background stop must come back, a user stop must not.
    private var resumeSuppressed: Bool { Self.resumeSuppressed(after: stopReason) }

    /// The two answers, as pure functions, for the same reason `shouldSelfHeal` is one: the
    /// mapping is the part that was wrong, and the properties above are `private` on a
    /// `@MainActor` type that owns a real `AVAudioEngine` — a test cannot reach them without
    /// standing up audio hardware in CI. `nonisolated` so an ordinary `XCTestCase` can call
    /// them (the isolation shape CLAUDE.md records for `static let`).
    ///
    /// They differ on exactly one input, and that difference IS the bug fix. Written as one
    /// predicate with a comment, the next person merges them again.
    nonisolated static func selfHealSuppressed(after reason: StopReason?) -> Bool {
        reason != nil          // both reasons: never resurrect in the background
    }

    nonisolated static func resumeSuppressed(after reason: StopReason?) -> Bool {
        reason == .user        // only the user's own stop survives a foreground return
    }

    /// De-bounce guard so overlapping recovery triggers (route flap + config
    /// change firing together) don't schedule competing `start()` calls.
    @ObservationIgnored private var isRecovering = false
    /// Consecutive failed recovery attempts; capped so a permanently-bad route
    /// can't spin forever. Reset to 0 on any successful start.
    @ObservationIgnored private var recoveryAttempts = 0
    @ObservationIgnored private static let maxRecoveryAttempts = 3
    /// Token for the AVAudioEngineConfigurationChange observer (registered once).
    /// `nonisolated(unsafe)` so the nonisolated `deinit` can remove it; written only
    /// on the MainActor (prepareGraph) and `NotificationCenter.removeObserver` is
    /// safe from any thread.
    @ObservationIgnored nonisolated(unsafe) private var configChangeObserver: NSObjectProtocol?

    /// The one global output trim, applied on `mainMixerNode` AFTER the limiter. A −1 dB
    /// ceiling instead of the limiter's 0 dBFS: device capture showed repeated −0.1 dBFS
    /// peaks (harsh, inter-sample-clip-prone, "not smooth").
    ///
    /// Named rather than inline (#316b) because it is now needed in TWO places — the node
    /// gain, and the dB offset the meter readouts add because the tap sits upstream of it.
    /// Two hand-written 0.89s that must agree is exactly the split #332 was about.
    nonisolated static let outputTrimLinear: Float = 0.89
    /// The trim in dB: 20·log10(0.89) = −1.0122 dB.
    ///
    /// Adding this to a measured dB value is EXACT, not an approximation, and that is why
    /// the meter does not scale samples instead: the trim is a linear gain, and both
    /// K-weighted loudness and (true) peak are homogeneous in gain — scaling every sample
    /// by g shifts both by exactly 20·log10(g). So the offset costs one add per published
    /// value on the main actor instead of a multiply per sample on the audio thread.
    /// Derived from `outputTrimLinear`, NOT re-typed as `20 * log10f(0.89)` — which is what
    /// the first version did, three lines under a comment explaining that two hand-written
    /// 0.89s that must agree is the defect being fixed. Deriving it means the node gain and
    /// the readout offset cannot disagree by construction.
    nonisolated static let outputTrimDb: Float = 20 * log10f(outputTrimLinear)

    /// A measured dB value carried down to the true output — EXCEPT when it is the meter's
    /// FLOOR sentinel, which is passed through untouched.
    ///
    /// WHAT THIS GUARD IS FOR: the floor is a SENTINEL, not a measurement — "the meter has
    /// nothing to report". Adding a gain to it would turn a marker into a slightly smaller
    /// marker, which is a category error even where it happens to be invisible.
    ///
    /// ⛔ THE REASON FIRST WRITTEN HERE WAS OFF BY ONE BAND, and review caught it: it said
    /// the naive `value + trim` would push "a genuine value sitting in the 1 dB band just
    /// above the floor" below the display threshold. The readouts print "—" for
    /// `v <= floor + 1`, so a value in `(floor, floor + 1]` ALREADY printed "—" before any
    /// trim; nothing changes for it. The band that really flips from a number to a dash is
    /// `(floor + 1, floor + 2.0122]`, and this guard does NOT cover it — it is a genuine
    /// measurement about 1 dB above the display threshold, i.e. deep silence, and letting it
    /// read "—" is right. Stated plainly because a precise, confident, wrong justification is
    /// the exact defect the rest of this commit exists to remove.
    nonisolated static func trimmed(_ value: Float, floor: Float) -> Float {
        value <= floor ? floor : value + outputTrimDb
    }

    /// Held master sample-peak / true-peak in dBFS / dBTP, and momentary
    /// loudness in LUFS — published from the master tap (EchoelMix metering).
    ///
    /// ⚠️ THESE MOVED WITH THE TAP (#316b) AND DELIBERATELY KEPT THEIR NAMES AND THEIR
    /// MISSING TRIM, which is the opposite of what was done one declaration below — so the
    /// inconsistency is a decision, not an oversight. They have ZERO readers outside this
    /// file (`git grep` over `Sources/` + `Tests/` returns only these declarations and their
    /// write site in the poll block), so there is no call site a rename would inform and no
    /// display a trim would correct. Renaming them would be churn for its own sake. The
    /// moment one of them acquires a reader, give it the `masterOutput…` treatment — name
    /// AND `trimmed(_:floor:)` — rather than letting a second convention take root.
    ///
    /// ⭐ AND THAT IS EXACTLY WHAT HAPPENED to the third one (#347 Nachlese): the
    /// oscilloscope needed a live peak, so `masterTruePeakDb` became
    /// `masterOutputTruePeakDb` below, with the trim. The instruction above was written for
    /// a case nobody expected to arrive; it arrived four days later. These two stay as they
    /// are under the same rule — they still have no reader.
    var masterPeakDb: Float = EchoelMeter.floorDb
    var masterLUFS: Float = EchoelLoudnessMeter.floorLUFS
    /// Full EBU R128 set at the OUTPUT of the master chain (#316b): short-term (3 s) +
    /// max-hold true-peak (dBTP) + gated integrated loudness (LUFS) + loudness range (LU).
    ///
    /// ⭐ THE `Output` IN THE NAME IS THE WHOLE POINT AND IS LOAD-BEARING. These were
    /// `masterLUFS…`/`masterTruePeakMaxDb` and were measured on `masterMixer` — upstream of
    /// EQ, auto-gain and the brick-wall limiter, i.e. before every stage that decides what
    /// the number should be. #316 could only put a disclosure on screen; this is the move
    /// it deferred. The tap now sits on the chain's last node and these carry
    /// `outputTrimDb` for the one gain that is still downstream of it.
    ///
    /// The rename is deliberate churn: a post-chain value under the old name would look
    /// identical at every call site while meaning something else, and the next reader would
    /// have no way to tell which era they were looking at.
    var masterOutputLUFSShortTerm: Float = EchoelLoudnessMeter.floorLUFS
    var masterOutputTruePeakMaxDb: Float = EchoelMeter.floorDb
    /// LIVE true peak (dBTP) at the master output — the SAME measurement point and the same
    /// `outputTrimDb` as `…MaxDb` one line up, but the meter's decaying hold
    /// (`EchoelMeter.holdDecay`, 0.85 per block) instead of a session max-hold. The two are
    /// deliberately both here: the Master panel asks "did it EVER clip" (max-hold), a scope
    /// asks "how loud is it RIGHT NOW" (decaying hold). A max-hold in a live readout sticks
    /// at the loudest moment of the session and never comes down — which reads as a frozen
    /// meter, the lying-control class.
    ///
    /// Measured on the audio thread over EVERY block, so unlike anything derived from
    /// `copyLatestOutputSamples` it has no duty-cycle gap between UI ticks. And unlike
    /// `masterLevel` it is a peak: `masterLevel` is `vDSP_rmsqv × 3.0` clamped to 1.0, a
    /// meter-ballistics value with a contract to `AutoMixChain.updateLUFS` — reading it as
    /// dBFS pins anything above ≈ −6.5 dBFS at "0.0" (#347 review).
    var masterOutputTruePeakDb: Float = EchoelMeter.floorDb
    var masterOutputLUFSIntegrated: Float = EchoelLoudnessMeter.floorLUFS
    var masterOutputLRA: Float = 0

    /// Live output sample rate (Hz), set from the master tap format in
    /// `prepareGraph`. 48 kHz until the graph is built. Used by the FFT visual to
    /// map magnitude bins to frequency bands.
    var sampleRate: Double = 48000

    @ObservationIgnored nonisolated(unsafe) private let _rawMeterL = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    @ObservationIgnored nonisolated(unsafe) private let _rawMeterR = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    /// Master metering published values (dB / LUFS). Written ONLY from the tap
    /// thread, read ONLY from the poll timer — single-Float cross-thread handoff,
    /// matching the `_rawMeter*` pattern (no shared multi-word state).
    @ObservationIgnored nonisolated(unsafe) private let _peakDb = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    @ObservationIgnored nonisolated(unsafe) private let _truePeakDb = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    @ObservationIgnored nonisolated(unsafe) private let _lufs = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    @ObservationIgnored nonisolated(unsafe) private let _lufsS = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    @ObservationIgnored nonisolated(unsafe) private let _tpMax = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    @ObservationIgnored nonisolated(unsafe) private let _lufsI = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    @ObservationIgnored nonisolated(unsafe) private let _lra = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    /// MainActor sets true to request a loudness/peak reset; the tap performs the
    /// reset on its own thread (meters are tap-confined) and clears the flag.
    @ObservationIgnored nonisolated(unsafe) private let _resetMeters = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
    /// Gate for the EXPENSIVE mastering meters (peak/true-peak oversample + EBU
    /// R128 K-weighting/gating). Only `MasterLoudnessGrid` reads their outputs, and
    /// it lives in a collapsed-by-default panel — yet the tap ran them on EVERY
    /// buffer, forever, burning CPU during play (a load contributor to the
    /// occasional "Knistern"). The cheap RMS level + FFT ring always run (the
    /// SpectralDonut + immersive visual need them); the heavy meters run ONLY while
    /// a mastering readout is on screen. Set true `.onAppear`, false `.onDisappear`;
    /// the 100 ms poll makes the readout live within a frame of opening.
    @ObservationIgnored nonisolated(unsafe) private let _detailedMetering = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
    @ObservationIgnored nonisolated(unsafe) private var meterPollTimer: Timer?

    // MARK: - Audio-path timing instrument (#193 "es knistert")

    /// CoreAudio's own `hostTime` for the previous master-tap delivery, in mach ticks.
    /// `0` = no previous delivery (first callback after an install), which the tap treats
    /// as "nothing to compare against" rather than as a giant gap.
    ///
    /// It is the RENDER-CYCLE stamp out of `AVAudioTime`, not `mach_absolute_time()` read
    /// inside the block. The difference is the whole point: the latter would also include
    /// however long the tap's own delivery path was descheduled, and this instrument
    /// exists to tell starvation of the audio path apart from everything else.
    @ObservationIgnored nonisolated(unsafe) private let _lastTapTicks = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)
    /// Frame position of the previous delivery. How far it advanced versus how far the
    /// PREVIOUS buffer said it should is the second, independent channel: forward drift =
    /// audio that was never rendered, backwards = the stream restarted. It is NOT true
    /// that any drift means a pause — that claim was the reason a dropped render cycle
    /// spent one commit being filed as "ignored". `Int64.min` = unknown/unavailable.
    @ObservationIgnored nonisolated(unsafe) private let _lastTapSampleTime = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
    /// Frames the PREVIOUS delivery carried. The interval between two deliveries covers
    /// that buffer's worth of audio, so it is the number the interval is measured
    /// against — not the current buffer's length, which may differ (`installTap`'s size
    /// is a hint, and iOS changes it across route/format transitions).
    @ObservationIgnored nonisolated(unsafe) private let _tapFrames = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    /// Intervals actually classified this window. THE liveness signal: `0` means nothing
    /// was measured — the timebase lookup failed, host time was never valid, or the tap
    /// stopped — and a window that measured nothing must never be reported as "clean".
    @ObservationIgnored nonisolated(unsafe) private let _measuredCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    /// How many intervals ran late enough to count as a starved audio path.
    @ObservationIgnored nonisolated(unsafe) private let _gapCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    /// Worst such interval, in render quanta — the number that says whether it was a
    /// hiccup or a stall.
    @ObservationIgnored nonisolated(unsafe) private let _gapWorst = UnsafeMutablePointer<Double>.allocate(capacity: 1)
    /// Intervals discarded as pause/restart artefacts rather than counted as starvation.
    @ObservationIgnored nonisolated(unsafe) private let _discCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    /// Worst FRAME drift seen alongside a late interval, in render quanta. Reported next
    /// to the lateness because the two together say something neither says alone: drift
    /// with lateness = audio was skipped; lateness with ZERO drift = the graph was not
    /// rendering at all (a short pause), which is a different fault with the same symptom.
    /// Which of the two the founder's device actually produces is the open question this
    /// instrument exists to settle, so it must not be reduced to one number here.
    @ObservationIgnored nonisolated(unsafe) private let _driftWorst = UnsafeMutablePointer<Double>.allocate(capacity: 1)
    /// The granted IO buffer DURATION in seconds, read by the tap. Seconds and not
    /// frames: the tap converts using the rate of the buffer it was actually handed, so a
    /// mid-session hardware rate change cannot leave a frame count denominated in the old
    /// rate. A CELL and not a captured copy so a route change can update it without
    /// re-installing the tap.
    @ObservationIgnored nonisolated(unsafe) private let _quantumSeconds = UnsafeMutablePointer<Double>.allocate(capacity: 1)
    /// `max(lateness, drift)` of the worst interval so far this window. Only the ranking
    /// key — the two reported numbers are that interval's OWN pair, so the log describes
    /// one real event rather than composing one out of two.
    @ObservationIgnored nonisolated(unsafe) private let _worstScore = UnsafeMutablePointer<Double>.allocate(capacity: 1)
    /// mach ticks → seconds, resolved ONCE on the main actor (`mach_timebase_info` is a
    /// syscall-ish lookup and has no business on the audio path). Captured by value into
    /// the tap closure so the callback does nothing but multiply.
    @ObservationIgnored nonisolated(unsafe) private var tickToSeconds: Double = 0

    /// When the current measurement window opened, on the MONOTONIC uptime clock, so the
    /// reported rate has a denominator instead of being a bare count. `0` = not yet open.
    @ObservationIgnored private var timingWindowStart: TimeInterval = 0
    /// The first window always writes a line — see `pollAudioTiming` for why an absent
    /// line would be an ambiguous null result.
    @ObservationIgnored private var timingReportedOnce = false
    /// The render quantum the tap is measuring against, in seconds. The SAME value must
    /// reach the log line, or the printed millisecond figure describes a different buffer
    /// than the multiplier next to it.
    @ObservationIgnored private var timingQuantumSeconds: Double = 0

    /// Lock-free mono ring of the most recent master-output samples, for the
    /// immersive FFT visual. The meter tap `memcpy`s the live mix into it
    /// (allocation-free, audio-safe — no DSP on the tap thread); a UI reader pulls
    /// the latest window on the MAIN thread and runs the FFT there. A torn read can
    /// only ripple one visual frame, never corrupt audio or crash. Size = a few
    /// FFT windows so the reader always has a full 1024-pt frame available.
    nonisolated static let outputRingSize = 4096
    @ObservationIgnored nonisolated(unsafe) private let _outputRing =
        UnsafeMutablePointer<Float>.allocate(capacity: AudioEngine.outputRingSize)
    /// Total samples ever written (monotonic). The tap writes; the UI reads. A
    /// single-word Int handoff, same discipline as the `_rawMeter*` floats.
    @ObservationIgnored nonisolated(unsafe) private let _outputRingCount =
        UnsafeMutablePointer<Int>.allocate(capacity: 1)

    /// Master meters. Confined to the tap thread (only ever touched inside the
    /// master tap callback); cross-thread output flows via `_peakDb`/`_lufs`.
    @ObservationIgnored nonisolated(unsafe) private let masterMeter = EchoelMeter()
    /// Re-created in `prepareGraph` with the real tap sample rate so the BS.1770
    /// window lengths / K-weighting match the hardware rate.
    @ObservationIgnored nonisolated(unsafe) private var loudnessMeter = EchoelLoudnessMeter()

    /// Retroactive capture — always-recording ring buffer + on-demand disk writer.
    let retroCapture = RetroCapture()

    /// Microphone-over-beats multitrack recorder (EchoelMix REC).
    let multiTrackRecorder = MultiTrackRecorder()

    /// Master mastering chain — EQ + compression + limiting + auto-LUFS.
    let autoMixChain = AutoMixChain()

    /// LUFS-normalized mastering + export (WAV/AAC) for completed sessions.
    let singleExport = SingleExport()

    @ObservationIgnored private let masterEngine = AVAudioEngine()
    @ObservationIgnored private let masterMixer = AVAudioMixerNode()
    @ObservationIgnored private let masterPlayerNode = AVAudioPlayerNode()

    var masterVolume: Float = 0.85 {
        didSet { masterMixer.outputVolume = masterVolume }
    }

    // MARK: - Live input monitoring + FeedbackGuard (opt-in, DEFAULT OFF)
    // Routes the mic through the main output so you can sing/play over the beat, with
    // a FeedbackGuard auto-duck that pulls the monitor down the instant a runaway
    // (rising level over a ceiling) starts — the classic acoustic-feedback signature.
    // Use headphones/an interface to remove the acoustic loop entirely. Nothing here
    // runs until the user explicitly enables it, so it can never affect normal use.
    @ObservationIgnored private let monitorMixer = AVAudioMixerNode()
    @ObservationIgnored private var monitorAttached = false
    /// Whether the mic is being monitored through the main output.
    public private(set) var isInputMonitoring = false
    /// True while FeedbackGuard is actively ducking (drives the UI indicator).
    public private(set) var feedbackGuardActive = false
    /// Monitor level 0…1 — conservative by default; feedback risk rises with gain.
    var inputMonitorGain: Float = 0.6 {
        didSet {
            let g = min(max(inputMonitorGain, 0), 1)
            if isInputMonitoring && !feedbackGuardActive { monitorMixer.outputVolume = g }
        }
    }
    /// #829 — Megaphone Mode (founder: "On Device mic directly Verstärkung mit
    /// intelligenter Rückkopplungsunterdrückung"). Amplifies the monitored mic by
    /// `megaphoneBoostDB` through the EXISTING `notchEQ`'s `globalGain` (−96…+24 dB) —
    /// a parameter on a node already in the monitor chain, so no graph change, no new
    /// presentation slot, and the MUSIC path is untouched (it never passes the notch).
    /// Deliberately NOT persisted, like monitoring itself: amplification through the
    /// speaker must never surprise on relaunch.
    /// NEEDS-FOUNDER-VERIFY: Megaphone am Gerät — Monitoring auf dem Lautsprecher,
    /// Schalter an: Stimme deutlich lauter, beginnendes Aufheulen wird binnen ~1 s
    /// weggeduckt und kommt nach dem Verstummen zurück; Schalter aus = alter Pegel.
    /// (Lautsprecher-Rückkopplung existiert in keinem Simulator.)
    var megaphoneMode: Bool = false {
        didSet {
            guard isInputMonitoring else { return }
            notchEQ.globalGain = megaphoneMode ? Self.megaphoneBoostDB : 0
            logMonitorOutcome("megaphone \(megaphoneMode ? "on" : "off") "
                              + "(boost \(Self.megaphoneBoostDB) dB) — #829", level: .info)
        }
    }
    /// ONE definition each (#416). THE AUTHORITY LAW: while boosted, the duck's depth
    /// is `FeedbackGuard.defaultMaxReductionDB + megaphoneBoostDB` — the guard must
    /// always be able to undo MORE than the boost, or an amplified howl saturates at
    /// unity gain and never comes down. The lower ceiling makes it react EARLIER
    /// while boosted; the notch half needs no change (it targets frequency, not level).
    nonisolated static let megaphoneBoostDB: Float = 12
    nonisolated static let megaphoneDuckCeiling: Float = 0.70
    /// Output-RMS window (MainActor) that feeds FeedbackGuard while monitoring.
    @ObservationIgnored private var monitorLevelHistory: [Float] = []
    @ObservationIgnored private var monitorPollTick = 0
    // #595: the NOTCH half of FeedbackGuard (the duck above is the LEVEL half; the
    // FeedbackGuard.swift header records which halves are wired). One parametric EQ
    // band sits in the MONITOR path only (input → notchEQ → monitorMixer) — the music
    // never passes through it, exactly the duck's scoping. The spectrum comes from a
    // tap on the input node pushing into `MonitorTapWindow` (the 10.76.48 lock-queue
    // shape, zero actor hops in the tap); the EXISTING ~15 Hz guard tick copies the
    // window out and runs the FFT on the MainActor — no DSP in the tap, none in render.
    @ObservationIgnored private let notchEQ = AVAudioUnitEQ(numberOfBands: 1)
    @ObservationIgnored private var notchAttached = false
    @ObservationIgnored private let monitorTapWindow = MonitorTapWindow(size: 2048)
    @ObservationIgnored private var monitorTapInstalled = false
    @ObservationIgnored private var monitorTapSampleRate: Double = 0
    /// #826 — captured beside the rate at tap install, for the re-arm gate's second
    /// half: a route switch that changes the CHANNEL COUNT without changing the rate
    /// (mono BT mic → stereo USB interface at 48 kHz both) used to re-arm nothing and
    /// left the monitor chain connected at the old count (#625b's registered gap).
    @ObservationIgnored private var monitorTapChannelCount: AVAudioChannelCount = 0
    /// Lazy so the FFT setup is only paid once monitoring is actually used. Under
    /// extreme memory pressure `EchoelRealFFT` can fall back to a smaller size — the
    /// guard tick checks `size` against the window and simply skips the notch then
    /// (the duck still defends; a wrong-size FFT would misread every bin).
    @ObservationIgnored private lazy var monitorSpectrumFFT = EchoelRealFFT(size: 2048)
    @ObservationIgnored private var monitorSpectrumBuffer = [Float](repeating: 0, count: 2048)
    /// Current slewed notch gain in dB (≤ 0; 0 = released). Written only by the guard
    /// tick via `FeedbackGuard.slewedNotchGainDB` — never stepped.
    @ObservationIgnored private var notchGainDB: Float = 0
    /// Ticks the notch stays engaged after the LAST ringing detection (~2 s at ~15 Hz).
    /// Once the notch bites, the ring decays and the DETECTOR loses it — without a
    /// hold the notch would release, the howl would return, and the loop would audibly
    /// oscillate. The hold keeps the notch parked on the same frequency through that gap.
    @ObservationIgnored private var notchHoldTicks = 0
    /// ~2 s at the ~15 Hz guard cadence (60 Hz poll gated %4 — see `monitorPollTick`).
    private static let notchHoldTickCount = 30
    // VL3 (#599): in-key pitch correction ("tune to key") on the MONITOR path only —
    // the optional autotune-with-character the founder asked for. Chain when enabled:
    // input → notchEQ → voiceTunePitch → monitorMixer (disabled: the unchanged #595
    // shape). `AVAudioUnitTimePitch` is a GRAPH node — no render code here. The
    // EXISTING ~15 Hz guard tick reads the EXISTING `MonitorTapWindow` (`copyLatest`
    // COPIES — the notch FFT and YIN share one window without stealing from each
    // other), runs `PitchTracker` (YIN) + `VoicePitchCorrector` (pure, tested), and
    // writes the smoothed correction in CENTS onto the node. Key + Kammerton are
    // re-read ~1 Hz from the SAME stored values the studio writes
    // (`StudioDefaultKeys.rootIndex`/`scale` + `SessionContext.a4StorageKey` — #416,
    // one definition; a key change in the studio reaches the voice within a second).
    /// What the monitor chain's OWN graph nodes report as their processing delay, in ms,
    /// in chain order and only for stages actually connected.
    ///
    /// #666, and it exists to pass the gate #654 wrote rather than to display anything.
    /// `auAudioUnit.latency` had zero precedent in this repo, and #654 refused to print a
    /// figure from it because an uninitialised node reports 0 and "a fabricated 0 is worse
    /// than an honest absence". This reads it into the LOG only, labelled per node, so the
    /// next founder log settles what the AU actually reports. Nothing on screen consumes it.
    ///
    /// ⚠️ A 0 here means "this AU reports no latency", NOT "this stage adds none".
    /// `AVAudioUnitTimePitch` is a phase vocoder and certainly has algorithmic delay; if it
    /// answers 0 the value is uninformative, which is itself the finding this slice is for.
    /// Do NOT add these into `floor=` and do NOT show them to a user until one real log has
    /// been read (#654's gate, still closed until then).
    ///
    /// MainActor: `auAudioUnit` is an ObjC property read — never call this from a render
    /// block. It is called from the two graph-configuration paths only.
    var monitorInsertLatencyMilliseconds: [(String, Double)] {
        guard isInputMonitoring else { return [] }
        var stages: [(String, Double)] = []
        if notchAttached { stages.append(("notch", notchEQ.auAudioUnit.latency * 1000)) }
        if voiceTuneEnabled, voiceTuneAttached {
            stages.append(("tune", voiceTunePitch.auAudioUnit.latency * 1000))
        }
        return stages
    }

    @ObservationIgnored private let voiceTunePitch = AVAudioUnitTimePitch()
    @ObservationIgnored private var voiceTuneAttached = false
    @ObservationIgnored private var voiceTuneCorrector = VoicePitchCorrector()
    @ObservationIgnored private var voiceTuneBuffer = [Float](repeating: 0, count: 2048)
    @ObservationIgnored private var voiceTuneKeyRefreshTick = 0
    /// Whether the in-key correction stage sits in the monitor chain. Observable so
    /// the input sheet's toggle reflects it; written ONLY via `setVoiceTune(_:)`
    /// (the setter owns the graph rewire). Default OFF — the founder's "optional".
    private(set) var voiceTuneEnabled = false
    /// 0…1 correction amount (`VoicePitchCorrector.strength`). Control-plane; the
    /// tick hands it to the corrector, so a mid-note edit takes effect immediately.
    var voiceTuneStrength: Float = 1
    /// 0…1 retune character — 1 = the classic hard snap, 0 = gentle natural drift
    /// (`VoicePitchCorrector.retuneSpeed`; the time constant lives THERE, #416).
    var voiceTuneRetune: Float = 0.8

    let microphoneManager: MicrophoneManager
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    /// True once the audio session is configured and the master graph is built.
    /// Guards `prepareGraph()` so it runs exactly once, post-UI.
    @ObservationIgnored private var graphPrepared = false

    convenience init() {
        self.init(microphoneManager: MicrophoneManager())
    }

    init(microphoneManager: MicrophoneManager) {
        self.microphoneManager = microphoneManager
        _rawMeterL.initialize(to: 0)
        _rawMeterR.initialize(to: 0)
        _peakDb.initialize(to: EchoelMeter.floorDb)
        _truePeakDb.initialize(to: EchoelMeter.floorDb)
        _lufs.initialize(to: EchoelLoudnessMeter.floorLUFS)
        _lufsS.initialize(to: EchoelLoudnessMeter.floorLUFS)
        _tpMax.initialize(to: EchoelMeter.floorDb)
        _lufsI.initialize(to: EchoelLoudnessMeter.floorLUFS)
        _lra.initialize(to: 0)
        _lastTapTicks.initialize(to: 0)
        _lastTapSampleTime.initialize(to: Int64.min)
        _tapFrames.initialize(to: 0)
        _measuredCount.initialize(to: 0)
        _gapCount.initialize(to: 0)
        _gapWorst.initialize(to: 0)
        _discCount.initialize(to: 0)
        _driftWorst.initialize(to: 0)
        _quantumSeconds.initialize(to: Double(AudioConfiguration.currentBufferSize) / AudioConfiguration.preferredSampleRate)
        _worstScore.initialize(to: 0)
        // Resolve the mach timebase once, here, so the audio path never does. On Apple
        // silicon numer/denom are not 1/1, so the ratio is not optional.
        var timebase = mach_timebase_info_data_t()
        if mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 {
            tickToSeconds = Double(timebase.numer) / Double(timebase.denom) * 1e-9
        }
        _resetMeters.initialize(to: false)
        _detailedMetering.initialize(to: false)
        _outputRing.initialize(repeating: 0, count: AudioEngine.outputRingSize)
        _outputRingCount.initialize(to: 0)

        // Interruption / route-change handlers are cheap closure storage with no
        // audio I/O — safe to wire at init.
        AudioConfiguration.onInterruptionBegan = { [weak self] in
            self?.masterEngine.pause()
            self?.isRunning = false
            // Remember WHY we stopped. Without this the next line is a trap: the
            // configuration-change watchdog only self-heals a running-or-degraded engine,
            // so setting `isRunning = false` here used to DISARM the one mechanism that
            // could have rescued an interruption whose `.ended` notification never
            // arrives (or arrives without `.shouldResume`). See `shouldSelfHeal`.
            self?.wasInterrupted = true
            log.audio("Audio interrupted — pausing engine")
        }
        AudioConfiguration.onInterruptionResume = { [weak self] in
            // The same law `shouldSelfHeal` states, applied to the OTHER resume path.
            // Review caught this: the predicate guarded the watchdog and left this
            // closure — which also restarts the engine — with no intent check at all.
            // A rule that holds on one of two paths is not a rule.
            guard self?.intentionallyStopped == false else {
                log.audio("Interruption ended but the engine was stopped deliberately — staying stopped")
                return
            }
            log.audio("Audio interruption ended — resuming engine")
            do {
                self?.armTimingInstrument()
                try self?.masterEngine.start()
                self?.isRunning = true
                self?.wasInterrupted = false
            } catch {
                // Leave `wasInterrupted` SET: the resume failed, so the watchdog and the
                // scene-phase resume must both still consider this engine rescuable.
                log.audio("Failed to resume master engine: \(error)", level: .error)
            }
        }
        AudioConfiguration.onMediaServicesReset = { [weak self] in
            // Route through the SAME de-bounced machinery route-loss uses, not through a
            // bare engine start. Three things that only `recoverEngine` → `start()` does
            // matter here: the 300 ms settle (the daemon is still coming up), the capped
            // retry with a `degraded` surface if it never does, and — the reason this
            // hook exists at all — the full start path, which reinstalls RetroCapture's
            // tap and re-prepares the recorder. A media-services reset takes taps with
            // it; resuming without redoing them is silent data loss, not silence.
            self?.isRunning = false
            // …and immediately raise the flag that says "stopped, NOT on purpose, still
            // rescuable". Without it this closure walks straight into the trap documented
            // 30 lines above: `shouldSelfHeal` reads `isRunning || degraded ||
            // wasInterrupted`, so clearing `isRunning` and setting nothing leaves all
            // three false. If `recoverEngine` then declines — already recovering, or the
            // attempt cap — NOTHING can rescue the engine: the config-change watchdog
            // stands down and so does the foreground resume. Silent until relaunch, which
            // is the exact bug `wasInterrupted` was invented for one commit ago. The name
            // is a stretch for a dead daemon; the MEANING is precisely right.
            self?.wasInterrupted = true
            // A media-services reset is a NEW fault, not the continuation of a route-flap
            // streak. The cap is shared and only clears on a successful start, so three
            // earlier failed route recoveries (a headphone plug flapping in a pocket)
            // would otherwise make `recoverEngine` refuse this outright — surfacing
            // `degraded` without ever attempting a start.
            self?.recoveryAttempts = 0
            self?.recoverEngine(reason: "media services reset")
        }
        AudioConfiguration.onRouteDeviceLost = { [weak self] in
            guard let self else { return }
            self.masterEngine.pause()
            self.isRunning = false
            // HIG: unplugging headphones must PAUSE playback, not continue on the
            // loudspeaker. The engine restart below only re-wires the graph onto the
            // new route (silent while the transport is stopped); the app layer stops
            // the transport via this hook — the Audio layer holds no Sequencer refs.
            self.onOutputDeviceLost?()
            log.audio("Audio route lost — restarting on new output...")
            self.recoverEngine(reason: "route lost")
        }

        // IMPORTANT: audio-session activation and AVAudioEngine graph construction
        // are deferred to prepareGraph() (run post-UI from the startup task). Doing
        // that work here — inside App.init(), before the first frame — risked an
        // instant launch crash on device: AVAudioEngine graph errors surface as
        // Objective-C exceptions that Swift try/catch cannot intercept. Keep init cheap.
        log.audio("AudioEngine initialized (graph deferred to prepareGraph)")
    }

    /// Configure the audio session and build the master engine graph. Idempotent.
    /// Must run before attaching source nodes or calling `start()`. Called post-UI
    /// from the app's startup task so no AVAudioSession/AVAudioEngine work happens
    /// before the UI is on screen.
    func prepareGraph() {
        guard !graphPrepared else { return }
        graphPrepared = true
        do {
            try AudioConfiguration.configureAudioSession()
            AudioConfiguration.registerInterruptionHandlers()
            log.audio(AudioConfiguration.latencyStats())
            // #653 — the same numbers, in the sink the founder can actually export.
            // `latencyStats()` above is the human-readable report and has gone to
            // `os_log` plus a write-only in-memory ring since it was written; neither
            // reaches `echoel_diag.log`. Keeping BOTH is deliberate: the report carries
            // the target and the ✅/⚠️/❌ verdict for a console session, the breadcrumb
            // carries the comparable one-liner for a shared log.
            // #666: `insertMilliseconds` has NO default (#431/#440/#443 — a defaulted
            // argument no call site writes appears in no diff). Empty here is a statement:
            // this line is about the session, before any monitor node exists.
            AudioConfiguration.latencyBreadcrumb(reason: "start", tuneStage: nil,
                                                 insertMilliseconds: [])
        } catch {
            log.audio("Failed to configure audio session: \(error)", level: .warning)
        }
        AudioConfiguration.setAudioThreadPriority()
        setupMasterEngine()
        registerConfigurationChangeWatchdog()
        log.audio("AudioEngine graph prepared — master output wired to hardware")
    }

    /// Should a stopped engine be restarted automatically? Pure, so the one rule that
    /// decides between "rescue the performance" and "resurrect a silent engine in the
    /// background" is testable without an audio device.
    ///
    /// The asymmetry is the whole point and it is easy to get wrong in either direction:
    /// an INTENTIONAL stop must never heal — that was review finding F2, a stale
    /// `degraded` re-opening the gate while backgrounded. An INTERRUPTED one must always
    /// heal, because the interruption handler itself sets `isRunning = false`, which used
    /// to make this predicate false and disarm the only rescue path the app has when
    /// iOS delivers no usable `.ended` notification.
    nonisolated static func shouldSelfHeal(isRunning: Bool,
                                           degraded: Bool,
                                           wasInterrupted: Bool,
                                           intentionallyStopped: Bool) -> Bool {
        // A deliberate stop wins over every other reason, including an interruption that
        // happened first — the user's last explicit intent is the authority.
        if intentionallyStopped { return false }
        return isRunning || degraded || wasInterrupted
    }

    /// Should coming back to the foreground restart the engine? The scene-phase twin of
    /// `shouldSelfHeal`, and it exists for the same reason: review found that the gate in
    /// `EchoelmusicApp` could not honour the "a deliberate stop wins" law, because
    /// `intentionallyStopped` is private to this type. A rule the enforcing site cannot
    /// read is a comment, not a rule — so the rule moves to where the state lives.
    nonisolated static func shouldResumeOnForeground(cameFromBackground: Bool,
                                                     wasBackgrounded: Bool,
                                                     wasInterrupted: Bool,
                                                     intentionallyStopped: Bool) -> Bool {
        if intentionallyStopped { return false }
        return cameFromBackground || wasBackgrounded || wasInterrupted
    }

    /// The view-facing form: the app knows the two scene-phase facts, this type knows the
    /// other two. Keeps `intentionallyStopped` private without keeping it unenforceable.
    func shouldResumeOnForeground(cameFromBackground: Bool, wasBackgrounded: Bool) -> Bool {
        // ⛔ `resumeSuppressed`, NOT `intentionallyStopped` — this one substitution is the
        // whole bug fix. Passing `intentionallyStopped` made the 2.5.4 idle stop refuse to
        // come back, so the app returned to the foreground with a dead engine and every
        // later Start produced a running transport and total silence (device log 2475).
        //
        // A SECOND effect rides along, and it is named here so a later audit does not read
        // it as an unexplained regression. `start()` is what clears the stop reason, and it
        // has only two callers (app startup, and this foreground resume) — the Start button
        // is NOT one of them, which is exactly why the founder's log shows notes without
        // audio. So before the fix, an idle stop disarmed self-healing PERMANENTLY for the
        // rest of the process: a later route or configuration change could not recover the
        // engine even in the foreground. Now the foreground return runs `start()` and
        // re-arms the watchdog. The predicate is bit-identical; the reachable state is not.
        Self.shouldResumeOnForeground(cameFromBackground: cameFromBackground,
                                      wasBackgrounded: wasBackgrounded,
                                      wasInterrupted: wasInterrupted,
                                      intentionallyStopped: resumeSuppressed)
    }

    /// Self-healing watchdog: AVAudioEngine posts `.AVAudioEngineConfigurationChange`
    /// when the OS rebuilds the I/O graph (AirPods/BT connect or disconnect, hardware
    /// sample-rate switch, media-services rebuild). Without observing it the engine
    /// frequently stops and stays SILENT until relaunch. The notification can arrive
    /// on any thread, so hop to the MainActor and route through the de-bounced
    /// `recoverEngine`. Registered once (prepareGraph is idempotent).
    private func registerConfigurationChangeWatchdog() {
        guard configChangeObserver == nil else { return }
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: masterEngine,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // #653 — an engine reconfigure is the only event that changes the granted
                // buffer and the hardware latencies without any user action, and it is
                // exactly the moment a founder plugs in an interface or connects a Bluetooth
                // headset. Without a line here the log would carry figures measured on a
                // configuration that is no longer live.
                //
                // ⛔ #654 CORRECTED THE REASON STRING. It said "route change", but this
                // observer's own doc above lists THREE causes — BT connect/disconnect, a
                // hardware sample-rate switch, and a media-services rebuild — and the
                // notification does not say which. Logging the rebuild (the one that
                // invalidates every tap and is the hardest failure to diagnose) as a route
                // change was the one lie that string could tell.
                //
                // ⛔ #657 MOVED IT HERE, OUT OF THE `isRunning` BRANCH, and the defect it
                // fixes is the one the first sentence above CLAIMS to prevent. Gated on a
                // running engine, a headset connected while the engine is STOPPED took the
                // `recoverEngine` path and emitted nothing — and `prepareGraph` is once-only
                // (`guard !graphPrepared`), so the log's ONLY latency line would describe a
                // configuration that is genuinely no longer live. Exactly the failure the
                // comment promised to close, left open by where the call sat. The handler is
                // entered for every configuration change; only the BRANCH depends on
                // `isRunning`, so one hoist covers both.
                //
                // ⚠️ #654 also retracted "route changes are rare, so this cannot flood the
                // file" — an assertion, not a measurement, and it ignored the app's OWN
                // category mutations, which post configuration changes too. Connecting a
                // headset while monitoring runs takes the running branch, then
                // `rearmInputMonitoring` toggles the category twice, each posting another
                // change: realistically 3–6 lines per physical connect. It CONVERGES (the
                // rearm re-captures the tap rate, so the follow-ups find rate equality) and
                // ~120 bytes a line is nothing for the file — the honest cost is that the
                // burst interleaves with the `monitor:` lines #650 put there to diagnose
                // monitoring failure. Signal, not size. Hoisting does not change that count:
                // the stopped-engine case is the one that emitted ZERO.
                // #666: a route change is exactly when a stage's latency could move, and the
                // gatherer returns [] on its own when monitoring is off — so this ASKS rather
                // than assuming, unlike `tuneStage`, which stays nil because this line is not
                // ABOUT the monitor chain.
                // ⛔ #667: KEEP `reason:` ON THIS LINE. #666 wrapped the call after the open
                // paren, and two guards in `TheMeasuredLatencyReachesTheDiagLogTests` anchor on
                // the substring `latencyBreadcrumb(reason: "engine reconfigured"` — which the
                // wrap deleted. The compiler cannot see that; it was a silent runtime red on a
                // correct tree, in the same commit that also broke three call sites the
                // compiler COULD see. #656's law again: reshaping an anchored string is the
                // same event as removing a surface.
                AudioConfiguration.latencyBreadcrumb(reason: "engine reconfigured",
                                                     tuneStage: nil,
                                                     insertMilliseconds: self.monitorInsertLatencyMilliseconds)
                // A healthy engine that simply re-mapped its output needs no restart —
                // BUT the route may have switched the hardware sample rate (e.g. the
                // rPPG camera activating mid-session drops it to 44.1 kHz). Re-install
                // the RetroCapture tap so its capture sample rate tracks the NEW format;
                // otherwise a retroactive capture/export would be pitch-shifted
                // ("viel höher"). install() is idempotent (removes the old tap first).
                //
                // ⛔ #630: THIS COMMENT OVER-CLAIMED FOR AS LONG AS IT EXISTED. Re-installing
                // updated the rate for FUTURE frames and left up to 30 s of ALREADY CAPTURED
                // history in the ring — which every pre-roll reader then wrote out under the
                // NEW rate. So the very pitch-shift named here survived this fix, moved from
                // the live tap into the pre-roll. `install(on:)` now records a rate boundary
                // and the pre-roll readers stop at it; the sentence above is true because
                // #630 made it true, not because re-installing was ever enough.
                //
                // ⚠️ Closed for the PRE-ROLL only. A rate change during an ACTIVE take still
                // leaves `RetroCapture.activeFile` open at the old rate — see the registered
                // note on `rateBoundaryFrame` (#630b). Do not read this retraction as "the
                // rate hazard is handled".
                if self.masterEngine.isRunning {
                    self.recoveryAttempts = 0
                    self.retroCapture.install(on: self.masterEngine)
                    // The route changed under a surviving tap: the granted IO buffer may
                    // be a different size now, and the render may have gapped across the
                    // switch. Re-read the one, forget the baseline for the other (#193).
                    self.refreshRenderQuantum(fallbackSampleRate: self.sampleRate)
                    self.armTimingInstrument()
                    // #612 (mic-sweep CRITICAL, the rate half): `monitorTapSampleRate` is
                    // captured ONCE at tap install; after a 44.1↔48 route switch the
                    // notch maths sat up to ~9 % off and (since #599) YIN divided by the
                    // stale rate — Tune-to-key then snaps to WRONG notes until monitoring
                    // is recycled. ⛔ #625b: this said "the 'route-change re-arm' the
                    // tap-install comment names as the honest fix" — #624 removed that
                    // naming from the tap-install comment (the phrase survives only inside
                    // its own retraction there), so the pointer outlived what it pointed
                    // at. THIS call is the re-arm; nothing else has to name it. `newRate > 0` keeps a transient
                    // input-less moment mid-switch from tearing monitoring down.
                    // #826 — the gate tests BOTH halves of the format now. Rate was #612;
                    // channel count was the #625b registered gap: mono BT mic → stereo
                    // USB interface at the same 48 kHz changed nothing this gate read,
                    // so the chain stayed connected at the old count. Same guard shape
                    // (`> 0` keeps the transient input-less moment from tearing down).
                    let newFormat = self.masterEngine.inputNode.inputFormat(forBus: 0)
                    let newRate = newFormat.sampleRate
                    if self.isInputMonitoring, newRate > 0, newFormat.channelCount > 0,
                       newRate != self.monitorTapSampleRate
                        || newFormat.channelCount != self.monitorTapChannelCount {
                        self.rearmInputMonitoring(reason: newRate != self.monitorTapSampleRate
                            ? "route sample-rate change"
                            : "route channel-count change")
                    }
                    return
                }
                // Engine actually stopped: recover only if we were meant to be running.
                guard Self.shouldSelfHeal(isRunning: self.isRunning,
                                          degraded: self.degraded,
                                          wasInterrupted: self.wasInterrupted,
                                          intentionallyStopped: self.intentionallyStopped)
                else { return }
                self.recoverEngine(reason: "engine configuration changed")
            }
        }
    }

    /// De-bounced, capped automatic restart used by route-loss and configuration
    /// changes. Control plane only — never touches the render block. On success the
    /// attempt counter resets and `degraded` clears; after `maxRecoveryAttempts`
    /// consecutive failures it surfaces `degraded` so the UI can offer a manual retry.
    private func recoverEngine(reason: String) {
        // An intentionally stopped engine is not "broken" — never self-heal it
        // (only an explicit start() re-arms recovery).
        guard !intentionallyStopped else { return }
        guard !isRecovering else { return }
        guard recoveryAttempts < Self.maxRecoveryAttempts else {
            degraded = true
            lastAudioError = "Audio stopped (\(reason)) and auto-recovery gave up."
            log.audio("Self-heal: giving up after \(recoveryAttempts) attempts (\(reason))", level: .error)
            return
        }
        isRecovering = true
        recoveryAttempts += 1
        let attempt = recoveryAttempts
        log.audio("Self-heal: recovery attempt \(attempt) (\(reason))")
        // Small settle delay lets the OS finish the route/format transition before
        // we restart, avoiding a restart onto a half-built graph. MainActor Task so
        // the restart stays on the control plane (never the render thread).
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }
            self.isRecovering = false
            // Re-check after the settle: a deliberate stop() (backgrounding) may
            // have landed during the 300 ms — restarting now would resurrect a
            // silent engine in the background (review F1).
            guard !self.intentionallyStopped else { return }
            self.start()
            if self.masterEngine.isRunning {
                self.recoveryAttempts = 0
                self.degraded = false
                self.lastAudioError = nil
                log.audio("Self-heal: engine recovered (\(reason))")
            } else {
                // start() failed (it sets degraded/lastAudioError); try again until cap.
                self.recoverEngine(reason: reason)
            }
        }
    }

    private func setupMasterEngine() {
        masterEngine.attach(masterMixer)
        masterEngine.attach(masterPlayerNode)

        let outputFormat = masterEngine.outputNode.outputFormat(forBus: 0)
        let processingFormat: AVAudioFormat
        if outputFormat.sampleRate > 0 && outputFormat.channelCount > 0,
           let customFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: outputFormat.sampleRate,
                channels: min(outputFormat.channelCount, 2),
                interleaved: false
           ) {
            processingFormat = customFormat
        } else if let fallback48 = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) {
            log.audio("Output format invalid (\(outputFormat.sampleRate)Hz, \(outputFormat.channelCount)ch) — using 48kHz stereo fallback", level: .warning)
            processingFormat = fallback48
        } else if let fallback44 = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) {
            log.audio("All 48kHz formats failed — using 44.1kHz stereo fallback", level: .warning)
            processingFormat = fallback44
        } else {
            log.audio("CRITICAL: Cannot create any audio format — skipping engine setup", level: .error)
            return
        }

        masterEngine.connect(masterPlayerNode, to: masterMixer, format: processingFormat)
        // Insert AutoMixChain: masterMixer → EQ → gainNode → mainMixerNode
        autoMixChain.insert(
            into: masterEngine,
            from: masterMixer,
            to: masterEngine.mainMixerNode,
            format: processingFormat
        )
        masterMixer.outputVolume = masterVolume
        // True-peak safety trim AFTER the brick-wall limiter. The Apple PeakLimiter
        // limits to 0 dBFS, so peaks sat right on the ceiling (device capture showed
        // repeated −0.1 dBFS peaks → harsh, inter-sample-clip-prone, "not smooth").
        // A −1 dB final trim gives a clean ≤ −1 dBFS ceiling: no clipping, smoother
        // and more homogeneous level, at a negligible 1 dB loudness cost. Everything
        // routes through masterMixer → AutoMixChain → here, so this is the one global
        // output trim.
        masterEngine.mainMixerNode.outputVolume = AudioEngine.outputTrimLinear

        // Extracted so `start()` can RE-install it: this method sits behind the one-shot
        // `graphPrepared` latch, so a tap installed only here can never come back after a
        // media-services reset orphans it (review of #212).
        //
        // Called from BOTH places on purpose — do not "clean up" the apparent redundancy.
        // `prepareGraph()` has five callers that are not `start()` (`attachSourceNode`
        // and friends), so dropping it here would leave the meters dead between graph
        // build and first start; dropping it from `start()` would leave them dead after a
        // reset, which is the whole point. `installMeterTap` removes any previous tap
        // first, so calling it twice costs one extra `EchoelLoudnessMeter` at startup.
        installMeterTap()
        log.audio("Master AVAudioEngine graph: playerNode -> masterMixer -> mainMixer -> outputNode -> hardware")
    }

    /// Install (or RE-install) the master meter tap. Idempotent by construction —
    /// `removeTap` first, exactly like `RetroCapture.install` — because it is called
    /// on every `start()`, not once at graph build.
    ///
    /// WHY IT LIVES HERE INSTEAD OF IN `setupMasterEngine`: review of #212 pointed out
    /// that the premise of that fix condemns this tap too. A media-services reset
    /// orphans the audio objects a tap is attached to; `setupMasterEngine` runs only
    /// through `prepareGraph()`, which returns immediately once `graphPrepared` is set.
    /// So a tap installed there is gone for the rest of the process. And this one is not
    /// only the level meters and the EBU R128 readouts: it is the SOLE writer of
    /// `_outputRing`, which feeds the immersive FFT visual. Restoring the pre-roll ring
    /// while leaving the visual dead would have been a fix that satisfied its own
    /// commit message and not the user.
    private func installMeterTap() {
        // ⭐ #316b: THE TAP SITS AT THE END OF THE MASTER CHAIN, not on `masterMixer`.
        // `masterMixer` is upstream of EQ, auto-gain and the brick-wall limiter — every
        // stage whose job is to shape and bound the master. A loudness/true-peak readout
        // taken there does not describe what leaves the device; #316 could only disclose
        // that on screen and defer the move to here.
        //
        // MOVED rather than DUPLICATED, and the deferral note in `MasterLoudnessGrid`
        // guessed the other way — worth correcting rather than quietly diverging. It
        // assumed a second tap, because this one is also the sole writer of `_outputRing`
        // (the FFT visual) and the host of the #193 timing instrument, and those "must
        // stay". They do not have to stay UPSTREAM: the ring feeds a visual of what is
        // heard, for which post-limiter is the better source, and the #193 instrument
        // measures `when.hostTime`/`sampleTime` deltas of the render cycle, which are the
        // same on any node. What decided it was checking the consumers: `masterPeakDb`
        // and the held true peak had ZERO readers outside this file, and the four EBU
        // values are read only by `MasterLoudnessGrid`. (The held true peak has one now —
        // it became `masterOutputTruePeakDb` for the oscilloscope's readout, #347. That
        // does not change the reasoning here; it is why the value carries the trim.)
        // No behaviour hangs off the old
        // measurement point, so moving costs nothing a second tap would have bought —
        // and a second tap would have doubled a per-buffer block carrying LUFS,
        // oversampled true-peak, an FFT ring write and the timing instrument, against a
        // <30 % CPU budget, for a readout.
        //
        // ⭐ IT ALSO SETTLES THE UNKNOWN #316 REFUSED TO ASSERT: whether the tap observes
        // `masterMixer.outputVolume` (the "Master volume" field). It does now, by
        // construction — that gain is applied at `masterMixer`'s output, which is
        // upstream of the node tapped here. No device run needed for that half any more.
        //
        // Falls back to `masterMixer` when the chain is not installed (`insert` skipped),
        // because tapping an unattached node traps. Both nodes get `removeTap` first: the
        // fallback path may have left one on `masterMixer` from an earlier install, and
        // this method is called on every `start()`, not once.
        masterMixer.removeTap(onBus: 0)
        autoMixChain.chainOutputNode?.removeTap(onBus: 0)
        let meterNode: AVAudioNode = autoMixChain.chainOutputNode ?? masterMixer
        // TRUE once the R128 meter really moved downstream, which is also the moment the
        // level/RMS pair has to STAY upstream — see the long note at its write site. When
        // the chain is not installed both live on `masterMixer` and there is one tap, as
        // before: a node can hold only one tap per bus, so they cannot be split there.
        let levelsComeFromPreChainTap = meterNode !== masterMixer
        let meterFormat = meterNode.outputFormat(forBus: 0)
        if meterFormat.sampleRate > 0 && meterFormat.channelCount > 0 {
            // Match the loudness windows to the real hardware rate. Safe to reassign
            // here ONLY because `removeTap` above already ran: with the tap detached,
            // no other thread is reading these. Before the #212 extraction this said
            // "the meter has no tap yet", which stopped being true the moment the
            // method became re-callable — and re-matching the rate is exactly why it
            // must be re-callable, since a media-services reset can bring the hardware
            // back at a different sample rate.
            sampleRate = meterFormat.sampleRate
            loudnessMeter = EchoelLoudnessMeter(sampleRate: Float(meterFormat.sampleRate))
            let ptrL = _rawMeterL
            let ptrR = _rawMeterR
            let peakPtr = _peakDb
            let tpPtr = _truePeakDb
            let lufsPtr = _lufs
            let lufsSPtr = _lufsS
            let tpMaxPtr = _tpMax
            let lufsIPtr = _lufsI
            let lraPtr = _lra
            let resetPtr = _resetMeters
            let detailedPtr = _detailedMetering
            let meter = masterMeter
            let loudness = loudnessMeter
            let ringPtr = _outputRing
            let ringCountPtr = _outputRingCount
            let ringSize = AudioEngine.outputRingSize
            // #193 instrument — captured by value so the callback touches no `self`.
            let lastTicksPtr = _lastTapTicks
            let lastSamplePtr = _lastTapSampleTime
            let tapFramesPtr = _tapFrames
            let gapCountPtr = _gapCount
            let gapWorstPtr = _gapWorst
            let discCountPtr = _discCount
            let measuredPtr = _measuredCount
            let tickRatio = tickToSeconds
            // One missed RENDER deadline is the event under investigation, so lateness is
            // denominated in IO buffers — not in this tap's (larger) buffer. It must be
            // the buffer the session GRANTED, not the one we preferred:
            // `currentBufferSize` is only ever fed to `setPreferredIOBufferDuration` and
            // is never reconciled with what iOS actually gave us (the two are logged side
            // by side in `AudioConfiguration.describeSession`). Believing 512 while
            // running 1024 would double every figure here AND print a millisecond value
            // that is simply wrong — which is the one thing that value exists to prevent.
            refreshRenderQuantum(fallbackSampleRate: meterFormat.sampleRate)
            let quantumPtr = _quantumSeconds
            let driftWorstPtr = _driftWorst
            let worstScorePtr = _worstScore
            armTimingInstrument()
            meterNode.installTap(onBus: 0, bufferSize: 1024, format: meterFormat) { @Sendable buffer, when in
                guard let channelData = buffer.floatChannelData else { return }
                let frameLength = UInt(buffer.frameLength)
                guard frameLength > 0 else { return }

                // AUDIO-PATH TIMING (#193). Arithmetic on pre-allocated cells plus FOUR
                // ObjC ivar getters on the `AVAudioTime` CoreAudio already handed us. Say
                // that plainly rather than claiming "no ObjC": they are `objc_msgSend`,
                // wait-free on a warm method cache, and unavoidable in a block whose
                // parameters ARE ObjC objects — `buffer.floatChannelData` and
                // `buffer.format` below are the same thing and cannot be removed either.
                // No allocation, no lock, no I/O; nothing of the class #153 took out.
                //
                // `when.hostTime` is the RENDER-CYCLE stamp, so a long interval is evidence
                // that the audio path ran late, not that this block was descheduled. Note
                // the interval spans top-of-callback N−1 → N and therefore CONTAINS the
                // previous callback's metering work: this instrument can implicate the
                // meters, it cannot exonerate them. `when.sampleTime` is the second,
                // INDEPENDENT channel: how far the render position advanced versus how far
                // the previous buffer said it should. The two disagree in a way that is
                // itself diagnostic, so both are reported rather than reduced to one.
                // See `RenderGapDetector` for the full statement of what it does not prove.
                let previousFrames = tapFramesPtr.pointee
                tapFramesPtr.pointee = Int(frameLength)
                // Both baselines are updated on EVERY delivery, valid or not — outside
                // the measuring branch below. An earlier version reset them inside it, so
                // one delivery with an unusable timestamp left BOTH cells holding a stamp
                // two buffers old, and the next good delivery measured across that hole
                // and fabricated a glitch out of it.
                let hostValid = when.isHostTimeValid
                let now = hostValid ? when.hostTime : 0
                let last = lastTicksPtr.pointee
                lastTicksPtr.pointee = now

                // `nil` = this delivery carried no usable frame position, so the second
                // channel abstains rather than voting blind.
                var sampleGap: Int64?
                if when.isSampleTimeValid {
                    let position = when.sampleTime
                    let previous = lastSamplePtr.pointee
                    lastSamplePtr.pointee = position
                    if previous != Int64.min { sampleGap = position &- previous }
                } else {
                    lastSamplePtr.pointee = Int64.min
                }

                if tickRatio > 0 && hostValid {
                    if last != 0 && now > last && previousFrames > 0 {
                        let elapsed = Double(now &- last) * tickRatio
                        // The rate of the buffer IN HAND, not one captured at install: a
                        // route change can move the hardware rate under a surviving tap,
                        // and a period computed from the old rate would fabricate lateness
                        // on every single interval.
                        let rate = buffer.format.sampleRate
                        let q = quantumPtr.pointee * rate
                        // `.rounded()` and not truncation: 0.0106666… × 48000 is
                        // 511.99997, and truncating gives 511 — a unit 0.2 % away from the
                        // millisecond figure printed beside it, which is exactly the
                        // conversion that figure exists to make exact.
                        let quantumFrames = (q.isFinite && q >= 1 && q < 1e7) ? Int(q.rounded()) : 0
                        measuredPtr.pointee &+= 1
                        switch RenderGapDetector.classify(elapsedSeconds: elapsed,
                                                          previousFrames: previousFrames,
                                                          sampleGap: sampleGap,
                                                          sampleRate: rate,
                                                          renderQuantumFrames: quantumFrames) {
                        case .discontinuity:
                            discCountPtr.pointee &+= 1
                        case .glitch(let lateInQuanta, let driftInQuanta):
                            gapCountPtr.pointee &+= 1
                            // Rank by whichever channel is worse, but REPORT that one
                            // interval's own pair. Two independent maxima would print a
                            // lateness from one event beside a drift from another and read
                            // as a single finding that never happened.
                            let score = Swift.max(lateInQuanta, driftInQuanta)
                            if score > worstScorePtr.pointee {
                                worstScorePtr.pointee = score
                                gapWorstPtr.pointee = lateInQuanta
                                driftWorstPtr.pointee = driftInQuanta
                            }
                        case .onTime:
                            break
                        }
                    }
                }

                // Honor a pending reset on this (the meter-owning) thread.
                if resetPtr.pointee {
                    resetPtr.pointee = false
                    meter.reset()
                    loudness.reset()
                }
                let stereo = buffer.format.channelCount > 1
                // ⭐ THE LEVEL/RMS PAIR IS NOT WRITTEN HERE WHEN THE METER MOVED (#316b review).
                // `masterLevel` is not only the two bars: `AudioEngine.start()` hands it to
                // `autoMixChain.connectMeter`, so it is the auto-gain's INPUT — and the
                // auto-gain's own `gainNode` sits UPSTREAM of this node. Writing it from a
                // post-chain tap closes that loop, and `steadyGainDB` is a proportional law
                // with no integrator: its fixed point becomes `g = (target − Lᵢₙ)/2`, i.e.
                // the stage would permanently deliver HALF the correction it computes and
                // never reach the target anywhere inside its ±6 dB window. The Master volume
                // fader (`masterMixer.outputVolume`, also upstream) would likewise keep half
                // its authority and visibly creep back after a drag. The pre-chain tap below
                // owns these two cells instead, which restores the control law byte-for-byte.
                if !levelsComeFromPreChainTap {
                    var rmsL: Float = 0
                    vDSP_rmsqv(channelData[0], 1, &rmsL, vDSP_Length(frameLength))
                    var rmsR: Float = 0
                    if stereo {
                        vDSP_rmsqv(channelData[1], 1, &rmsR, vDSP_Length(frameLength))
                    } else { rmsR = rmsL }
                    ptrL.pointee = rmsL.isNaN ? Float(0) : Swift.min(rmsL * 3.0, 1.0)
                    ptrR.pointee = rmsR.isNaN ? Float(0) : Swift.min(rmsR * 3.0, 1.0)
                }

                // Peak / true-peak / LUFS — meters are confined to this thread;
                // only the resulting Floats cross to the poll timer via pointers.
                // GATED: this is the EXPENSIVE work (true-peak oversampling + EBU
                // R128 K-weighting/gating). Its only consumer is MasterLoudnessGrid
                // (a collapsed-by-default panel), so run it ONLY while that readout
                // is on screen — otherwise it burned CPU every buffer for nothing
                // (a load contributor to the occasional "Knistern"). The cheap RMS +
                // FFT ring below always run (SpectralDonut + immersive visual).
                let n = Int(frameLength)
                if detailedPtr.pointee {
                    // Explicit UnsafePointer(_:) conversion: Swift's implicit
                    // mutable→immutable pointer conversion only fires at function
                    // argument positions, NOT in a let binding or ternary branch, so
                    // construct the immutable pointer directly.
                    let right: UnsafePointer<Float>? = stereo ? UnsafePointer(channelData[1]) : nil
                    meter.processStereo(left: channelData[0], right: right, frameCount: n)
                    loudness.processStereo(left: channelData[0], right: right, frameCount: n)
                    peakPtr.pointee = meter.peakDb
                    tpPtr.pointee = meter.truePeakDb
                    lufsPtr.pointee = loudness.momentaryLUFS
                    lufsSPtr.pointee = loudness.shortTermLUFS
                    tpMaxPtr.pointee = meter.truePeakMaxDb
                    lufsIPtr.pointee = loudness.integratedLUFS
                    lraPtr.pointee = loudness.loudnessRange
                }

                // Capture the mono mix into the lock-free ring for the FFT visual.
                // Plain index writes only — no allocation, no DSP, audio-safe. The
                // write cursor wraps; `_outputRingCount` advances monotonically so a
                // main-thread reader can find the newest contiguous window.
                let count = ringCountPtr.pointee
                let left = channelData[0]
                let rightCh = stereo ? channelData[1] : channelData[0]
                var w = count % ringSize
                for i in 0..<n {
                    ringPtr[w] = (left[i] + rightCh[i]) * 0.5
                    w += 1
                    if w == ringSize { w = 0 }
                }
                ringCountPtr.pointee = count + n
            }
        }

        // ⭐ THE PRE-CHAIN LEVEL TAP (#316b review). Deliberately the ONLY thing that was
        // duplicated, and it is the cheap half: two `vDSP_rmsqv` calls and two pointer
        // writes per buffer. The commit that moved the meter argued against a second tap on
        // CPU grounds and that argument still holds for what it was about — a second LUFS +
        // oversampled true-peak + FFT-ring + timing block. It does not extend to an RMS.
        //
        // WHY IT EXISTS AT ALL: `masterLevel` has a consumer the move's consumer census
        // missed. `start()` passes it to `autoMixChain.connectMeter`, making it the
        // auto-gain's measurement — and the auto-gain acts through `gainNode`, upstream of
        // the moved meter. Measuring a stage's own output with a proportional control law
        // halves it permanently. Keeping this reading where it always was leaves the whole
        // gain-staging chain bit-identical to before #316b, while the R128 readout keeps
        // the honest post-chain measurement that was the point of the change.
        //
        // Installed AFTER the detailed tap so the `meterNode !== masterMixer` case is the
        // only one that reaches here; in the fallback case the single tap above already
        // owns these cells and a second `installTap` on the same bus would replace it.
        if levelsComeFromPreChainTap {
            let preFormat = masterMixer.outputFormat(forBus: 0)
            if preFormat.sampleRate > 0 && preFormat.channelCount > 0 {
                let ptrL = _rawMeterL
                let ptrR = _rawMeterR
                masterMixer.installTap(onBus: 0, bufferSize: 1024,
                                       format: preFormat) { @Sendable buffer, _ in
                    guard let channelData = buffer.floatChannelData else { return }
                    let frameLength = UInt(buffer.frameLength)
                    guard frameLength > 0 else { return }
                    var rmsL: Float = 0
                    vDSP_rmsqv(channelData[0], 1, &rmsL, vDSP_Length(frameLength))
                    var rmsR: Float = 0
                    if buffer.format.channelCount > 1 {
                        vDSP_rmsqv(channelData[1], 1, &rmsR, vDSP_Length(frameLength))
                    } else { rmsR = rmsL }
                    // Same `* 3.0` scaling and NaN sentinel as the original single tap —
                    // `AutoMixChain.updateLUFS` divides by exactly 3.0 to undo it, so this
                    // constant is a contract between the two files, not a display choice.
                    ptrL.pointee = rmsL.isNaN ? Float(0) : Swift.min(rmsL * 3.0, 1.0)
                    ptrR.pointee = rmsR.isNaN ? Float(0) : Swift.min(rmsR * 3.0, 1.0)
                }
            }
        }
    }

    func start() {
        // An explicit start (startup, scenePhase .active, user retry) always
        // re-arms self-healing after an intentional stop.
        stopReason = nil
        // Ensure the session + graph exist before starting, regardless of caller
        // (startup task, scenePhase .active, or route-change recovery).
        prepareGraph()
        if !masterEngine.isRunning {
            masterEngine.prepare()
            armTimingInstrument()
            do {
                try masterEngine.start()
                log.audio("Master AVAudioEngine started — audio output active")
            } catch {
                log.audio("CRITICAL: Failed to start master engine: \(error)", level: .error)
                do {
                    try AudioConfiguration.configureAudioSession()
                    try masterEngine.start()
                    log.audio("Master AVAudioEngine started after session reconfiguration")
                } catch {
                    log.audio("CRITICAL: Master engine start failed after retry: \(error)", level: .error)
                    // Surface to the UI rather than silently showing "stopped".
                    degraded = true
                    lastAudioError = "Audio engine could not start: \(error.localizedDescription)"
                    isRunning = false
                    return
                }
            }
        }
        if inputMonitoringEnabled { microphoneManager.startRecording() }
        startMeterPollTimer()
        // Both taps are re-installed on EVERY start, not once at graph build, and both
        // remove any previous tap first. A media-services reset orphans them; the graph
        // build is behind a one-shot latch and cannot redo it (#212).
        installMeterTap()
        retroCapture.install(on: masterEngine)
        multiTrackRecorder.prepareForRecording(engine: masterEngine)
        autoMixChain.connectMeter { [weak self] in self?.masterLevel ?? 0 }
        isRunning = true
        // A clean start clears any prior degraded state and the recovery counter.
        degraded = false
        lastAudioError = nil
        wasInterrupted = false
        recoveryAttempts = 0
        // #612 (mic-sweep CRITICAL): a media-services reset orphans the monitor tap and
        // chain exactly like the two taps above — but nothing re-armed it: monitoring
        // was the missing third re-install. `isInputMonitoring` survives the reset as
        // true, so both door toggles rendered ON over a dead mic and the feedback guard
        // read a frozen window; a naive re-engage was a no-op behind the
        // already-monitoring guard. DELIBERATELY the last act of start(), AFTER the
        // clean-state block above: if the recycle's own restart fails, it declares
        // `degraded` via restartOrDegrade (#611), and an earlier position would let
        // `degraded = false` two lines up mask that verdict with a healthy claim.
        rearmInputMonitoring(reason: "engine start")
        log.audio("AudioEngine started (production mode) — output: \(currentOutputDescription)")
    }

    /// How long one audio-timing measurement window runs before it reports and resets.
    /// 60 s: long enough that a single scheduler hiccup does not produce a log line, short
    /// enough that a founder session yields several data points to compare against what
    /// they heard.
    private static let timingWindowSeconds: TimeInterval = 60

    /// Re-read the IO buffer size the audio session actually GRANTED, in frames — the
    /// unit the timing instrument denominates lateness in.
    ///
    /// `AudioConfiguration.currentBufferSize` is only ever handed to
    /// `setPreferredIOBufferDuration`; iOS is free to grant something else and routinely
    /// does (always on Bluetooth). Falls back to the preference when the session cannot
    /// answer — on a non-iOS build there is no session to ask.
    ///
    /// Called at tap install AND on a configuration change that leaves the tap in place:
    /// plugging in AirPods mid-session changes the granted buffer without re-installing
    /// anything, and a stale value would scale every figure by the ratio while printing a
    /// millisecond number for a buffer the device is not running. The tap reads the cell,
    /// not a captured copy, for exactly that reason.
    private func refreshRenderQuantum(fallbackSampleRate: Double) {
        #if os(iOS)
        let granted = AVAudioSession.sharedInstance().ioBufferDuration
        if granted.isFinite, granted > 0 {
            _quantumSeconds.pointee = granted
            timingQuantumSeconds = granted
            return
        }
        #endif
        let rate = fallbackSampleRate > 0 ? fallbackSampleRate : AudioConfiguration.preferredSampleRate
        let seconds = Double(AudioConfiguration.currentBufferSize) / rate
        _quantumSeconds.pointee = seconds
        timingQuantumSeconds = seconds
    }

    /// Forget the previous delivery so the first interval AFTER a (re)start is not
    /// measured across the pause.
    ///
    /// Called at every `masterEngine.start()`, not only at tap install — that was the
    /// original mistake: an interruption (Siri, a call) or an ordinary node attach
    /// restarts the graph without re-installing the tap, and the surviving stamp then
    /// produced one interval as long as the entire pause. In the founder's log that
    /// reads `worst 1400×`, which would send the next cycle hunting a stall that never
    /// happened. `nonisolated` because it touches nothing but two `nonisolated(unsafe)`
    /// cells — NOT, as an earlier version of this comment claimed, because the
    /// interruption-resume closure needs it: that closure inherits MainActor isolation
    /// from its context and calls `masterEngine.start()` right below.
    ///
    /// This is belt. The braces are narrower than they sound: the `sampleTime` check
    /// catches a BACKWARDS jump, and the 32-quantum ceiling catches a long gap — a pause
    /// shorter than ~340 ms that leaves the render position untouched is caught by
    /// neither, and is reported as lateness with a zero frame drift beside it. That
    /// pairing is the honest output, not a classification. One residual, pre-existing:
    /// `removeTap` does not guarantee an in-flight block has returned, so a straggler can
    /// undo the arm at re-install. Bounded to one spurious discontinuity by the ceiling.
    nonisolated private func armTimingInstrument() {
        _lastTapTicks.pointee = 0
        _lastTapSampleTime.pointee = Int64.min
    }

    /// Once per window, drain the audio-thread timing cells and write ONE line to
    /// `echoel_diag.log` — the file the founder actually shares (#193).
    ///
    /// Called from the existing 60 Hz meter poll; adds no timer and no thread. Between
    /// windows it is two `Double` compares and returns, and it writes NOTHING observable —
    /// deliberately: a 60 Hz write to an `@Observable` property registers every reader of
    /// this engine as a 60 Hz observer (assigning an equal value still notifies), which is
    /// exactly the churn that tears down an open `.menu` Picker. The log file is the
    /// delivery path for this instrument; there is no on-screen readout, and adding one
    /// would have to go through a leaf view, not through here.
    ///
    /// Reading and resetting the cells races the audio thread writing them. Deliberate: at
    /// worst one increment lands in the wrong window. These are counters whose ORDER OF
    /// MAGNITUDE is the diagnosis, and no lock belongs on the audio path to make a
    /// diagnostic tidier.
    /// Whether a completed timing window is worth a line in `echoel_diag.log`.
    ///
    /// Pure and `static` on purpose, mirroring `shouldSelfHeal(isRunning:…)` in this same
    /// file: the decision is the part that can be wrong, and it is the part a device cannot
    /// be asked to demonstrate. Three reasons to speak, and each exists because its silence
    /// would have meant something false:
    ///   · `firstWindow` — proof of life. Without it, "no line" cannot be told from "the tap
    ///     never ran".
    ///   · `!isClean` — the actual finding.
    ///   · blind while running — the hole this function was extracted to close. `isClean` is
    ///     `glitchCount == 0` and ignores the denominator, so a window that measured NOTHING
    ///     looks identical to a spotless one. Gated on the engine running so a stopped
    ///     instrument stays quiet: a diagnostic that talks during idle gets tuned out, and a
    ///     tuned-out diagnostic is the same as no diagnostic.
    /// ⚠️ `nonisolated`, matching `shouldSelfHeal` above and NOT by preference: `AudioEngine`
    /// is `@MainActor`, so a plain `static func` inherits that isolation and cannot be called
    /// from an ordinary `XCTestCase` method — the same access shape CLAUDE.md records for
    /// `static let`. A predicate that cannot be tested is the one thing this must not be.
    nonisolated static func shouldReportTimingWindow(firstWindow: Bool,
                                                     isClean: Bool,
                                                     measuredIntervals: Int,
                                                     engineRunning: Bool) -> Bool {
        if firstWindow { return true }
        if !isClean { return true }
        return measuredIntervals == 0 && engineRunning
    }

    /// The last completed 60 s timing verdict, in one short line for the Master panel (#408).
    ///
    /// `nil` until the first window closes — the row says so rather than showing a zero it has
    /// not earned. Observation-tracked ON PURPOSE (this is the whole point: the founder must
    /// see it change), and safe to be so because it is written exactly once per
    /// `timingWindowSeconds`. Do NOT add a faster writer to it.
    var lastTimingLine: String?

    private func pollAudioTiming(now: TimeInterval) {
        if timingWindowStart == 0 { timingWindowStart = now; return }
        let elapsed = now - timingWindowStart
        guard elapsed >= Self.timingWindowSeconds else { return }
        timingWindowStart = now
        let tally = RenderGapDetector.Tally(glitchCount: _gapCount.pointee,
                                            worstLateInQuanta: _gapWorst.pointee,
                                            worstDriftInQuanta: _driftWorst.pointee,
                                            discontinuityCount: _discCount.pointee,
                                            measuredIntervals: _measuredCount.pointee)
        let measured = _measuredCount.pointee
        _gapCount.pointee = 0
        // The SCORE is cleared FIRST, deliberately. Cleared last, a glitch classified in
        // between would be measured against the stale high-water mark, lose, and skip
        // writing its pair — into cells that had already been zeroed. The window would
        // then print "N late … worst one 0.0× … frame drift 0.0×", a line that
        // contradicts itself, in the file the founder ships. With the score at zero the
        // first glitch of the new window always wins (a glitch needs a channel above
        // 0.75, so its score is always > 0).
        _worstScore.pointee = 0
        _gapWorst.pointee = 0
        _driftWorst.pointee = 0
        _discCount.pointee = 0
        _measuredCount.pointee = 0

        // ⭐ THE SCREEN GETS EVERY WINDOW; THE LOG DOES NOT (#408). This assignment sits
        // deliberately ABOVE `shouldReportTimingWindow`, because the two readers want opposite
        // things. The LOG speaks only when a window is dirty — that discipline is what keeps
        // `echoel_diag.log` readable, and the comment below spends thirty lines earning it. The
        // ROW is read at the moment a crackle is heard, and a row that only updated on dirty
        // windows would show a verdict from ten minutes ago while the founder is looking for
        // one from now. Stale is worse than clean here: it would be a wrong answer, not a
        // missing one.
        //
        // WHY THIS EXISTS AT ALL: the instrument has been in the app since #193 and has only
        // ever spoken into a file the founder has to export and send. The v10.79.369 report
        // ("teilweise extremes Knacken") arrived without one — which is the normal case, not a
        // lapse, and it left six candidate mechanisms unseparated (#407).
        //
        // Written once per 60 s, so it is nowhere near the freeze law's rate. It is still read
        // in its own leaf (`AudioTimingRow`) rather than in a panel body, because the law is
        // about WHERE a published read registers its observer, not only how fast.
        lastTimingLine = tally.screenLine(overSeconds: elapsed,
                                          quantumMilliseconds: timingQuantumSeconds * 1000)

        // PROOF OF LIFE. The first window always reports, even clean. Otherwise an absent
        // line is indistinguishable between "the audio path was clean", "the timebase
        // lookup failed so the whole measurement was skipped", and "the tap never ran" —
        // and an instrument whose null result cannot be told from a dead instrument
        // cannot falsify anything, which is the one thing this was built to do.
        //
        // And the count is what carries that, not the fact that the tap fired: a window
        // in which NOTHING was classified must never print "no starvation", which would
        // be the same lie in a new place.
        // ⛔ THE PROOF OF LIFE COVERED ONLY THE FIRST WINDOW, AND THAT WAS NOT ENOUGH —
        // found by reading the founder's first real log (v10.79.357, build 2474, 2026-07-29).
        // Nine minutes of session produced exactly ONE timing line, at 60 s. That is correct
        // behaviour and I nearly reported it as a broken instrument: after the first window
        // the meter deliberately speaks only when a window is dirty, so silence means clean.
        //
        // But `isClean` is `glitchCount == 0` and says NOTHING about the denominator. So a
        // window in which the tap never fired — audio route torn down, tap lost after a
        // media-services reset, graph stopped while the engine still claims to run — has
        // glitchCount 0, counts as clean, and is suppressed. Silence therefore meant BOTH
        // "nine clean minutes" and "the instrument died after minute one", which is exactly
        // the ambiguity the comment above says the proof-of-life exists to remove. It removed
        // it once and then let it back in for every window after.
        //
        // A blind window now always speaks. Gated on the engine claiming to be running so an
        // idle app (user stopped playback; no tap, correctly) does not print a line a minute —
        // noise is how a diagnostic gets ignored, which is the same failure in a nicer form.
        // The contradiction "engine running, nothing measured" is the one worth a line.
        let firstWindow = !timingReportedOnce
        timingReportedOnce = true
        guard Self.shouldReportTimingWindow(firstWindow: firstWindow,
                                            isClean: tally.isClean,
                                            measuredIntervals: measured,
                                            engineRunning: masterEngine.isRunning)
        else { return }
        guard measured > 0, timingQuantumSeconds > 0 else {
            // The state is spelled out rather than assumed: this branch is also reached on the
            // FIRST window with the engine legitimately stopped, and when the quantum lookup
            // failed with intervals present. A line that asserted "engine running" in those
            // cases would be a confidently wrong diagnostic — the class of defect this whole
            // instrument was rebuilt five times to avoid.
            let why = measured == 0
                ? (masterEngine.isRunning
                   ? "the tap classified nothing while the engine reports RUNNING"
                   : "the engine was not running")
                : "the render quantum is unknown"
            EchoelCrashLog.breadcrumb("audio timing: no verdict for the last \(Int(elapsed)) s "
                                      + "— \(why). Silence after this line is not evidence of "
                                      + "a clean audio path.")
            return
        }
        // Print the quantum in ms so a later multiplier can be read back as a duration.
        let quantumMs = timingQuantumSeconds * 1000
        EchoelCrashLog.breadcrumb(tally.diagnosticLine(overSeconds: elapsed,
                                                       quantumMilliseconds: quantumMs))
    }

    private func startMeterPollTimer() {
        meterPollTimer?.invalidate()
        // NOT reset here. `start()` calls this on launch, on every foreground resume and
        // on every self-heal; zeroing the window meant a session with restarts under 60 s
        // apart never completed one — and never emitted the proof-of-life line, which is
        // the exact ambiguity it exists to remove. A route-flapping session is precisely
        // the session a founder sends a log from.
        // Read the meter values through `self` (the `_*` pointers are
        // `nonisolated(unsafe)` properties) rather than capturing non-Sendable
        // local pointer copies into the `@Sendable` timer block — Xcode's strict
        // concurrency flags the latter as "sending pointer risks data races".
        meterPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let decayCoeff: Float = 0.92
                self.masterLevel = Swift.max(self._rawMeterL.pointee, self.masterLevel * decayCoeff)
                self.masterLevelR = Swift.max(self._rawMeterR.pointee, self.masterLevelR * decayCoeff)
                // Peak / LUFS already carry their own hold/windowing in the meter;
                // publish them straight through.
                self.masterPeakDb = self._peakDb.pointee
                self.masterLUFS = self._lufs.pointee
                // #316b: the tap sits at the chain output, which is upstream of the ONE
                // remaining gain (`mainMixerNode.outputVolume`). Adding the trim in dB is
                // exact (see `outputTrimDb`) and keeps the audio thread untouched.
                //
                // ⚠️ NOT ADDED TO `masterOutputLRA`: loudness RANGE is a difference between two
                // loudness percentiles, so a constant gain cancels out of it entirely.
                // Offsetting it would have been a silent 1 dB error in a number nobody
                // would have checked — the kind this repo keeps finding a month later.
                self.masterOutputLUFSShortTerm =
                    AudioEngine.trimmed(self._lufsS.pointee, floor: EchoelLoudnessMeter.floorLUFS)
                self.masterOutputTruePeakMaxDb =
                    AudioEngine.trimmed(self._tpMax.pointee, floor: EchoelMeter.floorDb)
                self.masterOutputTruePeakDb =
                    AudioEngine.trimmed(self._truePeakDb.pointee, floor: EchoelMeter.floorDb)
                self.masterOutputLUFSIntegrated =
                    AudioEngine.trimmed(self._lufsI.pointee, floor: EchoelLoudnessMeter.floorLUFS)
                self.masterOutputLRA = self._lra.pointee
                // FeedbackGuard for live input monitoring (~15 Hz, only while monitoring).
                #if os(iOS)
                self.monitorPollTick &+= 1
                if self.isInputMonitoring && self.monitorPollTick % 4 == 0 {
                    self.updateFeedbackGuard()
                    self.updateVoiceTune()
                }
                #endif
                // #193. `systemUptime` and not `Date`/`CFAbsoluteTimeGetCurrent`: the
                // window is an ELAPSED duration, and wall-clock can step backwards on an
                // NTP correction, which would freeze the window open (or fire it early).
                self.pollAudioTiming(now: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    /// Copy the most recent `count` master-output samples (oldest→newest) into
    /// `dest` for the FFT visual. Returns true if a full window was available.
    /// Runs on the MAIN thread; the FFT itself is done by the caller, never on the
    /// audio thread. `dest` must have room for `count` samples. Before enough audio
    /// has played the leading samples are zero (a clean silent window).
    @discardableResult
    func copyLatestOutputSamples(into dest: inout [Float], count: Int) -> Bool {
        let ringSize = AudioEngine.outputRingSize
        let n = Swift.min(count, ringSize)
        guard dest.count >= n else { return false }
        let total = _outputRingCount.pointee          // snapshot once
        // Newest sample sits at (total-1)%ringSize; walk back n samples.
        let start = total - n
        for i in 0..<n {
            let idx = start + i
            dest[i] = idx < 0 ? 0 : _outputRing[((idx % ringSize) + ringSize) % ringSize]
        }
        return total >= n
    }

    /// Reset the EBU R128 integration (integrated LUFS, LRA) and the true-peak
    /// max-hold — e.g. at the start of a measurement / take. The actual reset
    /// runs on the meter-owning tap thread; this just raises the request flag.
    func resetMastering() {
        _resetMeters.pointee = true
    }

    /// Enable/disable the expensive mastering meters (peak/true-peak + EBU R128).
    /// Call `true` when a mastering readout (`MasterLoudnessGrid`) appears and
    /// `false` when it disappears, so the tap only runs that DSP while it is read.
    /// The cheap RMS level + FFT ring are unaffected (always on). Single-Bool
    /// cross-thread write, same discipline as `resetMastering`.
    func setDetailedMetering(_ on: Bool) {
        _detailedMetering.pointee = on
    }

    private var currentOutputDescription: String {
        #if os(macOS)
        return "macOS HAL"
        #else
        let route = AVAudioSession.sharedInstance().currentRoute
        let outputs = route.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }
        return outputs.isEmpty ? "No output" : outputs.joined(separator: ", ")
        #endif
    }

    deinit {
        meterPollTimer?.invalidate()
        if let configChangeObserver { NotificationCenter.default.removeObserver(configChangeObserver) }
        _rawMeterL.deinitialize(count: 1)
        _rawMeterL.deallocate()
        _rawMeterR.deinitialize(count: 1)
        _rawMeterR.deallocate()
        _peakDb.deinitialize(count: 1)
        _peakDb.deallocate()
        _truePeakDb.deinitialize(count: 1)
        _truePeakDb.deallocate()
        _lufs.deinitialize(count: 1)
        _lufs.deallocate()
        _lufsS.deinitialize(count: 1)
        _lufsS.deallocate()
        _tpMax.deinitialize(count: 1)
        _tpMax.deallocate()
        _lufsI.deinitialize(count: 1)
        _lufsI.deallocate()
        _lra.deinitialize(count: 1)
        _lra.deallocate()
        _resetMeters.deinitialize(count: 1)
        _resetMeters.deallocate()
        _detailedMetering.deinitialize(count: 1)
        _detailedMetering.deallocate()
        _outputRing.deinitialize(count: AudioEngine.outputRingSize)
        _outputRing.deallocate()
        _outputRingCount.deinitialize(count: 1)
        _outputRingCount.deallocate()
        _lastTapTicks.deinitialize(count: 1)
        _lastTapTicks.deallocate()
        _lastTapSampleTime.deinitialize(count: 1)
        _lastTapSampleTime.deallocate()
        _tapFrames.deinitialize(count: 1)
        _tapFrames.deallocate()
        _measuredCount.deinitialize(count: 1)
        _measuredCount.deallocate()
        _gapCount.deinitialize(count: 1)
        _gapCount.deallocate()
        _gapWorst.deinitialize(count: 1)
        _gapWorst.deallocate()
        _discCount.deinitialize(count: 1)
        _discCount.deallocate()
        _driftWorst.deinitialize(count: 1)
        _driftWorst.deallocate()
        _quantumSeconds.deinitialize(count: 1)
        _quantumSeconds.deallocate()
        _worstScore.deinitialize(count: 1)
        _worstScore.deallocate()
    }

    /// - Parameter reason: WHY, and it is required rather than defaulted. A default would
    ///   have let the two existing idle-stop call sites keep saying nothing about intent —
    ///   which is exactly how one flag came to answer two questions with opposite correct
    ///   answers and cost the founder a fully silent session (see `StopReason`).
    func stop(reason: StopReason) {
        // Either reason stands the self-healing paths down: an intentionally stopped engine
        // is not broken, and an in-flight recoverEngine settle-Task or a late config-change
        // notification would otherwise restart it in the BACKGROUND, re-creating the 2.5.4
        // silent-audio state the caller just removed (audio-thread review 2026-07-16, F1/F2).
        // Only the FOREGROUND-resume gate distinguishes them.
        stopReason = reason
        // A deliberate stop outranks the interruption that preceded it. Without this the
        // flag survives the stop and a later `.inactive → .active` transition (Control
        // Centre, a notification banner — neither touches `.background`, so neither of
        // the other two scene-phase conditions fires) restarts the engine against the
        // user's last explicit intent. `shouldSelfHeal` already says this in words; the
        // scene-phase gate cannot enforce it because `intentionallyStopped` is private
        // to this type, so it has to be enforced here, at the source of the flag.
        wasInterrupted = false
        meterPollTimer?.invalidate()
        meterPollTimer = nil
        microphoneManager.stopRecording()
        masterPlayerNode.stop()
        masterEngine.pause()
        #if canImport(AVFoundation) && !os(macOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log.audio("Failed to deactivate audio session: \(error.localizedDescription)")
        }
        #endif
        isRunning = false
        log.audio("AudioEngine stopped")
    }

    var stateDescription: String { isRunning ? "Audio engine running" : "Audio engine stopped" }
    var currentLevel: Float { microphoneManager.audioLevel }
    var currentPitch: Float { microphoneManager.currentPitch }

    func schedulePlayback(buffer: AVAudioPCMBuffer) {
        guard masterEngine.isRunning else {
            log.audio("Cannot schedule playback — master engine not running", level: .warning)
            return
        }
        masterPlayerNode.scheduleBuffer(buffer, completionHandler: nil)
        if !masterPlayerNode.isPlaying { masterPlayerNode.play() }
    }

    func scheduleLoopPlayback(buffer: AVAudioPCMBuffer, loopCount: AVAudioPlayerNodeBufferOptions = .loops) {
        guard masterEngine.isRunning else {
            log.audio("Cannot schedule loop playback — master engine not running", level: .warning)
            return
        }
        masterPlayerNode.scheduleBuffer(buffer, at: nil, options: loopCount, completionHandler: nil)
        if !masterPlayerNode.isPlaying { masterPlayerNode.play() }
    }

    // MARK: - Live Input Monitoring (opt-in)

    /// #601 (founder: "Audio in funktioniert bisher nicht"): the permission-aware front
    /// door for the two monitor toggles (mic strip + Audio-input sheet). A direct
    /// `setInputMonitoring(true)` reads the input node's format, and with mic permission
    /// UNDETERMINED that format is 0 Hz — the call bailed with only a log and the system
    /// permission dialog NEVER appeared: on a fresh install the toggle flipped back
    /// silently and audio-in was unreachable from both doors. This asks FIRST (the system
    /// shows no dialog when already granted or denied — those states answer immediately),
    /// engages only on grant, and returns false on denial WITHOUT claiming the record
    /// route, so the callers' refusal copy ("check microphone access in Settings") is
    /// literally the right advice.
    ///
    /// `MicrophoneManager.requestPermission()` is deliberately NOT reused here: it is
    /// fire-and-forget (a Task it cannot be awaited on), so it can never answer the
    /// caller whose Toggle needs the verdict. The capture path keeps it — one asker per
    /// pathway, one definition of "ask" per need.
    ///
    /// ⚠️ RACE PREMISE (review 2026-08-15, named so it cannot be broken silently): resuming
    /// after the `await` with a plain `setInputMonitoring(true)` is safe ONLY because no
    /// programmatic caller of `setInputMonitoring(false)` exists — today the only writers of
    /// `false` are the two toggles' OFF paths, and neither can be tapped while the system
    /// permission alert is up (it is app-modal). The day an interruption / scene-phase /
    /// route-change slice adds a programmatic disable, this method needs an intent re-check
    /// after the `await` — add it in the SAME commit as that caller.
    /// #613 (mic-sweep WARN 3): the ONE definition of "the Settings door is the right
    /// advice". `engageInputMonitoring` below returns false for permission-denial AND
    /// for non-permission failures (session claim, 0 Hz format, restart throw) — the
    /// refusal copy used to blame Settings for all of them, sending a GRANTED user to
    /// a toggle that is already on. Both doors branch their copy on this instead of
    /// re-deriving it (#416). Not `@Observable`-published, and that is safe for a
    /// PRECISE reason (#613b — the first wording said "constant per launch", which is
    /// overbroad): `.undetermined → .granted/.denied` DOES change in-app, at the
    /// permission dialog — but that transition happens exclusively inside
    /// `engageInputMonitoring`, whose result is written to the doors' `@State`
    /// (`micMonitorRefused`/`monitorRefused`), and THAT write forces the re-render
    /// which then reads this property fresh. An unobserved computed read is safe only
    /// while every change path passes through a `@State` write — add a new change path
    /// and this must become observable or be re-read on an event.
    var micPermissionDenied: Bool {
        #if os(iOS)
        return AVAudioApplication.shared.recordPermission == .denied
        #else
        return false
        #endif
    }

    func engageInputMonitoring() async -> Bool {
        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            break
        case .undetermined:
            guard await AVAudioApplication.requestRecordPermission() else {
                logMonitorOutcome("mic permission denied at the dialog", level: .warning)
                return false
            }
        case .denied:
            logMonitorOutcome("mic permission previously denied — Settings is the only door",
                              level: .warning)
            return false
        @unknown default:
            // ⛔ THE ONE EXIT THAT LOGGED NOTHING AT ALL. A future `AVAudioApplication`
            // permission case lands here, returns false, and the door renders "try again" with
            // no line in any sink — the founder's report with no evidence attached, by
            // construction. Unreachable today; that is exactly why it would have been the
            // hardest one to diagnose if it ever fired.
            logMonitorOutcome("unknown record-permission case — refused", level: .warning)
            return false
        }
        return setInputMonitoring(true)
        #else
        return false
        #endif
    }

    /// One monitoring outcome, written to BOTH sinks.
    ///
    /// ⭐ #650 EXISTS BECAUSE FIVE SLICES OF INSTRUMENTATION WENT SOMEWHERE THE FOUNDER
    /// CANNOT READ. #613/#625/#628/#631 each added a distinct `log.audio` line to an exit of
    /// this method, every one of them written to settle "Monitoring could not start — try
    /// again" on a device. `log.audio` reaches `os_log` and an in-memory ring that
    /// `ProfessionalLogger`'s own doc calls "write-only today". The file the founder exports —
    /// `echoel_diag.log`, the one that carries `launch`, `init a:`, `rPPG:`, `trust:` — is
    /// written by `EchoelCrashLog.breadcrumb` and by nothing else. `AudioEngine` had exactly
    /// TWO breadcrumbs before this, both in the audio-timing tally.
    ///
    /// MEASURED, not inferred (build 2531, 2026-08-20): the founder's screen recording shows
    /// the refusal banner at 13:43:49 and his diag log covers 13:43:23 → 13:44:09 — the
    /// failure is INSIDE the logged window and the log names none of the five exits. That is
    /// what makes this a hole and not a missing upload.
    ///
    /// ⚠️ NOT AUDIO-THREAD SAFE and never called from one. `breadcrumb` does `Date()` plus a
    /// `write(2)` — file I/O, banned in a render block. Every caller here is graph
    /// configuration on the main actor, which is the same place the existing `log.audio` calls
    /// already sat.
    ///
    /// ⚠️ ONE MESSAGE, TWO SINKS (#416). The prefixes differ because the sinks do: `os_log`
    /// carries a category, the breadcrumb file is flat and needs a greppable stem.
    private func logMonitorOutcome(_ message: String, level: LogLevel = .error) {
        log.audio("Input monitoring: \(message)", level: level)
        EchoelCrashLog.breadcrumb("monitor: \(message)")
    }

    /// Start/stop monitoring the mic through the main output with FeedbackGuard.
    /// Returns false if monitoring couldn't start (e.g. no mic permission / format).
    /// Defensive throughout — never crashes; worst case it simply doesn't engage.
    /// ⚠️ Turning ON from a user toggle goes through `engageInputMonitoring()` above —
    /// THIS method never shows the permission dialog. After #601 its only production
    /// caller with `true` is that front door; the toggles call it directly only with
    /// `false` (measured 2026-08-15: the two Toggle sites are the only callers outside
    /// this file). Keep it synchronous — the OFF path and tests need no dialog and no
    /// suspension point.
    @discardableResult
    func setInputMonitoring(_ on: Bool) -> Bool {
        #if os(iOS)
        prepareGraph()
        if on {
            guard !isInputMonitoring else { return true }
            // Default session is .playback (output only) so we never drag other
            // apps' Bluetooth audio to HFP call quality. Monitoring reads the mic,
            // so upgrade to .playAndRecord first — otherwise inputNode reports
            // sampleRate 0 and the format guard below bails.
            // #299: CLAIM, don't just upgrade. Before this, monitoring raised the route and
            // nothing ever lowered it — switching monitoring off left the whole system on
            // `.playAndRecord`, i.e. every other app's Bluetooth headset stuck on the HFP mono
            // call codec until Echoel was killed.
            //
            // #625 (founder 2026-08-19, "Es funktioniert gar nichts und killt den
            // restlichen Sound auch") — READ THE RUNNING STATE **BEFORE** THE CLAIM.
            // `claimRecordRoute` ends in `setCategory(.playAndRecord) + setActive(true,
            // options: .notifyOthersOnDeactivation)`, and iOS may STOP a running
            // `AVAudioEngine` underneath a session re-activation. The read used to sit
            // twelve lines BELOW this call, so in exactly that case `wasRunning` latched
            // **false** — and the restart block at the bottom of this branch is
            // `if wasRunning`. Nothing started the engine again. The monitor chain was
            // wired onto a stopped engine, `isInputMonitoring` was set to true and the
            // method returned SUCCESS: no monitor sound, and the MUSIC dead with it,
            // with not one line logged. That is the founder's report verbatim.
            //
            // #611 does not cover this. Its rollback is for `start()` THROWING on the
            // `wasRunning == true` path; this is the path where the flag was already
            // false, so no start was ever attempted and no catch could fire.
            //
            // Reading it early is safe in the other direction too: if the claim does NOT
            // stop the engine, `wasRunning` is what it always was and everything below
            // behaves identically — `pause()` on an already-stopped engine is a no-op.
            // The cost of being wrong about the mechanism is nothing; the cost of the
            // old order was total silence.
            let wasRunning = masterEngine.isRunning
            // #628 (founder screenshot 2026-08-19: "Monitoring could not start — try
            // again", the NON-permission copy) — PAUSE BEFORE THE CLAIM, and read the input
            // format with the engine paused. (⛔ the PAUSE half is superseded by #823
            // below: same position, but it is now a STOP — the pause kept the
            // input-scope-less I/O unit alive. The BEFORE-THE-CLAIM half still holds.)
            //
            // The screenshot is more precise than it looks. `AudioInputPickerView` branches
            // its refusal copy on `micPermissionDenied` (#613), and the founder got the
            // "try again" variant, not "check microphone access in Settings" — so the mic
            // is GRANTED and `engageInputMonitoring` reached `setInputMonitoring(true)`,
            // which then returned false. Only three exits do that: a throwing claim, a 0 Hz
            // input format, and a throwing restart.
            //
            // The format read is the suspect, and the ordering is why. `inputNode`'s format
            // is only meaningful once the session is ACTIVE in a record-capable category —
            // and this method changed the category while the engine was still RUNNING, then
            // read the format, and only paused afterwards. A running engine straddling a
            // category change is exactly the state in which `inputFormat(forBus: 0)` comes
            // back 0 Hz, which lands in the guard below whose message then blames the
            // microphone. Pausing first gives the claim a quiet graph to change under and
            // the read a settled session — the order every sibling site in this file
            // already uses (attach/detach all pause before they touch the graph).
            //
            // ⚠️ HYPOTHESIS, not measurement — and it is the second one this week on this
            // method, after #625's. What makes it worth shipping anyway is that it costs
            // nothing if wrong: pausing a moment earlier changes no state the rest of the
            // branch reads, and the restart at the end is gated on `wasRunning` exactly as
            // the pause is. (⛔ #631: this sentence said the restart was "unconditional on
            // `wasRunning`" — it is `if wasRunning { … start() }`, i.e. conditional ON it.
            // The property that actually holds is the SYMMETRY: whoever paused restarts.)
            // The distinct log lines below are what will actually settle it on the device.
            // #823 (founder device log v10.79.420: FOUR identical "input format
            // unusable" lines over ~10 s — a persistent state, not a race): STOP, do
            // not pause. `pause()` keeps the running I/O unit alive with the
            // configuration it was BUILT with — and an engine started from the
            // playback-only launch graph has no input scope on that unit. A category
            // change under a paused unit does not rebuild it, so
            // `inputFormat(forBus: 0)` returns the 0 Hz/2 ch placeholder on every
            // retry — exactly the four logged lines. `stop()` releases the prepared
            // I/O unit so the `start()` below rebuilds it against the NEW
            // record-capable session, input scope included. The #628 symmetry is
            // unchanged: whoever stopped restarts (`if wasRunning { … start() }`),
            // and every failure exit still goes through `restoreEngineIfStranded`.
            // ⚠️ HYPOTHESIS #3 on this method (#625 and #628 came first) — labeled so
            // the NEXT device log discriminates: if the session-fallback line below
            // fires and monitoring runs, the mechanism is confirmed; if the
            // #628/#823 line still fires WITH a live session rate in it, the
            // placeholder survives even a rebuild and this fix is wrong.
            if wasRunning { masterEngine.stop() }
            do { try AudioConfiguration.claimRecordRoute(.inputMonitoring) }
            catch {
                // #628: the claim used to only LOG and fall through — straight into a format
                // read that cannot succeed, so the user saw "no valid input format (mic
                // permission?)" for a failure that had nothing to do with the microphone.
                // Naming it here is what lets a diag log tell the two apart.
                logMonitorOutcome("session upgrade failed (\(error))")
                try? AudioConfiguration.releaseRecordRoute(.inputMonitoring)
                restoreEngineIfStranded(wasRunning, at: "input monitoring claim failed")
                return false
            }
            // ⛔ #631 — THE #625 BREADCRUMB STOOD HERE AND #628 TURNED IT INTO A CONSTANT.
            // It read `if wasRunning && !masterEngine.isRunning { log "the session claim
            // stopped the engine (#625)" }`, and its own comment promised it was "silent on
            // every healthy toggle and unmistakable on the broken one". #628 then moved
            // `masterEngine.pause()` ABOVE the claim — and `pause()` clears `isRunning`, so
            // from that commit on the condition was true on EVERY toggle where the engine had
            // been running. The line asserted the exact opposite of what it now measured.
            //
            // ⭐ DELETED RATHER THAN REPAIRED, because there is nothing left for it to
            // measure: once WE pause (a stop since #823) the engine, `isRunning == false` no longer distinguishes
            // "our pause" from "the claim stopped it". Sampling before the pause would say
            // nothing about the claim. The hypothesis #625 wanted to test is no longer
            // testable at this point in the method, and saying so is worth more than a line
            // that fires every time and reads like a confirmation.
            //
            // ⚠️ THIS MATTERS FOR THE PENDING DEVICE PROBE, which is the reason it is a
            // deletion and not a note: the founder's monitoring log would have carried this
            // warning on every healthy toggle, and the next session reading that log would
            // have counted it as evidence FOR the mechanism it was built to falsify.
            // What survives as evidence is `restoreEngineIfStranded`'s own line at each exit.
            let input = masterEngine.inputNode
            var inFmt = input.inputFormat(forBus: 0)
            if inFmt.sampleRate <= 0 || inFmt.channelCount == 0 {
                // #823: the node can still hand back its placeholder right after the
                // claim (the I/O unit rebuilds lazily on `start()`). The SESSION knows
                // the real hardware format by now — build the connect format from ITS
                // values, never from an invented constant: a connect format that
                // disagrees with hardware raises an ObjC exception no Swift `catch`
                // sees. Guarded on the session's own numbers, so this can only
                // substitute a format the hardware itself just reported.
                let session = AVAudioSession.sharedInstance()
                let sessionRate = session.sampleRate
                let sessionChannels = AVAudioChannelCount(min(max(session.inputNumberOfChannels, 1), 2))
                if sessionRate > 0, session.isInputAvailable,
                   let fallback = AVAudioFormat(standardFormatWithSampleRate: sessionRate,
                                                channels: sessionChannels) {
                    logMonitorOutcome("""
                        input format from session fallback \
                        (node \(inFmt.sampleRate) Hz/\(inFmt.channelCount) ch, \
                        session \(sessionRate) Hz/\(session.inputNumberOfChannels) ch) — #823
                        """, level: .info)
                    inFmt = fallback
                }
            }
            guard inFmt.sampleRate > 0, inFmt.channelCount > 0 else {
                // #628: the message no longer guesses "mic permission?". By the time this
                // runs the permission is granted (`engageInputMonitoring` is the only
                // production caller with `true` and it returns early on denial), so that
                // parenthetical sent every reader — me included — down the wrong path. Say
                // what was actually measured instead.
                // #823: carry the SESSION's view of the hardware in the same line, so
                // the next device log distinguishes "no input at all" (session rate 0
                // or input unavailable) from "input exists but the node won't say so"
                // (live session rate beside a 0 Hz node) without a second probe.
                let session = AVAudioSession.sharedInstance()
                logMonitorOutcome("""
                    input format unusable after the session claim \
                    (sampleRate \(inFmt.sampleRate), channels \(inFmt.channelCount), \
                    engine \(masterEngine.isRunning ? "running" : "stopped"), \
                    session \(session.sampleRate) Hz/\(session.inputNumberOfChannels) in, \
                    inputAvailable \(session.isInputAvailable)) — #628/#823
                    """)
                // The claim is already registered — hand it back on the way out, or a denied
                // mic permission leaves the route raised for the rest of the session. This is
                // the failure path that made a refcount unsafe; with a set it is one line.
                try? AudioConfiguration.releaseRecordRoute(.inputMonitoring)
                // #625b (review 2a, CRITICAL): #611's failure shape, on a different exit.
                // The claim above may already have stopped the engine; this exit does no
                // graph work, so it used to return with the WHOLE app silent — music
                // included — while the only visible line blamed microphone permission. Two
                // real ways in: a denied mic, and the transient input-less moment mid-route-
                // switch that this file already anticipates one screen up (`newRate > 0`).
                restoreEngineIfStranded(wasRunning, at: "input monitoring format guard")
                return false
            }
            // `wasRunning` is captured ABOVE, before the session claim (#625), and the
            // engine is STOPPED up there too (#628 paused it there; #823 turned the
            // pause into a stop) — do not move either back down here; the read being
            // late was #625's bug and the pause being late is #628's.
            if !monitorAttached { masterEngine.attach(monitorMixer); monitorAttached = true }
            // #595: the notch band is configured ONCE at attach; only frequency and
            // gain move at runtime (gain slewed by the guard tick, never stepped).
            if !notchAttached {
                masterEngine.attach(notchEQ)
                notchAttached = true
                if let band = notchEQ.bands.first {
                    band.filterType = .parametric
                    band.bandwidth = 0.15   // octaves — narrow, takes the whistle not the voice
                    band.gain = 0
                    band.bypass = false
                }
                notchEQ.globalGain = 0
            }
            monitorMixer.outputVolume = 0          // silent until connected, avoids a pop
            let outFmt = masterMixer.outputFormat(forBus: 0)
            masterEngine.connect(input, to: notchEQ, format: inFmt)
            if voiceTuneEnabled {
                if !voiceTuneAttached { masterEngine.attach(voiceTunePitch); voiceTuneAttached = true }
                voiceTuneCorrector.reset()
                voiceTunePitch.pitch = 0
                masterEngine.connect(notchEQ, to: voiceTunePitch, format: inFmt)
                masterEngine.connect(voiceTunePitch, to: monitorMixer, format: inFmt)
            } else {
                masterEngine.connect(notchEQ, to: monitorMixer, format: inFmt)
            }
            masterEngine.connect(monitorMixer, to: masterMixer, format: outFmt)
            monitorLevelHistory.removeAll(keepingCapacity: true)
            feedbackGuardActive = false
            notchGainDB = 0
            notchHoldTicks = 0
            notchEQ.bands.first?.gain = 0
            if wasRunning {
                armTimingInstrument()
                do { try masterEngine.start() }
                catch {
                    logMonitorOutcome("engine restart failed (\(error))")
                    masterEngine.disconnectNodeOutput(notchEQ)
                    if voiceTuneAttached { masterEngine.disconnectNodeOutput(voiceTunePitch) }
                    masterEngine.disconnectNodeOutput(monitorMixer)
                    try? AudioConfiguration.releaseRecordRoute(.inputMonitoring)   // #299
                    // #611: the pause (a stop since #823) above was OURS. Returning
                    // false with the engine still down stranded the WHOLE app silent (music included) behind
                    // a stale `isRunning`, while the only visible line blamed microphone
                    // permission. The monitor chain is disconnected again, so this start
                    // restores the exact pre-toggle graph; if even that fails, the
                    // helper declares `degraded` and AudioDegradedRow owns the silence.
                    restartOrDegrade(after: "input monitoring rollback")
                    return false
                }
            }
            // The spectrum tap is installed LAST, after every failure path above, so no
            // exit below `return false` can leave a live tap behind. One tap per bus —
            // and there IS a second claimant on this exact node/bus: `MultiTrackRecorder
            // .prepareForRecording(engine:)` is handed THIS engine and does
            // `removeTap` + `installTap` on `inputNode` bus 0. Today that path cannot
            // fire (doorless + flag-gated off, #204 — `RecordController.arm()` has zero
            // callers), so no live collision exists; MicrophoneManager taps its OWN
            // engine and is not a claimant. ⚠️ The #204 door-opening slice MUST make
            // monitoring and multitrack recording mutually exclusive on this bus (or
            // share one tap): started together, the recorder's `removeTap` silently
            // kills this tap while `monitorTapInstalled` stays true — the notch then
            // reads a frozen window — and the monitoring-OFF path below would remove
            // the RECORDER's tap mid-take. The mirror note sits at the recorder's
            // `installTap` site. ⛔ The first version of this comment said "this is the
            // ONLY tap on masterEngine.inputNode" — false in `Sources/`, reviewer #595.
            if !monitorTapInstalled {
                monitorTapWindow.clear()
                // Captured ONCE at install (#595 reviewer F2). Two consumers divide by
                // this rate: `binToHz` for the notch (a stale rate puts the 0.15-octave
                // band up to ~9 % off, i.e. beside the howl) and — since #599 — YIN,
                // where a 44.1↔48 switch shifts every detected pitch by a constant
                // ~147 cents, so "Tune to key" snaps the voice to WRONG notes.
                //
                // ⛔ BOTH ⚠️ BLOCKS THAT STOOD HERE ARE RETRACTED: they described the
                // repair as PENDING — "a route-change re-arm of monitoring is the honest
                // fix if this shows up on device" and "the re-arm above is now
                // correspondingly more valuable". **#612 BUILT IT.** The
                // `.AVAudioEngineConfigurationChange` observer compares the live
                // `inputNode` rate against this field and calls `rearmInputMonitoring`
                // on a mismatch; `start()` covers the media-services-reset path. The
                // capture is still once-per-install — that has not changed and does not
                // need to — but it is now RE-captured on every route switch, so neither
                // consumer runs stale for longer than one configuration-change hop.
                // ⚠️ #625b (review LOW): that sentence reads as total coverage and is not.
                // ⛔ #826 CLOSED THE HALF #625b REGISTERED: the gate now tests rate OR
                // channel count (both captured below), so "a route change that alters
                // the CHANNEL COUNT without altering the rate re-arms nothing" is no
                // longer true — that was the mono-BT-mic → stereo-USB-at-48k case.
                //
                // Why the retraction and not a deletion: a comment that files a fix as
                // outstanding is an instruction to the next session to build it, and
                // this one named a CRITICAL. Left as it was, the cheapest reading of
                // "live monitoring is broken on a route change" was to write
                // `rearmInputMonitoring` a second time. The residual risk is different
                // and smaller: the re-arm rides on a configuration-change NOTIFICATION,
                // so a route switch that never posts one leaves both consumers stale —
                // that, and nothing above, is what a device report would have to
                // distinguish.
                monitorTapSampleRate = inFmt.sampleRate
                monitorTapChannelCount = inFmt.channelCount   // #826, the gate's other half
                let window = monitorTapWindow
                input.installTap(onBus: 0,
                                 bufferSize: AVAudioFrameCount(monitorTapWindow.size),
                                 format: inFmt) { @Sendable buffer, _ in
                    // TAP THREAD (not the render thread — MicrophoneManager's tap states
                    // the same law). Push into the lock window and return; no FFT here.
                    guard let ch = buffer.floatChannelData else { return }
                    window.push(ch[0], count: Int(buffer.frameLength))
                }
                monitorTapInstalled = true
            }
            isInputMonitoring = true
            monitorMixer.outputVolume = min(max(inputMonitorGain, 0), 1)
            // #829: monitoring ON re-applies the megaphone choice — the flag can be
            // flipped while monitoring is off, and the OFF path resets globalGain.
            notchEQ.globalGain = megaphoneMode ? Self.megaphoneBoostDB : 0
            // ⚠️ THE SUCCESS LINE IS NOT OPTIONAL. Six refusal breadcrumbs and no success
            // breadcrumb makes a quiet log ambiguous between "never toggled" and "toggled and
            // worked" — the #454 shape, applied to a diag file instead of a test. The rate and
            // channel count ride along because they are what the format guard above rejects,
            // so a working take and a refused one can be compared side by side.
            logMonitorOutcome("ON (gain \(inputMonitorGain), "
                              + "megaphone \(megaphoneMode ? "on" : "off"), "
                              + "\(inFmt.sampleRate) Hz, "
                              + "\(inFmt.channelCount) ch)", level: .info)
            // #653 — the MOMENT that decides whether monitoring is usable at all. The
            // session's own round-trip estimate plus the port names it was measured on go
            // into the EXPORTABLE log here, right beside the "ON" line, so a founder take
            // reads as one pair: monitoring started, and this is what it costs on THIS
            // combination. Emitted after `logMonitorOutcome` deliberately — the ON line is
            // the fact, the latency is its measurement, and a reader scanning for failures
            // should hit the fact first.
            // ⛔ #654: `tuneStage` is passed because the monitor chain is
            // `input → notchEQ → [voiceTunePitch] → monitorMixer`, and the pitch node is a
            // phase vocoder whose delay is NOT in `floor=`. `AudioInputPickerView` already
            // warns about it in prose; a number that omitted it contradicted the app's own
            // UI on the same feature, and a number wins that argument every time.
            // ⭐ #666: and this is the line the `inserts[…]` field exists for — the only
            // moment where every monitor node is attached and connected.
            AudioConfiguration.latencyBreadcrumb(reason: "monitor on",
                                                 tuneStage: voiceTuneEnabled,
                                                 insertMilliseconds: monitorInsertLatencyMilliseconds)
            return true
        } else {
            guard isInputMonitoring else { return true }
            // #831 (founder crash v10.79.421, 2539: `required condition is false:
            // false == isInputConnToConverter`, SIGABRT thrown synchronously out of a
            // toggle's Binding set): graph surgery on the monitor chain must not race
            // a RUNNING render. This branch tore the chain down live — removeTap plus
            // three disconnects — while the file's own #628 block says every sibling
            // site quiets the engine before touching the graph. The capture moves up
            // here from below the surgery (it was read AFTER, #625b) and it is a
            // STOP, not a pause: a category change follows on this path, and #823
            // measured that a paused I/O unit keeps its built configuration across
            // category changes. `restoreEngineIfStranded` below restarts, as before.
            let offWasRunning = masterEngine.isRunning
            if offWasRunning { masterEngine.stop() }
            monitorMixer.outputVolume = 0
            if monitorTapInstalled {
                masterEngine.inputNode.removeTap(onBus: 0)
                monitorTapInstalled = false
            }
            monitorTapWindow.clear()
            masterEngine.disconnectNodeOutput(notchEQ)
            if voiceTuneAttached { masterEngine.disconnectNodeOutput(voiceTunePitch) }
            masterEngine.disconnectNodeOutput(monitorMixer)
            isInputMonitoring = false
            feedbackGuardActive = false
            notchGainDB = 0
            notchHoldTicks = 0
            notchEQ.bands.first?.gain = 0
            notchEQ.globalGain = 0   // #829: the boost never survives monitoring OFF
            // #599 sweep M1: monitoring OFF also DISARMS the tune. The flag was a
            // pure latch, but the ONLY surface that can show or clear it renders
            // while monitoring is on (the input sheet) — so the mixer strip's
            // Monitor door could silently re-arm a tune nobody can see. Routed
            // through setVoiceTune (the one writer); monitoring is already false
            // here, so its guard makes this a pure state+corrector reset.
            setVoiceTune(false)
            // #299: the missing half. Monitoring off returns the route — but only if no
            // recorder still holds it, which is why this goes through the owner set instead of
            // calling `downgradeToPlaybackAfterRecording` directly.
            // #625b (review 2b, CRITICAL): the OFF path changes the session category too
            // (`releaseRecordRoute` → `downgradeToPlaybackAfterRecording` →
            // `setCategory(.playback)`), and had NO running-state read and NO restart at
            // all. #625 enforced its own law on one of the two category-changing branches.
            //
            // This is the RECOVERY HOT PATH, not a corner: `start()` → `rearmInputMonitoring`
            // → OFF → category change → if THAT stops the engine, the immediately following
            // ON reads `wasRunning == false` and strands the engine exactly as #625
            // describes — through the door #625 left open.
            // (#831: `offWasRunning` is now captured at the TOP of this branch, before
            // the engine is stopped for the graph surgery — reading it here would
            // always see `false` and the restore below would never fire.)
            do { try AudioConfiguration.releaseRecordRoute(.inputMonitoring) }
            catch { logMonitorOutcome("session downgrade failed (\(error))", level: .warning) }
            restoreEngineIfStranded(offWasRunning, at: "input monitoring off")
            logMonitorOutcome("OFF", level: .info)
            return true
        }
        #else
        return false
        #endif
    }

    /// VL3 (#599): toggle the in-key correction stage. Rewires the LIVE monitor chain
    /// when monitoring is on; otherwise it only stores the choice — the next
    /// `setInputMonitoring(true)` builds the chain accordingly. NOT persisted, same
    /// law as the monitoring toggle itself: tuning the monitor is a performance act —
    /// and the monitoring-OFF path DISARMS it (sweep M1), so a later re-arm of
    /// monitoring from any door never carries a tune no visible control admits to.
    ///
    /// ⛔ The first version cited "graph edits while running are the #595/#299
    /// pattern" — WRONG PRECEDENT (#599 review): #595's `setInputMonitoring` PAUSES
    /// the engine before connecting and restarts after; #299 is session-category
    /// claiming, not graph work.
    /// ⛔ #831 — AND THE SECOND VERSION'S DEFENSE IS MEASURED FALSE. It read: this
    /// method is "deliberately the OTHER documented pattern — dynamic reconfiguration
    /// on a RUNNING engine — because there is no `start()` to fail here, and pausing
    /// the master engine would hiccup the MUSIC", with "whether the live rewire
    /// clicks audibly" left as the device probe. The founder's v10.79.421 device log
    /// answered it: `required condition is false: false == isInputConnToConverter`,
    /// SIGABRT, thrown synchronously out of a toggle's Binding set — rewiring the
    /// input-fed chain through the time-pitch node (converter machinery) while the
    /// engine renders is an ObjC assert no Swift catch can see. A bounded pause
    /// hiccup beats the whole app dying; the surgery is now paused around, with the
    /// `start()` failure path the old argument said did not exist.
    /// Both branches stay straight-line between disconnect and connect, so no exit
    /// leaves `notchEQ` outputless.
    func setVoiceTune(_ on: Bool) {
        guard on != voiceTuneEnabled else { return }
        voiceTuneEnabled = on
        voiceTuneCorrector.reset()
        voiceTunePitch.pitch = 0
        #if os(iOS)
        guard isInputMonitoring else { return }
        // Same format SOURCE as the build path (`inputFormat(forBus: 0)`, #599 review
        // LOW): mixing input- and output-format reads across the two wiring sites is
        // the connect-time-exception seed after a mid-session hardware-rate change.
        let inFmt = masterEngine.inputNode.inputFormat(forBus: 0)
        // #831: quiet the engine around the rewire — pause, not stop: no category
        // change happens here, and the pause is what removes the running-render race.
        let wasRunning = masterEngine.isRunning
        if wasRunning { masterEngine.pause() }
        if on {
            if !voiceTuneAttached { masterEngine.attach(voiceTunePitch); voiceTuneAttached = true }
            masterEngine.disconnectNodeOutput(notchEQ)
            masterEngine.connect(notchEQ, to: voiceTunePitch, format: inFmt)
            masterEngine.connect(voiceTunePitch, to: monitorMixer, format: inFmt)
        } else {
            masterEngine.disconnectNodeOutput(notchEQ)
            if voiceTuneAttached { masterEngine.disconnectNodeOutput(voiceTunePitch) }
            masterEngine.connect(notchEQ, to: monitorMixer, format: inFmt)
        }
        if wasRunning {
            armTimingInstrument()
            do { try masterEngine.start() }
            catch {
                logMonitorOutcome("voice tune rewire restart failed (\(error))")
                restartOrDegrade(after: "voice tune rewire")
            }
        }
        #endif
    }

    #if os(iOS)
    /// VL3 (#599): the ~15 Hz correction step, on the guard tick — YIN over the shared
    /// monitor window → pure `VoicePitchCorrector` → smoothed cents onto the graph
    /// node. MainActor throughout; the audio thread never sees any of this. YIN over
    /// 2048 samples is ~1–2 ms — the same budget class as the notch FFT beside it.
    private func updateVoiceTune() {
        guard voiceTuneEnabled else { return }
        // ~1 Hz: re-read key + Kammerton from the ONE stored definition the studio
        // writes (#416) — never a second copy of the key that can drift.
        if voiceTuneKeyRefreshTick % 15 == 0 {
            let d = UserDefaults.standard
            let root = d.object(forKey: StudioDefaultKeys.rootIndex.key) as? Int
                ?? StudioDefaultKeys.rootIndex.value
            let scale = d.string(forKey: StudioDefaultKeys.scale.key)
                .flatMap(Scale.init(rawValue:)) ?? StudioDefaultKeys.scale.value
            voiceTuneCorrector.key = MusicalKey(root: root, scale: scale)
            let a4 = d.object(forKey: SessionContext.a4StorageKey) as? Double
                ?? SessionContext.defaultA4Hz
            voiceTuneCorrector.a4Hz = a4 > 0 ? a4 : SessionContext.defaultA4Hz
        }
        voiceTuneKeyRefreshTick &+= 1
        // Sanitize at the boundary (#599 review LOW): the corrector clamps only in
        // init, and "EchoelValueField is the sole writer" is true today, not by
        // construction.
        voiceTuneCorrector.strength = Double(Swift.min(Swift.max(voiceTuneStrength, 0), 1))
        voiceTuneCorrector.retuneSpeed = Double(Swift.min(Swift.max(voiceTuneRetune, 0), 1))
        var detected: Double?
        if monitorTapSampleRate > 0, monitorTapWindow.copyLatest(into: &voiceTuneBuffer) {
            detected = PitchTracker.detect(voiceTuneBuffer, sampleRate: monitorTapSampleRate)
        }
        // dt = the guard cadence (60 Hz poll gated %4); unvoiced frames relax the
        // correction toward zero inside the corrector — no stale bend on the next onset.
        let correction = voiceTuneCorrector.process(detectedHz: detected, dt: 4.0 / 60.0)
        voiceTunePitch.pitch = Float(correction.appliedCents)
    }

    /// MainActor FeedbackGuard step (called from the meter poll while monitoring):
    /// duck the MIC monitor — not the music — when the output shows the rising-over-
    /// ceiling runaway that signals acoustic feedback. No audio-thread work, no tap.
    private func updateFeedbackGuard() {
        guard isInputMonitoring else { return }
        let level = Swift.max(_rawMeterL.pointee, _rawMeterR.pointee)
        monitorLevelHistory.append(level)
        if monitorLevelHistory.count > 8 { monitorLevelHistory.removeFirst() }
        // #829: while boosted, the guard reacts EARLIER (lower ceiling) and its
        // authority exceeds the boost (default depth + boost — derived, never a
        // second literal, #416). Unboosted, the call keeps the defaults untouched.
        let duckDB = megaphoneMode
            ? FeedbackGuard.gainReductionDB(rmsHistory: monitorLevelHistory,
                                            ceiling: Self.megaphoneDuckCeiling,
                                            maxReductionDB: FeedbackGuard.defaultMaxReductionDB
                                                            + Self.megaphoneBoostDB)
            : FeedbackGuard.gainReductionDB(rmsHistory: monitorLevelHistory)
        let base = Swift.min(Swift.max(inputMonitorGain, 0), 1)
        let factor: Float = duckDB > 0 ? powf(10, -duckDB / 20) : 1
        monitorMixer.outputVolume = base * factor
        // ⚠️ GATED ON CHANGE, NOT ASSIGNED EVERY TICK (#298 Nachlese). `feedbackGuardActive` is
        // a plain `@Observable` stored property, and **assigning an equal value still
        // notifies** — the rule this file already states at `emitTimingWindowIfDue`. Assigning
        // it unconditionally made every reader (today: `AudioInputPickerView.monitoringSection`,
        // which hosts a draggable `EchoelValueField`) a ~15 Hz observer for the whole time
        // monitoring runs. No `.menu` Picker lives in that sheet, so this was never the
        // 10.76.50 freeze — but it is the same mechanism, and the fix is one compare.
        let ducking = duckDB > 0
        if ducking != feedbackGuardActive { feedbackGuardActive = ducking }

        // #595: the NOTCH half. Engage ONLY while the duck already fires AND one bin
        // clearly dominates the input spectrum (`ringingBin`, dominance ×8) — two
        // independent signatures, so a loud clean note never gets notched. The gain is
        // slewed (±4 dB/tick) and held ~2 s past the last detection so the notch does
        // not audibly pump as the ring decays under it. All of this runs HERE, on the
        // MainActor at ~15 Hz — the tap only filled the window.
        var target: Float = 0
        if ducking,
           monitorSpectrumFFT.size == monitorTapWindow.size,
           monitorTapSampleRate > 0,
           monitorTapWindow.copyLatest(into: &monitorSpectrumBuffer),
           let bin = FeedbackGuard.ringingBin(
               magnitudes: monitorSpectrumFFT.forward(monitorSpectrumBuffer).magnitudes) {
            let hz = FeedbackGuard.binToHz(bin, fftSize: monitorSpectrumFFT.size,
                                           sampleRate: monitorTapSampleRate)
            // Clamp to the EQ's sane range: below ~40 Hz is rumble not howl, and the
            // band frequency must stay under Nyquist for the current input rate.
            let clamped = Swift.min(Swift.max(hz, 40), monitorTapSampleRate * 0.45)
            notchEQ.bands.first?.frequency = Float(clamped)
            target = -24
            notchHoldTicks = Self.notchHoldTickCount
        } else if notchHoldTicks > 0 {
            notchHoldTicks -= 1
            target = -24   // hold on the parked frequency while the ring decays
        }
        notchGainDB = FeedbackGuard.slewedNotchGainDB(current: notchGainDB, target: target)
        notchEQ.bands.first?.gain = notchGainDB
    }
    #endif

    // MARK: - Source Node Registration

    /// #611 (mic-sweep CRITICAL, found at all four pause/mutate/restart sites): a graph
    /// mutation pauses a running engine; if the restart then THROWS, the app is left
    /// silent while `isRunning` stays stale-true — a pause posts no configuration-change
    /// notification, so the watchdog never fires, the #605 silence line (which needs
    /// `!isRunning`) stays hidden, and AudioDegradedRow (which needs `degraded`) stays
    /// hidden. On the monitor path the only visible text then BLAMED MIC PERMISSION.
    /// Every restart-after-mutation funnels through this ONE helper: one more start
    /// attempt, and if that also throws, an honest handover to the degraded machinery
    /// that already owns cause + retry (AudioDegradedRow's button calls `start()`,
    /// which also re-runs the session config). Never a log-only catch again.
    private func restartOrDegrade(after context: String) {
        do { try masterEngine.start() }
        catch {
            log.audio("Engine restart after \(context) failed (\(error)) — handing over to AudioDegradedRow", level: .error)
            isRunning = false
            degraded = true
            lastAudioError = "Audio stopped (\(context)) and could not restart: \(error.localizedDescription)"
        }
    }

    /// #612 (mic-sweep CRITICAL): re-arm live monitoring by a full OFF→ON recycle.
    /// Needed because `setInputMonitoring(true)` is deliberately a no-op while
    /// `isInputMonitoring` is already true — so after a media-services reset (which
    /// orphans the monitor tap and connections but leaves the flag true) or a hardware
    /// sample-rate switch (which leaves `monitorTapSampleRate` stale for the notch and
    /// YIN maths), NOTHING could heal monitoring short of the user toggling it off and
    /// on. Two callers: `start()` (covers reset → recoverEngine → start and every manual
    /// retry) and the configuration-change running branch (rate switch under a running
    /// engine). The tune choice is saved and restored across the recycle because the
    /// OFF path deliberately disarms it (#599 M1) — restore happens BETWEEN off and on,
    /// while monitoring is off, so `setVoiceTune` only stores the choice and the ON
    /// builds the chain with the tune stage in place.
    /// #625b — THE EXIT GUARANTEE the #625 breadcrumb was writing cheques against.
    ///
    /// Both branches of `setInputMonitoring` mutate the shared audio session's CATEGORY,
    /// and iOS may stop a running `AVAudioEngine` underneath such a mutation. #625 moved
    /// the running-state read above the claim, which fixed the ON path's main exit — and
    /// left two doors open: the ON path's format-guard exit does no graph work and simply
    /// returned, and the OFF path had no running-state handling whatsoever. Either could
    /// return with the whole app silent, music included.
    ///
    /// Called at each such exit with the state captured BEFORE that exit's session
    /// mutation. `restartOrDegrade` is the file's one honest handover: it restarts, and if
    /// even that fails it raises `degraded` so `AudioDegradedRow` owns the silence instead
    /// of nobody owning it. A no-op whenever the engine is still running, which is every
    /// healthy toggle.
    ///
    /// ⚠️ WHAT THIS DOES NOT REPAIR (review 2c): if the session change altered the HARDWARE
    /// FORMAT, a bare restart brings the engine back with the master chain still wired at
    /// the old format — running and silent. Nothing in this app reconnects it, because
    /// `attachSourceNode` stores no registry of what it attached and `prepareGraph()` is
    /// one-shot. That is a separate, bigger slice with its own Council; do not read this
    /// helper as covering it.
    /// ⛔ #631: the message used to say "stopped by a session change", and after #628 that
    /// names a cause this helper cannot know. On the monitoring ON path the engine may be
    /// stopped because WE paused it a few lines earlier; on the OFF path and the other
    /// callers nothing paused it, so a session change really is the candidate. One helper,
    /// two causes — so it reports the STATE it measured and the exit it measured it at, and
    /// leaves the cause to the reader who has the surrounding lines.
    private func restoreEngineIfStranded(_ wasRunning: Bool, at exit: String) {
        guard wasRunning, !masterEngine.isRunning else { return }
        log.audio("Audio engine is not running at exit — restoring (\(exit))",
                  level: .warning)
        armTimingInstrument()
        restartOrDegrade(after: exit)
    }

    private func rearmInputMonitoring(reason: String) {
        guard isInputMonitoring else { return }
        // Included deliberately (#650): this is the one monitoring line that fires DURING a
        // take rather than at a toggle, so leaving it out of the diag file would keep exactly
        // the event a founder report cannot otherwise explain — "it was working and then it
        // was not" — invisible. It also brackets the OFF/ON pair below, which now breadcrumb
        // themselves, so a re-arm reads as three lines instead of a silent gap.
        logMonitorOutcome("re-arm (\(reason))", level: .info)
        let tuneWasOn = voiceTuneEnabled
        _ = setInputMonitoring(false)
        if tuneWasOn { setVoiceTune(true) }
        _ = setInputMonitoring(true)
    }

    func attachSourceNode(_ sourceNode: AVAudioSourceNode) {
        // The master graph (masterMixer attached + connected) must exist before
        // we connect a source node into it. Idempotent — no-op once prepared.
        prepareGraph()
        let wasRunning = masterEngine.isRunning
        if wasRunning { masterEngine.pause() }
        masterEngine.attach(sourceNode)
        let format = sourceNode.outputFormat(forBus: 0)
        if format.sampleRate > 0, format.channelCount > 0 {
            masterEngine.connect(sourceNode, to: masterMixer, format: format)
            log.audio("Source node attached to master engine (\(format.sampleRate)Hz, \(format.channelCount)ch)")
        } else {
            let fallback = masterMixer.outputFormat(forBus: 0)
            if fallback.sampleRate > 0, fallback.channelCount > 0 {
                masterEngine.connect(sourceNode, to: masterMixer, format: fallback)
                log.audio("Source node attached to master engine (fallback format: \(fallback.sampleRate)Hz)")
            } else {
                log.audio("Cannot attach source node — no valid audio format available", level: .error)
                masterEngine.detach(sourceNode)
            }
        }
        if wasRunning {
            armTimingInstrument()
            restartOrDegrade(after: "source node attachment")   // #611: never a log-only catch
        }
    }

    func detachSourceNode(_ sourceNode: AVAudioSourceNode) {
        masterEngine.disconnectNodeOutput(sourceNode)
        masterEngine.detach(sourceNode)
        log.audio("Source node detached from master engine")
    }

    /// Attach an AVAudioPlayerNode additively into the master mix (same safe
    /// pause/attach/connect pattern as `attachSourceNode`). Used by AudioClipPlayer
    /// — a clip plays into `masterMixer` like any voice, never touching the master
    /// OUTPUT path. `format` is the player's buffer format (file's processing format).
    func attachPlayerNode(_ node: AVAudioPlayerNode, format: AVAudioFormat) {
        prepareGraph()
        let wasRunning = masterEngine.isRunning
        if wasRunning { masterEngine.pause() }
        masterEngine.attach(node)
        if format.sampleRate > 0, format.channelCount > 0 {
            masterEngine.connect(node, to: masterMixer, format: format)
        } else {
            let fallback = masterMixer.outputFormat(forBus: 0)
            if fallback.sampleRate > 0, fallback.channelCount > 0 {
                masterEngine.connect(node, to: masterMixer, format: fallback)
            } else {
                masterEngine.detach(node)
                log.audio("Clip player node attach aborted — no valid format", level: .error)
            }
        }
        if wasRunning {
            armTimingInstrument()
            restartOrDegrade(after: "clip player attach")   // #611: never a log-only catch
        }
        log.audio("Clip player node attached to master engine")
    }

    func detachPlayerNode(_ node: AVAudioPlayerNode) {
        if node.isPlaying { node.stop() }
        masterEngine.disconnectNodeOutput(node)
        masterEngine.detach(node)
        log.audio("Clip player node detached from master engine")
    }

    /// Attach a clip player through a time-pitch stretch node: `player → timePitch →
    /// masterMixer`. The `AVAudioUnitTimePitch` is a first-party graph node (Apple's
    /// spectral phase-vocoder) — it does its OWN rendering, so this adds no work to the
    /// render callback and never touches the master OUTPUT path (audition path only).
    /// Warp #54 Slice A: the node stays IN the chain always; the caller sets
    /// `timePitch.rate` per play (rate 1.0 = no tempo change — but the spectral node is
    /// NOT bit-transparent, it carries overlap-add latency; fine on this audition path).
    func attachPlayerNode(_ node: AVAudioPlayerNode,
                          through timePitch: AVAudioUnitTimePitch,
                          format: AVAudioFormat) {
        prepareGraph()
        let wasRunning = masterEngine.isRunning
        if wasRunning { masterEngine.pause() }
        masterEngine.attach(node)
        masterEngine.attach(timePitch)
        let fmt: AVAudioFormat? = (format.sampleRate > 0 && format.channelCount > 0)
            ? format
            : { let f = masterMixer.outputFormat(forBus: 0)
                return (f.sampleRate > 0 && f.channelCount > 0) ? f : nil }()
        if let fmt {
            masterEngine.connect(node, to: timePitch, format: fmt)
            masterEngine.connect(timePitch, to: masterMixer, format: fmt)
        } else {
            masterEngine.detach(node)
            masterEngine.detach(timePitch)
            log.audio("Warpable clip player attach aborted — no valid format", level: .error)
        }
        if wasRunning {
            armTimingInstrument()
            restartOrDegrade(after: "warpable player attach")   // #611: never a log-only catch
        }
        log.audio("Warpable clip player attached (player → timePitch → masterMixer)")
    }

    /// Detach a warpable clip player and its time-pitch node.
    func detachPlayerNode(_ node: AVAudioPlayerNode, timePitch: AVAudioUnitTimePitch) {
        if node.isPlaying { node.stop() }
        masterEngine.disconnectNodeOutput(node)
        masterEngine.disconnectNodeOutput(timePitch)
        masterEngine.detach(node)
        masterEngine.detach(timePitch)
        log.audio("Warpable clip player detached from master engine")
    }

    // MARK: - Video audio capture (mux the mix into a visual recording)

    /// Grab the last `seconds` of the master mix from RetroCapture's always-on ring
    /// buffer (max ~30 s) as a temp file, for muxing into a visual video recording.
    /// Reuses the existing mainMixerNode tap — no second tap (a tap on `outputNode`
    /// throws AVFAudio's `_isInput` assertion), and read-only on the ring so it never
    /// conflicts with LoopExporter's use of RetroCapture.
    func captureRecentMixAudio(seconds: Double) -> URL? {
        retroCapture.captureRecent(seconds: seconds)
    }

}
#endif
