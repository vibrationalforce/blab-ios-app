import XCTest

/// #509 — the decision log has to be readable by the one thing that reads it.
///
/// `decisions.csv` is the machine-readable half of the memory system: CLAUDE.md
/// says "Run `./review.sh` to surface decisions due for review" and "Daily cron job
/// auto-flags overdue decisions with `REVIEW_DUE`". Both halves were broken, in two
/// different ways, and neither could go red.
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
}
