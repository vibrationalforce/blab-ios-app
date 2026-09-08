// TheBioVisualFieldsSayTheyAreDeadTests.swift
// Echoel — `BioVisualParams`' four consumerless fields, in the BLOCKING bundle.
//
// #1131. `BioVisualParams` is the ONE pure bio→visual mapping and it has six fields.
// **Exactly one of them is read by anything.** #1116 measured that and took the claim back
// on `hue` — and left the identical claim standing on `complexity`, `spread` and
// `intensity`, whose docs went on describing live mappings in the present tense
// ("HRV drives ring count", "the figure expands on the inhale", "coherence makes it
// fuller"). That is the #496 shape exactly: one channel corrected, its neighbours not,
// because only the corrected one had been asked about.
//
// ⭐ THE ONE THAT COSTS SOMETHING IS `complexity`. It is the app's ONLY HRV→picture path.
// The body has four measured channels; the SOUND uses all four (`hrvForSound` → brightness),
// and the picture receives three — heart rate via `pulseHz`, breath and coherence via the
// shader's own terms. HRV's single route into the picture ends in a field nothing reads.
// This commit does not wire it: `BioUniforms` and the MSL `Uniforms` are hand-mirrored by
// BYTE LAYOUT (99 fields, no compiler check, #1119), so adding a channel is its own slice
// with its own hazard. Telling the truth first is what makes that slice decidable.
//
// ⚠️ THE COUNTERWEIGHT IS AS IMPORTANT AS THE FINDING, and claim 3 exists for it. "This
// field is dead" must never be read as "breath/coherence do not reach the picture" — they
// do, through `update(…)`'s own arguments and the shader's own terms. Overstating a
// retraction is the mirror image of the overclaim it retracts; #1130 had to correct exactly
// that shape on the other side (an argument that named the wrong row).
//
// ⚠️ THIS GUARD FORBIDS NOTHING (#364). Wiring any of the four is welcome and makes claim 1
// red on purpose — the message then names the doc to pull in the same commit.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBioVisualFieldsSayTheyAreDeadTests: XCTestCase {

    private static let paramsFile = "Sources/Echoelmusic/Studio/BioVisualParams.swift"
    private static let renderer = "Sources/Echoelmusic/Views/MetalBioView.swift"

    private func root() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func read(_ relativePath: String, stripped: Bool = true) throws -> String {
        let base = root()
        guard FileManager.default.fileExists(atPath: base.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(base.path)") }
        let path = base.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            // NOT a skip: a moved file must go RED, or this scan silently stops
            // checking anything at all (#454).
            struct AnchorMissing: Error { let path: String }
            throw AnchorMissing(path: relativePath)
        }
        let text = try String(contentsOf: path, encoding: .utf8)
        return stripped ? SourceText.codeOnly(text) : text
    }

    /// Every `.swift` under `Sources/`, comments blanked.
    private func allSources() throws -> [(path: String, code: String)] {
        let sources = root().appendingPathComponent("Sources")
        guard FileManager.default.fileExists(atPath: sources.path)
        else { throw XCTSkip("source tree not present under \(root().path)") }
        struct CannotWalk: Error { let path: String }
        guard let walker = FileManager.default.enumerator(atPath: sources.path) else {
            throw CannotWalk(path: sources.path)
        }
        var out: [(String, String)] = []
        for case let entry as String in walker where entry.hasSuffix(".swift") {
            let url = sources.appendingPathComponent(entry)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            out.append(("Sources/" + entry, SourceText.codeOnly(text)))
        }
        XCTAssertGreaterThan(out.count, 100,
                             "only \(out.count) Swift files found under Sources — the walk "
                             + "is broken, and an empty scan passes every claim below")
        return out
    }

    // MARK: - 1 · Exactly one field of the struct is read, anywhere

    func testOnlyOneBioVisualParamsFieldIsEverRead() throws {
        var reads: [String] = []
        for (path, code) in try allSources() {
            for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
                var rest = Substring(line)
                while let hit = rest.range(of: "vp.") {
                    let after = hit.upperBound
                    if after < rest.endIndex, rest[after].isLowercase {
                        reads.append("\(path): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                    rest = rest[after...]
                }
            }
        }
        XCTAssertEqual(reads.count, 1, """
            `vp.<field>` is read \(reads.count)× across Sources, expected exactly 1:
            \(reads.joined(separator: "\n"))

            `BioVisualParams` has SIX fields and — since #1116 measured it and #1131 wrote it
            down — only `pulseHz` has a consumer. If this count went UP, a field was wired:
            good, and its ⛔ NO CONSUMER note in \(Self.paramsFile) must come out in the SAME
            commit, or the code and its doc now disagree in the other direction. If it went
            DOWN to 0, the renderer stopped reading `pulseHz` and the heartbeat no longer
            drives the picture at all — that is a defect, not a cleanup.
            """)
        XCTAssertTrue(reads.first?.contains("vp.pulseHz") == true, """
            The one read is not `vp.pulseHz` but: \(reads.first ?? "—"). The heartbeat's route
            into the picture is what that single read IS; a different field being the only one
            read means the pulse path was replaced without this guard's doc being updated.
            """)
    }

    // MARK: - 2 · The four dead fields say so, at the field

    func testEachConsumerlessFieldCarriesItsRetraction() throws {
        // RAW on purpose: these needles ARE prose. `codeOnly` would blank exactly the
        // thing being checked — the same deliberate exception `TheVoiceTintsTheVisual
        // Tests` documents for its one law-comment needle.
        let params = try read(Self.paramsFile, stripped: false)
        XCTAssertEqual(params.components(separatedBy: "NO CONSUMER").count - 1, 4, """
            \(Self.paramsFile) carries \(params.components(separatedBy: "NO CONSUMER").count - 1) \
            "NO CONSUMER" notes, expected 4 — one each on `hue` (#1116), `complexity`, \
            `spread` and `intensity` (#1131). A field that is computed every frame and read \
            by nothing, while its doc describes a live mapping, is the sentence a website \
            line gets written from: six of them were, and #1116 had to take them back.
            """)
        for field in ["public var hue: Double", "public var complexity: Double",
                      "public var spread: Double", "public var intensity: Double"] {
            XCTAssertEqual(params.components(separatedBy: field).count - 1, 1, """
                `\(field)` is declared \(params.components(separatedBy: field).count - 1)× — \
                expected exactly 1. If it was renamed or removed, move its retraction with it; \
                if it was wired, delete the retraction and claim 1 above will already be red.
                """)
        }
        XCTAssertTrue(params.contains("only END appends are safe"), """
            The `complexity` note no longer names the #1119 byte-layout hazard. That sentence \
            is the reason this commit corrected the doc instead of wiring HRV in the same \
            breath — without it, the next reader sees a dead HRV path and an obvious fix, and \
            appends a field in the middle of a hand-mirrored 99-field struct.
            """)
    }

    // MARK: - 3 · COUNTERWEIGHT — the body still reaches the picture

    func testTheRetractionDoesNotOverstateItself() throws {
        let view = try read(Self.renderer)
        XCTAssertEqual(view.components(separatedBy:
            "float spread = (0.85 + u.breath * 0.35) * clamp(u.spread, 0.4, 1.6);").count - 1, 1, """
            The shader's own breath→spread term is gone. `BioVisualParams.spread` being dead \
            is a fact about that FIELD; breath reaches the picture through THIS line and the \
            `breath:` argument that feeds it. If the term really was removed, the retraction \
            on `spread` becomes a much stronger claim and must be rewritten — do not leave it \
            reading as the narrow one.
            """)
        XCTAssertEqual(view.components(separatedBy:
            "func update(hr: Float, coherence: Float, breath: Float, toneHz: Double,").count - 1, 1, """
            The renderer's entry point no longer takes `coherence:` and `breath:` directly. \
            Those two arguments are how the body actually reaches every field function — the \
            reason the #1131 retraction is narrow. Re-derive what the picture still receives \
            before touching that wording.
            """)
    }
}
