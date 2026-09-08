// TheCausticsObeyRefractionTests.swift
// Echoel — #1113: the ray optics of the light a rippled surface throws on the floor,
// pinned before any pixel depends on it.
//
// WHAT THIS GUARDS. Founder 2026-09-08: "generative and physical association Visuals weiter
// entwickeln". The shipped `fieldDepthCaustics` (style 7, in the DEFAULT slider sequence)
// calls itself CAUSTICS and computes a power curve on a sum of three sine layers; the
// sounding pitch never reaches it. `Core/WaterCaustics.swift` is the law that replaces that:
// Snell at a nearly-flat surface, illumination as the inverse Jacobian of the ray map, and a
// focusing depth the pitch moves through the dispersion relation Echoel already solves.
// This file pins each of those against a number a textbook or a ruler could check, so that a
// later "simplification" (dropping the 1 − 1/n factor, using the slope instead of the
// curvature, an unbounded 1/|det| that becomes a flash hazard) goes red in the blocking
// bundle rather than quietly turning the light back into a brightness curve.
//
// KIND (§1): **END-TO-END BEHAVIOUR** — every claim drives the shipped, Foundation-only value
// type, and two of them drive it THROUGH `FaradayDish` so the two cores are pinned as one
// chain. §3: this file does NOT compile against the parent tree (`WaterCaustics` is new
// there), so NO ASSERTION HAS A VERDICT ON THE PARENT. Grading: 0 regressions, 0 anchor
// absences, 9 FORWARD guards, 0 counterweights. Every pinned number below is a MEASURED
// value from a Python transcription of the same algorithm with the same constants (#808),
// not a prediction.
//
// ⚠️ WHAT NO TEST HERE CAN SAY: whether the resulting network LOOKS like a pool floor, and
// whether the two named choices — the saturated ripple amplitude and the intensity ceiling —
// land where the founder's eye wants them. Both are device probes. Both constants are pinned
// here so a retune moves the header prose in the same commit; neither is FORBIDDEN (#364).
//
// ⚠️ NO PRODUCTION CALLER YET, deliberately (the W1 shape that landed `FaradayDish` at
// #1100). Wiring this into the shader changes pixels for every user in the default sequence
// AND requires re-deriving that look's flash budget, because a caustic has sharper temporal
// extrema than a sine sum. That is its own slice; this one ships only the law.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheCausticsObeyRefractionTests: XCTestCase {

    // MARK: - 1. Refraction bends a quarter of the slope, not all of it

    /// `1 − 1/n` for water. A "simplification" that drops the factor (treating the ray as
    /// following the surface slope directly) would make every pattern four times too fine.
    func testTheDeflectionIsAQuarterOfTheSlope() {
        XCTAssertEqual(WaterCaustics.deflectionCoefficient(), 0.24981245311327827, accuracy: 1e-12)
        // Air (n = 1) cannot refract; a non-physical index must not produce a negative tilt.
        XCTAssertEqual(WaterCaustics.deflectionCoefficient(index: 1.0), 0.0, accuracy: 1e-15)
        XCTAssertEqual(WaterCaustics.deflectionCoefficient(index: 0.5), 0.0, accuracy: 1e-15)
        XCTAssertEqual(WaterCaustics.deflectionCoefficient(index: .nan), 0.0, accuracy: 1e-15)
    }

    // MARK: - 2. A flat surface is an evenly lit floor, not a bright one

    /// The single most important behaviour: silence must not glow. With no pattern the
    /// amplitude is zero, the focus number is zero, det J is exactly 1 and the illumination
    /// is exactly 1 — the same as no water at all.
    func testSilenceIsAnEvenlyLitFloor() {
        let k = FaradayDish.wavenumber(responseHz: 100)
        XCTAssertNotNil(k)
        let a = WaterCaustics.rippleAmplitude(patternStrength: 0)
        XCTAssertEqual(a, 0.0, accuracy: 1e-18)
        let phi = WaterCaustics.focusNumber(depthMetres: 0.006, amplitudeMetres: a, wavenumber: k ?? 0)
        XCTAssertEqual(phi, 0.0, accuracy: 1e-15)
        let det = WaterCaustics.jacobianDeterminant(focusNumber: phi, curvatureXX: -1)
        XCTAssertEqual(det, 1.0, accuracy: 1e-15)
        XCTAssertEqual(WaterCaustics.intensity(jacobianDeterminant: det), 1.0, accuracy: 1e-15)
    }

    // MARK: - 3. Pattern strength maps linearly to a bounded amplitude

    func testAmplitudeIsLinearAndClamped() {
        XCTAssertEqual(WaterCaustics.rippleAmplitude(patternStrength: 1.0), 0.00025, accuracy: 1e-18)
        XCTAssertEqual(WaterCaustics.rippleAmplitude(patternStrength: 0.5), 0.000125, accuracy: 1e-18)
        // A caller cannot drive the surface past saturation, or below flat.
        XCTAssertEqual(WaterCaustics.rippleAmplitude(patternStrength: 4.0), 0.00025, accuracy: 1e-18)
        XCTAssertEqual(WaterCaustics.rippleAmplitude(patternStrength: -2.0), 0.0, accuracy: 1e-18)
        XCTAssertEqual(WaterCaustics.rippleAmplitude(patternStrength: .nan), 0.0, accuracy: 1e-18)
    }

    // MARK: - 4. The focusing depth is millimetres, and it is the pitch that moves it

    /// Measured: the saturated ripple under a 200 Hz tone focuses 5.35 mm below the surface.
    /// The chain runs through `FaradayDish`, so this also pins that a caustic depth is
    /// derived from the SUBHARMONIC response (100 Hz), not from the drive.
    func testTheSaturatedRippleFocusesAtFiveAndAHalfMillimetres() throws {
        let k = try XCTUnwrap(FaradayDish.wavenumber(responseHz: 100))
        XCTAssertEqual(k, 1730.2168528158406, accuracy: 1e-6)
        let d = try XCTUnwrap(WaterCaustics.focusingDepth(
            amplitudeMetres: WaterCaustics.rippleAmplitudeAtFullPattern, wavenumber: k))
        XCTAssertEqual(d, 0.005348658025632117, accuracy: 1e-12)
        // At exactly that depth the focus number is 1 — the definition, closing the loop.
        let phi = WaterCaustics.focusNumber(
            depthMetres: d, amplitudeMetres: WaterCaustics.rippleAmplitudeAtFullPattern, wavenumber: k)
        XCTAssertEqual(phi, 1.0, accuracy: 1e-12)
    }

    /// An octave up divides the focusing depth by ≈2^(4/3). MEASURED 0.38990 against the
    /// pure-capillary 0.39685: the gap is the gravity term, still alive at these response
    /// frequencies, exactly as in `FaradayDish`. Pinning the measured value (not the power
    /// law) is what keeps a future "simplification" to k ∝ f^(2/3) honest at the bass end.
    func testAnOctaveUpFocusesTwoAndAHalfTimesShallower() throws {
        let kLow = try XCTUnwrap(FaradayDish.wavenumber(responseHz: 100))
        let kHigh = try XCTUnwrap(FaradayDish.wavenumber(responseHz: 200))
        let a = WaterCaustics.rippleAmplitudeAtFullPattern
        let dLow = try XCTUnwrap(WaterCaustics.focusingDepth(amplitudeMetres: a, wavenumber: kLow))
        let dHigh = try XCTUnwrap(WaterCaustics.focusingDepth(amplitudeMetres: a, wavenumber: kHigh))
        XCTAssertEqual(dHigh / dLow, 0.3898962546394769, accuracy: 1e-9)
        XCTAssertNotEqual(dHigh / dLow, 0.3968502629920499, accuracy: 1e-4,
                          "the pure capillary power law is NOT what water does here")
        XCTAssertEqual(kHigh / kLow, 1.6014945620016006, accuracy: 1e-9)
    }

    /// A flat or absent ripple never focuses at any depth.
    func testAFlatSurfaceHasNoFocusingDepth() {
        XCTAssertNil(WaterCaustics.focusingDepth(amplitudeMetres: 0, wavenumber: 1730))
        XCTAssertNil(WaterCaustics.focusingDepth(amplitudeMetres: 0.00025, wavenumber: 0))
        XCTAssertNil(WaterCaustics.focusingDepth(amplitudeMetres: .nan, wavenumber: 1730))
    }

    // MARK: - 5. Crests focus, troughs spread — the sign that makes it a caustic

    /// The whole look lives in this sign. At a crest the dimensionless curvature is −1, so
    /// det J = 1 − φ falls to zero: the light converges. At a trough it is +1, so det J
    /// = 1 + φ grows: the light spreads. Flip the sign and the picture inverts into
    /// something no pool floor does.
    func testCrestsFocusAndTroughsSpread() {
        XCTAssertEqual(WaterCaustics.jacobianDeterminant(focusNumber: 0.5, curvatureXX: -1), 0.5, accuracy: 1e-15)
        XCTAssertEqual(WaterCaustics.jacobianDeterminant(focusNumber: 0.5, curvatureXX: 1), 1.5, accuracy: 1e-15)
        // φ = 1 at a crest IS the caustic — the determinant reaches exactly zero.
        XCTAssertEqual(WaterCaustics.jacobianDeterminant(focusNumber: 1.0, curvatureXX: -1), 0.0, accuracy: 1e-15)
        // Past focus the ray map folds over: a negative determinant, which is a real state
        // and must not be clamped away — it is the second sheet of the network.
        XCTAssertEqual(WaterCaustics.jacobianDeterminant(focusNumber: 2.0, curvatureXX: -1), -1.0, accuracy: 1e-15)
        // The cross term enters squared, so it can only ever DARKEN toward focus.
        XCTAssertEqual(WaterCaustics.jacobianDeterminant(focusNumber: 1.0, curvatureXX: 0,
                                                        curvatureYY: 0, curvatureXY: 0.5),
                       0.75, accuracy: 1e-15)
        // Non-finite input must render a flat floor, never a NaN pixel.
        XCTAssertEqual(WaterCaustics.jacobianDeterminant(focusNumber: .nan, curvatureXX: -1), 1.0, accuracy: 1e-15)
    }

    // MARK: - 6. The singularity is bounded — this is a flash-safety pin, not a taste pin

    /// Ray optics predicts infinite brightness on the caustic itself. An unbounded 1/|det|
    /// riding a moving surface is a full-luminance excursion, i.e. a WCAG flash hazard, so
    /// the bound belongs in the law and not in the hope that a caller clamps.
    func testTheCausticSingularityIsBounded() {
        XCTAssertEqual(WaterCaustics.intensity(jacobianDeterminant: 0), 8.0, accuracy: 1e-12)
        XCTAssertEqual(WaterCaustics.intensity(jacobianDeterminant: 1), 1.0, accuracy: 1e-12)
        XCTAssertEqual(WaterCaustics.intensity(jacobianDeterminant: 0.25), 4.0, accuracy: 1e-12)
        XCTAssertEqual(WaterCaustics.intensity(jacobianDeterminant: 2), 0.5, accuracy: 1e-12)
        // A folded (negative) determinant is just as bright as its positive twin.
        XCTAssertEqual(WaterCaustics.intensity(jacobianDeterminant: -0.5), 2.0, accuracy: 1e-12)
        // NaN must saturate, not propagate.
        XCTAssertEqual(WaterCaustics.intensity(jacobianDeterminant: .nan), 8.0, accuracy: 1e-12)
        XCTAssertEqual(WaterCaustics.intensityCeiling, 8.0, accuracy: 1e-12)
    }

    // MARK: - 7. The two named choices are pinned so a retune moves the prose with it

    func testTheNamedChoicesAreWhatTheHeaderSays() {
        XCTAssertEqual(WaterCaustics.rippleAmplitudeAtFullPattern, 0.00025, accuracy: 1e-18)
        XCTAssertEqual(WaterCaustics.waterIndex, 1.333, accuracy: 1e-12)
    }
}
