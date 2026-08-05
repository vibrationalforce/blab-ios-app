// TheMasterGainMovesInSmallStepsTests.swift
// Echoel — #404 Slice 2. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS PROTECTS. `AutoMixChain`'s auto-gain lands on an `AVAudioMixerNode`'s
// `outputVolume`, which has NO ramp: a write takes effect whole at the next render quantum.
// So the size of one application IS the size of an amplitude discontinuity in the master —
// i.e. a click. At the old one-application-per-200-ms rate a 6 dB correction stepped 1.08 dB,
// which is a −13.2 % jump, and the one-pole kept stepping every 200 ms while it converged: a
// burst of clicks, only while the level moves. That is what "teilweise extremes Knacken"
// sounds like and why it is intermittent.
//
// TWO PROPERTIES, AND THE SECOND IS THE ONE A FUTURE "SIMPLIFICATION" WOULD BREAK:
//   · every application must be small enough not to click, and
//   · the FEEL must be unchanged — the founder tuned "slow to boost, quicker to cut" by ear
//     (#183/#295), and a fix that quietly retunes it trades a click for a complaint.
// The second is why the sub-step coefficient is `1 − (1−c)^(1/n)` and not `c/n`: only the
// former reproduces the one-pole EXACTLY over n applications. `c/n` looks equivalent, is
// off by ~9 % on the cut path after one tick, and drifts further from there.
//
// ⚠️ THIS FILE PROVES A MECHANISM, NOT A DIAGNOSIS. It shows this stage can click and by how
// much. It cannot show that this stage is what the founder heard — only a device listen can,
// and #404 stays open until then.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMasterGainMovesInSmallStepsTests: XCTestCase {

    /// The shipped coefficients, named here so the test reads against the same two numbers
    /// the production call site passes.
    private let boost: Float = 0.05
    private let cut: Float = 0.18

    /// Linear amplitude ratio of a dB step — the number that decides audibility, since the
    /// mixer applies it as an instantaneous jump.
    private func linearJump(_ dB: Float) -> Double {
        abs(1 - Foundation.pow(10.0, Double(dB) / 20.0))
    }

    // MARK: - Small enough not to click

    /// The ceiling, in the domain's own unit. ⚠️ It is a JUDGEMENT, written as a number so it
    /// can be argued with rather than assumed: a gain step becomes an audible click on
    /// programme material somewhere around half a dB, and is inaudible even on a held tone
    /// below roughly a tenth. Two marks, so the test can say both "no longer clicks" and
    /// "and the ordinary case is comfortably under the stricter mark".
    ///
    /// ⛔ THE FIRST VERSION OF THIS FILE ASSERTED A 2 % LINEAR BUDGET AND WOULD HAVE FAILED —
    /// the worst legal cut step is 2.75 %. The tempting fix was to move the budget to 3 %,
    /// i.e. to pick the threshold that makes the code pass. That is backwards, and this repo
    /// has spent whole cycles undoing arguments built that way. The threshold is now stated in
    /// dB, chosen before the code was measured against it, and the worst case clears it 2×.
    private let clickCeilingDB: Float = 0.5
    private let inaudibleMarkDB: Float = 0.15

    func testNoSingleApplicationCanJumpTheMasterAudibly() {
        for coeff in [boost, cut] {
            let sub = AutoMixChain.subStepped(coeff)
            // The largest delta the stage can ever see: ±maxDB target against ∓maxDB current,
            // and `maxDB` is 6 (`steadyGainDB`). Everything else is smaller by construction.
            let worstStep = 12 * sub
            let message = "One auto-gain application steps the master by "
                + "\(String(format: "%.3f", Double(worstStep))) dB "
                + "(\(String(format: "%.2f", linearJump(worstStep) * 100)) % of amplitude), "
                + "over the \(clickCeilingDB) dB ceiling. `outputVolume` has no ramp, so that "
                + "is a click on every correction — the #404 defect."
            XCTAssertLessThan(worstStep, clickCeilingDB, message)
        }
    }

    func testAnOrdinaryCorrectionStepsBelowTheInaudibleMark() {
        // The worst LEGAL delta is a corner case (the target flips sign while the stage sits
        // fully deflected). A real correction is one `maxDB`, and that is the case the founder
        // actually hears — it must clear the stricter mark, not merely the click ceiling.
        for coeff in [boost, cut] {
            let step = 6 * AutoMixChain.subStepped(coeff)
            let message = "An ordinary 6 dB correction steps "
                + "\(String(format: "%.3f", Double(step))) dB, over the \(inaudibleMarkDB) dB mark."
            XCTAssertLessThan(step, inaudibleMarkDB, message)
        }
    }

    func testTheOldRateWouldHaveFailedThisTest() {
        // ⭐ THE TEST THAT MAKES THE TWO ABOVE MEAN SOMETHING. Without it, a future session
        // could set `subSteps` to 1, watch the ceiling assertion still pass on some smaller
        // coefficient, and conclude nothing was lost. This pins the actual before-number:
        // 2.16 dB, four times the ceiling, and −28 % of amplitude in one render boundary.
        let worstBefore = 12 * cut
        let message = "The pre-#404 behaviour is \(String(format: "%.2f", Double(worstBefore))) dB, "
            + "no longer above the \(clickCeilingDB) dB ceiling — so either the coefficients "
            + "moved or this file is measuring the wrong thing."
        XCTAssertGreaterThan(worstBefore, clickCeilingDB * 4, message)
    }

    // MARK: - …and the feel is unchanged, exactly

    func testTenSubStepsReproduceOneWholeStepExactly() {
        // The whole safety argument for changing the rate. If this drifts, the founder's
        // tuned anti-pumping envelope has been silently retuned.
        for coeff in [boost, cut] {
            let sub = AutoMixChain.subStepped(coeff)
            let target: Float = -6
            var eased: Float = 0
            for _ in 0..<AutoMixChain.subSteps { eased += (target - eased) * sub }
            let whole = (target - 0) * coeff
            XCTAssertEqual(eased, whole, accuracy: 0.0005,
                           "Ten sub-steps no longer land where one whole step landed. The "
                           + "coefficient must be 1−(1−c)^(1/n); c/n is NOT equivalent.")
        }
    }

    func testTheNaiveDivisionWouldNotHaveBeenEquivalent() {
        // Names the wrong answer so nobody re-derives it. c/n is the obvious move and it is
        // measurably different — this is the test that says by how much.
        let target: Float = -6
        var naive: Float = 0
        for _ in 0..<AutoMixChain.subSteps { naive += (target - naive) * (cut / Float(AutoMixChain.subSteps)) }
        let whole = target * cut
        XCTAssertNotEqual(naive, whole, accuracy: 0.005,
                          "c/n happens to match the one-pole here. If that is now true, the "
                          + "reasoning in `subSteps` needs re-reading before it is trusted.")
    }

    // MARK: - The edges

    func testTheCoefficientStaysInsideTheUnitInterval() {
        // Outside 0…1 the ease either stalls (≤0) or overshoots past the target (>1), and a
        // negative base would make `pow` return NaN — which on this node is silence.
        for raw in [Float(-1), 0, 0.5, 1, 2, .nan] {
            let sub = AutoMixChain.subStepped(raw)
            XCTAssertFalse(sub.isNaN, "A coefficient of \(raw) produced NaN.")
            XCTAssertGreaterThanOrEqual(sub, 0, "A coefficient of \(raw) went below zero.")
            XCTAssertLessThanOrEqual(sub, 1, "A coefficient of \(raw) went above one.")
        }
    }

    func testASingleSubStepIsTheIdentity() {
        // n = 1 must return the coefficient untouched, so the helper can be used at any rate
        // including the old one without a special case at the call site.
        XCTAssertEqual(AutoMixChain.subStepped(cut, over: 1), cut, accuracy: 0.000001)
        XCTAssertEqual(AutoMixChain.subStepped(cut, over: 0), cut, accuracy: 0.000001,
                       "A nonsensical count must degrade to the identity, not to a division "
                       + "by zero.")
    }

    // MARK: - The wiring (the timer and the call site live in a private method)

    func testTheMeasurementRateDidNotFollowTheApplicationRate() throws {
        // ⚠️ THE FREEZE LAW, AS A TEST. `lufsReading` is observation-tracked and feeds the
        // loudness readout; publishing it at the 50 Hz application rate would put a 50 Hz
        // write in front of a SwiftUI body — the 10.76.50 menu-freeze class. So the timer
        // fires fast and the MEASUREMENT is gated behind the sub-step counter. A positive
        // scan on that gate, because a negative scan cannot tell code from prose (#367).
        let source = try Self.chainSource()
        let gateMessage = "The measurement is no longer gated behind the sub-step counter. If "
            + "the meter now reads at the application rate, `lufsReading` publishes at 50 Hz "
            + "and every open Picker dies while the master moves."
        XCTAssertTrue(source.contains("if self.easeTick >= Self.subSteps"), gateMessage)
        XCTAssertTrue(source.contains("self.updateAutoGain()"),
                      "The gain is no longer applied on every tick, which is the fix itself.")
    }

    func testTheApplicationUsesTheSubSteppedCoefficients() throws {
        // The helper existing and being correct is worth nothing if the call site still
        // passes the whole-tick numbers — a pure core with no caller is the same defect with
        // more steps, which this repo has paid for before.
        let source = try Self.chainSource()
        XCTAssertTrue(source.contains("boostCoeff: Self.subStepped(0.05)"),
                      "The boost path is back on the whole-tick coefficient.")
        let cutMessage = "The cut path is back on the whole-tick coefficient — that is the "
            + "loud one, 3.6× the boost step."
        XCTAssertTrue(source.contains("cutCoeff: Self.subStepped(0.18)"), cutMessage)
    }

    private static func chainSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/CISmoke
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/Echoelmusic/Audio/AutoMixChain.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
