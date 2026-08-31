// TheSliceHelperHasTwoSemanticsTests.swift
// Echoel — ten private helpers share one name and two different meanings. #926.
//
// WHAT THIS RECORDS. Ten files in this bundle declare a private `slice(…, from:, to:)` to cut a
// member's body out of a source file. Measured (comments stripped, brace-matched bodies), they
// fall into **two families that do different things**:
//
//   · EXCLUDES-marker (4 files) — `let rest = text[start.upperBound...]` … the returned text
//     starts AFTER the `from` marker.
//   · INCLUDES-marker (6 files) — `String(code[start.lowerBound..<end.lowerBound])` … the
//     returned text STARTS WITH the `from` marker.
//
// Both stop before the `to` marker, so the families differ by exactly the opening marker.
// Driven on a fixture below, not argued: for the same input they return different strings, and
// a needle counting anything that occurs in the marker text differs by one between them.
//
// ⚠️ LATENT, NOT LIVE, AND SAYING SO IS PART OF THE FINDING. I scanned every `slice(` binding in
// the six INCLUDES-marker files for a needle whose literal occurs inside its own `from` marker:
// **zero today**. So nothing is currently wrong, and this guard fixes no bug. What it stops is
// the drift getting worse — and the trap is real the moment anyone moves an assertion between
// two guard files, which this repo does routinely (§4 of this directory's law is entirely about
// prose and guards moving between homes). Two spellings of one operation is the #416 defect
// "whether or not they agree today"; here they do not even agree today.
//
// ⚠️ THIS IS NOT A MIGRATION AND MUST NOT TURN INTO ONE (#364). Folding ten helpers into one
// shared definition is the right end state — it is what `SourceText.codeOnly` is for the
// stripper — but that touches ten files and changes the meaning of four of them, so it is a
// migration with a founder-sized blast radius, not a Ralph slice. This guard is deliberately
// written so the migration stays GREEN: it asks each declaration to be CLASSIFIABLE, never for
// a particular family, a particular count, or a particular file list. Zero declarations (all
// callers moved to a shared helper) passes. A new file adopting either family passes. Only a
// THIRD, differently-behaving spelling goes red.
//
// ⚠️ THE CLASSIFIER IS RENAME-PROOF ON PURPOSE, and that decided its shape. Comparing the
// normalized body TEXT reports three distinct bodies, not two: `TheMarkIsTheSameMarkTests`
// spells the EXCLUDES-marker family with `open`/`after`/`close` instead of `start`/`rest`/`end`.
// Pinning text would therefore (a) miscount the families and (b) go red the day someone renames
// a local — a value a reader may reasonably change, which is exactly what #364 forbids pinning.
// So the classifier keys on the RANGE ARITHMETIC, which is the semantics: a body containing
// `.lowerBound..<` returns from the marker's start (INCLUDES); one containing `.upperBound...`
// returns from after it (EXCLUDES). Verified: that rule sorts all ten declarations, including
// the renamed one, into 4 + 6 with none left over.
//
// ⚠️ THIS FILE ADDS THREE PINS THAT `count-pins.py` REPORTS AS UNRESOLVED, and they are the
// harmless kind — said here so nobody spends a cycle chasing them. The tool cannot bind
// `included`/`excluded`/`missed` to a path, correctly, because they are not source text at all:
// they are slices of a FIXTURE string declared three lines above each assertion. A source pin
// rots when the code changes underneath it (#903/#904); a fixture pin cannot, because its input
// is in the same method. The tool refusing to guess is it working, not it failing.
//
// ⚠️ WHAT THE BEHAVIOURAL CLAIMS DO AND DO NOT PROVE — state the limit before the claim (§1).
// Claims 2 and 3 drive LOCAL reimplementations of the two families, because the shipped helpers
// are `private` on ten different `XCTestCase`s and no test can call them. So they pin the
// DOCUMENTED semantics, not the files. The link between the two is claim 1: if a shipped body
// stops matching its family's arithmetic, claim 1 goes red. Neither claim can catch a body that
// keeps the arithmetic and changes something else.
//
// ⚠️ HONEST GRADING (#433/#464/#486). **ZERO regressions. All four claims are GREEN on the
// parent tree**, and booking any of them as a finding would be the flattering direction this
// directory names by name. This is a REGISTER guard: the split exists, it is not written down
// anywhere, and an undocumented split is what lets the next author pick a family by copying
// whichever neighbour they opened first. Claim 4 exists so claim 1 cannot pass by finding
// nothing (#367) while surviving the migration that would legitimately empty it.
//
// ⛔ AND THE FIRST DRAFT OF CLAIM 1 WAS RED ON A CORRECT TREE — its scan matched its own needle
// literal, because `SourceText.codeOnly` leaves string literals standing. Found by DRIVING the
// claim, never by reading it; the repair and the reason are at `sliceDeclarations`. Worth
// stating up here because it is the third needle collision in three slices (#921b a bare type
// name matching its own declaration, #924 a label colliding with two unrelated rows, this one a
// scanner reading itself) and they share one cause: **the needle was chosen from what the thing
// is CALLED rather than from where it can only OCCUR.**

import Foundation
import XCTest
@testable import Echoelmusic

final class TheSliceHelperHasTwoSemanticsTests: XCTestCase {

    private enum Family: String {
        /// Returns the text AFTER the `from` marker.
        case excludesMarker = "EXCLUDES-marker"
        /// Returns the text STARTING WITH the `from` marker.
        case includesMarker = "INCLUDES-marker"
    }

    private struct Declaration {
        let file: String
        let family: Family?
    }

    // MARK: - the law

    func testEverySliceHelperMatchesOneOfTheTwoRecordedSemantics() throws {
        let declarations = try sliceDeclarations()
        let unclassified = declarations.filter { $0.family == nil }.map(\.file)
        XCTAssertEqual(unclassified.sorted(), [String](), """
            \(unclassified.count) private `slice` helper(s) no longer match either recorded \
            family: \(unclassified.sorted().joined(separator: ", ")). Ten files share this name \
            and already mean two different things by it — one keeps the `from` marker, one drops \
            it — so a THIRD meaning under the same name is how an assertion moved between guard \
            files silently changes its verdict. Either write the new body with one of the two \
            range forms (`.lowerBound..<` to keep the marker, `.upperBound...` to drop it), or \
            give the new behaviour its own NAME. This claim never asks for a particular family, \
            count or file list, so adopting either one — or folding them all into a shared \
            helper — stays green (#364).
            """)
    }

    // MARK: - counterweights: the two families really do differ, and both fail silently

    /// Without this, claim 1 is fussing over spelling. This is the content (#343): the two
    /// families return different text for the same input, differing by exactly the marker.
    func testTheTwoFamiliesReturnDifferentText() {
        let text = "private func moodKnob(x: Int) -> View {\n    let a = 1\n    knob(a)\n    }\n"
        let marker = "private func moodKnob"
        let terminator = "\n    }"

        let excluded = excludesMarkerSlice(text, from: marker, to: terminator)
        let included = includesMarkerSlice(text, from: marker, to: terminator)

        XCTAssertNotEqual(excluded, included,
                          "The two recorded families no longer differ — re-derive the split.")
        XCTAssertEqual(included, marker + excluded, """
            The two families no longer differ by exactly the `from` marker. That single \
            difference is the whole hazard: a needle counting anything that occurs in the marker \
            text — a function name, `private func`, a label — reads one higher in the \
            INCLUDES-marker family than in the EXCLUDES-marker one, for identical source.
            """)
        XCTAssertEqual(included.components(separatedBy: "moodKnob").count - 1, 1)
        XCTAssertEqual(excluded.components(separatedBy: "moodKnob").count - 1, 0, """
            The EXCLUDES-marker family now keeps the marker text. If both families count the \
            marker the hazard is gone — and so is the reason for this file; retire it rather \
            than weakening the claim.
            """)
    }

    /// The shared silent-failure mode, and the reason a mis-anchored slice does not announce
    /// itself: on a miss BOTH families return `""`. A `contains` assertion then fails with a
    /// message about the wrong thing, and a `count == 0` assertion passes having proven nothing
    /// — the #367 shape, built into the helper rather than into any one guard.
    func testBothFamiliesReturnEmptyOnAMissedAnchor() {
        let text = "private func moodKnob() {\n    knob()\n    }\n"

        // ⚠️ Written out rather than looped over `[(name, function)]` pairs: an unapplied
        // method reference in an array literal is the kind of inference the compiler here
        // would have to settle, and there is no compiler here (§0). Four plain assertions.
        XCTAssertEqual(excludesMarkerSlice(text, from: "no such marker", to: "\n    }"), "",
                       "EXCLUDES-marker no longer returns \"\" for a missing `from` anchor.")
        XCTAssertEqual(excludesMarkerSlice(text, from: "private func moodKnob", to: "no such end"),
                       "",
                       "EXCLUDES-marker no longer returns \"\" for a missing `to` anchor.")
        XCTAssertEqual(includesMarkerSlice(text, from: "no such marker", to: "\n    }"), "",
                       "INCLUDES-marker no longer returns \"\" for a missing `from` anchor.")
        XCTAssertEqual(includesMarkerSlice(text, from: "private func moodKnob", to: "no such end"),
                       "",
                       "INCLUDES-marker no longer returns \"\" for a missing `to` anchor.")

        // The consequence, asserted rather than described: a count over an empty slice is 0,
        // so `XCTAssertEqual(count, 0)` on a mis-anchored slice is green having proven nothing.
        // Any guard whose expectation is zero must anchor-check first.
        let missed = excludesMarkerSlice(text, from: "no such marker", to: "\n    }")
        XCTAssertEqual(missed.components(separatedBy: "knob").count - 1, 0, """
            A count over a MISSED slice is no longer 0 — if that ever changes, the vacuous-green             hazard this claim records has changed shape and the wording above must follow.
            """)
    }

    /// #367 protection: claim 1 must not pass by finding nothing — while still surviving the
    /// migration that would legitimately leave nothing to find.
    ///
    /// ⚠️ THE CALL COUNT IS AN INDICATOR, NOT A CENSUS, and it is used only as one side of a
    /// disjunction so that cannot mislead. It counts the substring `slice(` in stripped source,
    /// which includes the needle literals in THIS file (the stripper leaves string literals
    /// standing — the same property that made this scan match itself once, see
    /// `sliceDeclarations`). No number is pinned, so nothing here can rot (#903).
    func testTheScanFindsTheDeclarationsThatTheCallSitesNeed() throws {
        let declarations = try sliceDeclarations()
        var callSites = 0
        for file in try filesUnderCISmoke() {
            let code = SourceText.codeOnly(try rawText(file))
            callSites += code.components(separatedBy: "slice(").count - 1
        }
        XCTAssertTrue(!declarations.isEmpty || callSites == 0, """
            This bundle contains \(callSites) `slice(` call site(s) and \
            \(declarations.count) declaration(s) the scan could read. Claim 1 inspects \
            declarations, so zero of them with calls still present means the extractor stopped \
            matching how the helper is written — claim 1 would then be green having read \
            nothing. Zero declarations AND zero calls is the migrated tree and is fine.
            """)
    }

    // MARK: - the two families, reimplemented locally (see the header for what that limits)

    private func excludesMarkerSlice(_ text: String, from: String, to: String) -> String {
        guard let start = text.range(of: from) else { return "" }
        let rest = text[start.upperBound...]
        guard let end = rest.range(of: to) else { return "" }
        return String(rest[..<end.lowerBound])
    }

    private func includesMarkerSlice(_ text: String, from: String, to: String) -> String {
        guard let start = text.range(of: from),
              let end = text.range(of: to, range: start.upperBound..<text.endIndex) else {
            return ""
        }
        return String(text[start.lowerBound..<end.lowerBound])
    }

    // MARK: - helpers

    /// Every `func slice(` DECLARATION in this bundle, classified by its range arithmetic.
    ///
    /// ⛔ THE FIRST DRAFT MATCHED ITS OWN NEEDLE AND WAS RED ON A CORRECT TREE — caught by
    /// driving the claim, not by reading it. Its header claimed the scan cannot read itself
    /// because this file's two reimplementations are named `excludesMarkerSlice` /
    /// `includesMarkerSlice`, which is true of the METHOD NAMES and irrelevant: the literal
    /// `"func slice("` appears in the scanner below, and `SourceText.codeOnly` deliberately
    /// leaves STRING LITERALS standing. The scan therefore counted its own needle as an
    /// eleventh, unclassifiable declaration. That is #753 — a tool reading its own text as data
    /// — arriving through the one door the header had declared shut.
    ///
    /// ⭐ THE REPAIR IS A STRUCTURAL DISCRIMINATOR, NOT AN EXEMPTION FOR THIS FILE. A real
    /// declaration begins its line (modifiers only in front of it); the needle sits mid-line
    /// after `range(of: "`. Anchoring on the LINE keeps the scan honest about every file
    /// including this one, which an exclusion list would not (#408: anchor on something that
    /// occurs only at the intended site, and check that while WRITING the scan).
    private func sliceDeclarations() throws -> [Declaration] {
        var found: [Declaration] = []
        for file in try filesUnderCISmoke() {
            let code = SourceText.codeOnly(try rawText(file))
            var searchStart = code.startIndex
            while let match = code.range(of: "func slice(",
                                         range: searchStart..<code.endIndex) {
                searchStart = match.upperBound
                // Everything between the start of this LINE and the match must be modifiers
                // only. That is what separates a declaration from the needle literal.
                let lineStart = code[..<match.lowerBound].lastIndex(of: "\n")
                    .map { code.index(after: $0) } ?? code.startIndex
                guard isOnlyModifiers(String(code[lineStart..<match.lowerBound])) else { continue }
                guard let body = bracedBody(of: code, startingAt: match.upperBound) else {
                    found.append(Declaration(file: file, family: nil))
                    continue
                }
                found.append(Declaration(file: file, family: family(of: body)))
            }
        }
        return found
    }

    /// Whether the text in front of `func slice(` on its own line is modifiers and nothing else.
    private func isOnlyModifiers(_ head: String) -> Bool {
        let known: Set<String> = ["private", "fileprivate", "internal", "public",
                                  "static", "final", "class"]
        let words = head.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        return words.allSatisfy { known.contains($0) }
    }

    /// The range arithmetic IS the semantics; see the header for why the body text is not.
    private func family(of body: String) -> Family? {
        if body.contains(".lowerBound..<") { return .includesMarker }
        if body.contains(".upperBound...") { return .excludesMarker }
        return nil
    }

    /// The brace-matched body of the next `{ … }` at or after `index`.
    ///
    /// Brace matching rather than a line window, because this repo writes 30–40-line comment
    /// blocks and `SourceText.codeOnly` preserves line count, so any fixed window is unsound by
    /// construction (#408). The input is comment-stripped; string literals survive stripping, so
    /// a brace inside a literal would miscount — none of the ten bodies contains one, and an
    /// unbalanced walk returns nil, which claim 1 reports as unclassified rather than guessing.
    private func bracedBody(of code: String, startingAt index: String.Index) -> String? {
        guard let open = code.range(of: "{", range: index..<code.endIndex) else { return nil }
        var depth = 0
        var cursor = open.lowerBound
        while cursor < code.endIndex {
            if code[cursor] == "{" { depth += 1 }
            if code[cursor] == "}" {
                depth -= 1
                if depth == 0 {
                    return String(code[code.index(after: open.lowerBound)..<cursor])
                }
            }
            cursor = code.index(after: cursor)
        }
        return nil
    }

    private func filesUnderCISmoke() throws -> [String] {
        let directory = try repoRoot().appendingPathComponent("Tests/CISmoke")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        return names.filter { $0.hasSuffix(".swift") }
            .sorted()
            .map { "Tests/CISmoke/" + $0 }
    }

    private func rawText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        // ⚠️ ASSERT, DO NOT SKIP — a skip is not a pass (#454/#806).
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path),
                      "\(relativePath) is not present; a missing subject is a broken guard.")
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func repoRoot() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
