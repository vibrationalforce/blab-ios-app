// TheLawFileNeverReachesMainByItselfTests.swift
// Echoel — #697. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// WHAT THIS RECORDS, and it is the twin of #683 rather than a repeat of it. That one found
// that the auto-merge waits for no GATE. This one finds what it does not WATCH: neither
// auto-merge workflow lists `CLAUDE.md`, `memory/**` or `scratchpads/**` in its `paths:`
// filter. A commit that touches only those never reaches `main` by automation — so the file
// every session reads FIRST can drift on `main` while the branch is correct, and nothing
// anywhere says so.
//
// ⭐ IT IS NOT A HYPOTHESIS; it was measured on the drift it caused. #696 corrected the
// tracked-Swift-file count from 368 to 369. No workflow fired on that push (docs-only), and
// `git show origin/main:CLAUDE.md` still read **368** while the branch read **369** —
// `git rev-list --count origin/main..HEAD -- CLAUDE.md` = 1. The code commits either side of
// it (#695 `76eaf99`) merged normally, which is exactly why the gap is easy to miss: the
// SLICES land on `main`, only the law and the provenance stay behind.
//
// ⚠️ THE PROPORTION, so this reads as a record and not an alarm — the same shape as #683's
// claim 4. A stale `CLAUDE.md` on `main` reaches no user; `main` is not what ships
// (`.deploy/release` is). The cost is a FRESH CLONE, or any session that starts from `main`,
// reading a number or a law that the branch has already corrected. That is a real cost in a
// repo whose whole discipline is "measure, do not recite" — but it is a documentation cost,
// not a shipped defect, and claim 5 pins the half that keeps it that way.
//
// ⛔ THIS GUARD FORBIDS NOTHING (#364). `.github/workflows/**` is founder-gated — report, do
// not edit — so widening the filter (or deciding the law file SHOULD require a human merge,
// which is a perfectly good answer) is his call. On the day he widens it, claim 2 goes red BY
// DESIGN and its message names the prose to pull along in the same commit (#456). A red here
// is then the good news.
//
// ⚠️ WHY IT READS ITS TARGET RAW, and why it slices the block instead of scanning the file.
// `SourceText.codeOnly` is a SWIFT stripper; YAML comments start with `#`, so running it here
// would mangle rather than clean (#453, the same reasoning as `TheAutoMergeWaitsForNoGate`).
// But a whole-file negative would be WRONG here for a second reason that file does not face:
// `- 'claude/**'` at line 14 is a BRANCH pattern and `- 'Sources/**'` at line 16 is a PATH,
// and they are indistinguishable by shape — same indent, same quoting, four lines apart. So
// every claim below reads the list that FOLLOWS the `paths:` key and stops at the first line
// that is not a list item. A needle that scanned the file would one day be "fixed" by someone
// who noticed it also matched the branch filter.
//
// ⚠️ HONEST LIMITS. 5 tests. This proves what the workflows SAY, never what GitHub does:
// branch-protection and required-checks live in repository settings, not in the tree. It also
// cannot prove that `main` IS currently stale — that is a live `git` fact, not a source fact,
// and pinning it would make the guard red the moment the founder merges by hand, which is the
// #364 trap. What is proven is the mechanism that ALLOWS the drift.
//
// ⭐ GRADING (§3). Claims 1–4 are COUNTERWEIGHTS: the workflow files are untouched by this
// commit, so they are green at the parent too, and that is the point — they record a standing
// state rather than create it. Claim 5 is FORWARD: the CLAUDE.md sentence is new here, so it
// is red at the parent by one absence (#486).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheLawFileNeverReachesMainByItselfTests: XCTestCase {

    private static let claudeMerge = ".github/workflows/auto-merge-claude.yml"
    private static let docsMerge = ".github/workflows/auto-merge-docs.yml"

    // MARK: - 1: the anchor — both doors exist and both filter by path

    /// Without this every negative below is vacuous (#454): a renamed workflow, or one that
    /// dropped its `paths:` key entirely, would make "does not list CLAUDE.md" trivially true
    /// — and in the second case it would be true for the OPPOSITE reason, because a workflow
    /// with no path filter fires on everything.
    func testBothAutoMergeWorkflowsExistAndFilterByPath() throws {
        for path in [Self.claudeMerge, Self.docsMerge] {
            let yml = try rawFile(path)
            XCTAssertNotNil(yml.range(of: #"(?m)^\s*paths:"#, options: .regularExpression), """
                `\(path)` has no `paths:` key. If the filter was REMOVED, this whole file is \
                obsolete in the best possible way — the workflow now fires on every push, \
                including a CLAUDE.md-only one, and the finding is fixed. Delete these claims \
                and correct the CI section of CLAUDE.md in the same commit (#456). If instead \
                the file was renamed, re-anchor rather than letting the negatives pass empty.
                """)
            // Bound outside the assertion by habit, not by necessity — `pathFilter` does not
            // throw and `yml` is already in hand. The habit is worth keeping: this bundle has a
            // scar from a `try` inside an assertion's MESSAGE autoclosure, which is
            // non-throwing and does not compile (#663/#664), and with no local compiler the
            // cheapest defence is to never put a call inside an assertion argument at all.
            let entries = Self.pathFilter(in: yml)
            XCTAssertFalse(entries.isEmpty, """
                `\(path)` has a `paths:` key with no entries under it. The slicer below found \
                nothing, so every claim about "what is in the filter" would be empty. Fix the \
                slicer against the file's real indentation; do not relax the claims.
                """)
        }
    }

    // MARK: - 2: THE FINDING — the law file is in no filter

    /// ⭐ `CLAUDE.md`, `memory/` and `scratchpads/` are where this repo keeps its law, its
    /// count provenance and its session history. None of the three can reach `main` on its own.
    func testTheClaudeMergeIgnoresTheLawAndTheLedger() throws {
        let filter = try Self.pathFilter(in: rawFile(Self.claudeMerge))
        for needle in ["CLAUDE.md", "memory/", "scratchpads/"] {
            let hits = filter.filter { $0.contains(needle) }
            XCTAssertTrue(hits.isEmpty, """
                `auto-merge-claude.yml` now watches "\(needle)" (\(hits.joined(separator: ", "))).

                If the founder widened the filter, this claim has done its job: delete it and \
                correct CLAUDE.md's CI section in the SAME commit (#456) — it currently states \
                that a commit touching only the law file never reaches `main` by automation, \
                and #696's 368-vs-369 drift is cited there as the evidence.
                """)
        }
    }

    // MARK: - 3: the other door is docs-only, and `docs/` is not the law

    /// The obvious "but surely the docs merge covers it" — it does not. `CLAUDE.md` is at the
    /// repo root, not under `docs/`, so `docs/**` cannot match it. Worth pinning because it is
    /// the first thing a reader assumes, and because widening THAT filter is the other plausible
    /// repair.
    func testTheDocsMergeCoversOnlyTheWebsiteTree() throws {
        let filter = try Self.pathFilter(in: rawFile(Self.docsMerge))
        let positives = filter.filter { !$0.contains("!") }
        XCTAssertEqual(positives.count, 1, """
            `auto-merge-docs.yml` now has \(positives.count) positive path entries \
            (\(positives.joined(separator: ", "))), not the single `docs/**` this claim was \
            written against. If one of them reaches the repo root, the finding in claim 2 may \
            be fixed from this side instead — check, then move the prose.
            """)
        XCTAssertTrue(positives.first?.contains("docs/") == true, """
            The one positive entry in `auto-merge-docs.yml` is no longer under `docs/`: \
            \(positives.first ?? "—"). Re-read claim 2 against it before trusting either.
            """)
    }

    // MARK: - 4: counterweight — the scan reads the right list

    /// ⚠️ THE ANTI-VACUITY HALF, and it guards a specific confusion. `- 'claude/**'` (a BRANCH)
    /// and `- 'Sources/**'` (a PATH) are four lines apart and identical in shape. If the slicer
    /// ever grabbed the branch list instead, claim 2 would pass for the wrong reason — the law
    /// file is not in the branch list either. Asserting that the slice contains the code paths
    /// proves it landed on the path filter.
    func testTheSliceIsThePathFilterAndNotTheBranchFilter() throws {
        let filter = try Self.pathFilter(in: rawFile(Self.claudeMerge))
        for needle in ["Sources/**", "Tests/**"] {
            XCTAssertTrue(filter.contains { $0.contains(needle) }, """
                The slice of `auto-merge-claude.yml`'s `paths:` does not contain "\(needle)" — \
                it holds \(filter.joined(separator: ", ")). Either the code paths were removed \
                from the filter (a much bigger change than this file is about) or the slicer \
                landed on the branch list. Fix the slicer; claim 2 is worthless without this.
                """)
        }
        XCTAssertFalse(filter.contains { $0.contains("claude/**") }, """
            The slice contains the BRANCH pattern `claude/**`, so it is reading the `branches:` \
            list, not `paths:`. Every negative in claim 2 is then true for the wrong reason.
            """)
    }

    // MARK: - 5: the register names it

    /// The reason this file exists. A mechanism that decides whether the law file reaches
    /// `main` belongs in the section a session reads to learn what runs here.
    func testTheCISectionRecordsIt() throws {
        let claude = try rawFile("CLAUDE.md")
        XCTAssertTrue(claude.contains("`auto-merge-claude.yml`"), """
            CLAUDE.md's Active Workflows table no longer names the workflow this file is \
            about — re-anchor claim 5 rather than deleting it. (#683 added that row.)
            """)
        XCTAssertTrue(claude.contains("erreicht `main` nie durch Automatik"), """
            The sentence recording that a CLAUDE.md-only commit never reaches `main` by \
            automation is gone. If the founder widened a path filter, claim 2 above is red too \
            and THAT is the correct order of repair; if claim 2 is green, the prose has drifted \
            from the workflow and the prose is what is wrong.
            """)
    }

    // MARK: - reading the workflow

    /// The entries of the list that FOLLOWS the `paths:` key, trimmed of the `- ` and quotes.
    /// Stops at the first line that is not a list item, so a later key cannot leak in.
    ///
    /// ⚠️ Deliberately plain rather than a regex over the whole file: see the file header for
    /// why a whole-file scan cannot distinguish a branch pattern from a path pattern here.
    /// Not `throws`: it reads a `String` already in hand. The three call sites below still
    /// write `try` — that covers `rawFile`, which does throw. Line-for-line honesty about which
    /// call the keyword belongs to, in a bundle that has paid for the opposite twice.
    private static func pathFilter(in yml: String) -> [String] {
        let lines = yml.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("paths:")
        }) else { return [] }
        var out: [String] = []
        for line in lines[(start + 1)...] {
            var t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("- ") else { break }
            t = String(t.dropFirst(2))
            // A trailing `# comment` is legal on a YAML list item and one is present in
            // `auto-merge-docs.yml`; strip it before the quotes so it cannot end up in a needle.
            if let hash = t.firstIndex(of: "#") { t = String(t[..<hash]) }
            t = t.trimmingCharacters(in: .whitespaces)
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            if !t.isEmpty { out.append(t) }
        }
        return out
    }

    private struct AnchorMissing: Error { let reason: String }

    /// Raw, unstripped. See the header: the Swift comment stripper would mangle YAML.
    private func rawFile(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }
}
