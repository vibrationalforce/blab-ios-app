// TheManifestArgumentOrderIsTheCompilersTests.swift
// Echoel — #420. `Package.swift` did not parse, and nothing could say so.
//
// ⭐ THE DEFECT. The `.target(…)` call listed `swiftSettings:` before `resources:`.
// `PackageDescription.target` is
//   (name:dependencies:path:exclude:sources:resources:publicHeadersPath:
//    cSettings:cxxSettings:swiftSettings:linkerSettings:plugins:)
// with every label after `name` defaulted, so the wrong ORDER does not produce a tidy
// "argument out of order" diagnostic — overload resolution walks off to a different `target`
// overload and reports two misleading errors instead:
//   Package.swift:39: incorrect argument labels in call (have
//     'name:dependencies:swiftSettings:resources:', expected 'name:dependencies:path:
//     exclude:sources:publicHeadersPath:…')
//   Package.swift:54: type 'Array<String>.ArrayLiteralElement' (aka 'String') has no
//     member 'process'
// The second points at `.process("Resources")` and reads like a resources bug. It is not:
// `resources` had been bound into `path`'s position, so its array was typed `[String]`.
//
// ⛔ WHY IT SURVIVED — THIS IS THE PART WORTH REMEMBERING. `ci.yml:165` runs
// `swift package resolve || true`. With the mask, an invalid manifest cannot fail anything;
// the error simply printed into every CI/CD log as noise. And CLAUDE.md's SESSION START
// ritual opens with `swift build` / `swift test`, so a fresh session's first action returned
// a manifest error about a file it had not touched. A broken instrument plus a masked signal
// is the exact pairing the `doctor` skill exists for. The `|| true` lives in a founder-gated
// file (`.github/workflows/**`) and is REPORTED, not edited — this guard is the half I may do.
//
// ⛔ HONEST LIMITS — and they matter more than usual here, because this file is easy to
// over-read as "the manifest is valid".
//   · This CANNOT compile `Package.swift`. There is no SwiftPM step in the blocking bundle and
//     no local toolchain. It pins the ONE shape that was actually broken, in the order the
//     compiler demands. A different manifest error would sail straight past it.
//   · It therefore does NOT prove `swift build` or `swift test` work. The test target points
//     at `Tests/EchoelmusicTests` (313 files that the iOS-sim gates never compile), so SwiftPM
//     may still fail for entirely separate reasons. Fixing the manifest removes a blocker; it
//     does not certify what is behind it. Do not upgrade this claim without a real run.
//   · The label list below is hand-transcribed from PackageDescription. If SwiftPM ever
//     reorders it (it has not since 5.0), this guard becomes wrong in the safe direction —
//     red on correct code — rather than silently permissive.

import Foundation
import XCTest

final class TheManifestArgumentOrderIsTheCompilersTests: XCTestCase {

    /// The canonical order, name-first. Only the labels this repo's manifest actually uses are
    /// asserted on; the rest are here so the next reader can check a NEW label's position
    /// without leaving the file.
    private static let targetLabelOrder = [
        "name", "dependencies", "path", "exclude", "sources", "resources",
        "publicHeadersPath", "cSettings", "cxxSettings", "swiftSettings",
        "linkerSettings", "plugins"
    ]

    /// ⭐ THE REGRESSION. Red on the shipped-until-#420 manifest, green after.
    func testResourcesIsDeclaredBeforeSwiftSettings() throws {
        let text = try manifest()
        guard let resources = text.range(of: "\n            resources: ["),
              let settings = text.range(of: "\n            swiftSettings: [") else {
            return XCTFail("Both labels must be present on the Echoelmusic target — if one was " +
                           "renamed or removed, re-derive this guard rather than deleting it")
        }
        XCTAssertLessThan(
            resources.lowerBound, settings.lowerBound,
            "`resources:` must precede `swiftSettings:`. PackageDescription orders them that " +
            "way and every label is defaulted, so the wrong order does not read as an ordering " +
            "error — it binds `resources` into `path`'s slot and blames `.process`.")
    }

    /// A second, independent hold on the same fact, because the first one anchors on exact
    /// indentation and would go quietly green if the call were reformatted. This one asserts
    /// the relative order of the labels the manifest uses against the canonical list.
    func testEveryLabelTheManifestUsesAppearsInCanonicalOrder() throws {
        let text = try manifest()
        guard let call = targetCall(in: text) else {
            return XCTFail("Could not isolate the `.target(` call — re-derive the guard")
        }
        var lastIndex = -1
        var seen: [String] = []
        for label in Self.targetLabelOrder {
            guard let found = call.range(of: "\n            \(label): ") else { continue }
            let position = call.distance(from: call.startIndex, to: found.lowerBound)
            XCTAssertGreaterThan(position, lastIndex,
                                 "label `\(label):` appears out of canonical order; seen so far: \(seen)")
            lastIndex = position
            seen.append(label)
        }
        XCTAssertTrue(seen.contains("resources") && seen.contains("swiftSettings"),
                      "the two labels this guard exists for must both be found; got \(seen)")
    }

    /// The manifest still declares zero dependencies. CLAUDE.md states this as a product fact
    /// ("ZERO external deps shipped today"), the tech-stack table plans HaishinKit as the first
    /// one, and the App Store copy leans on it — so a dependency arriving unannounced should
    /// surface here rather than in a review.
    func testTheManifestStillShipsNoDependencies() throws {
        let text = try manifest()
        guard let open = text.range(of: "dependencies: [\n"),
              let close = text.range(of: "],", range: open.upperBound..<text.endIndex) else {
            return XCTFail("Could not isolate the package-level `dependencies:` array")
        }
        let body = text[open.upperBound..<close.lowerBound]
        let code = body.split(separator: "\n").filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && !t.hasPrefix("//")
        }
        XCTAssertTrue(code.isEmpty,
                      "Package.swift declares a dependency. That is allowed — but CLAUDE.md, " +
                      "the tech-stack table and the store copy all say zero, and all three have " +
                      "to move with it. Found: \(code)")
    }

    // MARK: - Reading the manifest

    private func manifest() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Package.swift not present — this scan cannot report a green")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// From `.target(` to the `.testTarget(` that follows it. Deliberately not a brace matcher:
    /// the manifest carries `//` comments with braces and parentheses in them (including the
    /// diagnostic quoted above), and a naive matcher would stop inside one.
    private func targetCall(in text: String) -> Substring? {
        guard let start = text.range(of: ".target(") else { return nil }
        let end = text.range(of: ".testTarget(", range: start.upperBound..<text.endIndex)
        return text[start.lowerBound..<(end?.lowerBound ?? text.endIndex)]
    }
}
