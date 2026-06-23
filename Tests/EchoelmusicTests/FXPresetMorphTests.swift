import XCTest
@testable import Echoelmusic

/// Pure tests for the FX macro-morph (FXPreset.morphed) — Workstream 3.
final class FXPresetMorphTests: XCTestCase {

    /// Two presets differing in continuous + boolean params, built via capture from
    /// two configured chains so we exercise the real fields.
    private func presetA() -> FXPreset {
        let c = EchoelFXChain(sampleRate: 48000)
        c.reverbEnabled = false; c.reverb.mix = 0.0
        c.delayEnabled = true;   c.delay.mix = 0.2; c.delay.feedback = 0.1
        c.bitcrush.bits = 16
        return FXPreset.capture(from: c, fxEnabled: true, name: "A")
    }
    private func presetB() -> FXPreset {
        let c = EchoelFXChain(sampleRate: 48000)
        c.reverbEnabled = true;  c.reverb.mix = 0.8
        c.delayEnabled = true;   c.delay.mix = 0.6; c.delay.feedback = 0.5
        c.bitcrush.bits = 4
        return FXPreset.capture(from: c, fxEnabled: true, name: "B")
    }

    func testMorph_ZeroIsSelf() {
        let a = presetA(), b = presetB()
        let m = a.morphed(to: b, amount: 0)
        XCTAssertEqual(m.reverbMix, a.reverbMix, accuracy: 1e-5)
        XCTAssertEqual(m.delayMix, a.delayMix, accuracy: 1e-5)
        XCTAssertEqual(m.bitcrushBits, a.bitcrushBits, accuracy: 1e-5)
        XCTAssertEqual(m.reverbEnabled, a.reverbEnabled)
    }

    func testMorph_OneIsOther() {
        let a = presetA(), b = presetB()
        let m = a.morphed(to: b, amount: 1)
        XCTAssertEqual(m.reverbMix, b.reverbMix, accuracy: 1e-5)
        XCTAssertEqual(m.delayFeedback, b.delayFeedback, accuracy: 1e-5)
        XCTAssertEqual(m.bitcrushBits, b.bitcrushBits, accuracy: 1e-5)
        XCTAssertEqual(m.reverbEnabled, b.reverbEnabled)
    }

    func testMorph_HalfInterpolatesContinuous() {
        let a = presetA(), b = presetB()
        let m = a.morphed(to: b, amount: 0.5)
        XCTAssertEqual(m.reverbMix, (a.reverbMix + b.reverbMix) / 2, accuracy: 1e-5)
        XCTAssertEqual(m.delayMix, (a.delayMix + b.delayMix) / 2, accuracy: 1e-5)
        XCTAssertEqual(m.bitcrushBits, (a.bitcrushBits + b.bitcrushBits) / 2, accuracy: 1e-5)
    }

    func testMorph_ClampsAmount() {
        let a = presetA(), b = presetB()
        let lo = a.morphed(to: b, amount: -5)
        let hi = a.morphed(to: b, amount: 5)
        XCTAssertEqual(lo.reverbMix, a.reverbMix, accuracy: 1e-5)
        XCTAssertEqual(hi.reverbMix, b.reverbMix, accuracy: 1e-5)
    }

    func testMorph_RoundTripsThroughChain() {
        // Applying a half-morph to a chain then capturing should reflect the morph.
        let a = presetA(), b = presetB()
        let m = a.morphed(to: b, amount: 0.5)
        let c = EchoelFXChain(sampleRate: 48000)
        m.apply(to: c)
        XCTAssertEqual(c.reverb.mix, m.reverbMix, accuracy: 1e-5)
        XCTAssertEqual(c.delay.mix, m.delayMix, accuracy: 1e-5)
    }
}
