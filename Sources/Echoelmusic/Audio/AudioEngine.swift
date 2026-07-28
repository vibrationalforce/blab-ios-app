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
    @ObservationIgnored private var intentionallyStopped = false

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
        Self.shouldResumeOnForeground(cameFromBackground: cameFromBackground,
                                      wasBackgrounded: wasBackgrounded,
                                      wasInterrupted: wasInterrupted,
                                      intentionallyStopped: intentionallyStopped)
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
            masterMixer.installTap(onBus: 0, bufferSize: 1024, format: meterFormat) { @Sendable buffer, _ in
                guard let channelData = buffer.floatChannelData else { return }
                let frameLength = UInt(buffer.frameLength)
                guard frameLength > 0 else { return }
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
        intentionallyStopped = false
        // Ensure the session + graph exist before starting, regardless of caller
        // (startup task, scenePhase .active, or route-change recovery).
        prepareGraph()
        if !masterEngine.isRunning {
            masterEngine.prepare()
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

    private func startMeterPollTimer() {
        meterPollTimer?.invalidate()
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
    }

    func stop() {
        // Deliberate stop (e.g. backgrounding with nothing audible, 2.5.4): the
        // self-healing paths must NOT resurrect the engine — an in-flight
        // recoverEngine settle-Task or a late config-change notification would
        // otherwise restart it in the background, re-creating the silent-audio
        // state the caller just removed (audio-thread review 2026-07-16, F1/F2).
        intentionallyStopped = true
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
