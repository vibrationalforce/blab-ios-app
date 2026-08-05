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

    func testACleanWindowNamesItsWindowAndNothingMore() {
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
        XCTAssertFalse(line.contains("0.0 ms"), """
            An unknown quantum produced a fabricated 0.0 ms figure. Line was: \(line)
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
        XCTAssertTrue(caption.lowercased().contains("not counted")
                      || caption.lowercased().contains("not"), """
            The caption no longer says what it does NOT see. A clean timing window is not an \
            all-clear for a click that happens with the audio path on time. Caption was: \
            \(caption)
            """)
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
        let source = try Self.read("Sources/Echoelmusic/Audio/AudioEngine.swift")
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
        let source = try Self.read("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
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
