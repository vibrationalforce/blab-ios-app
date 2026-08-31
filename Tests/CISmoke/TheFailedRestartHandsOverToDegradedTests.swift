// TheFailedRestartHandsOverToDegradedTests.swift
// Echoel — #611. A failed engine restart after a graph mutation is never silent.
//
// KIND (§1): SOURCE-TEXT SCAN throughout — `AudioEngine` needs a live AVAudioEngine and a
// device audio session, which no test bundle here can drive. This proves the handover code
// sits where it must; whether the second start actually succeeds on device, and whether
// AudioDegradedRow then reads well, are DEVICE PROBES, registered as open.
//
// ⛔ #905 — THIS PARAGRAPH IS THE ONE A SESSION READS FIRST, AND #904 LEFT IT DESCRIBING
// THE OLD ARITHMETIC. #904 moved two numbers and left FIVE sentences (plus a method name)
// saying "four" — §4's own defect, a guard green while every word around it is stale.
// Corrected below and at each site; nothing about the DEFECT CLASS changed, only the count
// and one verb: the monitor rollback STOPS, it does not pause (a stop since #823).
//
// WHY. The #610 ultracode sweep (mic-monitoring-sweep, 2026-08-15) found ONE defect class
// at four sites as it stood then: every graph mutation (`setInputMonitoring(true)`
// rollback, source-node attach, clip-player attach, warpable-player attach) took a running
// engine down, and each restart `catch` only LOGGED. A pause posts no configuration-change notification, so on a
// restart failure the watchdog never fired, `isRunning` stayed stale-true, the #605
// silence line (needs `!isRunning`) stayed hidden, AudioDegradedRow (needs `degraded`)
// stayed hidden — the WHOLE app went silent with no explanation, and on the monitor path
// the only visible line blamed microphone permission (the #601b refusal copy + the #610
// Settings button). Three sweep workers found the monitor instance independently.
//
// THE FIX pinned here: ONE helper (`restartOrDegrade(after:)`, #416 — one decision, one
// definition) that retries the start once and, if it throws again, writes the three
// fields the degraded machinery already owns (`isRunning = false`, `degraded = true`,
// `lastAudioError`) so AudioDegradedRow surfaces cause + retry. FIVE sites call it today —
// the four above plus `restoreEngineIfStranded`, added by #625b (`bae1672`); the log-only
// catch pattern is banned by needle.
//
// HONEST GRADING (§3), against parent dc7e434:
// · Claims 1–3 are FORWARD — `restartOrDegrade` is born with this commit. On the parent
//   they are red together by ANCHOR ABSENCE: ONE finding (#486).
// · Claim 3's second assertion (the old pattern is GONE) is a REGRESSION guard that is
//   green on the worktree and red on the parent for its named reason (#367): the parent
//   really contains three log-only catches.
// · Claim 4 is a COUNTERWEIGHT (#343) — green on both trees: the pause-before-mutate sites
//   are the premise that makes the helper load-bearing. It said "four" and is three since
//   #823 (`d0564d7`) turned the rollback's pause into a stop.
// · Stripper (§2): 8 needles counted raw vs. stripped on both trees. TWO differ at file
//   level (`masterEngine.start()` 9→7 raw→stripped on the parent, `isRunning = false`
//   8→6 on the worktree — comment copies elsewhere in the file), but 0 of the ASSERTION
//   verdicts flip, because those two needles are asserted only inside the brace-matched
//   helper body, which contains no comment copy — PROPHYLAKTISCH at the verdict level,
//   and the brace matcher is what makes it so. The remaining six needles are identical
//   raw vs. stripped on both trees.

import Foundation
import XCTest

final class TheFailedRestartHandsOverToDegradedTests: XCTestCase {

    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"

    // MARK: - claim 1 — the one helper exists and hands over honestly

    func testTheHelperDeclaresTheFullHandover() throws {
        let code = try source(Self.engine)
        let body = try braceMatchedBlock(after: "private func restartOrDegrade(after context: String)", in: code)
        XCTAssertTrue(body.contains("masterEngine.start()"), """
            `restartOrDegrade` no longer attempts the restart itself — every graph-\
            mutation site relies on it for the second start attempt on the restored graph.
            """)
        for needle in ["isRunning = false", "degraded = true", "lastAudioError ="] {
            XCTAssertTrue(body.contains(needle), """
                `restartOrDegrade` lost `\(needle)` from its failure branch. All three \
                writes are load-bearing: `isRunning = false` unhides the #605 silence \
                machinery, `degraded = true` mounts AudioDegradedRow (cause + retry), and \
                `lastAudioError` is the cause it renders. Without any one of them a failed \
                restart is silent again — the exact #611 defect.
                """)
        }
    }

    // MARK: - claim 2 — the monitor rollback goes through the helper

    func testTheMonitorRollbackRestartsOrDegrades() throws {
        let code = try source(Self.engine)
        // ⛔ #937 — THIS ANCHOR WAS DEAD FOR ELEVEN DAYS AND THIS TEST WAS RED ON A CORRECT
        // TREE THE WHOLE TIME. It read `"Input monitoring: engine restart failed"`. #650
        // (`3a54a08`, 2026-08-20) routed every monitoring outcome through `logMonitorOutcome`,
        // which OWNS the `"Input monitoring: "` prefix and prepends it, so the call site now
        // reads `logMonitorOutcome("engine restart failed (\(error))")` and the old literal
        // matches nothing. The BEHAVIOUR was never touched: `restartOrDegrade(after: "input
        // monitoring rollback")` still sits after the disconnects and before `return false`,
        // and claim 3's count of five call sites still holds.
        //
        // ⛔ AND THIS IS THE SECOND INSTANCE OF ONE EVENT. #655/#656 found the identical break
        // in `TheNotchIsSlewedAndMonitorOnlyTests`, re-anchored it, wrote the lesson into
        // `Tests/CISmoke/CLAUDE.md` and built `scripts/dead-needles.py` to catch the next one.
        // The fix went into ONE home; the same #650 broke TWO guards, and nobody grepped for
        // the second (#456 — prose and repairs move in EVERY home, not the one you are looking
        // at). ⚠️ `dead-needles.py` could not see this one either: its `XCTUnwrap` shape wants
        // an INLINE literal, and this needle was bound to a local `let` first. #937 taught it
        // to follow that binding — the instrument's blind spot is why eleven days passed.
        //
        // Anchored on the part that survived BOTH wordings, with uniqueness asserted rather
        // than assumed (#408): `grep -c "engine restart failed" AudioEngine.swift` = 1.
        let anchor = "engine restart failed"
        let start = try XCTUnwrap(code.range(of: anchor), "the monitor rollback catch lost its log anchor — re-anchor this scan").lowerBound
        let rest = String(code[start...])
        let ret = try XCTUnwrap(rest.range(of: "return false"), "the monitor rollback no longer returns false — re-judge this scan")
        let block = String(rest[..<ret.lowerBound])
        XCTAssertTrue(block.contains("restartOrDegrade(after:"), """
            The monitor-engage rollback no longer restarts the paused engine before \
            returning false. That was the sweep's worst CRITICAL: the toggle's failure \
            path stranded the WHOLE app silent (music included) while the refusal line \
            and the #610 Settings button blamed microphone permission. The rollback must \
            call `restartOrDegrade` AFTER disconnecting the monitor nodes and BEFORE \
            `return false`.
            """)
    }

    // MARK: - claim 3 — every call site, and the log-only catch is extinct

    func testEveryPauseSiteRoutesThroughTheHelper() throws {
        let code = try source(Self.engine)
        // ⛔ #904 — RAISED 4 → 5, AND THIS PIN HAD BEEN RED ON A CORRECT TREE. The fifth
        // caller is `restoreEngineIfStranded`, added by #625b (`bae1672`, 2026-08-19 — ⛔
        // #905: #904 credited "#631/#836b" here, and those two only EDITED the helper's
        // logging later; `git log -S 'func restoreEngineIfStranded'` returns one commit and
        // `git show bae1672^:…| grep -c` is 4 against `bae1672`'s 5). It is precisely what the
        // message below asks a new site to do: route through the helper. The code obeyed the
        // instruction; nobody raised the number. Found by `scripts/count-pins.py`, written
        // after #903 hit the identical shape in `AudioConfiguration.swift` — and NOT by CI,
        // because the pipeline reports `failure` on every push (#396), so a genuinely red
        // guard is indistinguishable from the host dying (§5).
        XCTAssertEqual(occurrences(of: "restartOrDegrade(after:", in: code), 5, """
            The helper's call-site count changed (expected 5: monitor rollback, source-\
            node attach, clip-player attach, warpable-player attach, and the stranded-\
            engine restore). If you ADDED a pause/mutate/restart site, route it through \
            `restartOrDegrade` and raise this count in the same commit. If you REMOVED one, \
            lower it. A site that restarts on its own re-opens the #611 silence.

            ⚠️ Claim 4's pause count is NOT this number: they differ by TWO. A new pause-\
            before-mutate site raises BOTH; a caller that does not pause raises only this \
            one. See claim 4's note.
            """)
        XCTAssertEqual(occurrences(of: "Failed to restart engine after", in: code), 0, """
            A log-only restart catch is back. That pattern IS the #611 defect: it leaves \
            the engine paused with `isRunning` stale-true and no visible explanation. \
            Route the restart through `restartOrDegrade(after:)` instead.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — the pause premise

    func testThePauseBeforeMutateSitesSurvive() throws {
        let code = try source(Self.engine)
        // ⛔ #904 — LOWERED 4 → 3, red on a correct tree for the same reason as claim 3 and
        // in the OPPOSITE direction. The monitor-rollback site stopped matching this needle
        // when #823 turned its pause into a STOP — the source says so itself, at the rollback
        // call: "the pause (a stop since #823) above was OURS".
        //
        // ⚠️ THE TWO NUMBERS ARE NOT THE SAME NUMBER — they are OFFSET BY TWO, and #904's
        // first wording over-corrected that into "do NOT assume claim 3's count moves with
        // it". Measured: the three pause sites are a strict SUBSET of the five helper
        // callers; the two extras are the monitor rollback (stops, never paused) and
        // `restoreEngineIfStranded` (never paused). So for the likeliest future edit — the
        // one this message itself describes, a new pause-before-mutate site — claim 3 MUST
        // move too, and a reader obeying the old wording literally raises this to 4, leaves
        // claim 3 at 5 and ships a red. Decoupling them was as wrong as equating them.
        XCTAssertEqual(occurrences(of: "if wasRunning { masterEngine.pause() }", in: code), 3, """
            The pause-before-mutate site count changed (expected 3: source-node attach, \
            clip-player attach, warpable-player attach). This is the premise that makes \
            `restartOrDegrade` load-bearing. If a site was added or removed, update this \
            count and make sure any NEW site's restart goes through the helper. These two \
            counts differ by TWO: a new pause-before-mutate site raises BOTH; a helper \
            caller that does not pause (the monitor rollback, the stranded-engine restore) \
            raises only claim 3's.
            """)
    }

    // MARK: - helpers

    private func occurrences(of needle: String, in haystack: String) -> Int {
        var count = 0
        var search = haystack.startIndex..<haystack.endIndex
        while let r = haystack.range(of: needle, range: search) {
            count += 1
            search = r.upperBound..<haystack.endIndex
        }
        return count
    }

    /// The brace-matched body following `anchor`'s first `{` — no fixed line window
    /// (this repo's comment blocks grow, and `SourceText.codeOnly` preserves lines).
    private func braceMatchedBlock(after anchor: String, in code: String) throws -> String {
        struct AnchorMissing: Error { let reason: String }
        guard let a = code.range(of: anchor) else {
            throw AnchorMissing(reason: "anchor `\(anchor)` not found — re-anchor this scan")
        }
        var depth = 0
        var begun = false
        var out = String.UnicodeScalarView()
        for ch in code[a.upperBound...].unicodeScalars {
            if ch == "{" { depth += 1; begun = true }
            if begun { out.append(ch) }
            if ch == "}" {
                depth -= 1
                if begun && depth == 0 { break }
            }
        }
        guard begun else {
            throw AnchorMissing(reason: "no block opened after `\(anchor)`")
        }
        return String(out)
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct AnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
