import AVFoundation
import SwiftUI
import Accelerate

/// Manages microphone access and advanced audio processing
/// Now includes FFT for frequency detection and professional-grade DSP
class MicrophoneManager: NSObject, ObservableObject {

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


    // MARK: - Initialization

    override init() {
        super.init()
        checkPermission()
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

    /// Start recording audio from the microphone
    func startRecording() {
        guard hasPermission else {
            print("⚠️ Cannot start recording: No microphone permission")
            requestPermission()
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

            // Setup FFT
            fftSetup = vDSP_DFT_zop_CreateSetup(
                nil,
                vDSP_Length(fftSize),
                vDSP_DFT_Direction.FORWARD
            )

            // Install a tap to capture audio data
            inputNode?.installTap(onBus: 0, bufferSize: UInt32(fftSize), format: format) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
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
        // Safely stop the audio engine
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

    /// Process incoming audio data with FFT for frequency detection
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        let channelDataValue = channelData.pointee

        // Calculate RMS (amplitude/volume)
        var sum: Float = 0.0
        vDSP_sve(channelDataValue, 1, &sum, vDSP_Length(frameLength))
        let mean = sum / Float(frameLength)

        var sumSquares: Float = 0.0
        var meanNegative = -mean
        vDSP_vsq(channelDataValue, 1, &sumSquares, vDSP_Length(frameLength))
        let rms = sqrt(sumSquares / Float(frameLength) - mean * mean)

        // Normalize to 0-1 range with better sensitivity
        let normalizedLevel = min(rms * 15.0, 1.0)

        // Capture audio buffer for waveform visualization (last 512 samples)
        let bufferSampleCount = min(512, frameLength)
        var capturedBuffer = [Float](repeating: 0, count: bufferSampleCount)
        cblas_scopy(Int32(bufferSampleCount), channelDataValue, 1, &capturedBuffer, 1)

        // Perform FFT for frequency detection and get magnitudes
        let (detectedFrequency, magnitudes) = performFFT(on: channelDataValue, frameLength: frameLength)

        // Perform YIN pitch detection for fundamental frequency
        let detectedPitch = pitchDetector.detectPitch(buffer: buffer, sampleRate: Float(sampleRate))

        // Update UI on main thread with smoothing
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Smooth audio level changes
            self.audioLevel = self.audioLevel * 0.7 + normalizedLevel * 0.3

            // Smooth frequency changes (only update if significantly different)
            if detectedFrequency > 50 { // Ignore very low frequencies (likely noise)
                self.frequency = self.frequency * 0.8 + detectedFrequency * 0.2
            }

            // Smooth pitch changes (YIN is more robust than FFT for voice)
            if detectedPitch > 0 {
                self.currentPitch = self.currentPitch * 0.8 + detectedPitch * 0.2
            } else {
                // Decay pitch to zero if no pitch detected
                self.currentPitch *= 0.9
            }

            // Update audio buffer and FFT magnitudes for visualizations
            self.audioBuffer = capturedBuffer
            self.fftMagnitudes = magnitudes
        }
    }

    /// Perform FFT to detect fundamental frequency and return magnitudes
    private func performFFT(on data: UnsafePointer<Float>, frameLength: Int) -> (frequency: Float, magnitudes: [Float]) {
        guard let setup = fftSetup else { return (0, []) }

        // Prepare buffers
        var realParts = [Float](repeating: 0, count: fftSize)
        var imagParts = [Float](repeating: 0, count: fftSize)

        // Copy audio data to real parts (pad with zeros if needed)
        let copyLength = min(frameLength, fftSize)
        for i in 0..<copyLength {
            realParts[i] = data[i]
        }

        // Apply Hann window to reduce spectral leakage
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(realParts, 1, window, 1, &realParts, 1, vDSP_Length(fftSize))

        // Perform FFT
        vDSP_DFT_Execute(setup, &realParts, &imagParts, &realParts, &imagParts)

        // Calculate magnitudes (power spectrum)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        for i in 0..<(fftSize / 2) {
            magnitudes[i] = sqrt(realParts[i] * realParts[i] + imagParts[i] * imagParts[i])
        }

        // Downsample magnitudes for visualization (256 bins for spectral mode)
        let visualBins = 256
        var visualMagnitudes = [Float](repeating: 0, count: visualBins)
        let binRatio = magnitudes.count / visualBins
        for i in 0..<visualBins {
            let startIdx = i * binRatio
            let endIdx = min(startIdx + binRatio, magnitudes.count)
            var sum: Float = 0
            for j in startIdx..<endIdx {
                sum += magnitudes[j]
            }
            visualMagnitudes[i] = sum / Float(binRatio)
        }

        // Find peak frequency (ignore DC component at index 0)
        var maxMagnitude: Float = 0
        var maxIndex: vDSP_Length = 0

        vDSP_maxvi(Array(magnitudes[1...]), 1, &maxMagnitude, &maxIndex, vDSP_Length(magnitudes.count - 1))
        maxIndex += 1 // Adjust for skipping index 0

        // Convert bin index to frequency
        let frequency = Float(maxIndex) * Float(sampleRate) / Float(fftSize)

        // Only return frequencies in audible/useful range
        if frequency > 50 && frequency < 2000 && maxMagnitude > 0.01 {
            return (frequency, visualMagnitudes)
        }

        return (0.0, visualMagnitudes)
    }


    // MARK: - Cleanup

    /// Clean up when the object is destroyed
    deinit {
        stopRecording()
    }
}
