import XCTest
import AVFoundation
@testable import Blab

/// Unit tests for BinauralBeatGenerator
/// Tests binaural/isochronic mode, frequency accuracy, and brainwave presets
@MainActor
final class BinauralBeatTests: XCTestCase {

    var generator: BinauralBeatGenerator!

    override func setUp() async throws {
        generator = BinauralBeatGenerator()
    }

    override func tearDown() {
        generator?.stop()
        generator = nil
    }


    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        XCTAssertEqual(generator.carrierFrequency, 432.0, "Default carrier should be 432 Hz")
        XCTAssertEqual(generator.beatFrequency, 10.0, "Default beat should be 10 Hz (Alpha)")
        XCTAssertEqual(generator.amplitude, 0.3, "Default amplitude should be 0.3")
    }

    func testCustomConfiguration() {
        generator.configure(carrier: 528.0, beat: 6.0, amplitude: 0.5)

        XCTAssertEqual(generator.carrierFrequency, 528.0)
        XCTAssertEqual(generator.beatFrequency, 6.0)
        XCTAssertEqual(generator.amplitude, 0.5)
    }

    func testAmplitudeClamping() {
        // Test upper bound
        generator.configure(carrier: 432.0, beat: 10.0, amplitude: 1.5)
        XCTAssertEqual(generator.amplitude, 1.0, "Amplitude should clamp to 1.0")

        // Test lower bound
        generator.configure(carrier: 432.0, beat: 10.0, amplitude: -0.5)
        XCTAssertEqual(generator.amplitude, 0.0, "Amplitude should clamp to 0.0")
    }


    // MARK: - Brainwave Preset Tests

    func testDeltaPreset() {
        generator.configure(state: .delta)
        XCTAssertEqual(generator.beatFrequency, 2.0, "Delta should be 2 Hz")
    }

    func testThetaPreset() {
        generator.configure(state: .theta)
        XCTAssertEqual(generator.beatFrequency, 6.0, "Theta should be 6 Hz")
    }

    func testAlphaPreset() {
        generator.configure(state: .alpha)
        XCTAssertEqual(generator.beatFrequency, 10.0, "Alpha should be 10 Hz")
    }

    func testBetaPreset() {
        generator.configure(state: .beta)
        XCTAssertEqual(generator.beatFrequency, 20.0, "Beta should be 20 Hz")
    }

    func testGammaPreset() {
        generator.configure(state: .gamma)
        XCTAssertEqual(generator.beatFrequency, 40.0, "Gamma should be 40 Hz")
    }

    func testAllBrainwaveStates() {
        let expectedFrequencies: [BinauralBeatGenerator.BrainwaveState: Float] = [
            .delta: 2.0,
            .theta: 6.0,
            .alpha: 10.0,
            .beta: 20.0,
            .gamma: 40.0
        ]

        for (state, expectedFreq) in expectedFrequencies {
            generator.configure(state: state)
            XCTAssertEqual(generator.beatFrequency, expectedFreq,
                          "\(state.rawValue) should be \(expectedFreq) Hz")
        }
    }


    // MARK: - HRV Coherence Adaptation Tests

    func testHRVCoherenceLow() {
        // Low coherence (0-40) should promote relaxation (Alpha 10 Hz)
        generator.setBeatFrequencyFromHRV(coherence: 20.0)
        XCTAssertEqual(generator.beatFrequency, 10.0, "Low coherence should set Alpha (10 Hz)")
    }

    func testHRVCoherenceMedium() {
        // Medium coherence (40-60) should transition to focus (15 Hz)
        generator.setBeatFrequencyFromHRV(coherence: 50.0)
        XCTAssertEqual(generator.beatFrequency, 15.0, "Medium coherence should set 15 Hz")
    }

    func testHRVCoherenceHigh() {
        // High coherence (60-100) should maintain focus (Beta 20 Hz)
        generator.setBeatFrequencyFromHRV(coherence: 80.0)
        XCTAssertEqual(generator.beatFrequency, 20.0, "High coherence should set Beta (20 Hz)")
    }

    func testHRVCoherenceEdgeCases() {
        // Test boundary values
        generator.setBeatFrequencyFromHRV(coherence: 0.0)
        XCTAssertEqual(generator.beatFrequency, 10.0)

        generator.setBeatFrequencyFromHRV(coherence: 40.0)
        XCTAssertEqual(generator.beatFrequency, 15.0)

        generator.setBeatFrequencyFromHRV(coherence: 60.0)
        XCTAssertEqual(generator.beatFrequency, 20.0)

        generator.setBeatFrequencyFromHRV(coherence: 100.0)
        XCTAssertEqual(generator.beatFrequency, 20.0)
    }


    // MARK: - Audio Mode Tests

    func testDefaultAudioMode() {
        // Should default to binaural before detection
        XCTAssertEqual(generator.audioMode, .binaural, "Should default to binaural")
    }

    func testAudioModeEnum() {
        // Test that enum cases exist
        let binaural = BinauralBeatGenerator.AudioMode.binaural
        let isochronic = BinauralBeatGenerator.AudioMode.isochronic

        XCTAssertNotNil(binaural)
        XCTAssertNotNil(isochronic)
    }


    // MARK: - Lifecycle Tests

    func testStartStop() {
        XCTAssertFalse(generator.isPlaying, "Should not be playing initially")

        generator.start()
        // Note: May or may not actually start depending on permissions/hardware
        // We just test it doesn't crash

        generator.stop()
        XCTAssertFalse(generator.isPlaying, "Should not be playing after stop")
    }

    func testMultipleStarts() {
        // Starting multiple times should not crash
        generator.start()
        generator.start()
        generator.start()

        generator.stop()
    }

    func testMultipleStops() {
        // Stopping multiple times should not crash
        generator.stop()
        generator.stop()
        generator.stop()

        XCTAssertFalse(generator.isPlaying)
    }


    // MARK: - Integration Tests

    func testConfigureWhilePlaying() {
        generator.start()

        // Should be able to reconfigure while playing
        generator.configure(carrier: 528.0, beat: 8.0, amplitude: 0.4)

        XCTAssertEqual(generator.carrierFrequency, 528.0)
        XCTAssertEqual(generator.beatFrequency, 8.0)

        generator.stop()
    }

    func testPresetChangeWhilePlaying() {
        generator.configure(state: .alpha)
        generator.start()

        // Change preset while playing
        generator.configure(state: .beta)
        XCTAssertEqual(generator.beatFrequency, 20.0)

        generator.stop()
    }


    // MARK: - Performance Tests

    func testConfigurationPerformance() {
        measure {
            for _ in 0..<100 {
                generator.configure(carrier: 432.0, beat: 10.0, amplitude: 0.3)
            }
        }
    }

    func testPresetSwitchingPerformance() {
        measure {
            let states: [BinauralBeatGenerator.BrainwaveState] = [.delta, .theta, .alpha, .beta, .gamma]
            for state in states {
                generator.configure(state: state)
            }
        }
    }


    // MARK: - Edge Case Tests

    func testZeroBeatFrequency() {
        generator.configure(carrier: 432.0, beat: 0.0, amplitude: 0.3)
        XCTAssertEqual(generator.beatFrequency, 0.0, "Should allow 0 Hz beat (pure tone)")
    }

    func testHighBeatFrequency() {
        generator.configure(carrier: 432.0, beat: 100.0, amplitude: 0.3)
        XCTAssertEqual(generator.beatFrequency, 100.0, "Should allow high beat frequencies")
    }

    func testLowCarrierFrequency() {
        generator.configure(carrier: 50.0, beat: 10.0, amplitude: 0.3)
        XCTAssertEqual(generator.carrierFrequency, 50.0, "Should allow low carrier frequencies")
    }

    func testHighCarrierFrequency() {
        generator.configure(carrier: 1000.0, beat: 10.0, amplitude: 0.3)
        XCTAssertEqual(generator.carrierFrequency, 1000.0, "Should allow high carrier frequencies")
    }


    // MARK: - Brainwave State Description Tests

    func testBrainwaveDescriptions() {
        XCTAssertFalse(BinauralBeatGenerator.BrainwaveState.delta.description.isEmpty)
        XCTAssertFalse(BinauralBeatGenerator.BrainwaveState.theta.description.isEmpty)
        XCTAssertFalse(BinauralBeatGenerator.BrainwaveState.alpha.description.isEmpty)
        XCTAssertFalse(BinauralBeatGenerator.BrainwaveState.beta.description.isEmpty)
        XCTAssertFalse(BinauralBeatGenerator.BrainwaveState.gamma.description.isEmpty)
    }

    func testAllCasesIteration() {
        let allStates = BinauralBeatGenerator.BrainwaveState.allCases
        XCTAssertEqual(allStates.count, 5, "Should have 5 brainwave states")

        // Verify all expected states are present
        XCTAssertTrue(allStates.contains(.delta))
        XCTAssertTrue(allStates.contains(.theta))
        XCTAssertTrue(allStates.contains(.alpha))
        XCTAssertTrue(allStates.contains(.beta))
        XCTAssertTrue(allStates.contains(.gamma))
    }
}
