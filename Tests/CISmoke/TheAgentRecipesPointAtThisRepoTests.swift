// TheAgentRecipesPointAtThisRepoTests.swift
// Echoel — #1041. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// WHAT THIS RECORDS. `.claude/agents/*.md` and `.claude/routines/*.md` are PRESCRIPTIVE: they
// hand a subagent the command to run and the fix to apply. A phantom in one of them does not
// merely mislead a reader — it produces a scan over a directory that is not there, or code
// against an API that was never in the tree. Measured 2026-09-06, four defects in three files:
//
//   · `concurrency-reviewer.md` — ALL EIGHT `grep` recipes pointed at `Echoelmusic/`, and two
//     also at `EchoelmusicComplete/`. `ls -d` on both: "No such file or directory". Each recipe
//     still returned the `Sources/` hits, so it half-worked while printing what looks like a
//     broken tool, and `grep -r` over a missing path exits 2, so `&&` chaining after it stopped.
//   · `build-error-resolver.md` — "API Gotchas" prescribed `.value` on `NormalizedCoherence`
//     (0 hits in `Sources/`; the one hit in `Tests/` is a test METHOD name) and listed eight
//     method names of `EchoelBrandFont` (0 hits in `Sources/` AND `Tests/`). The live type is
//     `EchoelTheme`, 1765 references.
//   · `02-issue-triage.md` — routed "sound doesn't react to heartbeat" to a DEEP_RESEARCH doc
//     that does not exist anywhere, and "camera pulse not working" to `isCameraActive` /
//     `BioSourceManager`, both 0 hits (the manager went in the 2026-06-19 cleanup).
//
// ⭐ AND THE SIBLING FILE ALREADY HAD THE DIRECTORY FIX. `ui-state-reviewer.md:18` says in so
// many words that its recipes "pointed at `Echoelmusic/` and `EchoelmusicComplete/`, neither of
// which exists". One agent file was corrected and the other was not — the #456 shape, and the
// third instance of it in a single day (#1035 CLAUDE.md→build-guard, #1038 #1024→CLAIMS.md).
// That is why claim 2 scans the WHOLE tree for the recipe shape rather than one file.
//
// ⛔ THIS GUARD FORBIDS NOTHING (#364). Claim 1 works off an explicit list of names that are
// deliberately dead, and it is red in BOTH directions: a NEW phantom is not on the list, and a
// REVIVED name is on the list while existing again. Either way the message says which edit to
// make. Nothing here stops an agent file naming a real type, adding a recipe, or being deleted.
//
// ⚠️ WHY CLAIM 1 NEEDS A LIST AT ALL, rather than "every backticked Echoel* must exist". That
// simpler rule was written first and MEASURED before it was trusted: it fires on four names
// that are perfectly legitimate — `EchoelDDSPTests` (a test class, so absent from `Sources/`),
// `EchoelmusicFullTests`, `EchoelmusicWatch`, `EchoelmusicWidgets` (scheme and target names in
// `project.yml`). Widening the corpus to Sources+Tests+project.yml+Package.swift clears those,
// and exactly three remain — each a deliberate retraction. A guard tuned until it is quiet is
// decoration; this one was tuned until every remaining hit was a real finding.
//
// ⚠️ AND CLAIM 1 CANNOT TELL AN EPITAPH FROM LIVE ADVICE — say it plainly, because the
// grading below reads better than the guard is. At the parent commit `EchoelBrandFont` was
// cited as a FIX TO APPLY, and claim 1 was green there, because the name is on the list. The
// list is what makes the check quiet enough to survive; it is also why claim 1 catches only
// the FOURTH phantom, never the three already known. Those three are held honest by the
// retraction prose beside them and by the `revived` half above, not by this claim.
//
// ⚠️ HONEST LIMITS. This proves the NAMES resolve and the RECIPE PATHS exist. It cannot know
// whether a recipe finds what it claims to find — `ui-state-reviewer.md` records a
// `grep "@Observable" | grep "class"` that selected 0 of 65 because the attribute sits on its
// own line, and no path check would have caught that. The repaired recipe in
// `concurrency-reviewer.md` carries a `-A 1` and a warning for that reason; verifying its yield
// stays non-zero is a human step, not this file's.
//
// ⭐ GRADING (§3). Transcribed in Python against both trees. Claim 2 is FORWARD — eight matching
// recipe lines at the parent, zero here. Claim 1 is a COUNTERWEIGHT, green at the parent too
// for the reason stated above; it goes red on a FOURTH phantom or on a revival. Driven to red
// deliberately (#914): adding "`EchoelPhantomMutant`" to `code-reviewer.md` produced
// `unknown phantoms=['EchoelPhantomMutant']`, and the line was removed again.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheAgentRecipesPointAtThisRepoTests: XCTestCase {

    /// Names that appear in agent instructions, do NOT exist in the tree, and are there on
    /// purpose — each next to a retraction explaining what replaced it. Re-measured by claim 1
    /// on every run, so the list cannot quietly rot into an excuse.
    private static let deliberatelyDead: Set<String> = [
        "EchoelBeat",           // the drum product; deleted by #166/#167, cited by dsp-reviewer
        "EchoelBrandFont",      // never existed; the live type is EchoelTheme (#1041)
        "EchoelmusicComplete"   // a phantom directory; cited by ui-state-reviewer and #1041
    ]

    // MARK: - 1: every project name an agent file cites either exists or is a known epitaph

    func testEveryEchoelNameInAnAgentFileResolvesOrIsAKnownEpitaph() throws {
        let root = try repoRoot()
        let corpus = try instructionFiles(under: root)
        XCTAssertFalse(corpus.isEmpty, """
            No `.claude/agents/*.md` or `.claude/routines/*.md` files found. Every claim in \
            this file is a statement about them; re-anchor rather than passing on an empty set.
            """)

        // The tree the names must resolve against — code AND the project/package manifests,
        // because a scheme or target name is a real name that lives in neither Sources nor Tests.
        var tree = ""
        for relative in ["Sources", "Tests"] {
            let base = root.appendingPathComponent(relative)
            guard let walk = FileManager.default.enumerator(atPath: base.path) else { continue }
            for case let rel as String in walk where rel.hasSuffix(".swift") {
                tree += (try? String(contentsOf: base.appendingPathComponent(rel),
                                     encoding: .utf8)) ?? ""
            }
        }
        for manifest in ["project.yml", "Package.swift"] {
            tree += (try? String(contentsOf: root.appendingPathComponent(manifest),
                                 encoding: .utf8)) ?? ""
        }
        XCTAssertTrue(tree.contains("EchoelStudioView"), """
            The tree corpus came back without `EchoelStudioView`, so it did not load. Every \
            name would look dead and this claim would fire on all of them. Fix the reader.
            """)

        let backticked = try NSRegularExpression(pattern: "`(Echoel[A-Za-z0-9_]+)")
        var cited = Set<String>()
        for file in corpus {
            let ns = file.text as NSString
            for m in backticked.matches(in: file.text,
                                        range: NSRange(location: 0, length: ns.length)) {
                cited.insert(ns.substring(with: m.range(at: 1)))
            }
        }

        let absent = cited.filter { !tree.contains($0) }
        let unknownPhantoms = absent.subtracting(Self.deliberatelyDead).sorted()
        XCTAssertTrue(unknownPhantoms.isEmpty, """
            Agent instructions cite \(unknownPhantoms) — no such name exists in `Sources/`, \
            `Tests/`, `project.yml` or `Package.swift`.

            These files are PRESCRIPTIVE: a subagent is told to run the command and apply the \
            fix. A phantom here produces code against an API that was never in the tree — \
            #1041 found `EchoelBrandFont` handing out eight method names of nothing. Either \
            correct the citation to the live name, or, if the name is a deliberate epitaph, \
            add it to `deliberatelyDead` above WITH the retraction that explains what replaced \
            it. Do not add it to the list to silence this.
            """)

        let revived = Self.deliberatelyDead.filter { tree.contains($0) }.sorted()
        XCTAssertTrue(revived.isEmpty, """
            \(revived) is on the `deliberatelyDead` list and EXISTS in the tree again.

            That is good news and still a red (#364): the epitaph beside it in the agent file \
            is now false, and a reader would be told a live thing is gone. Remove the name \
            from the list and correct the prose in the SAME commit (#456).
            """)
    }

    // MARK: - 2: the finding — no recipe scans a directory that is not there

    /// ⭐ Anchored to the recipe SHAPE (`--include="*.swift"`), not to prose, so the retraction
    /// blocks that quote the phantom paths cannot trip it.
    func testNoRecipeScansADirectoryThatDoesNotExist() throws {
        let root = try repoRoot()
        var offenders: [String] = []
        for file in try instructionFiles(under: root) {
            for line in file.text.split(separator: "\n", omittingEmptySubsequences: false) {
                guard line.contains("--include=\"*.swift\"") else { continue }
                if line.contains(" Echoelmusic/") || line.contains(" EchoelmusicComplete/") {
                    offenders.append("\(file.name): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) recipe(s) scan a top-level `Echoelmusic/` or \
            `EchoelmusicComplete/` directory, and neither exists — the source tree is \
            `Sources/Echoelmusic/`:

            \(offenders.joined(separator: "\n            "))

            The recipe still returns the `Sources/` hits, so it half-works while printing what \
            reads as a broken tool, and `grep -r` over a missing path exits 2, which silently \
            stops any `&&` after it. `ui-state-reviewer.md` had this corrected before \
            `concurrency-reviewer.md` did; when you fix a recipe, grep the whole `.claude/` \
            tree for the same shape before calling it done (#456).
            """)

        // COUNTERWEIGHT (#367): a negative over an empty set is not a measurement.
        let recipeLines = try instructionFiles(under: root)
            .flatMap { $0.text.split(separator: "\n") }
            .filter { $0.contains("--include=\"*.swift\"") }
        XCTAssertFalse(recipeLines.isEmpty, """
            No `--include="*.swift"` recipe lines found at all, so claim 2's negative passed \
            over nothing. If the agent files stopped carrying grep recipes, re-anchor this \
            claim on whatever shape replaced them.
            """)
    }

    // MARK: - helpers

    private struct DiagAnchorMissing: Error { let reason: String }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return root
    }

    private func instructionFiles(under root: URL) throws -> [(name: String, text: String)] {
        var out: [(name: String, text: String)] = []
        for dir in [".claude/agents", ".claude/routines"] {
            let base = root.appendingPathComponent(dir)
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: base.path)
            else { continue }
            for item in items.sorted() where item.hasSuffix(".md") {
                guard let text = try? String(contentsOf: base.appendingPathComponent(item),
                                             encoding: .utf8) else { continue }
                out.append(("\(dir)/\(item)", text))
            }
        }
        return out
    }
}
