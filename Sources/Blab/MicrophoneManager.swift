import AVFoundation
import SwiftUI
import Accelerate

// MARK: - Supporting Types

/// Helper that maintains an exponential moving average with separate attack
/// and release constants. Used to smooth amplitude updates before they hit the
/// UI or downstream biofeedback processors.
private struct AmplitudeSmoother {
    var attackTime: Double
    var releaseTime: Double
    private(set) var sampleRate: Double
    private var currentValue: Float = 0

    init(attackTime: Double, releaseTime: Double, sampleRate: Double) {
        self.attackTime = attackTime
        self.releaseTime = releaseTime
        self.sampleRate = sampleRate
    }

    mutating func reset(sampleRate: Double) {
        self.sampleRate = sampleRate
        currentValue = 0
    }

    mutating func process(level: Float, frameCount: Int) -> Float {
        guard sampleRate > 0 else { return level }

        let blockDuration = Double(frameCount) / sampleRate
        let attackCoeff = exp(-blockDuration / max(attackTime, 0.0001))
        let releaseCoeff = exp(-blockDuration / max(releaseTime, 0.0001))

        if level > currentValue {
            currentValue = attackCoeff * currentValue + (1 - attackCoeff) * level
        } else {
            currentValue = releaseCoeff * currentValue + (1 - releaseCoeff) * level
        }

        return currentValue
    }
}

/// Scratch buffers that are reused for FFT processing to avoid per-frame
/// allocations. All arrays are sized for the configured FFT size and lazily
/// resized if needed.
private final class FFTScratch {
    private(set) var size: Int
    private(set) var visualBins: Int
    var real: [Float]
    var imag: [Float]
    var window: [Float]
    var magnitudes: [Float]
    var visualMagnitudes: [Float]

    init(size: Int, visualBins: Int) {
        self.size = size
        self.visualBins = visualBins
        self.real = [Float](repeating: 0, count: size)
        self.imag = [Float](repeating: 0, count: size)
        self.window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&self.window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        self.magnitudes = [Float](repeating: 0, count: size / 2)
        self.visualMagnitudes = [Float](repeating: 0, count: visualBins)
    }

    func ensure(size: Int, visualBins: Int) {
        if size != self.size {
            self.size = size
            real = [Float](repeating: 0, count: size)
            imag = [Float](repeating: 0, count: size)
            window = [Float](repeating: 0, count: size)
            vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
            magnitudes = [Float](repeating: 0, count: size / 2)
        }

        if visualBins != self.visualBins {
            self.visualBins = visualBins
            visualMagnitudes = [Float](repeating: 0, count: visualBins)
        }
    }
}

/// Manages microphone access and advanced audio processing
/// Now includes FFT for frequency detection and professional-grade DSP
class MicrophoneManager: NSObject, ObservableObject {

    /// Metrics representing the state of a single audio input channel.
    struct ChannelMetrics: Identifiable, Equatable {
        let id: UUID
        let kind: AudioGraph.InputKind
        let name: String
        var amplitude: Float
        var peakAmplitude: Float
        var frequency: Float
        var pitch: Float
        var clarity: Float
        var updatedAt: Date
    }

    // MARK: - Published Properties

    /// Current audio level (0.0 to 1.0)
    @Published var audioLevel: Float = 0.0

    /// Detected frequency in Hz (fundamental pitch from FFT)
    @Published var frequency: Float = 0.0

    /// Current pitch in Hz (fundamental frequency from YIN algorithm)
    @Published var currentPitch: Float = 0.0

    /// Whether we have microphone permission
    @Published var hasPermission: Bool = false

    /// Whether we're currently recording
    @Published var isRecording: Bool = false

    /// Audio buffer for waveform visualization (last 512 samples)
    @Published var audioBuffer: [Float]? = nil

    /// FFT magnitudes for spectral visualization (256 bins)
    @Published var fftMagnitudes: [Float]? = nil

    /// Per-input metrics for multi-source processing chains.
    @Published private(set) var channelMetrics: [ChannelMetrics] = []


    // MARK: - Private Properties

    /// The audio engine that processes audio input
    private var audioEngine: AVAudioEngine?

    /// The input node that captures microphone data
    private var inputNode: AVAudioInputNode?

    /// FFT setup for frequency analysis
    private var fftSetup: vDSP_DFT_Setup?

    /// Buffer size for FFT (power of 2)
    private let fftSize = 2048

    /// Sample rate (will be set from audio format)
    private var sampleRate: Double = 44100.0

    /// YIN pitch detector for fundamental frequency estimation
    private let pitchDetector = PitchDetector()

    /// Shared audio graph when the microphone manager is used alongside the
    /// modular `AudioGraph` builder. When `nil` the manager falls back to its
    /// internal `AVAudioEngine` instance.
    private var sharedGraph: AudioGraph?

    /// Handle for the microphone channel within the shared audio graph.
    private var microphoneChannel: AudioGraph.InputChannel?

    /// Stable identifier used when running the manager without a shared graph.
    private let localMicrophoneChannelID = UUID()

    /// Currently active identifier for the microphone channel.
    private var microphoneChannelID: UUID?

    /// Metrics cache keyed by channel identifier.
    private var channelMetricsMap: [UUID: ChannelMetrics] = [:]

    /// Peak hold values per channel.
    private var peakHold: [UUID: Float] = [:]

    /// Cached identifiers for transient external input sources.
    private var transientChannelIDs: [AudioGraph.InputKind: UUID] = [:]

    /// Processing queue used to avoid heavy DSP work on the main thread.
    private let processingQueue = DispatchQueue(
        label: "com.blab.microphone.processing",
        qos: .userInteractive
    )

    /// Scratch buffers shared across FFT calls.
    private let scratchBuffers = FFTScratch(size: 2048, visualBins: 256)

    /// Buffer used for waveform capture (reused between frames).
    private var waveformBuffer = [Float](repeating: 0, count: 512)

    /// RMS smoother for amplitude updates.
    private var amplitudeSmoother = AmplitudeSmoother(
        attackTime: 0.02,
        releaseTime: 0.15,
        sampleRate: 44100
    )


    // MARK: - Initialization

    override init() {
        super.init()
        checkPermission()
        microphoneChannelID = localMicrophoneChannelID
        channelMetricsMap[localMicrophoneChannelID] = ChannelMetrics(
            id: localMicrophoneChannelID,
            kind: .microphone,
            name: AudioGraph.InputKind.microphone.displayName,
            amplitude: 0,
            peakAmplitude: 0,
            frequency: 0,
            pitch: 0,
            clarity: 0,
            updatedAt: Date()
        )
        channelMetrics = Array(channelMetricsMap.values)
    }


    // MARK: - Permission Handling

    /// Check if we already have microphone permission
    private func checkPermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            hasPermission = true
        case .denied, .undetermined:
            hasPermission = false
        @unknown default:
            hasPermission = false
        }
    }

    /// Request microphone permission from the user
    func requestPermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.hasPermission = granted
                if granted {
                    print("✅ Microphone permission granted")
                } else {
                    print("❌ Microphone permission denied")
                }
            }
        }
    }


    // MARK: - Recording Control

    /// Attach the microphone manager to a shared audio graph so that recording
    /// and analysis can reuse the app-wide engine.
    func attach(to audioGraph: AudioGraph) {
        var graph = audioGraph

        do {
            let channel = try graph.registerInput(node: audioGraph.input, kind: .microphone)
            sharedGraph = graph
            microphoneChannel = channel
            microphoneChannelID = channel.id

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.channelMetricsMap[channel.id] = ChannelMetrics(
                    id: channel.id,
                    kind: channel.kind,
                    name: channel.kind.displayName,
                    amplitude: 0,
                    peakAmplitude: 0,
                    frequency: 0,
                    pitch: 0,
                    clarity: 0,
                    updatedAt: Date()
                )
                self.publishChannelMetrics()
            }
        } catch {
            print("⚠️ Failed to attach microphone to shared graph: \(error)")
        }
    }

    /// Remove the microphone channel from an attached audio graph.
    func detachFromAudioGraph() {
        if var graph = sharedGraph, let channel = microphoneChannel {
            graph.removeInput(channel)
        }

        sharedGraph = nil
        microphoneChannel = nil
        microphoneChannelID = localMicrophoneChannelID
    }

    /// Start recording audio from the microphone
    func startRecording() {
        guard hasPermission else {
            print("⚠️ Cannot start recording: No microphone permission")
            requestPermission()
            return
        }

        if let graph = sharedGraph, let channel = microphoneChannel {
            let format = graph.input.outputFormat(forBus: 0)
            sampleRate = format.sampleRate
            configureFFT(for: sampleRate)

            graph.installTap(on: channel, bufferSize: UInt32(fftSize), format: format) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer, channelID: channel.id, kind: channel.kind)
            }

            do {
                try graph.start()
                DispatchQueue.main.async { [weak self] in
                    self?.isRecording = true
                }
            } catch {
                print("❌ Failed to start shared audio graph: \(error)")
                DispatchQueue.main.async { [weak self] in
                    self?.isRecording = false
                }
            }

            return
        }

        do {
            // Configure the audio session for recording
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setActive(true)

            // Create and configure the audio engine
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else { return }

            inputNode = audioEngine.inputNode

            // Get the input format from the microphone
            let recordingFormat = inputNode?.outputFormat(forBus: 0)
            guard let format = recordingFormat else { return }

            // Store sample rate for frequency calculation
            sampleRate = format.sampleRate
            configureFFT(for: sampleRate)

            // Setup FFT
            fftSetup = vDSP_DFT_zop_CreateSetup(
                nil,
                vDSP_Length(fftSize),
                vDSP_DFT_Direction.FORWARD
            )

            // Install a tap to capture audio data
            inputNode?.installTap(onBus: 0, bufferSize: UInt32(fftSize), format: format) { [weak self] buffer, _ in
                guard let self = self else { return }
                self.processAudioBuffer(buffer, channelID: self.localMicrophoneChannelID, kind: .microphone)
            }

            // Prepare and start the audio engine
            audioEngine.prepare()
            try audioEngine.start()

            DispatchQueue.main.async {
                self.isRecording = true
            }

            print("🎙️ Recording started with FFT enabled")

        } catch {
            print("❌ Failed to start recording: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isRecording = false
            }
        }
    }

    /// Stop recording audio
    func stopRecording() {
        if let graph = sharedGraph, let channel = microphoneChannel {
            graph.removeTap(from: channel)
        }

        // Safely stop the local audio engine if used
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }

        audioEngine = nil
        inputNode = nil

        // Destroy FFT setup
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
            fftSetup = nil
        }

        // Deactivate the audio session
        try? AVAudioSession.sharedInstance().setActive(false)

        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0.0
            self.frequency = 0.0
            self.currentPitch = 0.0
        }

        print("⏹️ Recording stopped")
    }


    // MARK: - Audio Processing with FFT

    /// Prepare FFT scratch buffers when the sample rate changes.
    private func configureFFT(for sampleRate: Double) {
        amplitudeSmoother.reset(sampleRate: sampleRate)
        scratchBuffers.ensure(size: fftSize, visualBins: 256)
    }

    /// Process incoming audio data with FFT for frequency detection
    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        channelID: UUID,
        kind: AudioGraph.InputKind
    ) {
        processingQueue.async { [weak self] in
            guard let self = self, let channelData = buffer.floatChannelData else { return }

            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            let channelPointer = channelData.pointee

            // Calculate RMS using vDSP for efficiency
            var sum: Float = 0
            vDSP_sve(channelPointer, 1, &sum, vDSP_Length(frameLength))
            let mean = sum / Float(frameLength)

            var sumSquares: Float = 0
            vDSP_vsq(channelPointer, 1, &sumSquares, vDSP_Length(frameLength))
            let rms = sqrt(sumSquares / Float(frameLength) - mean * mean)
            let normalizedLevel = min(rms * 15.0, 1.0)

            let smoothedLevel = self.amplitudeSmoother.process(level: normalizedLevel, frameCount: frameLength)

            // Capture waveform snapshot
            let bufferSampleCount = min(self.waveformBuffer.count, frameLength)
            cblas_scopy(Int32(bufferSampleCount), channelPointer, 1, &self.waveformBuffer, 1)
            let waveformSnapshot = Array(self.waveformBuffer.prefix(bufferSampleCount))

            // Perform FFT and pitch detection
            let (detectedFrequency, magnitudes, _, clarity) = self.performFFT(
                on: channelPointer,
                frameLength: frameLength
            )

            let detectedPitch = self.pitchDetector.detectPitch(
                buffer: buffer,
                sampleRate: Float(self.sampleRate)
            )

            // Peak hold for metering
            let decayedPeak = (self.peakHold[channelID] ?? 0) * 0.92
            let peak = max(decayedPeak, smoothedLevel)
            self.peakHold[channelID] = peak

            let metrics = ChannelMetrics(
                id: channelID,
                kind: kind,
                name: kind.displayName,
                amplitude: smoothedLevel,
                peakAmplitude: peak,
                frequency: detectedFrequency,
                pitch: detectedPitch,
                clarity: clarity,
                updatedAt: Date()
            )

            let spectralSnapshot = magnitudes

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                if channelID == self.microphoneChannelID {
                    self.audioLevel = self.audioLevel * 0.6 + smoothedLevel * 0.4

                    if detectedFrequency > 50 {
                        self.frequency = self.frequency * 0.8 + detectedFrequency * 0.2
                    }

                    if detectedPitch > 0 {
                        self.currentPitch = self.currentPitch * 0.8 + detectedPitch * 0.2
                    } else {
                        self.currentPitch *= 0.9
                    }

                    self.audioBuffer = waveformSnapshot
                    self.fftMagnitudes = spectralSnapshot
                }

                self.channelMetricsMap[channelID] = metrics
                self.publishChannelMetrics()
            }
        }
    }

    /// Perform FFT to detect fundamental frequency and return magnitudes
    private func performFFT(on data: UnsafePointer<Float>, frameLength: Int) -> (frequency: Float, magnitudes: [Float], peak: Float, clarity: Float) {
        guard let setup = fftSetup else { return (0, [], 0, 0) }

        scratchBuffers.ensure(size: fftSize, visualBins: 256)

        let copyLength = min(frameLength, fftSize)

        var resolvedFrequency: Float = 0
        var resolvedPeak: Float = 0
        var resolvedClarity: Float = 0

        scratchBuffers.real.withUnsafeMutableBufferPointer { realPtr in
            scratchBuffers.imag.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else { return }

                realPtr.initialize(repeating: 0)
                imagPtr.initialize(repeating: 0)
                cblas_scopy(Int32(copyLength), data, 1, realBase, 1)

                scratchBuffers.window.withUnsafeBufferPointer { windowPtr in
                    if let windowBase = windowPtr.baseAddress {
                        vDSP_vmul(realBase, 1, windowBase, 1, realBase, 1, vDSP_Length(fftSize))
                    }
                }

                vDSP_DFT_Execute(setup, realBase, imagBase, realBase, imagBase)

                let halfSize = fftSize / 2
                var maxMagnitude: Float = 0
                var maxIndex = 0
                var totalEnergy: Float = 0

                for i in 0..<halfSize {
                    let real = realBase[i]
                    let imag = imagBase[i]
                    let magnitude = hypot(real, imag)
                    scratchBuffers.magnitudes[i] = magnitude
                    totalEnergy += magnitude

                    if magnitude > maxMagnitude {
                        maxMagnitude = magnitude
                        maxIndex = i
                    }
                }

                let binRatio = max(1, halfSize / scratchBuffers.visualMagnitudes.count)
                for i in 0..<scratchBuffers.visualMagnitudes.count {
                    let start = i * binRatio
                    let end = min(start + binRatio, halfSize)
                    var sum: Float = 0
                    for j in start..<end {
                        sum += scratchBuffers.magnitudes[j]
                    }
                    scratchBuffers.visualMagnitudes[i] = sum / Float(max(1, end - start))
                }

                resolvedFrequency = Float(maxIndex) * Float(sampleRate) / Float(fftSize)
                resolvedPeak = maxMagnitude
                resolvedClarity = totalEnergy > 0 ? maxMagnitude / totalEnergy : 0
            }
        }

        let magnitudes = Array(scratchBuffers.visualMagnitudes)
        return (resolvedFrequency, magnitudes, resolvedPeak, resolvedClarity)
    }


    // MARK: - Channel Management Helpers

    /// Register a channel in the metrics map if it does not already exist.
    private func registerChannelIfNeeded(id: UUID, kind: AudioGraph.InputKind) {
        if channelMetricsMap[id] != nil { return }

        channelMetricsMap[id] = ChannelMetrics(
            id: id,
            kind: kind,
            name: kind.displayName,
            amplitude: 0,
            peakAmplitude: 0,
            frequency: 0,
            pitch: 0,
            clarity: 0,
            updatedAt: Date()
        )
        publishChannelMetrics()
    }

    /// Publish the current metrics to subscribers in a deterministic order.
    private func publishChannelMetrics() {
        channelMetrics = channelMetricsMap.values.sorted { lhs, rhs in
            if lhs.name == rhs.name {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.name < rhs.name
        }
    }

    /// Allow external audio sources (virtual instruments, BLE sensors, etc.) to
    /// reuse the microphone manager's analysis pipeline.
    func processExternalBuffer(
        _ buffer: AVAudioPCMBuffer,
        kind: AudioGraph.InputKind,
        identifier: UUID? = nil
    ) {
        var channelID: UUID

        if let identifier {
            channelID = identifier
        } else if let existing = transientChannelIDs[kind] {
            channelID = existing
        } else {
            let newID = UUID()
            transientChannelIDs[kind] = newID
            channelID = newID

            DispatchQueue.main.async { [weak self] in
                self?.registerChannelIfNeeded(id: newID, kind: kind)
            }
        }

        if identifier != nil {
            DispatchQueue.main.async { [weak self] in
                self?.registerChannelIfNeeded(id: channelID, kind: kind)
            }
        }

        processAudioBuffer(buffer, channelID: channelID, kind: kind)
    }


    // MARK: - Cleanup

    /// Clean up when the object is destroyed
    deinit {
        stopRecording()
    }
}
