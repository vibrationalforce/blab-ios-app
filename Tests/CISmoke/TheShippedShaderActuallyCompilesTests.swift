//
//  TheShippedShaderActuallyCompilesTests.swift
//  Echoelmusic — CISmoke
//
//  #1079 — the Metal shader is COMPILED here, not merely read.
//
//  THE GAP THIS CLOSES, found while verifying #1078 and worth more than that one change.
//  `MetalBioView`'s 805-line shader lives in a Swift multi-line string literal and is
//  compiled by `device.makeLibrary(source:)` at RUNTIME. So `Xcode Compile Check` and
//  CI/CD's `Build for Testing` both go green on a shader with a syntax error: the Swift
//  around it compiles perfectly, and the string is just a string. Two guards already read
//  this shader as TEXT (`TheShaderSaysWhenItDidNotCompileTests` pins that the failure
//  carries Metal's own message; `TheFinishDialsReachTheShaderTests` pins that dials arrive),
//  and neither asks the only question that matters first: does it build at all?
//
//  THE FAILURE MODE IS SILENT AND TOTAL, which is why a text scan is not enough here. On a
//  compile error `MetalBioView` does not crash -- it takes its degraded path and the field
//  simply never renders. Every user opens on a Metal look (`LookBlendMap.defaultSequence`
//  is [3, 5, 7]), so a one-character slip in the shader ships an app whose main picture is
//  gone, through two green gates, and the first person to find out is the founder.
//
//  ⚠️ WHAT THIS DOES NOT PROVE. Compiling is not rendering. It says nothing about whether
//  the picture is beautiful, correct, or flash-safe -- `FlashGuardTests` and
//  `TheWaterLookObeysCapillaryDispersionTests` own those, and the founder's eye owns the
//  rest. It also runs the SIMULATOR's Metal compiler, not the device's; they agree on
//  syntax, which is the whole claim.
//
//  ⚠️ IT CAN SKIP, AND A SKIP IS NOT A PASS (#806). `MTLCreateSystemDefaultDevice()`
//  returns nil where no Metal device exists. Rather than pass quietly, the test throws
//  `XCTSkip` with a message -- `scripts/gh-test-verdict.py` reports skipped tests BY NAME,
//  so a run where this silently stopped working is visible instead of green.
//

import Foundation
import XCTest
#if canImport(Metal)
import Metal
#endif
@testable import Echoelmusic

final class TheShippedShaderActuallyCompilesTests: XCTestCase {

    private static let viewPath = "Sources/Echoelmusic/Views/MetalBioView.swift"

    /// The five `\(…)` interpolations the shader literal carries, resolved from the SAME
    /// constants the shipped code interpolates.
    ///
    /// Reading them from the types rather than re-typing their values is the point: if
    /// `FlashGuard.ringsPhaseDampingLiteral` changes, this substitution follows it, exactly
    /// as the shipped string does. And a SIXTH interpolation added later needs no change
    /// here -- an unsubstituted `\(` is not valid Metal, so the compile fails loudly, which
    /// is the safe direction for a guard to break in.
    private static var substitutions: [(String, String)] {
        [("\\(SpectralColor.tRedMetalLiteral)", SpectralColor.tRedMetalLiteral),
         ("\\(SpectralColor.tVioletMetalLiteral)", SpectralColor.tVioletMetalLiteral),
         ("\\(FlashGuard.ringsPhaseDampingLiteral)", FlashGuard.ringsPhaseDampingLiteral),
         ("\\(FlashGuard.bloomBeatGainSwingLiteral)", FlashGuard.bloomBeatGainSwingLiteral),
         ("\\(FlashGuard.filmicStrengthLiteral)", FlashGuard.filmicStrengthLiteral)]
    }

    /// The shader text exactly as the compiler receives it at runtime.
    private func shaderSource() throws -> String {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(Self.viewPath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(Self.viewPath) could not be read — a missing anchor "
                    + "is a finding, not a pass.")
            return ""
        }
        guard let open = text.range(of: "private static let shaderSource = \"\"\"\n"),
              let close = text.range(of: "\n    \"\"\"", range: open.upperBound..<text.endIndex)
        else {
            XCTFail("ANCHOR MISSING: `private static let shaderSource = \"\"\"` and its closing "
                    + "delimiter could not both be found. If the shader moved to a `.metal` "
                    + "file or a different literal, re-anchor this file there — do not delete "
                    + "the claim, it is the only thing that compiles the shader.")
            return ""
        }
        var body = String(text[open.upperBound..<close.lowerBound])
        for (needle, value) in Self.substitutions {
            body = body.replacingOccurrences(of: needle, with: value)
        }
        return body
    }

    // 1 — IT COMPILES. The whole file in one assertion, because there is nothing weaker
    // worth asserting: a shader either builds or the picture is gone.
    func testTheShaderBuilds() throws {
        #if canImport(Metal)
        let source = try shaderSource()
        try XCTSkipIf(source.isEmpty, "Anchor failed above; that failure is the finding.")
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device on this runner, so the shipped shader was NOT "
                          + "compiled in this run. This is a SKIP and not a pass — "
                          + "gh-test-verdict.py reports skipped tests by name for exactly "
                          + "this reason.")
        }
        do {
            _ = try device.makeLibrary(source: source, options: nil)
        } catch {
            XCTFail("""
                THE SHIPPED METAL SHADER DOES NOT COMPILE. Both CI gates stay green on this — \
                `Xcode Compile Check` and `Build for Testing` see a Swift string literal, and \
                `makeLibrary(source:)` runs at runtime — so this assertion is the only thing \
                between a shader typo and a TestFlight build whose main picture never draws \
                (MetalBioView takes its degraded path, it does not crash). Metal's own \
                message: \(error.localizedDescription)
                """)
        }
        #else
        throw XCTSkip("Metal is not importable here, so the shipped shader was NOT compiled "
                      + "in this run. A SKIP, not a pass.")
        #endif
    }

    // 2 — COUNTERWEIGHT (#367). Claim 1 passes just as well on an EMPTY string, or on one
    // whose interpolations were never substituted and happened to be stripped. Prove the
    // text really is the shipped shader before believing the compile means anything.
    func testTheCompiledTextIsTheShippedShader() throws {
        let source = try shaderSource()
        XCTAssertGreaterThan(source.count, 20000,
                             "The extracted shader is \(source.count) characters — far short "
                             + "of the shipped file. The literal's delimiters probably moved, "
                             + "and claim 1 then compiled a fragment.")
        XCTAssertTrue(source.contains("#include <metal_stdlib>"),
                      "The extracted text does not start like a Metal source file.")
        XCTAssertTrue(source.contains("fragment float4 echoel_bio_fragment"),
                      "The extracted text is missing the fragment entry point, so whatever "
                      + "claim 1 compiled was not the shader that draws the field.")
        XCTAssertFalse(source.contains("\\("),
                       "An unsubstituted Swift interpolation survived into the text handed "
                       + "to Metal. Add it to `substitutions` — reading the value from the "
                       + "same constant the shipped string interpolates, never re-typed.")
    }
}
