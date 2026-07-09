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

    // MARK: - Self-healing recovery state (MainActor-confined)

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
        _outputRing.initialize(repeating: 0, count: AudioEngine.outputRingSize)
        _outputRingCount.initialize(to: 0)

        // Interruption / route-change handlers are cheap closure storage with no
        // audio I/O — safe to wire at init.
        AudioConfiguration.onInterruptionBegan = { [weak self] in
            self?.masterEngine.pause()
            self?.isRunning = false
            log.audio("Audio interrupted — pausing engine")
        }
        AudioConfiguration.onInterruptionResume = { [weak self] in
            log.audio("Audio interruption ended — resuming engine")
            do {
                try self?.masterEngine.start()
                self?.isRunning = true
            } catch {
                log.audio("Failed to resume master engine: \(error)", level: .error)
            }
        }
        AudioConfiguration.onRouteDeviceLost = { [weak self] in
            guard let self else { return }
            self.masterEngine.pause()
            self.isRunning = false
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
                // Engine actually stopped or we were intentionally stopped: recover only
                // if we were meant to be running.
                guard self.isRunning || self.degraded else { return }
                self.recoverEngine(reason: "engine configuration changed")
            }
        }
    }

    /// De-bounced, capped automatic restart used by route-loss and configuration
    /// changes. Control plane only — never touches the render block. On success the
    /// attempt counter resets and `degraded` clears; after `maxRecoveryAttempts`
    /// consecutive failures it surfaces `degraded` so the UI can offer a manual retry.
    private func recoverEngine(reason: String) {
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

        let meterFormat = masterMixer.outputFormat(forBus: 0)
        if meterFormat.sampleRate > 0 && meterFormat.channelCount > 0 {
            // Match the loudness windows to the real hardware rate. Safe to
            // reassign here: the meter has no tap yet, so it is untouched by any
            // other thread until installTap below.
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
                let n = Int(frameLength)
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
        log.audio("Master AVAudioEngine graph: playerNode -> masterMixer -> mainMixer -> outputNode -> hardware")
    }

    func start() {
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
        retroCapture.install(on: masterEngine)
        multiTrackRecorder.prepareForRecording(engine: masterEngine)
        autoMixChain.connectMeter { [weak self] in self?.masterLevel ?? 0 }
        isRunning = true
        // A clean start clears any prior degraded state and the recovery counter.
        degraded = false
        lastAudioError = nil
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
        _outputRing.deinitialize(count: AudioEngine.outputRingSize)
        _outputRing.deallocate()
        _outputRingCount.deinitialize(count: 1)
        _outputRingCount.deallocate()
    }

    func stop() {
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

    /// Attach a self-rendering instrument AU (any `AVAudioUnit`, e.g. a hosted
    /// AUv3 or an AVAudioUnitSampler) additively into the master mix — the exact
    /// pause→attach→connect→restart pattern of `attachSourceNode`. The AU does
    /// its own rendering; nothing is added to our render path.
    func attachInstrument(_ node: AVAudioUnit) {
        prepareGraph()
        let wasRunning = masterEngine.isRunning
        if wasRunning { masterEngine.pause() }
        masterEngine.attach(node)
        let format = node.outputFormat(forBus: 0)
        if format.sampleRate > 0, format.channelCount > 0 {
            masterEngine.connect(node, to: masterMixer, format: format)
            log.audio("Instrument AU attached to master engine (\(format.sampleRate)Hz, \(format.channelCount)ch)")
        } else {
            let fallback = masterMixer.outputFormat(forBus: 0)
            if fallback.sampleRate > 0, fallback.channelCount > 0 {
                masterEngine.connect(node, to: masterMixer, format: fallback)
                log.audio("Instrument AU attached to master engine (fallback format)")
            } else {
                // No early return — the restart below must still run or a
                // paused engine would stay paused after a failed attach.
                log.audio("Cannot attach instrument AU — no valid audio format", level: .error)
                masterEngine.detach(node)
            }
        }
        if wasRunning {
            do { try masterEngine.start() }
            catch { log.audio("Failed to restart engine after instrument attach: \(error)", level: .error) }
        }
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

    // MARK: - AUv3 Node Hosting

    /// Run graph-mutating work with the engine paused, restarting it afterwards if
    /// it was running. Pause/restart is the safe way to re-wire a live AVAudioEngine
    /// (mirrors `attachSourceNode`). The AU does its own rendering — no work is added
    /// to the render path here.
    func withGraphPaused(_ body: () -> Void) {
        prepareGraph()
        let wasRunning = masterEngine.isRunning
        if wasRunning { masterEngine.pause() }
        body()
        if wasRunning {
            do { try masterEngine.start() }
            catch { log.audio("Failed to restart engine after AUv3 re-wire: \(error)", level: .error) }
        }
    }

    /// Attach a hosted AU into the graph (no connections yet). Call inside
    /// `withGraphPaused`. Idempotent-safe only if the caller tracks attach state.
    func attachAU(_ node: AVAudioUnit) { masterEngine.attach(node) }

    /// Disconnect a hosted AU's output and detach it. Call inside `withGraphPaused`.
    func detachAU(_ node: AVAudioUnit) {
        masterEngine.disconnectNodeOutput(node)
        masterEngine.detach(node)
    }

    /// Drop a hosted AU's current output connection (to re-route it). Inside pause.
    func disconnectAUOutput(_ node: AVAudioUnit) { masterEngine.disconnectNodeOutput(node) }

    /// One canonical format for the whole hosted AU chain — the master mixer's
    /// (stereo, hardware rate). Driving every link from a single format avoids
    /// channel-count mismatches between a mono instrument and a stereo effect, and
    /// avoids reading an un-negotiated node's `outputFormat` before it's connected.
    private var auChainFormat: AVAudioFormat? {
        let f = masterMixer.outputFormat(forBus: 0)
        return (f.sampleRate > 0 && f.channelCount > 0) ? f : nil
    }

    /// Connect one hosted AU's output into another's input (instrument → effect).
    func connectAU(_ from: AVAudioUnit, to dest: AVAudioUnit) {
        guard let format = auChainFormat else {
            log.audio("Cannot connect AUv3 chain — no valid format", level: .error); return
        }
        masterEngine.connect(from, to: dest, format: format)
    }

    /// Connect a hosted AU's output to the master mixer (chain endpoint).
    func connectAUToMaster(_ node: AVAudioUnit) {
        guard let format = auChainFormat else {
            log.audio("Cannot connect AUv3 node to master — no valid format", level: .error); return
        }
        masterEngine.connect(node, to: masterMixer, format: format)
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

    /// One canonical format for the master-bus FX path — the main mixer's output
    /// (post AutoMixChain, what actually feeds the hardware). Valid-or-nil.
    private var masterFXFormat: AVAudioFormat? {
        let f = masterEngine.mainMixerNode.outputFormat(forBus: 0)
        return (f.sampleRate > 0 && f.channelCount > 0) ? f : nil
    }

    /// Master-bus FX: insert hosted AU effects between the main mixer and the output,
    /// so they process the ENTIRE Echoel mix (mainMixer → fx[0] → … → fx[n] → output).
    /// Passing an EMPTY array restores the direct mainMixer → output connection (the
    /// default). The units must already be attached (`attachAU`); call inside
    /// `withGraphPaused`. NB: only ever called when the master chain CHANGES, so a
    /// build with no master FX never touches the default output wiring (zero-risk).
    func rewireMasterFX(_ units: [AVAudioUnit]) {
        let main = masterEngine.mainMixerNode
        let out = masterEngine.outputNode
        let fmt = masterFXFormat
        // Drop the main mixer's current output (the implicit main→output link, or a
        // previous master-FX link) and every master-FX node's output, then relink.
        masterEngine.disconnectNodeOutput(main)
        for u in units { masterEngine.disconnectNodeOutput(u) }
        guard !units.isEmpty else {
            masterEngine.connect(main, to: out, format: fmt)   // restore default
            log.audio("Master-bus FX cleared — main mixer → output restored")
            return
        }
        var prev: AVAudioNode = main
        for u in units {
            masterEngine.connect(prev, to: u, format: fmt)
            prev = u
        }
        masterEngine.connect(prev, to: out, format: fmt)
        log.audio("Master-bus FX chain wired (\(units.count) effect\(units.count == 1 ? "" : "s"))")
    }
}
#endif
