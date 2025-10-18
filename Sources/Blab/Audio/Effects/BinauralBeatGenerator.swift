import Foundation
import AVFoundation
import Accelerate

/// Generates binaural beats for brainwave entrainment and healing frequencies
///
/// Binaural beats work by playing two slightly different frequencies (one per ear),
/// causing the brain to perceive a "beat" at the difference frequency.
/// This can induce specific brainwave states for relaxation, focus, sleep, etc.
///
/// Scientific basis: Oster, G. (1973). "Auditory beats in the brain"
@MainActor
class BinauralBeatGenerator: ObservableObject {

    // MARK: - Audio Mode

    /// Audio output mode based on device capabilities
    enum AudioMode {
        case binaural     // Stereo - different frequency per ear (requires headphones)
        case isochronic   // Mono - pulsed tone (works on speakers, spatial audio, etc.)
    }

    // MARK: - Brainwave Presets

    /// Brainwave state configurations based on neuroscience research
    enum BrainwaveState: String, CaseIterable {
        case delta      // 2 Hz - Deep sleep, healing
        case theta      // 6 Hz - Meditation, creativity
        case alpha      // 10 Hz - Relaxation, learning
        case beta       // 20 Hz - Focus, alertness
        case gamma      // 40 Hz - Peak awareness, cognition

        /// Beat frequency in Hz for this brainwave state
        var beatFrequency: Float {
            switch self {
            case .delta: return 2.0
            case .theta: return 6.0
            case .alpha: return 10.0
            case .beta: return 20.0
            case .gamma: return 40.0
            }
        }

        /// Human-readable description
        var description: String {
            switch self {
            case .delta: return "Deep Sleep & Healing"
            case .theta: return "Meditation & Creativity"
            case .alpha: return "Relaxation & Learning"
            case .beta: return "Focus & Alertness"
            case .gamma: return "Peak Awareness"
            }
        }
    }


    // MARK: - Configuration

    /// Carrier frequency in Hz (the base tone, often 432 Hz for healing)
    /// 432 Hz is considered the "natural frequency" in some healing traditions
    private(set) var carrierFrequency: Float = 432.0

    /// Beat frequency in Hz (difference between left and right ear)
    /// This is what entrains the brain to the target brainwave state
    private(set) var beatFrequency: Float = 10.0  // Alpha by default

    /// Amplitude (volume) of the generated tone (0.0 - 1.0)
    private(set) var amplitude: Float = 0.3

    /// Sample rate for audio generation
    private let sampleRate: Double = 44100.0

    /// Current audio mode (automatically detected)
    @Published private(set) var audioMode: AudioMode = .binaural


    // MARK: - Audio Components

    /// Audio engine for playback
    private let audioEngine = AVAudioEngine()

    /// Player node for left channel
    private let leftPlayerNode = AVAudioPlayerNode()

    /// Player node for right channel
    private let rightPlayerNode = AVAudioPlayerNode()

    /// Audio format (stereo, 44.1 kHz)
    private lazy var audioFormat: AVAudioFormat = {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    }()

    /// Buffer size for generation (larger = less CPU, more latency)
    private let bufferSize: AVAudioFrameCount = 4096

    /// Whether the generator is currently playing
    private(set) var isPlaying: Bool = false

    /// Timer for continuous buffer generation
    private var bufferTimer: Timer?


    // MARK: - Initialization

    init() {
        setupAudioEngine()
    }

    deinit {
        stop()
    }


    // MARK: - Public Methods

    /// Configure the binaural beat parameters
    /// - Parameters:
    ///   - carrier: Base frequency in Hz (typically 200-500 Hz, default 432 Hz)
    ///   - beat: Beat frequency in Hz (0.5-40 Hz for different brainwave states)
    ///   - amplitude: Volume (0.0-1.0, default 0.3)
    func configure(carrier: Float, beat: Float, amplitude: Float) {
        self.carrierFrequency = carrier
        self.beatFrequency = beat
        self.amplitude = min(max(amplitude, 0.0), 1.0)  // Clamp to 0-1
    }

    /// Configure using a brainwave preset
    /// - Parameter state: Predefined brainwave state (delta, theta, alpha, beta, gamma)
    func configure(state: BrainwaveState) {
        self.beatFrequency = state.beatFrequency
        // Keep current carrier frequency and amplitude
        print("🧠 Configured for \(state.rawValue) state: \(state.description)")
    }

    /// Set beat frequency dynamically based on HRV coherence
    /// Maps coherence (0-100) to optimal brainwave states:
    /// - Low coherence (0-40) → Alpha (10 Hz) for relaxation
    /// - Medium coherence (40-60) → Alpha-Beta transition (15 Hz)
    /// - High coherence (60-100) → Beta (20 Hz) for peak focus
    ///
    /// - Parameter coherence: HRV coherence score (0-100)
    func setBeatFrequencyFromHRV(coherence: Double) {
        if coherence < 40 {
            // Low coherence: promote relaxation
            beatFrequency = 10.0  // Alpha
        } else if coherence < 60 {
            // Medium coherence: transition to focus
            beatFrequency = 15.0  // Alpha-Beta blend
        } else {
            // High coherence: maintain focus
            beatFrequency = 20.0  // Beta
        }
        print("💓 HRV coherence \(Int(coherence)) → \(beatFrequency) Hz beat")
    }

    /// Start generating and playing binaural/isochronic beats
    func start() {
        guard !isPlaying else { return }

        do {
            // Configure audio session for playback
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)

            // Detect audio output type and choose optimal mode
            detectAudioMode()

            // Start the audio engine
            if !audioEngine.isRunning {
                try audioEngine.start()
            }

            // Start player nodes
            leftPlayerNode.play()
            rightPlayerNode.play()

            // Schedule initial buffers
            scheduleBuffers()

            // Start timer for continuous buffer generation
            bufferTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.scheduleBuffers()
            }

            isPlaying = true
            let modeStr = audioMode == .binaural ? "Binaural (stereo)" : "Isochronic (mono)"
            print("▶️ \(modeStr) beats started: \(carrierFrequency) Hz @ \(beatFrequency) Hz")

        } catch {
            print("❌ Failed to start beats: \(error.localizedDescription)")
        }
    }

    /// Stop playing binaural beats
    func stop() {
        guard isPlaying else { return }

        // Stop timer
        bufferTimer?.invalidate()
        bufferTimer = nil

        // Stop player nodes
        leftPlayerNode.stop()
        rightPlayerNode.stop()

        // Stop engine
        audioEngine.stop()

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)

        isPlaying = false
        print("⏹️ Binaural beats stopped")
    }


    // MARK: - Private Methods

    /// Setup audio engine with stereo output
    private func setupAudioEngine() {
        // Attach player nodes to engine
        audioEngine.attach(leftPlayerNode)
        audioEngine.attach(rightPlayerNode)

        // Create mixer node to combine left and right channels
        let mixer = audioEngine.mainMixerNode

        // Connect left player to mixer (left channel)
        audioEngine.connect(leftPlayerNode, to: mixer, format: audioFormat)

        // Connect right player to mixer (right channel)
        audioEngine.connect(rightPlayerNode, to: mixer, format: audioFormat)

        // Prepare engine
        audioEngine.prepare()
    }

    /// Schedule audio buffers for continuous playback
    private func scheduleBuffers() {
        if audioMode == .binaural {
            // Binaural mode: different frequency per ear
            let leftBuffer = generateToneBuffer(frequency: leftEarFrequency)
            let rightBuffer = generateToneBuffer(frequency: rightEarFrequency)

            leftPlayerNode.scheduleBuffer(leftBuffer, completionHandler: nil)
            rightPlayerNode.scheduleBuffer(rightBuffer, completionHandler: nil)
        } else {
            // Isochronic mode: pulsed tone (same on both ears)
            let isoBuffer = generateIsochronicBuffer()

            leftPlayerNode.scheduleBuffer(isoBuffer, completionHandler: nil)
            rightPlayerNode.scheduleBuffer(isoBuffer, completionHandler: nil)
        }
    }

    /// Calculate frequency for left ear
    /// Left ear plays carrier frequency MINUS half the beat frequency
    private var leftEarFrequency: Float {
        return carrierFrequency - (beatFrequency / 2.0)
    }

    /// Calculate frequency for right ear
    /// Right ear plays carrier frequency PLUS half the beat frequency
    private var rightEarFrequency: Float {
        return carrierFrequency + (beatFrequency / 2.0)
    }

    /// Generate a pure sine wave tone buffer at specified frequency
    /// - Parameter frequency: Frequency in Hz
    /// - Returns: Audio buffer containing the sine wave
    private func generateToneBuffer(frequency: Float) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize)!
        buffer.frameLength = bufferSize

        guard let channelData = buffer.floatChannelData?[0] else {
            return buffer
        }

        // Generate sine wave: y = A * sin(2π * f * t)
        let angularFrequency = 2.0 * Float.pi * frequency
        let sampleRateFloat = Float(sampleRate)

        for i in 0..<Int(bufferSize) {
            let time = Float(i) / sampleRateFloat
            let phase = angularFrequency * time
            channelData[i] = amplitude * sin(phase)
        }

        return buffer
    }

    /// Apply smooth fade-in envelope to prevent clicks
    /// - Parameter buffer: Audio buffer to apply envelope to
    private func applyFadeIn(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let fadeLength = min(Int(bufferSize) / 10, 441)  // 10ms fade

        for i in 0..<fadeLength {
            let envelope = Float(i) / Float(fadeLength)
            channelData[i] *= envelope
        }
    }

    /// Apply smooth fade-out envelope to prevent clicks
    /// - Parameter buffer: Audio buffer to apply envelope to
    private func applyFadeOut(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let fadeLength = min(Int(bufferSize) / 10, 441)  // 10ms fade
        let startIndex = Int(bufferSize) - fadeLength

        for i in 0..<fadeLength {
            let envelope = 1.0 - (Float(i) / Float(fadeLength))
            channelData[startIndex + i] *= envelope
        }
    }

    /// Generate isochronic tone buffer (pulsed carrier tone at beat frequency)
    /// Works on mono speakers, Bluetooth, spatial audio - no stereo required
    /// - Returns: Audio buffer containing pulsed tone
    private func generateIsochronicBuffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize)!
        buffer.frameLength = bufferSize

        guard let channelData = buffer.floatChannelData?[0] else {
            return buffer
        }

        // Generate carrier tone with amplitude modulation at beat frequency
        let carrierAngularFreq = 2.0 * Float.pi * carrierFrequency
        let pulseAngularFreq = 2.0 * Float.pi * beatFrequency
        let sampleRateFloat = Float(sampleRate)

        for i in 0..<Int(bufferSize) {
            let time = Float(i) / sampleRateFloat

            // Carrier sine wave
            let carrier = sin(carrierAngularFreq * time)

            // Pulse envelope (square wave smoothed with sine for clicks reduction)
            // Converts -1...1 sine to 0...1 pulse
            let pulseEnvelope = (sin(pulseAngularFreq * time) + 1.0) / 2.0

            // Modulate carrier with pulse
            channelData[i] = amplitude * carrier * pulseEnvelope
        }

        return buffer
    }

    /// Detect optimal audio mode based on current output route
    /// ONLY headphones → Binaural (requires isolated left/right channels)
    /// Everything else → Isochronic (speakers, Bluetooth, spatial audio, club systems)
    ///
    /// Why: Binaural beats require each ear to receive ONLY its designated frequency.
    /// Regular stereo speakers fail because both speakers reach both ears (crosstalk).
    /// Even in clubs with stereo systems, the sound mixes in the room.
    private func detectAudioMode() {
        let audioSession = AVAudioSession.sharedInstance()
        let currentRoute = audioSession.currentRoute

        // Check output ports - be conservative, only wired/BT headphones get binaural
        var hasIsolatedHeadphones = false
        for output in currentRoute.outputs {
            let portType = output.portType

            // Only wired headphones or Bluetooth headphones (not speakers!)
            if portType == .headphones ||
               portType == .bluetoothHFP ||  // Phone calls (headsets)
               portType == .bluetoothLE {     // AirPods, modern BT headphones
                hasIsolatedHeadphones = true
                break
            }

            // Explicitly exclude cases that can't do binaural:
            // - .builtInSpeaker (phone speaker)
            // - .bluetoothA2DP (could be speaker or headphones - assume speaker for safety)
            // - .airPlay (wireless speakers)
            // - Any other speaker type
        }

        // Set mode based on output
        if hasIsolatedHeadphones {
            audioMode = .binaural
            print("🎧 Isolated headphones detected → Binaural mode (true stereo)")
        } else {
            audioMode = .isochronic
            print("🔊 Speaker/Open-air detected → Isochronic mode (mono pulsed, works anywhere)")
        }
    }
}
