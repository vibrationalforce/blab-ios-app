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
    var spatialAudioEnabled: Bool = false
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

    /// True between a deliberate `stop()` (e.g. backgrounding with nothing
    /// audible) and the next explicit `start()`. While set, ALL self-healing
    /// paths (route-loss recovery, its 300 ms settle-Task, the config-change
    /// watchdog) stand down — an intentionally stopped engine is not broken,
    /// and resurrecting it in the background would re-create the 2.5.4
    /// silent-audio state (audio-thread review 2026-07-16, findings F1/F2).
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
        /// the idle path. `AudioTimingReportGateTests`' sibling pins both directions so the
        /// case cannot quietly become equivalent to `.idleBackground`.
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

    /// Held master sample-peak / true-peak in dBFS / dBTP, and momentary
    /// loudness in LUFS — published from the master tap (EchoelMix metering).
    var masterPeakDb: Float = EchoelMeter.floorDb
    var masterTruePeakDb: Float = EchoelMeter.floorDb
    var masterLUFS: Float = EchoelLoudnessMeter.floorLUFS
    /// Full EBU R128 set: short-term (3 s) + max-hold true-peak (dBTP) + gated
    /// integrated loudness (LUFS) + loudness range (LU). Published from the tap.
    var masterLUFSShortTerm: Float = EchoelLoudnessMeter.floorLUFS
    var masterTruePeakMaxDb: Float = EchoelMeter.floorDb
    var masterLUFSIntegrated: Float = EchoelLoudnessMeter.floorLUFS
    var masterLRA: Float = 0

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
    /// Output-RMS window (MainActor) that feeds FeedbackGuard while monitoring.
    @ObservationIgnored private var monitorLevelHistory: [Float] = []
    @ObservationIgnored private var monitorPollTick = 0

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
                // A healthy engine that simply re-mapped its output needs no restart —
                // BUT the route may have switched the hardware sample rate (e.g. the
                // rPPG camera activating mid-session drops it to 44.1 kHz). Re-install
                // the RetroCapture tap so its capture sample rate tracks the NEW format;
                // otherwise a retroactive capture/export would be pitch-shifted
                // ("viel höher"). install() is idempotent (removes the old tap first).
                if self.masterEngine.isRunning {
                    self.recoveryAttempts = 0
                    self.retroCapture.install(on: self.masterEngine)
                    // The route changed under a surviving tap: the granted IO buffer may
                    // be a different size now, and the render may have gapped across the
                    // switch. Re-read the one, forget the baseline for the other (#193).
                    self.refreshRenderQuantum(fallbackSampleRate: self.sampleRate)
                    self.armTimingInstrument()
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
        masterEngine.mainMixerNode.outputVolume = 0.89   // ≈ −1.0 dBFS

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
        masterMixer.removeTap(onBus: 0)   // idempotent — drops a previous/orphaned tap
        let meterFormat = masterMixer.outputFormat(forBus: 0)
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
            masterMixer.installTap(onBus: 0, bufferSize: 1024, format: meterFormat) { @Sendable buffer, when in
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
                var rmsL: Float = 0
                vDSP_rmsqv(channelData[0], 1, &rmsL, vDSP_Length(frameLength))
                var rmsR: Float = 0
                let stereo = buffer.format.channelCount > 1
                if stereo {
                    vDSP_rmsqv(channelData[1], 1, &rmsR, vDSP_Length(frameLength))
                } else { rmsR = rmsL }
                let scaledL = rmsL.isNaN ? Float(0) : Swift.min(rmsL * 3.0, 1.0)
                let scaledR = rmsR.isNaN ? Float(0) : Swift.min(rmsR * 3.0, 1.0)
                ptrL.pointee = scaledL
                ptrR.pointee = scaledR

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
                self.masterTruePeakDb = self._truePeakDb.pointee
                self.masterLUFS = self._lufs.pointee
                self.masterLUFSShortTerm = self._lufsS.pointee
                self.masterTruePeakMaxDb = self._tpMax.pointee
                self.masterLUFSIntegrated = self._lufsI.pointee
                self.masterLRA = self._lra.pointee
                // FeedbackGuard for live input monitoring (~15 Hz, only while monitoring).
                #if os(iOS)
                self.monitorPollTick &+= 1
                if self.isInputMonitoring && self.monitorPollTick % 4 == 0 {
                    self.updateFeedbackGuard()
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

    /// Start/stop monitoring the mic through the main output with FeedbackGuard.
    /// Returns false if monitoring couldn't start (e.g. no mic permission / format).
    /// Defensive throughout — never crashes; worst case it simply doesn't engage.
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
            do { try AudioConfiguration.upgradeToPlayAndRecord() }
            catch { log.audio("Input monitoring: session upgrade failed (\(error))", level: .error) }
            let input = masterEngine.inputNode
            let inFmt = input.inputFormat(forBus: 0)
            guard inFmt.sampleRate > 0, inFmt.channelCount > 0 else {
                log.audio("Input monitoring: no valid input format (mic permission?)", level: .error)
                return false
            }
            let wasRunning = masterEngine.isRunning
            if wasRunning { masterEngine.pause() }
            if !monitorAttached { masterEngine.attach(monitorMixer); monitorAttached = true }
            monitorMixer.outputVolume = 0          // silent until connected, avoids a pop
            let outFmt = masterMixer.outputFormat(forBus: 0)
            masterEngine.connect(input, to: monitorMixer, format: inFmt)
            masterEngine.connect(monitorMixer, to: masterMixer, format: outFmt)
            monitorLevelHistory.removeAll(keepingCapacity: true)
            feedbackGuardActive = false
            if wasRunning {
                armTimingInstrument()
                do { try masterEngine.start() }
                catch {
                    log.audio("Input monitoring: engine restart failed (\(error))", level: .error)
                    masterEngine.disconnectNodeOutput(monitorMixer)
                    return false
                }
            }
            isInputMonitoring = true
            monitorMixer.outputVolume = min(max(inputMonitorGain, 0), 1)
            log.audio("Input monitoring ON (gain \(inputMonitorGain))")
            return true
        } else {
            guard isInputMonitoring else { return true }
            monitorMixer.outputVolume = 0
            masterEngine.disconnectNodeOutput(monitorMixer)
            isInputMonitoring = false
            feedbackGuardActive = false
            log.audio("Input monitoring OFF")
            return true
        }
        #else
        return false
        #endif
    }

    #if os(iOS)
    /// MainActor FeedbackGuard step (called from the meter poll while monitoring):
    /// duck the MIC monitor — not the music — when the output shows the rising-over-
    /// ceiling runaway that signals acoustic feedback. No audio-thread work, no tap.
    private func updateFeedbackGuard() {
        guard isInputMonitoring else { return }
        let level = Swift.max(_rawMeterL.pointee, _rawMeterR.pointee)
        monitorLevelHistory.append(level)
        if monitorLevelHistory.count > 8 { monitorLevelHistory.removeFirst() }
        let duckDB = FeedbackGuard.gainReductionDB(rmsHistory: monitorLevelHistory)
        let base = Swift.min(Swift.max(inputMonitorGain, 0), 1)
        let factor: Float = duckDB > 0 ? powf(10, -duckDB / 20) : 1
        monitorMixer.outputVolume = base * factor
        feedbackGuardActive = duckDB > 0
    }
    #endif

    // MARK: - Source Node Registration

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
            do { try masterEngine.start() }
            catch { log.audio("Failed to restart engine after source node attachment: \(error)", level: .error) }
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
            do { try masterEngine.start() }
            catch { log.audio("Failed to restart engine after player-node attach: \(error)", level: .error) }
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
            do { try masterEngine.start() }
            catch { log.audio("Failed to restart engine after warpable player attach: \(error)", level: .error) }
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
