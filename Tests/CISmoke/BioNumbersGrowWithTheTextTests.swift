// BioNumbersGrowWithTheTextTests.swift
// Echoel — the row that shows the body's numbers must not show them SMALLEST to the person who
// asked for bigger text. #353c. `Tests/CISmoke` is the blocking bundle.
//
// THE DEFECT THIS PINS, measured rather than assumed. `BioStripView.strip` puts the ⓘ, the
// driving dot, four dividers, FOUR metric cells and an 88 pt source-tag slot on ONE line. On a
// 375 pt phone, after 24 pt of horizontal padding, each metric cell gets roughly 50 pt for a
// label, a value and a unit. The row is `lineLimit(1)` with `minimumScaleFactor(0.6)`, so
// growing Dynamic Type does not grow these numbers — it SHRINKS them, to 60 % of a 12 pt face.
// The user who raised the text size ends up with the smallest numbers in the app, and nothing
// about that is visible at the default size, which is the only size anyone screenshots.
//
// ⭐ WHAT IS ASSERTED IS THE STRUCTURE, NOT THE PIXELS. This bundle cannot build a SwiftUI view
// and there is no simulator, so "the numbers are legible at accessibility5" is not a claim any
// test here can earn. What IS checkable, and what actually decides the outcome: the leaf reads
// `dynamicTypeSize` itself, it branches on `isAccessibilitySize`, the two layouts share ONE
// definition of the metrics row, and the fixed 88 pt slot exists only in the compact branch.
//
// ⚠️ THE SAFETY PROPERTY, and it is why this slice was shaped this way: at every
// NON-accessibility size the layout is the old one, untouched. A layout change nobody can run
// locally is a gamble; a layout change that only fires above a threshold, with the default path
// left alone, is not. The guard checks that property directly — the compact branch must still
// carry the fixed slot.
//
// ⛔ NOT ASSERTED: that `ViewThatFits` is absent. It was considered and rejected (reasoning in
// `strip`'s doc: `minimumScaleFactor` makes the one-row candidate always report a fit, so the
// second candidate is never chosen and a guard over it could never fail). Pinning its absence
// would forbid a future, correctly-built measurement layout for no reason.
//
// NEEDS-FOUNDER-VERIFY: iOS Settings → Display → Text Size at an accessibility step, Bio panel
// open — are HR, HRV, Br and Coh readable, and does the source tag sit on its own line?

import Foundation
import XCTest

final class BioNumbersGrowWithTheTextTests: XCTestCase {

    private static let strip = "Sources/Echoelmusic/Studio/BioStripView.swift"

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, so \
                it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    /// Whole-line comments dropped: this file's prose names every token asserted below, and a
    /// naive `contains` over the raw text would stay green with the code deleted.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    func testTheStripDecidesItsLayoutFromTheTextSize() throws {
        let lines = try codeLines(Self.strip)
        XCTAssertTrue(lines.contains { $0.contains("@Environment(\\.dynamicTypeSize)") }, """
            `BioStripView` no longer reads `dynamicTypeSize`. Without it the strip cannot know \
            that its four numbers are being scaled DOWN as the user's chosen text size goes up, \
            and it goes back to squeezing them into 60 % of a 12 pt face.
            """)
        XCTAssertTrue(lines.contains { $0.contains("dynamicTypeSize.isAccessibilitySize") }, """
            The accessibility branch is gone. The threshold is what makes this safe to ship \
            without a simulator: below it the layout is the one that has always shipped, above \
            it the source tag steps out of the metrics row and gives ~22 pt back per cell.
            """)
    }

    /// ONE definition of the metrics row, shared by both layouts.
    func testBothLayoutsShareOneMetricsRow() throws {
        let lines = try codeLines(Self.strip)
        XCTAssertTrue(lines.contains { $0.contains("private var metricsRow: some View") }, """
            `metricsRow` is gone. If the two layouts each spell the four metric cells out, they \
            drift — and only the compact one is ever screenshotted, so the accessibility copy \
            would rot unseen. One definition, two arrangements.
            """)
        let mounts = lines.filter { $0.trimmingCharacters(in: .whitespaces) == "metricsRow" }.count
        XCTAssertEqual(mounts, 2, """
            `metricsRow` is mounted \(mounts) time(s); both layouts must use it exactly once. \
            Zero means a layout renders no numbers at all; more than two means a third \
            arrangement appeared without this guard being updated.
            """)
        // The cells themselves stay in the shared row — spelled once, not per branch.
        //
        // ⛔ THE DECLARATION IS EXCLUDED, and the first version of this assertion did not do
        // that: `private func metricButton(label:...)` also contains the token, so the naive
        // count answered FIVE for four cells and the assertion failed on arrival. This repo has
        // paid for exactly this twice before (the `signalSection` door count, the `Analysis*View`
        // prose match) — a count over source text has to say which occurrences it means.
        let cells = lines.filter {
            $0.contains("metricButton(label:") && !$0.contains("private func")
        }.count
        XCTAssertEqual(cells, 4, """
            \(cells) `metricButton` CALL sites (the declaration excluded); four are expected — \
            HR, HRV, Br, Coh. Eight would mean the row was copied into the second layout \
            instead of shared, which is the drift `metricsRow` exists to prevent.
            """)
    }

    /// The fixed 88 pt slot belongs to the compact branch ONLY — it is the width the
    /// accessibility layout exists to give back.
    func testTheFixedTagSlotIsGoneFromTheAccessibilityLayout() throws {
        let lines = try codeLines(Self.strip)
        let slots = lines.filter { $0.contains(".frame(width: 88") }
        XCTAssertEqual(slots.count, 1, """
            The 88 pt source-tag slot appears \(slots.count) time(s); exactly one is expected. \
            None means the compact layout lost the bounded slot that stops the tag's width from \
            reflowing its neighbours (the old "wobble"); two means the accessibility layout \
            pinned it again and gave back nothing.
            """)
        // Window the accessibility branch: from the `if` to the `} else {` at the same
        // indentation. A line count or a "next N lines" rule would be wrong the first time
        // anyone adds a line — the brace at the branch's own indentation is the boundary.
        guard let start = lines.firstIndex(where: { $0.contains("dynamicTypeSize.isAccessibilitySize") }) else {
            throw XCTSkip("no accessibility branch to window — the test above reports that")
        }
        let indent = String(repeating: " ", count: lines[start].prefix(while: { $0 == " " }).count)
        guard let end = lines[(start + 1)...].firstIndex(where: { $0 == indent + "} else {" }) else {
            throw XCTSkip("""
                no `} else {` closes the accessibility branch at its own indentation — the \
                window would be wrong, and a wrong window is worse than no assertion
                """)
        }
        let branch = lines[(start + 1)..<end]
        XCTAssertFalse(branch.contains { $0.contains(".frame(width:") }, """
            The accessibility layout pins a fixed width: \
            \(branch.filter { $0.contains(".frame(width:") }.map { $0.trimmingCharacters(in: .whitespaces) }). \
            A fixed point size does not grow with the text, so it takes room away from exactly \
            the numbers this branch exists to make bigger.
            """)
    }
}
