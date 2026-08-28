// TheFinishDialsReachTheShaderTests.swift
// Echoel — #853 + #853B. The founder asked for "mehr Struktur/Textur Regler"; the two #578
// finishing stages (grain texture, per-speck glitter) got user dials (#853), and the "Struktur"
// half followed as a NEW static domain-warp stage with its own dial (#853B, neutral 0 — the
// stage did not exist before, so 0 IS the shipped look, unlike the two gain dials whose neutral
// is 1). This file pins the one fact NO gate can check and the chain that makes the dials real.
//
// ⭐ WHY THE LAYOUT TWIN IS THE CENTRAL CLAIM. `BioUniforms` is a Swift struct handed to the GPU
// as raw bytes; the MSL `Uniforms` struct in the same file must match it FIELD FOR FIELD, in
// order. The shader is compiled from a `String` at RUNTIME (`makeLibrary(source:)`), so neither
// `Xcode Compile Check` nor CI/CD can ever see a mismatch — the failure is garbage uniforms on a
// device: every value after the divergence point reads from the wrong offset, and the picture
// breaks in ways no log names. #853 is the first slice since the ripple rebuild to APPEND to both
// structs, and appending in only one of them is a one-edit mistake. Claim 1 compares the two
// field-name sequences outright, so a NAME-SEQUENCE divergence — middle insertion included —
// goes red with both lists printed. HONEST LIMIT: the extractors read only `: Float` / `float `
// members, so a future NON-Float field (`Int32`/`int`) inserted in one struct would shift real
// GPU offsets while both extracted sequences stay equal — a false green. Today every member is
// Float on both sides (asserted by the size floor); whoever adds a non-Float member widens the
// extractors in the same commit.
//
// ⚠️ THE LIMIT, PER ASSERTION (§1): every claim here is a SOURCE-TEXT SCAN — the shader cannot be
// rendered from this bundle and the `@AppStorage` members are `private` on `View`s it cannot
// instantiate. DEVICE PROBE, open and NOT covered: whether Texture at 2 reads as texture rather
// than noise, whether Glitter at 0 really leaves a clean field, and whether the dials feel right
// mid-performance. That is the founder's next device look. Flash safety is NOT re-asserted here:
// `GlitterCannotBecomeAFlashTests` owns the per-speck construction (#416 — one home per law), and
// amplitude factors cannot re-correlate the specks, which is stated THERE at the twinkle needles.
//
// ⚠️ WHAT IS DELIBERATELY NOT PINNED (#364): the gains (0.55, 0.045), the [0, 2] range as
// numbers, the 1.0 defaults, the tau. All taste, all free to move. Pinned is STRUCTURE: the twin,
// the clamp's existence, the reach of each dial into the fragment, and the three-surface binding.
//
// ⚠️ HONEST GRADING (§3), transcribed in Python against the parent (`f63433e`) and this tree —
// no local toolchain (§0). At #853: **12 checks: 10 assertions + claim 1's 2 `XCTUnwrap`
// anchors**, graded against #853's parent `f63433e` (92 = 92 fields then). #853B widened four
// of them (claim 1's contains, one clamp needle, one surface key) and added one shader-read
// assert — **14 checks** now, graded against #853B's own parent `e5aea66` (94 = 94) and its
// tree (95 = 95); the #853B additions are FORWARD checks whose parent-redness is the one
// shared absence of the structure field (#486). The
// file names no new Swift symbol, so it compiles against the parent and every check has a
// verdict there (measured, not assumed — the parent run printed 92 = 92 fields):
//   · **4 COUNTERWEIGHT** green on both trees: claim 1's two struct anchors, its size floor
//     (> 50 fields) and the sequence equality — the last one is the point of the file.
//   · **8 FORWARD, and their parent-redness is ONE shared absence (#486):** claim 1's
//     contains-new-fields, claim 2's two reads, claim 3's two clamps and claim 4's three
//     surface bindings all name text #853 itself introduces; none could have been red on the
//     parent for a regression reason, and booking them as eight findings would be the
//     flattering-direction defect (#433).
//   · STRIPPER: **PROPHYLAKTISCH (0 of 12 verdicts flip)** — every needle counted raw vs.
//     stripped on both trees; none sits right of a `//` and none contains one.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheFinishDialsReachTheShaderTests: XCTestCase {

    private static let viewPath = "Sources/Echoelmusic/Views/MetalBioView.swift"

    // MARK: - claim 1 — the Swift struct and the MSL struct are the same shape, in order

    func testTheShaderUniformsTwinTheSwiftStructFieldForField() throws {
        let src = try source(Self.viewPath)
        // Swift side: the fields of `private struct BioUniforms { … }`, in declaration order.
        let swiftBody = try XCTUnwrap(
            between(src, from: "private struct BioUniforms {", to: "\n}"),
            "`private struct BioUniforms {` is gone — re-anchor this twin scan (#454).")
        let swiftFields = fieldNames(inSwift: swiftBody)
        // MSL side: the members of `struct Uniforms { … };` inside the shader string.
        let mslBody = try XCTUnwrap(
            between(src, from: "struct Uniforms {", to: "};"),
            "the MSL `struct Uniforms {` is gone — re-anchor this twin scan (#454).")
        let mslFields = fieldNames(inMSL: mslBody)
        XCTAssertGreaterThan(swiftFields.count, 50, """
            the BioUniforms extraction found only \(swiftFields.count) fields — the anchor \
            matched something too small to be the real struct. Re-anchor before trusting \
            the comparison below.
            """)
        XCTAssertEqual(swiftFields, mslFields, """
            The Swift `BioUniforms` fields and the MSL `Uniforms` members have diverged.

            Swift: \(swiftFields.joined(separator: " "))
            MSL:   \(mslFields.joined(separator: " "))

            This struct crosses to the GPU as raw bytes and the shader compiles at RUNTIME, \
            so no CI gate can see this — on a device every uniform after the divergence point \
            reads from the wrong offset and the picture breaks with no log line. Append to \
            BOTH structs, at the SAME position (the end), in the same commit.
            """)
        XCTAssertTrue(swiftFields.contains("textureAmt") && swiftFields.contains("glitterAmt")
                      && swiftFields.contains("structureAmt"), """
            a finish field (#853 textureAmt/glitterAmt, #853B structureAmt) is gone from \
            BioUniforms. If a dial was removed on purpose, its rows, surface bindings and \
            shared key move with it in the same commit (§4).
            """)
    }

    // MARK: - claim 2 — each dial actually reaches the fragment (no placebo row)

    /// The Placebo law: a parameter is only offered if it moves real output. Each amount must
    /// appear as a factor in the fragment — a dial whose uniform is declared but never read
    /// would pass claim 1 and still do nothing.
    func testEveryAmountIsReadInTheFragment() throws {
        let src = try source(Self.viewPath)
        XCTAssertEqual(occurrences(of: "* u.textureAmt", in: src), 1, """
            `u.textureAmt` is not read exactly once in the shader. The Texture dial then \
            either does nothing (0 reads — a placebo row, which the Placebo law forbids) or \
            something this guard has not seen (2+). Re-anchor deliberately.
            """)
        XCTAssertEqual(occurrences(of: "* u.glitterAmt", in: src), 1, """
            `u.glitterAmt` is not read exactly once in the shader — same two failure \
            directions as the texture needle above.
            """)
        XCTAssertEqual(occurrences(of: "* u.structureAmt", in: src), 1, """
            `u.structureAmt` is not read exactly once in the shader — same two failure \
            directions as the texture needle above. The one read is the STATIC domain warp \
            on the styleField coordinate (#853B); its flash argument (a pure function of \
            pf, no phase) lives at that shader comment, not here.
            """)
    }

    // MARK: - claim 3 — the update() clamps exist (the GPU never sees a wild value)

    func testEveryAmountIsClampedInUpdate() throws {
        let src = try source(Self.viewPath)
        for needle in ["target.textureAmt = min(max(textureAmt.isFinite",
                       "target.glitterAmt = min(max(glitterAmt.isFinite",
                       "target.structureAmt = min(max(structureAmt.isFinite"] {
            XCTAssertEqual(occurrences(of: needle, in: src), 1, """
                `\(needle)` is gone. Every other look parameter sanitises non-finite input \
                and clamps its range before the GPU sees it (`update()`); the finish dials \
                must not be the exception — a NaN here multiplies straight into the output colour.
                """)
        }
    }

    // MARK: - claim 4 — all three mounted surfaces bind the shared keys

    /// Same premise `GlitterCannotBecomeAFlashTests` pins for saturation: the struct defaults
    /// in `MetalBioView.swift` are fallbacks a caller that omits the argument would see, and
    /// no such caller exists. What renders is the shared `@AppStorage` value — so a surface
    /// that stops binding it silently renders its own literal and the three surfaces drift.
    func testEveryMountedSurfaceBindsEveryFinishKey() throws {
        for path in ["Sources/Echoelmusic/Studio/EchoelStudioView.swift",
                     "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift",
                     "Sources/Echoelmusic/Studio/ExternalDisplayScene.swift"] {
            let src = try source(path)
            XCTAssertTrue(src.contains("StudioDefaultKeys.visualTexture.key")
                          && src.contains("StudioDefaultKeys.visualGlitter.key")
                          && src.contains("StudioDefaultKeys.visualStructure.key"), """
                \(path) no longer binds `visual.texture`, `visual.glitter` and \
                `visual.structure`. That surface \
                then renders the struct fallbacks instead of the user's dials, and the three \
                surfaces can show three different finishes in the same session.
                """)
        }
    }

    // MARK: - extraction helpers

    private func between(_ text: String, from: String, to: String) -> String? {
        guard let start = text.range(of: from)?.upperBound,
              let end = text.range(of: to, range: start..<text.endIndex)?.lowerBound
        else { return nil }
        return String(text[start..<end])
    }

    /// Field names of `var <name>: Float` declarations, in order (several share a line).
    private func fieldNames(inSwift body: String) -> [String] {
        body.components(separatedBy: "var ").dropFirst().compactMap { chunk in
            guard let colon = chunk.firstIndex(of: ":") else { return nil }
            let name = String(chunk[..<colon]).trimmingCharacters(in: .whitespaces)
            guard chunk[chunk.index(after: colon)...].hasPrefix(" Float") else { return nil }
            return name.allSatisfy { $0.isLetter || $0.isNumber } ? name : nil
        }
    }

    /// Member names of `float <name>;` in the MSL struct, in order. `float2`/`float3` never
    /// appear inside this struct; the trailing-space split cannot match them anyway.
    private func fieldNames(inMSL body: String) -> [String] {
        body.components(separatedBy: "float ").dropFirst().compactMap { chunk in
            guard let semi = chunk.firstIndex(of: ";") else { return nil }
            let name = String(chunk[..<semi]).trimmingCharacters(in: .whitespaces)
            return name.allSatisfy { $0.isLetter || $0.isNumber } ? name : nil
        }
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved file)

    private struct FinishAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw FinishAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
