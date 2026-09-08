// TheUniformMirrorHasNoCompilerTests.swift
// Echoel — the GPU uniform block, in the BLOCKING bundle.
//
// WHY THIS EXISTS. `MetalBioView` hands the GPU one struct, and that struct is declared
// TWICE in the same file: once in Swift as `private struct BioUniforms`, once as
// `struct Uniforms { float time; float hr; … }` inside the runtime-compiled Metal source.
// The two are matched by BYTE LAYOUT — `MemoryLayout<BioUniforms>.stride` is what
// `setFragmentBytes` uploads — and NOTHING CHECKS THAT. Not the Swift compiler, which never
// sees the Metal string; not `TheShippedShaderActuallyCompilesTests`, which proves the MSL
// parses and says nothing about what Swift sends it.
//
// The failure mode is the nastiest kind: insert or remove ONE field on one side and every
// uniform after it shifts by four bytes. `coherence` is read as `breath`, `breath` as
// `aspect`, and so on down 98 fields. Nothing crashes and nothing fails to build — the
// picture simply renders wrongly, with the cause a thousand lines from the symptom.
//
// #1119 found the first live reason to care: `hr` is uploaded, sanitised and eased every
// frame and NO shader reads it (`u.hr` occurs zero times in the MSL source). The obvious
// tidy-up is to delete it — and doing that on one side only is exactly the catastrophe
// above. The field's declaration now says so, and this file is the enforcement.
//
// ⚠️ WHAT IT PROVES AND WHAT IT DOES NOT. Same names, same order, all `Float` ⇒ the two
// declarations describe the same 4-byte-per-field layout. It does NOT prove Swift's actual
// `stride` equals the MSL struct's size: Metal's default alignment rules could in principle
// pad differently. For an all-`float` struct with no vectors they do not, which is exactly
// why claim 2 (nothing but `Float`) is load-bearing rather than decorative — a single
// `simd_float3` or `Double` on either side would break that argument, and claim 2 is what
// goes red.
//
// ⛔ A NEEDLE NOTE, because it cost a measurement DURING this slice. Two traps, both real:
//   · The Swift-side regex must NOT be line-anchored. Several lines declare THREE fields at
//     once (`var cc0r: Float = 0; var cc0g: Float = 0; var cc0b: Float = 0`), and a
//     `^\s*var` pattern silently counts 48 instead of 98 — then reports a divergence that
//     does not exist.
//   · The MSL needle must not be satisfiable by the PROSE about it. `#1119` added a comment
//     at `hr`'s declaration quoting `struct Uniforms { float time; float hr; … }`, and a
//     needle of that shape then matches the comment instead of the code — the
//     `EchoelModalBank` trap: writing about a thing falsifies the grep that measures it.
//     Anchoring on the THIRD field, which the comment elides, is what fixes it.

import Foundation
import XCTest

final class TheUniformMirrorHasNoCompilerTests: XCTestCase {

    private static let renderer = "Sources/Echoelmusic/Views/MetalBioView.swift"

    private func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(Self.renderer), encoding: .utf8)
    }

    /// (name, type) per Swift field, in declaration order.
    private func swiftFields(_ s: String) -> [(name: String, type: String)] {
        guard let open = s.range(of: "private struct BioUniforms {"),
              let close = s.range(of: "\n}", range: open.upperBound ..< s.endIndex) else { return [] }
        let block = String(s[open.upperBound ..< close.lowerBound])
        return matches(in: block, pattern: #"\bvar\s+(\w+)\s*:\s*(\w+)"#, groups: 2)
            .map { (name: $0[0], type: $0[1]) }
    }

    /// Field names of the MSL mirror, in declaration order.
    private func metalFields(_ s: String) -> [String] {
        // Third field in the needle on purpose — see the needle note in the header.
        guard let open = s.range(of: "struct Uniforms { float time; float hr; float coherence;"),
              let close = s.range(of: "};", range: open.lowerBound ..< s.endIndex) else { return [] }
        let block = String(s[open.lowerBound ..< close.lowerBound])
        return matches(in: block, pattern: #"\bfloat\s+(\w+)\s*;"#, groups: 1).map { $0[0] }
    }

    private func matches(in text: String, pattern: String, groups: Int) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (1 ... groups).map { ns.substring(with: m.range(at: $0)) }
        }
    }

    // MARK: - 3 · The parser cannot silently cover less than it claims (stated FIRST because
    //            claims 1 and 2 are worthless if the blocks were not found)

    func testBothDeclarationsWereActuallyFound() throws {
        let s = try source()
        let swift = swiftFields(s), metal = metalFields(s)
        XCTAssertGreaterThan(swift.count, 90, """
            Only \(swift.count) Swift uniform fields were parsed. There are ~98. Either the \
            struct shrank dramatically or — far more likely — the needle stopped matching: \
            `private struct BioUniforms {` was renamed, or the field regex became \
            line-anchored and is now missing the lines that declare three fields at once. \
            Fix the parser, do NOT lower this bound (#1114's claim-3 lesson).
            """)
        XCTAssertGreaterThan(metal.count, 90, """
            Only \(metal.count) Metal uniform fields were parsed. Check the needle first: it \
            anchors on `float coherence;`, the third field, precisely so a doc COMMENT that \
            quotes the first two cannot satisfy it. If the mirror was reformatted (one field \
            per line, say), point the parser at the new shape in the same commit.
            """)
    }

    // MARK: - 1 · Same fields, same order

    func testTheSwiftAndMetalUniformBlocksAgreeFieldForField() throws {
        let s = try source()
        let swift = swiftFields(s).map(\.name), metal = metalFields(s)
        guard swift.count > 90, metal.count > 90 else { return }   // claim 3 already failed

        XCTAssertEqual(swift.count, metal.count, """
            The uniform block has \(swift.count) fields in Swift and \(metal.count) in Metal. \
            The GPU is handed `MemoryLayout<BioUniforms>.stride` bytes and reads them \
            POSITIONALLY, so a count mismatch means every field past the difference is read \
            as its neighbour — no crash, no build error, just a wrong picture. Add or remove \
            the field on BOTH sides in ONE commit.
            """)
        for (index, pair) in zip(swift, metal).enumerated() where pair.0 != pair.1 {
            XCTFail("""
                Uniform field \(index) is `\(pair.0)` in Swift and `\(pair.1)` in Metal. From \
                here on the two declarations describe different memory: everything after this \
                offset is read as the wrong quantity. This is the FIRST divergence — later \
                ones are consequences, so fix this one and re-run. Both declarations live in \
                \(Self.renderer); they must move together, always.
                """)
            break
        }
    }

    // MARK: - 2 · Nothing but Float — the premise claim 1 rests on

    func testEveryUniformIsAFloatOnTheSwiftSide() throws {
        let s = try source()
        let swift = swiftFields(s)
        guard swift.count > 90 else { return }
        for field in swift where field.type != "Float" {
            XCTFail("""
                Uniform `\(field.name)` is a `\(field.type)`, not a `Float`. Matching NAMES \
                then stop proving matching LAYOUT: a `Double` is 8 bytes against Metal's \
                4-byte `float`, and a `simd_float3` carries 16-byte alignment that a plain \
                run of scalars does not. Everything after it shifts. If a vector type is \
                genuinely wanted, mirror it exactly on the Metal side and rewrite this claim \
                to check alignment rather than deleting it — it is the reason claim 1 is \
                allowed to reason about layout from names.
                """)
        }
    }
}
