// SpectralColorTests.swift
// Echoel — the perceptual sound→colour mapper: pitch-class→OKLCH hue (octave-equivalent,
// magenta-bridged loop), pitch→lightness, amplitude→chroma, and OKLab chord mixing that
// falls toward neutral (never blows out to white).

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
import Foundation
@testable import Echoelmusic

final class SpectralColorTests: XCTestCase {

    private func spread(_ c: LinearRGB) -> Double {
        Swift.max(c.r, Swift.max(c.g, c.b)) - Swift.min(c.r, Swift.min(c.g, c.b))
    }

    func testPitchClass_isOctaveEquivalent() {
        let a = SpectralColor.pitchClass(ofFrequency: 220)
        let b = SpectralColor.pitchClass(ofFrequency: 440)
        let c = SpectralColor.pitchClass(ofFrequency: 880)
        XCTAssertEqual(a, b, accuracy: 1e-6)
        XCTAssertEqual(b, c, accuracy: 1e-6)
        XCTAssertEqual(b, 9.0, accuracy: 1e-3)   // A is 9 semitones above C
    }

    func testHue01_octaveEquivalent_andSemitoneStep() {
        XCTAssertEqual(SpectralColor.hue01(forFrequency: 220),
                       SpectralColor.hue01(forFrequency: 440), accuracy: 1e-6)
        let h0 = SpectralColor.hue01(forFrequency: 440)
        let h1 = SpectralColor.hue01(forFrequency: 440 * pow(2.0, 1.0 / 12.0))
        var d = (h1 - h0).truncatingRemainder(dividingBy: 1.0)
        if d < 0 { d += 1 }
        XCTAssertEqual(d, 1.0 / 12.0, accuracy: 1e-3)  // one semitone = 30° = 1/12 turn
    }

    func testColor_alwaysInGamut_overSweep() {
        var hz = 50.0
        while hz < 4000 {
            let c = SpectralColor.color(forFrequency: hz, amplitude: 1)
            for v in [c.r, c.g, c.b] {
                XCTAssertTrue(v.isFinite)
                XCTAssertGreaterThanOrEqual(v, 0.0)
                XCTAssertLessThanOrEqual(v, 1.0)
            }
            hz *= 1.05
        }
    }

    func testSingleNote_isSaturated_butZeroAmplitudeIsGrey() {
        XCTAssertGreaterThan(spread(SpectralColor.color(forFrequency: 440, amplitude: 1)), 0.05)
        XCTAssertLessThan(spread(SpectralColor.color(forFrequency: 440, amplitude: 0)), 0.02)
    }

    func testHigherPitch_isLighter() {
        // Isolate lightness (amplitude 0 → greys): a higher note must be brighter.
        let low = SpectralColor.color(forFrequency: 110, amplitude: 0)
        let high = SpectralColor.color(forFrequency: 880, amplitude: 0)
        XCTAssertGreaterThan(high.r, low.r)
    }

    func testChordUnison_matchesSingleNote() {
        let single = SpectralColor.color(forFrequency: 440, amplitude: 1)
        let unison = SpectralColor.color(forChord: [(440, 1), (440, 1)])
        XCTAssertEqual(single.r, unison.r, accuracy: 1e-9)
        XCTAssertEqual(single.g, unison.g, accuracy: 1e-9)
        XCTAssertEqual(single.b, unison.b, accuracy: 1e-9)
    }

    func testOctavesReinforceHue_dissonantClusterGoesNeutral() {
        // All-A octaves share a pitch-class → colour stays saturated.
        let octaves = SpectralColor.color(forChord: [(220, 1), (440, 1), (880, 1)])
        // A full chromatic cluster spreads hues around the circle → averages to neutral.
        var cluster: [(hz: Double, amplitude: Double)] = []
        for k in 0..<12 { cluster.append((261.63 * pow(2.0, Double(k) / 12.0), 1.0)) }
        let dense = SpectralColor.color(forChord: cluster)

        XCTAssertGreaterThan(spread(octaves), 0.05, "octaves should reinforce a hue")
        XCTAssertLessThan(spread(dense), 0.05, "a dense cluster should fall toward neutral")
        // ...and NOT blow out to white (the RGB-sum failure mode this avoids).
        XCTAssertLessThan(Swift.max(dense.r, Swift.max(dense.g, dense.b)), 0.95)
    }

    func testEmptyAndInvalid_returnNeutral() {
        XCTAssertEqual(SpectralColor.color(forChord: []), SpectralColor.neutral)
        let bad = SpectralColor.color(forChord: [(0, 1), (.nan, 1), (440, 0)])
        XCTAssertEqual(bad, SpectralColor.neutral)
        // Single invalid frequency → neutral grey, no crash.
        XCTAssertLessThan(spread(SpectralColor.color(forFrequency: -10, amplitude: 1)), 0.02)
    }

    func testNeutral_isGrey() {
        let n = SpectralColor.neutral
        XCTAssertEqual(n.r, n.g, accuracy: 1e-6)
        XCTAssertEqual(n.g, n.b, accuracy: 1e-6)
        XCTAssertGreaterThan(n.r, 0.0)
        XCTAssertLessThan(n.r, 1.0)
    }

    // MARK: - Cousto table verification (founder 2026-07-08: "ist die Liste von Hans
    // Cousto physikalisch mathematisch korrekt oder haben wir unser eigenes besseres
    // System?"). Answer, pinned as tests: his table IS pure octave doubling (f x 2^40)
    // at Kammerton ~432 — arithmetically exact — and our visibleWavelength() reproduces
    // it for every in-band entry. Ours GENERALIZES it: continuous in frequency (any
    // detune/microtone), Kammerton-aware, and octave-CONSISTENT at the band edges
    // (Cousto's fixed 2^40 maps the same pitch class F to red-violet at 363 Hz but
    // near-UV at 726 Hz because visible light spans ~1.04 octaves; our nearest-green
    // rounding keeps one pitch class = one colour).

    func testCousto_a432_matchesOurPhysics() {
        // Cousto row a = 432 Hz <-> 475 THz. lambda = c/f = 2.998e17 / 4.75e14 = 631 nm.
        let wl = SpectralColor.visibleWavelength(forToneHz: 432)
        let coustoWl = 2.99792458e17 / (432.0 * pow(2.0, 40))
        XCTAssertEqual(wl, coustoWl, accuracy: 0.5, "our transposition IS Cousto's x2^40 here")
        XCTAssertEqual(wl, 631.2, accuracy: 1.0)
    }

    func testCousto_f363_deepRed_matches() {
        // Cousto row f = 363 Hz <-> 399 THz -> ~751 nm deep red.
        let wl = SpectralColor.visibleWavelength(forToneHz: 363)
        XCTAssertEqual(wl, 2.99792458e17 / (363.0 * pow(2.0, 40)), accuracy: 0.5)
        XCTAssertEqual(wl, 751.0, accuracy: 1.5)
    }

    func testOctaveConsistency_beatsCoustoAtTheBandEdge() {
        // 363 Hz and 726 Hz are the SAME pitch class (F). Cousto's fixed 2^40 sends
        // 726 to ~375 nm (violet, outside 380-780); our rounding picks 2^39 so both
        // octaves land on the SAME colour — octave equivalence, as an instrument needs.
        let low = SpectralColor.visibleWavelength(forToneHz: 363)
        let high = SpectralColor.visibleWavelength(forToneHz: 726)
        XCTAssertEqual(low, high, accuracy: 0.5, "one pitch class -> one colour, any octave")
        XCTAssertGreaterThanOrEqual(high, 380)
        XCTAssertLessThanOrEqual(high, 780)
    }

    // MARK: notePosition — colours at the RIGHT PLACE (pitch-space anchors)

    func testNotePosition_octaveHeight_lowAtBottom() {
        // Grid law: low notes at the bottom (+y up in the shader field coordinate).
        let c3 = SpectralColor.notePosition(forHz: 130.81)   // C3
        let c4 = SpectralColor.notePosition(forHz: 261.63)   // C4
        let c5 = SpectralColor.notePosition(forHz: 523.25)   // C5
        XCTAssertLessThan(c3.y, c4.y)
        XCTAssertLessThan(c4.y, c5.y)
        XCTAssertEqual(c4.y, 0, accuracy: 1e-6, "octave 4 is the vertical centre")
    }

    func testNotePosition_withinOctave_risesLeftToRight() {
        // Column order: C at the left, rising rightward — same note order as the grid.
        let c = SpectralColor.notePosition(forHz: 261.63)    // C4
        let e = SpectralColor.notePosition(forHz: 329.63)    // E4
        let a = SpectralColor.notePosition(forHz: 440.0)     // A4
        XCTAssertLessThan(c.x, e.x)
        XCTAssertLessThan(e.x, a.x)
        XCTAssertEqual(c.x, -0.75, accuracy: 0.02, "C sits at the left edge of the octave")
    }

    func testNotePosition_sameNoteName_sameColumn_anyOctave() {
        // A3 and A5 share the x column (pitch-class), only the height differs.
        let a3 = SpectralColor.notePosition(forHz: 220)
        let a5 = SpectralColor.notePosition(forHz: 880)
        XCTAssertEqual(a3.x, a5.x, accuracy: 1e-6)
        XCTAssertNotEqual(a3.y, a5.y)
    }

    func testNotePosition_extremeRegisters_stayOnScreen_andInvalidIsCentred() {
        for hz in [8.2, 20.0, 4186.0, 12543.0] {
            let p = SpectralColor.notePosition(forHz: hz)
            XCTAssertLessThanOrEqual(abs(p.x), 0.75 + 1e-9)
            XCTAssertLessThanOrEqual(abs(p.y), 0.8 + 1e-9)
        }
        let bad = SpectralColor.notePosition(forHz: .nan)
        XCTAssertEqual(bad.x, 0); XCTAssertEqual(bad.y, 0)
    }

    func testKammertonAwareness_beyondTheFixedTable() {
        // The table is frozen at one Kammerton; our mapping shifts with the real
        // played frequency (A4=440 vs 432 must give measurably different colours).
        let wl440 = SpectralColor.visibleWavelength(forToneHz: 440)
        let wl432 = SpectralColor.visibleWavelength(forToneHz: 432)
        XCTAssertLessThan(wl440, wl432, "higher tone -> shorter wavelength")
        XCTAssertGreaterThan(wl432 - wl440, 5, "the Kammerton difference is visible, not noise")
    }
}
#endif
