import XCTest
import AVFoundation
@testable import Blab

/// Unit tests for PitchDetector (YIN algorithm)
/// Tests accuracy, performance, and edge cases for real-time pitch detection
final class PitchDetectorTests: XCTestCase {

    var pitchDetector: PitchDetector!

    override func setUp() {
        pitchDetector = PitchDetector()
    }

    override func tearDown() {
        pitchDetector = nil
    }


    // MARK: - Accuracy Tests

    /// Test pitch detection with pure 440 Hz sine wave (A4 - concert pitch)
    func testPitchDetection_A440() {
        let sampleRate: Float = 44100.0
        let frequency: Float = 440.0
        let duration: Float = 0.5 // 500ms
        let buffer = generateSineWave(frequency: frequency,
                                     sampleRate: sampleRate,
                                     duration: duration,
                                     amplitude: 0.5)

        let detectedPitch = pitchDetector.detectPitch(buffer: buffer, sampleRate: sampleRate)

        // Allow 1% error tolerance (±4.4 Hz for 440 Hz)
        XCTAssertGreaterThan(detectedPitch, 0, "Should detect pitch in sine wave")
        XCTAssertEqual(detectedPitch, frequency, accuracy: frequency * 0.01,
                      "Detected pitch should be close to 440 Hz")
        print("A440 test: Expected \(frequency) Hz, detected \(detectedPitch) Hz")
    }

    /// Test with 261.63 Hz sine wave (C4 - middle C)
    func testPitchDetection_MiddleC() {
        let sampleRate: Float = 44100.0
        let frequency: Float = 261.63
        let duration: Float = 0.5
        let buffer = generateSineWave(frequency: frequency,
                                     sampleRate: sampleRate,
                                     duration: duration,
                                     amplitude: 0.5)

        let detectedPitch = pitchDetector.detectPitch(buffer: buffer, sampleRate: sampleRate)

        XCTAssertGreaterThan(detectedPitch, 0, "Should detect pitch")
        XCTAssertEqual(detectedPitch, frequency, accuracy: frequency * 0.01,
                      "Should detect middle C accurately")
        print("Middle C test: Expected \(frequency) Hz, detected \(detectedPitch) Hz")
    }

    /// Test with 880 Hz sine wave (A5 - one octave above A440)
    func testPitchDetection_A880() {
        let sampleRate: Float = 44100.0
        let frequency: Float = 880.0
        let duration: Float = 0.5
        let buffer = generateSineWave(frequency: frequency,
                                     sampleRate: sampleRate,
                                     duration: duration,
                                     amplitude: 0.5)

        let detectedPitch = pitchDetector.detectPitch(buffer: buffer, sampleRate: sampleRate)

        XCTAssertGreaterThan(detectedPitch, 0, "Should detect pitch")
        XCTAssertEqual(detectedPitch, frequency, accuracy: frequency * 0.02,
                      "Should detect high A accurately")
        print("A880 test: Expected \(frequency) Hz, detected \(detectedPitch) Hz")
    }

    /// Test with complex harmonic signal (fundamental + harmonics)
    /// This simulates a real voice or musical instrument
    func testPitchDetection_ComplexHarmonic() {
        let sampleRate: Float = 44100.0
        let fundamental: Float = 200.0 // Male voice range
        let duration: Float = 0.5

        // Generate complex tone: fundamental + 2nd + 3rd harmonics
        let buffer = generateComplexTone(fundamental: fundamental,
                                        harmonics: [1.0, 0.5, 0.3], // Amplitudes
                                        sampleRate: sampleRate,
                                        duration: duration)

        let detectedPitch = pitchDetector.detectPitch(buffer: buffer, sampleRate: sampleRate)

        // YIN should detect the fundamental, not harmonics
        XCTAssertGreaterThan(detectedPitch, 0, "Should detect fundamental frequency")
        XCTAssertEqual(detectedPitch, fundamental, accuracy: fundamental * 0.02,
                      "Should detect fundamental, ignoring harmonics")
        print("Complex harmonic test: Expected \(fundamental) Hz, detected \(detectedPitch) Hz")
    }

    /// Test with very low frequency (bass voice range)
    func testPitchDetection_LowFrequency() {
        let sampleRate: Float = 44100.0
        let frequency: Float = 85.0 // Low male voice (E2)
        let duration: Float = 0.5
        let buffer = generateSineWave(frequency: frequency,
                                     sampleRate: sampleRate,
                                     duration: duration,
                                     amplitude: 0.5)

        let detectedPitch = pitchDetector.detectPitch(buffer: buffer, sampleRate: sampleRate)

        XCTAssertGreaterThan(detectedPitch, 0, "Should detect low frequency")
        XCTAssertEqual(detectedPitch, frequency, accuracy: frequency * 0.03,
                      "Should detect bass frequency accurately")
        print("Low frequency test: Expected \(frequency) Hz, detected \(detectedPitch) Hz")
    }


    // MARK: - Edge Case Tests

    /// Test with silence (should return 0)
    func testPitchDetection_Silence() {
        let sampleRate: Float = 44100.0
        let duration: Float = 0.5
        let buffer = generateSilence(sampleRate: sampleRate, duration: duration)

        let detectedPitch = pitchDetector.detectPitch(buffer: buffer, sampleRate: sampleRate)

        XCTAssertEqual(detectedPitch, 0.0, "Silence should return 0 pitch")
    }

    /// Test with white noise (should return 0 or very low confidence)
    func testPitchDetection_Noise() {
        let sampleRate: Float = 44100.0
        let duration: Float = 0.5
        let buffer = generateWhiteNoise(sampleRate: sampleRate,
                                       duration: duration,
                                       amplitude: 0.3)

        let detectedPitch = pitchDetector.detectPitch(buffer: buffer, sampleRate: sampleRate)

        // Noise should either return 0 or be rejected by YIN threshold
        XCTAssertLessThanOrEqual(detectedPitch, 100.0,
                                "Noise should not produce high-confidence pitch")
        print("Noise test: Detected pitch \(detectedPitch) Hz (should be low or 0)")
    }

    /// Test with very quiet signal (below silence threshold)
    func testPitchDetection_QuietSignal() {
        let sampleRate: Float = 44100.0
        let frequency: Float = 440.0
        let duration: Float = 0.5
        let buffer = generateSineWave(frequency: frequency,
                                     sampleRate: sampleRate,
                                     duration: duration,
                                     amplitude: 0.0001) // Very quiet

        let detectedPitch = pitchDetector.detectPitch(buffer: buffer, sampleRate: sampleRate)

        // Should be rejected as silence
        XCTAssertEqual(detectedPitch, 0.0, "Very quiet signal should be treated as silence")
    }

    /// Test with empty buffer
    func testPitchDetection_EmptyBuffer() {
        let sampleRate: Float = 44100.0
        let buffer = generateSilence(sampleRate: sampleRate, duration: 0.0)

        let detectedPitch = pitchDetector.detectPitch(buffer: buffer, sampleRate: sampleRate)

        XCTAssertEqual(detectedPitch, 0.0, "Empty buffer should return 0")
    }

    /// Test with frequency outside detection range (too high)
    func testPitchDetection_FrequencyTooHigh() {
        let sampleRate: Float = 44100.0
        let frequency: Float = 3000.0 // Above maxFrequency (2000 Hz)
        let duration: Float = 0.5
        let buffer = generateSineWave(frequency: frequency,
                                     sampleRate: sampleRate,
                                     duration: duration,
                                     amplitude: 0.5)

        let detectedPitch = pitchDetector.detectPitch(buffer: buffer, sampleRate: sampleRate)

        // Should be rejected as out of range
        XCTAssertEqual(detectedPitch, 0.0, "Frequency above 2000 Hz should be rejected")
    }


    // MARK: - Performance Tests

    /// Test that pitch detection completes within 10ms (real-time requirement)
    func testPitchDetection_Performance() {
        let sampleRate: Float = 44100.0
        let frequency: Float = 440.0
        let duration: Float = 0.1 // 100ms buffer (typical for real-time)
        let buffer = generateSineWave(frequency: frequency,
                                     sampleRate: sampleRate,
                                     duration: duration,
                                     amplitude: 0.5)

        measure {
            _ = pitchDetector.detectPitch(buffer: buffer, sampleRate: sampleRate)
        }

        // Note: Measure block automatically reports timing
        // For real-time audio, processing should be < 10ms per 100ms buffer
    }

    /// Test performance with realistic buffer size (2048 samples)
    func testPitchDetection_RealtimeBufferSize() {
        let sampleRate: Float = 44100.0
        let frequency: Float = 200.0
        let frameCount = 2048 // Typical real-time buffer size
        let duration = Float(frameCount) / sampleRate

        let buffer = generateSineWave(frequency: frequency,
                                     sampleRate: sampleRate,
                                     duration: duration,
                                     amplitude: 0.5)

        let startTime = Date()
        let detectedPitch = pitchDetector.detectPitch(buffer: buffer, sampleRate: sampleRate)
        let elapsedTime = Date().timeIntervalSince(startTime)

        XCTAssertLessThan(elapsedTime, 0.01, "Should process 2048 samples in < 10ms")
        XCTAssertGreaterThan(detectedPitch, 0, "Should detect pitch in real-time buffer")
        print("Real-time buffer processing time: \(elapsedTime * 1000) ms")
    }


    // MARK: - Helper Methods for Test Signal Generation

    /// Generate a pure sine wave at specified frequency
    private func generateSineWave(frequency: Float,
                                 sampleRate: Float,
                                 duration: Float,
                                 amplitude: Float) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                  sampleRate: Double(sampleRate),
                                  channels: 1,
                                  interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            return buffer
        }

        // Generate sine wave: y = A * sin(2π * f * t)
        for i in 0..<Int(frameCount) {
            let time = Float(i) / sampleRate
            channelData[i] = amplitude * sin(2.0 * .pi * frequency * time)
        }

        return buffer
    }

    /// Generate complex tone with harmonics (fundamental + overtones)
    private func generateComplexTone(fundamental: Float,
                                    harmonics: [Float], // Amplitude for each harmonic
                                    sampleRate: Float,
                                    duration: Float) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                  sampleRate: Double(sampleRate),
                                  channels: 1,
                                  interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            return buffer
        }

        // Generate fundamental + harmonics
        for i in 0..<Int(frameCount) {
            let time = Float(i) / sampleRate
            var sample: Float = 0.0

            for (harmonicIndex, amplitude) in harmonics.enumerated() {
                let harmonicFreq = fundamental * Float(harmonicIndex + 1)
                sample += amplitude * sin(2.0 * .pi * harmonicFreq * time)
            }

            channelData[i] = sample / Float(harmonics.count) // Normalize
        }

        return buffer
    }

    /// Generate silence
    private func generateSilence(sampleRate: Float, duration: Float) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                  sampleRate: Double(sampleRate),
                                  channels: 1,
                                  interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frameCount, 1))!
        buffer.frameLength = max(frameCount, 1)
        return buffer // Already initialized to zeros
    }

    /// Generate white noise
    private func generateWhiteNoise(sampleRate: Float,
                                   duration: Float,
                                   amplitude: Float) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                  sampleRate: Double(sampleRate),
                                  channels: 1,
                                  interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            return buffer
        }

        // Generate random noise
        for i in 0..<Int(frameCount) {
            channelData[i] = amplitude * (Float.random(in: -1.0...1.0))
        }

        return buffer
    }
}
