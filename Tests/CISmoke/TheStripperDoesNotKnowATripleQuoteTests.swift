// TheStripperDoesNotKnowATripleQuoteTests.swift
// Echoel — #659. `SourceText.codeOnly` resets string state at every newline, so a Swift
// MULTI-LINE string literal is not a string to it. Measured, documented, pinned — and
// deliberately NOT "fixed".
//
// WHAT IS ACTUALLY TRUE. `codeOnly` walks each line with a fresh `inString = false`. A `"""`
// opens nothing that survives the newline, so every line INSIDE a multi-line literal is scanned
// as code: a `//` in that body ends the line, a `/*` in it opens a block. The type's own doc
// says it returns "everything the compiler would see, with comments blanked", and for a `"""`
// body that sentence is false.
//
// ⭐ AND THE FIX WOULD HAVE BEEN A REGRESSION, WHICH IS WHY THIS SLICE IS A GUARD AND NOT A
// PATCH. Measured 2026-08-20 across all 368 `Sources/**/*.swift`:
//   · 9 files carry a `"""` at all
//   · the two shapes disagree on exactly ONE of them — `Views/MetalBioView.swift`, 337 lines
//   · across the 36 needles the four guards that scan that file assert on, ZERO change count
// The 337 lines are the Metal shader, which `MetalBioView` holds as one `"""` literal. Its `//`
// are REAL comments — to the Metal compiler, which is the compiler that reads them. So for the
// single file where the shapes differ, today's behaviour is the one a source scanner wants, and
// a `"""`-aware stripper would start feeding shader comments to guards as if they were shader
// code. `GlitterCannotBecomeAFlashTests` — the WCAG-3-Hz flash-safety guard — is one of the four.
//
// ⚠️ SO THE HONEST STATEMENT IS "latent, one file, currently benign, and the obvious repair is
// wrong for the only case that exists" (#367: a guard should be able to fail for a reason that
// exists; inventing `"""` handling ahead of a real case would break the real case). What is
// genuinely wrong is that `SourceText.swift` LISTS its limitations — raw strings, nested block
// comments — and omitted the biggest one. Test 3 is that half.
//
// ⚠️ WHAT NO TEST HERE CAN PROVE: that a future `"""`-carrying scan target is benign. Test 2
// exists precisely because that is unknowable in advance — it names the day a second file joins
// the list, and asks a human to make the call the measurement above made once.
//
// ⛔ THIS FILE DECLARES A SECOND STRIPPER ON PURPOSE (`tripleQuoteAwareCodeOnly`), which is the
// shape `OneDefinitionOfCodeNotProseTests` exists to prevent. It is not a copy of the decision:
// it is the CONTRAST used to measure the shipped one, it is never used to make an assertion
// about source content, and this file calls `SourceText.codeOnly` for the real half. Stated
// here rather than left to the fact that the delegation check happens to exempt it (#453).

import XCTest

final class TheStripperDoesNotKnowATripleQuoteTests: XCTestCase {

    // MARK: - 1. The shipped behaviour, exercised (not read)

    /// END-TO-END on `SourceText.codeOnly` itself: a `//` inside a `"""` body is stripped.
    ///
    /// This pins the property as KNOWN rather than accidental. It is the assertion that goes red
    /// the day someone teaches the scanner about `"""` — which is allowed, and the message says
    /// what else moves in that commit (#364/#456).
    func testAMultiLineStringBodyIsScannedAsCode() {
        let sample = """
            let shader = \"\"\"
            float x = 1.0; // shader comment
            float y = 2.0;
            \"\"\"
            let plain = "kept // because a one-line literal IS understood"
            """
        let code = SourceText.codeOnly(sample)

        XCTAssertFalse(code.contains("shader comment"), """
            `SourceText.codeOnly` now keeps the body of a multi-line string literal. That may \
            well be the right change — but it is a CHANGE, and three things move with it in the \
            same commit (#456):
              1. the "WHAT IT DOES NOT HANDLE" block in `Tests/CISmoke/SourceText.swift`,
              2. test 2 below, whose expected set becomes empty,
              3. a re-measurement of the four guards that scan `Views/MetalBioView.swift` —
                 its 337-line Metal shader is a `"""` literal whose `//` are real comments, so
                 keeping them hands shader PROSE to a flash-safety scan as if it were shader code.
            """)
        XCTAssertTrue(code.contains("float y = 2.0;"), """
            Non-comment text inside the multi-line body vanished, so the scanner is not merely \
            unaware of `\"\"\"` — it is losing code. Re-derive before trusting any guard that \
            scans a file with a multi-line literal.
            """)
        XCTAssertTrue(code.contains("kept // because a one-line literal IS understood"), """
            A `//` inside an ORDINARY one-line string literal is being treated as a comment. \
            That case IS handled today and is the premise of the whole `SourceText` migration \
            (#477, the WeatherKit attribution URL in `EchoelStudioView.swift`). If this fails, \
            the regression is much larger than the `\"\"\"` gap this file is about.
            """)
    }

    // MARK: - 2. The census: exactly one file is affected

    /// Walks `Sources/` and compares the shipped scanner against a `"""`-aware reference.
    ///
    /// #454: the run is required to have LOOKED at something — a walk that found no files, or no
    /// multi-line literals at all, would otherwise pass by examining nothing.
    func testExactlyOneScannedSourceDiffersUnderATripleQuoteAwareScanner() throws {
        let sources = try Self.sourcesDirectory()
        var swiftFiles: [URL] = []
        if let walker = FileManager.default.enumerator(at: sources,
                                                       includingPropertiesForKeys: nil) {
            for case let url as URL in walker where url.pathExtension == "swift" {
                swiftFiles.append(url)
            }
        }
        XCTAssertGreaterThan(swiftFiles.count, 300, """
            Only \(swiftFiles.count) Swift files found under Sources/ — the walk is looking at \
            the wrong place, so a green result below proves nothing (#454).
            """)

        var carryTripleQuote: [String] = []
        var differ: [String] = []
        for url in swiftFiles {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard text.contains("\"\"\"") else { continue }
            carryTripleQuote.append(url.lastPathComponent)
            if SourceText.codeOnly(text) != Self.tripleQuoteAwareCodeOnly(text) {
                differ.append(url.lastPathComponent)
            }
        }

        XCTAssertGreaterThanOrEqual(carryTripleQuote.count, 1, """
            No source file carries a multi-line string literal at all, so the comparison below \
            examined nothing. Measured 2026-08-20: 9 of 368 do. Re-anchor (#454).
            """)
        XCTAssertEqual(differ.sorted(), ["MetalBioView.swift"], """
            The set of sources where the shipped scanner and a `\"\"\"`-aware one disagree is \
            now \(differ.sorted()) — measured 2026-08-20 it was exactly ["MetalBioView.swift"].

            This is NOT a failure to silence, and NOT a reason to change `SourceText.codeOnly` \
            on its own (#364). It is the one question this file exists to ask a human:

              · A file LEFT the set → someone taught the scanner about `\"\"\"`, or the shader \
                literal moved. Update this expectation and the doc block in `SourceText.swift`.
              · A file JOINED the set → a source now holds a multi-line literal whose body the \
                guards read as code. Ask whether any guard SCANS that file
                (`grep -l <name> Tests/CISmoke/*.swift`) and whether its needles sit after a \
                `//` inside the literal. For MetalBioView the answer was "four guards, 36 \
                needles, zero affected"; for the newcomer it has to be measured, not assumed.
            """)
    }

    // MARK: - 3. The limitation must stay written down

    /// `SourceText.swift` lists what it does not handle. The biggest case was missing.
    func testTheScannerDocumentsThatItDoesNotKnowATripleQuote() throws {
        let doc = try Self.read("SourceText.swift")
        XCTAssertTrue(doc.contains("\"\"\"") && doc.lowercased().contains("multi-line"), """
            The "WHAT IT DOES NOT HANDLE" block in SourceText.swift no longer names multi-line \
            string literals. That block exists "so nobody assumes more than it does" — and the \
            case it omitted for its whole life is the one where 337 lines of one scanned file \
            are read as code. A limitation that is real and unwritten is worse than one that is \
            written down, because nothing can contradict it (#167's "NICHT löschen" lesson).
            """)
        XCTAssertTrue(doc.contains("Everything in `text` that the compiler would see"), """
            The doc sentence this file measures against is gone. If `codeOnly`'s contract was \
            reworded, re-read test 1 — its whole point is that the old sentence overstated the \
            type for a `\"\"\"` body.
            """)
    }

    // MARK: - Helpers

    /// A reference scanner that DOES understand `"""`, used only for contrast in test 2.
    ///
    /// ⛔ Never call this to make an assertion about source CONTENT. It exists to be different
    /// from `SourceText.codeOnly` — that difference is the measurement — and a guard that
    /// scanned with it would be asserting against a shape the bundle does not ship (#453).
    private static func tripleQuoteAwareCodeOnly(_ text: String) -> String {
        var out: [String] = []
        var inBlock = false
        var inMulti = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = Array(raw)
            var kept = ""
            var i = 0
            var block = inBlock
            var multi = inMulti
            var inString = false
            while i < line.count {
                let c = line[i]
                let hasPair = i + 1 < line.count
                let opensTriple = i + 2 < line.count
                    && c == "\"" && line[i + 1] == "\"" && line[i + 2] == "\""
                if multi {
                    if opensTriple { multi = false; kept += "\"\"\""; i += 3; continue }
                    if c == "\\", hasPair { kept.append(c); kept.append(line[i + 1]); i += 2; continue }
                    kept.append(c); i += 1; continue
                }
                if block {
                    if hasPair, c == "*", line[i + 1] == "/" { block = false; i += 2 } else { i += 1 }
                    continue
                }
                if inString {
                    if c == "\\", hasPair { kept.append(c); kept.append(line[i + 1]); i += 2; continue }
                    if c == "\"" { inString = false }
                    kept.append(c); i += 1; continue
                }
                if opensTriple { multi = true; kept += "\"\"\""; i += 3; continue }
                if hasPair, c == "/", line[i + 1] == "/" { break }
                if hasPair, c == "/", line[i + 1] == "*" { block = true; i += 2; continue }
                if c == "\"" { inString = true }
                kept.append(c); i += 1
            }
            inBlock = block
            inMulti = multi
            out.append(kept)
        }
        return out.joined(separator: "\n")
    }

    private static func sourcesDirectory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("Source tree not reachable from the test bundle.")
        }
        return sources
    }

    private static func read(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("\(name) is not in Tests/CISmoke — this guard names a file that is gone.")
            throw XCTSkip("\(name) missing")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
