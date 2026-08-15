// TheFailedRestartHandsOverToDegradedTests.swift
// Echoel — #611. A failed engine restart after a graph mutation is never silent.
//
// KIND (§1): SOURCE-TEXT SCAN throughout — `AudioEngine` needs a live AVAudioEngine and a
// device audio session, which no test bundle here can drive. This proves the handover code
// sits where it must; whether the second start actually succeeds on device, and whether
// AudioDegradedRow then reads well, are DEVICE PROBES, registered as open.
//
// WHY. The #610 ultracode sweep (mic-monitoring-sweep, 2026-08-15) found ONE defect class
// at FOUR sites: every graph mutation (`setInputMonitoring(true)` rollback, source-node
// attach, clip-player attach, warpable-player attach) pauses a running engine, and each
// restart `catch` only LOGGED. A pause posts no configuration-change notification, so on a
// restart failure the watchdog never fired, `isRunning` stayed stale-true, the #605
// silence line (needs `!isRunning`) stayed hidden, AudioDegradedRow (needs `degraded`)
// stayed hidden — the WHOLE app went silent with no explanation, and on the monitor path
// the only visible line blamed microphone permission (the #601b refusal copy + the #610
// Settings button). Three sweep workers found the monitor instance independently.
//
// THE FIX pinned here: ONE helper (`restartOrDegrade(after:)`, #416 — one decision, one
// definition) that retries the start once and, if it throws again, writes the three
// fields the degraded machinery already owns (`isRunning = false`, `degraded = true`,
// `lastAudioError`) so AudioDegradedRow surfaces cause + retry. All four sites call it;
// the log-only catch pattern is banned by needle.
//
// HONEST GRADING (§3), against parent dc7e434:
// · Claims 1–3 are FORWARD — `restartOrDegrade` is born with this commit. On the parent
//   they are red together by ANCHOR ABSENCE: ONE finding (#486).
// · Claim 3's second assertion (the old pattern is GONE) is a REGRESSION guard that is
//   green on the worktree and red on the parent for its named reason (#367): the parent
//   really contains three log-only catches.
// · Claim 4 is a COUNTERWEIGHT (#343) — green on both trees: the four pause sites are the
//   premise that makes the helper load-bearing.
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
            `restartOrDegrade` no longer attempts the restart itself — the four graph-\
            mutation sites rely on it for the second start attempt on the restored graph.
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
        let anchor = "Input monitoring: engine restart failed"
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

    // MARK: - claim 3 — all four sites, and the log-only catch is extinct

    func testEveryPauseSiteRoutesThroughTheHelper() throws {
        let code = try source(Self.engine)
        XCTAssertEqual(occurrences(of: "restartOrDegrade(after:", in: code), 4, """
            The helper's call-site count changed (expected 4: monitor rollback, source-\
            node attach, clip-player attach, warpable-player attach). If you ADDED a \
            pause/mutate/restart site, route it through `restartOrDegrade` and raise this \
            count together with claim 4's in the same commit. If you REMOVED one, lower \
            both. A site that restarts on its own re-opens the #611 silence.
            """)
        XCTAssertEqual(occurrences(of: "Failed to restart engine after", in: code), 0, """
            A log-only restart catch is back. That pattern IS the #611 defect: it leaves \
            the engine paused with `isRunning` stale-true and no visible explanation. \
            Route the restart through `restartOrDegrade(after:)` instead.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — the pause premise

    func testTheFourPauseSitesSurvive() throws {
        let code = try source(Self.engine)
        XCTAssertEqual(occurrences(of: "if wasRunning { masterEngine.pause() }", in: code), 4, """
            The pause-before-mutate site count changed (expected 4). This is the premise \
            that makes `restartOrDegrade` load-bearing — if a site was added or removed, \
            update claim 3's count and this one in the same commit, and make sure any NEW \
            site's restart goes through the helper.
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
