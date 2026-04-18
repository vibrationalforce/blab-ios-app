#if canImport(AVFoundation)
import Foundation
import AVFoundation
import Combine
import Accelerate
import Observation

/// Central audio engine for bio-reactive soundscape generation
@MainActor
@Observable
public final class AudioEngine {

    // MARK: - Observed Properties

    var isRunning: Bool = false
    var spatialAudioEnabled: Bool = false
    var inputMonitoringEnabled: Bool = false
    var masterLevel: Float = 0.0
    var masterLevelR: Float = 0.0

    @ObservationIgnored nonisolated(unsafe) private let _rawMeterL = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    @ObservationIgnored nonisolated(unsafe) private let _rawMeterR = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    @ObservationIgnored nonisolated(unsafe) private var meterPollTimer: Timer?

    /// Retroactive capture — always-recording ring buffer + on-demand disk writer.
    let retroCapture = RetroCapture()

    /// Master mastering chain — EQ + compression + limiting + auto-LUFS.
    let autoMixChain = AutoMixChain()

    /// RTMP live stream output — audio to YouTube/Twitch.
    let liveStream = LiveStreamEngine()

    /// LUFS-normalized mastering + export (WAV/AAC) for completed sessions.
    let singleExport = SingleExport()

    @ObservationIgnored private let masterEngine = AVAudioEngine()
    @ObservationIgnored private let masterMixer = AVAudioMixerNode()
    @ObservationIgnored private let masterPlayerNode = AVAudioPlayerNode()

    var masterVolume: Float = 0.85 {
        didSet { masterMixer.outputVolume = masterVolume }
    }

    let microphoneManager: MicrophoneManager
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    convenience init() {
        self.init(microphoneManager: MicrophoneManager())
    }

    init(microphoneManager: MicrophoneManager) {
        self.microphoneManager = microphoneManager
        _rawMeterL.initialize(to: 0)
        _rawMeterR.initialize(to: 0)

        do {
            try AudioConfiguration.configureAudioSession()
            AudioConfiguration.registerInterruptionHandlers()
            log.audio(AudioConfiguration.latencyStats())
        } catch {
            log.audio("Failed to configure audio session: \(error)", level: .warning)
        }

        AudioConfiguration.setAudioThreadPriority()
        setupMasterEngine()

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.start()
            }
        }

        log.audio("AudioEngine initialized — master output wired to hardware")
        log.audio("   Master Engine: \(masterEngine.isRunning ? "Running" : "Ready")")
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
        // Insert AutoMixChain: masterMixer → EQ → Compressor → Limiter → mainMixerNode
        autoMixChain.insert(
            into: masterEngine,
            from: masterMixer,
            to: masterEngine.mainMixerNode,
            format: processingFormat
        )
        masterMixer.outputVolume = masterVolume
        masterEngine.mainMixerNode.outputVolume = 1.0

        let meterFormat = masterMixer.outputFormat(forBus: 0)
        if meterFormat.sampleRate > 0 && meterFormat.channelCount > 0 {
            let ptrL = _rawMeterL
            let ptrR = _rawMeterR
            masterMixer.installTap(onBus: 0, bufferSize: 1024, format: meterFormat) { @Sendable buffer, _ in
                guard let channelData = buffer.floatChannelData else { return }
                let frameLength = UInt(buffer.frameLength)
                guard frameLength > 0 else { return }
                var rmsL: Float = 0
                vDSP_rmsqv(channelData[0], 1, &rmsL, vDSP_Length(frameLength))
                var rmsR: Float = 0
                if buffer.format.channelCount > 1 {
                    vDSP_rmsqv(channelData[1], 1, &rmsR, vDSP_Length(frameLength))
                } else { rmsR = rmsL }
                let scaledL = rmsL.isNaN ? Float(0) : Swift.min(rmsL * 3.0, 1.0)
                let scaledR = rmsR.isNaN ? Float(0) : Swift.min(rmsR * 3.0, 1.0)
                ptrL.pointee = scaledL
                ptrR.pointee = scaledR
            }
        }
        log.audio("Master AVAudioEngine graph: playerNode -> masterMixer -> mainMixer -> outputNode -> hardware")
    }

    func start() {
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
                    return
                }
            }
        }
        if inputMonitoringEnabled { microphoneManager.startRecording() }
        startMeterPollTimer()
        retroCapture.install(on: masterEngine)
        autoMixChain.connectMeter { [weak self] in self?.masterLevel ?? 0 }
        isRunning = true
        log.audio("AudioEngine started (production mode) — output: \(currentOutputDescription)")
    }

    private func startMeterPollTimer() {
        meterPollTimer?.invalidate()
        let ptrL = _rawMeterL
        let ptrR = _rawMeterR
        meterPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let decayCoeff: Float = 0.92
                self.masterLevel = Swift.max(ptrL.pointee, self.masterLevel * decayCoeff)
                self.masterLevelR = Swift.max(ptrR.pointee, self.masterLevelR * decayCoeff)
            }
        }
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
        _rawMeterL.deinitialize(count: 1)
        _rawMeterL.deallocate()
        _rawMeterR.deinitialize(count: 1)
        _rawMeterR.deallocate()
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

    // MARK: - Source Node Registration

    func attachSourceNode(_ sourceNode: AVAudioSourceNode) {
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
}
#endif
