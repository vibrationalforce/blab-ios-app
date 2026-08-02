// InfoSheetTextScalesTests.swift
// Echoel — the way OUT of an explanation must grow with the explanation. #353f.
// `Tests/CISmoke` is the blocking bundle.
//
// THE DEFECT THIS PINS. `BioMetricInfo.swift` holds the two sheets that teach the body's
// numbers — `BioMetricInfoView` (tap a value in the bio strip) and `BioMetricsGuideView` (the ⓘ).
// Every string in them is set through `EchoelTheme.font`, which is `Font.custom(_:size:
// relativeTo: .body)` and therefore participates in Dynamic Type. Both "Done" buttons were
// `.font(.system(size: 15, weight: .semibold))` — an ABSOLUTE point size, which does not
// participate at all. At an accessibility text size the explanation swelled and the only way out
// of it stayed at 15 pt. A sheet whose escape hatch is the smallest thing on screen is worse than
// one that never grew.
//
// ⚠️ THE FAMILY CHANGES, AND THAT IS VISIBLE — this is not a render-neutral edit and must not be
// described as one. SF-Semibold-15 → Atkinson-Bold-15: a different typeface, not just a
// different scaling rule. It is the right trade because the brand family is the house default
// (`EchoelTheme.font`) and every neighbouring string in these two sheets already uses it, so the
// button was the odd one out in family AND in scaling. `EchoelTheme.font`'s own doc warns that
// `.font(.system(size:weight: .medium))` is a SEPARATE question from the #361 weight bug — this
// slice is that separate question, answered for these two sites only.
//
// ⭐ WHAT THE TREE-WIDE SURVEY FOUND, because the value of this slice is that it CLOSES a class
// and a closed class has to be provable. Command:
//
//     git grep -n '\.font(\.system(size:' -- Sources
//
// 92 hits, 2 of them whole-line comments. Each remaining hit was classified by whether it, or
// the nearest preceding non-blank non-comment line, owns an `Image(systemName:`. That leaves 17
// non-icon hits, and one of those (`FloatingVisualWindow.swift:935`) is the multi-line-ternary
// resize glyph this file's next paragraph already calls out — so 16 real ones:
//
//   · `Resources/AppIcon.swift` (4) — renders the app ICON at a caller-supplied `size`. An icon
//     is a fixed-geometry asset; Dynamic Type has no meaning there.
//   · `Studio/EchoelLogoMark.swift` (1) — a `Canvas` that resolves `Text("E")` into a drawn
//     glyph at `52 * s`. Same reason: artwork, not reading matter.
//   · `Studio/PianoRollView.swift` (8) — doorless and unmounted since the founder's
//     "Pianoroll soll raus" (2026-07-26, CLAUDE.md). Fixing type in a view nobody can open is
//     upkeep without a user; if it is ever re-doored, this paragraph is the checklist.
//   · `Sources/EchoelmusicWatch/EchoelWatchApp.swift` (1) and
//     `Sources/EchoelmusicWidgets/EchoelBioWidget.swift` (2) — the big `Text("\(bpm)")` numerals
//     at 40/44/48 pt. Reading matter, genuinely, but in HOST-LAID-OUT surfaces: a widget family
//     and a watch face are fixed point rectangles the app does not own, so a numeral that grew
//     with Larger Text would be clipped by the host rather than read. Absolute is the right
//     answer there and the wrong answer inside the app's own scrolling sheets. Not this slice.
//   · `Studio/BioMetricInfo.swift` (2) — THIS SLICE.
//
// ⛔ THE FIRST VERSION OF THIS BLOCK WROTE "(9)" FOR THE ROLL, OMITTED THE WATCH AND WIDGET
// THREE ENTIRELY, AND CLOSED WITH "every other hit in the tree is an SF Symbol" — which was
// false. The cause is the exact failure CLAUDE.md documents over and over, and it is worth
// naming precisely because it does not look like carelessness: I ran the classification over
// `git ls-files Sources/Echoelmusic` and then WROTE the command as `-- Sources`. The number and
// the command printed beside it were never the same query. `Sources/EchoelmusicWatch` and
// `Sources/EchoelmusicWidgets` are inside the pathspec I published and outside the one I ran.
// A command quoted next to a count is only worth something if it is the command that produced
// the count — copy it from the shell, do not retype it wider.
//
// Every other hit is an SF Symbol. Those are deliberately absolute: the ones in
// `FloatingVisualWindow` sit in 28×44 slots inside a chrome bar whose total width #365/#366 pin,
// so growing the glyph would break a budget that has its own guards. Icons that should track the
// text are a DIFFERENT slice with a different fix (`.imageScale`, or a text style) — do not fold
// them in here on the strength of this file's name.
//
// ⛔ THE SURVEY IS A SNAPSHOT, NOT AN INVARIANT. Nothing in this bundle scans the whole tree for
// new absolute-size text, and this file deliberately does not try: a source-text rule that has to
// tell `Text` from `Image` gets it wrong on a multi-line ternary (my own first pass mis-classified
// `FloatingVisualWindow.swift`'s resize glyph, which spells its symbol name across three lines).
// A guard that mis-classifies is worse than none — it either reds on nothing or, worse, reads
// green over a real defect. So the assertions below are scoped to ONE file, where every hit was
// checked by hand, and the claim "the class is closed" lives in this comment where a reader can
// re-run the command instead of trusting it.
//
// NEEDS-FOUNDER-VERIFY: Settings → Display → Text Size at an accessibility step, tap a number in
// the bio strip — does "Done" grow with the explanation?

import Foundation
import XCTest

final class InfoSheetTextScalesTests: XCTestCase {

    private static let info = "Sources/Echoelmusic/Studio/BioMetricInfo.swift"

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

    /// Raw lines, comments INCLUDED — the icon-ownership check below walks backwards to the
    /// nearest preceding line and has to know a comment when it sees one. Filtering here would
    /// silently let a comment stand in as an owner.
    private func lines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    func testBothDoneButtonsScaleWithTheText() throws {
        let all = try lines(Self.info)
        // Plain `if` inside the loop rather than a `for … where` clause: the needle is a string
        // literal containing braces, and a `where` clause that ends in one puts the loop body's
        // opening brace right behind it. It parses, but it reads like a trap and there is no
        // local compiler here to settle an argument about it.
        var buttons: [Int] = []
        for (i, l) in all.enumerated() {
            let trimmed = l.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            if l.contains("Button(\"Done\") { dismiss() }") { buttons.append(i) }
        }
        XCTAssertEqual(buttons.count, 2, """
            \(buttons.count) "Done" buttons in BioMetricInfo.swift; two are expected — one per \
            sheet (`BioMetricInfoView`, `BioMetricsGuideView`). A third would need its own font \
            decision, and this guard is the place that notices.
            """)
        for i in buttons {
            guard i + 1 < all.count else {
                return XCTFail("a \"Done\" button is the last line of the file — no font follows it")
            }
            // ⚠️ POSITIONAL, and the sibling assertion below goes out of its way to be
            // STRUCTURAL and says so. The inconsistency is deliberate but it should not be
            // silent: a comment inserted between a `Button("Done")` and its `.font` would red
            // this test while the code is correct. Accepted because the alternative — scanning
            // forward for the next `.font(` — would happily bind to a DIFFERENT view's font and
            // pass while the button had none, which is the failure that actually matters here.
            // A false red is a minute; a false green is the defect shipping.
            let font = all[i + 1].trimmingCharacters(in: .whitespaces)
            XCTAssertTrue(font.contains("EchoelTheme.font("), """
                The "Done" button on line \(i + 2) is set with `\(font)`. It must go through \
                `EchoelTheme.font`, which is `Font.custom(_:size:relativeTo: .body)` and \
                therefore scales; `.system(size:)` is absolute and leaves the way out of the \
                sheet at 15 pt while the explanation around it grows.
                """)
        }
    }

    /// Every absolute point size left in this file must belong to an SF Symbol.
    func testEveryRemainingAbsoluteSizeBelongsToAnIcon() throws {
        let all = try lines(Self.info)
        var offenders: [String] = []
        for (i, l) in all.enumerated()
        where !l.trimmingCharacters(in: .whitespaces).hasPrefix("//")
            && l.contains(".font(.system(size:") {
            // Nearest preceding line that is neither blank nor a whole-line comment. Structural,
            // not a line count — an added comment or blank line must not change the answer.
            var owner = ""
            var j = i - 1
            while j >= 0 {
                let s = all[j].trimmingCharacters(in: .whitespaces)
                if !s.isEmpty && !s.hasPrefix("//") { owner = s; break }
                j -= 1
            }
            if !owner.contains("Image(systemName:") {
                offenders.append("line \(i + 1): \(l.trimmingCharacters(in: .whitespaces)) — owner: \(owner)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            Absolute point sizes on non-icon content in BioMetricInfo.swift: \(offenders). These \
            two sheets are reading matter — their whole job is to be read — so every string in \
            them goes through `EchoelTheme.font`. An SF Symbol may stay absolute (it is a glyph \
            beside text, not text), which is the one exemption this assertion allows.
            """)
    }
}
