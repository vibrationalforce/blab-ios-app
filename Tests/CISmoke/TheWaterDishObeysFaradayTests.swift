// TheWaterDishObeysFaradayTests.swift
// Echoel — #1100: the physics of a dish of water on a speaker, pinned before any pixel exists.
//
// WHAT THIS GUARDS. Founder 2026-09-07: "ich will auch wirklich reale Wasser Klang Bilder
// haben, wie als wenn ein Lautsprecher mit Wasser füllt." `Core/FaradayDish.swift` is the
// physics of that experiment for ONE tone — subharmonic response, the full gravity–capillary
// dispersion relation, a viscous threshold that rises with pitch, a square-root onset. This
// file pins each of those against numbers a ruler or a textbook could check, so that a later
// "simplification" (a linear pitch→spacing map, the drive frequency instead of half of it, a
// look that ripples in silence) goes red in the blocking bundle rather than quietly turning the
// water picture back into a fudge.
//
// KIND (§1): **END-TO-END BEHAVIOUR** — every claim drives the shipped, Foundation-only value
// type. §3: this file does NOT compile against the parent tree (the type is new there), so no
// assertion has a verdict on the parent; the numbers were driven by a Python transcription of
// the same algorithm (same constants, same 64-step log-bisection, same clamps) and every pin
// below is a MEASURED value from it, not a prediction (#808).
//
// ⚠️ WHAT NO TEST HERE CAN SAY: whether the lattice LOOKS like the founder's photo, and whether
// the pitch at which it fades to a mirror is where his ear expects it. Both are device probes.
// The one constant that moves the second, `speakerAccelerationAtFullDrive`, is pinned here so
// a retune moves the header prose in the same commit — it is NOT forbidden (#364).
//
// ⚠️ ONE TONE. The core says so and the plan's NICHT-bauen list says why (a chord-driven
// Faraday dish is not physics). Nothing here pins a multi-tone path because none may exist.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheWaterDishObeysFaradayTests: XCTestCase {

    private static let twoToTheTwoThirds = pow(2.0, 2.0 / 3.0)

    private func dish(_ hz: Double, drive: Double = 1) throws -> FaradayDish.Response {
        try XCTUnwrap(FaradayDish.response(driveHz: hz, drive: drive),
                      "FaradayDish.response returned nil for a finite positive drive \(hz) Hz")
    }

    // MARK: - 1 · The response is the subharmonic

    func testTheSurfaceOscillatesAtHalfTheDriveFrequency() throws {
        for hz in [20.0, 130.81, 261.63, 1000.0, 20000.0] {
            XCTAssertEqual(try dish(hz).responseHz, hz / 2, """
                the dish answers \(hz) Hz at something other than half of it. Faraday waves \
                are SUBHARMONIC — the lattice a tone makes has the wavelength of a wave at half \
                its frequency. Using the drive frequency renders every pattern 2^(2/3) ≈ 1.59× \
                too fine, an octave of fineness a ruler can see on a still frame.
                """)
        }
    }

    // MARK: - 2 · The wavelength obeys the dispersion relation, both branches

    /// Above ~100 Hz the capillary branch dominates: k ∝ f^(2/3). Measured worst deviation of
    /// k(2f)/k(f) from 2^(2/3) over drive 200 … 2000 Hz is 0.89 % (at 200 Hz, where the
    /// gravity term is still 4 %); the tolerance is 1.5 %.
    func testTheCapillaryBranchFollowsTheTwoThirdsPowerLaw() throws {
        for hz in [200.0, 300, 400, 500, 700, 1000, 1400, 2000] {
            let ratio = try dish(2 * hz).wavenumber / dish(hz).wavenumber
            XCTAssertEqual(ratio, Self.twoToTheTwoThirds, accuracy: 0.015 * Self.twoToTheTwoThirds, """
                k(2f)/k(f) at f = \(hz) Hz is \(ratio), not 2^(2/3) ≈ 1.587. One octave up must \
                make the ripple spacing × 0.63 — that is the capillary dispersion ω² ≈ σk³/ρ. A \
                linear or logarithmic pitch→spacing map fails this by construction.
                """)
        }
    }

    /// COUNTERWEIGHT: the FULL relation is solved, not the power-law shortcut. At 20–40 Hz the
    /// gravity term is 42–58 % of the restoring force, so the octave ratio is NOT 2^(2/3):
    /// measured 1.728 (+8.9 %). A pure-capillary shortcut would print exactly 1.587 here.
    func testTheGravityBranchIsStillSolvedAtTheBassEnd() throws {
        let ratio = try dish(40).wavenumber / dish(20).wavenumber
        XCTAssertGreaterThan(ratio, Self.twoToTheTwoThirds * 1.05, """
            k(40 Hz)/k(20 Hz) is \(ratio), within 5 % of the capillary power law. At the bass \
            end the gravity term is alive (capillaryFraction 0.42 at 20 Hz) and the ratio must \
            be visibly larger than 2^(2/3). This is the branch a woofer actually drives; a \
            solver that drops g·k has been "simplified" into the wrong fluid.
            """)
        let bass = try dish(20)
        XCTAssertEqual(bass.capillaryFraction, 0.424, accuracy: 0.013, """
            capillaryFraction at 20 Hz is \(bass.capillaryFraction); measured 0.424 for water \
            3 mm deep. The gravity/capillary split is what the shader may use as a symmetry \
            driver — if it moved, the header's Binks–van de Water sentence moves with it.
            """)
        XCTAssertEqual(bass.depthFactor, 0.737, accuracy: 0.015, """
            tanh(k·h) at 20 Hz is \(bass.depthFactor); measured 0.737 for a 3 mm layer. \
            Below 1 means the depth is IN the relation — a deep-water shortcut prints 1 here.
            """)
    }

    /// A ruler fact: middle C makes ripples 3.02 mm apart on water. And spacing shrinks
    /// monotonically with pitch across the whole audible range.
    func testMiddleCMakesThreeMillimetreRipplesAndHigherNotesMakeFinerOnes() throws {
        let c4Millimetres = try dish(261.63).wavelength * 1000
        XCTAssertEqual(c4Millimetres, 3.023, accuracy: 0.06, """
            λ at C4 is \(c4Millimetres) mm; measured 3.023 mm for water. \
            This is the number a founder can check with a ruler on the real dish.
            """)
        var previous = Double.infinity
        for hz in stride(from: 20.0, through: 20000.0, by: 20.0) {
            let lambda = try dish(hz).wavelength
            XCTAssertLessThan(lambda, previous, "wavelength did not shrink at \(hz) Hz")
            previous = lambda
        }
        let depthAt100 = try dish(100).depthFactor
        XCTAssertGreaterThanOrEqual(depthAt100, 0.99, """
            tanh(k·h) at 100 Hz is \(depthAt100), below 0.99. The header claims \
            the layer is effectively deep from ~100 Hz up (measured 0.9967 there); if the depth \
            or the relation changed, that sentence changes with it.
            """)
    }

    // MARK: - 3 · The threshold rises with pitch; silence is a mirror

    func testTheThresholdIsOfOrderGAtTwoHundredHertzAndRisesWithPitch() throws {
        let at200 = try dish(200).thresholdAcceleration
        XCTAssertEqual(at200, 8.70, accuracy: 0.26, """
            a_c at 200 Hz is \(at200) m/s²; measured 8.70 (0.89 g) for water from \
            a_c = 8νkω/tanh(kh). The literature order of magnitude for water at a few hundred \
            hertz is ~1 g — a threshold far from that is the wrong formula or the wrong fluid.
            """)
        var previous = 0.0
        for hz in stride(from: 20.0, through: 20000.0, by: 20.0) {
            let a = try dish(hz).thresholdAcceleration
            XCTAssertGreaterThan(a, previous, "threshold did not rise at \(hz) Hz")
            previous = a
        }
    }

    func testSilenceIsAFlatMirrorAtEveryPitch() throws {
        for hz in [20.0, 200, 2000, 20000] {
            let quiet = try dish(hz, drive: 0)
            XCTAssertEqual(quiet.patternStrength, 0, "a silent speaker ripples at \(hz) Hz")
            XCTAssertFalse(quiet.isPatterned, "a silent speaker is patterned at \(hz) Hz")
        }
        XCTAssertEqual(try dish(200, drive: .nan).patternStrength, 0, """
            a NaN drive produced a pattern. Non-finite loudness must read as silence, not as \
            "some" — this value reaches a shader uniform.
            """)
    }

    /// At full drive (≈ 20 g) the bass patterns and the treble does not — the honest version
    /// of the founder's photo, where the lattice fades to a mirror as the tone climbs.
    func testFullDriveRipplesAtBassAndStaysFlatAtTwentyKilohertz() throws {
        XCTAssertTrue(try dish(130.81).isPatterned, "C3 at full drive is a mirror")
        XCTAssertEqual(try dish(130.81).patternStrength, 1, "C3 at full drive is not saturated")
        XCTAssertFalse(try dish(20000).isPatterned, """
            20 kHz at full drive is patterned. Its threshold is ~19 000 m/s² against a full \
            drive of \(FaradayDish.speakerAccelerationAtFullDrive) — a real speaker cannot \
            pattern water there, and a look that ripples at every pitch is not this experiment.
            """)
    }

    // MARK: - 4 · The onset is a square root of the excess

    func testTheLatticeGrowsAsTheSquareRootOfTheExcess() throws {
        let threshold = try dish(200).thresholdAcceleration
        func strength(_ multiple: Double) throws -> Double {
            try dish(200, drive: multiple * threshold / FaradayDish.speakerAccelerationAtFullDrive)
                .patternStrength
        }
        XCTAssertEqual(try strength(1.0), 0, accuracy: 1e-9, "at exactly the threshold the surface is still flat")
        let quarterOver = try strength(1.25)
        XCTAssertEqual(quarterOver, 0.5, accuracy: 1e-6, """
            at 1.25 × a_c the strength is \(quarterOver), not 0.5. The supercritical \
            onset is A ∝ √ε with ε = a/a_c − 1: ε = 0.25 → √0.25 = 0.5 at saturationExcess 1.
            """)
        XCTAssertEqual(try strength(2.0), 1, accuracy: 1e-9, "twice the threshold is full strength (saturationExcess = 1)")
        XCTAssertEqual(try strength(4.0), 1, accuracy: 1e-9, "strength must cap at 1 — it is a shader mix weight")
        var previous = 0.0
        for step in 0 ... 100 {
            let s = try dish(200, drive: Double(step) / 100).patternStrength
            XCTAssertGreaterThanOrEqual(s, previous, "strength fell as drive rose at step \(step)")
            previous = s
        }
    }

    // MARK: - 5 · The caption number: how high the dish still patterns

    func testTheHighestPatternedPitchIsMeasuredAndFallsWithDrive() throws {
        let full = try XCTUnwrap(FaradayDish.highestPatternedDriveHz(drive: 1))
        let half = try XCTUnwrap(FaradayDish.highestPatternedDriveHz(drive: 0.5))
        XCTAssertEqual(full, 1301.7, accuracy: 26, """
            at full drive the dish patterns up to \(full) Hz; measured 1301.7 Hz for 200 m/s². \
            This is the pitch the header quotes as "≈ 1.3 kHz" — if `speakerAccelerationAtFullDrive` \
            was retuned, move that sentence and this pin together.
            """)
        XCTAssertEqual(half, 859.3, accuracy: 17, "at half drive the reach is \(half) Hz; measured 859.3")
        XCTAssertLessThan(half, full, "a quieter speaker must pattern LESS of the range, not more")
        XCTAssertNil(FaradayDish.highestPatternedDriveHz(drive: 0), "silence has no patterned pitch")
        XCTAssertNil(FaradayDish.highestPatternedDriveHz(drive: 0.001), """
            a drive of 0.2 m/s² is below even the 20 Hz threshold (0.21 m/s²) and must report \
            nil, not the range floor — the caption would otherwise promise ripples that cannot form.
            """)
    }

    // MARK: - 6 · Inputs are sanitised at the boundary

    func testTheInputsAreSanitisedAtTheBoundary() throws {
        XCTAssertNil(FaradayDish.response(driveHz: .nan, drive: 1), "NaN pitch must be refused")
        XCTAssertNil(FaradayDish.response(driveHz: .infinity, drive: 1), "infinite pitch must be refused")
        XCTAssertNil(FaradayDish.response(driveHz: -5, drive: 1), "negative pitch must be refused")
        XCTAssertNil(FaradayDish.response(driveHz: 0, drive: 1), "zero pitch must be refused")
        let low = try dish(5)
        XCTAssertEqual(low.driveHz, 20, "5 Hz must clamp to the 20 Hz floor (the renderer's toneHz clamp)")
        XCTAssertEqual(low.responseHz, 10, "the clamped drive's response is half of the CLAMPED value")
        XCTAssertEqual(try dish(1e6).driveHz, 20000, "1 MHz must clamp to the 20 kHz ceiling")
        XCTAssertEqual(try dish(200, drive: 3).driveAcceleration,
                       FaradayDish.speakerAccelerationAtFullDrive, "drive above 1 must clamp to full")
        XCTAssertEqual(try dish(200, drive: -1).driveAcceleration, 0, "negative drive must clamp to silence")
    }

    // MARK: - 7 · Lattice symmetry: a stated choice with a measured direction (#1101)

    /// Binks & van de Water: symmetry RISES with drive frequency in a low-viscosity layer.
    /// The two anchors are a choice; the DIRECTION and the numbers below are measured.
    func testTheLatticeIsSquareInTheBassAndHexagonalFromMidRange() throws {
        func hex(_ hz: Double) throws -> Double {
            FaradayDish.latticeHexagonality(capillaryFraction: try dish(hz).capillaryFraction)
        }
        XCTAssertEqual(try hex(20), 0, "a 20 Hz dish (capillary fraction 0.42) must be square")
        XCTAssertEqual(try hex(100), 0, "a 100 Hz dish (capillary fraction 0.894) must still be square")
        XCTAssertEqual(try hex(200), 0.746, accuracy: 0.02, "200 Hz is mid-transition; measured 0.746")
        XCTAssertEqual(try hex(261.63), 0.916, accuracy: 0.02, "C4 is mostly hexagonal; measured 0.916")
        XCTAssertEqual(try hex(1000), 1, accuracy: 1e-9, "1 kHz must be fully hexagonal")
        var previous = -1.0
        for hz in stride(from: 20.0, through: 2000.0, by: 10.0) {
            let h = try hex(hz)
            XCTAssertGreaterThanOrEqual(h, previous, "hexagonality fell at \(hz) Hz — the measured direction is UP")
            previous = h
        }
        XCTAssertEqual(FaradayDish.latticeHexagonality(capillaryFraction: .nan), 0, "NaN must read as square")
        XCTAssertEqual(FaradayDish.latticeHexagonality(capillaryFraction: 5), 1, "above the top anchor is hexagonal, clamped")
        XCTAssertEqual(FaradayDish.squareLatticeCapillaryFraction, 0.90, "the square anchor moved — re-derive the pins above")
        XCTAssertEqual(FaradayDish.hexagonalLatticeCapillaryFraction, 0.985, "the hexagonal anchor moved — re-derive the pins above")
    }

    // MARK: - 8 · The named choices are pinned, not forbidden

    func testTheTwoRenderingChoicesAreTheNumbersTheHeaderExplains() {
        XCTAssertEqual(FaradayDish.speakerAccelerationAtFullDrive, 200, """
            `speakerAccelerationAtFullDrive` moved. Retuning it is ALLOWED (#364) — it is the one \
            founder-tunable here — but the header's derivation (100 dB SPL, 12-inch cone, ≈ 20 g), \
            its "patterns reach ≈ 1.3 kHz" sentence, and the reach pin above all describe 200. \
            Move them in the same commit.
            """)
        XCTAssertEqual(FaradayDish.saturationExcess, 1, """
            `saturationExcess` moved. Allowed — but the onset claim above pins 0.5 at 1.25 × a_c \
            and 1 at 2 × a_c for the value 1; re-derive those numbers in the same commit.
            """)
        XCTAssertEqual(FaradayDish.Fluid.water,
                       FaradayDish.Fluid(surfaceTension: 0.0728, density: 998.0,
                                         kinematicViscosity: 1.0e-6, depth: 0.003), """
            `Fluid.water` is no longer water at 20 °C, 3 mm deep. Every measured number in this \
            file was driven for exactly those four values; a different liquid or depth is a \
            legitimate change that re-derives all of them.
            """)
    }
}
