// TheVerdictParserReadsBothLogShapesTests.swift
// Echoel — the CI-verdict parser decoded one of two envelopes and reported off the other. #738.
//
// WHAT WAS WRONG. `scripts/gh-test-verdict.py` is the tool this directory's own CLAUDE.md
// tells every session to use instead of hand-rolling a needle set (#679). `get_job_logs`
// writes TWO envelopes and the loader only decoded one:
//
//   · run_id + failed_only → {"logs": [{"logs_content": "…"}], "run_id": …}   ← handled
//   · job_id               → {"job_id": …, "logs_content": "…"}               ← NOT handled
//
// On the second, `json.loads` SUCCEEDED, `"logs" not in blob` was true, and the loader fell
// through to `return raw` — handing every filter the un-decoded string with literal
// backslash-n and ZERO real newlines. Measured on `7644011`: it printed
// `tests observed passing: 1` where **136** passed; on `1118b46`, 1 where **172** passed.
//
// ⛔ AND THE FAILURE PATH WAS WORSE THAN THE COUNT. Driven against a fixture with two failing
// tests in the single-job shape, it printed **1** failure whose text began with the name of a
// test that had PASSED — because on one giant line `"Test case " in ln && " failed on " in ln`
// is satisfied by the whole log at once, and `split("Test case ", 1)[1]` then returns the
// remainder. Not silent (exit stayed 1), but an instrument that undercounts failures and
// labels a passing test as the failing one is exactly the class #679 built this script to end.
//
// ⭐ THE LESSON IS NARROWER THAN "HANDLE BOTH SHAPES", and it is why the repair is a shape
// SELFTEST rather than one more fixture: **a JSON parse that succeeds is not a decode that
// worked.** The document was well-formed; its only sin was a different key, and the
// fall-through answered with raw text. A fixture of either single shape would have passed
// forever.
//
// ⛔ AND #738's FIRST SWEEP WAS A CONTROL ITS OWN KNOWN-POSITIVE PASSED (#739) — #735's
// lesson recurring one commit later, inside the session that wrote #735. Measured: run
// #738's four shape checks against #737's broken loader and **all four report `ok`.** Every
// assertion it made was NEWLINE-INDEPENDENT (a regex over the whole text, a substring test),
// and JSON does not escape single quotes, so the needles sit in the un-decoded document
// verbatim. **It asserted the ANSWER while the defect was in the INPUT.** The fixture also
// carried one pass and one failure, so a count of 1 was right by accident.
//
// The sweep now asserts the DECODE and carries three live canaries, each the exact expression
// that went wrong: the real-newline count; #737's greedy `Test case .* passed on ` (3 on
// decoded text, 1 on one line); and #738's removed line predicate (2 vs 1). The fixture is
// three passes and two failures so no count is right by accident. Re-measured against a
// mutant carrying the true #737 state — no single-job branch AND no unescape belt — **3 of 5
// shapes go BAD, exit 1.** ⚠️ Removing ONLY the branch still passes, and that is CORRECT
// rather than a hole: the ratio-based `unescape` belt independently recovers such a document,
// verified against the real 250 kB log. Two independent repairs; the control reddens when
// both are gone, which is when the tool is actually broken.
//
// LIMITS, STATED FIRST (§1). This bundle is Swift and cannot execute Python, so nothing here
// runs `--selftest`; that is a `python3 scripts/gh-test-verdict.py --selftest` away and takes
// a second. What these claims CAN do is keep the repair from being quietly undone: the
// single-job key must stay decoded, the failure scan must stay independent of line splitting,
// the selftest must keep naming more than one shape AND keep its non-zero exit, and the tool
// must still exist at all (claim 0 — without it, deleting the script reddened nothing).
// A guard that pins the SHAPE of a repair is weaker than one that runs it — said plainly
// rather than implied. **Run `--selftest` by hand when you touch this script.**
//
// ⚠️ HONEST GRADING (#433/#464/#486). Hand-transcribed against `git show f40b9a3:` and the
// worktree before pushing:
//   · Claims 1-3 are REGRESSIONS: the parent's `load()` has no `logs_content` branch, its
//     failure list is built from `text.split("\n")`, and it has no selftest at all. Counted
//     as ONE finding — one loader that could not decode one envelope (#486).
//   · Claim 4 has two halves after #739. The NEGATIVE (`if "failed (" in` absent) is a
//     COUNTERWEIGHT green on both. The POSITIVE (the two-renderer alternation) is a
//     REGRESSION — the parent matched only the xcbeautify form and exited 0 on a plain
//     `xcodebuild` log. Its earlier positive half, a bare `" failed on "` substring, was
//     withdrawn before shipping: see the stripper note below.
//   · Claim 0 is a REGRESSION on the file's own failure mode, not on the parent's code: this
//     guard had no claim that could go red when the tool it grades is DELETED.
//   · Claim 5 is a COUNTERWEIGHT on the DIRECTORY's prose, green on both.
//
// ⚠️ STRIPPER (#453/#477): **NONE — and that is a measurement, not an omission.** This guard
// reads raw file text on purpose. `SourceText.codeOnly` strips SWIFT comments; the files
// scanned here are PYTHON (`#`) and MARKDOWN. Running it would strip nothing while the label
// implied comment-immunity — **a stripper pointed at a language it does not know is not
// stripping, it is passing text through**, and naming it would have been the fifth intuition
// label in a row (#728/#731/#732/#736).
//
// ⭐ SO THE MEASUREMENT WAS DONE THE OTHER WAY, WITH A PYTHON-AWARE STRIPPER, AND IT CHANGED
// THE GUARD. Fourteen needles, counted raw against `#`-and-docstring-stripped:
//   · 12 identical — no comment occurrence at all. ⚠️ EACH COUNTED IN ITS OWN SCAN SCOPE,
//     which the first draft did not say: whole-file counts for claim 3's three body needles
//     are 4/2, 5/3 and 9/7, i.e. NOT identical. Scoped to the `selftest` body — which is
//     what the claim actually reads — they are 2/2, 1/1, 4/4. A reader re-deriving the
//     number the obvious way would have got a different one and concluded the note was
//     stale. **State the scope beside the count, or the count is not reproducible.**
//   · `--selftest` 3 raw / 1 stripped, and the bare ` failed on ` 5 raw / 4 stripped
//     (⛔ the first draft wrote that needle as `" failed on "` WITH the quotes, a spelling
//     that occurs ZERO times in the file — a mis-transcription that left the conclusion
//     right and the recipe unrunnable, the `EchoelModalBank` shape). Both had a
//     real code occurrence TODAY, so neither was a false green — but delete the code and the
//     prose alone would have held each claim green. That is the TRAGEND condition arriving
//     one commit early.
// Both were repaired rather than documented: claim 3 now pins `sys.argv[1] == "--selftest"`
// (the dispatch, code-only), and claim 4's positive half was withdrawn outright — it was also
// a second spelling of claim 2's regex (#416). **The lesson that generalises: measure the
// needles even when no stripper is in play. The label answers "does stripping matter"; the
// question that actually protects the guard is "can prose alone satisfy this needle".**

import XCTest

private struct ToneAnchorMissingShape: Error, CustomStringConvertible {
    let reason: String
    var description: String { "anchor missing: \(reason)" }
}

final class TheVerdictParserReadsBothLogShapesTests: XCTestCase {

    private static let parser = "scripts/gh-test-verdict.py"
    private static let dirLaw = "Tests/CISmoke/CLAUDE.md"

    private func text(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(relative) not in this tree — nothing to grade (#454: missing TREE skips).")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 0 · the tool exists at all

    /// ⛔ WITHOUT THIS, DELETING THE TOOL PRODUCED ZERO RED ACROSS THE WHOLE FILE (#739).
    /// `text(_:)` throws `XCTSkip` when a file is absent, which is right for a #454 "missing
    /// TREE" — this bundle can run against a partial checkout. But the bundle normally runs
    /// on a FULL checkout, where absent can only mean deleted, and claims 1-4 would then all
    /// skip while claim 5 stayed green on the directory law's prose — the exact scenario
    /// claim 5's own message legislates against. **A guard whose every claim degrades to a
    /// skip has no failure mode**; one claim has to treat absence as absence.
    func testTheVerdictParserIsStillInTheRepository() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(Self.parser).path), """
            `\(Self.parser)` is gone. Every other claim here skips when it is absent, so this
            is the only one that can say so. If the tool was deliberately retired, retire
            `Tests/CISmoke/CLAUDE.md`'s paragraph and THIS FILE in the same commit (#456) —
            and put the replacement where the paragraph was, not nowhere.
            """)
    }

    // MARK: - 1 · REGRESSION: the single-job envelope is decoded

    func testTheLoaderKnowsTheSingleJobEnvelope() throws {
        let code = try text(Self.parser)
        XCTAssertTrue(code.contains("blob.get(\"logs_content\")"), """
            `gh-test-verdict.py` no longer reads the single-job envelope
            {"job_id": …, "logs_content": "…"}, which is what `get_job_logs` writes when it is
            given a job_id — the call every cycle in this session actually made. Without this
            branch `json.loads` succeeds, the "logs" test fails, and the loader returns the
            RAW string: one line, literal backslash-n, and every per-line filter reporting
            confident nonsense. Measured before the fix: 1 passing test reported where 136 ran.
            """)
        XCTAssertTrue(code.contains("blob.get(\"logs\")"), """
            The failed_only envelope {"logs": [{"logs_content": …}]} is no longer decoded.
            Both shapes are live — `failed_only=true` writes this one — and #738 exists
            because handling only ONE of them is indistinguishable from handling neither
            until the day the other arrives.
            """)
    }

    // MARK: - 2 · REGRESSION: the failure scan does not depend on line splitting

    func testTheFailureScanIsAnchoredAndNotLineBased() throws {
        let code = try text(Self.parser)
        // ⛔ SCOPED TO `main()` (#739). The bare regex text occurs TWICE in the script — the
        // live failure list AND `selftest()`'s own copy — so deleting the live one left the
        // claim green on the test double. The header's lesson had been applied to PROSE
        // occurrences only; "can other CODE satisfy this needle" is the same question and it
        // is the one that bit here.
        let live = try pythonBody(startingWith: "def main(", in: code)
        XCTAssertTrue(live.contains("find_failures(text)"), """
            The failing-test list is no longer an anchored scan over the whole text.

            The version this replaced filtered `text.split("\\n")` for a line containing both
            "Test case " and " failed on ". On a document that arrived as ONE line that
            predicate is satisfied by the entire log, so it printed a single "failure" whose
            text was the rest of the file — beginning with the name of a test that had PASSED.
            Anchoring on the quoted name makes the count independent of how the envelope was
            decoded, which is the only property that made the two bugs stop agreeing.
            """)
        XCTAssertFalse(live.contains(#"" failed on " in ln"#), """
            The line-splitting failure filter is back in `main()`. It is not wrong on a
            correctly decoded log — it is wrong on an INCORRECTLY decoded one, which is
            precisely the case the operator cannot see.

            ⚠️ Scoped to `main()` on purpose: `selftest()` keeps that exact predicate as a
            deliberate CANARY, so a whole-file ban would forbid the very thing that proves the
            bug cannot come back (#364).
            """)
    }

    // MARK: - 3 · REGRESSION: the tool proves itself across shapes

    func testTheParserCarriesAMultiShapeSelftest() throws {
        let code = try text(Self.parser)
        // The needle is the DISPATCH, not the flag name. Measured: the bare string
        // `--selftest` occurs three times raw and once outside comments — its usage line and
        // this file's own prose would keep the claim green after the branch was deleted.
        XCTAssertTrue(code.contains(#"sys.argv[1] == "--selftest""#), """
            `gh-test-verdict.py` no longer dispatches `--selftest`. A fixture of one shape
            passes forever against a loader that mishandles the other; a shape sweep is the
            only check that could have caught #738, and it is one second to run.
            """)
        // ⛔ SCOPED TO THE SELFTEST BODY, and the first draft was not — it asked whether the
        // whole FILE contained "logs" and "logs_content", which the parent's loader satisfies
        // on its own. Transcribed against `f40b9a3` before pushing: those two sub-assertions
        // came out GREEN ON A TREE WITH NO SELFTEST AT ALL. A needle that the thing it is
        // meant to detect does not affect is not a needle (#367) — and it was caught only
        // because every claim here was driven against the parent, not because it looked wrong.
        let body = try pythonBody(startingWith: "def selftest(", in: code)
        for shape in ["job_id", "\"logs\"", "logs_content"] {
            XCTAssertTrue(body.contains(shape), """
                `selftest()` no longer exercises the `\(shape)` shape. All four envelopes the
                tool can meet must produce the SAME verdict, which is the assertion — not that
                any one of them parses. If a shape is genuinely retired, drop it from the
                sweep AND from `decode()` in the same commit, so the tool never claims a
                coverage it does not have.
                """)
        }
        // ⛔ THIS WAS AN `||` AND ITS WEAKER HALF SURVIVED THE MUTATION IT NAMES (#739):
        // `body.contains("MISREAD")` is satisfied by the PRINT string, so replacing
        // `return 0 if not bad else 1` with `return 0` left the claim green while the
        // self-check became unconditionally successful. An `||` in a guard is only as strong
        // as its weakest disjunct — which is the whole reason to write one, and the reason it
        // has to be checked against the mutation rather than read.
        // ⚠️ THE CANARIES, PINNED BY NAME — the strongest text claim available for the #739
        // repair, and it is honestly weaker than the thing it guards. A source scan cannot
        // tell a sweep that DISCRIMINATES from one that does not; #738's sweep was fully
        // present and fully useless. What this CAN do is stop the three assertions that make
        // it discriminate from being quietly dropped, each being the exact expression that
        // once went wrong. Whether the sweep still reddens on a broken loader is a
        // `--selftest` against a mutant — a minute by hand, not expressible here (#488: this
        // limit is stated rather than left to read as coverage).
        // ⛔ THE NEEDLES ARE THE ASSIGNMENTS, NOT THE NAMES, AND THE FIRST DRAFT WAS THE
        // NAMES (#739, caught by transcribing against `1d806f0`). Bare `newlines` came out
        // GREEN ON THE PARENT — #738's sweep never computed it, but one of its shape LABELS
        // read "plain text, newlines already escaped". A needle satisfied by a label is the
        // same defect as one satisfied by a comment, third time in this file's short life.
        for canary in ["newlines = ", "greedy = ", "line_filter = "] {
            XCTAssertTrue(body.contains(canary), """
                `selftest()` no longer computes `\(canary)`. The three together are what make
                the sweep discriminate: `newlines` asserts the DECODE itself, `greedy` is
                #737's own expression (3 on decoded text, 1 on one line), and `line_filter` is
                the predicate #738 removed from production and kept here on purpose. Without
                them every assertion is newline-independent and the sweep passes against the
                very loader it is meant to catch — measured, that is exactly what #738 did.
                """)
        }
        XCTAssertTrue(body.contains("return 0 if not bad else 1"), """
            `selftest()` no longer exits non-zero when a check is misread. A self-check that
            always exits 0 is the `continue-on-error` defect one layer down — the shape the
            `doctor` skill exists to name.
            """)
    }

    /// Body of a top-level Python `def`, from its line to the next line that starts a new
    /// top-level statement (column 0, non-blank, not a decorator). Structural, not a fixed
    /// window (#408) — Python has no closing brace to match, so the boundary is indentation.
    private func pythonBody(startingWith prefix: String, in code: String) throws -> String {
        let lines = code.components(separatedBy: "\n")
        var start = -1
        for (i, line) in lines.enumerated() where line.hasPrefix(prefix) {
            guard start == -1 else {
                throw ToneAnchorMissingShape(reason: "`\(prefix)` occurs more than once — the anchor is not unique (#408)")
            }
            start = i
        }
        guard start >= 0 else {
            throw ToneAnchorMissingShape(reason: "no line starts with `\(prefix)` in the parser")
        }
        var out: [String] = [lines[start]]
        var i = start + 1
        while i < lines.count {
            let line = lines[i]
            let isTopLevel = !line.isEmpty && !line.hasPrefix(" ") && !line.hasPrefix("\t")
                && !line.hasPrefix("#") && !line.hasPrefix("@")
            if isTopLevel { break }
            out.append(line)
            i += 1
        }
        return out.joined(separator: "\n")
    }

    // MARK: - 4 · COUNTERWEIGHT: #679's discriminator survives the rewrite

    func testTheFailedOnDiscriminatorIsStillTheNeedle() throws {
        let code = try text(Self.parser)
        // ⛔ THE POSITIVE HALF OF THIS CLAIM WAS WITHDRAWN BEFORE IT EVER SHIPPED, for two
        // reasons that were MEASURED rather than felt.
        //   · #416 — claim 2 already pins the exact regex that carries `" failed on "`.
        //     Asserting the bare substring here was a second spelling of one decision.
        //   · It was the weaker spelling. The bare needle occurs 5 times raw and 4 outside
        //     comments; delete the regex and this file's own explanatory prose in the parser
        //     would hold the claim green. A needle whose subject can be removed while it
        //     stays satisfied is not evidence (#367).
        // What survives is the half that #679 actually paid for: the wrong needle must not
        // come back. That one can only be satisfied by real code.
        XCTAssertFalse(code.contains(#"if "failed (" in"#), """
            The `failed (` needle is back AS A SUBSTRING TEST. #679 measured that xcbeautify
            writes `Test case 'Suite.test()' failed on 'Clone 1 …' (0.039 seconds)`, so
            searching for `failed (` INSTEAD of `" failed on "` called a commit with FOUR
            failing tests clean.

            ⚠️ #739 corrected the other half of that story: plain `xcodebuild` (no formatter)
            really does write `Test Case '-[STests testA]' failed (0.001 seconds).`, and #738
            anchored on the xcbeautify form ONLY — on such a log the tool printed
            `TEST FAILURES: 0` and exited 0, a SILENT green. So `failed (` is banned ALONE and
            REQUIRED IN THE ALTERNATION; the next claim pins the alternation. Never either.
            """)
        XCTAssertTrue(code.contains(#"failed on |failed \("#), """
            The failure pattern no longer covers BOTH renderings. Today's pipeline pipes
            through xcbeautify and only emits the first, so dropping the second is invisible
            until the day a workflow loses the pipe — and then the tool exits 0 on a log full
            of failures. That is strictly worse than #679's loud-but-wrong reading.
            """)
    }

    // MARK: - 5 · COUNTERWEIGHT: the directory law still points sessions at this tool

    func testTheDirectoryLawStillNamesTheScript() throws {
        let law = try text(Self.dirLaw)
        XCTAssertTrue(law.contains("scripts/gh-test-verdict.py"), """
            `Tests/CISmoke/CLAUDE.md` no longer names the verdict parser. That paragraph is
            what stops a session hand-rolling a fourth ad-hoc needle set, which is how #679
            happened. If the tool is retired, retire the paragraph in the SAME commit (#456)
            — and put whatever replaces it in the paragraph's place, not nowhere.
            """)
    }
}
