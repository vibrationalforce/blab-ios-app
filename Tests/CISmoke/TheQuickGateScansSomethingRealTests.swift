// TheQuickGateScansSomethingRealTests.swift
// Echoel — #1035. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// WHAT THIS RECORDS. `scripts/build-guard.sh` is CI-wired twice — `ci.yml:78` and
// `pr-check.yml:87` both run it as `--quick`, which SKIPS stages 2 (SwiftLint) and 3
// (compile). So in CI this script is its Stage 1 pattern scan, and, until this commit,
// a Stage 4 that scanned five type names measured to occur ZERO times in `Sources/`:
// MonitorMode · TransitionType · TrackSend · TrackType · SourceFilter. The loop found
// nothing and then `pass "Type conflict scan complete"` printed UNCONDITIONALLY, outside
// the loop, with no reference to its result. Half of what CI executed here was a green
// light for an empty scan.
//
// ⭐ ITS PROSE HOME WAS ALREADY RETRACTED. CLAUDE.md deleted the "Type Conflict
// Resolution" section on 2026-07-25 — "every type this section named is GONE … Do not
// restore any of it". The executable copy was missed: the #456 pattern, a retraction that
// fixed one home and left the other running for six weeks.
//
// ⚠️ WHY DELETED, NOT REPAIRED. The invariant it claimed has a stronger enforcer: two
// top-level types with the same name in one module is a redeclaration ERROR, so the
// compiler already catches it. The prefixing convention belonged to the multi-target era;
// the AUv3 target went 2026-07-24. Repairing it would have meant re-implementing the
// compiler, badly, in grep.
//
// ⛔ THIS GUARD FORBIDS NOTHING (#364). A fourth stage may come back; claim 3 only asks
// that its number agrees with the denominator every header prints, so a stage added
// without renumbering is what goes red — not the stage itself. The deleted block's own
// comment names the check worth building instead (an `@Observable` class declaring its
// own `_foo`, which collides with the macro's backing store and which `--quick` mode
// cannot see because there is no compiler).
//
// ⚠️ WHY THIS FILE READS ITS TARGET RAW. `SourceText.codeOnly` is a SWIFT stripper; in
// bash the comment character is `#`. BOTH of claim 2's needles are therefore LINE-ANCHORED
// (`^CONFLICT_TYPES=`, `^pass "Type conflict…`), which the retraction comment quoting the
// old code cannot satisfy — the `#` comes first. ⛔ The first draft anchored only the
// FIRST one and was red on its own commit: the retraction I had just written into
// `build-guard.sh` quotes the pass line verbatim, so the guard found its own epitaph and
// called it a regression. Caught by the Python transcription, not by reading.
//
// ⚠️ HONEST LIMITS. This proves what the script SAYS. It does not run it, and it says
// nothing about whether Stage 1's six checks are the right six — only that they still
// exist, so the gate was not hollowed out by the deletion.
//
// ⭐ GRADING (§3). Transcribed in Python against both trees. Claim 2 is the only FORWARD
// one — red at the parent, where `CONFLICT_TYPES=` and the unconditional pass both stand.
// ⛔ The first draft also called claim 3 forward, and the transcription said otherwise:
// at the parent the headers read 1..4 of 4, which is INTERNALLY consistent. That is the
// whole point of the finding — the ghost stage was numbered, so nothing looked short.
// Claim 3 is a counterweight that would have stayed green through the defect and goes red
// only on a FUTURE mis-renumber; claims 1 and 4 are counterweights too (green at both).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheQuickGateScansSomethingRealTests: XCTestCase {

    private static let script = "scripts/build-guard.sh"

    // MARK: - 1: the anchor — CI really runs this, and in quick mode

    /// Without this, every claim below is a statement about a file nothing executes.
    func testCIRunsThisGuardInQuickMode() throws {
        for workflow in [".github/workflows/ci.yml", ".github/workflows/pr-check.yml"] {
            let yml = try rawFile(workflow)
            XCTAssertTrue(yml.contains("scripts/build-guard.sh --quick"), """
                \(workflow) no longer runs `build-guard.sh --quick`. If the gate was \
                rewired or dropped, re-anchor this file — its whole point is that these \
                checks are the ones CI actually executes.
                """)
        }
    }

    // MARK: - 2: the finding — no scan over names that do not exist

    /// ⭐ A loop over five absent identifiers followed by an unconditional `pass`.
    func testTheGhostTypeConflictScanStaysDeleted() throws {
        let sh = try rawFile(Self.script)
        XCTAssertNil(sh.range(of: #"(?m)^CONFLICT_TYPES="#, options: .regularExpression), """
            The `CONFLICT_TYPES=(...)` scan is back in \(Self.script). Before re-adding it, \
            measure whether the names exist: on 2026-09-06 all five occurred ZERO times in \
            `Sources/`, and the stage printed a pass regardless. If you have a REAL \
            duplicate-name rule to enforce, make the verdict depend on the loop's result \
            and say in the same commit which failure it has caught (the doctor rule).
            """)
        XCTAssertNil(sh.range(of: #"(?m)^pass "Type conflict scan complete""#,
                              options: .regularExpression), """
            The unconditional "scan complete" pass is back. A verdict that cannot go red \
            is not a check; it is a green light with a label on it.
            """)
    }

    // MARK: - 3: the stage count must match what the headers promise

    /// Self-maintaining: derives the denominator from the file, counts the numerators.
    func testEveryStageHeaderAgreesOnHowManyStagesThereAre() throws {
        let sh = try rawFile(Self.script)
        let pattern = #"header "(\d+)/(\d+)""#
        let re = try NSRegularExpression(pattern: pattern)
        let ns = sh as NSString
        let hits = re.matches(in: sh, range: NSRange(location: 0, length: ns.length))

        XCTAssertFalse(hits.isEmpty, """
            No `header "N/M"` calls found in \(Self.script). If the stage banners were \
            restyled, re-anchor this claim rather than letting it pass on an empty set.
            """)

        var denominators = Set<Int>()
        var numerators = Set<Int>()
        for h in hits {
            numerators.insert(Int(ns.substring(with: h.range(at: 1))) ?? -1)
            denominators.insert(Int(ns.substring(with: h.range(at: 2))) ?? -1)
        }

        XCTAssertEqual(denominators.count, 1, """
            The stage headers disagree about the total: \(denominators.sorted()). Every \
            banner must print the same denominator, or the run reads as if a stage went \
            missing halfway through.
            """)
        guard let total = denominators.first else { return }
        XCTAssertEqual(numerators.sorted(), Array(1...total), """
            The stage numbers are \(numerators.sorted()) but the headers promise \(total) \
            stages. A stage was added or removed without renumbering — that is exactly how \
            #1035's ghost stage stayed invisible: it was "4/4", so nothing looked short.
            """)
    }

    // MARK: - 4: the counterweight — the gate was not hollowed out

    /// Deleting a stage is only right if what remains still asserts something.
    func testStageOneStillCarriesRealChecks() throws {
        let sh = try rawFile(Self.script)
        let verdicts = ["pass \"", "fail \"", "warn \""]
            .map { needle in sh.components(separatedBy: needle).count - 1 }
            .reduce(0, +)
        XCTAssertGreaterThanOrEqual(verdicts, 8, """
            \(Self.script) is down to \(verdicts) verdict calls. #1035 removed a stage that \
            measured nothing; if the remaining checks are being removed too, the gate is \
            becoming decorative and CI is running it for nothing. Say so out loud rather \
            than letting it shrink quietly.
            """)
    }

    // MARK: - helpers

    private struct DiagAnchorMissing: Error { let reason: String }

    private func rawFile(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DiagAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or \
                moved. Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }
}
