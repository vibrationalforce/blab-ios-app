import XCTest
@testable import Echoelmusic

/// Pure DSP tests for the lo-fi EchoelFX stages: Bitcrush, the M/S Stereo Widener,
/// and the Tape / VHS character. No audio device needed — exercises the math directly.
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

    // MARK: - Tape / VHS

    /// A DC constant passes any low-pass and any wobble-free tap unchanged once the
    /// ~6 ms read line has filled — the tape stage is unity on steady state.
    func testTape_ConstantConvergesToInput() {
        let tape = EchoelTape(sampleRate: 48000)
        tape.depth = 0; tape.saturation = 0; tape.tone = 1
        var out: Float = 0
        for _ in 0..<2048 { out = tape.processStereo(0.5, 0.5).0 }
        XCTAssertEqual(out, 0.5, accuracy: 0.01, "steady DC should pass through the tape stage")
    }

    /// The stage must never emit NaN/Inf or blow up, even at full drive + wobble.
    func testTape_StaysFiniteAndBounded() {
        let tape = EchoelTape(sampleRate: 48000)
        tape.depth = 1; tape.saturation = 1; tape.tone = 0.5
        for i in 0..<4096 {
            let x = Float(sinf(Float(i) * 0.05)) * 0.9
            let (l, r) = tape.processStereo(x, x)
            XCTAssertTrue(l.isFinite && r.isFinite, "tape output must stay finite")
            XCTAssertLessThan(abs(l), 2.0, "tape output must stay bounded")
        }
    }

    /// Tape saturation compresses a hot signal — a sustained loud constant comes
    /// out below its input level once the line fills.
    func testTape_SaturationCompressesHotSignal() {
        let tape = EchoelTape(sampleRate: 48000)
        tape.depth = 0; tape.saturation = 1; tape.tone = 1
        var out: Float = 0
        for _ in 0..<2048 { out = tape.processStereo(1.0, 1.0).0 }
        XCTAssertLessThan(out, 1.0, "saturation should tame a hot signal")
        XCTAssertGreaterThan(out, 0.0, "…without inverting or muting it")
    }

    /// Low brightness (worn tape) attenuates a fast-alternating (near-Nyquist)
    /// signal more than full brightness does.
    func testTape_LowBrightnessDullsHighs() {
        func nyquistEnergy(tone: Float) -> Float {
            let tape = EchoelTape(sampleRate: 48000)
            tape.depth = 0; tape.saturation = 0; tape.tone = tone
            var energy: Float = 0
            for i in 0..<2048 {
                let x: Float = (i % 2 == 0) ? 1 : -1     // alternating = Nyquist
                let (l, _) = tape.processStereo(x, x)
                if i > 512 { energy += l * l }           // measure after the line fills
            }
            return energy
        }
        XCTAssertLessThan(nyquistEnergy(tone: 0), nyquistEnergy(tone: 1),
                          "dull tape should lose more high-frequency energy")
    }

    func testTape_ResetClearsState() {
        let tape = EchoelTape(sampleRate: 48000)
        tape.depth = 0; tape.saturation = 0; tape.tone = 1
        for _ in 0..<2048 { _ = tape.processStereo(0.9, 0.9) }
        tape.reset()
        // After reset the line is empty; feeding silence must decay to ~0 quickly.
        var out: Float = 1
        for _ in 0..<2048 { out = tape.processStereo(0, 0).0 }
        XCTAssertEqual(out, 0, accuracy: 1e-4, "reset should clear the tape delay line")
    }
}
