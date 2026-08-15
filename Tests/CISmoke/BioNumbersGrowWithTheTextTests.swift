// BioNumbersGrowWithTheTextTests.swift
// Echoel — the row that shows the body's numbers must not show them SMALLEST to the person who
// asked for bigger text. #353c. `Tests/CISmoke` is the blocking bundle.
//
// THE DEFECT THIS PINS, measured rather than assumed. `BioStripView.strip` puts the ⓘ, the
// driving dot, four dividers, FOUR metric cells and an 88 pt source-tag slot on ONE line. On a
// 375 pt phone, after 24 pt of horizontal padding, each metric cell gets roughly 50 pt for a
// label, a value and a unit. The row is `lineLimit(1)` with a 0.6 scale floor, so
// growing Dynamic Type does not grow these numbers — it SHRINKS them, to 60 % of the face.
// The user who raised the text size ends up with the smallest numbers in the app, and nothing
// about that is visible at the default size, which is the only size anyone screenshots.
// ⭐ #606 (GUI-Board Scheibe 3) finished what #353c started: the tag-removal alone still
// forced the shrink past ~AX2 with four cells on one line, so at accessibility sizes the
// four cells now stack VERTICALLY (full strip width each) and the scale floor there is 1.0
// — the anti-fix is out exactly where the user asked for larger text. The compact branch
// keeps the one-line row AND its 0.6 floor: that trade (shrink beats "…" on 375 pt) stands.
//
// ⭐ WHAT IS ASSERTED IS THE STRUCTURE, NOT THE PIXELS. This bundle cannot build a SwiftUI view
// and there is no simulator, so "the numbers are legible at accessibility5" is not a claim any
// test here can earn. What IS checkable, and what actually decides the outcome: the leaf reads
// `dynamicTypeSize` itself, it branches on `isAccessibilitySize`, the two layouts share ONE
// spelling of each metric cell (#606: the shared unit is the CELL, no longer the whole row),
// the scale floor is conditional, and the fixed 88 pt slot exists only in the compact branch.
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
// open — do HR, HRV, Br and Coh sit one per line at FULL size (no shrink, no "…"), and does
// the source tag sit on its own line? At the default size: byte-for-byte the old strip.
//
// ⚠️ HONEST GRADING (#433/#464) — the #606 rewrite, whole file transcribed in Python against
// the parent (7ca351e) and this tree (§3: a substantially rewritten guard is driven whole,
// not by diff). 12 verdicts hand-counted: cell-sharing test (1 decl + 1 mounts + 4 cell
// counts + 1 call-site count = 7) + layout test (2) + scale-floor test (1) + tag-slot test
// (1 slot count + 1 window scan = 2). ⛔ The first version of this paragraph said "11" and
// enumerated three tests while grading the scale-floor test's ternary two sentences later
// — the #606 review caught the arithmetic in exactly the discipline this header exists to
// satisfy (#433's flattering-direction warning cuts both ways: a miscount that still says
// "all green" is a miscount). On THIS tree all 12 pass. Against the PARENT: mounts==1 is
// red (it was 2 — the deliberate #606 widening), the four cell-name counts are red as ONE
// finding (#486 — the builders are born with #606), and the scale ternary is red (FORWARD,
// same commit). The rest — env read, AX branch, row decl, 4 call sites, one 88 pt slot, no
// fixed width in the AX window — are COUNTERWEIGHTS, green on both trees. ZERO regressions
// claimed, because zero exist.
// This file keeps its line-based private stripper (one of the 69 §2 legacy copies —
// migrating it is a bundle-wide move, not this slice); all needles live on code lines,
// and every #606 comment naming them is whole-line, so the filter drops it.

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

    /// ONE spelling of each metric cell, shared by both layouts.
    ///
    /// ⛔ #606 CHANGED WHAT "SHARED" MEANS HERE, and this test moved with it (§4). #353c
    /// shared the whole ROW (`metricsRow` mounted once per branch). #606 stacks the four
    /// cells VERTICALLY at accessibility sizes — the one-line row was still forcing the
    /// 0.6 shrink past ~AX2 even after the tag left — so the shared unit is now the CELL:
    /// four `hrCell`/`hrvCell`/`breathCell`/`coherenceCell` builders, spelled once,
    /// composed horizontally by `metricsRow` (compact) and vertically by the AX branch.
    /// The old `mounts == 2` assertion would be red on this correct tree; its law
    /// ("no third arrangement, no copied cells") survives in the counts below.
    func testBothLayoutsShareTheFourCells() throws {
        let lines = try codeLines(Self.strip)
        XCTAssertTrue(lines.contains { $0.contains("private var metricsRow: some View") }, """
            `metricsRow` is gone. The compact layout's equal-width horizontal arrangement \
            lives there; without it the default-size strip has no definition.
            """)
        let mounts = lines.filter { $0.trimmingCharacters(in: .whitespaces) == "metricsRow" }.count
        XCTAssertEqual(mounts, 1, """
            `metricsRow` is mounted \(mounts) time(s); exactly one (the compact branch) is \
            expected since #606. Zero means the default layout renders no numbers; two or \
            more means an arrangement went back to mounting the one-line row — if that is \
            the AX branch, the 0.6-shrink defect this file exists for is back.
            """)
        // Each cell: ONE declaration + ONE use per layout = exactly three lines naming it.
        // Fewer means a layout dropped a metric; more means a cell was copied instead of
        // shared — the drift the cell builders exist to prevent.
        for cell in ["hrCell", "hrvCell", "breathCell", "coherenceCell"] {
            let count = lines.filter { $0.contains(cell) }.count
            XCTAssertEqual(count, 3, """
                `\(cell)` appears on \(count) code line(s); exactly three are expected \
                (declaration + compact use + accessibility use). The four cells are the \
                ONE spelling of the metrics — a missing use means a layout lost a number, \
                an extra one means a copy appeared without this guard being updated.
                """)
        }
        // The cell builders themselves still delegate to `metricButton` exactly four times.
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
            HR, HRV, Br, Coh, one per cell builder. Eight would mean the cells were copied \
            into a layout instead of shared.
            """)
    }

    /// #606 — the anti-fix is OUT at accessibility sizes: the scale floor is 1.0 exactly
    /// where the user asked for larger text, and the compact branch keeps its measured 0.6
    /// trade (shrink beats "…" on a 375 pt phone — founder-complained-about twice).
    /// Pinning the ternary pins BOTH halves of that decision on purpose; a retune must
    /// update this needle, the in-code rationale beside it, and the #353c/#606 prose in
    /// the same commit.
    func testTheScaleFloorIsFullSizeAtAccessibilitySizes() throws {
        let lines = try codeLines(Self.strip)
        XCTAssertTrue(lines.contains {
            $0.contains(".minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.6)")
        }, """
            The conditional scale floor is gone. Either the strip went back to a flat 0.6 \
            (the anti-fix: growing Dynamic Type SHRINKS the bio numbers — at AX sizes the \
            vertical stack gives every cell the full width precisely so nothing needs to \
            shrink), or the floor moved/retuned without this guard moving with it.
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
