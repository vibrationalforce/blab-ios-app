// VisualEnergyTests.swift
// Echoel — #228: the ONE visual control is a DERIVED binding, so its whole
// correctness is "is `position` the exact inverse of `look`". If it is not, the dial
// jumps under the finger on the first drag — the classic lying control.
//
// In `Tests/CISmoke` on purpose: this is the only bundle a push actually COMPILES AND
// RUNS (`ci.yml` build-for-testing + test-without-building). A round-trip law that
// lived in the non-blocking suite would not be executed at all.

import XCTest
@testable import Echoelmusic

final class VisualEnergyTests: XCTestCase {

    // MARK: - The round trip (the dial must not jump under the finger)

    func testPositionIsTheExactInverseOfLook() {
        for i in 0...20 {
            let t = Double(i) / 20
            let l = VisualEnergy.look(at: t)
            let back = VisualEnergy.position(matching: l.intensity, motion: l.motion)
            XCTAssertEqual(back, t, accuracy: 1e-9,
                           "dial position must survive a look→position round trip at t=\(t)")
        }
    }

    func testLookIsMonotonicInEveryParameterItDrives() {
        // The whole justification for putting these two — and NOT Detail or Spread — on
        // one dial: a single monotonic control may only carry monotonic parameters.
        var prev = VisualEnergy.look(at: 0)
        for i in 1...20 {
            let now = VisualEnergy.look(at: Double(i) / 20)
            XCTAssertGreaterThan(now.intensity, prev.intensity, "intensity must rise with energy")
            XCTAssertGreaterThan(now.motion, prev.motion, "motion must rise with energy")
            prev = now
        }
    }

    /// The measured reason Spread is not on the dial, pinned so a future "let's add the
    /// other two energy params" cannot quietly reintroduce a non-monotonic axis.
    func testSpreadIsNotMonotonicAcrossTheCuratedSet_whichIsWhyItIsNotOnTheDial() {
        let spreads = VisualPreset.factory.map(\.spread)
        XCTAssertGreaterThan(spreads.count, 2, "needs at least three stops to show a reversal")
        // `$0` is the zipped PAIR, not two arguments — a `{ $0 < $1 }` here would not
        // compile, and the version of this file that had it would have failed the gate.
        let risesSomewhere = zip(spreads, spreads.dropFirst()).contains { $0.0 < $0.1 }
        let fallsSomewhere = zip(spreads, spreads.dropFirst()).contains { $0.0 > $0.1 }
        XCTAssertTrue(risesSomewhere && fallsSomewhere,
                      "spread goes down AND up across a set ordered softest→most energetic — "
                      + "it does not track energy and must stay a fine-tune field")
    }

    // MARK: - The endpoints are the CURATED set, not invented numbers

    func testEndpointsMatchTheCuratedPresetExtremes() {
        let factory = VisualPreset.factory
        XCTAssertFalse(factory.isEmpty, "the spans are derived from this set — an empty one is a bug")

        let calm = VisualEnergy.look(at: 0)
        let hot = VisualEnergy.look(at: 1)
        XCTAssertEqual(calm.intensity, Double(factory.map(\.intensity).min() ?? 0), accuracy: 1e-9)
        XCTAssertEqual(hot.intensity, Double(factory.map(\.intensity).max() ?? 0), accuracy: 1e-9)
        XCTAssertEqual(calm.motion, Double(factory.map(\.motion).min() ?? 0), accuracy: 1e-9)
        XCTAssertEqual(hot.motion, Double(factory.map(\.motion).max() ?? 0), accuracy: 1e-9)
    }

    /// The dial may never ask for more than the curated set already asks for. The flash
    /// cap in the renderer is the safety net; this pins that the CONTROL itself does not
    /// hand the renderer a larger number than any shipped preset does.
    func testTheDialNeverLeavesTheCuratedRange() {
        let maxMotion = Double(VisualPreset.factory.map(\.motion).max() ?? 1.5)
        for i in 0...10 {
            let m = VisualEnergy.look(at: Double(i) / 10).motion
            XCTAssertLessThanOrEqual(m, maxMotion + 1e-9)
            XCTAssertGreaterThanOrEqual(m, 0)
        }
    }

    // MARK: - Edge cases (the rule: never ship the happy path only)

    func testNonFiniteAndOutOfRangePositionsDegradeToAnEndpoint() {
        let calm = VisualEnergy.look(at: 0)
        let hot = VisualEnergy.look(at: 1)

        for bad in [Double.nan, -Double.infinity, -5] {
            let l = VisualEnergy.look(at: bad)
            XCTAssertEqual(l.intensity, calm.intensity, accuracy: 1e-9,
                           "a non-finite or negative position reads as the calm end, never unclamped")
            XCTAssertEqual(l.motion, calm.motion, accuracy: 1e-9)
        }
        for big in [Double.infinity, 42] {
            let l = VisualEnergy.look(at: big)
            XCTAssertEqual(l.motion, hot.motion, accuracy: 1e-9, "above 1 clamps to the hot end")
        }
    }

    func testNonFiniteLiveValuesDoNotProduceANonFinitePosition() {
        // A poisoned stored value must not turn the dial itself into NaN — that would
        // propagate into the renderer's uniforms on the very next frame.
        let p = VisualEnergy.position(matching: Double.nan, motion: Double.infinity)
        XCTAssertTrue(p.isFinite, "the dial position must stay finite for any stored value")
        XCTAssertGreaterThanOrEqual(p, 0)
        XCTAssertLessThanOrEqual(p, 1)
    }

    /// OFF-CURVE STATE — the case the reviewer found documented but unpinned. The fine-tune
    /// Intensity row ranges to 1.5 while the curated span tops out at 1.4, so a hand edit can
    /// put the values somewhere `look(at:)` can never produce. Two laws matter there:
    /// the dial must still read a finite, in-range position (it must not refuse to show), and
    /// values above the span top must NOT be distinguishable — they all sit at 1. Pinned so
    /// that "a 1 % dial nudge can be a large parameter change from off-curve" stays a
    /// deliberate macro-control property instead of turning into a bug report later.
    func testAnOffCurveHandEditStillReadsAFinitePositionAndSaturatesAtTheSpanTop() {
        let calmMotion = VisualEnergy.look(at: 0).motion
        let atTop = VisualEnergy.position(matching: 1.4, motion: calmMotion)
        let aboveTop = VisualEnergy.position(matching: 1.5, motion: calmMotion)
        XCTAssertEqual(atTop, 0.5, accuracy: 1e-9,
                       "intensity at the span top + motion at the bottom ⇒ the centre")
        XCTAssertEqual(aboveTop, atTop, accuracy: 1e-9,
                       "above the span top the position saturates — 1.5 and 1.4 read alike")

        // And the first move from that off-curve state lands exactly on the curve: whatever
        // the dial is set to, BOTH values come back as `look(at:)` of that position.
        let target = 0.25
        let l = VisualEnergy.look(at: target)
        XCTAssertEqual(VisualEnergy.position(matching: l.intensity, motion: l.motion),
                       target, accuracy: 1e-9,
                       "after one move the state is back on the curve, so the dial is exact again")
    }

    func testAMixedHandEditedLookReadsAsTheCentreOfItsParameters() {
        // Intensity at the hot end, motion at the calm end ⇒ (1 + 0)/2.
        let hot = VisualEnergy.look(at: 1)
        let calm = VisualEnergy.look(at: 0)
        let p = VisualEnergy.position(matching: hot.intensity, motion: calm.motion)
        XCTAssertEqual(p, 0.5, accuracy: 1e-9,
                       "a custom look shows the centre of its parameters, not one of them")
    }
}
