// SpectralColorTests.swift
// Echoel — the sound→colour mapper: pitch-class, the Cousto/physics wavelength checks,
// note POSITION in the visual field, and the chord mixer's boundary behaviour.
//
// REWRITTEN 2026-07-28 for the DELETION of the pitch-class OKLCH hue circle (#197).
// SEVEN tests here pinned `color(forChord:)`/`color(forFrequency:)`/`hue01`, which is the
// only reason that dead second colour language survived. FOUR moved onto
// `physicalColor(forChord:)` — unison == the single note, octaves stay saturated, the mix
// is really a mix, empty/invalid → neutral. THREE did not, because the physical mapping
// genuinely lacks their laws:
//   · "amplitude → saturation": there is no chroma ramp. Amplitude is the mixing WEIGHT
//     only (intensity is a separate dimmer). The "zero amplitude → grey" half DOES still
//     hold, but by a different mechanism — `physicalColor` FILTERS `amplitude > 0`, so an
//     all-silent chord returns `neutral` — and that is asserted below via the `(440, 0)`
//     entry, not via desaturation.
//   · "higher pitch → lighter": absent. Lightness comes from the CIE eye response at the
//     transposed wavelength, which is not monotonic in pitch.
//   · "one semitone = 1/12 turn of a hue circle": there is no hue circle. The other half
//     of that test — octave equivalence — survives, pinned in SpectralColorCIETests.
// And one property was deliberately WEAKENED rather than dropped: "a dense cluster falls
// toward NEUTRAL grey" is measured false for the physical mixer (the CIE locus plus the
// purple line is a lopsided horseshoe, not an evenly spaced circle — a 12-note chromatic
// cluster comes out a bounded purple). What survives is that the cluster is markedly LESS
// saturated than a unison stack, which is what actually proves an average happened.

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

    func testPhysicalChord_staysColoured_overSweep() {
        // This deliberately does NOT assert isFinite/0…1: `oklabToLinear` ends in
        // `clamp01` on all three channels, and `clamp01` maps non-finite → 0, so those
        // three assertions are true by construction one line before the return and cannot
        // fail however badly the mapping breaks. (Measured over this exact sweep, the
        // PRE-clamp values never leave [0.03, 0.94] either, so the clamp is not even
        // engaging.) The falsifiable property is that a two-note chord never degenerates
        // to grey — a broken CIE fit or a collapsed OKLab round-trip lands near neutral.
        var hz = 50.0
        while hz < 4000 {
            let c = SpectralColor.physicalColor(forChord: [(hz, 1), (hz * 1.5, 0.6)])
            XCTAssertGreaterThan(spread(c), 0.01,
                                 "a sounding chord at \(Int(hz)) Hz must have a colour")
            hz *= 1.05
        }
    }

    func testPhysicalChordUnison_matchesTheSingleNoteColour() {
        // A unison must survive the OKLab round-trip unchanged. This corroborates the
        // inverse pair on the two-note AVERAGING path (wSum == 2); the single-note sweep
        // and the inverse pair on their own are pinned in SpectralColorCIETests. Measured
        // error 3.7e-8 — 1e-9 would be pinning cbrt's last bits, 1e-6 is still far below
        // any 8-bit fixture or display step.
        let single = SpectralColor.toneLinearRGB(forToneHz: 440)
        let unison = SpectralColor.physicalColor(forChord: [(440, 1), (440, 1)])
        XCTAssertEqual(single.r, unison.r, accuracy: 1e-6)
        XCTAssertEqual(single.g, unison.g, accuracy: 1e-6)
        XCTAssertEqual(single.b, unison.b, accuracy: 1e-6)
    }

    func testPhysicalMixer_averagesTheChord_andNeverWashesOut() {
        // `toneLinearRGB` is octave-cyclic, so these three are the SAME colour; the mix of
        // them must stay fully saturated. (The octave-equivalence law itself is pinned at
        // 1e-9 in SpectralColorCIETests — this assertion would survive a broken fold, so
        // don't read it as the octave test.)
        let octaves = SpectralColor.physicalColor(forChord: [(220, 1), (440, 1), (880, 1)])
        XCTAssertGreaterThan(spread(octaves), 0.05, "a unison/octave stack stays saturated")

        var cluster: [(hz: Double, amplitude: Double)] = []
        for k in 0..<12 { cluster.append((261.63 * pow(2.0, Double(k) / 12.0), 1.0)) }
        let dense = SpectralColor.physicalColor(forChord: cluster)

        // THE load-bearing assertion: an implementation that just returned the LOUDEST
        // note's colour would pass every other test in this file and in
        // SpectralColorCIETests. Only the contrast catches it — measured, a chromatic
        // cluster spreads 0.267 against the octave stack's 1.0, while pick-the-loudest
        // gives 1.0 for both. (The deleted hue-circle test asserted the same thing as
        // "falls toward neutral"; that absolute is false here, the contrast is not.)
        XCTAssertLessThan(spread(dense), spread(octaves) * 0.6,
                          "the mixer must average the chord, not take its loudest note")
        // ...and the failure mode an RGB sum would cause instead: everything near white.
        XCTAssertLessThan(Swift.min(dense.r, Swift.min(dense.g, dense.b)), 0.90,
                          "a dense chord must not wash out to white")
    }

    func testPhysicalChord_emptyAndInvalid_returnNeutral() {
        XCTAssertEqual(SpectralColor.physicalColor(forChord: []), SpectralColor.neutral)
        // Zero, NaN and zero-amplitude entries are each filtered out; all three gone → neutral.
        let bad = SpectralColor.physicalColor(forChord: [(0, 1), (.nan, 1), (440, 0)])
        XCTAssertEqual(bad, SpectralColor.neutral)
        // A single invalid note among valid ones must be dropped, not poison the average.
        let mixed = SpectralColor.physicalColor(forChord: [(440, 1), (.nan, 1)])
        XCTAssertEqual(mixed, SpectralColor.physicalColor(forChord: [(440, 1)]))
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
        // notePosition floors log2(hz/C0) to bucket the octave — the commonly-quoted
        // 2-decimal note table (130.81/261.63/523.25) rounds DOWN from the true C0*2^n
        // values (130.8128/261.6256/523.2511), so 130.81 and 523.25 floor into the
        // octave BELOW their real one (2.99997→2, 4.99997→4) while 261.63 rounds up
        // and floors correctly (4.00002→4) — a false failure from test-literal
        // precision, not from Sources. Use the exact C0*2^n multiples instead.
        let c0 = 16.351597831287414
        let c3 = SpectralColor.notePosition(forHz: c0 * 8)    // C3
        let c4 = SpectralColor.notePosition(forHz: c0 * 16)   // C4
        let c5 = SpectralColor.notePosition(forHz: c0 * 32)   // C5
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
