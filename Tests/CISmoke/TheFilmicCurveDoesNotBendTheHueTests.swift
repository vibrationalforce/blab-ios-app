// TheFilmicCurveDoesNotBendTheHueTests.swift
// Echoel — #1059. Blocking bundle. HALF source-text scan, half REAL arithmetic: claims 1 and 4
// read the shader text (`Tests/CISmoke/CLAUDE.md` §1 — they prove which expression is compiled,
// never what a pixel looks like), while claims 2 and 3 execute the curve and the flash product
// in Swift, where they are ordinary numbers with no GPU in the way.
//
// ⭐ WHY THIS FILE EXISTS. The shader's closing line was
// `outCol = clamp((outCol - 0.5) * 1.06 + 0.5, 0.0, 1.0)` under a comment calling it a "gentle
// filmic S-contrast". It was neither. A straight line has no toe and no shoulder, so the name
// described a function the code did not implement; and applying it per CHANNEL rotated hue —
// a (0.10, 0, 0.50) pixel came out (0.076, 0, 0.50), its R:B ratio moving 0.20 → 0.15 — on the
// one surface whose whole claim is that a pitch has a physically derived colour. Below 0.028
// every channel clamped to zero, undoing part of the ambient wash three lines above it whose
// stated job is that the frame is NEVER a dead black. Same defect class as #1054's colour
// floor, one line later in the same chain.
//
// ⛔ AND THE REPLACEMENT HAD TO CLEAR A WCAG ARGUMENT IN ANOTHER FILE (claim 3, the one that
// makes this more than a taste change). `FlashGuard.bloomBeatGainSwing` is bounded by
// `swing × restGlowMax × (1 − ambient) × filmicMaxSlope < 0.10`, so this curve's steepest
// point is an INPUT to a flash-safety proof. Strength 0.12 was chosen because
// `1 + 0.12/2 = 1.06` reproduces the old uniform gain exactly, with every other point on the
// curve amplifying less — the product is unchanged and the bound became strict rather than
// tight. Claim 3 pins that equality so a later "make it punchier" cannot move a WCAG headroom
// without going red.
//
// ⛔ AND THE GAMUT STEP MUST NOT GO BACK TO A PER-CHANNEL CLAMP (claim 4). `outCol` can arrive
// above 1 — the intensity product upstream is unclamped — and clamping each channel is exactly
// the rotation this slice removes. Dividing by the peak keeps the ratios. The SEPARATE clamp
// further down (#578's restoration before the touch-ripple SCREEN blend) is a different line
// with a different job and must survive too; claim 4 pins both, because "fixing" this by
// deleting the later clamp would silently re-open the dark-holes artifact.
//
// ⚠️ WHAT THIS DOES NOT CLAIM: that the picture looks better. It claims the transform no longer
// moves channel ratios, that it never crushes to black, and that the flash product is
// unchanged. Whether the founder likes the grade is a device look, not a test.
//
// ⚠️ HONEST GRADING, and it does not reduce to one number because half of this file cannot be
// graded the usual way. THIRTEEN assertion statements across four claims (3 · 5 · 3 · 2). The
// five TEXT assertions were driven against both trees: 5/5 green today, and on the pre-slice
// tree FOUR are red and one green (the #578 clamp, the counterweight). The eight ARITHMETIC
// assertions of claims 2 and 3 have no red/green on that tree at all — the file would not
// COMPILE there, because `FlashGuard.filmicStrength` does not exist yet. That is a stronger
// signal than a red assertion, and it is also not an assertion count, so it is reported as
// what it is rather than folded into one. All eight were driven against today's constants in
// Python: monotone over 1000 samples, f(0)=0, f(1)=1, f(0.5)=0.5 to twelve decimals,
// f(0.028)=0.0249, measured max slope 1.060000 against a claimed 1.06.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheFilmicCurveDoesNotBendTheHueTests: XCTestCase {

    private func shader() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/Echoelmusic/Views/MetalBioView.swift")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: MetalBioView.swift could not be read — a missing anchor "
                    + "is a finding, not a pass (#454).")
            return ""
        }
        // NOT comment-stripped, deliberately: the shader is MSL inside a Swift string, so to
        // `SourceText.codeOnly` the whole body is one string literal and stripping buys
        // nothing here — while the ⛔ blocks in this file quote the old expression, so the
        // needle below is chosen to appear ONLY as compiled shader text. See the retraction
        // note in claim 1.
        return text
    }

    /// The curve, transcribed from the shipped constant. Luminance in, luminance out.
    private func filmic(_ luminance: Double) -> Double {
        let t = min(max(luminance, 0.0), 1.0)
        let shaped = 3 * t * t - 2 * t * t * t          // smoothstep(0, 1, t)
        return luminance + FlashGuard.filmicStrength * (shaped - luminance)
    }

    /// claim 1 — the compiled expression is the luminance form, and the per-channel affine is
    /// gone from the shader.
    func testTheShaderAppliesTheCurveToLuminance() throws {
        let src = try shader()
        // ⚠️ The needle is the WHOLE old statement including its trailing semicolon, so the
        // quotations of it in this file's own ⛔ blocks (which have none) cannot match it. A
        // guard whose needle can hit its own prose is the #1050 defect.
        XCTAssertFalse(src.contains("outCol = clamp((outCol - 0.5) * 1.06 + 0.5, 0.0, 1.0);"), """
            The per-channel affine is back at the end of the shader. It moves channel ratios \
            (a (0.10, 0, 0.50) pixel leaves as (0.076, 0, 0.50)) and clamps anything under \
            0.028 to black, which is a hue rotation and a crushed shadow on the surface that \
            sells physically derived colour. Shape LUMINANCE and scale the colour by the ratio.
            """)
        XCTAssertTrue(src.contains("float lumOut = lumIn + \\(FlashGuard.filmicStrengthLiteral)"), """
            The shader no longer interpolates `FlashGuard.filmicStrengthLiteral` into the \
            filmic curve. A hand-typed strength here and a derived `filmicMaxSlope` there is \
            precisely how a flash-safety bound goes stale while still reading as correct.
            """)
        XCTAssertTrue(src.contains("outCol *= (lumIn > 1e-4) ? (lumOut / lumIn) : 1.0;"), """
            The colour is no longer scaled by the luminance RATIO. That single multiply is \
            what makes this hue-preserving; without it the curve is being applied to \
            something other than luminance and the whole slice is undone.
            """)
    }

    /// claim 2 — the curve really is a curve: fixed at both ends and at mid grey, monotone,
    /// and it never crushes a lit pixel to black the way the affine did.
    func testTheCurveIsMonotoneAndCrushesNothing() {
        XCTAssertEqual(filmic(0.0), 0.0, accuracy: 1e-12, "The toe moved off zero.")
        XCTAssertEqual(filmic(1.0), 1.0, accuracy: 1e-12, "The shoulder moved off one.")
        XCTAssertEqual(filmic(0.5), 0.5, accuracy: 1e-12, """
            Mid grey is no longer a fixed point. It is what makes this a CONTRAST curve rather \
            than an exposure change — the old affine also fixed 0.5, and losing that would \
            rebrighten or redarken the whole frame as a side effect of a hue fix.
            """)
        var previous = -1.0
        for step in 0...1000 {
            let value = filmic(Double(step) / 1000.0)
            XCTAssertGreaterThanOrEqual(value, previous, """
                The curve is not monotone at \(Double(step) / 1000.0). A non-monotone tone \
                curve makes two different luminances render identically and can invert local \
                contrast — visible as banding or as an edge that reverses.
                """)
            previous = value
        }
        // The affine returned exactly 0 here. Anything at or below the ambient wash used to
        // be crushed, which contradicted the wash's own reason for existing.
        XCTAssertGreaterThan(filmic(0.028), 0.02, """
            A 0.028 luminance is being crushed toward black again. Three lines above this \
            curve the shader composes a deliberate ambient wash so the frame is NEVER a dead \
            black; a toe that zeroes the wash undoes it, and the frame goes flat-dark in the \
            calm state the visual is supposed to be best at.
            """)
    }

    /// claim 3 — the WCAG headroom in `FlashGuard` is untouched, and the two spellings of the
    /// strength cannot drift apart.
    func testTheFlashProductIsUnchangedAndTheStrengthHasOneSpelling() {
        XCTAssertEqual(Double(FlashGuard.filmicStrengthLiteral), FlashGuard.filmicStrength, """
            The Metal token and the Swift constant disagree. The shader interpolates the \
            token; `filmicMaxSlope` is derived from the constant — so a mismatch means the \
            flash bound is computed for a curve the GPU is not running.
            """)
        XCTAssertEqual(FlashGuard.filmicMaxSlope, 1.06, accuracy: 1e-12, """
            The curve's steepest point is no longer 1.06. That number is a factor in \
            `bloomBeatGainSwing`'s WCAG product (swing × 0.21 × 0.94 × maxSlope < 0.10); \
            #1059 chose strength 0.12 precisely so the product did not have to be reopened. \
            If a louder grade is genuinely wanted, re-run that product and move the swing in \
            the SAME commit — do not let a hue fix quietly spend flash headroom (#456).
            """)
        // Slope is 1 + strength · (6L − 6L² − 1); sampled rather than differentiated by hand,
        // so a change of curve SHAPE is caught too, not only a change of strength.
        var steepest = 0.0
        for step in 0...10_000 {
            let x = Double(step) / 10_000.0
            let slope = (filmic(x + 1e-6) - filmic(x - 1e-6)) / 2e-6
            steepest = Swift.max(steepest, slope)
        }
        XCTAssertEqual(steepest, FlashGuard.filmicMaxSlope, accuracy: 1e-4, """
            The curve's measured maximum slope (\(steepest)) is not what `filmicMaxSlope` \
            claims. That constant is the one the flash product multiplies by, so a curve \
            steeper than its own documented bound spends WCAG headroom nobody counted.
            """)
    }

    /// claim 4 — the counterweights (#367). Gamut is kept by peak-normalising, and the
    /// separate downstream clamp that guards the touch-ripple blend is untouched.
    func testGamutIsKeptWithoutAPerChannelClampAndTheLaterClampSurvives() throws {
        let src = try shader()
        XCTAssertTrue(src.contains("outCol = (peak > 1.0) ? (outCol / peak) : outCol;"), """
            The peak normalisation is gone. `outCol` can arrive above 1 because the intensity \
            product upstream is unclamped, and the obvious repair — clamping each channel — \
            is the very hue rotation this file exists to remove. Divide by the peak: the \
            brightest channel lands exactly on 1 and the ratios survive.
            """)
        XCTAssertTrue(src.contains("outCol = clamp(outCol, 0.0, 1.0);"), """
            #578's clamp before the touch-ripple SCREEN blend is gone. It is a DIFFERENT line \
            with a different job from the gamut step above: `outCol += ripple * (1 - outCol)` \
            only adds light while `outCol <= 1`, and past that a touch SUBTRACTS light — dark \
            holes in the brightest places. `GlitterCannotBecomeAFlashTests` pins its position; \
            this pins its existence, so a tidy-up of the filmic block cannot take it along.
            """)
    }
}

// NEEDS-FOUNDER-VERIFY: Visual im Ruhezustand (kein Ton) anschauen — das Bild darf NICHT
// flacher oder dunkler wirken als vorher; die tiefen Töne sollten eher etwas mehr Farbe halten.
// Dann laut spielen: die hellsten Stellen dürfen nicht in eine andere Farbe kippen.
