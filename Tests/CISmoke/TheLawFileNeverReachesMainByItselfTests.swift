// TheLawFileNeverReachesMainByItselfTests.swift
// Echoel — #697. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// WHAT THIS RECORDS, and it is the twin of #683 rather than a repeat of it. That one found
// that the auto-merge waits for no GATE. This one finds what it does not WATCH: neither
// auto-merge workflow lists `CLAUDE.md`, `memory/**` or `scratchpads/**` in its `paths:`
// filter. A commit that touches only those triggers NO MERGE OF ITS OWN — so the file every
// session reads FIRST can drift on `main` while the branch is correct, and nothing anywhere
// says so.
//
// ⛔ THE FIRST VERSION OF THIS FILE SAID "never reaches `main` by automation" AND THAT WAS AN
// OVER-CLAIM — caught an hour later by reading the workflow instead of re-reading my own
// sentence. The merge step takes `${{ github.sha }}`: the pushed commit WITH ITS WHOLE
// ANCESTRY, not a path-filtered subset. A law-only commit therefore rides to `main` as a
// PASSENGER on the next commit that touches a watched path. Measured twice: `c86a351`
// (SESSION_LOG only) rode on #695, `4ef259b` (#696) rode on #697.
//
// ⚠️ AND THE EVIDENCE I CITED COULD NOT TELL THE TWO APART. A snapshot of `main` looks
// identical under "never" and under "not yet"; only the workflow's merge step distinguishes
// them. That is the whole lesson of this retraction — the measurement was real and the
// conclusion drawn from it was one word too strong.
//
// ⭐ THE FILENAME SURVIVES THE RETRACTION, and that is worth one line rather than a rename
// (#374 asks for a rename when a name describes a procedure the code no longer takes). "Never
// reaches main BY ITSELF" is exactly what is true: it rides, it does not travel alone. The
// three words that had to go were in the prose, not in the name — a rarer outcome here than
// the reverse, and the reason to check the name against the correction instead of assuming.
//
// ⭐ THE FINDING SURVIVES IN TWO WEAKER, TRUE FORMS. The drift is UNBOUNDED in duration (the
// next code commit may be days away), and it becomes PERMANENT if a branch ENDS on such a
// commit — the ordinary case at the end of a 24h mandate. In neither form is there a signal:
// no run, no notification, nothing that surfaces it.
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
// `- 'claude/**'` is a BRANCH pattern and `- 'Sources/**'` is a PATH, and they are
// indistinguishable by shape — same indent, same quoting, a few lines apart. (⛔ #699 removed
// the two line numbers that stood here: a quoted token survives an insertion, a line number
// does not, and this repo has paid for that distinction repeatedly.) So
// every claim below reads the list that FOLLOWS the `paths:` key and stops at the first line
// that is not a list item. A needle that scanned the file would one day be "fixed" by someone
// who noticed it also matched the branch filter.
//
// ⚠️ CLAIM 2 SCANS ONLY `auto-merge-claude.yml`. If the founder instead widened
// `auto-merge-docs.yml`, the catch falls entirely to claim 3's `positives.count == 1` — which
// does fire, but by a different mechanism than this file's name advertises. Said here rather
// than duplicating the three needles onto the second workflow (#416): two scans of one decision
// is the defect, and claim 3 already owns that side.
//
// ⚠️ HONEST LIMITS. 7 tests. This proves what the workflows SAY, never what GitHub does:
// branch-protection and required-checks live in repository settings, not in the tree. It also
// cannot prove that `main` IS currently stale — that is a live `git` fact, not a source fact,
// and pinning it would make the guard red the moment the founder merges by hand, which is the
// #364 trap. What is proven is the mechanism that ALLOWS the drift.
//
// ⛔ #932 — I CLAIMED A REGISTER GAP THAT THE REGISTER ALREADY HELD, AND THE SENTENCE I WAS
// ABOUT TO WRITE WAS THE EXACT OVER-CLAIM IT HAD ALREADY PRE-EMPTED. Last cycle I measured
// that `scripts/**` appears in no `paths:` filter of the three gate/merge workflows and called
// it "ein echter Registerbefund". Both halves were wrong. `ContentPipeline/README.md` records
// it under #720 — surfaced by three of my own scripts-only commits (#717–#719) — and its own
// text says, verbatim, that "`scripts/**` steht in keinem Filter" would have been the next
// over-claim, because `xcode-compile-check.yml` lists ONE file from that directory by name:
// `scripts/check-infoplist.sh`. My grep looked for the GLOB and a per-file entry does not
// contain it. ⭐ THE LESSON IS NOT "grep better" — it is that a register entry lives where the
// decision lives, and I searched the always-loaded file plus this bundle and stopped. The
// cheap check that would have settled it is the one this repo already prescribes: grep the
// FINDING, not the file you expect to hold it.
//
// ⭐ SO WHAT #932 ACTUALLY ADDS, once the duplicate is subtracted: the #720 finding had NO
// GUARD. Its only home is prose that dates itself ("gemessen am 2026-08-22") and warns in its
// own margin that the list ages. Measured today: 19 tracked paths under `scripts/`, exactly
// ONE of them named in any `paths:` filter, and 11 Python scripts — 10 of them measuring
// instruments (`doctor.py`,
// `dead-needles.py`, `count-pins.py`, `founder-verify.py`, `gh-run-status.py`,
// `gh-test-verdict.py`, `needle-reachability.py`, and three more), the eleventh being
// `analyze-youtube.py`, which its own docstring calls PIPELINE-ONLY dev tooling rather than
// an instrument that measures this repo (#932b) — all unwatched. Claim 6
// pins the single precedent — the fact that makes the over-claim tempting and the one that can
// change silently — and claim 7 pins the prose that holds the inversion.
//
// ⚠️ THE PROPORTION, again stated so this reads as a record: no CI job runs any of
// `scripts/*.py`, so a gate run on such a commit would prove nothing about it. ⛔ #932b
// narrowed that sentence — it said "no CI job runs a Python script here", refutable in one
// grep: `community-triage.yml` runs `.github/scripts/community_triage.py` and
// `fetch-samples.yml` runs `scratchpads/tools/sample_processor.py`. The only `scripts/`
// files any workflow executes are `build-guard.sh` and `check-infoplist.sh`, both shell.
// A claim one directory too wide is still a wrong claim. The cost is the
// same documentation cost as the law file's — an instrument repaired on the branch reaches
// `main` only as a passenger, and never at all if the branch ends on such a commit.
//
// ⭐ GRADING (§3). Claims 1–4 are COUNTERWEIGHTS: the workflow files are untouched by this
// commit, so they are green at the parent too, and that is the point — they record a standing
// state rather than create it. Claim 5 is FORWARD: the CLAUDE.md sentence is new here, so it
// is red at the parent by one absence (#486) — ⛔ #932b: TRUE FOR #697, AND CARRIED FORWARD
// UNCHANGED INTO A PARAGRAPH THIS DIFF REWRITES, which is the generous-direction error §3
// forbids. Measured against #932's own parent: both of claim 5's needles are present in
// `CLAUDE.md` there, so for THIS commit claim 5 is a COUNTERWEIGHT, not forward. The line is
// kept with its origin named rather than silently re-graded, because the #697 grading was
// correct then and a reader comparing the two commits needs to see which tree each describes.
// Claims 6 and 7 (#932) are COUNTERWEIGHTS in the
// same sense as 1–4 — the workflow and the register both predate this commit, so both are green
// at the parent, and that is exactly the point: they pin a standing state that had no guard at
// all. Claim 2's fourth needle is green at the parent too. Nothing here is TRAGEND — this slice
// adds no behaviour, it stops a measured fact from ageing unwitnessed.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheLawFileNeverReachesMainByItselfTests: XCTestCase {

    private static let claudeMerge = ".github/workflows/auto-merge-claude.yml"
    private static let docsMerge = ".github/workflows/auto-merge-docs.yml"
    private static let compileCheck = ".github/workflows/xcode-compile-check.yml"

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
    ///
    /// ⭐ #932 ADDED `scripts/` TO THE SAME LOOP RATHER THAN STANDING A NEAR-COPY BESIDE IT
    /// (#416): it is one decision — what this merge filter does not watch — so it gets one
    /// scan. The CATEGORY differs and the rename says so: `scripts/` is not law, it is the
    /// measuring instruments, and an unmerged repair there leaves a future session running a
    /// tool this branch already fixed. The needle is the DIRECTORY, not the `scripts/**` glob,
    /// precisely because a filter can name a single file from it — see claim 6.
    func testTheClaudeMergeIgnoresTheLawTheLedgerAndTheInstruments() throws {
        let filter = try Self.pathFilter(in: rawFile(Self.claudeMerge))
        for needle in ["CLAUDE.md", "memory/", "scratchpads/", "scripts/"] {
            // #932b: `hasPrefix`, not `contains` — see claim 6. `ci_scripts/**` is a
            // tracked sibling of `scripts/`, and `docs/CLAUDE.md` is a different file from
            // the root law file. Both would be false reds under `contains`.
            let hits = filter.filter { $0.hasPrefix(needle) }
            XCTAssertTrue(hits.isEmpty, """
                `auto-merge-claude.yml` now watches "\(needle)" (\(hits.joined(separator: ", "))).

                If the founder widened the filter, this claim has done its job: delete it and \
                correct the prose in the SAME commit (#456) — but check WHICH prose. For \
                `CLAUDE.md`, `memory/` and `scratchpads/` it is CLAUDE.md's CI section, which \
                states that a commit touching only the law file triggers no merge of its own \
                and reaches `main` only as a passenger on a later code commit. For `scripts/` \
                it is the #720 register in `ContentPipeline/README.md` — the CLAUDE.md \
                sentence stays TRUE when the scripts filter widens, so following it there \
                would move the wrong paragraph (#932b, found in review).
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
        XCTAssertTrue(claude.contains("löst KEINEN eigenen Merge aus"), """
            The sentence recording that a CLAUDE.md-only commit triggers no merge of its own \
            is gone. (#698 replaced an earlier, stronger needle — "erreicht `main` nie durch \
            Automatik" — because the workflow merges the pushed commit's whole ancestry, so \
            such a commit DOES reach `main` as a passenger on the next code commit. If you are \
            restoring the old wording, re-read the workflow's merge step first.) If the founder widened a path filter, claim 2 above is red too \
            and THAT is the correct order of repair; if claim 2 is green, the prose has drifted \
            from the workflow and the prose is what is wrong.
            """)
    }

    // MARK: - 6: the precedent that stops the over-claim

    /// ⚠️ THE COUNTERWEIGHT TO CLAIM 2's NEWEST NEEDLE, and the reason #932 exists at all.
    /// `scripts/` is not blanket-unwatched: `xcode-compile-check.yml` names ONE file from it,
    /// `scripts/check-infoplist.sh`, so a commit to THAT script does pull a gate while one to
    /// `scripts/doctor.py` does not. Pinning the set at exactly that one entry keeps both
    /// failure directions loud — if it is removed, the last watched script is gone and the
    /// register sentence is wrong; if a second appears, the founder has begun widening and
    /// the prose must follow in the same commit (#456).
    func testExactlyOneScriptIsNamedInACompileGateFilter() throws {
        let filter = try Self.pathFilter(in: rawFile(Self.compileCheck))
        // ⛔ #932b — `contains` HERE WAS THE SIXTH COLLISION OF THE SAME LAW, and the
        // reviewer caught it in the one direction that matters: `ci_scripts/**` and
        // `.github/scripts/**` are BOTH real tracked directories in this repo, and
        // `ContentPipeline/README.md` names `ci_scripts/**` as ship-relevant and therefore
        // among the likeliest paths to be added to a filter. `contains` would then have gone
        // red and blamed `scripts/`. `hasPrefix` is the whole repair: an entry under another
        // directory is a different decision, and this claim owns only one of them.
        let scripts = filter.filter { $0.hasPrefix("scripts/") }
        XCTAssertEqual(scripts, ["scripts/check-infoplist.sh"], """
            `xcode-compile-check.yml`'s path filter now names \(scripts.count) entries under \
            `scripts/` (\(scripts.joined(separator: ", "))), not the single \
            `scripts/check-infoplist.sh` this claim was written against.

            MORE than one: the founder is widening the watch. Move the #720 register entry \
            in `ContentPipeline/README.md` in the SAME commit (#456) — it states the \
            single-file precedent as the reason a blanket "no script is watched" is wrong.

            NONE: the last watched script is gone, and the blanket sentence would now be \
            TRUE. Correct the register before quoting it either way.
            """)
    }

    // MARK: - 7: the register holds the inversion, not a partial list

    /// ⭐ THE PROSE HOME IS `ContentPipeline/README.md`, NOT `CLAUDE.md` (#416: the filters are
    /// enumerated once, and the always-loaded file points at that enumeration instead of
    /// copying it). What must survive there is the INVERSION #720 corrected to: the filter is
    /// a short allow-list, so the hole belongs to every other tracked path — not to a namable
    /// handful. A partial list in a register reads as complete, and answers "am I affected?"
    /// with No for everything absent from it.
    ///
    /// ⛔ THE FIRST NEEDLE HERE WAS `Erlaubnis-Liste` AND THIS COMMIT ITSELF BROKE IT — the
    /// FIFTH instance of the collision law (#921b, #924, #926, #928b) and the first where the
    /// guard and its collision arrive together. #932 also added a pointer paragraph to
    /// `ContentPipeline/README.md` saying the register now HAS a guard, and that paragraph
    /// names the framing word, so the needle went from 1 occurrence to 2. Deleting the #720
    /// sentence would then have left this claim GREEN on the pointer to itself — #926 exactly,
    /// a scanner reading its own literal. The repair is not a longer needle: it is a needle on
    /// the INVERSION (`jeder andere getrackte Pfad`), which is what the claim's name says it
    /// pins and which the pointer paragraph has no reason to repeat.
    ///
    /// ⚠️ Caught by counting occurrences after writing the paragraph, not by review. The cheap
    /// habit that finds this class every time: after ANY commit that adds prose about a guard,
    /// re-count that guard's needles in the file it reads.
    func testTheFilterRegisterKeepsTheInversionAndThePreEmptedOverClaim() throws {
        let readme = try rawFile("ContentPipeline/README.md")
        XCTAssertTrue(readme.contains("jeder andere getrackte Pfad"), """
            The #720 register no longer states the INVERSION — that the hole belongs to every \
            other tracked path, not to a namable handful of siblings. That inversion IS the \
            finding; a partial list would be the defect it was written to replace. Re-anchor \
            here only after re-reading the workflows.
            """)
        XCTAssertTrue(readme.contains("wäre die nächste Über-Behauptung gewesen"), """
            The sentence pre-empting the blanket claim is gone from \
            `ContentPipeline/README.md`. It is the only place recording WHY the blanket \
            wording is wrong; without it the next session measures the glob, finds nothing, \
            and writes the over-claim again — which is exactly what #932 did before reading \
            that file. If claim 6 is red too, fix the workflow reading first; prose follows.
            """)
    }

    // MARK: - reading the workflow

    /// The entries of the list that FOLLOWS the `paths:` key, trimmed of the `- ` and quotes.
    /// Stops at the first line that is not a list item, so a later key cannot leak in.
    ///
    /// ⚠️ Deliberately plain rather than a regex over the whole file: see the file header for
    /// why a whole-file scan cannot distinguish a branch pattern from a path pattern here.
    /// Not `throws`: it reads a `String` already in hand. The four call sites below still
    /// write `try` — that covers `rawFile`, which does throw. (⛔ #932b: "three" until
    /// claim 6 added the fourth in the same commit that left the number behind — a count
    /// in prose is a date, and this one aged inside a single diff.) Line-for-line honesty about which
    /// call the keyword belongs to, in a bundle that has paid for the opposite twice.
    private static func pathFilter(in yml: String) -> [String] {
        let lines = yml.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("paths:")
        }) else { return [] }
        var out: [String] = []
        for line in lines[(start + 1)...] {
            var t = line.trimmingCharacters(in: .whitespaces)
            // ⛔ #699 — WITHOUT THESE TWO SKIPS THE GUARD WAS BLIND TO THE REPAIR IT EXISTS TO
            // DETECT. The loop used to `break` on the first line that is not `- `, and this repo
            // writes FULL-LINE comments inside a `paths:` list: `ci.yml` has five of them, and
            // running this slicer over that file returns 4 entries while silently dropping
            // `.github/workflows/ci.yml`. So the likely repair — `- 'CLAUDE.md'` under a comment
            // saying why — would have left claims 1, 2 and 4 ALL GREEN with the law file in the
            // filter: green for a reason other than the one its message states (#367). A
            // following KEY (`jobs:`) still breaks the loop, so the extraction stays bounded.
            if t.isEmpty || t.hasPrefix("#") { continue }
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
