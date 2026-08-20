// EveryDeliberateResettleFlushesTheWindowTests.swift
// Echoel — #651: two of the four exposure transitions handed the window a photometric seam.
//
// WHAT THIS GUARDS. Exposure is handed back to auto at FIVE places. Four of them CONTINUE the
// take — saturation, weak periodicity on a bright lock, finger loss, and the stall path in
// `handleCameraSessionReset()` — and the fifth is teardown, which is exempt for a measured
// reason: `startPulseDetection()` calls `resetPulseState()`, so the window is emptied on the
// way IN and a take that ends cannot hand a seam to the next one.
// ⛔ THE FIRST DRAFT SAID FOUR AND ASSERTED THE FLAT UNIVERSAL. The driver found five sites and
// the guard was RED ON ITS OWN CORRECT TREE. Recorded rather than quietly patched, because the
// shape recurs: I wrote the universal from the branches I had just edited, not from a count. Every one of them changes the transfer function between light
// and the red channel, so every sample taken before it is measured on a different scale from
// every sample after. An autocorrelation over a window straddling that seam cannot find a
// pulse — the AC component it looks for is buried under a DC step.
//
// ⭐ THIS FILE ARGUES FROM THE REPO'S OWN HISTORY, NOT FROM THEORY. Two of the four already
// flushed, and both say why at their call site: "the pre-loss SATURATED samples + the
// exposure-unlock brightness STEP in the window … amp froze and conf stayed 0.00 for the whole
// window" (finger loss) and "the post-stall window kept the pre-stall samples + the brightness
// STEP the exposure re-lock injects, freezing amp=0.3618 / conf=0.00" (stall). Each cites a
// device log. The two DELIBERATE re-settles were the two that did not flush.
//
// MEASURED on the founder's device log, build 2531, 2026-08-20 — the same signature, digit for
// digit: confidence had just reached **0.89 at a stable 52–53 bpm** when the saturation branch
// fired. One sample later `amp` jumped to **0.4898 and froze there across two consecutive
// reads**, `acf` fell 0.40 → 0.05, `conf` went 0.89 → 0.07 → 0.00, and `win` stayed **150** —
// a full window that was never emptied. Both `generate` lines of that take report `body=0`.
// The take was seconds from locking when the recovery it asked for poisoned it.
//
// ⚠️ WHAT THIS DOES **NOT** FIX, stated because the fix is partial by choice. The flush happens
// at the UNLOCK, matching the two sibling sites. The AGC then ramps for ~3 s before the next
// lock (measured in that log: unlock 13:44:05, lock 13:44:08) and those ramp samples enter the
// fresh window. Flushing at the LOCK would be photometrically cleaner — but that path is shared
// with the FIRST lock of a take, and first acquisition demonstrably works (it reached 0.89).
// Trading a measured bug for an unmeasured one is not an improvement. Registered, not hidden.
//
// KIND (§1): SOURCE-TEXT SCAN. `manageExposure()` is private, needs a live `AVCaptureSession`,
// a torch and a finger; nothing here can drive it. What is checkable is that no branch which
// calls `unlockExposure()` returns without flushing. **DEVICE PROBE, open:** that the pulse now
// re-acquires after a "Too bright" event is the founder's next take.
//
// GRADING (#433 / §3), DRIVEN in Python against the parent (ba828ac), both trees, raw and
// stripped:
// **7 scan verdicts: 3 REGRESSIONS, 4 COUNTERWEIGHTS.** Driven, and three of these bullets
// say the opposite of what I first wrote — the corrections are kept, not tidied away.
//   · **REGRESSION — claim 1's per-site check.** On the parent 2 of the 5 `unlockExposure()`
//     sites reach neither a flush nor a teardown; here 0 do. Unsafe sites 2 → 0.
//   · **REGRESSION — claim 2.** `analyzer.resetForRecovery()` occurs 3× on the parent and 5×
//     here. Pinned as a FLOOR, never an equality (#364): a sixth transition that needs a flush
//     must be free to add one without reddening this file.
//   · **REGRESSION — claim 4**, and I had it down as a counterweight. On the parent the weak
//     branch does not flush AT ALL, so "the breadcrumb is composed before the flush" has no
//     flush to be before. It only became a real ordering question when #651 added one. Booking
//     it as a counterweight would have been the flattering direction §3 names.
//   · **COUNTERWEIGHTS — claim 1's site floor, claims 3a and 3b, claim 4b.** Green on both
//     trees, and they are what makes flushing safe at all: five sites exist to be checked;
//     `resetForRecovery()` keeps its `isPulseDetecting` guard; `displayBPM` stays held by the
//     publish loop across the refill, so the SHOWN pulse does not snap to zero; and no flush
//     creeps in ahead of the weak breadcrumb.
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED **TRAGEND — 1 of 14 verdicts
// flips** (7 claims × 2 trees), and it is the FIRST load-bearing one in five slices. It flips
// in the DANGEROUS direction: on the parent, raw text counts 5 `analyzer.resetForRecovery()`
// because two of them are inside comments, so an unstripped claim 2 would have PASSED there —
// the guard would have looked like a non-regression and the whole slice like a no-op. Stripped
// counts the real 3. ⛔ I had written "PROPHYLAKTISCH, 0 of 6" before running the driver, with
// the four-slice retraction streak quoted directly above it. Writing the retraction is not the
// same as waiting for the number.
//
// ⚠️ #364: flushing at the LOCK instead, or flushing at both boundaries, would satisfy this law
// better and turn claim 1 green by a different route — that is a rewrite of this file, not a
// violation. What is forbidden silently is a branch that hands exposure back to auto and leaves
// the old regime's samples in the window.

import Foundation
import XCTest
@testable import Echoelmusic

final class EveryDeliberateResettleFlushesTheWindowTests: XCTestCase {

    private static let publisher = "Echoelmusic/Bio/CameraRPPGBioPublisher.swift"

    /// 1 — REGRESSION, and the universal the whole slice is about: **no** branch may unlock
    /// exposure without flushing.
    ///
    /// ⚠️ NOT A LIST OF THE FOUR SITES. The comment this slice had to repair failed on its
    /// fifth attempt precisely because it enumerated a set that then grew. The scan walks every
    /// `unlockExposure()` and asks the same question of each, so a fifth transition is covered
    /// the day it is written.
    func testNoBranchHandsExposureBackWithoutFlushing() throws {
        let code = try Self.codeText(Self.publisher)
        let sites = Self.lineNumbers(of: "capture.unlockExposure()", in: code)
        XCTAssertGreaterThanOrEqual(sites.count, 5, """
            Only \(sites.count) `unlockExposure()` sites found — there were FIVE when #651 was \
            written: four transitions that CONTINUE the take (saturation · weak periodicity · \
            finger loss · stall) plus the teardown. A short read makes the per-site check below \
            vacuous (#454), so this floor comes first.
            """)
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var unflushed: [Int] = []
        for site in sites where !Self.flushesNearby(site, in: lines) { unflushed.append(site) }
        XCTAssertTrue(unflushed.isEmpty, """
            \(unflushed.count) branch(es) hand exposure back to auto without flushing the \
            analysis window, at line(s) \(unflushed.map(String.init).joined(separator: ", ")). \
            Every sample taken before an exposure change is measured on a different scale from \
            every sample after it; an autocorrelation across that seam finds no pulse. Two \
            sibling branches already flush and each cites the device log that taught it. On \
            build 2531 the un-flushed saturation branch took a take from conf 0.89 at a stable \
            52–53 bpm to conf 0.00 with amp frozen at 0.4898 and a full 150-sample window.
            """)
    }

    /// 2 — REGRESSION. A floor, never an equality (#364).
    func testTheFlushCountIsAFloorNotASet() throws {
        let code = try Self.codeText(Self.publisher)
        let flushes = Self.lineNumbers(of: "analyzer.resetForRecovery()", in: code).count
        XCTAssertGreaterThanOrEqual(flushes, 5, """
            Only \(flushes) `analyzer.resetForRecovery()` call sites; #651 left five (four in \
            `manageExposure()`, one in `handleCameraSessionReset()`). Removing one is a real \
            decision — say which transition stopped needing a clean window and why — not a \
            tidy-up. ADDING one is expected and must never redden this, which is why the \
            assertion is a floor: the comment this slice repaired failed on its fifth attempt \
            by enumerating a set that grew.
            """)
    }

    /// 3 — COUNTERWEIGHT, green on both trees. The contract that makes flushing safe.
    func testTheFlushKeepsItsGuardAndTheShownPulseIsHeld() throws {
        let analyzer = try Self.codeText("Echoelmusic/Video/CameraAnalyzer.swift")
        guard let body = Self.body(of: "func resetForRecovery", in: analyzer) else {
            return XCTFail("`resetForRecovery` is no longer declared — re-anchor (#454).")
        }
        XCTAssertTrue(body.contains("isPulseDetecting"), """
            `resetForRecovery()` lost its `isPulseDetecting` guard. #651 added two more callers \
            on the exposure path; without the guard they would clear pulse state on a take that \
            is not measuring one.
            """)
        let code = try Self.codeText(Self.publisher)
        XCTAssertTrue(code.contains("displayBPM"), """
            `displayBPM` is gone from the publisher. It is what holds the SHOWN pulse across a \
            refill — every flush site names that contract, and five of them now depend on it. \
            Without it each flush would snap the reading to zero and the cure would read worse \
            than the disease.
            """)
    }

    /// 4 — COUNTERWEIGHT, green on both trees. Breadcrumb the state you flush BECAUSE of.
    func testTheWeakBranchLogsBeforeItFlushes() throws {
        let code = try Self.codeText(Self.publisher)
        guard let range = code.range(of: "weak periodicity on a bright lock") else {
            return XCTFail("the weak-periodicity breadcrumb is gone — re-anchor (#454).")
        }
        let before = String(code[..<range.lowerBound].suffix(600))
        let after = String(code[range.upperBound...].prefix(600))
        XCTAssertTrue(after.contains("analyzer.resetForRecovery()"), """
            The weak-periodicity branch composes its breadcrumb AFTER flushing (or no longer \
            flushes). `resetForRecovery()` zeroes `lastAutoStrength` and the confidence, so a \
            line built afterwards prints "acf=0.00 conf=0.00" on every single re-lock and the \
            log can never show which weak state caused it. The dead-window flush a few lines up \
            had to learn this once already and says so at its own call site.
            """)
        XCTAssertFalse(before.contains("analyzer.resetForRecovery()"), """
            A flush now sits between the weak branch's entry and its breadcrumb. Same failure as \
            above, seen from the other side.
            """)
    }

    // MARK: - helpers

    /// A flush belonging to the same branch as the unlock at `line`.
    ///
    /// ⚠️ A WINDOW, AND ITS SIZE IS ARGUED. The four branches are short (the longest is nine
    /// statements) but each carries a long comment, and `SourceText.codeOnly` preserves line
    /// count — so a *line* window would be unsound by construction (#408) exactly as the
    /// `.prefix(400)` character window in #650's guard was. This one counts CODE lines only,
    /// skipping the blanks the stripper leaves behind, and stops at the branch's closing brace.
    private static func flushesNearby(_ line: Int, in lines: [String]) -> Bool {
        var depth = 0
        var seenBrace = false
        var i = line - 1
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            depth += t.filter { $0 == "{" }.count
            let closes = t.filter { $0 == "}" }.count
            if t.contains("analyzer.resetForRecovery()") { return true }
            // ⛔ THE TEARDOWN SITE, AND WITHOUT THIS THE GUARD WAS RED ON CORRECT WORK. The
            // first draft asserted the flat universal "no branch may unlock without flushing"
            // and I wrote "the four transitions" in the header — the driver found FIVE
            // `unlockExposure()` sites, and the fifth is the stop path
            // (`setTorch(false)` → unlock → `capture.stop()` → `stopPulseDetection()`).
            // ⭐ The exemption is PRINCIPLED, not a hole punched to make a red test green, and
            // the difference is one measurement: `stopPulseDetection()` only clears a flag, but
            // `startPulseDetection()` calls `resetPulseState()`, which empties every buffer.
            // The window is cleared on the way IN, so a take that ENDS cannot hand a seam to
            // the next one. A re-settle continues the take; teardown does not.
            if t.contains("analyzer.stopPulseDetection()") { return true }
            if closes > 0 {
                seenBrace = true
                depth -= closes
                if depth <= 0 && seenBrace { return false }
            }
            i += 1
        }
        return false
    }

    private static func lineNumbers(of needle: String, in code: String) -> [Int] {
        code.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .filter { $0.element.contains(needle) }
            .map { $0.offset + 1 }
    }

    private static func body(of key: String, in text: String) -> String? {
        guard text.components(separatedBy: key).count - 1 == 1,
              let start = text.range(of: key),
              let open = text[start.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var out = ""
        var i = open
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return out }
            }
            out.append(c)
            i = text.index(after: i)
        }
        return nil
    }

    private static func codeText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent("Sources").appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            struct Missing: Error, CustomStringConvertible {
                let p: String
                var description: String { "Sources/\(p) is missing — re-anchor this scan (#454)." }
            }
            throw Missing(p: relative)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }
}
