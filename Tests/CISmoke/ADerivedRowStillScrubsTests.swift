// ADerivedRowStillScrubsTests.swift
// Echoel — #427 review. A row whose binding RECOMPUTES its value must still accumulate a drag.
//
// THE DEFECT, and it is the first one in this chain that a slice's own guard could not see.
// `EchoelValueField` carries an un-snapped running target across the events of a scrub (#376), so
// finger travel smaller than half a grid unit accumulates instead of being thrown away every
// frame. It may only trust that target while the target still names the number on screen, and
// until now the test for that was raw equality against the stored value.
//
// Raw equality holds for a STORED binding, because `apply` wrote exactly the snapped target. It
// does NOT hold for a DERIVED one. `EchoelStudioView.visualEnergy` — the ONE visual control
// (#228) — has no state: its getter runs `VisualEnergy.position(matching:motion:)` over the two
// values its setter wrote through `VisualEnergy.look(at:)`. That round trip is exact in
// arithmetic and not in `Double`: measured over the 101 two-decimal positions it is bit-exact on
// **39**, worst residual 2.2e-16.
//
// So on 62 of 101 positions the drag re-seeded EVERY event — the exact pre-#376 regime, whose
// measured dead zone for a `0…1, decimals: 2` row is ≈135 pt/s at 60 Hz. Simulated against the
// shipped constants (`fullRangePoints = 200`, `ScrubPrecision.scale`), a 3 s drag from 0 reached
// **0.01 and stopped** at 10, 40, 60 and 120 pt/s, then jumped to **1.00** at 135: under the
// finger the one visual control was a two-state control. At `decimals: 4` the same threshold is
// ≈2.7 pt/s, which is why nobody saw it until #427 coarsened the grid — the slice did not create
// the fragility, it made it reachable.
//
// ⭐ WHY THE FIX IS IN THE SHARED CONTROL AND NOT IN `visualEnergy`. Snapping inside the getter
// would have worked and would have put a second copy of the grid constant next to the row's
// `decimals: 2` — the double-definition defect #416 was written about. The predicate itself was
// simply over-strict: it asked "is the target the stored value" when the question it documents is
// "does the target still describe the number ON SCREEN". `ScrubPrecision.carriesTarget` asks the
// documented one, and any binding whose read-back lands inside the displayed grid cell now works.
//
// ⚠️ WHAT THIS FILE CANNOT DO. It exercises the pure predicate, not SwiftUI: it cannot prove a
// finger travels on a device, and the ≈135 pt/s and the 39/101 above come from simulation and
// from arithmetic, not from a run. The founder verify is one sentence: drag Energy SLOWLY with
// the visual open — does the picture move, or does it sit at 0.01?
//
// `Tests/CISmoke` is the blocking bundle.

import Foundation
import XCTest
@testable import Echoelmusic

final class ADerivedRowStillScrubsTests: XCTestCase {

    /// The Energy row's grid and range, as `visualAdjustFields` declares them.
    private static let decimals = 2
    private static let lo = 0.0
    private static let hi = 1.0

    /// Every two-decimal position the Energy row can hold.
    private static var gridPositions: [Double] { (0...100).map { Double($0) / 100.0 } }

    /// What the binding hands back after the field wrote `t` — the app's own round trip.
    private func readBack(_ t: Double) -> Double {
        let look = VisualEnergy.look(at: t)
        return VisualEnergy.position(matching: look.intensity, motion: look.motion)
    }

    // MARK: - The defect

    /// A scrub on the derived row keeps its target at every position it can occupy.
    ///
    /// RED BEFORE THE FIX on 62 of these 101 positions.
    func testTheEnergyRowCarriesItsTargetAtEveryPosition() {
        for t in Self.gridPositions {
            let value = readBack(t)
            XCTAssertTrue(ScrubPrecision.carriesTarget(t, value: value,
                                                       lowerBound: Self.lo, upperBound: Self.hi,
                                                       decimals: Self.decimals), """
                The scrub cannot keep its running target at Energy position \(t): the binding \
                reads back \(value), which is the same number on screen but not the same `Double`.

                Every event of a drag would therefore re-seed from the stored value and discard \
                everything below half a grid unit — the pre-#376 dead zone, ≈135 pt/s on a \
                `0…1, decimals: 2` row. The one visual control becomes a two-state control: one \
                hundredth, or the end of the range.
                """)
        }
    }

    /// The predicate this replaced really did fail here — otherwise the fix guards nothing.
    ///
    /// This is the half that makes the file able to fail in the OTHER direction: if someone
    /// simplifies `carriesTarget` back to raw equality, the test above goes red and this one
    /// explains why in one number.
    func testRawEqualityWouldStillFailOnMostOfThem() {
        let exact = Self.gridPositions.filter { readBack($0) == $0 }.count
        XCTAssertLessThan(exact, Self.gridPositions.count, """
            The derived round trip is now bit-exact at every position, so the measurement this \
            file is built on no longer holds. That is not automatically good news: check whether \
            `VisualEnergy` changed shape, and re-derive the argument in \
            `ScrubPrecision.carriesTarget` before trusting it.
            """)
        // Measured 39 of 101 on the shipped spans. Asserted as a floor, not a fixture: the point
        // is that a MAJORITY fails raw equality, not that this exact count is a law.
        XCTAssertLessThan(exact * 2, Self.gridPositions.count, """
            Fewer than half of the positions fail raw equality now (\(exact) of \
            \(Self.gridPositions.count) are exact). The defect this file documents was measured \
            at 39 of 101 exact; if the shape changed that much, re-measure before editing.
            """)
    }

    // MARK: - What the predicate must still refuse

    /// A foreign write the user can SEE must still win — this is the whole reason for the check.
    func testATypedNumberStillTakesTheTargetAway() {
        // The keypad wrote a genuinely different number while a drag's target stood.
        XCTAssertFalse(ScrubPrecision.carriesTarget(0.90, value: 0.40,
                                                    lowerBound: Self.lo, upperBound: Self.hi,
                                                    decimals: Self.decimals),
                       "A stale target must not survive a write to a different number — that is "
                       + "the #375/#377 teleport this predicate exists to prevent.")

        // One whole grid step apart is still a different number on screen.
        XCTAssertFalse(ScrubPrecision.carriesTarget(0.41, value: 0.40,
                                                    lowerBound: Self.lo, upperBound: Self.hi,
                                                    decimals: Self.decimals),
                       "One grid step is a visible difference and must not be carried.")

        // And the range-edge case: a target beyond the top clamps onto it.
        XCTAssertTrue(ScrubPrecision.carriesTarget(1.4, value: 1.0,
                                                   lowerBound: Self.lo, upperBound: Self.hi,
                                                   decimals: Self.decimals),
                      "A target that clamps onto the value the row is already showing IS the "
                      + "number on screen; refusing it would unwind an overshoot the user cannot "
                      + "see.")
    }

    /// NaN is healed rather than carried, exactly as before.
    func testANonFiniteTargetIsNotCarried() {
        XCTAssertFalse(ScrubPrecision.carriesTarget(.nan, value: 0.40,
                                                    lowerBound: Self.lo, upperBound: Self.hi,
                                                    decimals: Self.decimals),
                       "A NaN target must fail the test so the gesture re-seeds from the stored "
                       + "value instead of carrying poison for the rest of the drag.")
    }

    // MARK: - The half that would break if the `V` mapping were dropped

    /// A `Float` row at high magnitude and fine grid still carries — the cutoff case.
    ///
    /// `Double(Float(17999.9))` is 17999.900390625, which snaps to 17999.9004 at four decimals
    /// while a target of 17999.9 snaps to 17999.9. A Double-side comparison would therefore
    /// re-seed on every event of every cutoff drag. Mapping both sides through `V` collapses them
    /// to the same `Float`, which is what the original code got right and this must not lose.
    ///
    /// ⚠️ GREEN ON BOTH SIDES OF THE FIX, deliberately, and it is not the regression test: it
    /// pins the half a future simplification would be most tempted to drop. Only
    /// `testTheEnergyRowCarriesItsTargetAtEveryPosition` is red on the old predicate.
    func testAFloatRowAtFineGridStillCarries() {
        let stored = Float(17_999.9)
        XCTAssertTrue(ScrubPrecision.carriesTarget(17_999.9, value: stored,
                                                   lowerBound: 20, upperBound: 18_000,
                                                   decimals: 4),
                      "The cutoff row lost its scrub target: the comparison is no longer being "
                      + "made in the binding's own precision, so `Float` rounding reads as a "
                      + "foreign write on every event.")
    }

    /// A plain stored row behaves exactly as it did — the fix may not move existing rows.
    func testAStoredRowIsUnchanged() {
        for step in 0...150 {
            let t = Double(step) / 100.0                      // the Intensity row: 0…1.5, 2 places
            let stored = Float(t)
            let carried = ScrubPrecision.carriesTarget(t, value: stored,
                                                       lowerBound: 0, upperBound: 1.5,
                                                       decimals: 2)
            let rawEquality = Float(ScrubPrecision.snapped(t, lowerBound: 0, upperBound: 1.5,
                                                           decimals: 2)) == stored
            XCTAssertEqual(carried, rawEquality, """
                At \(t) the new predicate disagrees with the one it replaced on a STORED row \
                (carried: \(carried), raw equality: \(rawEquality)). The fix is only allowed to \
                be more permissive where a binding recomputes; on a row that holds what was \
                written it must be indistinguishable.
                """)
        }
    }
}
