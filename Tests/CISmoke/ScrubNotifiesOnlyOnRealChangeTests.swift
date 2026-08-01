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
//     ⛔ AND THIS ITEM WAS WRITTEN BEFORE #376 GAVE THE GESTURE A THIRD LATCH. `scrubTarget`
//     goes stale the same way, and that one costs a VALUE rather than a commit decision: a
//     keypad or VoiceOver edit made after a cancelled drag would have been thrown away by the
//     next drag's first event. #376's Nachlese contains that half AT THE POINT OF USE — the
//     per-event branch re-seeds whenever the target no longer describes the number on screen —
//     so what is left for #377 is `scrubbing` and `scrubStartValue`, which no point-of-use check
//     can reach. Worth stating plainly because the previous sentence's "strictly better than the
//     unconditional commit" was, for one commit, no longer true in every direction.
//     ✅ CLOSED BY #377 (the latch, via a `@GestureState` SwiftUI resets itself) AND #378 (the
//     value: a cancelled drag now puts the number back and re-fires `onChange`). What item 1
//     above says is still true and is why #378 exists at all — this file cannot show that a
//     scroll reaches the field, only that whatever leaks through before SwiftUI rules on the
//     gesture leaves nothing behind.
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
        // The other side of that target: carrying one removed the per-event re-read of `value`
        // that used to self-correct any divergence within a frame. These two needles hold the
        // replacement — the base is re-seeded whenever the target no longer describes the
        // number on screen. Without it a CANCELLED gesture (#377) leaves a target standing that
        // the next drag builds on, throwing away any keypad or VoiceOver edit made in between.
        XCTAssertTrue(squashed.contains("V(ScrubPrecision.snapped(running,"), """
            The drag's base is no longer checked against the live value in `V`'s OWN precision. \
            In `Double` this check is worse than none: `Double(Float(0.57)) != 0.57`, so every \
            `Float` field would re-seed every event and the #376 dead zone would be back with \
            both guards green.
            """)
        XCTAssertTrue(squashed.contains("base=Double(value)"), """
            The drag no longer falls back to the live value when its target has gone stale, so \
            a gesture cancelled by the surrounding ScrollView can teleport the field on the \
            first event of the NEXT drag — and fire `onChange()` for a move nobody made, which \
            is this file's whole subject arrived at from the other side.
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
        // `fullRangePoints` is `private let` INSIDE the `#if canImport(SwiftUI)` block, so no
        // test in this bundle can read it — and `SlowScrubStillMovesTests` mirrors the 200 as a
        // literal. Pinning the source text is the only thing that keeps the two in step; without
        // it, changing the view's travel constant leaves every arithmetic assertion over there
        // green while measuring a gearing the app no longer has.
        XCTAssertTrue(src.contains("fullRangePoints: Double = 200"), """
            The full-range travel constant changed or was renamed. `SlowScrubStillMovesTests` \
            hardcodes 200 to compute a drag's per-event delta, so its numbers now describe a \
            control that does not exist — update both together or neither.
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

    /// #377 — THE CANCELLED GESTURE. SwiftUI does not call `onEnded` when a parent `ScrollView`
    /// claims a drag, and these fields sit in one, so without a second path every latch this
    /// gesture sets stays standing and the NEXT drag inherits it. `@GestureState` is the one
    /// wrapper SwiftUI resets by itself in that case; watching it fall back to `false` is the
    /// cancellation signal the callbacks cannot give.
    ///
    /// ⚠️ A SOURCE SCAN AGAIN, AND WEAKER HERE THAN ANYWHERE ELSE IN THIS FILE: it cannot show
    /// that SwiftUI re-evaluates the view when it resets a `@GestureState`, which is the entire
    /// mechanism. That is documented behaviour and a device question. What this holds is that
    /// the wiring exists, that the cancellation path does NOT commit, and that the two cleanups
    /// stay a deliberate PAIR rather than drifting apart — `resetScrubState` for the normal end,
    /// `unlatchScrub` for the falling edge, differing in exactly one field.
    ///
    /// ⛔ THAT LAST CLAUSE SAID "BOTH PATHS CLEAR THROUGH ONE FUNCTION" AND #378's NACHLESE
    /// RETIRED IT. One function was the right answer while both paths wanted the same three
    /// fields cleared. They do not: the falling edge must drop what a NEXT drag could inherit
    /// (`scrubbing`, `scrubTarget`) and must NOT drop `scrubStartValue`, because a normal
    /// `onEnded` may still be delivered afterwards and measures its commit against it. #378's
    /// first version merged them anyway — behind a deferred task justified by an ordering
    /// assumption — and would have lost that commit silently whenever the assumption was wrong.
    /// Two functions, one difference, and a guard on each half is the honest shape.
    func testACancelledGestureHasAPathToClearItsLatches() throws {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent("Sources/Echoelmusic/Studio/EchoelValueField.swift")
        guard let src = try? String(contentsOf: path, encoding: .utf8) else {
            throw XCTSkip("EchoelValueField.swift not readable at \(path.path) — scan skipped")
        }
        let squashed = src.components(separatedBy: .whitespacesAndNewlines).joined()

        XCTAssertTrue(src.contains("@GestureState private var dragActive"), """
            The gesture no longer carries a `@GestureState`. Every other latch here is `@State`, \
            which SwiftUI does NOT reset on cancellation — without this one there is no signal \
            that a drag was taken away, and the stale-latch class of #377 is open again.
            """)
        // ⛔ THE CLOSURE BODY IS PART OF THE NEEDLE, and the first draft pinned only the call.
        // `.updating($dragActive) { _, _, _ in }` would have passed it and produced exactly the
        // state the message warns about: never true, never falling, cancellation path dead,
        // blocking gate green. A guard whose own message describes the hole it leaves open is
        // the worst kind.
        XCTAssertTrue(squashed.contains(".updating($dragActive){_,active,_inactive=true}"), """
            `dragActive` is declared but not driven to `true` on every event, so it can never \
            fall back to `false` and the watcher below can never fire. A latch that cannot \
            change is worse than none: it reads as cover.
            """)
        // THE WHOLE CLOSURE, bound value included — because the #378 Nachlese proved that every
        // single piece of it is load-bearing and that a partial needle catches none of them.
        //
        // ⛔ THE SHAPE THIS REPLACES WAS WRONG IN TWO WAYS AT ONCE, and both reviewers found them
        // independently. It deferred the UNLATCH as well as the revert, which re-opened the
        // stale-latch window #377 exists to close (a drag starting inside the hop skipped the
        // anchor branch and measured its first delta against the abandoned gesture's
        // translation). And it decided cancel-vs-normal-end by asking `scrubbing` after the hop,
        // calling that a proof — it is an assumption about SwiftUI's dispatch, and the price of
        // it being wrong had just risen from nothing to a silently dropped `onCommit()` plus a
        // snapback. `unlatchScrub()` is therefore synchronous and `endedSeq` is a recorded fact.
        XCTAssertTrue(squashed.contains(SourceNeedles.cancellationWatcher), """
            The cancellation watcher changed shape. Every clause is a defect that was actually \
            shipped once: unlatch SYNCHRONOUSLY or the next drag inherits this one's anchors · \
            defer the REVERT or a normal end gets judged a cancel · `gestureSeq` or a drag that \
            started inside the hop is reverted under the user's finger · `endedSeq` or the \
            cancel-vs-end question is answered by assumption instead of by record.
            """)

        // #378: what a cancelled gesture DOES. Restore, tell the engine, yield to anyone else.
        XCTAssertTrue(squashed.contains(
            "ifletstart,start!=lastWritten,value==lastWritten{value=startonChange()}"
        ), """
            `revertCancelled` changed shape. It must put the number back and re-fire \
            `onChange()` so the live-applies follow it (otherwise the screen and the sound \
            disagree, which is worse than either alone). `value == lastWritten` is not optional \
            polish: it is the rule `544ac8f` set one commit earlier — a gesture may not assert \
            its own target once somebody else has written the value. `AutomationPlayer` rewrites \
            the master level and the tempo every tick, and the tempo write also cancels a glide.
            """)

        // ⛔ A `contains` CANNOT PROVE AN ABSENCE, and the first version of the assertion above
        // claimed one in its message ("must NOT fire onCommit()") while testing a substring that
        // stayed green if `onCommit()` were appended right after it. Absence needs the function's
        // own text, so read it.
        let revert = Self.functionBody(named: "revertCancelled", in: src)
        XCTAssertFalse(revert.isEmpty, """
            `revertCancelled` is gone from EchoelValueField — if the cancellation revert was \
            removed, remove this assertion with it rather than letting it pass on empty text.
            """)
        XCTAssertFalse(revert.contains("onCommit()"), """
            The cancellation path fires `onCommit()`. A drag the ScrollView took away is not a \
            finished edit: committing it re-rolls the mood, re-tunes the take or writes a preset \
            for a gesture the user never completed.
            """)

        // ⛔ `unlatchScrub` MUST NOT TOUCH `scrubStartValue`, and that asymmetry is the fix. It
        // runs synchronously at the falling edge, where a normal `onEnded` may still be coming;
        // that callback measures `moved` against `scrubStartValue`, so nilling it here drops a
        // finished edit's commit — the exact regression `6046db7` refused in writing.
        let unlatch = Self.functionBody(named: "unlatchScrub", in: src)
        XCTAssertFalse(unlatch.isEmpty, "`unlatchScrub` is gone from EchoelValueField.")
        XCTAssertFalse(unlatch.contains("scrubStartValue"), """
            `unlatchScrub` drops `scrubStartValue`. It runs synchronously at the falling edge, \
            where `onEnded` may still be delivered for the same gesture — and `onEnded` measures \
            `moved` against exactly this reference. Nilling it here makes every normal drag whose \
            end arrives after the falling edge compute `moved == false` and lose its `onCommit()`.
            """)

        // ⛔ PLACEMENT, NOT PRESENCE. The first needle was a bare `gestureSeq&+=1` anywhere in
        // the file — it would have stayed green with the stamp moved into every event (which
        // defeats it completely) and, worse, it stayed green while the stamp sat in a branch the
        // cancel path could not reach. Pin it to the anchor branch's first two statements.
        XCTAssertTrue(squashed.contains("if!scrubbing{scrubbing=truegestureSeq&+=1"), """
            The gesture stamp left the anchor branch. It has to be the thing that fires when a \
            NEW drag begins, because that is the only event the deferred cancel check can use to \
            recognise that the drag it saw end is no longer the drag in flight.
            """)
        XCTAssertTrue(squashed.contains("endedSeq=gestureSeqletmoved=scrubStartValue"), """
            `onEnded` no longer records that it ran, or records it after measuring the commit. \
            `endedSeq` is the ONLY evidence the deferred cancellation task has that this gesture \
            ended legitimately; without it that task falls back to inferring SwiftUI's dispatch \
            order, which is what the #378 Nachlese removed.
            """)
        XCTAssertTrue(squashed.contains("resetScrubState()ifmoved{onCommit()}"), """
            `onEnded` stopped clearing through `resetScrubState()`. Two hand-written cleanups \
            are how a latch gets forgotten in one of them — which is the whole history of #376 \
            and #377 in this file.
            """)
        // Whole trimmed LINES, not substrings — the declaration reads
        // `@State private var scrubbing = false` and a substring count would score it as a
        // clear.
        //
        // ⛔ THIS NUMBER HAS BEEN 1, 2, 1, AND IS NOW 2 AGAIN IN FOUR CONSECUTIVE COMMITS, and
        // the history is the useful part: 1 while `resetScrubState()` was the only clear · 2
        // while #377's watcher unlatched by hand · 1 while #378's first version deferred the
        // whole cleanup into `resetScrubState()` · 2 again now that the unlatch is synchronous
        // and named (`unlatchScrub`). A guard whose expected value moves with every slice tracks
        // an implementation detail — kept anyway, because what it actually protects is "the set
        // of places that decide a drag is over is small and deliberate", and all four of those
        // commits would have changed it unnoticed.
        let clears = src.split(separator: "\n").filter {
            $0.trimmingCharacters(in: .whitespaces) == "scrubbing = false"
        }.count
        XCTAssertEqual(clears, 2, """
            `scrubbing` is cleared in \(clears) places, not 2. It must be exactly two — \
            `resetScrubState()` for the normal end and `unlatchScrub()` for the falling edge. \
            They differ in one respect only (whether `scrubStartValue` goes with it) and that \
            one respect is what keeps a late `onEnded` able to commit.
            """)
    }

    /// The needle for the whole cancellation watcher, kept out of the assertion so it is ONE
    /// string literal and not a `+` chain in an autoclosure — #287 took the blocking gate red
    /// with exactly that shape (`3379bb3`), and this is the position where the type-checker pays
    /// most.
    private enum SourceNeedles {
        static let cancellationWatcher = ".onChange(of:dragActive){_,inFlightinguard!inFlight,scrubbingelse{return}letseq=gestureSeqletstart=scrubStartValueletwrote=valueunlatchScrub()Task{@MainActoringuardgestureSeq==seq,endedSeq!=seqelse{return}revertCancelled(to:start,lastWritten:wrote)}}"
    }

    /// Raw text of `private func <name>`'s body, from its declaration to the next declaration at
    /// the same indentation. Used only where a `contains` cannot express the claim — an ABSENCE.
    /// Returns "" when the function is not found, so callers must assert non-empty first rather
    /// than reading an empty string as "clean".
    private static func functionBody(named name: String, in source: String) -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains("private func \(name)(") })
        else { return "" }
        var end = start + 1
        while end < lines.count, !lines[end].hasPrefix("    }") { end += 1 }
        return lines[start...min(end, lines.count - 1)].joined(separator: "\n")
    }
}
