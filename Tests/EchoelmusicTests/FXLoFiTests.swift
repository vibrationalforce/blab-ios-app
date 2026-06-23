import XCTest
@testable import Echoelmusic

/// Pure DSP tests for the two new EchoelFX stages (Workstream 2): Bitcrush + the
/// M/S Stereo Widener. No audio device needed — exercises the math directly.
final class FXLoFiTests: XCTestCase {

    // MARK: - Bitcrush

    func testBitcrush_16Bit_FullRate_IsNearlyTransparent() {
        let bc = EchoelBitcrush(sampleRate: 48000)
        bc.bits = 16; bc.downsample = 1; bc.mix = 1
        for x in [Float(-0.9), -0.3, 0, 0.25, 0.7, 0.95] {
            let (l, r) = bc.processStereo(x, x)
            XCTAssertEqual(l, x, accuracy: 0.001, "16-bit should be ~transparent")
            XCTAssertEqual(r, x, accuracy: 0.001)
        }
    }

    func testBitcrush_DryWhenMixZero() {
        let bc = EchoelBitcrush(sampleRate: 48000)
        bc.bits = 1; bc.downsample = 8; bc.mix = 0     // extreme crush, but fully dry
        let (l, r) = bc.processStereo(0.31, -0.42)
        XCTAssertEqual(l, 0.31, accuracy: 1e-6)
        XCTAssertEqual(r, -0.42, accuracy: 1e-6)
    }

    func testBitcrush_LowBits_Quantizes() {
        let bc = EchoelBitcrush(sampleRate: 48000)
        bc.bits = 1; bc.downsample = 1; bc.mix = 1      // levels = 2^1-1 = 1 → round()
        // 0.3 rounds to 0; 0.7 rounds to 1 — coarse quantisation is audible-crushed.
        XCTAssertEqual(bc.processStereo(0.30, 0.30).0, 0.0, accuracy: 1e-6)
        XCTAssertEqual(bc.processStereo(0.70, 0.70).0, 1.0, accuracy: 1e-6)
    }

    func testBitcrush_Downsample_HoldsSamples() {
        let bc = EchoelBitcrush(sampleRate: 48000)
        bc.bits = 16; bc.downsample = 4; bc.mix = 1     // hold each input for 4 samples
        let first = bc.processStereo(0.5, 0.5).0        // refreshes hold → ~0.5
        XCTAssertEqual(first, 0.5, accuracy: 0.001)
        // Next 3 inputs are ignored (held at 0.5) despite a very different input.
        for _ in 0..<3 {
            let held = bc.processStereo(-0.9, -0.9).0
            XCTAssertEqual(held, 0.5, accuracy: 0.001, "sample-and-hold keeps the old value")
        }
        // The 5th input refreshes the hold to the new value.
        let refreshed = bc.processStereo(-0.9, -0.9).0
        XCTAssertEqual(refreshed, -0.9, accuracy: 0.001)
    }

    func testBitcrush_ResetClearsHold() {
        let bc = EchoelBitcrush(sampleRate: 48000)
        bc.bits = 16; bc.downsample = 10; bc.mix = 1
        _ = bc.processStereo(0.8, 0.8)
        bc.reset()
        // After reset the counter is 0 → the next sample refreshes immediately.
        let v = bc.processStereo(-0.4, -0.4).0
        XCTAssertEqual(v, -0.4, accuracy: 0.001)
    }

    // MARK: - Stereo widener

    func testWidener_UnityIsUnchanged() {
        let w = EchoelStereoWidener(sampleRate: 48000)
        w.width = 1
        let (l, r) = w.processStereo(0.8, 0.2)
        XCTAssertEqual(l, 0.8, accuracy: 1e-6)
        XCTAssertEqual(r, 0.2, accuracy: 1e-6)
    }

    func testWidener_ZeroIsMono() {
        let w = EchoelStereoWidener(sampleRate: 48000)
        w.width = 0
        let (l, r) = w.processStereo(0.8, 0.2)   // mid = 0.5
        XCTAssertEqual(l, 0.5, accuracy: 1e-6)
        XCTAssertEqual(r, 0.5, accuracy: 1e-6)
    }

    func testWidener_TwoDoublesSide() {
        let w = EchoelStereoWidener(sampleRate: 48000)
        w.width = 2
        let (l, r) = w.processStereo(0.8, 0.2)   // mid 0.5, side 0.3*2 = 0.6
        XCTAssertEqual(l, 1.1, accuracy: 1e-6)
        XCTAssertEqual(r, -0.1, accuracy: 1e-6)
    }

    func testWidener_ClampsWidth() {
        let w = EchoelStereoWidener(sampleRate: 48000)
        w.width = 99                              // clamped to 2
        let (l, _) = w.processStereo(0.8, 0.2)
        XCTAssertEqual(l, 1.1, accuracy: 1e-6, "width clamps to 2")
    }
}
