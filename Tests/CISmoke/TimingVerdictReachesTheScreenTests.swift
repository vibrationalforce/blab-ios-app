// TimingVerdictReachesTheScreenTests.swift
// Echoel — #408. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS PROTECTS, AND WHY IT IS NOT ABOUT AUDIO AT ALL. `RenderGapDetector` turns
// "es knistert" into a number (#193). It has been in the app for a week and has only ever
// written that number into `echoel_diag.log` — a file the founder has to find, export and
// send. The v10.79.369 report ("teilweise extremes Knacken") arrived without one. That is
// the NORMAL case, not a lapse, and it left six candidate mechanisms unseparated (#407).
//
// So this slice moves the verdict to where it is read at the moment the sound is heard.
// The failure modes it must not have are all about HONESTY, not about audio:
//   · a window in which the tap never fired must NOT read as a clean one — `isClean` is
//     `glitchCount == 0`, which is also true when there was no denominator at all;
//   · a clean window must NOT read as "the crackling is fixed" — this meter is blind to
//     the whole second class of click (voice steal, parameter step, un-faded seam);
//   · the row must show the LAST window, always, including the clean ones — the log
//     deliberately speaks only when dirty, and a row inheriting that rule would show a
//     ten-minute-old verdict to someone looking for one from now.
//
// ⚠️ THIS FILE PROVES A READOUT, NOT A DIAGNOSIS. It cannot make the crackling stop and it
// does not claim to. #404 stays open until a device listen; this exists so the next report
// arrives with its own measurement attached.

import Foundation
import XCTest
@testable import Echoelmusic

final class TimingVerdictReachesTheScreenTests: XCTestCase {

    private let window: Double = 60
    private let quantumMs: Double = 5.33      // 256 frames at 48 kHz — a real device value

    // MARK: - The line must not lie in either direction

    func testABlindWindowDoesNotReadAsACleanOne() {
        // THE ONE THAT MATTERS MOST. Tap lost after a media-services reset, route torn down,
        // graph stopped while the engine still claims to run: `glitchCount` is 0 and so is the
        // denominator. The log's proof-of-life rules exist to separate exactly these two, and
        // the whole point would come straight back if the row printed "Nothing late".
        let blind = RenderGapDetector.Tally(measuredIntervals: 0)
        let line = blind.screenLine(overSeconds: window, quantumMilliseconds: quantumMs)
        XCTAssertFalse(line.contains("Nothing late"), """
            A window with no measured intervals now reads as clean. That is the ambiguity \
            `RenderGapDetector`'s header spends a paragraph removing: silence from a dead \
            instrument must never look like silence from a healthy audio path.
            """)
        XCTAssertTrue(line.contains("Not measured"), """
            A blind window must SAY it is blind. Line was: \(line)
            """)
    }

    // ⛔ Named `…AndNothingMore` in the first version, which stopped being true the moment the
    // thin-evidence caveat landed — 400 intervals at 5.33 ms is 2 s of a 60 s window, so this
    // very fixture now carries one. A test name that describes yesterday's behaviour is the
    // stale-name trap this repo has already paid for at `RefractoryFollowsTheMeasuredRate`.
    func testACleanWindowNamesItsWindow() {
        let clean = RenderGapDetector.Tally(measuredIntervals: 400)
        let line = clean.screenLine(overSeconds: window, quantumMilliseconds: quantumMs)
        XCTAssertTrue(line.contains("Nothing late"), "Line was: \(line)")
        XCTAssertTrue(line.contains("60"), """
            The clean line drops its window length. "Nothing late" without a denominator is \
            the same over-claim the log line refuses to make. Line was: \(line)
            """)
    }

    func testADirtyWindowIsReportedInMillisecondsNotInQuanta() {
        // The log prints a multiplier because its reader is expected to know the buffer size.
        // The row's reader is not, and "2.4×" means nothing without it. Same measurement, unit
        // a person can compare against a sound they just heard.
        let dirty = RenderGapDetector.Tally(glitchCount: 3, worstLateInQuanta: 2.4,
                                            worstDriftInQuanta: 1.0, measuredIntervals: 400)
        let line = dirty.screenLine(overSeconds: window, quantumMilliseconds: quantumMs)
        XCTAssertTrue(line.contains("3 late"), "Line was: \(line)")
        XCTAssertTrue(line.contains("ms"), """
            The dirty line no longer carries a duration. 2.4 quanta is not a number the \
            founder can act on. Line was: \(line)
            """)
        XCTAssertFalse(line.contains("×"), """
            The row is showing the log's quanta multiplier. Line was: \(line)
            """)
        // 2.4 × 5.33 ms = 12.792 ms — pinned so a unit slip cannot pass as a formatting change.
        XCTAssertTrue(line.contains("12.8"), "Expected 12.8 ms in: \(line)")
    }

    func testAnUnknownQuantumStillReportsTheCount() {
        // The publish sits above the guard that requires a known quantum, so this case is
        // reachable: the count is real even when the buffer size lookup failed. Losing the
        // whole line there would be the instrument going quiet exactly when it is degraded.
        let dirty = RenderGapDetector.Tally(glitchCount: 7, worstLateInQuanta: 2.0,
                                            measuredIntervals: 400)
        let line = dirty.screenLine(overSeconds: window, quantumMilliseconds: 0)
        XCTAssertTrue(line.contains("7 late"), "Line was: \(line)")
        // ⛔ This asserted `!contains("0.0 ms")` — format-specific, so a switch to `%.2f`
        // would print "0.00 ms", which is not that substring, and the guard would have stayed
        // green over the fabricated figure it was written to forbid. Assert the absence of any
        // millisecond claim instead: with no quantum there is no duration to state at all.
        XCTAssertFalse(line.contains("ms"), """
            An unknown quantum produced a millisecond figure anyway. Line was: \(line)
            """)
    }

    func testANonFiniteWindowDoesNotPrintNaN() {
        for seconds in [Double.nan, .infinity, -1] {
            let clean = RenderGapDetector.Tally(measuredIntervals: 400)
            let line = clean.screenLine(overSeconds: seconds, quantumMilliseconds: quantumMs)
            XCTAssertFalse(line.lowercased().contains("nan"), "Line was: \(line)")
            XCTAssertFalse(line.contains("inf"), "Line was: \(line)")
        }
    }

    func testTheCaptionRefusesToBeAnAllClear() {
        // The caption is what stops "Nothing late" from reading as "the crackling is fixed".
        // It is shown unconditionally, so it must carry the disclaimer in its own words.
        let caption = RenderGapDetector.Tally.screenCaption
        XCTAssertFalse(caption.isEmpty)
        XCTAssertTrue(caption.lowercased().contains("timing"), """
            The caption no longer says what it is limited TO. Caption was: \(caption)
            """)
        // ⛔ THE FIRST VERSION OF THIS ASSERTION COULD NOT FAIL, AND BOTH REVIEWERS SAID SO
        // INDEPENDENTLY. It read `contains("not counted") || contains("not")`. The second
        // disjunct implies the first and matches "nothing", "note", "cannot", "another" — so
        // the caption "Timing looks good — nothing to worry about" passed BOTH assertions
        // while being precisely the all-clear sentence this test exists to forbid. A guard
        // with a fallback that swallows its own condition is the #367 trap wearing an OR.
        XCTAssertTrue(caption.lowercased().contains("not counted"), """
            The caption no longer says what it does NOT see. A clean timing window is not an \
            all-clear for a click that happens with the audio path on time. Caption was: \
            \(caption)
            """)
    }

    // MARK: - A mostly-blind window is not a measured one

    func testAMostlyBlindWindowSaysHowLittleItSaw() {
        // The over-claim one step milder than a fully blind window, and the one the first
        // version shipped: a route flapping through the window leaves 50 classified intervals
        // of which 48 are pause/restart artefacts. `measuredIntervals` looks healthy because
        // the tap counts them BEFORE classifying, `glitchCount` is 0, and the row read
        // "Nothing late in the last 60 s" — a clean verdict off a quarter-second of evidence.
        let thin = RenderGapDetector.Tally(discontinuityCount: 48, measuredIntervals: 50)
        let line = thin.screenLine(overSeconds: window, quantumMilliseconds: quantumMs)
        XCTAssertTrue(line.contains("measured"), """
            A window with 0.27 s of evidence in 60 s reads as fully measured. The field doc \
            of `measuredIntervals` states this rule verbatim and `diagnosticLine` honours it. \
            Line was: \(line)
            """)
    }

    func testAFullWindowCarriesNoCaveat() {
        // The other half, and the reason the caveat is conditional: a row that always carries
        // a qualifier trains its reader to stop reading it. 11_000 × 5.33 ms ≈ 59 s of 60.
        let full = RenderGapDetector.Tally(measuredIntervals: 11_000)
        let line = full.screenLine(overSeconds: window, quantumMilliseconds: quantumMs)
        XCTAssertEqual(line, "Nothing late in the last 60 s", """
            A fully measured window grew a caveat. Line was: \(line)
            """)
    }

    func testAnUnknownQuantumCannotInventADenominator() {
        // Without the buffer duration a COUNT of intervals cannot become a SPAN. Silence is
        // the honest answer there; a guessed number would be worse than none.
        let thin = RenderGapDetector.Tally(discontinuityCount: 48, measuredIntervals: 50)
        let line = thin.screenLine(overSeconds: window, quantumMilliseconds: 0)
        XCTAssertFalse(line.contains("measured"), """
            The row named a measured span with no quantum to derive it from. Line was: \(line)
            """)
    }

    // MARK: - The row after Stop

    func testAPreStopVerdictIsNotPresentedAsCurrent() {
        // `stop()` invalidates the meter poll timer and does NOT clear `lastTimingLine`, so
        // the string outlives the measurement. The realistic sequence is the one #408 exists
        // for: play, hear the crackle, hit Stop, open Master — and read a clean verdict from
        // before the stop as if it described now. The commit's own message argued "stale is
        // worse than clean: a wrong answer, not a missing one" and then applied that argument
        // only to the log gate.
        let line = "Nothing late in the last 60 s"
        let stopped = RenderGapDetector.Tally.screenText(line: line, isRunning: false)
        XCTAssertNotEqual(stopped, line, """
            A verdict measured before the stop is shown verbatim, as if it were current.
            """)
        XCTAssertTrue(stopped.contains(line), """
            The verdict was discarded rather than qualified. Discarding trades a wrong answer \
            for a missing one — and the founder's own gesture is to stop and THEN look. \
            Text was: \(stopped)
            """)
    }

    func testARunningVerdictIsShownVerbatim() {
        let line = "3 late in 60 s · worst 12.8 ms behind"
        XCTAssertEqual(RenderGapDetector.Tally.screenText(line: line, isRunning: true), line)
    }

    func testTheWaitingStateDistinguishesRunningFromStopped() {
        // Before the first window closes there is nothing to show. "Measuring…" is true while
        // the engine runs and a lie once it does not — nothing is measuring after Stop.
        let running = RenderGapDetector.Tally.screenText(line: nil, isRunning: true)
        let stopped = RenderGapDetector.Tally.screenText(line: nil, isRunning: false)
        XCTAssertNotEqual(running, stopped, """
            The empty state reads the same whether or not the engine is measuring.
            """)
        XCTAssertTrue(running.lowercased().contains("measuring"), "Was: \(running)")
        XCTAssertFalse(stopped.lowercased().contains("measuring…"), "Was: \(stopped)")
    }

    // MARK: - The wiring: every window, and a leaf

    func testTheScreenIsUpdatedOnEveryWindowNotOnlyTheReportedOnes() throws {
        // ⭐ THE ASSERTION THIS FILE EXISTS FOR. `shouldReportTimingWindow` suppresses clean
        // windows so `echoel_diag.log` stays readable — correct for the log, wrong for a row
        // that is read live. If the publish ever moves below that guard, the row silently
        // freezes on the last DIRTY verdict and shows it as the present state: a wrong answer
        // rather than a missing one, which is worse.
        //
        // An ORDERING check on the source, not a presence check — presence is satisfied by
        // both the right and the wrong arrangement. The two tokens are chosen to appear only
        // at the code sites: the property's own doc names `lastTimingLine` without the
        // assignment, and the comment above the assignment names `shouldReportTimingWindow`
        // without its argument label. That is the #367 trap in its prose form, avoided by
        // construction rather than by hoping the comments never change.
        //
        // ⛔ THE FIRST VERSION OF THIS TEST FAILED, AND IT IS THE SAME TRAP ONE STEP OVER.
        // It anchored on `shouldReportTimingWindow(firstWindow:` — which matches the function
        // DECLARATION (line ~1169) before it ever reaches the CALL (~1260). `range(of:)` returns
        // the FIRST occurrence, so the guard compared 1228 < 1169 and went red on correct code.
        // A source scan must anchor on a token that occurs ONLY at the site it means; here the
        // `Self.` prefix is what makes it the call and nothing else. Checking that a token is
        // unique is part of writing the scan, not a detail.
        //
        // ⚠️ WHAT IT DOES NOT PROVE, stated so nobody reads more into a green than is there:
        // this is TEXTUAL order, not control flow. Inserting `guard !tally.isClean else
        // { return }` above the publish would break the behaviour and keep this green. A real
        // proof needs the poll driven from a test, which needs an engine, which this bundle
        // cannot start. The comment strip below is belt-and-braces on top of anchors already
        // chosen to be unique in code.
        let source = SourceText.codeOnly(try Self.read("Sources/Echoelmusic/Audio/AudioEngine.swift"))
        guard let publish = source.range(of: "lastTimingLine = tally.screenLine("),
              let gate = source.range(of: "Self.shouldReportTimingWindow(firstWindow:") else {
            return XCTFail("""
                One of the two anchors is gone. Either the screen publish or the log gate was \
                renamed, and this guard can no longer see their order.
                """)
        }
        XCTAssertTrue(publish.lowerBound < gate.lowerBound, """
            The screen publish moved BELOW the log's report gate. Clean windows now leave the \
            Master row showing the last dirty verdict as if it were current.
            """)
    }

    func testTheRowIsItsOwnViewAndIsMounted() throws {
        // Both halves, because either alone is the defect this repo keeps paying for: a leaf
        // nobody mounts is a doorless view, and a mounted read that is not a leaf is the
        // 10.76.50 freeze class one refactor away.
        //
        // ⛔ CODE ONLY, NOT RAW TEXT — the fix the ordering test above got by construction and
        // this one did not. Both anchors are unique today, but comment out the mount and leave
        // the tombstone this repo habitually writes (`// AudioTimingRow(engine: audioEngine)`)
        // and a raw `contains` stays green over a view that is gone from the UI.
        // `NoDoorlessStudioViewsTests` has a test named for exactly this — prose about a view
        // does not count as mounting it — and strips comments for the same reason.
        let source = SourceText.codeOnly(try Self.read("Sources/Echoelmusic/Studio/EchoelStudioView.swift"))
        XCTAssertTrue(source.contains("private struct AudioTimingRow: View"), """
            The timing readout is no longer its own View. Read from `masterPanel` directly it \
            enrols the root body as an observer of an AudioEngine property — the class the \
            10.76.50 audit had to find one level above the obvious view.
            """)
        XCTAssertTrue(source.contains("AudioTimingRow(engine: audioEngine)"), """
            The timing row is not mounted anywhere. A verdict nobody can see is the state \
            #408 exists to end.
            """)
    }

    // ⛔ A PRIVATE `codeOnly` STOOD HERE AND IT MADE THE #453 GUARD RED FROM THE DAY IT WAS
    // WRITTEN. #453 (2026-08-06) folded eleven comment-strippers into `SourceText.codeOnly` and
    // installed `OneDefinitionOfCodeNotProseTests.testNoUnlistedFileDeclaresItsOwnStripper` to
    // stop a TWELFTH appearing. The twelfth was already here — this file (#408) predates #453 —
    // and the guard's own anchor, `func codeOnly` without `SourceText.codeOnly`, selects it
    // deterministically: replicating that logic against the tree returns exactly
    // `["TimingVerdictReachesTheScreenTests.swift"]`.
    //
    // ⚠️ SAID EXACTLY, because the flattering phrasing was "the guard named it on the first run"
    // and that is a claim about a RUN, which cannot be supported. The assertion appears in no
    // flushed CI log, and under #445 that absence proves nothing either way — #396 kills one
    // simulator clone mid-suite and the surviving clone flushes a non-deterministic subset. So
    // the honest statement is: the guard WOULD have failed on every run that reached it, and
    // whether any run reached it is unknowable. That is worse than a missed red, not better —
    // a guard whose verdict cannot be observed is not yet a guard.
    //
    // ⭐ THE LESSON IS NOT "the survey was sloppy" — it is sharper than that. #453's survey and
    // #453's guard used DIFFERENT detection methods, and the guard's was the better one. When
    // the two disagree, the guard is the measurement and the survey is a memory of one. Here the
    // check that would have settled it was written, shipped, and never readable.
    //
    // ⚠️ THE SWAP IS VERDICT-NEUTRAL, MEASURED RATHER THAN ASSUMED, because the two shapes are
    // NOT interchangeable in general — `testEveryScanningGuardDelegates` names the exact place
    // they disagree. Both files this test scans were run through both strippers before the edit:
    // `AudioEngine.swift` differs on **0 lines** (so the two `range(of:)` byte offsets that the
    // ordering assertion compares are bit-identical, 32771 and 33257 under either shape), and
    // `EchoelStudioView.swift` differs on **exactly 1** — the WeatherKit attribution line,
    // `URL(string: "https://developer.apple.com/…")`, which the naive shape truncated at the
    // `//` inside the string literal. (Named, not numbered: the line index moves with every
    // insertion above it, the phrase does not.) It holds none of the four anchors. The ordered
    // scanner keeps it, which is the correct reading and the reason #453 exists.
    private static func read(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/CISmoke
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(relativePath)
        // SKIPS rather than reporting a green it did not earn — and rather than a RED it did
        // not earn either, which is what a raw read error would be on a host where the source
        // tree is not co-located with the built bundle.
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(relativePath) not reachable from \(#filePath) — tree not co-located.")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
