// ACleanExitIsNotACrashTests.swift
// Echoel — using biofeedback must not make the next launch open with a log dump. #582.
//
// WHAT THIS GUARDS. `EchoelStudioView.onAppear` calls `surfacePriorCrashIfAny()`, which reads the
// PREVIOUS session's `echoel_diag.log` and, if it looks like that session died badly, presents the
// raw log in a sheet. The intent is good and stays: a foreground death — jetsam, the watchdog, a
// kill that outruns the signal handler — writes NO crash marker, so the only evidence such a death
// leaves is "the session reached biofeedback and then simply stopped".
//
// ⛔ THE BUG. The gate was `prev.contains("Start tapped") || prev.contains("CRASH")`, and
// `Start tapped` is written by the ordinary Start button (`EchoelStudioView.startBiofeedback`).
// The first arm therefore matched every normal session in which the app's CORE INTERACTION was
// used. Pressing Start and later leaving is not a crash; it is the app working. So the second
// launch of a working app opened onto a screen of timestamps. #580 sharpened it into a
// first-impression defect: since that slice the app comes up as a full-bleed Metal visual with the
// chrome mounted beneath, so the log now lands on an unexplained picture instead of on the
// recognisable studio.
//
// THE REPAIR is subtraction, not removal: `EchoelCrashLog.looksLikeUnseenCrash` keeps both arms
// and takes away the sessions that ended in `background` — the clean exits. Everything the
// heuristic was built to catch still surfaces.
//
// ⭐ WHY THE LOGIC MOVED OUT OF THE VIEW. `surfacePriorCrashIfAny` is `private` on a `View` no test
// bundle can instantiate, so the old condition could only ever be checked by looking at its
// spelling. As a `String → Bool` on a Foundation-only type it is END-TO-END DRIVABLE, and eight of
// the assertions below are the strong kind (§1) rather than a source-text scan. That is the reason
// for the move, and it is worth more than the tidiness.
//
// ⚠️ HONEST LIMITS.
//   · 13 tests, 19 assertions (`grep -c`, not counted by eye — three slices in a row in this
//     bundle reported the number of `func`s as the number of assertions). Nine tests are
//     END-TO-END BEHAVIOUR against the shipped function; four are a SOURCE-TEXT SCAN pinning
//     that the two writers and the one reader still use the shared constants, which no
//     behavioural test can see (the writers are `View`/`App` members).
//   · DEVICE PROBE, open and NOT covered: that a real jetsam kill on a real phone leaves a log
//     whose last scene line is not `background`. The cases below are hand-built logs in the shape
//     the writer emits; they prove the decision, never the capture.
//
// ⭐ GRADING (§3), and it is the honest form of "cannot be graded". This file names
// `EchoelCrashLog.looksLikeUnseenCrash`, `.lastScenePhase(in:)`, `.sceneTransition(from:to:)` and
// three constants, ALL created by this same commit — so the file DOES NOT COMPILE against the
// parent tree and NO assertion has a verdict there. Do not read that as "green on its own tree":
// it was hand-transcribed instead (both gates in Python, driven over the nine logs below against
// the parent's `contains("Start tapped") || contains("CRASH")`).
//   · The transcription flips exactly ONE verdict of nine logs — the clean exit — which is the
//     regression this slice exists for. Two assertions express it (tests 1 and 2); that is ONE
//     finding reported twice, not two findings (#486).
//   · The other eight logs are COUNTERWEIGHTS: the parent's gate and this one agree on every case
//     where a report is genuinely wanted, which is the point (#343). A repair that also silenced
//     the foreground death, the return-from-background death, or either crash case would be worse
//     than the bug it fixes.
//   · The stripper is **TRAGEND (1 of 6 needles flips)**, measured raw vs. stripped over the six
//     needles the four scans use — and the flip is caused by this very slice. ⛔ The first version
//     of this header claimed "PROPHYLAKTISCH, 0 of 4", by eye and in the flattering direction
//     twice over (the count is six, not four). What actually happens: `surfacePriorCrashIfAny`
//     now carries a ⛔ block that QUOTES the retracted condition `prev.contains("Start tapped")`,
//     so the negative needle for it is present RAW in `EchoelStudioView.swift` and absent only
//     after stripping. Without `SourceText.codeOnly` this guard would be red on a correct tree —
//     which is #453's thesis arriving in the same commit that doubted it. Measure, do not
//     estimate; and a file that documents what it forbids is exactly where the estimate fails.

import Foundation
import XCTest
@testable import Echoelmusic

final class ACleanExitIsNotACrashTests: XCTestCase {

    // The nine logs are written in the shape `EchoelCrashLog.breadcrumb` emits: a timestamp, two
    // spaces, the message. Built through `sceneTransition` where a transition is meant, so a change
    // to that shape cannot leave these fixtures describing a format the app no longer writes.
    private func scene(_ old: String, _ new: String) -> String {
        "1785340629.599  " + EchoelCrashLog.sceneTransition(from: old, to: new) + "\n"
    }
    private let launch = "1785340620.001  launch v10.79.389 (2506)\n"
    private var started: String { "1785340625.100  " + EchoelCrashLog.startTappedMarker + "\n" }

    // MARK: - END-TO-END: what must NOT surface

    /// THE REGRESSION (1 of 1). A session that used biofeedback and then left cleanly is the
    /// overwhelmingly common case, and it must produce nothing. On the parent tree this is `true`.
    func testACleanExitAfterBiofeedbackDoesNotSurface() {
        let log = launch + started + scene("active", "inactive") + scene("inactive", "background")
        XCTAssertFalse(EchoelCrashLog.looksLikeUnseenCrash(log),
                       "Pressing Start and then leaving the app is the app WORKING. The next "
                       + "launch must not open with a log dump — that was #582.")
    }

    /// The same fact from the other end: it is the ENDING that decides, not the presence of Start.
    /// Stated separately because a repair that dropped the `Start tapped` arm entirely would also
    /// pass the test above while destroying the heuristic (see the counterweight in test 4).
    func testItIsTheLastPhaseThatDecidesNotThePresenceOfStart() {
        let clean = launch + started + scene("active", "background")
        let unseen = launch + started
        XCTAssertFalse(EchoelCrashLog.looksLikeUnseenCrash(clean))
        XCTAssertTrue(EchoelCrashLog.looksLikeUnseenCrash(unseen),
                      "Same Start, different ending — the ending is the whole signal.")
    }

    /// A first launch has no previous log at all.
    func testAnEmptyLogSurfacesNothing() {
        XCTAssertFalse(EchoelCrashLog.looksLikeUnseenCrash(""))
    }

    /// COUNTERWEIGHT. Someone who opened the app, looked around and left never reached Start, so
    /// there is nothing to report either — and this stayed true across the change.
    func testBrowsingWithoutStartingSurfacesNothing() {
        XCTAssertFalse(EchoelCrashLog.looksLikeUnseenCrash(launch + scene("active", "background")))
    }

    // MARK: - END-TO-END: what must STILL surface (the counterweights that carry the meaning)

    /// COUNTERWEIGHT — the case the whole heuristic exists for. A foreground death writes no
    /// marker; "reached Start, never left the foreground" is the only evidence there is.
    func testAForegroundDeathAfterStartStillSurfaces() {
        XCTAssertTrue(EchoelCrashLog.looksLikeUnseenCrash(
            launch + started + "1785340640.000  camera started\n"),
            "Jetsam/watchdog leave no CRASH line. Losing this case would make #582 a removal "
            + "rather than a repair.")
    }

    /// COUNTERWEIGHT and the reason `lastScenePhase` says LAST rather than `contains`. A long
    /// session switches apps and comes back; a log that merely MENTIONS `background` says nothing
    /// about how it ended. A `contains` repair would silence every multitasking user.
    func testReturningFromBackgroundAndThenDyingStillSurfaces() {
        let log = launch + started
            + scene("active", "background") + scene("background", "active")
            + "1785340700.000  generate[evolve]\n"
        XCTAssertEqual(EchoelCrashLog.lastScenePhase(in: log), "active")
        XCTAssertTrue(EchoelCrashLog.looksLikeUnseenCrash(log))
    }

    /// COUNTERWEIGHT. A real crash marker outranks everything, including a clean-looking ending —
    /// the signal handler can fire after the app has gone to the background.
    func testARecordedCrashSurfacesEvenAfterBackgrounding() {
        let log = launch + started + scene("active", "background")
            + "1785340650.000  CRASH SIGSEGV (bad memory access / heap) — see breadcrumbs above\n"
        XCTAssertTrue(EchoelCrashLog.looksLikeUnseenCrash(log))
    }

    /// COUNTERWEIGHT. A crash before Start was ever pressed must still surface.
    func testACrashWithoutStartSurfaces() {
        XCTAssertTrue(EchoelCrashLog.looksLikeUnseenCrash(
            launch + "1785340621.000  CRASH SIGTRAP (Swift trap: precondition/force-unwrap/overflow)\n"))
    }

    /// COUNTERWEIGHT, and the reason the parser selects on the ARROW and not on the `scene: `
    /// prefix. `EchoelmusicApp` writes three other lines with that prefix — `scene: audio resumed`,
    /// `scene: audio continues`, `scene: idle audio engine stopped (2.5.4)` — none of which is a
    /// phase. A prefix-based parser would read "resumed" or "stopped (2.5.4)" as the final phase.
    func testNonTransitionSceneLinesAreNotPhases() {
        let log = launch + started
            + "1785340629.657  scene: idle audio engine stopped (2.5.4)\n"
            + "1785340641.907  scene: audio resumed\n"
        XCTAssertNil(EchoelCrashLog.lastScenePhase(in: log))
        XCTAssertTrue(EchoelCrashLog.looksLikeUnseenCrash(log))
    }

    // MARK: - SOURCE-TEXT SCAN: writer and reader must keep sharing one spelling

    /// The failure this pins is silent by construction: if a writer drifts from the constant the
    /// reader compares against, nothing goes red — the heuristic simply stops matching and the
    /// crash report quietly turns off. That is why the constants exist (#416) and why their USE is
    /// asserted rather than their value.
    func testTheStartMarkerIsWrittenThroughTheSharedConstant() throws {
        let src = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(src.contains("EchoelCrashLog.breadcrumb(EchoelCrashLog.startTappedMarker)"),
                      "The Start breadcrumb must go through the constant the reader matches on.")
        XCTAssertFalse(src.contains("breadcrumb(\"Start tapped\")"),
                       "A literal here and a constant in the reader is the drift this guards.")
    }

    /// The scene line must be BUILT by the function `lastScenePhase(in:)` is the inverse of.
    func testTheSceneLineIsWrittenThroughTheSharedBuilder() throws {
        let src = try source("Sources/Echoelmusic/EchoelmusicApp.swift")
        XCTAssertTrue(src.contains("EchoelCrashLog.sceneTransition(from:"),
                      "The transition breadcrumb must be built by the shared function.")
        XCTAssertTrue(src.contains("case .background: return EchoelCrashLog.backgroundPhase"),
                      "The phase token the reader compares against must have one definition.")
    }

    /// The emitted text must not have changed: founder logs going back months read
    /// `scene: inactive → background`, and `AudioEngineStopReasonTests` quotes that shape.
    func testTheEmittedSceneLineIsUnchanged() {
        XCTAssertEqual(EchoelCrashLog.sceneTransition(from: "inactive", to: "background"),
                       "scene: inactive → background")
    }

    /// The view must ASK the shared decision rather than restate it — the old condition being
    /// spelled out inside a private view member is what let it go four months unexamined.
    func testTheViewAsksTheSharedDecision() throws {
        let src = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(src.contains("EchoelCrashLog.looksLikeUnseenCrash(prev)"))
        XCTAssertFalse(src.contains("prev.contains(\"Start tapped\")"),
                       "The old gate must not survive as a second spelling of the decision.")
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct DiagAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DiagAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
