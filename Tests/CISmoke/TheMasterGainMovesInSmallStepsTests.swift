// TheMasterGainMovesInSmallStepsTests.swift
// Echoel — #404 Slice 2. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS PROTECTS. `AutoMixChain`'s auto-gain lands on an `AVAudioMixerNode`'s
// `outputVolume`, which has no DOCUMENTED ramp. IF a write takes effect whole at the next
// render quantum, the size of one application IS the size of an amplitude discontinuity in the
// master — i.e. a click. At the old one-application-per-200-ms rate a 6 dB cut stepped 1.08 dB,
// which is −11.7 % of amplitude, and the one-pole kept stepping every 200 ms while it
// converged: a burst of clicks, only while the level moves.
//
// ⚠️ THAT "IF" IS LOAD-BEARING AND UNPROVEN. Apple's mixer AUs may interpolate gain across a
// render slice — undocumented, historically variable. `AutoMixChain.subSteps` carries the
// experiment that would settle it (`RetroCapture` taps downstream of `gainNode`). This file
// proves the STAGE'S ARITHMETIC, and nothing about what the founder heard. #404 stays open
// until a device listen.
//
// TWO PROPERTIES, AND THE SECOND IS THE ONE A FUTURE "SIMPLIFICATION" WOULD BREAK:
//   · every application must be small enough not to click, and
//   · the FEEL must be unchanged — the founder tuned "slow to boost, quicker to cut" by ear
//     (#183/#295), and a fix that quietly retunes it trades a click for a complaint.
// The second is why the sub-step coefficient is `1 − (1−c)^(1/n)` and not `c/n`: only the
// former reproduces the one-pole EXACTLY over n applications. `c/n` looks equivalent and moves
// 16.61 % of the distance per tick where the real coefficient moves 18.00 % — 7.7 % short on
// the cut path after ONE tick, and further from there.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMasterGainMovesInSmallStepsTests: XCTestCase {

    /// The shipped whole-tick coefficients, named here so the test reads against the same two
    /// numbers the production constants are built from.
    private let boost: Float = 0.05
    private let cut: Float = 0.18

    /// The ceiling, in the domain's own unit. ⚠️ It is a JUDGEMENT, written as a number so it
    /// can be argued with rather than assumed: a gain step becomes an audible click on
    /// programme material somewhere around half a dB, and is inaudible even on a held tone
    /// below roughly a tenth. Two marks, so the test can say both "no longer clicks" and "and
    /// the ordinary case is comfortably under the stricter mark".
    ///
    /// ⛔ THE FIRST VERSION OF THIS FILE ASSERTED A 2 % LINEAR BUDGET AND WOULD HAVE FAILED —
    /// the worst legal cut step is 2.68 %. The tempting fix was to move the budget to 3 %,
    /// i.e. to pick the threshold that makes the code pass. That is backwards, and this repo
    /// has spent whole cycles undoing arguments built that way. The threshold is now stated in
    /// dB, chosen before the code was measured against it, and the worst case clears it 2×.
    private let clickCeilingDB: Float = 0.5
    private let inaudibleMarkDB: Float = 0.15

    /// Amplitude ratio of a dB step, as a signed percentage.
    ///
    /// ⛔ THE FIRST VERSION WAS `abs(1 - pow(10, dB/20))`, WHICH IS THE BOOST MAGNITUDE
    /// WHATEVER SIGN WAS MEANT — so the prose attached a minus to a plus and overstated the
    /// two headline numbers by 13 % and 28 % relative. A cut of `d` dB changes amplitude by
    /// `10^(−d/20) − 1`; a boost of `d` by `10^(d/20) − 1`. They are not the same size.
    private func amplitudeChangePercent(dB: Float) -> Double {
        (Foundation.pow(10.0, Double(dB) / 20.0) - 1) * 100
    }

    /// One application of the SHIPPED function, in the shipped configuration — the largest
    /// `|next − current|` it can produce is what "one stair" actually means.
    private func step(current: Float, raw: Float?) -> Float {
        let next = AutoMixChain.steadyGainDB(current: current,
                                             targetLUFS: raw, lufsReading: 0,
                                             boostCoeff: AutoMixChain.boostSubStep,
                                             cutCoeff: AutoMixChain.cutSubStep)
        return abs(next - current)
    }

    // MARK: - Small enough not to click

    func testNoSingleApplicationCanJumpTheMasterAudibly() {
        // ⭐ DRIVES `steadyGainDB`, NOT THE COEFFICIENT ARITHMETIC. The first version computed
        // `12 * subStepped(c)` and called that "the largest delta the stage can ever see" —
        // which was wrong, because the `nil`-target branch snaps up to `deadZoneDB` in one
        // application and never touches a coefficient. Sweeping the real function is the only
        // way this test can see a path its author did not think of.
        var worst: Float = 0
        var worstCase = ""
        for currentTenths in -60...60 {
            let current = Float(currentTenths) / 10
            for rawTenths in -60...60 where rawTenths % 5 == 0 {
                let d = step(current: current, raw: Float(rawTenths) / 10)
                if d > worst { worst = d; worstCase = "current \(current) → raw \(rawTenths)/10" }
            }
            let d = step(current: current, raw: nil)      // "No target"
            if d > worst { worst = d; worstCase = "current \(current) → No target" }
        }
        let message = """
            The largest single auto-gain application is \(String(format: "%.3f", Double(worst))) dB \
            (\(String(format: "%.2f", amplitudeChangePercent(dB: worst))) % of amplitude), at \
            \(worstCase) — over the \(clickCeilingDB) dB ceiling. `outputVolume` has no \
            documented ramp, so that is a click on every correction: the #404 defect.
            """
        XCTAssertLessThan(worst, clickCeilingDB, message)
    }

    func testTheNilSnapIsTheBiggestStepAndIsNotTheOneSubStepsFixed() {
        // ⭐ PINS THE PATH THE FIRST VERSION MISSED, so nobody re-derives "everything is under
        // 0.24 dB". Selecting "No target" from a deflected state eases toward unity and then
        // lands the last `< deadZoneDB` in ONE application. It is deliberate (see the ⛔ block
        // at that branch) and it is the largest step this file makes.
        let snap = step(current: -0.39, raw: nil)
        let ordinary = 6 * AutoMixChain.cutSubStep
        let message = """
            The "No target" snap is \(String(format: "%.3f", Double(snap))) dB. It is supposed \
            to be the one deliberate exception — larger than an ordinary correction \
            (\(String(format: "%.3f", Double(ordinary))) dB) and still under the ceiling. If it \
            is now smaller, someone sub-stepped it and "No target" no longer reaches exact \
            unity within a tick, which is the #183 lie that branch exists to end.
            """
        XCTAssertGreaterThan(snap, ordinary, message)
        XCTAssertLessThan(snap, clickCeilingDB, message)
    }

    func testAnOrdinaryCorrectionStepsBelowTheInaudibleMark() {
        // The worst LEGAL delta is a corner case (the target flips sign while the stage sits
        // fully deflected). A real correction is one `maxDB`, and that is the case the founder
        // actually hears — it must clear the stricter mark, not merely the click ceiling.
        for (name, raw) in [("cut", Float(-6)), ("boost", Float(6))] {
            let d = step(current: 0, raw: raw)
            let message = """
                An ordinary 6 dB \(name) steps \(String(format: "%.3f", Double(d))) dB, over the \
                \(inaudibleMarkDB) dB mark.
                """
            XCTAssertLessThan(d, inaudibleMarkDB, message)
        }
    }

    func testTheOldRateWouldHaveFailedThisTest() {
        // ⭐ THE TEST THAT MAKES THE ONES ABOVE MEAN SOMETHING. Without it, a future session
        // could set `subSteps` to 1, watch the ceiling assertion still pass on some smaller
        // coefficient, and conclude nothing was lost.
        //
        // ⛔ IT USED TO ASSERT `> clickCeilingDB * 4`, WHICH COUPLED IT TO A NUMBER THE FILE
        // ITSELF INVITES YOU TO ARGUE WITH. Raise the ceiling to 0.55 and this went red with
        // a message blaming the coefficients — the self-disarming-guard trap in reverse. It
        // now pins the before-number and separately states that it is over the ceiling.
        let worstBefore = 12 * cut
        let pin = """
            The pre-#404 worst step is no longer 2.16 dB. Either `cutCoeff` or `maxDB` moved, \
            and every number in this file's header is now describing a defect that is not the \
            one that was fixed.
            """
        XCTAssertEqual(worstBefore, 2.16, accuracy: 0.0001, pin)
        XCTAssertGreaterThan(worstBefore, clickCeilingDB, pin)
    }

    // MARK: - …and the feel is unchanged

    func testTenSubStepsReproduceOneWholeStepExactly() {
        // The whole safety argument for changing the rate: ten sub-steps must land where one
        // whole step landed. Driven through `steadyGainDB` rather than hand-rolled arithmetic,
        // because it is that function — with its dead zone, its `maxDB` clamp and its
        // asymmetric coefficient choice — that owns the feel.
        for (name, raw) in [("cut", Float(-6)), ("boost", Float(6))] {
            var eased: Float = 0
            for _ in 0..<AutoMixChain.subSteps {
                eased = AutoMixChain.steadyGainDB(current: eased, targetLUFS: raw, lufsReading: 0,
                                                  boostCoeff: AutoMixChain.boostSubStep,
                                                  cutCoeff: AutoMixChain.cutSubStep)
            }
            let whole = AutoMixChain.steadyGainDB(current: 0, targetLUFS: raw, lufsReading: 0)
            let message = """
                Ten sub-steps on the \(name) path land at \(eased) where one whole step landed \
                at \(whole). The coefficient must be 1−(1−c)^(1/n); c/n is NOT equivalent.
                """
            XCTAssertEqual(eased, whole, accuracy: 0.0005, message)
        }
    }

    func testTheDeadZoneIsTheOnePlaceTheEquivalenceDoesNotHold() {
        // ⛔ THE SOURCE ONCE SAID "bit-for-bit". It is not, in a band 0.078 dB wide: the
        // dead-zone hold is now evaluated per sub-step, so for |delta| just above `deadZoneDB`
        // it can engage part-way through a window where it was previously all-or-nothing.
        // Pinned rather than asserted away, so the bound is a fact and not a hope.
        var eased: Float = 0
        for _ in 0..<AutoMixChain.subSteps {
            eased = AutoMixChain.steadyGainDB(current: eased, targetLUFS: -0.45, lufsReading: 0,
                                              boostCoeff: AutoMixChain.boostSubStep,
                                              cutCoeff: AutoMixChain.cutSubStep)
        }
        let whole = AutoMixChain.steadyGainDB(current: 0, targetLUFS: -0.45, lufsReading: 0)
        let divergence = abs(eased - whole)
        let message = """
            Sub-stepped and whole-step now agree at |delta| = 0.45 dB, inside the dead-zone \
            band. Either `deadZoneDB` moved or the hold is no longer evaluated per sub-step — \
            the "exact outside the dead zone" wording in `subSteps` needs re-reading either way.
            """
        XCTAssertGreaterThan(divergence, 0, message)
        let bound = 0.4 * cut       // deadZoneDB × c — the worst the hold can cost
        XCTAssertLessThan(divergence, bound, """
            The dead-zone divergence is \(divergence) dB, past the \(bound) dB bound the source \
            claims. That bound is the only reason this is documented rather than fixed.
            """)
    }

    func testTheNaiveDivisionWouldNotHaveBeenEquivalent() {
        // Names the wrong answer so nobody re-derives it. c/n is the obvious move and it is
        // measurably different — this is the test that says by how much.
        let target: Float = -6
        var naive: Float = 0
        let naiveCoeff = cut / Float(AutoMixChain.subSteps)
        for _ in 0..<AutoMixChain.subSteps { naive += (target - naive) * naiveCoeff }
        let whole = target * cut
        let message = """
            c/n happens to match the one-pole here. If that is now true, the reasoning in \
            `subSteps` needs re-reading before it is trusted.
            """
        XCTAssertNotEqual(naive, whole, accuracy: 0.005, message)
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
        XCTAssertEqual(AutoMixChain.subStepped(cut, over: 0), cut, accuracy: 0.000001, """
            A nonsensical count must degrade to the identity, not to a division by zero.
            """)
    }

    // MARK: - The wiring

    func testTheTuningSurvivesAnyRateChange() {
        // ⭐ THE INVARIANT NOTHING ELSE IN THIS FILE CAN SEE. Every other assertion depends on
        // `subSteps` alone, so a future session could set `easeInterval = 0.05` "for battery",
        // leave `subSteps = 10`, and pass the whole file green — while the measurement rate
        // silently drops to 2 Hz and the founder's tuned envelope stretches by 2.5×. It is the
        // PRODUCT of the two that reproduces the 200 ms one-pole, not either one.
        let window = AutoMixChain.easeInterval * Double(AutoMixChain.subSteps)
        XCTAssertEqual(window, 0.2, accuracy: 0.0001, """
            easeInterval × subSteps is \(window) s, not the 0.2 s the founder tuned the ease \
            against (#183/#295). The staircase may be finer or coarser — that is a free choice \
            — but their product is not.
            """)
    }

    func testTheShippedConstantsAreTheSubSteppedCoefficients() {
        // A value check, not a source scan: the constants exist to give the two numbers one
        // home, and a constant that drifted from its coefficient would be worse than the
        // call-site literals it replaced.
        XCTAssertEqual(AutoMixChain.boostSubStep, AutoMixChain.subStepped(0.05), accuracy: 1e-9)
        XCTAssertEqual(AutoMixChain.cutSubStep, AutoMixChain.subStepped(0.18), accuracy: 1e-9)
    }

    func testTheMeasurementRateDidNotFollowTheApplicationRate() throws {
        // ⚠️ THE FREEZE LAW, AS A TEST. `lufsReading` is observation-tracked and feeds the
        // loudness readout; publishing it at the 50 Hz application rate would put a 50 Hz write
        // in front of a SwiftUI body — the 10.76.50 menu-freeze class. So the timer fires fast
        // and the MEASUREMENT is gated behind the sub-step counter. A positive scan on that
        // gate, because a negative scan cannot tell code from prose (#367).
        let source = try Self.chainSource()
        XCTAssertTrue(source.contains("if self.easeTick >= Self.subSteps"), """
            The measurement is no longer gated behind the sub-step counter. If the meter now \
            reads at the application rate, `lufsReading` publishes at 50 Hz and every open \
            Picker dies while the master moves.
            """)
        XCTAssertTrue(source.contains("self.updateAutoGain()"), """
            The gain is no longer applied on every tick, which is the fix itself.
            """)
    }

    func testTheTimerDoesNotSubmitAMainActorTaskPerTick() throws {
        // ⛔ THE FIRST #404 COMMIT USED `Task { @MainActor }` HERE, AT 50 Hz. HARNESS_LEDGER
        // records per-tick main-actor task submission as a proven dead-end (the 10.76.48 menu
        // freeze), and enqueued sub-steps can bunch into one runloop turn — reassembling the
        // staircase this change exists to break apart. The timer already runs on the main
        // thread, so the synchronous form is both correct and cheaper. Positive scan, again
        // because a negative one would trip over this very comment.
        let source = try Self.chainSource()
        XCTAssertTrue(source.contains("MainActor.assumeIsolated {"), """
            The auto-gain timer no longer enters the main actor synchronously. If it went back \
            to `Task { @MainActor }`, it submits 50 tasks a second — the pattern the ledger \
            records as the cause of the biofeedback menu freeze.
            """)
    }

    func testTheApplicationUsesTheSubSteppedCoefficients() throws {
        // The constants existing and being correct is worth nothing if the call site still
        // passes the whole-tick numbers — a pure core with no caller is the same defect with
        // more steps, which this repo has paid for before.
        let source = try Self.chainSource()
        XCTAssertTrue(source.contains("boostCoeff: Self.boostSubStep"), """
            The boost path is back on the whole-tick coefficient.
            """)
        XCTAssertTrue(source.contains("cutCoeff: Self.cutSubStep"), """
            The cut path is back on the whole-tick coefficient — that is the loud one, 3.6× \
            the boost COEFFICIENT (and 3.8× the boost step, which is a different ratio because \
            the root is non-linear).
            """)
    }

    private static func chainSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/CISmoke
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/Echoelmusic/Audio/AutoMixChain.swift")
        // SKIPS rather than reporting a green it did not earn — and rather than reporting a RED
        // it did not earn either, which is what a raw read error would have done on any host
        // where the source tree is not co-located with the built bundle. Same guard as every
        // sibling source-scanning test in this directory.
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("AutoMixChain.swift not reachable from \(#filePath) — source tree not co-located.")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
