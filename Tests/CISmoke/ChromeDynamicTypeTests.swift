// ChromeDynamicTypeTests.swift
// Echoel — the always-visible chrome must not cap the text size a low-vision user set.
//
// WHAT THIS GUARDS (#232 C). `WorkspaceView` clamps its chrome Group — brand header,
// TransportBar, CompositionHeaderStrip — with `.dynamicTypeSize(...)`. Behind that clamp sit
// Play/Stop, tempo, Genre, Key, Scale, Tone system and A4: the controls that are on screen at
// all times. Until 2026-07-30 the ceiling was `.xxLarge`, the largest NON-accessibility size,
// so a user on AX1…AX5 got no enlargement at all there — and neither did the app's own
// pinch-to-zoom, because `StudioZoom` drives Dynamic Type and stopped at the same wall.
//
// The clamp existed for a real reason: the three bars were `.frame(height:)`, so bigger text
// overran a box that could not grow. The fix removed the reason (heights are minimums now) and
// then raised the ceiling. Both halves have to stay true together, which is what this file
// checks — a fixed height reintroduced under a raised ceiling CROPS the chrome, and a lowered
// ceiling under flexible heights silently takes the accessibility win back.
//
// ⚠️ WHY A SOURCE SCAN AND NOT A LAYOUT TEST. There is no simulator in this environment and
// the blocking bundle is `Tests/CISmoke`; a SwiftUI layout assertion cannot run here. The
// realistic regression is textual — someone re-pins `.frame(height: 44)` to make a row line up,
// or lowers the ceiling to make something fit — and a textual check catches exactly that. It
// does NOT check that the layout looks right at AX1; nothing here can. Read the ceiling itself
// as unfinished: AX4/AX5 users are still served AX1, deliberately, because nobody has seen
// those sizes on a device. Do not read a green here as "the chrome is accessible".
//
// ⚠️ SECOND HONEST LIMIT: it scans SOURCE TEXT. If the checkout is not at the path this file
// was compiled from, it SKIPS rather than passes — a silent pass on an unscanned tree is the
// `continue-on-error` lie the `doctor` skill exists to catch.

import Foundation
import XCTest

final class ChromeDynamicTypeTests: XCTestCase {

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…` → up two).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()              // Tests
            .deletingLastPathComponent()              // repo
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("source tree not present at \(sources.path) — this test inspects "
                          + "source text, so it SKIPS rather than reporting a green it did "
                          + "not earn")
        }
        return root
    }

    /// Every line of `path` that is not a whole-line comment. Comments are dropped because the
    /// commit that made this change QUOTES the old `.frame(height: 50)` spellings in its own
    /// prose so the history stays legible — matching those would fail on the fix itself.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    private static let workspace = "Sources/Echoelmusic/Studio/WorkspaceView.swift"

    /// The sizes that are NOT an accessibility size. Any of them as the chrome ceiling means a
    /// low-vision user gets nothing, which is the defect.
    private static let nonAccessibilityCeilings = [
        "DynamicTypeSize.xSmall", "DynamicTypeSize.small", "DynamicTypeSize.medium",
        "DynamicTypeSize.large", "DynamicTypeSize.xLarge", "DynamicTypeSize.xxLarge",
        "DynamicTypeSize.xxxLarge"
    ]

    func testTheChromeCeilingIsAnAccessibilitySize() throws {
        let lines = try codeLines(Self.workspace)
        let clamps = lines.filter { $0.contains(".dynamicTypeSize(") }
        XCTAssertEqual(clamps.count, 1,
                       "expected exactly ONE Dynamic Type clamp in the chrome; found "
                       + "\(clamps.count). A second clamp means two ceilings disagree and the "
                       + "lower one silently wins:\n\(clamps.joined(separator: "\n"))")
        let clamp = try XCTUnwrap(clamps.first)
        XCTAssertTrue(clamp.contains("DynamicTypeSize.accessibility"),
                      "the chrome ceiling is not an accessibility size — every AX user is "
                      + "capped below the smallest accessibility step, on Play/Stop, tempo, "
                      + "Key and Scale: \(clamp)")
        for bad in Self.nonAccessibilityCeilings {
            XCTAssertFalse(clamp.contains(bad),
                           "the chrome ceiling names \(bad): \(clamp)")
        }
    }

    /// The three chrome bars. Each pairs the bar's design height with the property that draws
    /// it, so a failure message says WHICH bar regressed rather than only that one did.
    private static let chromeBars = [(bar: "topBar", height: 50),
                                     (bar: "TransportBar", height: 44),
                                     (bar: "CompositionHeaderStrip", height: 40)]

    func testTheChromeBarsCanGrowWithTheirText() throws {
        let lines = try codeLines(Self.workspace)
        for spec in Self.chromeBars {
            XCTAssertFalse(lines.contains { $0.contains(".frame(height: \(spec.height))") },
                           "\(spec.bar) pins .frame(height: \(spec.height)) again. A fixed "
                           + "height under the raised Dynamic Type ceiling does not shrink the "
                           + "text — it CROPS it, which is worse than the clamp this replaced.")
            XCTAssertTrue(lines.contains { $0.contains(".frame(minHeight: \(spec.height))") },
                          "\(spec.bar) no longer carries .frame(minHeight: \(spec.height)). If "
                          + "the bar was deliberately resized, update this expectation in the "
                          + "same commit — do not delete the check.")
        }
    }

    func testTheValueBoxIsAFloorAndNotACeiling() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/EchoelValueField.swift")
        XCTAssertTrue(lines.contains { $0.contains(".frame(minHeight: boxHeight)") },
                      "EchoelValueField pins its box height again. `boxHeight` means 'match "
                      + "the neighbouring buttons' — a floor. As a ceiling it crops the number "
                      + "the box exists to show, and the chrome's A4 field (104×30) is the "
                      + "case that made it visible.")
        XCTAssertFalse(lines.contains { $0.contains(".frame(height: boxHeight)") },
                       "EchoelValueField still has the fixed-height spelling somewhere — two "
                       + "frames on one box means the stricter one decides.")
    }
}
