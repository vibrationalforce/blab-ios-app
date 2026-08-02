// ParameterRowStacksAtAccessibilitySizesTests.swift
// Echoel — the app's ONE parameter control must not lose its label and run off the screen for
// the person who raised the system text size. #353e. `Tests/CISmoke` is the blocking bundle.
//
// THE DEFECT THIS PINS, measured rather than assumed. `EchoelValueField`'s labelled row is
// `HStack { Text(label) ; Spacer(minLength: 8) ; valueBox }`, and the box is PINNED to
// `valueWidth` — 150 pt, declared `@ScaledMetric(relativeTo: .body)`, so it tracks body text.
// Body is 17 pt at `.large` and 53 pt at `.accessibility5`, a factor of ~3.1, which puts the pin
// at ~468 pt on a 375 pt phone. A `.frame(width:)` is a pin and does not compress: the box takes
// the whole row and then some, the label is squeezed to its `minimumScaleFactor(0.7)` floor and
// truncates to nothing, and the box runs past the screen edge.
//
// The reach is what makes it worth a blocking guard rather than a note. This is the one control
// every adjustable number in the app uses (house law, CLAUDE.md: "no raw SwiftUI
// `Slider`/`Stepper` for parameters") — 62 call sites, and `EchoelStudioView`'s `param`/`knob`
// helpers each render several rows from one site, so more rows than sites.
//
// ⭐ WHAT IS ASSERTED IS STRUCTURE, NOT PIXELS. This bundle cannot build a SwiftUI view and there
// is no simulator, so "the label is readable at accessibility5" is not a claim any test here can
// earn. What IS checkable, and what decides the outcome: the control reads `dynamicTypeSize`
// itself, the stacking decision excludes label-less callers, the stacked label is allowed to WRAP
// instead of shrink, and the width pin is dropped in exactly the branch where the box has the row
// to itself.
//
// ⚠️ THE SAFETY PROPERTY, and it is why the slice is cut at a threshold: below an accessibility
// size the layout is byte-for-byte the one that has always shipped. The last two assertions guard
// that directly — the compact branch must still carry its `Spacer(minLength: 8)` and its
// shrink-to-fit label. A guard that only checks the NEW branch would stay green while the default
// path, the one everybody actually sees, was rewritten underneath it.
//
// ⛔ NOT ASSERTED: that the label-less compact callers also reflow. They render the box alone, so
// there is no label to rescue, and dropping their pin would make a chrome field greedy inside a
// bar whose geometry #365/#382 pin. Asserting it would forbid the deliberate choice.
//
// NEEDS-FOUNDER-VERIFY: iOS Settings → Display → Text Size at an accessibility step, then open the
// Sound panel — does each parameter row show its name above its number, and does the number box
// stay inside the panel?

import Foundation
import XCTest

final class ParameterRowStacksAtAccessibilitySizesTests: XCTestCase {

    private static let field = "Sources/Echoelmusic/Studio/EchoelValueField.swift"

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

    /// Whole-line comments dropped: this file's prose names every token asserted below, and the
    /// source file's prose does too, so a naive `contains` over the raw text would stay green
    /// with the code deleted and only the doc left standing.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    func testTheControlDecidesItsLayoutFromTheTextSize() throws {
        let lines = try codeLines(Self.field)
        XCTAssertTrue(lines.contains { $0.contains("@Environment(\\.dynamicTypeSize)") }, """
            `EchoelValueField` no longer reads `dynamicTypeSize`. Without it the control cannot \
            know that its pinned box is being scaled to ~3× the row it sits in, and every \
            parameter in the app goes back to an unlabelled box running off the screen.
            """)
        XCTAssertTrue(lines.contains { $0.contains("dynamicTypeSize.isAccessibilitySize") }, """
            The accessibility threshold is gone. The threshold is what makes this shippable \
            without a simulator: below it the layout is the one that has always shipped, above \
            it the label steps above the box and the box gets the row to itself.
            """)
    }

    /// The stacking decision must exclude label-less callers — see the ⛔ in this file's header.
    func testOnlyLabelledRowsStack() throws {
        let lines = try codeLines(Self.field)
        guard let decl = lines.first(where: { $0.contains("private var stacksLabel: Bool") }) else {
            return XCTFail("""
                `stacksLabel` is gone. It is the one place the two conditions for reflowing are \
                spelled together; splitting them across the body is how one of them gets lost.
                """)
        }
        XCTAssertTrue(decl.contains("!label.isEmpty"), """
            `stacksLabel` no longer requires a label: \(decl.trimmingCharacters(in: .whitespaces)). \
            A label-less caller has no label to rescue, and dropping ITS width pin makes a chrome \
            field greedy inside a bar whose geometry #365/#382 pin.
            """)
        XCTAssertTrue(decl.contains("dynamicTypeSize.isAccessibilitySize"), """
            `stacksLabel` no longer consults the text size: \
            \(decl.trimmingCharacters(in: .whitespaces)). Without the threshold this either \
            reflows every row at every size or none at any.
            """)
    }

    /// The pin becomes nil in exactly the branch where the box has the row to itself.
    func testTheWidthPinIsDroppedWhenTheLabelStepsAside() throws {
        let lines = try codeLines(Self.field)
        XCTAssertTrue(lines.contains { $0.contains(".frame(width: pinnedBoxWidth)") }, """
            The box width is spelled inline again. A literal `.frame(width: …)` at the call site \
            cannot express "no pin", which is the whole fix — the number inside already carries \
            `.frame(maxWidth: .infinity)`, so a nil width lets the box take the row it was given \
            instead of overflowing it.
            """)
        XCTAssertTrue(lines.contains { $0.contains("if stacksLabel { return nil }") }, """
            `pinnedBoxWidth` no longer returns nil while stacking, so the ~468 pt pin survives \
            the reflow: the label moves out of the way and the box still runs off the screen. \
            Half a fix reads, on a screenshot at the default size, exactly like a whole one.
            """)
    }

    /// The stacked label WRAPS. Shrinking is the behaviour that created the defect.
    func testTheStackedLabelWrapsInsteadOfShrinking() throws {
        let lines = try codeLines(Self.field)
        // Window the stacking branch by the closing brace at the branch's OWN indentation. A
        // line count or a "next N lines" rule is wrong the first time anyone adds a line.
        guard let start = lines.firstIndex(where: { $0.contains("} else if stacksLabel {") }) else {
            throw XCTSkip("no `else if stacksLabel` branch to window — the tests above report that")
        }
        let indent = String(repeating: " ", count: lines[start].prefix(while: { $0 == " " }).count)
        guard let end = lines[(start + 1)...].firstIndex(where: { $0 == indent + "} else {" }) else {
            throw XCTSkip("""
                no `} else {` closes the stacking branch at its own indentation — the window \
                would be wrong, and a wrong window is worse than no assertion
                """)
        }
        let branch = lines[(start + 1)..<end]
        XCTAssertTrue(branch.contains { $0.contains(".fixedSize(horizontal: false, vertical: true)") }, """
            The stacked label lost `fixedSize(vertical:)`. Having its own line is not enough — a \
            tight parent proposal still truncates it to one line, so the name of the parameter \
            disappears in exactly the layout that exists to show it.
            """)
        XCTAssertFalse(branch.contains { $0.contains("minimumScaleFactor") }, """
            The stacked label shrinks to fit again: \
            \(branch.filter { $0.contains("minimumScaleFactor") }.map { $0.trimmingCharacters(in: .whitespaces) }). \
            Shrinking text for someone who asked for bigger text IS the defect — on its own line \
            the label has room to wrap, and wrapping is the answer.
            """)
    }

    /// The default path — the one everybody sees — must be untouched. Without this the guard
    /// above would stay green while the layout at normal sizes was rewritten underneath it.
    func testTheCompactRowIsUnchanged() throws {
        let lines = try codeLines(Self.field)
        XCTAssertTrue(lines.contains { $0.contains("Spacer(minLength: 8)") }, """
            The compact row lost its `Spacer(minLength: 8)`. Below an accessibility size this \
            control must render byte-for-byte what has always shipped — that property is what \
            makes a layout change safe to commit with no simulator in the repo.
            """)
        XCTAssertTrue(lines.contains { $0.contains(".lineLimit(1).minimumScaleFactor(0.7)") }, """
            The compact row's label no longer shrinks to fit. On one shared line that IS the \
            correct behaviour — it is only wrong above the accessibility threshold, which is \
            precisely why the fix is a branch and not a replacement.
            """)
    }
}
