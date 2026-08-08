import XCTest

/// #510 — the standing-prompt layer (`.claude/routines/`) described a product that was
/// renamed away and code that was deleted.
///
/// `_golden-goal.md` says of itself *"prepend verbatim to every Echoelmusic routine
/// prompt"* and *"never shorten it"*. It is therefore the FIRST thing every routine agent
/// reads — ahead of CLAUDE.md, which routine #1 only reaches at its own step 1. What it
/// said, measured against the tree on 2026-08-08:
///
/// * *"bio-reactive **ambient soundscape generator**"* — CLAUDE.md BRAND says in as many
///   words *"It is NOT a wellness, soundscape, or therapy product"* and *"NEVER use …
///   legacy bio-wellness/soundscape branding"*. The banned term was the product NOUN.
/// * *"**AUv3 Plugin** — Bio-reactive soundscape usable in Logic Pro, GarageBand, AUM"*,
///   as **priority 2 of 3**. The AUv3 target was removed 2026-07-24 (#121 slice 1/2).
///   This is the exact claim #158 and #192 each spent a full cycle removing from the
///   website and #184 removed twelve of from the App Store text, where a false claim is a
///   2.3 rejection. The website is now clean — all three `docs/` hits are explicit
///   denials (verified) — so the last surviving copy was in our own prompt.
/// * *"for iOS 26"* — the deployment floor is 18.0 (`Package.swift`, and four
///   `IPHONEOS_DEPLOYMENT_TARGET` entries in `project.yml`). The iOS 26 **SDK** is real
///   and separate; conflating floor and SDK is what made the line wrong.
/// * *"circadian phase"* — `CircadianClock` was deleted 2026-06-19; zero files name it.
///
/// And two dangling citations: `01-pr-auto-review.md` cited
/// `Sources/Echoelmusic/Core/SoundscapeEngine.swift` (deleted 2026-06-19) as its worked
/// example, and `05-decision-review.md` declared a trigger workflow
/// `.github/workflows/decision-review.yml` that has never existed.
/// **`scratchpads/archive/BACKLOG_OPTIMIZATION_2026-06-01.md:28` recorded that second one
/// on 2026-06-01** — it was archived rather than fixed, which is how a finding survives
/// two months in a repo that fixes things daily.
///
/// ⚠️ HONEST SIZING, first: this layer is DOORLESS. Every routine says *"When pasting into
/// claude.ai: prepend `_golden-goal.md` verbatim"*; nothing in the repo fires them (the
/// same archive note, line 34, says so). This slice therefore repairs a MECHANISM, not a
/// running system — written for the same reason as #429/#433/#444/#470: the sentence is
/// false whether or not a door exists, and a door arriving later must not sit on a silent
/// contradiction.
///
/// ⚠️ HONEST GRADING (#433), transcribed against `git show HEAD:` rather than asserted:
/// **FIVE** of six claims are regressions, and — unlike #486 — they are five DISTINCT
/// causes at five distinct sites (`_golden-goal.md` product noun · `_golden-goal.md` AUv3
/// list item · `01` dangling path · `05` trigger line · `05` due-predicate), not one
/// absence reported five times. The sixth is a COUNTERWEIGHT, green on both trees.
///
/// ⚠️ `proseOnly` is **LOAD-BEARING here, and that is MEASURED, not assumed** (#484/#485
/// had to retract the stronger claim once each, #486 twice): raw versus stripped, **3 of
/// 12 needle verdicts flip** — claims 1, 4 and 5 are all RED on the CORRECT worktree
/// without it, because the ⛔ retractions this very slice writes quote *"ambient
/// soundscape generator"*, `.github/workflows/decision-review.yml` and `` `CLOSED` ``
/// verbatim in order to withdraw them. The #486/#491 collision again, and at its widest
/// so far: this repo writes down what it removed, so a negative scan necessarily meets
/// its own obituary.
///
/// ⚠️ It is deliberately NOT `SourceText.codeOnly` (#453). That definition is for SWIFT —
/// it strips `//` and `/* */`, and `//` appears inside every URL in these files. Markdown
/// blockquotes are a different operation on a different language, so a second helper here
/// is not the #416 defect; unifying them would be. It is also named `proseOnly` rather
/// than `codeOnly` on purpose: `OneDefinitionOfCodeNotProseTests` anchors its
/// duplicate-stripper detector on the literal `func codeOnly`, and a same-named copy that
/// did something else would read as drift when it is not.
///
/// ⚠️ And the limit first: every claim is a TEXT SCAN over markdown. That a routine agent
/// reads these files, that it obeys them, and that the corrected wording produces better
/// reviews are three things this bundle cannot show.
final class TheStandingPromptDescribesThisRepoTests: XCTestCase {

    private static let routineFiles = [
        "_golden-goal.md",
        "01-pr-auto-review.md",
        "02-issue-triage.md",
        "03-bug-solver.md",
        "04-ci-watchdog.md",
        "05-decision-review.md",
    ]

    /// Claim 1 (REGRESSION — `_golden-goal.md:9` on the parent).
    ///
    /// The needle is the product NOUN, not the word: the corrected file still says
    /// *"never wellness/soundscape/therapy framing"*, which is the rule itself and must
    /// stay. A bare `contains("soundscape")` would forbid the repo from naming what it
    /// bans — the #364 trap.
    func testNoRoutineCallsThisProductASoundscapeGenerator() throws {
        let offenders = try scan { text in
            let lower = text.lowercased()
            return lower.contains("soundscape generator") || lower.contains("ambient soundscape")
        }
        let detail = offenders.joined(separator: ", ")
        XCTAssertTrue(offenders.isEmpty, """
            A routine prompt calls Echoel a soundscape generator: \(detail).
            CLAUDE.md BRAND: "It is NOT a wellness, soundscape, or therapy product."
            This text is prepended verbatim to every routine, so it outranks CLAUDE.md \
            in those agents' reading order.
            """)
    }

    /// Claim 2 (REGRESSION — `_golden-goal.md:18` on the parent).
    ///
    /// Naming AUv3 is allowed and necessary — the corrected file lists it under "not this
    /// product, on purpose", exactly so a routine does not propose rebuilding it. What is
    /// forbidden is naming it **together with a host**, which is only ever written to
    /// claim compatibility.
    func testNoRoutineClaimsAUv3HostCompatibility() throws {
        let hosts = ["Logic Pro", "GarageBand", "AUM"]
        let offenders = try scan { text in
            text.contains("AUv3") && hosts.contains(where: { text.contains($0) })
        }
        let detail = offenders.joined(separator: ", ")
        XCTAssertTrue(offenders.isEmpty, """
            A routine prompt names AUv3 alongside a host DAW: \(detail).
            The AUv3 target was removed 2026-07-24 (#121). #158, #192 and #184 each spent \
            a cycle deleting this claim from the website and the App Store text; the \
            website is clean today, so a copy here is the last one standing.
            """)
    }

    /// Claim 3 (REGRESSION — `01-pr-auto-review.md:102` on the parent, which cited
    /// `SoundscapeEngine.swift`, deleted 2026-06-19).
    ///
    /// This is doctor section B made blocking: a prompt that points at a deleted file
    /// teaches the agent a codebase that no longer exists, and no compiler sees it.
    func testNoRoutineCitesASourceFileThatIsGone() throws {
        let root = try treeRoot()
        var dangling: [String] = []
        for name in Self.routineFiles {
            let text = try proseOnly(routineText(name))
            for path in Self.sourcePaths(in: text) {
                let onDisk = root.appendingPathComponent(path).path
                if !FileManager.default.fileExists(atPath: onDisk) {
                    dangling.append("\(name) → \(path)")
                }
            }
        }
        let detail = dangling.joined(separator: ", ")
        XCTAssertTrue(dangling.isEmpty, """
            A routine prompt cites a source file that does not exist: \(detail).
            Fix the citation or delete it — do not leave a prompt describing a tree \
            that was refactored away.
            """)
    }

    /// Claim 4 (REGRESSION — `05-decision-review.md:3` on the parent).
    ///
    /// A declared trigger that cannot fire is worse than no trigger: the backlog reads as
    /// watched. `.github/workflows/**` is founder-gated, so the honest repair is to
    /// correct the CLAIM, never to invent the workflow.
    func testEveryDeclaredTriggerWorkflowExists() throws {
        let root = try treeRoot()
        var missing: [String] = []
        for name in Self.routineFiles {
            let text = try proseOnly(routineText(name))
            for path in Self.workflowPaths(in: text) {
                let onDisk = root.appendingPathComponent(path).path
                if !FileManager.default.fileExists(atPath: onDisk) {
                    missing.append("\(name) → \(path)")
                }
            }
        }
        let detail = missing.joined(separator: ", ")
        XCTAssertTrue(missing.isEmpty, """
            A routine declares a trigger workflow that does not exist: \(detail).
            Correct the trigger line. Do NOT add the workflow — .github/workflows/** is \
            founder-gated (report, do not edit).
            """)
    }

    /// Claim 5 (REGRESSION — `05-decision-review.md` step 2 on the parent).
    ///
    /// The parent filtered on `status != CLOSED`. Measured over all 364 rows on
    /// 2026-08-08: **`CLOSED` occurs zero times** — 22 status tokens are in use and none
    /// is that one — so the clause matched everything and a `shipped` or `superseded`
    /// decision would have been raised as an open question. `review.sh` owns the one
    /// predicate (#416); this asserts the routine quotes it rather than inventing a
    /// second.
    func testTheRoutineUsesTheOneDuePredicate() throws {
        let text = try proseOnly(routineText("05-decision-review.md"))
        XCTAssertTrue(text.contains("REVIEW_DUE") && text.contains("REVIEWED"), """
            05-decision-review.md must use review.sh's due-predicate \
            (review_date <= today AND status not in {REVIEW_DUE, REVIEWED}). \
            A second definition of "due" drifts silently — nothing compares them.
            """)
        XCTAssertFalse(text.contains("`CLOSED`"), """
            05-decision-review.md filters on a status token `CLOSED` that decisions.csv \
            has never used (0 of 364 rows). It filters nothing, and telling a reviewer to \
            write it would add a 23rd token that review.sh does not read.
            """)
    }

    /// Claim 6 (COUNTERWEIGHT — green on both trees, and the half that earns its place).
    ///
    /// #343: every claim above is a NEGATIVE scan, so deleting `_golden-goal.md` outright
    /// turns all five green while destroying the guardrail table that keeps routines from
    /// merging, pushing and deploying. Anchor on the file surviving with that table
    /// intact.
    func testTheGoldenGoalSurvivesWithItsGuardrails() throws {
        let text = try routineText("_golden-goal.md")
        XCTAssertGreaterThan(text.count, 500, "the canonical prefix has been gutted")
        XCTAssertTrue(text.contains("Golden Goal"),
                      "the canonical prefix lost its heading — the negative scans above go vacuous")
        XCTAssertTrue(text.contains("**Merge PRs into main**"), """
            The guardrail table is gone. Those rows are what stop a routine agent from \
            merging, pushing to main, deploying, or editing CI — they are the reason this \
            file is prepended verbatim.
            """)
    }

    // MARK: - helpers

    private func treeRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return root
    }

    private func routineText(_ name: String) throws -> String {
        let url = try treeRoot()
            .appendingPathComponent(".claude/routines")
            .appendingPathComponent(name)
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            throw AnchorMissing(reason: ".claude/routines/\(name) is missing or empty")
        }
        return text
    }

    /// Blanks every markdown blockquote line. This repo records what it removed, so a ⛔
    /// retraction quotes the removed wording verbatim and would satisfy a raw negative
    /// scan on CORRECT text. Line count is preserved for the same reason `SourceText`
    /// preserves it: a future claim may assert on the ORDER of two matches.
    private func proseOnly(_ text: String) throws -> String {
        let kept = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                line.drop(while: { $0 == " " }).hasPrefix(">") ? "" : line
            }
            .joined(separator: "\n")
        // #367: a strip that ate the body would make every negative claim vacuously true.
        guard kept.contains("Echoel") else {
            throw AnchorMissing(reason: "the blockquote strip ate the prompt body — negative claims would be vacuous")
        }
        return kept
    }

    private func scan(_ isOffending: (String) -> Bool) throws -> [String] {
        var hits: [String] = []
        for name in Self.routineFiles {
            let text = try proseOnly(routineText(name))
            if isOffending(text) { hits.append(name) }
        }
        return hits
    }

    private static func sourcePaths(in text: String) -> [String] {
        matches(in: text, pattern: "Sources/[A-Za-z0-9_/.-]+\\.swift")
    }

    private static func workflowPaths(in text: String) -> [String] {
        matches(in: text, pattern: "\\.github/workflows/[A-Za-z0-9_.-]+\\.yml")
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        var found: [String] = []
        for match in re.matches(in: text, range: whole) {
            guard let r = Range(match.range, in: text) else { continue }
            found.append(String(text[r]))
        }
        return found
    }

    private struct AnchorMissing: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }
}
