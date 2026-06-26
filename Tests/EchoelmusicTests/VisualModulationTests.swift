import XCTest
@testable import Echoelmusic

/// Pure mapping tests for bio-reactive IMMERSIVE-VISUAL modulation: carrier signal →
/// visual-parameter offset, polarity, clamping, hue-wrap, multi-route sum, and the
/// non-destructive `apply`. Linux-verifiable (no GPU/UI).
final class VisualModulationTests: XCTestCase {

    private func base(_ blend: Float = 0, intensity: Float = 1.0, spread: Float = 1.0,
                      hue: Float = 0, detail: Float = 40) -> VisualParams {
        VisualParams(intensity: intensity, detail: detail, motion: 1.0, spread: spread,
                     hue: hue, saturation: 1.0, blend: blend)
    }

    private func bio(coherence: Float = 0, breathPhase: Float = 0, hr: Float = 60) -> BioSampleFrame {
        BioSampleFrame(timestamp: CFAbsoluteTimeGetCurrent(), heartRateBPM: hr,
                       hrvNormalized: 0.5, breathRate: 12, breathPhase: breathPhase,
                       coherence: coherence, motionEnergy: 0, source: .cameraPPG)
    }

    // MARK: - offset math (mirrors FXModulation)

    func testUnipolarBlend_FullSignal_AddsDepthTimesSpan() {
        // blend range 0...1, span 1, depth 0.5, signal 1 → +0.5.
        let o = VisualModulation.offset(target: .blend, signal: 1.0, depth: 0.5, bipolar: false)
        XCTAssertEqual(o, 0.5, accuracy: 1e-5)
    }

    func testBipolarSpread_MidSignal_IsNeutral() {
        let o = VisualModulation.offset(target: .spread, signal: 0.5, depth: 1.0, bipolar: true)
        XCTAssertEqual(o, 0, accuracy: 1e-5)
    }

    func testCombine_ClampsToTargetRange() {
        // intensity range 0...1.5: base 1.4 + 0.5 → clamps to 1.5.
        let v = VisualModulation.combine(base: 1.4, target: .intensity, offset: 0.5)
        XCTAssertEqual(v, 1.5, accuracy: 1e-5)
    }

    func testHue_Wraps_NotClamps() {
        // hue is a turn on the wheel: 0.8 + 0.5 → 1.3 → wraps to 0.3.
        let v = VisualModulation.combine(base: 0.8, target: .hue, offset: 0.5)
        XCTAssertEqual(v, 0.3, accuracy: 1e-5)
    }

    // MARK: - apply (non-destructive, multi-route)

    func testApply_NoEnabledRoutes_ReturnsBaseUnchanged() {
        let out = VisualModulation.apply(routes: [], base: base(), bio: bio(coherence: 1), lfoTime: 0)
        XCTAssertEqual(out, base())
    }

    func testApply_CoherenceDrivesBlend() {
        // Coherence 1.0 → Blend, unipolar depth 1.0 → blend goes base(0)+1 = 1.
        let r = VisualModRoute(carrier: .bio(.coherence), target: .blend, depth: 1.0, bipolar: false)
        let out = VisualModulation.apply(routes: [r], base: base(0), bio: bio(coherence: 1.0), lfoTime: 0)
        XCTAssertEqual(out.blend, 1.0, accuracy: 1e-4)
        // Untouched targets stay at base.
        XCTAssertEqual(out.intensity, 1.0, accuracy: 1e-5)
    }

    func testApply_NilBio_BioRoutesContributeNothing() {
        let r = VisualModRoute(carrier: .bio(.coherence), target: .blend, depth: 1.0, bipolar: false)
        let out = VisualModulation.apply(routes: [r], base: base(0.2), bio: nil, lfoTime: 0)
        XCTAssertEqual(out.blend, 0.2, accuracy: 1e-5)   // unchanged
    }

    func testApply_DisabledRouteIgnored() {
        var r = VisualModRoute(carrier: .bio(.coherence), target: .blend, depth: 1.0, bipolar: false)
        r.enabled = false
        let out = VisualModulation.apply(routes: [r], base: base(0.2), bio: bio(coherence: 1), lfoTime: 0)
        XCTAssertEqual(out.blend, 0.2, accuracy: 1e-5)
    }

    func testApply_TwoRoutesSumOnSameTarget() {
        // Two unipolar routes onto intensity: coherence 1 (depth 0.2 → +0.3 span1.5) +
        // breath 1 (depth 0.2 → +0.3) = +0.6 over base 0.5 → 1.1.
        let a = VisualModRoute(carrier: .bio(.coherence), target: .intensity, depth: 0.2, bipolar: false)
        let b = VisualModRoute(carrier: .bio(.breathPhase), target: .intensity, depth: 0.2, bipolar: false)
        let out = VisualModulation.apply(routes: [a, b], base: base(intensity: 0.5),
                                         bio: bio(coherence: 1.0, breathPhase: 1.0), lfoTime: 0)
        XCTAssertEqual(out.intensity, 1.1, accuracy: 1e-4)
    }

    func testApply_NonFiniteSafe() {
        // A NaN carrier can't happen (sources clamp), but combine guards base on non-finite.
        let v = VisualModulation.combine(base: 0.5, target: .intensity, offset: .nan)
        XCTAssertEqual(v, 0.5, accuracy: 1e-5)
    }
}
