import XCTest

/// #509 — the decision log has to be readable by the one thing that reads it.
///
/// `decisions.csv` is the machine-readable half of the memory system: CLAUDE.md
/// says "Run `./review.sh` to surface decisions due for review" and "Daily cron job
/// auto-flags overdue decisions with `REVIEW_DUE`". Both halves were broken, in two
/// different ways, and neither could go red.
///
/// ⛔ THAT SECOND QUOTE IS HISTORICAL AS OF #805 — CLAUDE.md no longer says it, and the
/// sentence was not merely broken but false: nothing has ever flagged anything. #510 retracted
/// the same claim in `.claude/routines/05-decision-review.md` on 2026-08-08 and left the
/// always-loaded file asserting it for another 16 days. Claim 7 below is the executable form of
/// the fact this header already stated in prose ("It has never run"), and the quote is kept
/// rather than deleted because it is what the #509 narrative was written against.
///
/// **The file:** 5 of 361 decisions did not have 6 columns, and the repair brings
/// the log to 363 — the arithmetic is the point: two decisions had stopped being
/// rows at all. Three separate authoring habits produced the five —
/// `review_date` and `status` quoted together into ONE field
/// (twice; the second time the closing quote was forgotten and the field swallowed
/// the next TWO decision rows whole), one row written with an extra outcome field,
/// and two rows with an unescaped comma inside a `decision` / `expected_outcome`.
/// An 8-column row means a reasoning string sits where the review date belongs, so
/// that decision can never surface in the due report.
///
/// **The reader:** `review.sh` used `while IFS=, read -r date decision reasoning
/// outcome review_date status`, which splits on every comma and is blind to quoting
/// (`tr -d '"'` ran AFTER the split, so quoting never helped). Measured on the log
/// of 2026-08-08: **241 of 363 rows** handed a non-date to `review_date`. Two thirds
/// of the log was invisible to the report whose entire job is to surface it.
///
/// ⚠️ **The `--flag` path was the dangerous half** and is why this file pins the
/// rewrite as well as the read: it re-emitted the mangled split with `echo`. A
/// garbage token beginning with a space sorts before any date, so it read as due;
/// the status token was garbage too, so the "already flagged" skip never fired. One
/// run would have shifted every field of every comma-carrying row, permanently. It
/// has never run (`grep -c REVIEW_DUE` = 0) — luck, not design. `check-decisions.sh`,
/// the documented daily cron, calls exactly `review.sh --flag`.
///
/// ⚠️ **`SourceText.codeOnly` is the WRONG tool here and is deliberately not used.**
/// It strips `//` and `/* */`; a shell script comments with `#`. The needles would
/// be worse than useless without a shell-aware strip, and this is MEASURED, not
/// assumed: `IFS=,` and `read -r date decision` each occur **1× raw / 0× stripped**
/// — the ⛔ retraction block in `review.sh` quotes the removed form verbatim, so
/// both negative claims would be RED ON CORRECT CODE without the strip. This is the
/// #486/#491 collision again, in a language `codeOnly` does not cover: this repo
/// writes down what it removed, and a negative scan necessarily meets its own
/// obituary. The strip is line-wise at the first `#`, which is adequate ONLY because
/// no `#` in this file appears inside a string literal — measured, zero such lines.
/// A future `"…#…"` in `review.sh` breaks the strip, not the claims; that is stated
/// here so the next session widens the strip instead of loosening the claim.
///
/// ⚠️ HONEST GRADING (#433) — TRANSCRIBED against the parent tree and run, not
/// asserted. This file compiles against the parent (it names no symbol this commit
/// creates), so every claim really does have a verdict there — not the #464 case.
/// **FOUR claims are red on the parent, and they are TWO findings.** Finding one is
/// the file (`testEveryDecisionRowHasTheHeaderShape`). Finding two is the reader,
/// and its three claims are one root cause in three places — the read path, the
/// delegation, and `testTheRewriteGoesThroughACSVWriter`, which is the sharpest
/// because it pins the half that could destroy data rather than the half that
/// merely under-reported. Counting them as four findings would be the #433 defect
/// in the flattering direction.
///
/// ⛔ And my first draft of this paragraph had it wrong in exactly that direction:
/// it called `testBothDateColumnsAreDateShaped` a second symptom of finding one.
/// Measured, it is **green on the parent** — it skips rows whose column count is
/// already wrong, precisely so it does not re-report what claim 1 reports (#486).
/// It is a pure FORWARD guard: it buys the row that has six columns and prose in a
/// date field, which nothing else here can see. Two claims are green on both trees
/// and they are the ones that make the rest mean anything (#343).
///
/// ⚠️ And the limit first: this file proves the log PARSES and that the reader
/// delegates to a real parser. It does not run `review.sh`, does not prove python3
/// exists on the CI host, and says nothing about whether the 132 currently-due
/// decisions are worth reviewing. That last one is a founder judgment, not a test.
final class TheDecisionLogIsMachineReadableTests: XCTestCase {

    // MARK: - the file

    /// Claim 1 (REGRESSION). Every row carries the header's shape. A row that
    /// breaks it puts every later field in the wrong column, silently.
    func testEveryDecisionRowHasTheHeaderShape() throws {
        let rows = try decisionRows()
        let expected = rows[0].count
        XCTAssertEqual(expected, 6, "header should be date,decision,reasoning,expected_outcome,review_date,status")

        let malformed = rows.enumerated()
            .filter { $0.element.count != expected }
            .map { "row \($0.offset) has \($0.element.count) columns: \($0.element.first ?? "")" }

        let shapeDetail = malformed.joined(separator: "\n")
        XCTAssertTrue(malformed.isEmpty, """
            decisions.csv rows must all have \(expected) columns. A short or long row shifts \
            every field after the break, so that decision can never surface in the due report:
            \(shapeDetail)
            """)
    }

    /// Claim 2 (FORWARD GUARD — measured GREEN on the parent tree, so it is not a
    /// finding at all). It deliberately skips rows whose column count is already
    /// wrong, so it cannot re-report what claim 1 reports (#486). What it buys is
    /// the case claim 1 cannot see: a row with the right column COUNT but a swapped
    /// date/status, or a review date typed as prose.
    func testBothDateColumnsAreDateShaped() throws {
        let rows = try decisionRows()
        var bad: [String] = []
        for (i, r) in rows.enumerated() where i > 0 && r.count == 6 {
            if !isISODate(r[0]) { bad.append("row \(i) col0 (date): \(r[0].prefix(40))") }
            if !isISODate(r[4]) { bad.append("row \(i) col4 (review_date): \(r[4].prefix(40))") }
        }
        let dateDetail = bad.joined(separator: "\n")
        XCTAssertTrue(bad.isEmpty, """
            `date` and `review_date` must both be YYYY-MM-DD. review.sh compares them as strings, \
            so prose in either column silently sorts before every real date and reads as due:
            \(dateDetail)
            """)
    }

    /// Claim 3 (COUNTERWEIGHT — green on both trees, and the reason the rest mean
    /// anything). Every other claim in this file is vacuously true on an empty or
    /// deleted log (#343). The floor is deliberately far below the real count so
    /// ordinary logging never turns it red; it fails on deletion, not on pruning.
    func testTheLogIsStillPopulated() throws {
        let rows = try decisionRows()
        XCTAssertEqual(rows[0], ["date", "decision", "reasoning", "expected_outcome", "review_date", "status"],
                       "the header names are the contract review.sh and .claude/routines/05 both read by position")
        XCTAssertGreaterThan(rows.count - 1, 300, """
            The #509 repair took decisions.csv from 361 to 363 decisions and it grows every \
            cycle, so this floor is a deletion detector, not a census. A collapse to near-zero \
            would make every other claim in this file vacuously green.
            """)
    }

    // MARK: - the reader

    /// Claim 4 (REGRESSION). The bash field-split must not come back. This is the
    /// form that misread 241 of 363 rows.
    func testTheReaderDoesNotSplitOnEveryComma() throws {
        let sh = try shellCodeOnly(readerScript())
        XCTAssertFalse(sh.contains("IFS=,"), """
            review.sh must not split decisions.csv on every comma. `IFS=,` is blind to quoting, \
            and stripping quotes after the split does not help.
            """)
        XCTAssertFalse(sh.contains("read -r date decision"),
                       "the six-name `read` form is the specific misparse #509 removed")
    }

    /// Claim 5 (REGRESSION). Delegation to a real parser, so claim 4 cannot be
    /// satisfied by a script that reads the log some third broken way.
    func testTheReaderDelegatesToAQuoteAwareParser() throws {
        let sh = try shellCodeOnly(readerScript())
        XCTAssertTrue(sh.contains("python3"),
                      "review.sh parses decisions.csv with python3 — the house tool (scripts/gh-run-status.py)")
        XCTAssertTrue(sh.contains("csv.reader"),
                      "reading must go through the csv module, not a hand-rolled split")
    }

    /// Claim 6 (REGRESSION — the sharpest, because it pins the half that could
    /// destroy data rather than the half that merely under-reported).
    func testTheRewriteGoesThroughACSVWriter() throws {
        let sh = try shellCodeOnly(readerScript())
        XCTAssertTrue(sh.contains("csv.writer"), """
            `review.sh --flag` REWRITES decisions.csv and check-decisions.sh runs it daily. \
            Reassembling rows by hand re-emits the mangled split as the new file: one run \
            permanently shifts every field of every comma-carrying row.
            """)
        XCTAssertFalse(sh.contains("echo \"$date,$decision"),
                       "the hand-reassembled rewrite is the destructive form and must not return")
    }

    // MARK: - the schedule

    /// Claim 7 (#805) — nothing flags overdue decisions automatically, and the always-loaded
    /// law file must not tell a session otherwise.
    ///
    /// ⛔ THE DEFECT THIS CORRECTS IS #510's SECOND HOME. That slice, on 2026-08-08, retracted
    /// the "daily cron" claim in `.claude/routines/05-decision-review.md` — its ⛔ block is still
    /// there and says "unwired as automation". It did not touch `CLAUDE.md`, which went on
    /// asserting "Daily cron job auto-flags overdue decisions with `REVIEW_DUE`" as a plain fact
    /// for another 16 days, in the one file every session reads before its first line of work.
    /// The #456 law again, and the expensive direction of it: when two homes disagree, the
    /// always-loaded one wins by default, and here it was the wrong one.
    ///
    /// MEASURED, three ways, none of them recalled:
    ///   · `git log -S REVIEW_DUE -- decisions.csv` returns nothing over the WHOLE history — no
    ///     run of `--flag` has ever reached the repo. That is the decisive one, because `--flag`
    ///     WRITES to a tracked file: a run on anyone's machine would leave a diff.
    ///   · No workflow carries a `schedule:` trigger at all (not one, of fourteen).
    ///   · `check-decisions.sh` is a crontab line a human installs; `crontab` does not even
    ///     exist in the session container.
    ///
    /// ⚠️ WHY THIS IS NOT COSMETIC. The review mechanism is the founder's, and the report it
    /// feeds is long — measure it with `./review.sh | grep -c '^REVIEW DUE'` rather than reading
    /// a number here (#803). A law file that says the backlog is flagged automatically is the
    /// reason nobody looks at it.
    ///
    /// ⚠️ #364 — WHAT THIS DOES **NOT** DO. It does not forbid installing a scheduler; that is
    /// the repair, and `.github/workflows/**` is founder-gated so it is not mine to make. When
    /// one appears, the premise below flips and this claim goes red ONCE, with the two prose
    /// homes named in its message — the `TheAutoMergeWaitsForNoGateTests` shape. It also does not
    /// pin a wording: any of several markers satisfies it, and it deliberately does NOT assert on
    /// `review.sh`'s "it has never run" sentence, which becomes false the day someone runs the
    /// flag by hand and must then be free to change.
    ///
    /// ⚠️ POSITIVE, NOT A NEGATIVE SCAN, and that is deliberate (#491): this repo quotes its own
    /// retracted claims on purpose, so a scan for "daily cron" would meet the ⛔ block that
    /// retracts it. The assertion asks that the honest sentence be PRESENT, inside the anchored
    /// section it belongs to (#408) — a marker elsewhere in a 145 KB file would not count.
    ///
    /// GRADING (#464): REGRESSION. On the parent tree the anchored section contains none of the
    /// markers, because the sentence this commit writes is the only place any of them occur.
    func testTheLawFileDoesNotPromiseAutomaticFlagging() throws {
        let root = try treeRoot()
        let fm = FileManager.default

        // PREMISE, measured rather than assumed.
        var schedulers: [String] = []
        let workflows = root.appendingPathComponent(".github/workflows")
        for name in ((try? fm.contentsOfDirectory(atPath: workflows.path)) ?? []).sorted()
        where name.hasSuffix(".yml") || name.hasSuffix(".yaml") {
            guard let text = try? String(contentsOf: workflows.appendingPathComponent(name),
                                         encoding: .utf8),
                  text.contains("schedule:"),
                  text.contains("review.sh") || text.contains("check-decisions") else { continue }
            schedulers.append(".github/workflows/\(name)")
        }

        let law = try String(contentsOf: root.appendingPathComponent("CLAUDE.md"),
                             encoding: .utf8)

        // ANCHOR (#408/#454): the claim belongs to the decision-logging section. A missing
        // anchor FAILS — a section-wide scan that cannot find its section proves nothing.
        guard let start = law.range(of: "### Decision Logging"),
              let end = law.range(of: "\n### ", range: start.upperBound..<law.endIndex) else {
            throw AnchorMissing(reason:
                "CLAUDE.md has no `### Decision Logging` section followed by another `### ` "
                + "heading — claim 7 could not locate the text it grades")
        }
        let section = String(law[start.upperBound..<end.lowerBound]).lowercased()

        guard schedulers.isEmpty else {
            XCTFail("""
                A scheduler for the decision review now exists: \(schedulers.joined(separator: ", ")).

                That is good news and this claim is now the stale one. Two prose homes \
                describe the flagging as MANUAL and must be corrected in the same commit \
                that installs the scheduler:
                  · CLAUDE.md, the `### Decision Logging` block
                  · .claude/routines/05-decision-review.md, its ⛔ block (#510)
                Then retire this claim, or invert it to require that the scheduler stays.
                """)
            return
        }

        let markers = ["nichts flaggt automatisch", "flaggt nichts automatisch",
                       "kein automatischer", "keine automatik", "no scheduler", "not automated"]
        XCTAssertTrue(markers.contains(where: { section.contains($0) }), """
            Nothing in this repo flags overdue decisions, and the `### Decision Logging` \
            block of CLAUDE.md does not say so.

            Measured: `git log -S REVIEW_DUE -- decisions.csv` is empty over the whole \
            history, no workflow carries a `schedule:` trigger, and `check-decisions.sh` is a \
            crontab line a human installs. A law file that presents the flagging as automatic \
            tells every session the backlog is watched when it is not — which is exactly what \
            it did from #510 until #805, because #510 corrected the routine file and left \
            this one.

            Say it in the section, in any of these forms: \(markers.joined(separator: " / ")).
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

    private func decisionRows() throws -> [[String]] {
        let url = try treeRoot().appendingPathComponent("decisions.csv")
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = parseCSV(text)
        guard rows.first?.isEmpty == false else {
            throw AnchorMissing(reason: "decisions.csv parsed to no rows at all")
        }
        return rows
    }

    private func readerScript() throws -> String {
        let url = try treeRoot().appendingPathComponent("review.sh")
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            throw AnchorMissing(reason: "review.sh is missing or empty — the reader claims cannot be graded")
        }
        return text
    }

    /// Line-wise strip at the first `#`. See the ⚠️ note in the type doc for why
    /// `SourceText.codeOnly` cannot be used and why this suffices for this one file.
    private func shellCodeOnly(_ text: String) throws -> String {
        let stripped = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let hash = line.firstIndex(of: "#") else { return line }
                return line[line.startIndex..<hash]
            }
            .joined(separator: "\n")
        // #367: a strip that removed everything would make every negative claim
        // vacuously true. Anchor on code that must survive it.
        guard stripped.contains("set -euo pipefail") else {
            throw AnchorMissing(reason: "the shell strip ate the script body — negative claims would be vacuous")
        }
        return stripped
    }

    private func isISODate(_ s: String) -> Bool {
        guard s.count == 10 else { return false }
        let c = Array(s)
        guard c[4] == "-", c[7] == "-" else { return false }
        for i in [0, 1, 2, 3, 5, 6, 8, 9] where !c[i].isNumber { return false }
        return true
    }

    /// RFC 4180: `,` separates, `"` quotes, `""` is a literal quote inside a quoted
    /// field, and a quoted field may span newlines — which is exactly how one row
    /// here swallowed two others, so a line-based reader could not have found it.
    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if inQuotes {
                if ch == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                case "\r": break
                default: field.append(ch)
                }
            }
            i = text.index(after: i)
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    private struct AnchorMissing: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }

    // MARK: - 8 · the review filter can actually match (#815)

    /// ⛔ WHAT THIS CAUGHT. `review.sh` skipped `{REVIEW_DUE, REVIEWED}` — two statuses that
    /// occur ZERO times in `decisions.csv` and always have. The skip was empty in practice, so
    /// the report listed every past-dated row including decisions explicitly recorded as
    /// replaced or refused. **A filter whose entries cannot match is the same defect class as a
    /// needle that cannot match (#808)**, and it survived four months because an over-reporting
    /// filter looks like a thorough one.
    ///
    /// ⚠️ THIS ASSERTS MATCHABILITY, NOT MEMBERSHIP (#364). It does not say WHICH statuses
    /// belong in the list — that is the workflow judgment `review.sh`'s header argues out, and a
    /// later slice may widen or narrow it. It says every entry must correspond to something the
    /// log actually contains, so the list cannot silently become decoration again. Two entries
    /// are exempt BY NAME: `review_due` and `reviewed` are what `--flag` WRITES, so they are
    /// legitimately absent until it runs — without that exemption this claim would forbid the
    /// flagging path (#364 again, one level down).
    ///
    /// KIND (§1): **REGRESSION, and the DRIVE corrected the grading.** I predicted "8a passes on
    /// the parent because both entries are exempt". It does not: the parent's entries are
    /// `REVIEW_DUE`/`REVIEWED` in CAPITALS and the exempt set is lower-case, so the exemption
    /// missed — **the very case-sensitivity defect this slice fixed in `review.sh`, reproduced
    /// inside its own guard.** The entries are now lower-cased before both the exemption and the
    /// status lookup, and with that fix the prediction holds again: re-driven against `HEAD`,
    /// **8a passes and only 8b fails** (no BACKLOG line, no skipped-count).
    ///
    /// ⚠️ READ THAT SEQUENCE EXACTLY, because "the prediction was right after all" is the wrong
    /// summary. The prediction was right about the OUTCOME and wrong about the CODE: as first
    /// written, this guard did not do what the prediction assumed it did. A drive that ends
    /// green after a fix does not retroactively make the untested version correct. Fourth time
    /// this session a predicted verdict differed from the driven one (#808, #813, and the
    /// 216-vs-219 correction in `review.sh`'s own header).
    func testTheReviewFilterEntriesCanActuallyMatch() throws {
        let script = try readerScript()
        guard let open = script.range(of: "SKIP_STATUS = {"),
              let close = script.range(of: "}", range: open.upperBound ..< script.endIndex)
        else {
            return XCTFail("""
                `SKIP_STATUS = {` is gone from review.sh. It is the review report's only filter;
                if it was renamed, re-anchor this claim rather than deleting it — the defect it
                guards does not go away with the name.
                """)
        }
        let quoteAndSpace = CharacterSet(charactersIn: " \"\n")
        let entries = script[open.upperBound ..< close.lowerBound]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: quoteAndSpace).lowercased() }
            .filter { !$0.isEmpty }
        XCTAssertFalse(entries.isEmpty, "SKIP_STATUS is empty — the filter cannot skip anything.")

        let written: Set<String> = ["review_due", "reviewed"]   // what `--flag` WRITES, not reads
        let rows = try decisionRows().dropFirst()
        let statuses = Set(rows.compactMap { row -> String? in
            guard let last = row.last else { return nil }
            let head = last.trimmingCharacters(in: .whitespaces).lowercased()
            return head.split(separator: "-").first.map(String.init)
        })
        for entry in entries where !written.contains(entry) {
            XCTAssertTrue(statuses.contains(entry), """
                `review.sh` skips the status "\(entry)", which appears nowhere in decisions.csv.
                That is exactly how the old `{REVIEW_DUE, REVIEWED}` list read as a filter while
                skipping nothing for four months. Either the status was renamed in the log and
                this entry must follow it, or the entry was a guess.
                """)
        }
    }

    /// The report has to state its size BEFORE the first entry. Two hundred-odd items is a
    /// BACKLOG, not a to-do list, and a reader who starts at entry one cannot tell which.
    func testTheReviewReportStatesItsOwnSize() throws {
        let script = try readerScript()
        XCTAssertTrue(script.contains("BACKLOG:"), """
            The review report stopped stating its own size and age. Without it the output is a
            wall of entries that reads as a work queue; with it a session sees at once that the
            oldest is months old and that nothing has ever flagged them (#810 — there is no cron).
            """)
        XCTAssertTrue(script.contains("skipped as no longer in force"), """
            The report stopped saying how many rows the filter removed. That count is the only
            thing between an honest filter and one that quietly grows into hiding real work.
            """)
    }
}
