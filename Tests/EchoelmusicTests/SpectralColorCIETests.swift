// SpectralColorCIETests.swift
// Echoel — colorimetric wavelength→RGB via the CIE 1931 analytic fit, and the
// octave-transposition tone→wavelength physics. Foundation-only (no AVFoundation
// gate) so ci.yml EXECUTES these on Linux.

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
}
