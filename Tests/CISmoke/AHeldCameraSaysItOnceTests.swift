// AHeldCameraSaysItOnceTests.swift
// Echoel — #576. A diagnostic that repeats a stale reading is worse than one that is quiet.
//
// THE DEVICE EVIDENCE, measured from the founder's v10.79.388/2505 log, one backgrounded
// stretch from t=1786636631 to t=1786636851 — **220 seconds**:
//   · ~105 lines of `rPPG: finger=yes R=0.39 bright=0.38 q=0.00 … in=0.0 … cue=Press gently`,
//     byte-identical, every ~2.1 s;
//   · ~35 lines of `rPPG: no frames ~6 s but iOS holds the camera (interrupted)`, identical,
//     every ~6.3 s;
//   · **~140 lines of noise from ONE stretch**, in the file the founder also reads for launch
//     and crash triage.
//
// ⭐ AND THE VOLUME IS THE SMALLER HALF. `finger=yes R=0.39 bright=0.38` was the analyzer's
// LAST value from before the interruption, reprinted as if current, while `in=0.0` in the very
// same line said nothing had arrived. A reader who trusts the left of the line and misses the
// `in=0.0` concludes a finger is on the lens and the signal is dead — the exact wrong
// diagnosis, offered 105 times. The repo already knows this shape: the 2026-07-25 TRUTH GATE
// exists because a stalled camera published a FROZEN pulse with a FRESH timestamp. This is the
// same defect one layer out, in the log instead of on the bus.
//
// WHAT #576 CHANGES: nothing but the speaking. The recovery ladder, the waiting behaviour
// ("iOS holds it — wait, do not thrash restarts"), the banner state and the publish gate are
// untouched. The hold is announced ONCE per episode, the stale 2 s line is suppressed while it
// holds, and the return of frames is announced once so silence can never be confused with a
// dead loop.
//
// ⚠️ THE LIMIT, PER ASSERTION (§1): all SOURCE-TEXT SCANS. `CameraRPPGBioPublisher`'s publish
// loop is a `private` `Task` inside a `@MainActor` class driving a real `AVCaptureSession`;
// no test bundle can run it. DEVICE PROBE, open and NOT covered: whether the next log is
// actually readable through a backgrounding. That is the founder's next paste.
//
// ⚠️ HONEST GRADING (§3), hand-transcribed in Python against the parent (`45764be`) and this
// tree — no local toolchain (§0):
//   · claims 1–3 are REGRESSIONS on the parent for the reason their names give: `heldQuiet`
//     does not exist there, the hold breadcrumb is unconditional, and the 2 s line has no
//     guard. ONE absence, reported once (#486).
//   · claim 4 is a COUNTERWEIGHT, green on both trees, and it is the reason this file is not
//     three positive scans: the silence must not have been bought by making the publisher DO
//     less. The waiting branch, the banner block it must still fall through to, and the whole
//     recovery ladder are pinned as still present. Buying a quiet log by disabling recovery
//     would satisfy every other assertion in this file.
//   · STRIPPER: **TRAGEND (1 of 7 verdicts flip)** — measured raw vs. stripped on both trees,
//     after two of this file's own assertions were caught red on a correct tree by exactly
//     that transcription (⛔ blocks at both sites). The claimed "2 of 5" was written before
//     the measurement and is retracted; the flip is the fall-through needle, which existed
//     only in a comment and is why that assertion had to be rebuilt at code level.

import Foundation
import XCTest

final class AHeldCameraSaysItOnceTests: XCTestCase {

    private static let publisherPath = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"

    // MARK: - claim 1 — the hold is announced once, not every six seconds

    func testTheHoldBreadcrumbIsLatched() throws {
        let src = try source(Self.publisherPath)
        XCTAssertEqual(src.components(separatedBy: "if !self.heldQuiet {").count - 1, 1, """
            The held-interruption breadcrumb is no longer behind a latch. Unlatched it fires \
            every ~6 s for as long as iOS holds the camera — 35 identical lines in the 220 s \
            stretch this guard was written from. The message is a STATE; a state that has not \
            changed carries no information the thirty-fifth time.
            """)
        XCTAssertTrue(src.contains("self.heldQuiet = true"), """
            Nothing sets `heldQuiet`, so the latch can never engage and the announcement is \
            unlatched in effect while looking latched in source.
            """)
    }

    // MARK: - claim 2 — and the silence ends out loud

    /// The half that makes the silence readable. Without it a quiet stretch is
    /// indistinguishable from a crashed loop, which is a worse failure than the noise.
    func testTheReturnOfFramesIsAnnounced() throws {
        let src = try source(Self.publisherPath)
        XCTAssertTrue(src.contains("self.heldQuiet = false"), """
            Nothing clears `heldQuiet`. Once the latch engages the publisher would stay silent \
            for the rest of the session, and a silent log cannot be told apart from a dead one.
            """)
        XCTAssertTrue(src.contains("frames are back after a held interruption"), """
            The end of a held interruption is no longer announced. A reader then sees a hold \
            reported once and nothing afterwards, and cannot tell recovery from a hang.
            """)
        // A NEW session must not inherit silence — otherwise a start that lands straight into
        // an interruption says nothing at all, and "quiet" stops meaning "already reported".
        //
        // ⛔ THE FIRST VERSION COUNTED `"heldQuiet = false"` AND DEMANDED TWO. That substring
        // also matches the DECLARATION (`private var heldQuiet = false`), so the true count is
        // three and the assertion was red on a correct tree — #367 in one line. Caught by
        // transcribing it in Python against both trees, which is the whole point of §0. The two
        // sites are pinned individually now, because they fail differently and a single number
        // could never say which one went.
        XCTAssertEqual(src.components(separatedBy: "self.heldQuiet = false").count - 1, 1, """
            The frames-returned clear is missing or duplicated. Without it the log goes \
            permanently silent after the first hold, and silence cannot be told apart from a \
            dead loop.
            """)
        let startClear = "heldQuiet = false\n        EchoelCrashLog.breadcrumb"
        XCTAssertTrue(src.contains(startClear), """
            `start()` no longer clears `heldQuiet`, so a session that begins while the camera \
            is already interrupted inherits the previous session's silence and never reports \
            the hold at all. That is the failure mode the frames-returned clear cannot cover.
            """)
    }

    // MARK: - claim 3 — the stale 2 s line is suppressed while the hold holds

    func testTheStaleDiagnosticIsSuppressedWhileHeld() throws {
        let src = try source(Self.publisherPath)
        XCTAssertTrue(src.contains("if tick % 20 == 0, !self.heldQuiet {"), """
            The ~2 s rPPG diagnostic no longer checks `heldQuiet`. While the OS holds the \
            camera and nothing arrives, every value in that line is the analyzer's last \
            PRE-interruption reading — `finger=yes R=0.39 bright=0.38` printed beside \
            `in=0.0`. That is not merely noise: a reader who trusts the left of the line \
            concludes a finger is on the lens and the signal is dead. It was offered 105 \
            times in one 220 s stretch.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — the silence was not bought with behaviour

    /// Green on both trees, and the point of the file. Every assertion above is satisfied just
    /// as well by a publisher that stops recovering, stops waiting, or stops rendering the
    /// banner — which would be a far worse bug than the one #576 fixes, and invisible to a
    /// scan that only checks what is no longer printed.
    func testTheWaitingAndRecoveryBehaviourIsUnchanged() throws {
        let src = try source(Self.publisherPath)
        XCTAssertTrue(src.contains("if self.capture.isInterrupted {"), """
            The interrupted branch is gone from the stall ladder. That branch is what stops \
            the publisher from burning its recovery budget, the battery and heat on restarts \
            iOS will refuse — device log 1783749556: 3 forced recoveries + 8 cold restarts, \
            0 frames, ~3 min. #576 was allowed to change the LOGGING only.
            """)
        // ⛔ THE FIRST VERSION SCANNED FOR THE FALL-THROUGH COMMENT — a needle that
        // `SourceText.codeOnly` blanks by construction, so it was FALSE on both trees and red
        // on correct code. A guard cannot assert prose through the one stripper whose job is
        // to remove prose (#367, and §2's "one stripper" is exactly why the mistake is easy).
        // The invariant it was reaching for is code-level and is pinned properly here: the
        // interrupted test appears TWICE — once in the stall ladder, once in the banner block
        // below it — and that second occurrence is only reachable because the first does not
        // `continue`.
        XCTAssertEqual(src.components(separatedBy: "if self.capture.isInterrupted {").count - 1, 2, """
            `self.capture.isInterrupted` is tested a number of times other than two in the \
            publish tick. If the stall-ladder branch starts skipping the rest of the tick, the \
            banner block below never runs, the on-screen state stops showing the interruption, \
            and the user is told nothing while the log has also gone quiet — the two halves of \
            #576 failing together.
            """)
        for needle in ["forcing camera recovery", "cold camera restart", "recoverFromStall()"] {
            XCTAssertTrue(src.contains(needle), """
                `\(needle)` is gone from the publisher. The recovery ladder for a REAL stall \
                (frames stopped while the session is NOT interrupted) is a different path \
                from the held case and must keep both its behaviour and its breadcrumbs — \
                those are loud on purpose, because they describe something changing.
                """)
        }
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct HeldAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw HeldAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
