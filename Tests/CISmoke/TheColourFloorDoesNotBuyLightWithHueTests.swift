// TheColourFloorDoesNotBuyLightWithHueTests.swift
// Echoel — #1054. Blocking bundle. SOURCE-TEXT SCAN over the inline MSL in
// `MetalBioView.swift` (`Tests/CISmoke/CLAUDE.md` §1): it proves the SHAPE of the two
// colour steps, never what a pixel looks like. The look is NEEDS-FOUNDER-VERIFY, below.
//
// ⭐ WHY THIS FILE EXISTS. Two adjacent steps in the field shader cancelled each other out
// on exactly the colours they name. The luminance floor lifts a dim colour "while
// PRESERVING hue" — but a saturated violet reaches luminance 0.35 only with its blue
// channel far past 1.0, and the very next step (`echoelHue`) ended in a PER-CHANNEL
// `clamp(rgb, 0.0, 1.0)`. Blue alone was crushed back to 1.0, the other two were left
// where they were, and the result is a hue rotation. Measured by transcribing both steps:
//
//     (0.15, 0.02, 0.30)  ->  lift  ->  (0.774, 0.103, 1.547)
//                          ->  clamp ->  (0.795, 0.091, 1.000)   = 18.6° of hue, -0.034 sat
//
// So the two lines written to protect "deep-red/violet tones" were destroying exactly
// those tones, at the DEFAULT setting, and the comment above them said "PRESERVING hue"
// while it happened. In-gamut colours (cyan, amber, pale blue) drifted <= 0.07°, which is
// the YIQ round trip's rounded constants and is why nobody saw this by looking.
//
// ⭐ THE REPAIR IS TWO SHAPES, NOT TWO NUMBERS, AND THAT IS WHY THIS GUARD PINS SHAPES.
// (1) the lift stops at whichever comes first, the floor or the sRGB gamut boundary —
// `1.0 / peak` — so it never asks for a luminance the display cannot show; (2) `echoelHue`
// returns early at shiftTurns 0 and, above 1.0, normalises by the PEAK instead of clamping
// per channel, so an out-of-gamut result loses brightness and keeps its ratios.
//
// ⚠️ WHAT MUST NOT BE READ INTO THIS (#364). The floor VALUE (0.35), the saturation
// default and the warm tint are taste and are deliberately NOT pinned — a designer may
// move any of them without touching this file. What is pinned is that light is never
// bought with hue. If a future slice replaces the whole approach (an OKLab lift, say),
// these claims go red BY DESIGN and their messages say what the replacement must preserve.
//
// ⛔ AND THE SATURATION HALF IS NOT PART OF THE RETRACTION (#367). `echoelSaturate` really
// IS exact at s = 1 — `mix(float3(l), c, 1)` returns `c`. Claim 4 pins that it stayed as it
// was, so nobody "finishes the job" by rewriting the half that was already correct.
//
// ⚠️ HONEST GRADING. No local Swift toolchain (§0). **Seven assertions across four claims**
// (1 · 2 · 2 · 2), stated rather than counted from the file's shape. Every needle was driven
// against BOTH trees before this line was written. Against the working tree all seven are
// green; against the tree this slice was cut from, **five are RED** — the early return, the
// peak normalisation, the gamut term and its `max(…, 1.0)` were all absent, and
// `clamp(rgb, 0.0, 1.0)` was present. So **5 REGRESSION CATCHES, 2 COUNTERWEIGHTS** (both
// in claim 4, which is the half that was already correct).
//
// ⛔ THE FIRST VERSION OF THIS PARAGRAPH SAID "six assertions … 3 catches, 3 counterweights"
// and both halves were wrong — there are seven, and the split is 5/2. It was written from
// the file's SHAPE (four claims, "about one and a half each") instead of from the driven
// result, which is the miscount this bundle has now made three times. The numbers above are
// transcribed from the run, not from the outline.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheColourFloorDoesNotBuyLightWithHueTests: XCTestCase {

    private static let shaderFile = "Sources/Echoelmusic/Views/MetalBioView.swift"

    private func shader() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent(Self.shaderFile)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(Self.shaderFile) could not be read — a missing anchor "
                    + "is a finding, not a pass (#454).")
            return ""
        }
        return text
    }

    /// claim 1 — the hue rotation is an identity at zero, by CONSTRUCTION rather than by a
    /// comment claiming so. The old text asserted it; the YIQ round trip did not deliver it.
    func testTheHueRotationIsAnIdentityAtZero() throws {
        let src = try shader()
        XCTAssertTrue(src.contains("if (shiftTurns == 0.0) { return c; }"), """
            `echoelHue` no longer returns early at shiftTurns 0. Without it the default \
            path runs a YIQ round trip whose published constants are rounded (measured \
            drift up to 0.07° on in-gamut colours) and then a gamut clamp. If the rotation \
            was rewritten to be exactly identity at 0 by other means, say so here — but do \
            not go back to a COMMENT claiming it, which is what this slice retracted.
            """)
    }

    /// claim 2 — and out of gamut it loses BRIGHTNESS, never hue. This is the assertion that
    /// would have caught the 18.6° rotation.
    func testTheHueRotationNormalisesByPeakInsteadOfClampingPerChannel() throws {
        let src = try shader()
        XCTAssertFalse(src.contains("return clamp(rgb, 0.0, 1.0);"), """
            The per-channel clamp is back at the end of `echoelHue`. Clamping the channels \
            independently rotates the hue of anything out of gamut — measured 18.6° on a \
            lifted violet, which is precisely the colour class the luminance floor above \
            exists to protect. Scale by the peak instead.
            """)
        XCTAssertTrue(src.contains("return (m > 1.0) ? rgb / m : rgb;"), """
            The peak normalisation is gone from `echoelHue`. An out-of-gamut result must \
            lose brightness and keep its ratios; if the normalisation moved, this claim \
            must move with it in the same commit (#456).
            """)
    }

    /// claim 3 — the floor stops at the gamut boundary. Without this the lift keeps
    /// promising a luminance sRGB cannot hold, and something downstream pays for it.
    func testTheLuminanceFloorStopsAtTheGamutBoundary() throws {
        let src = try shader()
        XCTAssertTrue(src.contains("1.0 / peak"), """
            The luminance lift no longer stops at the sRGB gamut boundary. A saturated \
            violet reaches the floor only with a channel far past 1.0; whatever clips it \
            next will trade the hue for the luminance. The floor VALUE is free to change — \
            the gamut term is not.
            """)
        XCTAssertTrue(src.contains("float lift = max(min("), """
            The lift lost its `max(…, 1.0)`. The gamut term is a CEILING on a lift, never a \
            reason to darken a colour that already sits at or above the floor.
            """)
    }

    /// claim 4 — the counterweight (#367). The saturation half was already correct and is
    /// NOT part of this retraction; pinned so it is not "fixed" too.
    func testTheSaturationHalfIsUntouchedAndStillExactAtOne() throws {
        let src = try shader()
        XCTAssertTrue(src.contains("return mix(float3(l), c, s);"), """
            `echoelSaturate` changed. It is exact at s = 1 by construction (`mix(a, b, 1)` \
            returns `b`) and was never part of the #1054 defect — only the hue half was. If \
            it genuinely needed changing, this claim is the place to say why.
            """)
        XCTAssertTrue(src.contains("col = echoelSaturate(col, clamp(u.saturation, 0.0, 2.0));"), """
            The saturation step left the field pipeline or changed its clamp. The ORDER \
            matters to this slice's measurement: the lift runs first, then saturation, then \
            hue — a reorder invalidates the numbers in this file's header, so re-measure and \
            re-write them rather than only moving the line.
            """)
    }
}

// NEEDS-FOUNDER-VERIFY: Vollbild-Visual öffnen, Hue auf 0 und Saturation auf Default lassen,
// eine ruhige Passage mit tiefen Violett-/Rot-Tönen anschauen — sind die dunklen Farben jetzt
// VIOLETT statt blau-verkippt, und wirkt das Bild insgesamt gleich hell wie vorher (es darf
// NICHT dunkler geworden sein)? Zweite Probe: Hue-Regler langsam von 0 wegdrehen — der
// Übergang muss stufenlos sein; ein sichtbarer Sprung genau beim Verlassen der 0 hieße, der
// Frühausstieg und die Rotation sind sich uneinig.
