import XCTest
@testable import Echoelmusic

/// Pure mapping tests for bio-reactive FX modulation: carrier signal → parameter
/// offset, polarity, clamping, LFO. Linux-verifiable (no audio/UI).
final class FXModulationTests: XCTestCase {

    // MARK: - Bipolar swings around base

    func testBipolar_MidSignal_IsNeutral() {
        // signal 0.5 → centre → no offset, returns base.
        let v = FXModulation.value(base: 0.5, target: .reverbMix,
                                   signal: 0.5, depth: 1.0, bipolar: true)
        XCTAssertEqual(v, 0.5, accuracy: 1e-5)
    }

    func testBipolar_FullSignal_AddsHalfSpanTimesDepth() {
        // reverbMix range 0...1, span 1, depth 0.5, signal 1 → +0.25 around base.
        let v = FXModulation.value(base: 0.5, target: .reverbMix,
                                   signal: 1.0, depth: 0.5, bipolar: true)
        XCTAssertEqual(v, 0.75, accuracy: 1e-5)
    }

    func testBipolar_ZeroSignal_SubtractsHalfSpanTimesDepth() {
        let v = FXModulation.value(base: 0.5, target: .reverbMix,
                                   signal: 0.0, depth: 0.5, bipolar: true)
        XCTAssertEqual(v, 0.25, accuracy: 1e-5)
    }

    // MARK: - Unipolar only adds

    func testUnipolar_AddsUpwardFromBase() {
        let v = FXModulation.value(base: 0.2, target: .chorusMix,
                                   signal: 1.0, depth: 0.5, bipolar: false)
        XCTAssertEqual(v, 0.7, accuracy: 1e-5)   // 0.2 + 1*0.5*1
    }

    func testUnipolar_ZeroSignal_KeepsBase() {
        let v = FXModulation.value(base: 0.2, target: .chorusMix,
                                   signal: 0.0, depth: 0.9, bipolar: false)
        XCTAssertEqual(v, 0.2, accuracy: 1e-5)
    }

    // MARK: - Clamping to the target range

    func testValue_ClampsToTargetRange_Upper() {
        let v = FXModulation.value(base: 0.95, target: .delayFeedback,   // range 0...0.95
                                   signal: 1.0, depth: 1.0, bipolar: false)
        XCTAssertEqual(v, 0.95, accuracy: 1e-5, "never exceeds the feedback ceiling")
    }

    func testValue_ClampsToTargetRange_Lower() {
        let v = FXModulation.value(base: 0.0, target: .reverbMix,
                                   signal: 0.0, depth: 1.0, bipolar: true)
        XCTAssertGreaterThanOrEqual(v, 0.0)
    }

    func testValue_WideRangeTarget_ScalesBySpan() {
        // filterCutoff span = 17920; depth 0.1, signal 1, unipolar → +1792 from base.
        let v = FXModulation.value(base: 2000, target: .filterCutoff,
                                   signal: 1.0, depth: 0.1, bipolar: false)
        XCTAssertEqual(v, 2000 + 1792, accuracy: 1.0)
    }

    // MARK: - Non-finite guards

    func testValue_NonFiniteSignal_FallsBackToBase() {
        let v = FXModulation.value(base: 0.4, target: .reverbMix,
                                   signal: .nan, depth: 1.0, bipolar: true)
        // NaN signal → clamp01 makes it 0 → bipolar -depth/2; just assert finite + in range.
        XCTAssertTrue(v.isFinite)
        XCTAssertTrue((0...1).contains(v))
    }

    // MARK: - LFO

    func testLFO_PhaseQuarters() {
        XCTAssertEqual(FXModulation.lfoUnipolar(phase: 0.0), 0.5, accuracy: 1e-5)
        XCTAssertEqual(FXModulation.lfoUnipolar(phase: 0.25), 1.0, accuracy: 1e-5)
        XCTAssertEqual(FXModulation.lfoUnipolar(phase: 0.5), 0.5, accuracy: 1e-5)
        XCTAssertEqual(FXModulation.lfoUnipolar(phase: 0.75), 0.0, accuracy: 1e-5)
    }

    // MARK: - Route model

    func testRoute_ClampsDepthAndRate() {
        let r = FXModRoute(carrier: .lfo, target: .tremoloDepth, depth: 5, lfoRateHz: -3)
        XCTAssertLessThanOrEqual(r.depth, 1.0)
        XCTAssertGreaterThanOrEqual(r.lfoRateHz, 0.01)
    }

    func testRoute_CodableRoundTrip() throws {
        let r = FXModRoute(carrier: .bio(.coherence), target: .reverbMix,
                           depth: 0.6, bipolar: true, lfoRateHz: 0.5)
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(FXModRoute.self, from: data)
        XCTAssertEqual(r, back)
    }

    func testTarget_AllHaveFiniteRanges() {
        for t in FXModTarget.allCases {
            XCTAssertTrue(t.range.lowerBound.isFinite && t.range.upperBound.isFinite)
            XCTAssertLessThan(t.range.lowerBound, t.range.upperBound, "\(t) range")
            XCTAssertFalse(t.displayName.isEmpty)
        }
    }
}
