// EveryPublishedOutputHasAProducerTests.swift
// Echoel — a value announced as an OUTPUT must be computed somewhere. #925.
//
// WHAT WAS WRONG. `CameraAnalyzer` heads a block `// MARK: - Published Output` and declares
// thirteen values under it. Twelve of them are written somewhere in that same file. The
// thirteenth, `var dominantHue: Float = 180`, documented as "Average hue (0–360)", occurred
// **exactly once in the whole repository** — that declaration. No assignment, no reader, in
// `Sources/` or in `Tests/`. It was permanently 180, i.e. cyan, and nothing could ever move it.
//
// ⛔ THE FIRST DRAFT SAID "eleven values … ten of them are written" AND THAT WAS THE SCAN'S
// SUBSET REPORTED AS THE FILE'S CONTENT (#925b). The block holds thirteen `var`s; two of them —
// `@ObservationIgnored var beatTimes` and `@ObservationIgnored private(set) var rrSegments` —
// carry an attribute, and the first draft's prefix test ran against the trimmed line, so an
// attributed declaration was invisible to it. **That was not only a wrong number in prose: it
// was a coverage hole in the guard itself**, and the shape was already present in the very block
// being guarded, so `@ObservationIgnored var` is the natural next declaration here. Driven: an
// uncomputed `@ObservationIgnored var ghostHue` left all three claims GREEN — the guard silent
// on exactly the defect its name describes. `withoutLeadingAttributes` closes it; the parent
// tree now reports 13 declarations and the one orphan, and the worktree 12 and none.
//
// ⭐ WHY AN UNCOMPUTED OUTPUT IS WORSE THAN AN ABSENT FIELD, which is the whole reason this
// guard exists. The block is a real surface: `CameraRPPGBioPublisher` reads `brightness` and
// `redChannel` from it on the wash-out path. So a session wiring the visual palette to camera
// colour would open this class, find `dominantHue` sitting between two values that ARE live,
// bind it, and ship a permanently-cyan feature that looks wired from every angle — producer
// present, consumer present, doc present, and a constant on the wire. That is the `.eegBurst`
// shape (an OSC address with no producer, which CLAUDE.md says no integrator may wait on) one
// size smaller, and it is inside the class rather than on a wire, where nothing was watching.
//
// ⚠️ THE LAW IS "HAS A PRODUCER", NOT "THIS NAME IS ABSENT" (#364). A needle on the absence of
// `dominantHue` would forbid correct work: camera hue driving the palette is a reasonable
// FEATURE, and the day someone builds it — producer and reader arriving together — an absence
// needle goes red on a correct tree. This guard asks each declared output for an assignment, so
// that day it stays green. It has no opinion about which outputs exist. Measured, not asserted:
// re-adding the declaration TOGETHER with a real `dominantHue = 42` leaves claim 1 green.
//
// ⚠️ WHAT THE SCAN CAN AND CANNOT SEE, stated before the claim (§1 of this directory's law).
// This is a SOURCE-TEXT SCAN, and it has two blind spots, both narrow and both named here
// rather than discovered later:
//   · ASSIGNMENT shapes. It reads `name = `, `self.name = `, `name.append(`, `name.removeAll`
//     at the start of a stripped line. A property written only through some other path (a
//     `withMutation`, a `KeyPath`-based setter, an `inout` hand-off) would read as unassigned.
//     No output in this file is written that way today; if one ever is, widen the shapes rather
//     than exempting the name.
//   · DECLARATION shapes. `var`, `private(set) var`, `public var`, each optionally preceded by
//     attributes, which `withoutLeadingAttributes` removes. A declaration in some other form
//     (a computed property, a `let`) is out of scope by design — neither can be the defect this
//     guard is about, because neither is a mutable value waiting for a producer.
// It also cannot say whether the value is CORRECT, or whether anyone reads it — only that
// something computes it.
//
// ⚠️ THE BLOCK BOUNDARY IS READ FROM RAW TEXT, THE DECLARATIONS FROM STRIPPED TEXT.
// `// MARK: - Published Output` is a COMMENT, so it does not survive `SourceText.codeOnly` —
// anchoring on it after stripping would find nothing and the whole file would pass vacuously.
// That half is load-bearing and is the reason for the split.
//   ⛔ THE STRIPPING HALF IS **PROPHYLAKTISCH (0 of 4 verdicts flip)**, and the first draft
//   claimed otherwise with an example that does not work (#925b). It said the ⛔ note now
//   standing where `dominantHue` was — which quotes the removed declaration verbatim, on
//   purpose — would otherwise be counted as a live output. It would not: trimmed, that line
//   starts with `//`, so the `var ` prefix test misses it in RAW text too. Driven on both
//   trees, raw-declarations and stripped-declarations give identical verdicts.
//   ⭐ The shape that IS caught only by stripping is a `/* … */` block whose inner line reads
//   `var foo = 1` — raw, that line begins with `var `; stripped, `codeOnly` blanks it. Verified
//   on a fixture. So the design stands and only its stated reason was wrong, which is the
//   #367 mirror one level up: an assertion green for a reason other than the one it gives.
// `codeOnly` preserves line count, and that is what lets the two views be indexed against each
// other — asserted below rather than assumed.
//
// ⚠️ SCOPE IS ONE FILE, DELIBERATELY, AND A SCRIPT ALREADY COVERS THE GENERAL LAW.
// `scripts/doorless-state.py` scans all of `Sources/` for settable class state with no writer
// and would have listed `dominantHue`; do not build a third instrument for that (#416). What it
// cannot do is BLOCK — it is a script nobody runs on a push. This guard puts the one block that
// declares its outputs under an explicit heading into the blocking bundle. The general form
// ("every `@Observable` output in `Sources/` has a producer") stays unenforceable here without
// false alarms: much legitimate state is written by a cross-file setter, which is why
// `doorless-state.py` has a MASKED section and explicitly refuses to accuse.
//
// ⚠️ HONEST GRADING (#433/#464/#486). This file compiles against the parent tree, so every claim
// has a verdict there. **ONE is a regression** — claim 1, red on the parent naming `dominantHue`,
// which is the finding. **Two are counterweights** (#343), green on both: the anchor must still
// exist and still hold outputs (without it claim 1 passes by finding nothing — the #367 failure
// this file would otherwise be prone to), and the block must still be consumed elsewhere, which
// is what makes it an OUTPUT surface rather than a scratch pad and what makes the law worth
// enforcing at all.
//
// ⚠️ WHAT NO TEST HERE CAN SAY: whether the camera should publish a hue. That is a founder
// question with a consumer attached; this slice only removes a field that answered it silently
// with "yes, and the answer is always cyan".

import Foundation
import XCTest
@testable import Echoelmusic

final class EveryPublishedOutputHasAProducerTests: XCTestCase {

    private static let analyzer = "Sources/Echoelmusic/Video/CameraAnalyzer.swift"
    private static let publisher = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"
    private static let heading = "// MARK: - Published Output"

    /// One declared output: its name and the 1-based line its declaration sits on.
    private struct Output {
        let name: String
        let declarationLine: Int
    }

    // MARK: - the law

    func testEveryDeclaredOutputIsWrittenSomewhereInItsOwnFile() throws {
        let (outputs, strippedLines) = try publishedOutputs()
        let orphans = outputs
            .filter { !isAssigned($0, in: strippedLines) }
            .map(\.name)
        XCTAssertEqual(orphans.sorted(), [String](), """
            \(Self.analyzer) declares \(orphans.count) value(s) under "\(Self.heading)" that \
            nothing in that file ever writes: \(orphans.sorted().joined(separator: ", ")). \
            A value announced as an output and never computed is a constant wearing a \
            measurement's name — the next reader binds it and ships a feature that cannot move. \
            Either compute it, or remove it and leave a note saying why (#925). This claim asks \
            for a PRODUCER and never for a particular name's absence, so building the real \
            producer is the way to make it green (#364).
            """)
    }

    // MARK: - counterweights: the anchor, and the surface the law protects

    /// Without this, claim 1 passes by finding nothing — the #367 failure where an assertion is
    /// green for a reason other than the one its message states. Deleting the heading, or the
    /// declarations under it, must be a red, not a quiet pass.
    func testTheOutputBlockStillExistsAndStillDeclaresOutputs() throws {
        let (outputs, _) = try publishedOutputs()
        // A floor, not a pin: the exact count is a date, and a count pin that nobody updates
        // rots silently (#903). Twelve stand today; eight is comfortably below any tree that
        // still has this surface, and well above the zero that a vacuous claim 1 would need.
        XCTAssertGreaterThanOrEqual(outputs.count, 8, """
            The "\(Self.heading)" block now declares only \(outputs.count) value(s). Claim 1 \
            asks every declared output for a producer, so a block that has been emptied, \
            renamed, or truncated by a stray heading makes it pass while proving nothing.
            """)
    }

    func testTheOutputBlockIsActuallyConsumedElsewhere() throws {
        let code = SourceText.codeOnly(try rawText(Self.publisher))
        XCTAssertTrue(code.contains("analyzer.brightness"), """
            \(Self.publisher) no longer reads `analyzer.brightness`. That read (with \
            `redChannel`, on the wash-out path) is what makes this a published OUTPUT surface \
            rather than internal scratch state — and therefore what makes an uncomputed value \
            in it a trap for the next reader instead of a harmless unused field.
            """)
        XCTAssertTrue(code.contains("analyzer.redChannel"), """
            \(Self.publisher) no longer reads `analyzer.redChannel` — see the message above; \
            the two are read together and either one going means the surface has changed owner.
            """)
    }

    // MARK: - helpers

    /// The outputs declared between the heading and the next MARK, plus the whole file's
    /// comment-stripped lines (trimmed) so the caller can scan for assignments.
    ///
    /// Boundaries come from RAW text because the heading is a comment; declarations come from
    /// STRIPPED text. See the file header for which half is load-bearing and which is not.
    private func publishedOutputs() throws -> ([Output], [String]) {
        let raw = try rawText(Self.analyzer)
        let rawLines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let codeLines = SourceText.codeOnly(raw)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // `SourceText.codeOnly` preserves line count. If that ever stops being true the two
        // views cannot be indexed against each other and every verdict below is meaningless.
        // ⚠️ A `guard`, not an `XCTAssertEqual`: an assertion RECORDS and CONTINUES, and the
        // next loop then indexes `codeLines` with a bound taken from `rawLines` — an
        // out-of-range crash in the runner instead of the clean red this message promises.
        guard rawLines.count == codeLines.count else {
            XCTFail("""
                SourceText.codeOnly no longer preserves line count (\(rawLines.count) raw vs \
                \(codeLines.count) stripped); this scan indexes raw boundaries against stripped \
                content and cannot work without it.
                """)
            return ([], [])
        }

        guard let start = rawLines.firstIndex(where: { $0.contains(Self.heading) }) else {
            XCTFail("""
                \(Self.analyzer) no longer carries the line "\(Self.heading)". The block is this \
                class's self-declared contract and the anchor for the whole guard.
                """)
            return ([], [])
        }
        // ⚠️ `hasPrefix("// MARK:")` on the TRIMMED line, never `contains("MARK:")` (#925b).
        // PROPHYLAKTISCH, and labelled as such: all twelve "MARK:" occurrences in the scanned
        // file are real headings today, so the two forms pick the same boundary and no verdict
        // flips. It is tightened anyway because the failure mode is SILENT — a comment inside
        // the block that merely MENTIONS a heading would truncate it, and every output below
        // the mention would leave coverage with nothing going red. This repo writes 30–40-line
        // comment blocks that discuss their own structure; that mention is a matter of time.
        let end = rawLines[(start + 1)...]
            .firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("// MARK:") })
            ?? rawLines.endIndex

        var outputs: [Output] = []
        for index in (start + 1)..<end {
            let line = withoutLeadingAttributes(
                codeLines[index].trimmingCharacters(in: .whitespaces))
            for prefix in ["var ", "private(set) var ", "public var "] where line.hasPrefix(prefix) {
                let rest = line.dropFirst(prefix.count)
                let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                if !name.isEmpty {
                    outputs.append(Output(name: String(name), declarationLine: index + 1))
                }
                break
            }
        }
        return (outputs, codeLines.map { $0.trimmingCharacters(in: .whitespaces) })
    }

    /// Drop any leading `@Attribute` / `@Attribute(args)` run from a trimmed declaration line.
    ///
    /// Two of this block's declarations carry `@ObservationIgnored`, so without this the prefix
    /// test misses them entirely — the coverage hole #925b closed. The paren depth is tracked so
    /// an attribute whose argument list contains spaces (`@available(iOS 17, *)`) is consumed as
    /// one token rather than cutting at the first space inside it.
    private func withoutLeadingAttributes(_ line: String) -> String {
        var rest = Substring(line)
        while rest.hasPrefix("@") {
            var index = rest.index(after: rest.startIndex)
            var depth = 0
            while index < rest.endIndex {
                let character = rest[index]
                if character == "(" { depth += 1 }
                if character == ")" { depth -= 1 }
                if character == " ", depth == 0 { break }
                index = rest.index(after: index)
            }
            rest = rest[index...].drop(while: { $0 == " " })
        }
        return String(rest)
    }

    /// Whether any line other than the declaration writes this output.
    private func isAssigned(_ output: Output, in lines: [String]) -> Bool {
        for (zeroBased, line) in lines.enumerated() where zeroBased + 1 != output.declarationLine {
            for receiver in ["", "self."] {
                let base = receiver + output.name
                if line.hasPrefix(base + " = ")
                    || line.hasPrefix(base + ".append(")
                    || line.hasPrefix(base + ".removeAll") {
                    return true
                }
            }
        }
        return false
    }

    private func rawText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        // ⚠️ ASSERT, DO NOT SKIP. A guard that skips when its subject is missing reports a
        // green it did not earn — a skip is not a pass (#454/#806), and #921b shipped exactly
        // that shape before the review caught it. If either file has moved, this guard is
        // broken and must say so.
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), """
            \(relativePath) is not present. This guard inspects that file's source text; a \
            missing subject is a broken guard, never a pass.
            """)
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func repoRoot() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
