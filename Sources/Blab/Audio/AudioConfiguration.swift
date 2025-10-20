import Foundation
import AVFoundation

/// Audio configuration constants and optimization settings
/// Target: < 5ms latency for real-time performance
enum AudioConfiguration {

    // MARK: - Sample Rate

    /// Preferred sample rate (48 kHz for pro audio)
    static let preferredSampleRate: Double = 48000.0

    /// Fallback sample rate if 48kHz unavailable
    static let fallbackSampleRate: Double = 44100.0


    // MARK: - Buffer Configuration

    /// Ultra-low latency buffer size (128 frames)
    /// At 48kHz: 128/48000 = 2.67ms latency
    static let ultraLowLatencyBufferSize: AVAudioFrameCount = 128

    /// Low latency buffer size (256 frames)
    /// At 48kHz: 256/48000 = 5.33ms latency
    static let lowLatencyBufferSize: AVAudioFrameCount = 256

    /// Normal buffer size (512 frames) - better for battery
    /// At 48kHz: 512/48000 = 10.67ms latency
    static let normalBufferSize: AVAudioFrameCount = 512

    /// Current buffer size (defaults to low latency)
    static var currentBufferSize: AVAudioFrameCount = lowLatencyBufferSize

    /// Calculate IO buffer duration for AVAudioSession
    static func ioBufferDuration(for sampleRate: Double) -> TimeInterval {
        return Double(currentBufferSize) / sampleRate
    }


    // MARK: - Audio Format

    /// Standard audio format for processing
    /// 32-bit float, interleaved, stereo
    static func standardFormat(sampleRate: Double = preferredSampleRate) -> AVAudioFormat? {
        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: true
        )
    }

    /// Non-interleaved format for DSP operations
    static func dspFormat(sampleRate: Double = preferredSampleRate) -> AVAudioFormat? {
        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        )
    }


    // MARK: - Audio Session Configuration

    /// Configure audio session for real-time performance
    static func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()

        // Set category for playback and recording
        try audioSession.setCategory(
            .playAndRecord,
            mode: .measurement,  // Low-latency mode
            options: [.allowBluetooth, .defaultToSpeaker, .mixWithOthers]
        )

        // Set preferred sample rate
        try audioSession.setPreferredSampleRate(preferredSampleRate)

        // Set preferred IO buffer duration (target latency)
        let bufferDuration = ioBufferDuration(for: preferredSampleRate)
        try audioSession.setPreferredIOBufferDuration(bufferDuration)

        // Activate session
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        print("🎵 Audio Session Configured:")
        print("   Sample Rate: \(audioSession.sampleRate) Hz")
        print("   IO Buffer Duration: \(audioSession.ioBufferDuration * 1000) ms")
        print("   Input Latency: \(audioSession.inputLatency * 1000) ms")
        print("   Output Latency: \(audioSession.outputLatency * 1000) ms")
        print("   Total Latency: \((audioSession.inputLatency + audioSession.outputLatency + audioSession.ioBufferDuration) * 1000) ms")
    }


    // MARK: - Latency Modes

    enum LatencyMode {
        case ultraLow   // 128 frames (~2.7ms @ 48kHz) - max CPU usage
        case low        // 256 frames (~5.3ms @ 48kHz) - balanced
        case normal     // 512 frames (~10.7ms @ 48kHz) - battery friendly

        var bufferSize: AVAudioFrameCount {
            switch self {
            case .ultraLow: return ultraLowLatencyBufferSize
            case .low: return lowLatencyBufferSize
            case .normal: return normalBufferSize
            }
        }

        var description: String {
            switch self {
            case .ultraLow: return "Ultra-Low (~2.7ms)"
            case .low: return "Low (~5.3ms)"
            case .normal: return "Normal (~10.7ms)"
            }
        }
    }

    /// Set latency mode and reconfigure audio session
    static func setLatencyMode(_ mode: LatencyMode) throws {
        currentBufferSize = mode.bufferSize
        try configureAudioSession()
        print("🎵 Latency mode set to: \(mode.description)")
    }


    // MARK: - Thread Priority

    /// Set real-time audio thread priority
    static func setAudioThreadPriority() {
        // Get current thread
        var threadTimeConstraintPolicy = thread_time_constraint_policy()

        // Audio thread constraints (48kHz, 256 frames)
        let sampleRate = preferredSampleRate
        let bufferSize = currentBufferSize

        // Period: time for one buffer in nanoseconds
        let period = UInt32((Double(bufferSize) / sampleRate) * 1_000_000_000)

        // Computation: 75% of period
        let computation = UInt32(Double(period) * 0.75)

        // Constraint: 95% of period
        let constraint = UInt32(Double(period) * 0.95)

        threadTimeConstraintPolicy.period = period
        threadTimeConstraintPolicy.computation = computation
        threadTimeConstraintPolicy.constraint = constraint
        threadTimeConstraintPolicy.preemptible = 0  // Not preemptible

        // Apply policy
        var policyCount = mach_msg_type_number_t(
            MemoryLayout<thread_time_constraint_policy>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &threadTimeConstraintPolicy) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(policyCount)) {
                thread_policy_set(
                    mach_thread_self(),
                    thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY),
                    $0,
                    policyCount
                )
            }
        }

        if result == KERN_SUCCESS {
            print("✅ Real-time audio thread priority set")
        } else {
            print("⚠️  Failed to set audio thread priority: \(result)")
        }
    }


    // MARK: - Performance Monitoring

    /// Measure actual audio latency
    static func measureLatency() -> TimeInterval {
        let audioSession = AVAudioSession.sharedInstance()
        let inputLatency = audioSession.inputLatency
        let outputLatency = audioSession.outputLatency
        let ioBufferDuration = audioSession.ioBufferDuration

        return inputLatency + outputLatency + ioBufferDuration
    }

    /// Get latency statistics
    static func latencyStats() -> String {
        let audioSession = AVAudioSession.sharedInstance()
        let totalLatency = measureLatency() * 1000  // Convert to ms

        return """
        🎵 Audio Latency Statistics:
           Sample Rate: \(audioSession.sampleRate) Hz
           IO Buffer: \(audioSession.ioBufferDuration * 1000) ms (\(currentBufferSize) frames)
           Input Latency: \(audioSession.inputLatency * 1000) ms
           Output Latency: \(audioSession.outputLatency * 1000) ms
           Total Latency: \(String(format: "%.2f", totalLatency)) ms
           Target: < 5.0 ms
           Status: \(totalLatency < 5.0 ? "✅ EXCELLENT" : totalLatency < 10.0 ? "⚠️  GOOD" : "❌ NEEDS OPTIMIZATION")
        """
    }
}
