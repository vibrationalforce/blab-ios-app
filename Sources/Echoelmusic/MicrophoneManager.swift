#if canImport(AVFoundation)
import AVFoundation
import SwiftUI
import Accelerate
import Observation

/// Manages microphone access and advanced audio processing
/// Now includes FFT for frequency detection and professional-grade DSP
@MainActor
@Observable
final class MicrophoneManager: NSObject {

    // MARK: - Observed Properties

    /// Current audio level (0.0 to 1.0)
    var audioLevel: Float = 0.0

    /// Detected frequency in Hz (fundamental pitch from FFT)
    var frequency: Float = 0.0

    /// Current pitch in Hz (fundamental frequency from YIN algorithm)
    var currentPitch: Float = 0.0

    /// Whether we have microphone permission
    var hasPermission: Bool = false

    /// Whether the user explicitly denied microphone permission
    var permissionDenied: Bool = false

    /// Whether we're currently recording
    var isRecording: Bool = false

    /// Audio buffer for waveform visualization (last 512 samples)
    var audioBuffer: [Float]? = nil

    /// FFT magnitudes for spectral visualization (256 bins)
    var fftMagnitudes: [Float]? = nil


    // MARK: - Private Properties

    /// The audio engine that processes audio input
    @ObservationIgnored nonisolated(unsafe) private var audioEngine: AVAudioEngine?

    /// The input node that captures microphone data
    @ObservationIgnored private var inputNode: AVAudioInputNode?

    /// FFT setup for frequency analysis
    private var complexDFT: EchoelComplexDFT?

    /// Buffer size for FFT (power of 2)
    /// Reduced from 2048 to 1024 for lower latency (46ms → 23ms)
    /// Trade-off: frequency resolution 21.5Hz → 43Hz per bin (still acceptable)
    private let fftSize = 1024

    /// Sample rate (will be set from audio format)
    private var sampleRate: Double = AudioConfiguration.preferredSampleRate

    /// Pitch detection disabled (PitchDetector removed in soundscape refactor)

    /// Dedicated queue for FFT/pitch processing — keeps audio render thread unblocked
    private let processingQueue = DispatchQueue(label: "com.echoelmusic.audio.processing", qos: .userInteractive)

    // MARK: - Pre-allocated FFT Buffers (avoid per-callback allocation)

    /// Pre-allocated buffers for FFT processing — reused every callback
    private var fftRealParts: [Float]
    private var fftWindow: [Float]
    private var fftWindowedParts: [Float]
    private var fftImagZeros: [Float]
    private var fftMagnitudesBuffer: [Float]
    private var fftVisualMagnitudes: [Float]
    private var capturedBufferStorage: [Float]

    // MARK: - Initialization

    override init() {
        // Pre-allocate FFT buffers to avoid per-callback heap allocation
        self.fftRealParts = [Float](repeating: 0, count: fftSize)
        self.fftWindow = [Float](repeating: 0, count: fftSize)
        self.fftWindowedParts = [Float](repeating: 0, count: fftSize)
        self.fftImagZeros = [Float](repeating: 0, count: fftSize)
        self.fftMagnitudesBuffer = [Float](repeating: 0, count: fftSize / 2)
        self.fftVisualMagnitudes = [Float](repeating: 0, count: 256)
        self.capturedBufferStorage = [Float](repeating: 0, count: 512)

        super.init()

        // Pre-compute Hann window once (never changes)
        vDSP_hann_window(&fftWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        checkPermission()
    }


    // MARK: - Permission Handling

    /// Check if we already have microphone permission
    private func checkPermission() {
        #if os(macOS)
        hasPermission = false // macOS handles mic permission via system dialog on first use
        #elseif os(watchOS) || os(tvOS)
        hasPermission = false
        #else
        if #available(iOS 17.0, *) {
            hasPermission = AVAudioApplication.shared.recordPermission == .granted
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                hasPermission = true
            case .denied, .undetermined:
                hasPermission = false
            @unknown default:
                hasPermission = false
            }
        }
        #endif
    }

    /// Request microphone permission from the user
    func requestPermission() {
        #if os(macOS) || os(watchOS) || os(tvOS)
        log.audio("Microphone permission request not supported on this platform", level: .warning)
        #else
        if #available(iOS 17.0, *) {
            Task {
                let granted = await AVAudioApplication.requestRecordPermission()
                await MainActor.run {
                    self.hasPermission = granted
                    if granted {
                        log.audio("Microphone permission granted")
                        self.permissionDenied = false
                        do {
                            try AudioConfiguration.upgradeToPlayAndRecord()
                        } catch {
                            log.audio("Failed to upgrade audio session to play-and-record: \(error.localizedDescription)", level: .error)
                        }
                    } else {
                        log.audio("Microphone permission denied", level: .error)
                        self.permissionDenied = true
                    }
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                // Permission callback runs on arbitrary queue — DispatchQueue.main.async
                // avoids Swift 6 dispatch_assert_queue_fail
                DispatchQueue.main.async {
                    self?.hasPermission = granted
                    if granted {
                        log.audio("Microphone permission granted")
                        self?.permissionDenied = false
                        do {
                            try AudioConfiguration.upgradeToPlayAndRecord()
                        } catch {
                            log.audio("Failed to upgrade audio session to play-and-record: \(error.localizedDescription)", level: .error)
                        }
                    } else {
                        log.audio("Microphone permission denied", level: .error)
                        self?.permissionDenied = true
                    }
                }
            }
        }
        #endif
    }


    // MARK: - Recording Control

    /// Start recording audio from the microphone
    func startRecording() {
        guard hasPermission else {
            log.audio("⚠️ Cannot start recording: No microphone permission", level: .warning)
            requestPermission()
            return
        }
        // AU4 re-entry guard: a second startRecording() would overwrite `audioEngine`
        // while the previous engine is still running with its input tap installed —
        // leaking it (and its tap → processExtractedAudio) and contending for the input
        // node ("alles still" class, #22). One recorder at a time; stop before restart.
        guard !isRecording else {
            log.audio("MicrophoneManager: startRecording ignored — already recording")
            return
        }

        do {
            // The app's DEFAULT session is now .playback (output only) so it never
            // drags other apps' Bluetooth audio down to HFP call quality. Recording
            // needs the mic, so upgrade to .playAndRecord HERE — the moment the user
            // actually records. (Permission was granted in a prior launch, so
            // requestPermission's upgrade didn't run this time.) .playAndRecord — not
            // .record — keeps the synth/drum output alive alongside the mic.
            #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            if !AudioConfiguration.isSessionConfigured {
                try AudioConfiguration.configureAudioSession()
            }
            // #299: claim the route as an OWNER. The stop side used to lower it
            // unconditionally, which cut live input monitoring; now the route only comes down
            // when this recorder is the last holder.
            try AudioConfiguration.claimRecordRoute(.microphoneManager)
            #endif

            // Create and configure the audio engine
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else {
                log.error("MicrophoneManager: failed to create AVAudioEngine", category: .audio)
                return
            }

            inputNode = audioEngine.inputNode

            // Get the input format from the microphone
            let recordingFormat = inputNode?.outputFormat(forBus: 0)
            guard let format = recordingFormat else {
                log.error("MicrophoneManager: failed to get microphone input format", category: .audio)
                return
            }

            // Store sample rate for frequency calculation
            sampleRate = format.sampleRate

            // Setup FFT
            complexDFT = EchoelComplexDFT(size: fftSize)

            // Install a tap to capture audio data — dispatch off the audio render thread
            // Capture sampleRate locally to avoid reading @MainActor property from Sendable closure
            let capturedSampleRate = sampleRate
            // Tap runs on audio thread — do NOT access @MainActor self in outer closure.
            // nonisolated(unsafe) avoids Swift 6 actor isolation check on audio thread.
            nonisolated(unsafe) weak var weakSelf = self
            inputNode?.installTap(onBus: 0, bufferSize: UInt32(fftSize), format: format) { @Sendable buffer, _ in
                // Extract all buffer data synchronously while memory is valid
                // AVAudioPCMBuffer is non-Sendable — its memory is reused after this closure returns
                guard let channelData = buffer.floatChannelData else { return }
                let frameLength = Int(buffer.frameLength)
                guard frameLength > 0 else { return }
                let channelDataPtr = channelData.pointee
                // Note: Array allocation in installTap is acceptable — this is NOT the render block.
                // The tap runs on a separate I/O thread with more tolerance than internalRenderBlock.
                let samples = Array(UnsafeBufferPointer(start: channelDataPtr, count: frameLength))
                // DispatchQueue.main.async bypasses Swift concurrency runtime entirely —
                // Task { @MainActor } crashes on audio thread (dispatch_assert_queue_fail)
                DispatchQueue.main.async {
                    weakSelf?.processExtractedAudio(samples, frameLength: frameLength, sampleRate: capturedSampleRate)
                }
            }

            // Prepare and start the audio engine
            audioEngine.prepare()
            try audioEngine.start()

            self.isRecording = true

            log.audio("🎙️ Recording started with FFT enabled")

        } catch {
            log.audio("❌ Failed to start recording: \(error.localizedDescription)", level: .error)
            self.isRecording = false
            // ⭐ #299 Nachlese — THE ONE REACHABLE EXIT THAT CLAIMED WITHOUT RELEASING, and the
            // sentence that let it through was in the design note: "a Set is idempotent in both
            // directions, which makes the failure paths safe to write as a plain release". A Set
            // makes a DUPLICATE release safe. It does nothing about a MISSING one — that leaks
            // exactly like the refcount the note rejects. Note also that `claimRecordRoute` at
            // the top of this `do` can itself throw and land HERE, so both a failed
            // `audioEngine.start()` and a failed session upgrade strand `.microphoneManager` in
            // the owner set: monitoring off afterwards would then find a non-empty set and never
            // return the route to `.playback`. The other two owners avoid this by catching their
            // claim locally; this one propagates, which is why it needs the release here.
            #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            try? AudioConfiguration.releaseRecordRoute(.microphoneManager)
            #endif
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

        // Release FFT wrapper
        complexDFT = nil

        // AU4: return the SHARED session to the app's default .playback WITHOUT
        // deactivating it. The master output engine owns the process-wide session —
        // the old `setActive(false)` here tore it down under the master and cut ALL
        // app audio ("alles still" class, #22). The symmetric inverse of the
        // start-side `upgradeToPlayAndRecord` keeps output alive + restores A2DP.
        //
        // #299: released as an OWNER, not lowered outright. This unconditional downgrade was
        // the one place that DID return the route — and because it was unconditional it also
        // yanked it away from input monitoring running at the same time.
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        do {
            try AudioConfiguration.releaseRecordRoute(.microphoneManager)
        } catch {
            log.audio("Failed to downgrade audio session after recording: \(error.localizedDescription)", level: .warning)
        }
        #endif

        self.isRecording = false
        self.audioLevel = 0.0
        self.frequency = 0.0
        self.currentPitch = 0.0

        log.audio("⏹️ Recording stopped")
    }


    // MARK: - Audio Processing with FFT

    /// EchoelVoice #592b: while a voice capture runs, every extracted sample block is
    /// ALSO handed here (main thread — this rides the existing per-buffer hop, adding
    /// zero new thread crossings; the per-buffer hop itself is trap 2 of
    /// `scratchpads/PLAN_ECHOEL_VOICE.md`, pre-existing and unchanged by this slice).
    /// Set by `VoiceCaptureController` for the duration of a capture, nil otherwise.
    var captureSampleSink: (([Float], Double) -> Void)?

    /// Process pre-extracted audio samples with FFT for frequency detection
    /// Called with data copied synchronously from AVAudioPCMBuffer while memory was valid
    private func processExtractedAudio(_ samples: [Float], frameLength: Int, sampleRate: Double) {
        captureSampleSink?(samples, sampleRate)
        // Calculate RMS (amplitude/volume) from copied samples
        var sumSquares: Float = 0.0
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            vDSP_measqv(base, 1, &sumSquares, vDSP_Length(frameLength))
        }
        let rms = sqrt(sumSquares)

        // Normalize to 0-1 range with better sensitivity
        let normalizedLevel = min(rms * 15.0, 1.0)

        // Capture audio buffer for waveform visualization (last 512 samples)
        let bufferSampleCount = min(512, frameLength)
        let capturedBuffer = Array(samples.prefix(bufferSampleCount))

        // Perform FFT for frequency detection and get magnitudes
        let (detectedFrequency, magnitudes) = samples.withUnsafeBufferPointer { ptr -> (Float, [Float]) in
            guard let base = ptr.baseAddress else { return (0, []) }
            return performFFT(on: base, frameLength: frameLength, sampleRate: sampleRate)
        }

        // Pitch detection disabled (soundscape refactor)
        let detectedPitch: Float = 0

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

    /// Perform FFT to detect fundamental frequency and return magnitudes
    /// Uses pre-allocated buffers (fftRealParts, fftWindowedParts, etc.) to avoid
    /// per-callback heap allocation on the processing queue.
    private func performFFT(on data: UnsafePointer<Float>, frameLength: Int, sampleRate: Double) -> (frequency: Float, magnitudes: [Float]) {
        guard let dft = complexDFT else { return (0, []) }

        // Zero-fill pre-allocated buffer, then copy audio data
        memset(&fftRealParts, 0, fftSize * MemoryLayout<Float>.size)
        let copyLength = min(frameLength, fftSize)
        memcpy(&fftRealParts, data, copyLength * MemoryLayout<Float>.size)

        // Apply pre-computed Hann window to reduce spectral leakage
        vDSP_vmul(fftRealParts, 1, fftWindow, 1, &fftWindowedParts, 1, vDSP_Length(fftSize))

        // Perform FFT via EchoelComplexDFT (handles overlapping access safety internally)
        let result = dft.forward(real: fftWindowedParts, imag: fftImagZeros)
        let realParts = result.real
        let imagParts = result.imag

        // Calculate magnitudes (power spectrum) into pre-allocated buffer
        let halfSize = fftSize / 2
        for i in 0..<halfSize {
            fftMagnitudesBuffer[i] = sqrt(realParts[i] * realParts[i] + imagParts[i] * imagParts[i])
        }

        // Downsample magnitudes for visualization (256 bins for spectral mode)
        let visualBins = 256
        let binRatio = Swift.max(1, halfSize / visualBins)
        for i in 0..<visualBins {
            let startIdx = i * binRatio
            let endIdx = min(startIdx + binRatio, halfSize)
            guard startIdx < halfSize else { break }
            var sum: Float = 0
            for j in startIdx..<endIdx {
                sum += fftMagnitudesBuffer[j]
            }
            fftVisualMagnitudes[i] = sum / Float(binRatio)
        }

        // Find peak frequency (ignore DC component at index 0)
        guard halfSize > 1 else { return (0, Array(fftVisualMagnitudes)) }
        var maxMagnitude: Float = 0
        var maxIndex: vDSP_Length = 0

        let searchBuffer = Array(fftMagnitudesBuffer[1...])
        vDSP_maxvi(searchBuffer, 1, &maxMagnitude, &maxIndex, vDSP_Length(halfSize - 1))
        maxIndex += 1 // Adjust for skipping index 0

        // Convert bin index to frequency
        let frequency = Float(maxIndex) * Float(sampleRate) / Float(fftSize)

        // Return copy of visual magnitudes for UI (must be independent of mutable buffer)
        let visualResult = Array(fftVisualMagnitudes)

        // Only return frequencies in audible/useful range
        if frequency > 50 && frequency < 2000 && maxMagnitude > 0.01 {
            return (frequency, visualResult)
        }

        return (0.0, visualResult)
    }


    // MARK: - Cleanup

    /// Clean up when the object is destroyed
    deinit {
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        audioEngine = nil
    }
}

// MARK: - Settings Utility

/// Open iOS Settings app to allow the user to re-enable denied permissions.
@MainActor
func openAppSettings() {
    #if os(iOS)
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
    #endif
}
#endif
