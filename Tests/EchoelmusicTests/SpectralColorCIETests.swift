// SpectralColorCIETests.swift
// Echoel — colorimetric wavelength→RGB via the CIE 1931 analytic fit, and the
// octave-transposition tone→wavelength physics. Foundation-only (no AVFoundation
// gate), so this file is UNGATED.
//
// ⛔ CORRECTED 2026-07-27: the header claimed "ci.yml EXECUTES these on Linux". It does
// not — every build/test job in ci.yml runs on macos-26 via xcodebuild, and
// quick-test.yml states outright that the suite cannot compile on Linux. The same false
// claim was corrected in PatternEngineTransportRelayTests; it matters because it would
// push a session into writing Linux-portability constraints for code no Linux job sees.

import XCTest
import Foundation
@testable import Echoelmusic

final class SpectralColorCIETests: XCTestCase {

    func testCIE_returnsNonNegativeXYZ() {
        var wl = 380.0
        while wl <= 780 {
            let (x, y, z) = SpectralColor.cie1931(wl)
            XCTAssertGreaterThanOrEqual(x, 0); XCTAssertGreaterThanOrEqual(y, 0); XCTAssertGreaterThanOrEqual(z, 0)
            XCTAssertTrue(x.isFinite && y.isFinite && z.isFinite)
            wl += 5
        }
    }

    func testWavelengthRGB_inGamutAndFiniteOverVisibleRange() {
        var wl = 380.0
        while wl <= 780 {
            let c = SpectralColor.wavelengthToLinearRGB(wl)
            for v in [c.r, c.g, c.b] {
                XCTAssertTrue(v.isFinite)
                XCTAssertGreaterThanOrEqual(v, 0.0)
                XCTAssertLessThanOrEqual(v, 1.0)
            }
            wl += 2
        }
    }

    func testPrimaryWavelengths_haveCorrectDominantChannel() {
        let red = SpectralColor.wavelengthToLinearRGB(700)
        XCTAssertGreaterThan(red.r, red.g); XCTAssertGreaterThan(red.r, red.b)
        let green = SpectralColor.wavelengthToLinearRGB(530)
        XCTAssertGreaterThan(green.g, green.r); XCTAssertGreaterThan(green.g, green.b)
        let blue = SpectralColor.wavelengthToLinearRGB(460)
        XCTAssertGreaterThan(blue.b, blue.r); XCTAssertGreaterThan(blue.b, blue.g)
        // ~580 nm reads yellow: red & green both strong, blue weak.
        let yellow = SpectralColor.wavelengthToLinearRGB(580)
        XCTAssertGreaterThan(yellow.r, yellow.b); XCTAssertGreaterThan(yellow.g, yellow.b)
    }

    func testVisibleWavelength_isOctaveEquivalentAndInBand() {
        // Integer-octave transposition → a note and its octave map to the SAME colour.
        let a4 = SpectralColor.visibleWavelength(forToneHz: 440)
        let a5 = SpectralColor.visibleWavelength(forToneHz: 880)
        let a3 = SpectralColor.visibleWavelength(forToneHz: 220)
        XCTAssertEqual(a4, a5, accuracy: 1e-6)
        XCTAssertEqual(a4, a3, accuracy: 1e-6)
        for hz in [40.0, 261.63, 440.0, 2000.0, 8000.0] {
            let wl = SpectralColor.visibleWavelength(forToneHz: hz)
            XCTAssertGreaterThanOrEqual(wl, 380.0)
            XCTAssertLessThanOrEqual(wl, 780.0)
        }
        // Guards: non-finite / non-positive → safe mid-green fallback, no crash.
        XCTAssertEqual(SpectralColor.visibleWavelength(forToneHz: 0), 555.0, accuracy: 1e-6)
    }

    // MARK: displayComponents — the shared note-grid tint (Kammerton-reactive)

    func testDisplayComponents_boundedByLiftAndOne() {
        for hz in [55.0, 261.63, 440.0, 1760.0, 7040.0] {
            let c = SpectralColor.displayComponents(forToneHz: hz)
            for v in [c.r, c.g, c.b] {
                XCTAssertTrue(v.isFinite)
                XCTAssertGreaterThanOrEqual(v, 0.22 - 1e-9)   // white lift floor
                XCTAssertLessThanOrEqual(v, 1.0 + 1e-9)
            }
        }
    }

    func testDisplayComponents_shiftWithKammerton() {
        // The founder's requirement made testable: the SAME pitch (A4) at a
        // different concert pitch is a different sounding frequency → a
        // different wavelength → a visibly different grid tint.
        let at440 = SpectralColor.displayComponents(forToneHz: 440)
        let at432 = SpectralColor.displayComponents(forToneHz: 432)
        let delta = abs(at440.r - at432.r) + abs(at440.g - at432.g) + abs(at440.b - at432.b)
        XCTAssertGreaterThan(delta, 0.005, "an 8 Hz Kammerton shift must move the grid colour")
    }

    func testDisplayComponents_octaveEquivalent() {
        // Rows an octave apart share one colour (integer-octave transposition) —
        // the raster reads as pitch-CLASS colour, like the touch fretboard.
        let a4 = SpectralColor.displayComponents(forToneHz: 440)
        let a5 = SpectralColor.displayComponents(forToneHz: 880)
        XCTAssertEqual(a4.r, a5.r, accuracy: 1e-9)
        XCTAssertEqual(a4.g, a5.g, accuracy: 1e-9)
        XCTAssertEqual(a4.b, a5.b, accuracy: 1e-9)
    }

    func testDisplayComponents_guardsNonFiniteInput() {
        let c = SpectralColor.displayComponents(forToneHz: .nan)
        for v in [c.r, c.g, c.b] { XCTAssertTrue(v.isFinite) }
    }

    // MARK: - Closed spectral circle (purple-line seam) — founder 2026-07-12:
    // "Da fehlt jetzt gerade das F komplett als Farbe … die Chords werden gar
    // nicht visualisiert." At A4=440 the pitch class F fell exactly on the
    // octave-fold seam (390/780 nm) where CIE response → 0 → black.

    private func hz(midi: Int, a4: Double = 440) -> Double {
        a4 * pow(2.0, Double(midi - 69) / 12.0)
    }

    func testToneCircle_everyPitchClassIsVisible_at440and432() {
        for a4 in [440.0, 432.0] {
            for midi in 36...96 {   // C2…C7
                let c = SpectralColor.toneLinearRGB(forToneHz: hz(midi: midi, a4: a4))
                let peak = max(c.r, max(c.g, c.b))
                XCTAssertGreaterThan(peak, 0.35,
                    "midi \(midi) @ a4=\(a4) must be a visible colour, got peak \(peak)")
            }
        }
    }

    func testToneCircle_FIsAPurple_notBlack_at440() {
        let f4 = SpectralColor.toneLinearRGB(forToneHz: hz(midi: 65))   // F4 ≈ 349.23
        XCTAssertGreaterThan(max(f4.r, max(f4.g, f4.b)), 0.5, "F4 must be present")
        // Purple: red and blue carry the colour, green stays low.
        XCTAssertGreaterThan(f4.b, f4.g)
        XCTAssertGreaterThan(f4.r, f4.g)
    }

    func testToneCircle_AStaysSpectralRed_at440() {
        let a4 = SpectralColor.toneLinearRGB(forToneHz: 440)
        XCTAssertGreaterThan(a4.r, a4.g)
        XCTAssertGreaterThan(a4.r, a4.b)
        // Inside the spectral span the closed circle agrees with the raw physics.
        let raw = SpectralColor.wavelengthToLinearRGB(SpectralColor.visibleWavelength(forToneHz: 440))
        XCTAssertEqual(a4.r, raw.r, accuracy: 1e-9)
        XCTAssertEqual(a4.g, raw.g, accuracy: 1e-9)
        XCTAssertEqual(a4.b, raw.b, accuracy: 1e-9)
    }

    func testToneCircle_octaveEquivalence() {
        let f4 = SpectralColor.toneLinearRGB(forToneHz: hz(midi: 65))
        let f5 = SpectralColor.toneLinearRGB(forToneHz: hz(midi: 77))
        XCTAssertEqual(f4.r, f5.r, accuracy: 1e-6)
        XCTAssertEqual(f4.g, f5.g, accuracy: 1e-6)
        XCTAssertEqual(f4.b, f5.b, accuracy: 1e-6)
    }

    func testToneCircle_isContinuousAcrossTheSeam() {
        // Sweep one full octave in fine steps: no adjacent pair may jump —
        // the seam blend and its brightness lift must be continuous at both
        // boundaries (an earlier draft normalized only the violet side and
        // jumped ×1.44 there).
        var prev: LinearRGB?
        var f = 330.0                       // E4 …
        while f < 660.0 {                   // … E5, crossing the F seam
            let c = SpectralColor.toneLinearRGB(forToneHz: f)
            if let p = prev {
                XCTAssertLessThan(abs(c.r - p.r), 0.12, "r jump at \(f) Hz")
                XCTAssertLessThan(abs(c.g - p.g), 0.12, "g jump at \(f) Hz")
                XCTAssertLessThan(abs(c.b - p.b), 0.12, "b jump at \(f) Hz")
            }
            prev = c
            f *= 1.002                      // ~3.5 cents per step
        }
    }

    func testToneCircle_everyConcertPitch392to466_staysVisible() {
        // Founder 2026-07-12: "Wie ist es mit den anderen Kammertönen?
        // Verschiebt sich alles dann korrekt?" The mapping is CONTINUOUS in
        // frequency (no 12-colour table), so ANY concert pitch shifts every
        // note's colour smoothly. Sweep the whole historical range — French
        // baroque 392, baroque 415, classical 430, Verdi 432, diapason normal
        // 435, 440, modern orchestras 442/444, Chorton 466 — across C1…C8.
        var a4 = 392.0
        while a4 <= 466.0 {
            for midi in stride(from: 24, through: 108, by: 1) {
                let c = SpectralColor.toneLinearRGB(forToneHz: hz(midi: midi, a4: a4))
                XCTAssertGreaterThan(max(c.r, max(c.g, c.b)), 0.35,
                    "midi \(midi) @ a4=\(a4) must stay visible")
            }
            a4 += 2.0
        }
    }

    func testToneCircle_isFrequencyTrue_notNameTrue() {
        // The real translation law: colour belongs to the SOUNDING FREQUENCY.
        // G#4 at concert pitch 440 (≈415.30 Hz) must be the same colour as A4
        // at concert pitch 415.30 — so ANY tuning system (equal, just, custom)
        // that produces Hz gets that Hz's physical colour.
        let gSharpAt440 = SpectralColor.toneLinearRGB(forToneHz: 440 * pow(2.0, -1.0 / 12.0))
        let aAt41530 = SpectralColor.toneLinearRGB(forToneHz: 415.3046975770599)
        XCTAssertEqual(gSharpAt440.r, aAt41530.r, accuracy: 1e-9)
        XCTAssertEqual(gSharpAt440.g, aAt41530.g, accuracy: 1e-9)
        XCTAssertEqual(gSharpAt440.b, aAt41530.b, accuracy: 1e-9)
    }

    func testToneCircle_guardsBadInput() {
        for bad in [Double.nan, .infinity, 0, -5] {
            let c = SpectralColor.toneLinearRGB(forToneHz: bad)
            for v in [c.r, c.g, c.b] {
                XCTAssertTrue(v.isFinite)
                XCTAssertGreaterThanOrEqual(v, 0); XCTAssertLessThanOrEqual(v, 1)
            }
        }
    }

    // MARK: - The physical chord mix (founder 2026-07-27: one colour, every surface)

    /// THE assertion that earns its keep here. `physicalColor(forChord:)` mixes in OKLab,
    /// so it round-trips every note through `linearToOKLab` → average → `oklabToLinear`.
    /// A single note must therefore come back EXACTLY as `toneLinearRGB` — which is the
    /// one thing a wrong inverse matrix (the real risk in this change) cannot fake. Note
    /// this is NOT a tautology: the two sides are computed by different code paths.
    func testPhysicalChord_singleNote_roundTripsToTheToneColourItself() {
        for hz in [110.0, 261.626, 349.23, 440.0, 880.0, 1760.0] {
            let direct = SpectralColor.toneLinearRGB(forToneHz: hz)
            let viaMix = SpectralColor.physicalColor(forChord: [(hz: hz, amplitude: 1)])
            // 1e-6, not 1e-9: Ottosson's forward and inverse constants are INDEPENDENTLY
            // rounded 10-digit approximations, not an exactly-inverted pair — `M2 · M2⁻¹`
            // is off identity by ~3.7e-8 and the cube in `oklabToLinear` amplifies it, so
            // the true round-trip floor is ~3e-7. 1e-6 still falsifies what this test is
            // for: a transposed or mistyped row moves the result by ~1e-2, four orders up.
            XCTAssertEqual(viaMix.r, direct.r, accuracy: 1e-6, "r at \(hz) Hz")
            XCTAssertEqual(viaMix.g, direct.g, accuracy: 1e-6, "g at \(hz) Hz")
            XCTAssertEqual(viaMix.b, direct.b, accuracy: 1e-6, "b at \(hz) Hz")
        }
    }

    /// The OKLab inverse must be an actual inverse. Pinned separately from the mix so a
    /// failure says WHICH half broke.
    func testLinearToOKLab_isTheInverseOfOklabToLinear() {
        for c in [SpectralColor.wavelengthToLinearRGB(460),
                  SpectralColor.wavelengthToLinearRGB(530),
                  SpectralColor.wavelengthToLinearRGB(620),
                  LinearRGB(r: 0, g: 0, b: 0),
                  LinearRGB(r: 1, g: 1, b: 1)] {
            let back = SpectralColor.oklabToLinear(SpectralColor.linearToOKLab(c))
            XCTAssertEqual(back.r, c.r, accuracy: 1e-6)   // see the note above on 1e-6
            XCTAssertEqual(back.g, c.g, accuracy: 1e-6)
            XCTAssertEqual(back.b, c.b, accuracy: 1e-6)
        }
    }

    /// The founder's actual claim, stated as a test: the colour comes from OCTAVE
    /// transposition, so notes an octave apart are the same colour. If someone ever
    /// replaces the mapping with a non-octave-equivalent stretch (the retired
    /// `visibleColor` was exactly that), this fails.
    func testPhysicalChord_isOctaveEquivalent() {
        let a4 = SpectralColor.physicalColor(forChord: [(hz: 440, amplitude: 1)])
        for hz in [110.0, 220.0, 880.0, 1760.0] {
            let other = SpectralColor.physicalColor(forChord: [(hz: hz, amplitude: 1)])
            XCTAssertEqual(other.r, a4.r, accuracy: 1e-9, "r at \(hz) Hz vs A4")
            XCTAssertEqual(other.g, a4.g, accuracy: 1e-9, "g at \(hz) Hz vs A4")
            XCTAssertEqual(other.b, a4.b, accuracy: 1e-9, "b at \(hz) Hz vs A4")
        }
    }

    /// Invalid input must not produce NaN channels on a path that drives DMX fixtures.
    func testPhysicalChord_invalidInput_isNeutralNotNaN() {
        XCTAssertEqual(SpectralColor.physicalColor(forChord: []), SpectralColor.neutral)
        let junk = SpectralColor.physicalColor(forChord: [(hz: 0, amplitude: 1),
                                                         (hz: .nan, amplitude: 1),
                                                         (hz: 440, amplitude: 0)])
        XCTAssertEqual(junk, SpectralColor.neutral)
        for v in [junk.r, junk.g, junk.b] { XCTAssertTrue(v.isFinite) }
    }
}
