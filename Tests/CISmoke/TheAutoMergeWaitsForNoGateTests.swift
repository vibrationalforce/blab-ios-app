// TheAutoMergeWaitsForNoGateTests.swift
// Echoel — #683. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// WHAT THIS RECORDS. `auto-merge-claude.yml` decides what reaches `main`, and it was
// missing from CLAUDE.md's "Active Workflows" table entirely — the register gap this repo
// calls more expensive than a wrong number, because it never surfaces as a question.
// Measured 2026-08-21: the workflow fires on `push` to `claude/**` and merges immediately.
// It has NO `needs:`, NO `workflow_run` trigger and reads no other workflow's conclusion,
// so it CANNOT wait for `Xcode Compile Check` or `CI/CD Pipeline` — the three run in
// parallel and the merge wins.
//
// ⭐ IT IS NOT A HYPOTHESIS. #681 failed `Xcode Compile Check` (run 32457537356,
// `f61be63`) and `git branch -r --contains f61be63` lists `origin/main` anyway. #682
// landed the fix ten minutes later, so `main` compiles today — but for those ten minutes
// it did not, and nothing anywhere said that was possible.
//
// ⚠️ THE PROPORTION MATTERS, and claim 4 is why this file is a record and not an alarm:
// the TestFlight dispatch inside the same workflow is `if: false` (disabled 2026-06-16
// over Apple's upload quota). An ungated merge therefore reaches `main`, never a user.
// Deploy stays deliberate (`.deploy/release`). Delete claim 4 and this whole finding
// changes severity — that is exactly why it is pinned next to the others.
//
// ⛔ THIS GUARD FORBIDS NOTHING (#364). `.github/workflows/**` is founder-gated — report,
// do not edit — so the repair (adding a `workflow_run` gate, or requiring the checks on a
// protected `main`) is HIS call, not this file's. On the day he makes it, claims 2 and 3
// go red BY DESIGN, and their messages name the prose to pull along in the same commit
// (#456). A red here is then the good news, not a regression.
//
// ⚠️ WHY THIS FILE READS ITS TARGET RAW, alone in the bundle. `SourceText.codeOnly` is a
// SWIFT stripper: in YAML the comment character is `#`, and `//` appears inside URLs, so
// running it here would mangle the file rather than clean it. Adding a YAML stripper would
// break the one-stripper rule (#453). Instead every needle is LINE-ANCHORED (`^\s*needs:`),
// which a `#`-comment mention cannot satisfy because the `#` comes first. Verified: the
// file's four comment blocks contain none of these tokens anyway.
//
// ⚠️ HONEST LIMITS. 5 tests, 12 assertion statements (2+3+2+2+3; counted in Python over
// lines whose first token is XCTAssert). This file proves what the workflow SAYS, never
// what GitHub does with it — branch-protection rules live in repository settings, not in
// the tree, so a protected `main` could already be refusing these pushes and no test here
// would know. What is proven is that the workflow itself waits for nothing.
//
// ⭐ GRADING (§3). Needles transcribed in Python against both trees; the workflow file is
// untouched by this commit, so claims 1–4 are COUNTERWEIGHTS (green at the parent too, and
// that is the point — they record a standing state, they do not create it). Claim 5 is
// FORWARD: the CLAUDE.md table row is new here, red at the parent by one absence (#486).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheAutoMergeWaitsForNoGateTests: XCTestCase {

    private static let workflow = ".github/workflows/auto-merge-claude.yml"

    // MARK: - 1: the anchor — what this workflow is and when it fires

    /// Without this, every negative below is vacuous (#454): a renamed or deleted
    /// workflow would make "contains no gate" trivially true.
    func testTheWorkflowExistsAndFiresOnEveryBranchPush() throws {
        let yml = try rawFile(Self.workflow)
        XCTAssertTrue(yml.contains("name: Auto-Merge Claude Branch"), """
            The auto-merge workflow is gone or renamed. Everything else in this file is a \
            statement about it; re-anchor rather than letting the negatives pass empty.
            """)
        XCTAssertNotNil(yml.range(of: #"(?m)^\s*-\s*'claude/\*\*'"#, options: .regularExpression), """
            The workflow no longer fires on `claude/**` pushes. If the trigger moved, the \
            claim "every push to a work branch reaches main unreviewed" needs re-measuring.
            """)
    }

    // MARK: - 2: it structurally cannot wait for a gate

    /// ⭐ THE FINDING. Three independent ways a GitHub workflow can depend on another
    /// finishing, and this file uses none of them.
    func testItCarriesNoDependencyOnAnyOtherWorkflow() throws {
        let yml = try rawFile(Self.workflow)
        XCTAssertNil(yml.range(of: #"(?m)^\s*needs:"#, options: .regularExpression), """
            A `needs:` appeared. If that is the founder's repair, this claim has done its \
            job — delete it, and correct the CI section of CLAUDE.md in the SAME commit \
            (#456): it currently states that the merge waits for nothing.
            """)
        XCTAssertNil(yml.range(of: #"(?m)^\s*workflow_run:"#, options: .regularExpression), """
            A `workflow_run:` trigger appeared — see the message above; same repair, same \
            prose to pull along.
            """)
        XCTAssertNil(yml.range(of: #"conclusion"#, options: .regularExpression), """
            The workflow now reads a conclusion. That is a third way to gate, and it means \
            the same prose correction as the two above.
            """)
    }

    // MARK: - 3: it pushes straight to main

    /// A PR would put the checks in the way even without a `needs:`. There is no PR.
    func testItPushesDirectlyToMainWithoutAPullRequest() throws {
        let yml = try rawFile(Self.workflow)
        XCTAssertTrue(yml.contains("git push origin main"), """
            The direct push to `main` is gone. If this became a pull request, the checks \
            now stand in the way — say so in CLAUDE.md's CI section in the same commit.
            """)
        XCTAssertNil(yml.range(of: #"(?m)^\s*-\s*uses:.*create-pull-request"#,
                               options: .regularExpression),
                     "A PR action appeared — see the message above.")
    }

    // MARK: - 4: the counterweight — an ungated merge does not ship

    /// ⚠️ THIS IS WHAT KEEPS THE FINDING PROPORTIONATE. Remove the `if: false` and an
    /// unverified commit would go from "on main" to "on a tester's phone".
    func testTheMergeDoesNotDispatchTestFlight() throws {
        let yml = try rawFile(Self.workflow)
        XCTAssertTrue(yml.contains("workflow_id: 'testflight.yml'"), """
            The TestFlight dispatch step is gone entirely. That is fine for shipping — but \
            claim 4's counterweight now rests on absence rather than on a visible `if: \
            false`, so re-word the severity note at the top of this file.
            """)
        XCTAssertTrue(yml.contains("if: false"), """
            THE DISPATCH IS LIVE AGAIN. An auto-merge that waits for no gate would now put \
            an unverified commit on TestFlight. This is the one claim in this file worth \
            stopping for: raise it with the founder before the next push.
            """)
    }

    // MARK: - 5: the register names it

    /// The reason this file exists at all. A workflow that decides what reaches `main`
    /// belongs in the table a session reads to learn what runs here.
    func testTheActiveWorkflowsTableNamesIt() throws {
        let claude = try rawFile("CLAUDE.md")
        XCTAssertTrue(claude.contains("`auto-merge-claude.yml`"), """
            CLAUDE.md's Active Workflows table no longer names the workflow that decides \
            what reaches `main`. That omission is what this whole file was written for.
            """)
        XCTAssertTrue(claude.contains("Xcode Compile Check"),
                      "The CI section moved — re-anchor claim 5 rather than deleting it.")
        XCTAssertTrue(claude.contains("wartet auf KEIN Gate"), """
            The sentence recording that the merge waits for no gate is gone from CLAUDE.md. \
            If the founder gated the merge, claims 2 and 3 above are red too and this is \
            the correct order of repair; if they are green, the prose has drifted from the \
            workflow and the prose is what is wrong.
            """)
    }

    // MARK: - raw file access (see the ⚠️ note in the header: NO Swift stripper here)

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
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }
}
