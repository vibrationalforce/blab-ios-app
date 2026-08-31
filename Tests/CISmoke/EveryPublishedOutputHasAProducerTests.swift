// EveryPublishedOutputHasAProducerTests.swift
// Echoel — a value announced as an OUTPUT must be computed somewhere. #925.
//
// WHAT WAS WRONG. `CameraAnalyzer` heads a block `// MARK: - Published Output` and declares
// eleven values under it. Ten of them are written somewhere in that same file. The eleventh,
// `var dominantHue: Float = 180`, documented as "Average hue (0–360)", occurred **exactly once
// in the whole repository** — that declaration. No assignment, no reader, in `Sources/` or in
// `Tests/`. It was permanently 180, i.e. cyan, and nothing could ever move it.
//
// ⭐ WHY THAT IS WORSE THAN AN ABSENT FIELD, which is the whole reason this guard exists. The
// block is a real surface: `CameraRPPGBioPublisher` reads `brightness` and `redChannel` from it
// on the wash-out path. So a session wiring the visual palette to camera colour would open this
// class, find `dominantHue` sitting between two values that ARE live, bind it, and ship a
// permanently-cyan feature that looks wired from every angle — producer present, consumer
// present, doc present, and a constant on the wire. That is the `.eegBurst` shape (an OSC
// address with no producer, which CLAUDE.md says no integrator may wait on) one size smaller,
// and it is inside the class rather than on a wire, where nothing was watching.
//
// ⚠️ THE LAW IS "HAS A PRODUCER", NOT "THIS NAME IS ABSENT" (#364). A needle on the absence of
// `dominantHue` would forbid correct work: camera hue driving the palette is a reasonable
// FEATURE, and the day someone builds it — producer and reader arriving together — an absence
// needle goes red on a correct tree. This guard asks each declared output for an assignment, so
// that day it stays green. It has no opinion about which outputs exist.
//
// ⚠️ WHAT THE SCAN CAN AND CANNOT SEE, stated before the claim (§1 of this directory's law).
// This is a SOURCE-TEXT SCAN. It reads assignment SHAPES — `name = `, `self.name = `,
// `name.append(`, `name.removeAll` at the start of a stripped line. A property written only
// through some other path (a `withMutation`, a `KeyPath`-based setter, an `inout` hand-off)
// would read as unassigned and this guard would be wrong about it. No output in this file is
// written that way today; if one ever is, widen the shapes rather than exempting the name.
// It also cannot say whether the value is CORRECT, or whether anyone reads it — only that
// something computes it.
//
// ⚠️ THE BLOCK BOUNDARY IS READ FROM RAW TEXT, THE DECLARATIONS FROM STRIPPED TEXT, and both
// halves are necessary. `// MARK: - Published Output` is a COMMENT, so it does not survive
// `SourceText.codeOnly` — anchoring on it after stripping would find nothing and the whole file
// would pass vacuously. Conversely the declarations must come from stripped text, or the ⛔ note
// that now stands where `dominantHue` was — it quotes the removed declaration verbatim, on
// purpose, so the next reader knows what was there — would be counted as a live output and this
// guard would report the very field it just retired. `codeOnly` preserves line count, which is
// what lets the two views be indexed against each other.
//
// ⚠️ SCOPE IS ONE FILE, DELIBERATELY. "Every `@Observable` output in `Sources/` has a producer"
// is the general law and it is not enforceable here without false alarms: plenty of legitimate
// state is written by a cross-file setter (`doorless-state.py` calls that its MASKED section and
// refuses to accuse). `CameraAnalyzer` earns a guard because it declares its outputs under an
// explicit heading — a self-declared contract this scan can hold it to.
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
        // rots silently (#903). Ten stand today; eight is comfortably below any tree that
        // still has this surface, and well above the zero that a vacuous claim 1 would need.
        XCTAssertGreaterThanOrEqual(outputs.count, 8, """
            The "\(Self.heading)" block now declares only \(outputs.count) value(s). Claim 1 \
            asks every declared output for a producer, so a block that has been emptied or \
            renamed makes it pass while proving nothing.
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

    /// The outputs declared between the heading and the next `MARK:`, plus the whole file's
    /// comment-stripped lines (trimmed) so the caller can scan for assignments.
    ///
    /// Boundaries come from RAW text because the heading is a comment; declarations come from
    /// STRIPPED text so a commented-out declaration is not counted. See the file header.
    private func publishedOutputs() throws -> ([Output], [String]) {
        let raw = try rawText(Self.analyzer)
        let rawLines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let codeLines = SourceText.codeOnly(raw)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // `SourceText.codeOnly` preserves line count. If that ever stops being true the two
        // views cannot be indexed against each other and every verdict below is meaningless,
        // so it is asserted rather than assumed.
        XCTAssertEqual(rawLines.count, codeLines.count,
                       "SourceText.codeOnly no longer preserves line count; this scan indexes "
                       + "raw boundaries against stripped content and cannot work without it.")

        guard let start = rawLines.firstIndex(where: { $0.contains(Self.heading) }) else {
            XCTFail("""
                \(Self.analyzer) no longer carries the line "\(Self.heading)". The block is this \
                class's self-declared contract and the anchor for the whole guard.
                """)
            return ([], [])
        }
        let end = rawLines[(start + 1)...].firstIndex(where: { $0.contains("MARK:") })
            ?? rawLines.endIndex

        var outputs: [Output] = []
        for index in (start + 1)..<end {
            let line = codeLines[index].trimmingCharacters(in: .whitespaces)
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
