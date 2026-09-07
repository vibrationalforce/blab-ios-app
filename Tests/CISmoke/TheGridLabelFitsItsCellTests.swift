// TheGridLabelFitsItsCellTests.swift
// Echoel — #1058. Blocking bundle. SOURCE-TEXT SCAN (`Tests/CISmoke/CLAUDE.md` §1): it proves
// what the sizing expression READS, never what a rendered glyph looks like.
//
// ⭐ WHY THIS FILE EXISTS. The play-surface grid sized its note labels from `cellH` alone
// (`min(12, max(9, cellH * 0.16))`) and gave them a box of `cellW - 11`. On a chromatic key at
// phone width that box is about 18 pt while the Solfège label is four glyphs ("Do♯4"), which at
// 12 pt cannot fit 18 pt in any normal-width face. `CATextLayer`'s default `truncationMode` is
// `.none`, so the surplus was CLIPPED — on the one surface where the COLUMN IS THE NOTE, two
// neighbouring columns could read the same. Height was never the binding constraint; width
// always was, and the expression could not see it.
//
// ⭐ WHAT IS PINNED, and why it is the expression rather than a pixel. There is no font engine
// here and no device, so "the label fits" is not measurable in this bundle. What IS measurable,
// and is exactly the defect, is that the size decision CONSULTS the width — claim 1 — and that
// the fallback which makes the fit reachable at all (dropping the octave digit rather than
// shrinking into illegibility) exists — claim 2.
//
// ⛔ AND THE MEASUREMENT MUST NAME THE TYPEFACE IT MEASURES (claim 3, the counterweight that
// matters most). The layer never sets `font`, and an unset `CATextLayer` font is Helvetica —
// so measuring in `UIFont.systemFont` would produce a fit that is rigorous about a typeface
// nobody renders. A future "cleanup" replacing the named face with the system font would leave
// every assertion about width intact and quietly reintroduce a percentage of the same clipping.
//
// ⚠️ THE OCTAVE DIGIT IS NOT LOST INFORMATION, said here because a reader of claim 2 could
// reasonably think it is: the ROW is the octave on this surface by construction (bottom = low),
// and `accessibilityValue` in the same method spells that out for VoiceOver. Claim 4 pins that
// second home so the two cannot drift apart.
//
// ⚠️ HONEST GRADING. No local Swift toolchain (§0). SEVEN assertions across four claims
// (3 · 2 · 1 · 1), driven in Python against BOTH trees: 7/7 green on today, and on the
// pre-slice tree five are RED and two green. So **5 REGRESSION CATCHES, 2 COUNTERWEIGHTS** —
// the bottom-anchored label frame and the spoken octave layout. Counted from the driven run,
// never from this file's outline (#1054).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheGridLabelFitsItsCellTests: XCTestCase {

    private static let file = "Sources/Echoelmusic/Studio/TouchInstrumentView.swift"

    private func code() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent(Self.file)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(Self.file) could not be read — a missing anchor is a "
                    + "finding, not a pass (#454).")
            return ""
        }
        // Comment-stripped (#1050): this file quotes the old expression at length in its own ⛔
        // blocks, and a raw scan would count that prose as code.
        return SourceText.codeOnly(text)
    }

    /// claim 1 — the size decision reads the cell's WIDTH. The old expression is gone and a
    /// box width derived from `cellW` is what the fit is asked about.
    func testTheLabelSizeIsDerivedFromTheCellWidth() throws {
        let source = try code()
        XCTAssertFalse(source.contains("let labelSize: CGFloat = min(12, max(9, cellH * 0.16))"), """
            The height-only label size is back in `rebuildGrid`. It cannot see `cellW`, so on a \
            12-degree key at phone width it hands a four-glyph label an ~18 pt box and \
            `CATextLayer` clips the surplus — two columns then read the same on the surface \
            where the column IS the note. Size the label through `fittedLabelStyle`, which is \
            asked about the width.
            """)
        XCTAssertTrue(source.contains("boxWidth: labelBoxWidth"), """
            `rebuildGrid` no longer passes a width-derived box to the fit. `labelBoxWidth` is \
            the one place the cell's horizontal room is computed (`cellW` minus the insets the \
            label frame actually uses); passing anything else would make the fit describe a \
            box the layer is not drawn in.
            """)
        // Counterweight (#367): the fix is about WIDTH. The label still hangs off the cell's
        // BOTTOM edge, which is what makes the fills readable above it and what every
        // screenshot of this surface has looked like. An over-correction that recentres the
        // text to "use the space" would pass both assertions above and change the instrument.
        XCTAssertTrue(source.contains("y: cellFrame.maxY - labelSize - 6"), """
            The label no longer hangs off the cell's bottom edge. #1058 changed how WIDE the \
            text may be, never where it sits; if a later slice genuinely wants it moved, that \
            is its own decision with its own founder look, not a side effect of a fit.
            """)
    }

    /// claim 2 — the fit has somewhere to go when shrinking runs out. Without the second stage
    /// this is a shrink, not a fit, and it bottoms out clipping a smaller glyph.
    func testTheFitCanDropTheOctaveRatherThanClip() throws {
        let source = try code()
        XCTAssertTrue(source.contains("dropsOctave"), """
            The octave-drop fallback is gone from `TouchInstrumentUIView`. A pure size search \
            has a readability floor (8 pt), so on a narrow cell it ends by clipping a smaller \
            glyph — the same defect one notch quieter. Dropping the digit is what makes the \
            floor reachable; the row already encodes the octave.
            """)
        XCTAssertTrue(source.contains("static func fittedLabelStyle("), """
            `fittedLabelStyle` is gone. It is the one place that decides both the point size \
            and whether the octave digit survives; inlining that decision back into \
            `rebuildGrid` would put two branches of it next to a `for` loop that must apply \
            the SAME answer to every cell (#416).
            """)
    }

    /// claim 3 — the counterweight (#367). The fit must measure the face the layer draws.
    func testTheFitMeasuresTheFaceTheLayerActuallyDraws() throws {
        let source = try code()
        XCTAssertTrue(source.contains("UIFont(name: \"Helvetica\", size: size)"), """
            The fit no longer measures Helvetica. The grid's `CATextLayer` never sets `font`, \
            and an unset `CATextLayer` font IS Helvetica — measuring `UIFont.systemFont` \
            instead gives a fit that is exact about a typeface nothing renders, which looks \
            like rigour and reintroduces part of the clipping. If the layer starts setting its \
            own font, change BOTH sides in the same commit and this message with them (#456).
            """)
    }

    /// claim 4 — the premise behind "the digit is safe to drop": the row already says it, out
    /// loud, in the same method.
    func testTheRowStillSpeaksTheOctaveLayout() throws {
        let source = try code()
        XCTAssertTrue(source.contains("three octave rows, low at the bottom"), """
            The spoken layout description is gone from `rebuildGrid`. Claim 2 lets the octave \
            digit disappear from the cells on the grounds that the ROW carries it and VoiceOver \
            is told so; without this sentence that justification is no longer true, and the \
            repair is to restore the spoken layout rather than to weaken claim 2.
            """)
    }
}

// NEEDS-FOUNDER-VERIFY: Vollbild-Visual, Tonart auf eine CHROMATISCHE Skala (12 Spalten) und die
// Notennamen auf Solfège oder Sargam stellen. Vorher standen dort abgeschnittene Namen; jetzt
// muss in JEDER Zelle ein vollständiger Name stehen — notfalls ohne Oktavziffer, aber nie
// halbiert. Gegenprobe mit einer 7-Ton-Skala und Englisch: dort soll die Ziffer weiterhin da sein.
