// ScrubNotifiesOnlyOnRealChangeTests.swift
// Echoel — a parameter edit that does not move the number must not notify anyone.
// In the BLOCKING bundle.
//
// THE DEFECT (#375). `EchoelValueField` is the one control for every numeric parameter in the
// app. Its drag path ran the caller's `onChange` whenever the computed delta was non-zero, and
// its `onCommit` on every gesture end — neither asked whether the VALUE had actually changed.
// Those are different questions, and two situations separate them:
//
//  • BELOW THE GRID. Travel is `(step × scale) / 200 × span`. On "Detail" (8…90, `decimals: 0`)
//    one point of deliberately slow finger movement is ~0.09 — a tenth of the smallest number
//    the field can show. The drag produces those deltas for as long as the finger moves.
//  • AT A RANGE EDGE. A field already at its bound, dragged further that way, clamps.
//
// What ran anyway is not cosmetic. Of the ten `onChange` sites, `visualPresetID = ""` (4×) drops
// the user's chosen visual look and `applyArticulation()` (1×) overwrites hand-tuned A/D/S/R.
// Of the four `onCommit` sites, `moodKnob` commits `recomposeIfRunning()` — so a drag that moved
// nothing RE-ROLLED THE COMPOSITION. A mood knob parked at 0 and dragged downward, the direction
// of a scroll, is exactly that gesture, and its symptom is "it suddenly generated something new"
// with no visible cause.
//
// ⚠️ WHAT THIS DOES NOT CLAIM. It does not say a scroll gesture reaches the field at all — that
// is SwiftUI/UIKit gesture arbitration and cannot be decided from source (it is the open half of
// #360). It says that IF a drag reaches the field, the field no longer notifies for an edit that
// did not happen. Those are separate defects and only the second one is fixed here.
//
// ⛔ AND ONE MORE THING THIS FILE IS: `ScrubPrecision.snapped` was hoisted out of the view for
// these tests. That is the pattern this file argues for — the rest of `EchoelValueField` is a
// SwiftUI `View` whose gesture cannot be driven from a unit test, so the only parts a blocking
// gate can hold are the pure ones plus a source scan. A source scan is weaker than an execution
// and is named as such below.

import Foundation
import XCTest
@testable import Echoelmusic

final class ScrubNotifiesOnlyOnRealChangeTests: XCTestCase {

    typealias P = ScrubPrecision

    // MARK: - The two ways a real delta lands on the same number

    /// The crisp statement of the bug: a delta can be non-zero and still not move the value.
    /// The numbers are the app's own — "Detail" spans 8…90 at `decimals: 0`, so one point of
    /// slow travel is `82 / 200 × 0.22 ≈ 0.09`.
    func testANonZeroDeltaIsNotTheSameQuestionAsAMovedValue() {
        let onePointOfSlowTravel = (90.0 - 8.0) / 200.0 * P.fineScale
        XCTAssertGreaterThan(onePointOfSlowTravel, 0, """
            A slow drag on an 8…90 field produced no travel at all. If `fineScale` reached zero \
            the control stops responding to a slow finger, which is the opposite of what the \
            precision scrub was asked for.
            """)
        let landed = P.snapped(23.0 + onePointOfSlowTravel,
                               lowerBound: 8, upperBound: 90, decimals: 0)
        XCTAssertEqual(landed, 23.0, """
            A \(onePointOfSlowTravel) delta on a whole-number field moved the value to \(landed). \
            If the grid changed, re-derive this — but the point stands either way: the old guard \
            asked whether the DELTA was non-zero, and that is not the same as asking whether the \
            NUMBER moved.
            """)
    }

    /// The range edge. This is the case that reaches the mood knobs, whose grid (0.0001) is fine
    /// enough that a slow drag does move them everywhere else.
    func testARangeEdgeSwallowsTheWholeDelta() {
        let moodOnePoint = 1.0 / 200.0 * P.fineScale          // ≈ 0.0011, well above the grid
        XCTAssertEqual(P.snapped(0.0 - moodOnePoint, lowerBound: 0, upperBound: 1, decimals: 4),
                       0.0, """
            A mood knob at 0, dragged DOWN, did not stay at 0. That drag is the one that used to \
            reach `recomposeIfRunning()` with nothing changed — a new take out of nowhere.
            """)
        XCTAssertEqual(P.snapped(1.5 + moodOnePoint, lowerBound: 0, upperBound: 1.5, decimals: 4),
                       1.5, "A field at its upper bound, dragged further up, did not stay put.")
        XCTAssertEqual(P.snapped(-0.02, lowerBound: 0, upperBound: 1, decimals: 2), 0.0,
                       "A value below the lower bound was not clamped to it.")
    }

    /// The weather mixers the founder photographed reading 0.00 — `0…1`, `decimals: 2`. Their
    /// grid is coarse enough that even a slow drag's step rounds away.
    func testTheWeatherMixerGridSwallowsASlowStep() {
        let onePoint = 1.0 / 200.0 * P.fineScale
        XCTAssertEqual(P.snapped(0.5 + onePoint, lowerBound: 0, upperBound: 1, decimals: 2),
                       0.5, """
            A \(onePoint) step moved a two-decimal 0…1 field. It should round back: 0.0011 is a \
            ninth of the 0.01 grid.
            """)
    }

    // MARK: - The landing rule itself

    /// Rounds to the grid, never truncates — the displayed number is the stored one.
    func testTheGridRoundsRatherThanTruncates() {
        XCTAssertEqual(P.snapped(0.4999, lowerBound: 0, upperBound: 1, decimals: 2), 0.5,
                       "0.4999 truncated to 0.49 instead of rounding to the 0.50 it displays as.")
        XCTAssertEqual(P.snapped(-3.4, lowerBound: -12, upperBound: 12, decimals: 0), -3.0,
                       "A negative value did not round half-away-from-zero like the positive side.")
    }

    /// A degenerate `a...a` range pins the value instead of producing a NaN from a zero span.
    /// (`frac` guards the same case for the fader fill; this is the write side of it.)
    func testADegenerateRangePinsTheValue() {
        XCTAssertEqual(P.snapped(0.7, lowerBound: 0.5, upperBound: 0.5, decimals: 2), 0.5,
                       "A single-point range did not pin the value to its one legal number.")
    }

    // MARK: - The structural half (a source scan — weaker than the above, and it says so)

    /// The arithmetic above stays green if someone reverts the CALL SITES, because `snapped`
    /// would still be correct in isolation — it would simply stop deciding anything. This is the
    /// check that fails in that case. It reads source rather than running the gesture, which a
    /// unit test cannot drive; treat a green here as "the wiring is still shaped this way", not
    /// as "the gesture was exercised".
    func testAllThreeEditPathsGuardOnTheLandedValue() throws {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent("Sources/Echoelmusic/Studio/EchoelValueField.swift")
        guard let src = try? String(contentsOf: path, encoding: .utf8) else {
            throw XCTSkip("EchoelValueField.swift not readable at \(path.path) — scan skipped")
        }

        XCTAssertTrue(src.contains("ScrubPrecision.snapped("), """
            `apply` no longer calls `ScrubPrecision.snapped`. Everything above then tests a \
            function the app does not use — the worst state for this file to be in, because it \
            stays green.
            """)
        XCTAssertTrue(src.contains("private func apply(_ raw: Double) -> Bool"), """
            `apply` stopped reporting whether the value moved. All three edit paths depend on \
            that answer; without it they are back to guessing from the requested delta.
            """)
        XCTAssertTrue(src.contains("if delta != 0, apply(Double(value) + delta) { onChange() }"), """
            The drag path no longer gates `onChange()` on `apply`'s answer. Below the grid and \
            at a range edge that runs destructive live-applies for an edit that never happened.
            """)
        XCTAssertTrue(src.contains("scrubStartValue"), """
            The gesture no longer records the value it started from, so `onEnded` cannot tell \
            whether the drag changed anything — and `onCommit` re-rolls the composition on every \
            mood knob.
            """)
        XCTAssertFalse(src.contains("scrubbing = false; onCommit()"), """
            `onEnded` commits unconditionally again. That is the exact line #375 replaced: a drag \
            that moved nothing must not commit.
            """)
    }
}
