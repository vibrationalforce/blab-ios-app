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
// nothing RE-ROLLED THE COMPOSITION whenever the transport was running (the method name carries
// that condition and an earlier draft of this line dropped it). A mood knob parked at 0 and
// dragged downward, the direction of a scroll, is exactly that gesture, and its symptom is "it
// suddenly generated something new" with no visible cause.
//
// ⚠️ WHAT THIS DOES NOT CLAIM — three things, and the last two came out of the review of this
// very commit:
//  1. It does not say a scroll gesture reaches the field at all. That is SwiftUI/UIKit gesture
//     arbitration, undecidable from source, and it is the open half of #360.
//  2. ⛔ RETIRED BY #376, ONE CYCLE LATER. This said "it does not make a below-grid drag WORK,
//     only silent" — true when written and false now: the scrub carries an un-snapped target, so
//     a slow drag accumulates instead of losing its remainder every event. Kept as a retraction
//     rather than deleted, because the claim shipped and someone may have read it. The guard
//     that holds the new behaviour is `SlowScrubStillMovesTests`.
//  3. It does not survive a CANCELLED gesture. SwiftUI skips `onEnded` when a parent scroll view
//     claims the drag, so the `scrubbing` latch and the start reference go stale and the next
//     gesture can be judged against the previous one's start. Strictly better than the
//     unconditional commit it replaces, not correct. That is #377.
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
        // `fineScale > 0` is NOT re-asserted here — `ScrubPrecisionSmokeTests` already pins it,
        // and a fact pinned twice in one bundle is a fact that gets half-updated once.
        let onePointOfSlowTravel = (90.0 - 8.0) / 200.0 * P.fineScale
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

    /// The weather mixers reported reading 0.00 in #360 — `0…1`, `decimals: 2` (verified at
    /// `EchoelStudioView.swift`'s `WeatherMixRow`). Their grid is coarse enough that even a slow
    /// drag's step rounds away.
    ///
    /// ⛔ AN EARLIER DRAFT WROTE "the weather mixers the founder photographed". The 0.00 report
    /// is real and is what sent me here, but I could not find a screenshot to attribute it to,
    /// and inventing a source is the "unbelegtes schon-immer" the repo strikes on sight. The
    /// ranges below are measured; the provenance is the task entry, not a photograph.
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
        // ⛔ THIS WAS −3.4 IN THE FIRST DRAFT, inside a test named after rounding-vs-truncation —
        // and −3.4 gives −3 under rounding, truncation AND round-half-to-even alike, so it could
        // not fail for any behaviour it claimed to separate. −3.6 does: rounding gives −4,
        // truncation gives −3. Exactly the "assertion that cannot fail" class this repo has
        // already paid for once (AudioLanePlayerTests:426).
        XCTAssertEqual(P.snapped(-3.6, lowerBound: -12, upperBound: 12, decimals: 0), -4.0,
                       "−3.6 landed on −3, so the negative side truncates instead of rounding.")
    }

    /// A degenerate `a...a` range pins the value to its one legal number.
    ///
    /// ⛔ THE FIRST VERSION OF THIS DOC GAVE A REASON THAT DOES NOT APPLY: "instead of producing
    /// a NaN from a zero span". `snapped` never divides by the span, so there is no such path;
    /// the `frac` analogy it drew is a false parallel, because `frac` DOES divide by `(hi - lo)`
    /// and genuinely needs its guard. The assertion was right and the reason was borrowed.
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

        // ⛔ MATCHED ON WHITESPACE-STRIPPED TEXT, and the first draft did not — it pinned three
        // source lines verbatim, so a rewrap or a SwiftLint reflow would have reddened the only
        // blocking gate for a formatting edit. The sibling `ValueFieldNotifiesEveryPathTests`
        // already made and documented that decision ("a guard that fails on formatting is a
        // guard people delete"); adopting it a file later rather than copying it is how a bundle
        // ends up with two conventions.
        let squashed = src.components(separatedBy: .whitespacesAndNewlines).joined()

        // ⛔ THIS NEEDLE WAS `apply(Double(value)+delta)` FOR EXACTLY ONE CYCLE. #376 gave the
        // scrub its own un-snapped target, so the drag now applies `target`. I changed it in the
        // same commit as the source — which is the discipline the previous cycle had to learn the
        // expensive way, when #375 moved two lines that a sibling guard pinned and turned the
        // blocking gate red while the compile check stayed green.
        XCTAssertTrue(squashed.contains("ifdelta!=0,apply(target){onChange()}"), """
            The drag path no longer gates `onChange()` on `apply`'s answer. Below the grid and \
            at a range edge that runs destructive live-applies for an edit that never happened.
            """)
        XCTAssertTrue(squashed.contains("scrubTarget=target"), """
            The drag stopped carrying its own un-snapped target, so each event's sub-grid \
            remainder is discarded again and a slow drag cannot move the value at all (#376).
            """)
        // The other two paths, because the arithmetic above cannot tell them apart and because
        // the drag is the one everybody remembers to check.
        XCTAssertTrue(squashed.contains("ifapply(newVal){onChange();onCommit()}"), """
            The keypad path notifies unconditionally again. Confirming the number that is \
            already there is not an edit — on the concert-pitch field it re-tunes every voice \
            and recomposes.
            """)
        XCTAssertTrue(squashed.contains("guardmovedelse{return}"), """
            The VoiceOver adjustment no longer gates on `apply`'s answer. A swipe against a \
            range limit then fires the live-apply closures for a value that did not change.
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
