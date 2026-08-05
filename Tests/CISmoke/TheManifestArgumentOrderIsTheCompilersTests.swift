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

    /// ⭐ THE SECOND ERROR, and the reason this file grew. The first version of this guard shipped
    /// with an honest-limits note saying "a different manifest error would sail straight past it."
    /// One did, in the very next CI run: with the argument order fixed, the log stopped saying
    /// `incorrect argument labels` (0 occurrences) and started saying
    ///
    ///   Package.swift:25:15: error: 'v18' is unavailable
    ///   note: 'v18' was introduced in PackageDescription 6.0
    ///
    /// while line 1 declares `swift-tools-version: 5.10`. Overload resolution had been reporting
    /// the label mismatch first, so the platform error was invisible until the label error was
    /// gone. TWO errors, one visible at a time — which is why "I fixed the manifest error" was
    /// the wrong sentence and "the manifest still does not parse" was the right one.
    ///
    /// So this test encodes the RULE rather than my fix: a `.vNN` platform case only exists if the
    /// tools version is new enough for it. The string form (`.iOS("18.0")`) is always legal and
    /// passes. A future tools-version bump makes the enum form legal again and this stays green.
    ///
    /// ⚠️ It still cannot compile the manifest. It closes the ONE class that has now bitten twice
    /// (a platform literal ahead of its tools version); a third, different manifest error would
    /// still sail past. The only real proof is a successful `swift build`, which no gate here runs.
    func testThePlatformLiteralIsWithinItsToolsVersion() throws {
        let raw = try manifest()
        guard let toolsMajor = declaredToolsMajorVersion(in: raw) else {
            return XCTFail("Could not read the `swift-tools-version:` line — re-derive this guard")
        }
        // ⛔ COMMENTS MUST GO FIRST, and this was nearly the bug. The fix in `Package.swift`
        // documents itself with a block that QUOTES the broken form (".iOS(.v18)") so the next
        // reader understands why the string form is there. A scan over the raw text finds that
        // sentence, parses `v18` out of prose, and fails on correct code — the same
        // "a source scan cannot tell code from prose" trap this repo has now hit from both
        // directions (#367 a guard that could not fail, #404 one that failed on a doc comment).
        let text = codeOnly(raw)
        // ⛔ ANCHOR FIRST, OR THIS GUARD CANNOT FAIL. The natural shape here is "if the enum
        // form is present, check it; otherwise return" — and on today's manifest (string form)
        // that returns immediately, so the test is green no matter what else happens to the
        // platforms block, including its deletion. That is the #367 defect exactly: a guard
        // whose passing state carries no information. So assert the platform EXISTS in one of
        // the two forms first; only then apply the rule to the form that has a constraint.
        let usesStringForm = text.contains(".iOS(\"")
        let enumForm = text.range(of: ".iOS(.")
        XCTAssertTrue(usesStringForm || enumForm != nil, """
            `Package.swift` no longer declares an iOS platform. CLAUDE.md states an iOS 18 \
            deployment floor kept in step across Package.swift, project.yml and \
            Resources/iOS/Info.plist — if the floor moved, move all three and re-derive this guard.
            """)
        guard let range = enumForm,
              let close = text.range(of: ")", range: range.upperBound..<text.endIndex) else { return }
        let caseName = text[range.upperBound..<close.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        guard caseName.hasPrefix("v"), let major = Int(caseName.dropFirst()) else {
            return XCTFail("Unrecognised platform case `.\(caseName)` — re-derive this guard")
        }
        // PackageDescription 6.0 introduced .v18; 5.x tops out at .v17.
        let highestCaseFor5x = 17
        let message = """
            `Package.swift` uses the platform case `.\(caseName)` under \
            `swift-tools-version: \(toolsMajor).x`. That case was introduced in \
            PackageDescription 6.0, so the manifest does NOT compile — `swift build` and \
            `swift test` fail before touching a single source file, and `ci.yml:165` runs \
            `swift package resolve || true`, so nothing turns red. Use the string form \
            `.iOS("\(major).0")`, or bump the tools version in its own slice with an explicit \
            `.swiftLanguageMode(.v5)`.
            """
        XCTAssertTrue(toolsMajor >= 6 || major <= highestCaseFor5x, message)
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

    /// Everything before a `//` on each line. Crude on purpose: this manifest has no string
    /// literal containing `//`, and a real tokenizer here would be more machinery than the one
    /// fact it protects. If a URL ever lands in a string in `Package.swift`, revisit this.
    private func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let slashes = line.range(of: "//") else { return line }
                return line[line.startIndex..<slashes.lowerBound]
            }
            .joined(separator: "\n")
    }

    /// Major version from the `// swift-tools-version:` line. Deliberately tolerant of the two
    /// spellings SwiftPM accepts (`:5.10` and `: 5.10`) and of a trailing patch component.
    private func declaredToolsMajorVersion(in text: String) -> Int? {
        guard let marker = text.range(of: "swift-tools-version:") else { return nil }
        let rest = text[marker.upperBound...].prefix(20)
        let digits = rest.drop { $0 == " " }.prefix { $0.isNumber }
        return Int(digits)
    }

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
