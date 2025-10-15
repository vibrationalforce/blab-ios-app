import AVFoundation
import SwiftUI

/// Manages microphone access and audio input capture
/// This class handles all audio recording functionality
class MicrophoneManager: NSObject, ObservableObject {

    // MARK: - Published Properties
    // These properties automatically update the UI when they change

    /// Current audio level (0.0 to 1.0)
    @Published var audioLevel: Float = 0.0

    /// Whether we have microphone permission
    @Published var hasPermission: Bool = false

    /// Whether we're currently recording
    @Published var isRecording: Bool = false


    // MARK: - Private Properties

    /// The audio engine that processes audio input
    private var audioEngine: AVAudioEngine?

    /// The input node that captures microphone data
    private var inputNode: AVAudioInputNode?

    /// Timer to update audio levels regularly
    private var levelTimer: Timer?


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
    /// This will show the iOS permission dialog
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

            // Install a tap to capture audio data
            // The tap captures audio in blocks (buffers)
            inputNode?.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }

            // Prepare and start the audio engine
            audioEngine.prepare()
            try audioEngine.start()

            isRecording = true
            print("🎙️ Recording started")

            // Start a timer to update the audio level display
            startLevelTimer()

        } catch {
            print("❌ Failed to start recording: \(error.localizedDescription)")
        }
    }

    /// Stop recording audio
    func stopRecording() {
        // Stop the audio engine
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        inputNode = nil

        // Stop the level timer
        stopLevelTimer()

        // Deactivate the audio session
        try? AVAudioSession.sharedInstance().setActive(false)

        isRecording = false
        audioLevel = 0.0

        print("⏹️ Recording stopped")
    }


    // MARK: - Audio Processing

    /// Process incoming audio data and calculate the audio level
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelDataValue = channelData.pointee
        let channelDataCount = Int(buffer.frameLength)

        // Calculate the RMS (Root Mean Square) level
        // This gives us the average "loudness" of the audio
        var sum: Float = 0.0
        for i in 0..<channelDataCount {
            let sample = channelDataValue[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(channelDataCount))

        // Convert to a 0-1 scale for easier visualization
        // Apply some scaling to make it more responsive
        let normalizedLevel = min(rms * 20, 1.0)

        // Update on the main thread since we're changing a @Published property
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = normalizedLevel
        }
    }


    // MARK: - Level Timer

    /// Start a timer to regularly update the audio level display
    private func startLevelTimer() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            // The actual level is updated in processAudioBuffer
            // This timer just ensures smooth UI updates
        }
    }

    /// Stop the level timer
    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }


    // MARK: - Cleanup

    /// Clean up when the object is destroyed
    deinit {
        stopRecording()
    }
}
