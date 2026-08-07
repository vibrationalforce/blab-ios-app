// TheUnitToPeriodLawSurvivesTheViewTests.swift
// Echoel — #470. The unit→occurrence-period law was a static on a DOORLESS SwiftUI view.
//
// ⭐ WHAT WAS ACTUALLY WRONG, said narrowly. Nothing was computing the wrong number.
// `PianoRollView.occurrencePeriod(forUnit:)` was correct arithmetic sitting in the wrong
// place: a `@MainActor` view struct that nothing instantiates since the founder removed the
// note editor (2026-07-26, "Pianoroll soll raus", #178). CLAUDE.md records the consequence
// exactly — "the struct still compiles and still exists because a test calls its static
// `occurrencePeriod(forUnit:)`; hoisting that one pure function into a core file is what
// unblocks deleting the struct." This is that hoist, and nothing else.
//
// It went to `RollHitTest` rather than to `NoteOperators`, and that choice is the slice:
// `RollHitTest.velocity(forY:laneHeight:)` is the ONE producer of the unit this consumes,
// so Y → unit → period is a single chain and both ends were already pure Foundation-only
// geometry. `NoteOperators` owns the RANGE and keeps owning it — the floor branch asks it
// rather than repeating 64, which is the half `testTheFloorIsChainedNotCopied` pins.
//
// ⛔ HONEST GRADING, because the flattering version is available and wrong. Only ONE
// assertion in this file is a regression: `testTheViewNoLongerDeclaresItsOwnCopy`. Every
// behavioural case drives a symbol this same commit created — those could never have been
// red, and calling them regressions would be the #433 defect committed inside the file that
// cites it. What they buy is that a later "simplify" cannot quietly change the mapping, the
// floor value, or the NaN branch.
//
// ⚠️ AND THE SCAN NEEDED THE #453 STRIPPER TO BE LOAD-BEARING, not prophylactic: the doc
// comment at the new declaration names the old home in prose, and this file's own header
// does too. A raw-text scan would be reading its own explanation. `SourceText.codeOnly`
// removes that. The positive anchor comes FIRST (#367/#408): a scan that only forbade the
// old form would be green on a tree that had lost BOTH copies.
//
// ⚠️ WHAT THIS FILE CANNOT DO. It proves the law survived the move. It proves nothing about
// whether anyone can reach it. When #470 wrote this, the reason was "`PianoRollView` is
// doorless"; since #475 the reason is stronger and simpler — that view is DELETED, so the
// law has no production caller at all (see the retired third assertion at the bottom of
// `testTheViewNoLongerDeclaresItsOwnCopy`). It is hoisted anyway because a copy inside a
// doomed view is exactly where a later deletion loses a decision by accident — not because
// a user is waiting for it. #475 is the deletion #470 was insuring against, and the law
// came through it intact; that is the insurance paying out, not a reason to drop the file.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheUnitToPeriodLawSurvivesTheViewTests: XCTestCase {

    // MARK: - The law (new symbol — pins behaviour, never was red)

    /// The lane bar draws the 1:N ratio, so the map is the inverse. These four are the
    /// values the moved test asserted before the hoist, unchanged.
    func testTheInverseRatioIsUnchanged() {
        XCTAssertEqual(RollHitTest.occurrencePeriod(forUnit: 1.0), 1, "full bar = every loop")
        XCTAssertEqual(RollHitTest.occurrencePeriod(forUnit: 0.5), 2, "half = 1:2")
        XCTAssertEqual(RollHitTest.occurrencePeriod(forUnit: 0.25), 4, "quarter = 1:4")
        XCTAssertEqual(RollHitTest.occurrencePeriod(forUnit: 0.125), 8, "eighth = 1:8")
    }

    /// The floor asks `NoteOperators` instead of repeating its upper bound. A later widening
    /// of `periodRange` must move this branch with it — a literal 64 would not.
    func testTheFloorIsChainedNotCopied() {
        XCTAssertEqual(RollHitTest.occurrencePeriod(forUnit: 0.0),
                       NoteOperators.periodRange.upperBound, """
            The bottom of the lane must mean "the sparsest period the range allows", read \
            FROM NoteOperators. If this became a literal, widening periodRange would leave \
            the lane unable to reach its own new maximum — the #416 class.
            """)
        XCTAssertEqual(RollHitTest.occurrencePeriod(forUnit: -1.0),
                       NoteOperators.periodRange.upperBound,
                       "a negative unit is below the floor, not a negative period")
    }

    /// ⚠️ The `> 0.02` boundary is a STEP, not a taper, and it is pre-existing. Pinned so the
    /// discontinuity is a stated property rather than a surprise: just inside it the map is
    /// still the inverse (≈50), at and below it the answer jumps to the range maximum.
    func testTheFloorIsAStepAndTheStepIsWhereItSays() {
        XCTAssertEqual(RollHitTest.occurrencePeriod(forUnit: 0.0201), 50,
                       "just above the floor the inverse still applies")
        XCTAssertEqual(RollHitTest.occurrencePeriod(forUnit: 0.02),
                       NoteOperators.periodRange.upperBound,
                       "the comparison is strict — 0.02 itself takes the floor branch")
    }

    /// NaN and −∞ are safe BY ARGUMENT ORDER, the same law `clamped(to:)` exists for: neither
    /// is `> 0.02`, so both take the floor branch instead of propagating.
    ///
    /// ⛔ +∞ IS NOT, and this test says so rather than pretending. It passes the guard and
    /// `Int((1/∞).rounded())` is 0 — below `periodRange`. The first draft of this file asserted
    /// 1 and would have been RED on correct code; the first draft of the doc at the declaration
    /// claimed all non-finite input took the floor. Both were wrong in the same direction.
    /// Recorded, not repaired: #470 is a hoist, and the shipped chain is safe because
    /// `NoteOperators` clamps — which is what the second half here actually pins.
    func testNaNAndNegativeInfinityTakeTheFloorButPositiveInfinityDoesNot() {
        for safe in [Double.nan, -.infinity] {
            XCTAssertEqual(RollHitTest.occurrencePeriod(forUnit: safe),
                           NoteOperators.periodRange.upperBound, """
                A non-finite unit stopped taking the floor branch. Rewriting the guard as \
                `unit <= 0.02` inverts exactly this — the shape this repo has paid for before.
                """)
        }
        XCTAssertEqual(RollHitTest.occurrencePeriod(forUnit: .infinity), 0, """
            The +∞ hole closed. That is an improvement, not a failure — but it is a BEHAVIOUR \
            change to a function #470 moved without touching, so make it deliberately: update \
            this assertion and the ⛔ note at the declaration in the same commit.
            """)
    }

    /// The half that decides whether the hole matters: the shipped chain always ends in
    /// `NoteOperators`, whose init clamps to `periodRange`. Every out-of-range unit — the
    /// +∞ case above included — is legal by the time it reaches a note.
    func testTheShippedChainIsLegalWhereTheMapAloneIsNot() {
        for unit in [Double.infinity, 3.0, 100.0, .nan, -.infinity, 0.0, 1.0] {
            let raw = RollHitTest.occurrencePeriod(forUnit: unit)
            let landed = NoteOperators(occurrencePeriod: raw).occurrencePeriod
            XCTAssertTrue(NoteOperators.periodRange.contains(landed), """
                unit \(unit) → map \(raw) → note \(landed), outside \(NoteOperators.periodRange). \
                The map is allowed to be loose only because this clamp exists; if the clamp is \
                ever removed, the map has to tighten in the same commit.
                """)
        }
    }

    /// Whatever the map returns must be usable as-is. `NoteOperators` clamps again on init,
    /// so this is belt-and-braces — but a map that routinely needed rescuing would mean the
    /// two disagree about what the lane can express.
    func testEveryLanePositionYieldsALegalPeriod() {
        for i in 0...1000 {
            let unit = Double(i) / 1000.0
            let period = RollHitTest.occurrencePeriod(forUnit: unit)
            XCTAssertTrue(NoteOperators.periodRange.contains(period),
                          "unit \(unit) produced \(period), outside \(NoteOperators.periodRange)")
        }
    }

    // MARK: - The regression (the only assertion here that was ever red)

    /// ONE definition. The positive half must come first: a scan that only forbade the old
    /// declaration would pass on a tree that had lost both (#367).
    func testTheViewNoLongerDeclaresItsOwnCopy() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let studio = root.appendingPathComponent("Sources/Echoelmusic/Studio")
        guard FileManager.default.fileExists(atPath: studio.path) else {
            throw XCTSkip("source tree not present under \(root.path) — this half reads source text")
        }

        let core = SourceText.codeOnly(
            try String(contentsOf: studio.appendingPathComponent("RollHitTest.swift"),
                       encoding: .utf8))
        XCTAssertTrue(core.contains("func occurrencePeriod(forUnit"), """
            RollHitTest no longer declares the unit→period law. It is the pure core that owns \
            velocity(forY:laneHeight:), the one producer of the unit it consumes — if the law \
            moved again, move this assertion with it rather than deleting it.
            """)

        let view = SourceText.codeOnly(
            try String(contentsOf: studio.appendingPathComponent("PianoRollView.swift"),
                       encoding: .utf8))
        XCTAssertFalse(view.contains("func occurrencePeriod(forUnit"), """
            PianoRollView.swift declares the unit→period law again. The view that used to \
            own it was doorless (#178) and is now DELETED (#475) — this file's top level is \
            now `protocol NoteVoice` + its two conformances, `PianoRollModel`, and the \
            test-only `enum RollSelection`. A second copy here is unreachable AND \
            authoritative-looking, \
            which is how one decision quietly becomes two (#416). Call RollHitTest instead.
            """)
        // ⛔ A THIRD ASSERTION STOOD HERE AND #475 RETIRED IT — following the instruction its
        // own failure message gave, rather than loosening it. It read:
        //
        //     XCTAssertTrue(view.contains("RollHitTest.occurrencePeriod(forUnit:"), …
        //     "The paint-lane no longer calls the hoisted law. Removing a copy is only half
        //      the hoist — if the call site went away too, this assertion should be deleted
        //      together with the lane, deliberately, not left to rot."
        //
        // The lane went away: #475 (2026-08-07) deleted the 987-line `PianoRollView` struct,
        // and the law now has **exactly one declaration and zero callers of any kind** — the
        // declaration lives in `RollHitTest.swift`.
        // ⛔ THAT FACT WAS FIRST WRITTEN AS A GREP RECIPE AND THE RECIPE FALSIFIED ITSELF:
        // `git grep -n "occurrencePeriod(forUnit" -- Sources` "returns exactly ONE hit". It
        // returns THREE, because the same commit added two header lines to
        // `PianoRollView.swift` that spell the searched string out in prose. The `EchoelModalBank`
        // trap CLAUDE.md records, twice in one changeset — a note that QUOTES a grep corrupts
        // its own evidence, and the next reader runs it, sees 3, and reads a contradiction where
        // there is none. To re-measure, exclude prose:
        // `git grep -n "occurrencePeriod(forUnit" -- Sources | grep -v '://'`.
        // That is stated here rather than asserted, and the distinction is the point: a
        // "must have zero callers" check would go red the day someone re-doors a note editor,
        // which is correct work — the #364 trap of a rule that fires on the future.
        //
        // Why the law is kept at all, unchanged from #470: a hoisted decision sitting in a
        // deleted view's file is exactly where a later cleanup loses a decision by accident.
        // It is exercised by `Tests/EchoelmusicTests/NoteOperatorsTests.swift`. Assertions 1
        // and 2 above still carry the whole hoist: the core declares it, the old home does not.
    }
}
