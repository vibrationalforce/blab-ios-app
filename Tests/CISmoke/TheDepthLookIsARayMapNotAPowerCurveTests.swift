// TheDepthLookIsARayMapNotAPowerCurveTests.swift
// Echoel — style 7 ("Depth"), in the BLOCKING bundle.
//
// WHAT #1117 FIXED, AND WHY IT NEEDED A GATE. The shipped `fieldDepthCaustics` called itself
// CAUSTICS and computed `pow(0.5 + 0.14 * (three sine layers), gamma)` — a brightness curve
// on a sine sum. A real caustic is a SINGULARITY of a ray map, not a steep power curve. The
// second half of the defect was worse and is the one a user could see: its ONLY length scale
// was `mix(3.0, 5.0, breath)`, so THE SOUNDING PITCH NEVER REACHED THIS LOOK — the exact
// defect #1078 removed from `fieldWater`, still sitting in a style that
// `LookBlendMap.defaultSequence` puts in front of every user.
//
// #1113 pinned the law first (`Core/WaterCaustics.swift`, deliberately with no caller);
// #1117 wired it. The floor is now I = 1/|det J| with J = I + β·Hess(h), evaluated at three
// depths of the SAME surface — the one `FaradayDish` already solves and `MetalBioView`
// already carries to the GPU as `dishK`/`dishStrength`. The dish seen from above and the
// light beneath it are one experiment drawn twice.
//
// ⚠️ WHAT THIS FILE CAN AND CANNOT PROVE. There is no Metal compiler and no GPU here, so
// every claim below is either a SOURCE-TEXT scan of the shader string or a call into the
// Swift law. It proves that the pitch reaches the function, that the numbers are the law's
// and not retyped, and that the law behaves at the two boundaries that matter. It proves
// NOTHING about how the result looks; that is a founder judgement on a device
// (NEEDS-FOUNDER-VERIFY: does the network read as light on a pool floor, and does an octave
// up visibly tighten it?). `TheShippedShaderActuallyCompilesTests` covers compilation.
//
// ⚠️ IT DOES NOT FREEZE THE LOOK (#364). Claim 5 is a COUNTERWEIGHT, not a ban: it fails if
// the focus number drops below the value at which a caustic can exist at all, and its
// message says which prose to move when the number changes on purpose.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheDepthLookIsARayMapNotAPowerCurveTests: XCTestCase {

    private static let renderer = "Sources/Echoelmusic/Views/MetalBioView.swift"

    private func rendererSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(Self.renderer), encoding: .utf8)
    }

    /// The body of the shader function, so a claim about it cannot be satisfied by a match
    /// somewhere else in a 2000-line file.
    private func causticFunctionBody() throws -> String {
        let source = try rendererSource()
        guard let start = source.range(of: "float fieldDepthCaustics(") else {
            XCTFail("""
                `float fieldDepthCaustics(` no longer exists in \(Self.renderer), so every \
                claim here checked nothing (#454: a missing ANCHOR fails, it does not skip). \
                If the look was renamed or retired, retire this file in the same commit and \
                take its `LookBlendMap.library` row and its flash-budget row with it.
                """)
            return ""
        }
        guard let end = source.range(of: "\n    }", range: start.upperBound ..< source.endIndex) else {
            XCTFail("could not find the end of fieldDepthCaustics — the file's indentation changed")
            return ""
        }
        return String(source[start.lowerBound ..< end.upperBound])
    }

    // MARK: - 1 · The sounding pitch reaches the look

    func testTheCausticIsDrivenByTheDishSurfaceAndNotByBreathAlone() throws {
        let body = try causticFunctionBody()
        guard !body.isEmpty else { return }
        XCTAssertTrue(body.contains("float k, float strength"), """
            `fieldDepthCaustics` no longer takes the dish's wavenumber and pattern strength. \
            Those two arguments ARE the sounding pitch: `dishK` comes from \
            `FaradayDish.wavenumber`'s gravity–capillary solve, so an octave up makes the \
            network 2^(2/3) finer. Without them this look is back to the pre-#1117 state, \
            where the only length scale was the breath and the tone reached the picture not \
            at all — while the look sits in `LookBlendMap.defaultSequence`.
            """)
        let source = try rendererSource()
        XCTAssertTrue(source.contains("fieldDepthCaustics(pf, phase, coh, breath, u_dishK, u_dishStrength)"), """
            `styleField` no longer hands the dish uniforms to `fieldDepthCaustics`. The \
            signature can keep the parameters and still receive nothing — that is why this \
            claim reads the CALL and not only the declaration.
            """)
    }

    // MARK: - 2 · The defect itself, named, so it cannot come back by copy-paste

    func testBreathIsNoLongerTheWavelengthOfThisLook() throws {
        let body = try causticFunctionBody()
        guard !body.isEmpty else { return }
        XCTAssertFalse(body.contains("mix(3.0, 5.0, breath)"), """
            The breath-as-wavelength line is back in `fieldDepthCaustics`. This is the exact \
            expression #1117 removed and the same class #1078 removed from `fieldWater`: in a \
            Faraday cell the drive FREQUENCY sets the wavelength and the drive AMPLITUDE sets \
            whether a pattern appears at all — putting breath on the wavelength swaps the two \
            knobs and drops the tone out of the picture. Breath may move the viewing DEPTH \
            here (it does, `mix(0.8, 1.2, breath)`), never the ripple spacing.
            """)
        XCTAssertFalse(body.contains("mix(3.0, 6.0, coh)"), """
            The old `pow(net, mix(3.0, 6.0, coh))` gamma curve is back. That exponent was how \
            the pre-#1117 look FAKED filaments; the filaments are now the locus det J = 0 and \
            need no steep curve. A high gamma on top of a real caustic crushes the dark cells \
            the network is read against.
            """)
    }

    // MARK: - 3 · Every number is the law's, not a retyped copy

    func testTheShaderSpendsTheSwiftLawsNumbersAndNotItsOwn() throws {
        let body = try causticFunctionBody()
        guard !body.isEmpty else { return }
        let required = [
            "WaterCaustics.renderFocusNumberAtFullPatternMetalLiteral",
            "WaterCaustics.intensityCeilingMetalLiteral",
            "WaterCaustics.depthLayerFocusRatioMetalLiterals",
            "WaterCaustics.depthLayerWeightMetalLiterals",
            "WaterCaustics.depthLayerWeightSumMetalLiteral",
            "WaterCaustics.renderFullBrightIntensityMetalLiteral",
        ]
        for token in required {
            XCTAssertTrue(body.contains(token), """
                `fieldDepthCaustics` no longer interpolates `\(token)`. A number typed into \
                the Metal string instead of interpolated from the Swift law can drift from \
                it silently, and one of these is a FLASH-SAFETY bound (the intensity \
                ceiling): ray optics diverges at a caustic, and an unbounded division riding \
                a moving surface is a full-luminance excursion. This is the \
                `SpectralColor`/`FlashGuard` twinning convention, applied to the one look \
                whose brightness is a reciprocal.
                """)
        }
    }

    // MARK: - 4 · The two boundaries the law must get right (BEHAVIOUR, not text)

    func testSilenceIsAnEvenlyLitFloorAndNotABlackFrame() {
        // strength 0 ⇒ φ = 0 ⇒ det J = 1 at every depth ⇒ intensity exactly 1.
        let lit = WaterCaustics.layeredIntensity(focusNumber: 0, curvatureXX: 0, curvatureYY: 0)
        XCTAssertEqual(lit, 1.0, accuracy: 1e-12, """
            A flat surface no longer returns exactly 1. This is not a cosmetic constant: the \
            shader divides this by `renderFullBrightIntensity` to get its field, so 1 is what \
            makes SILENCE a calm evenly lit ground. A value near 0 would cold-launch the app \
            into a black frame on a look that is in the default sequence; a large value would \
            make an unrippled dish glow, which is the opposite of the physics.
            """)
        // A weighted mean of bounded intensities can never exceed the bound.
        let folded = WaterCaustics.layeredIntensity(focusNumber: 3.0, curvatureXX: -1, curvatureYY: -1)
        XCTAssertLessThanOrEqual(folded, WaterCaustics.intensityCeiling, """
            The layered intensity exceeded `intensityCeiling`. Each layer is individually \
            bounded and the layers are averaged by weight, so this can only break if the \
            normaliser stopped dividing by the weight sum — which would also brighten the \
            shipped look by 85 %.
            """)
        // Non-finite curvature must not poison the floor (engineering.md: sanitize at the boundary).
        XCTAssertTrue(WaterCaustics.layeredIntensity(focusNumber: .nan, curvatureXX: 0).isFinite,
                      "a non-finite focus number produced a non-finite floor brightness")
    }

    // MARK: - 5 · COUNTERWEIGHT — the look must be able to HAVE a caustic

    func testTheFocusNumberIsHighEnoughForANetworkToExist() {
        // On h = ½(cos kx + cos ky) the normalised curvature is −½cos kx, so
        // det J = (1 − ½φ·cos kx)(1 − ½φ·cos ky) and a fold needs cos kx = 2/φ.
        // Below φ = 2 that has no solution ANYWHERE on the surface: smooth banding only.
        XCTAssertGreaterThan(WaterCaustics.renderFocusNumberAtFullPattern, 2.0, """
            `renderFocusNumberAtFullPattern` is \(WaterCaustics.renderFocusNumberAtFullPattern), \
            which is at or below 2. On the square standing surface this look renders, a \
            caustic exists only where cos(kx) = 2/φ, so at φ ≤ 2 there is NO fold anywhere and \
            the look degenerates to smooth banding — while still being called "Depth Caustics" \
            in `LookBlendMap.library` and on the website. This claim does not forbid changing \
            the number (#364); it forbids changing it into a name that lies. If the look is \
            deliberately becoming a banding look, rename it and move this file, the constant's \
            doc, and the shader's header comment in the same commit.
            """)
        // The deepest layer folds further than the first — that IS the depth cue.
        guard let first = WaterCaustics.depthLayerFocusRatios.first,
              let last = WaterCaustics.depthLayerFocusRatios.last else {
            return XCTFail("the depth-layer ratio list is empty — the look has no layers left")
        }
        XCTAssertGreaterThan(last, first, """
            The last depth layer no longer sits deeper than the first. φ is proportional to \
            depth, so an increasing ratio list is what makes the three layers three DEPTHS \
            rather than three redundant copies — the whole reason this look may keep the name \
            "Depth" after #1117 replaced its fake parallax with real ones.
            """)
        XCTAssertEqual(WaterCaustics.depthLayerFocusRatios.count,
                       WaterCaustics.depthLayerWeights.count, """
            The ratio and weight lists have different lengths. `layeredIntensity` zips them, \
            so the extra entries would be silently dropped and the shader — which unrolls all \
            three by hand — would compute something the Swift law does not.
            """)
    }
}
