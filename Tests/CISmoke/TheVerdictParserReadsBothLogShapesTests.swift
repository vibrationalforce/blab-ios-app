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
// forever. `--selftest` drives all four shapes the tool can meet — both envelopes, plain
// text, and plain text whose newlines are already escaped — and asserts the SAME verdict
// comes out of each.
//
// LIMITS, STATED FIRST (§1). This bundle is Swift and cannot execute Python, so nothing here
// runs `--selftest`; that is a `python3 scripts/gh-test-verdict.py --selftest` away and takes
// a second. What these claims CAN do is keep the repair from being quietly undone: the
// single-job key must stay decoded, the failure scan must stay independent of line splitting,
// and the selftest must keep naming more than one shape. A guard that pins the SHAPE of a
// repair is weaker than one that runs it — said plainly rather than implied.
//
// ⚠️ HONEST GRADING (#433/#464/#486). Hand-transcribed against `git show f40b9a3:` and the
// worktree before pushing:
//   · Claims 1-3 are REGRESSIONS: the parent's `load()` has no `logs_content` branch, its
//     failure list is built from `text.split("\n")`, and it has no selftest at all. Counted
//     as ONE finding — one loader that could not decode one envelope (#486).
//   · Claim 4 is a COUNTERWEIGHT, green on both, and NEGATIVE-ONLY: reintroducing the
//     `failed (` needle that #679 paid four failing tests to disprove goes red here. Its
//     positive half was withdrawn before shipping — see the stripper note below.
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
//   · 12 identical — no comment occurrence at all.
//   · `--selftest` 3 raw / 1 stripped, and `" failed on "` 5 raw / 4 stripped. Both had a
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
        XCTAssertTrue(code.contains(#"re.findall(r"Test case '([^']+)' failed on ", text)"#), """
            The failing-test list is no longer an anchored regex over the whole text.

            The version this replaced filtered `text.split("\\n")` for a line containing both
            "Test case " and " failed on ". On a document that arrived as ONE line that
            predicate is satisfied by the entire log, so it printed a single "failure" whose
            text was the rest of the file — beginning with the name of a test that had PASSED.
            Anchoring on the quoted name makes the count independent of how the envelope was
            decoded, which is the only property that made the two bugs stop agreeing.
            """)
        XCTAssertFalse(code.contains(#"for ln in text.split("\n")"#) &&
                       code.contains(#"" failed on " in ln"#), """
            The line-splitting failure filter is back. It is not wrong on a correctly decoded
            log — it is wrong on an INCORRECTLY decoded one, which is precisely the case the
            operator cannot see. Keep the regex.
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
        XCTAssertTrue(body.contains("MISREAD") || body.contains("return 0 if not bad else 1"), """
            `selftest()` no longer reports a non-zero exit when a shape is misread. A
            self-check that always exits 0 is the `continue-on-error` defect one layer down —
            it is the shape the `doctor` skill exists to name.
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
            The `failed (` needle is back. #679 measured that xcodebuild writes
            `Test case 'Suite.test()' failed on 'Clone 1 …' (0.039 seconds)`, so `failed (`
            can NEVER match — searching for it called a commit with FOUR failing tests clean.
            The live discriminator is pinned by claim 2; this claim only forbids the relapse.
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
