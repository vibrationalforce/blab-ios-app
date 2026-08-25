// EveryDeliberateResettleFlushesTheWindowTests.swift
// Echoel — #651: two exposure transitions handed the analysis window a photometric seam.
//          #652: the review pass that corrected the MECHANISM, budgeted the flush, and kept
//          the measured frame rate across it.
//
// WHAT THIS GUARDS. Exposure is handed back to auto at FIVE places. Four of them CONTINUE the
// take — saturation, weak periodicity on a bright lock, finger loss, and the stall path in
// `handleCameraSessionReset()` — and the fifth is teardown, which is exempt for a measured
// reason: `startPulseDetection()` calls `resetPulseState()`, so the window is emptied on the
// way IN and a take that ends cannot hand a seam to the next one. Claim 6c pins that premise;
// it used to be asserted in prose only, which is a hole that stays green (#343).
//
// ⛔ THE FIRST DRAFT SAID FOUR AND ASSERTED THE FLAT UNIVERSAL. The driver found five sites and
// the guard was RED ON ITS OWN CORRECT TREE. Recorded rather than quietly patched, because the
// shape recurs: I wrote the universal from the branches I had just edited, not from a count.
//
// ⛔ AND #651 NAMED THE WRONG MECHANISM, WHICH IN THIS REPO IS THE MORE EXPENSIVE HALF. It said
// "the AC component is buried under a DC step" and "an autocorrelation across that seam finds
// no pulse". Measured (#651 DSP review, re-derived here): the 0.7 Hz Butterworth highpass
// settles the DC step in ~1 s, so the DC is not what lasts. What lasts is the step's
// AMPLITUDE. The window's very next computation is `amplitude = maxAmp - minAmp`, a max/min
// pinned by ONE extreme sample for the window's whole ~10–12 s life; `CameraAnalyzer` gates on
// `isMotionAmplitude(amplitude)` = `amplitude > 0.20`, and that branch zeroes the peak count,
// multiplies `bpmConfidence` by `motionBleed` PER SAMPLE (0.6 while acf ≤ 0.4, ~15–30 samples
// per tick ⇒ ≈0 in one tick) and RETURNS before peak detection runs. Confidence dies from the
// amplitude gate alone. The autocorrelation collapse is a symptom riding alongside, not the
// cause. The FIX is unchanged — only a flush can clear a max/min-pinned window early — but a
// reader sent to `PulsePeriodEstimator` would have debugged the wrong file. CLAUDE.md twice:
// a correct note with a false reason is worse than no note.
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
// fired. One sample later `amp` jumped to **0.4898** — 20× a resting rPPG AC and 2.4× the 0.20
// gate — and froze there across two consecutive reads, `acf` fell 0.40 → 0.05, `conf` went
// 0.89 → 0.07 → 0.00, and `win` stayed **150**: a full window that was never emptied. Both
// `generate` lines of that take report `body=0`. The take was seconds from locking when the
// recovery it asked for poisoned it.
//
// ⚠️ WHAT #652 FIXED THAT #651 BROKE, and it is the reason this file grew two claims. The
// saturation branch has no cooldown of its own: 2 s of saturation to enter, it clears
// `fingerStableTicks` but not `fingerPresentTicks`, and it never increments `quickFailLocks`.
// A placement oscillating around the washout line can therefore re-settle every ~4–6 s while
// the window needs ~10–12 s to fill. An UNBUDGETED flush there pins `lastWindowSize` below
// `fullWindowSamples`; `weakTicksStep` returns 0 on its `windowFull` guard; `weakAcfTicks`
// never accumulates — and BOTH escalations become unreachable: `weakLockNeedsResettle` and
// `deadWindowNeedsFlush`, the last-resort recovery written for device log 2465's four dead
// minutes. #651 would have converted "dead with a recovery ladder" into "dead with the ladder
// gone". Claim 5 pins the gate. The weak branch deliberately gets NO such gate: it is already
// bounded by `maxWeakRelocks` AND its flush holds its own counter at zero through the refill.
//
// ⚠️ AND A HAZARD #651 NEWLY EXPOSED, which claim 6 now forbids. `resetPulseState()` used to
// re-arm the ONE-TIME frame-rate measurement. That measurement samples the first 30 samples
// after a reset (~2.5 s) and then latches for the rest of the take. #651's two flushes fire
// mid-take immediately after an exposure unlock — squarely inside the AGC ramp, the one
// stretch where the camera runs slowest. On the founder's log that depressed rate is 12.1 fps.
// A highpass designed for 12.1 Hz and then clocked at the recovered ~15 Hz puts its −3 dB
// corner at `0.7 × 15/12.1` = 0.8678 Hz = **52.07 bpm** — against a **52–53 bpm** pulse. The
// recovery would have attenuated the exact component it was hunting. #652 moved the re-arm
// into `CameraAnalyzer.rearmFrameRateAdaptation()`, called only where a genuinely FRESH
// capture format is possible.
//
// ⚠️ WHAT IS STILL **NOT** FIXED, stated because the fix is partial by choice. The flush
// happens at the UNLOCK, matching the two sibling sites. #651 called the residual "~3 s of AGC
// ramp"; measured, the re-lock is `lockExposure()` PLUS `setTorch(true)` — a second
// photometric STEP, not a ramp, and it lands AFTER the flush. If that step alone exceeds 0.20,
// the flush buys no recovery time on this path. Bounding it: the FIRST lock of a take injects
// the same step into an accumulating window and acquisition demonstrably works (it reached
// 0.89), so the lock step is the smaller of the two — but "smaller" is not "under 0.20".
// #652 therefore INSTRUMENTS instead of guessing: both re-settle breadcrumbs now carry `amp`
// and `win`, so the founder's next log settles the placement. Registered, not hidden.
//
// KIND (§1): SOURCE-TEXT SCAN. `manageExposure()` is private, needs a live `AVCaptureSession`,
// a torch and a finger; nothing here can drive it. What is checkable is that no branch which
// calls `unlockExposure()` returns without flushing, that the flush is budgeted, and that it
// does not re-arm the rate. **DEVICE PROBE, open:** that the pulse re-acquires after a "Too
// bright" event is the founder's next take.
//
// GRADING (#433 / §3), DRIVEN in Python against the parent (594917a), both trees, raw and
// stripped. Numbers written from the driver's output, after the run — #651's grading was wrong
// twice in this exact place (it booked a regression as a counterweight, and printed a stripper
// flip count of 1 that was 2).
// **14 scan verdicts: 3 REGRESSIONS, 11 COUNTERWEIGHTS.**
//   · REGRESSION — claim 5b. The saturation branch has no `fullWindowSamples` gate on the
//     parent; the flush there is unbudgeted and can starve the escalation ladder.
//   · REGRESSION — claim 6a2. `resetPulseState()` re-arms the rate on the parent.
//   · REGRESSION — claim 6b. `startPulseDetection()` does not re-arm on the parent, because
//     the re-arm did not exist as a separable step at all.
//   · COUNTERWEIGHTS — the other eleven, green on both trees: the five unlock sites and their
//     per-site flush, the flush-count floor, `resetForRecovery`'s `isPulseDetecting` guard,
//     the `displayBPM` declaration AND its hold branch, both halves of the weak-branch
//     ordering, the saturation branch still flushing at all, and `startPulseDetection` still
//     emptying the buffers.
//
// ⚠️ ONE OF THOSE ELEVEN IS VACUOUS ON THE PARENT AND SAYS SO AT ITS CALL SITE: claim 6a
// ("`resetForRecovery` contains no re-arm") is green on `594917a` only because the identifier
// did not exist there — the hazard lived one level down, in `resetPulseState()`. The driver is
// what exposed that; claim 6a2 is the version that actually fails on the buggy tree. A claim
// that cannot fail where the bug is looks exactly like a regression test and is not one.
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED **PROPHYLAKTISCH — 0 of 28
// verdicts flip** (14 claims × 2 trees). #651's stripper WAS load-bearing (2 of 14) because
// its claim 2 counted a bare identifier that also appeared in comments; every anchor here
// carries call context or a declaration prefix, which is narrower than any prose that quotes
// it. That is now the fifth measurement of the same lesson and the reason the prediction is
// no longer written before the run.
//
// ⚠️ #364: flushing at the LOCK instead, or flushing at BOTH boundaries behind a latch, would
// satisfy this law better and would change claims 1, 4 and 5 — that is a rewrite of this file,
// not a violation. What is forbidden silently is a branch that hands exposure back to auto and
// leaves the old regime's samples in the window, or a flush that fires often enough to starve
// the escalation ladder.

import Foundation
import XCTest
@testable import Echoelmusic

final class EveryDeliberateResettleFlushesTheWindowTests: XCTestCase {

    private static let publisher = "Echoelmusic/Bio/CameraRPPGBioPublisher.swift"
    private static let analyzerFile = "Echoelmusic/Video/CameraAnalyzer.swift"

    /// 1 — the universal the whole slice is about: **no** branch may unlock exposure without
    /// flushing.
    ///
    /// ⚠️ NOT A LIST OF THE FIVE SITES. The comment this slice had to repair failed on its
    /// fifth attempt precisely because it enumerated a set that then grew. The scan walks every
    /// `unlockExposure()` and asks the same question of each, so a sixth transition is covered
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
        let siteList = unflushed.map { String($0) }.joined(separator: ", ")
        XCTAssertTrue(unflushed.isEmpty, """
            \(unflushed.count) branch(es) hand exposure back to auto without flushing the \
            analysis window, at line(s) \(siteList). Every sample taken before an exposure change \
            is measured on a different scale from every sample after it; the step's AMPLITUDE \
            then pins `maxAmp - minAmp` above the 0.20 motion gate for the window's whole life \
            and bleeds confidence to zero per sample. Two sibling branches already flush and \
            each cites the device log that taught it. On build 2531 the un-flushed saturation \
            branch took a take from conf 0.89 at a stable 52–53 bpm to conf 0.00 with amp \
            frozen at 0.4898 and a full 150-sample window.
            """)
    }

    /// 2 — a floor, never an equality (#364).
    func testTheFlushCountIsAFloorNotASet() throws {
        let code = try Self.codeText(Self.publisher)
        let flushes = Self.lineNumbers(of: "analyzer.resetForRecovery(keepEstimate:", in: code).count
        XCTAssertGreaterThanOrEqual(flushes, 5, """
            Only \(flushes) `analyzer.resetForRecovery(keepEstimate:)` call sites; #651 left five (four in \
            `manageExposure()`, one in `handleCameraSessionReset()`). Removing one is a real \
            decision — say which transition stopped needing a clean window and why — not a \
            tidy-up. ADDING one is expected and must never redden this, which is why the \
            assertion is a floor. This scan runs on COMMENT-STRIPPED text, which is why it is \
            the authority the publisher's prose now points at instead of a `grep` recipe: two \
            different recipes there printed two different wrong numbers, each falsified by the \
            ordinary act of writing comments about the very sites they counted.
            """)
    }

    /// 3 — the contract that makes flushing safe at all.
    func testTheFlushKeepsItsGuardAndTheShownPulseIsHeld() throws {
        let analyzer = try Self.codeText(Self.analyzerFile)
        guard let body = Self.body(of: "func resetForRecovery", in: analyzer) else {
            return XCTFail("`resetForRecovery` is no longer declared — re-anchor (#454).")
        }
        XCTAssertTrue(body.contains("isPulseDetecting"), """
            `resetForRecovery()` lost its `isPulseDetecting` guard. #651 added two more callers \
            on the exposure path; without the guard they would clear pulse state on a take that \
            is not measuring one.
            """)
        let code = try Self.codeText(Self.publisher)
        // ⛔ #652: this used to be `code.contains("displayBPM")`. That identifier occurs ten
        // times in the publisher, and the HOLD contract — the thing the message describes —
        // can be destroyed with every one of them intact. An assertion that cannot fail for
        // the reason its message gives is #367 in the mirror. Anchored on the declaration AND
        // on the branch that implements the hold.
        XCTAssertTrue(code.contains("public private(set) var displayBPM"), """
            `displayBPM` is no longer the publisher's own published reading. It is what holds \
            the SHOWN pulse across a refill, and five flush sites depend on that contract.
            """)
        XCTAssertTrue(code.contains("if self.displayBPM == 0 {"), """
            The `displayBPM` hold branch is gone. It is assigned ONLY from a confident reading \
            — first one adopted as-is, later ones EMA-smoothed and slew-capped — so a flushed \
            window cannot move it: four sites publish bpm=0 after their flush, and the #834 \
            keep site retains bpm but zeroes acf, which fails the same trust conjunct. Without \
            that branch each flush would snap the shown reading to zero and the cure would \
            read worse than the disease.
            """)
    }

    /// 4 — breadcrumb the state you flush BECAUSE of, not the zeroes the flush leaves behind.
    func testTheWeakBranchLogsBeforeItFlushes() throws {
        let code = try Self.codeText(Self.publisher)
        guard let range = code.range(of: "weak periodicity on a bright lock") else {
            return XCTFail("the weak-periodicity breadcrumb is gone — re-anchor (#454).")
        }
        // ⛔ #652 — THIS WAS TEN CHARACTERS FROM LYING, AND BOTH REVIEWERS MEASURED IT. The
        // previous form was `code[..<range.lowerBound].suffix(600)`. Driven on stripped text:
        // the nearest preceding `analyzer.resetForRecovery()` is the DEAD-WINDOW flush — a
        // different branch entirely — and it starts 610 characters before the anchor. Deleting
        // 10 characters of code anywhere between them would have pulled it inside the window
        // and reddened a correct tree with the message "a flush now sits between the weak
        // branch's entry and its breadcrumb", which would have been false. (Note the direction:
        // ADDING code moves the anchor and the window together and is safe. Both review reports
        // illustrated it with an insertion; the driver says deletion. The number was right in
        // both, the example was not — measured here rather than repeated.) This file's own
        // helper lectures about exactly this (#408, and #650's `.prefix(400)`), twenty lines
        // below where the window sat. Bounded at the BRANCH ENTRY now: exact, and it cannot
        // drift in either direction.
        guard let entry = code.range(of: "if Self.weakLockNeedsResettle("),
              entry.lowerBound < range.lowerBound else {
            return XCTFail("""
                The weak branch no longer opens with `if Self.weakLockNeedsResettle(` before its \
                breadcrumb — re-anchor claim 4 (#454). Do NOT restore a character window.
                """)
        }
        let before = String(code[entry.lowerBound..<range.lowerBound])
        let after = String(code[range.upperBound...].prefix(600))
        XCTAssertTrue(after.contains("analyzer.resetForRecovery(keepEstimate:"), """
            The weak-periodicity branch composes its breadcrumb AFTER flushing (or no longer \
            flushes). `resetForRecovery()` zeroes `lastAutoStrength`, `lastFilteredAmplitude`, \
            `lastWindowSize` and the confidence, so a line built afterwards prints \
            "acf=0.00 conf=0.00 amp=0.0000 win=0" on every single re-lock and the log can never \
            show which weak state caused it. The dead-window flush a few lines up had to learn \
            this once already and says so at its own call site.
            """)
        XCTAssertFalse(before.contains("analyzer.resetForRecovery(keepEstimate:"), """
            A flush now sits between the weak branch's ENTRY and its breadcrumb — the window is \
            the branch itself, so this can only be a flush that really belongs to it. Same \
            failure as above, seen from the other side.
            """)
    }

    /// 5 — #652. The saturation flush must be BUDGETED, or it starves the escalation ladder.
    func testTheSaturationFlushIsBudgeted() throws {
        let code = try Self.codeText(Self.publisher)
        guard let branch = Self.body(of: "if saturatedTicks >= Self.resettleAfterTicks",
                                     in: code) else {
            return XCTFail("""
                The saturation re-settle branch is no longer anchored by \
                `if saturatedTicks >= Self.resettleAfterTicks` — re-anchor claim 5 (#454). An \
                extraction that returns nothing makes the assertions below vacuously green.
                """)
        }
        XCTAssertTrue(branch.contains("analyzer.resetForRecovery(keepEstimate:"), """
            The saturation re-settle stopped flushing the analysis window. That is the #651 bug \
            itself: on build 2531 it took a take from conf 0.89 to conf 0.00 with amp frozen at \
            0.4898 across a full 150-sample window.
            """)
        XCTAssertTrue(branch.contains("fullWindowSamples"), """
            The saturation flush is UNBUDGETED again. This branch has no cooldown of its own — \
            2 s of saturation to enter, `fingerPresentTicks` untouched, `quickFailLocks` never \
            incremented — so an oscillating placement can re-settle every ~4–6 s against a \
            window that needs ~10–12 s to fill. Flushing every time pins `lastWindowSize` below \
            `fullWindowSamples`, `weakTicksStep` returns 0 on its `windowFull` guard, \
            `weakAcfTicks` never accumulates, and BOTH escalations become unreachable: \
            `weakLockNeedsResettle` AND `deadWindowNeedsFlush` — the last-resort recovery \
            written for device log 2465's four dead minutes. Flushing a window that is already \
            short costs a refill for no gain, so the gate is free. If you replace it with a \
            different limiter (a per-placement budget like `maxWeakRelocks`), say so here — \
            #364, the law is "budgeted", not "this expression".
            """)
    }

    /// 6 — #652. A mid-take flush must NOT re-measure the camera's frame rate, and the
    /// teardown exemption's premise must be pinned rather than merely asserted in prose.
    func testAMidTakeFlushKeepsTheMeasuredFrameRate() throws {
        let analyzer = try Self.codeText(Self.analyzerFile)
        guard let recovery = Self.body(of: "func resetForRecovery", in: analyzer),
              let start = Self.body(of: "func startPulseDetection", in: analyzer),
              let plain = Self.body(of: "private func resetPulseState", in: analyzer) else {
            return XCTFail("""
                `resetForRecovery` / `startPulseDetection` / `resetPulseState` are no longer \
                uniquely declared in `CameraAnalyzer` — re-anchor claim 6 (#454).
                """)
        }
        // ⛔ #652 — THE DRIVER CAUGHT THIS ONE, AND IT IS THE WHOLE REASON GRADING IS RUN AND
        // NOT ESTIMATED. The assertion below (`recovery` has no re-arm) is **vacuously green
        // on the parent**: on `594917a` the identifier `rearmFrameRateAdaptation` does not
        // exist at all, and the hazard lived one level DOWN, inside `resetPulseState()`. A
        // claim that cannot fail on the tree that has the bug is not a regression test — it is
        // decoration that reads like one (#454). The transitive assertion is the load-bearing
        // half: whatever `resetForRecovery` delegates to must not touch the rate either.
        XCTAssertFalse(plain.contains("filterRateAdapted"), """
            `resetPulseState()` re-arms the frame-rate measurement again — and this is where \
            the #651 hazard actually lived, which is why the direct check below could not see \
            it. Every flush goes through here. Re-measuring the rate during an AGC ramp latched \
            a 12.1 fps design that puts the highpass corner at 52.07 bpm against the founder's \
            52–53 bpm pulse. The re-arm belongs in `rearmFrameRateAdaptation()`, called only \
            where a genuinely fresh capture format is possible.
            """)
        XCTAssertFalse(recovery.contains("rearmFrameRateAdaptation"), """
            A mid-take flush re-arms the one-time frame-rate measurement again. That \
            measurement samples the first 30 samples AFTER the reset (~2.5 s) and then latches \
            for the rest of the take — and #651's flushes fire immediately after an exposure \
            unlock, i.e. inside the AGC ramp, the one stretch where the camera runs slowest. On \
            the founder's build-2531 log that depressed rate is 12.1 fps; a highpass designed \
            for 12.1 Hz and then clocked at the recovered ~15 Hz puts its −3 dB corner at \
            0.7 × 15/12.1 = 0.8678 Hz = 52.07 bpm, against a 52–53 bpm pulse. The recovery \
            would attenuate the exact component it is hunting. A flush empties the window; it \
            does not change the camera's format, so the measured rate still holds.
            """)
        XCTAssertTrue(start.contains("rearmFrameRateAdaptation"), """
            `startPulseDetection()` no longer re-arms the frame-rate measurement. A fresh \
            session CAN deliver a different capture format, so this is one of the two places \
            that must — otherwise the filter keeps a rate measured on a previous session.
            """)
        XCTAssertTrue(start.contains("resetPulseState"), """
            `startPulseDetection()` no longer empties the pulse buffers. This is the PREMISE of \
            the teardown exemption in `flushesNearby` below: the stop path unlocks exposure \
            without flushing, and that is only safe because the window is cleared on the way IN. \
            Without this call the exemption becomes a silent hole that stays green (#343).
            """)
    }

    // MARK: - helpers

    /// A flush belonging to the same branch as the unlock at `line`.
    ///
    /// ⚠️ A WINDOW, AND ITS SIZE IS ARGUED. The branches are short but each carries a long
    /// comment, and `SourceText.codeOnly` preserves line count — so a *line* window would be
    /// unsound by construction (#408) exactly as the `.prefix(400)` character window in #650's
    /// guard was. This one walks braces and stops at the branch's closing brace.
    ///
    /// ⚠️ KNOWN AND ACCEPTED EDGES, both in the conservative direction (#651 code review):
    /// a nested `{ }` inserted BETWEEN an unlock and its flush closes depth early and reddens
    /// correct work; and the walk only looks FORWARD, so moving a flush to just BEFORE its
    /// `unlockExposure()` in the same branch also reddens. Neither can produce a false PASS on
    /// a branch that truly never flushes, which is the failure this file exists to catch.
    private static func flushesNearby(_ line: Int, in lines: [String]) -> Bool {
        var depth = 0
        var i = line - 1
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            depth += t.filter { $0 == "{" }.count
            let closes = t.filter { $0 == "}" }.count
            if t.contains("analyzer.resetForRecovery(keepEstimate:") { return true }
            // ⛔ THE TEARDOWN SITE, AND WITHOUT THIS THE GUARD WAS RED ON CORRECT WORK. The
            // first draft asserted the flat universal "no branch may unlock without flushing"
            // and I wrote "the four transitions" in the header — the driver found FIVE
            // `unlockExposure()` sites, and the fifth is the stop path
            // (`setTorch(false)` → unlock → `capture.stop()` → `stopPulseDetection()`).
            // ⭐ The exemption is PRINCIPLED, not a hole punched to make a red test green, and
            // the difference is one measurement: `stopPulseDetection()` only clears a flag, but
            // `startPulseDetection()` calls `resetPulseState()`, which empties every buffer.
            // The window is cleared on the way IN, so a take that ENDS cannot hand a seam to
            // the next one. A re-settle continues the take; teardown does not. Claim 6c pins
            // that premise — in the first version it lived only in this comment.
            if t.contains("analyzer.stopPulseDetection()") { return true }
            if closes > 0 {
                depth -= closes
                // ⛔ #652 removed a `seenBrace` flag that was tested only inside the block that
                // set it, so `depth <= 0 && seenBrace` was exactly `depth <= 0`. Dead logic in
                // a guard reads as a condition someone reasoned about.
                if depth <= 0 { return false }
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
