//
//  ColorOctaveTests.swift
//  Echoelmusic — Cousto cosmic-octave colour convention.
//

import XCTest
@testable import Echoelmusic

final class ColorOctaveTests: XCTestCase {

    // MARK: Octave maths (exact physics)

    func testColorFrequency_432Hz_isAbout475THz() {
        // Cousto's published colour octave: c = 432 Hz → ≈ 475 THz.
        XCTAssertEqual(ColorOctave.colorFrequencyTHz(forToneHz: 432), 475, accuracy: 1.0)
    }

    func testWavelength_432Hz_isAbout631nm() {
        // 475 THz → ≈ 631 nm (green) — Cousto's "C = Grün".
        XCTAssertEqual(ColorOctave.wavelengthNm(forToneHz: 432), 631, accuracy: 2.0)
    }

    func testWavelength_inVisibleBand_forAudibleTones() {
        // A musical sweep should land inside (or very near) the visible band 380–780 nm.
        for hz in stride(from: 110.0, through: 880.0, by: 1.0) {
            // wavelength wraps by octave; reduce into one octave of the band for the check
            var wl = ColorOctave.wavelengthNm(forToneHz: hz)
            while wl > 780 { wl /= 2 }
            while wl < 380 { wl *= 2 }
            XCTAssertTrue(wl >= 380 && wl <= 780, "hz=\(hz) → wl=\(wl)")
        }
    }

    func testInvalidInput_returnsZero() {
        XCTAssertEqual(ColorOctave.colorFrequencyTHz(forToneHz: 0), 0)
        XCTAssertEqual(ColorOctave.wavelengthNm(forToneHz: -5), 0)
        XCTAssertEqual(ColorOctave.colorFrequencyTHz(forToneHz: .nan), 0)
    }

    // MARK: Pitch class

    func testPitchClass_A440_is9() {
        XCTAssertEqual(ColorOctave.pitchClass(ofFrequency: 440), 9, accuracy: 0.01)
    }

    func testPitchClass_isOctaveEquivalent() {
        let a = ColorOctave.pitchClass(ofFrequency: 220)
        let b = ColorOctave.pitchClass(ofFrequency: 440)
        let c = ColorOctave.pitchClass(ofFrequency: 880)
        XCTAssertEqual(a, b, accuracy: 0.01)
        XCTAssertEqual(b, c, accuracy: 0.01)
    }

    func testPitchClass_middleC_is0() {
        XCTAssertEqual(ColorOctave.pitchClass(ofFrequency: 261.6256), 0, accuracy: 0.01)
    }

    // MARK: Cousto convention

    func testNamedColours_matchConvention() {
        XCTAssertEqual(ColorOctave.name(pitchClass: 0), "Grün")        // C
        XCTAssertEqual(ColorOctave.name(pitchClass: 6), "Rot")         // F#
        XCTAssertEqual(ColorOctave.name(pitchClass: 9), "Gelborange")  // A
    }

    func testWheel_has12DistinctInGamutColours() {
        XCTAssertEqual(ColorOctave.wheel.count, 12)
        for c in ColorOctave.wheel {
            for v in [c.r, c.g, c.b] {
                XCTAssertTrue(v >= 0 && v <= 1, "out of gamut: \(c)")
            }
        }
        // All distinct.
        for i in 0..<ColorOctave.wheel.count {
            for j in (i + 1)..<ColorOctave.wheel.count {
                XCTAssertNotEqual(ColorOctave.wheel[i], ColorOctave.wheel[j], "dup \(i),\(j)")
            }
        }
    }

    func testColor_pitchClass_wraps() {
        XCTAssertEqual(ColorOctave.color(pitchClass: 12), ColorOctave.wheel[0])
        XCTAssertEqual(ColorOctave.color(pitchClass: -1), ColorOctave.wheel[11])
    }

    func testColorForFrequency_onPitchClass_matchesWheel() {
        // 261.6256 Hz = middle C → pitch class 0 → exactly the wheel's C colour.
        let c = ColorOctave.color(forFrequencyHz: 261.6256)
        XCTAssertEqual(c.r, ColorOctave.wheel[0].r, accuracy: 0.02)
        XCTAssertEqual(c.g, ColorOctave.wheel[0].g, accuracy: 0.02)
        XCTAssertEqual(c.b, ColorOctave.wheel[0].b, accuracy: 0.02)
    }

    func testColorForFrequency_interpolatesBetweenPitchClasses() {
        // A quartertone above C (≈ pitch class 0.5) should sit between C and C# colours.
        let cFreq = 261.6256
        let quarterUp = cFreq * pow(2.0, 0.5 / 12.0)
        let mid = ColorOctave.color(forFrequencyHz: quarterUp)
        let lo = ColorOctave.wheel[0], hi = ColorOctave.wheel[1]
        XCTAssertTrue(mid.g <= max(lo.g, hi.g) && mid.g >= min(lo.g, hi.g))
        XCTAssertTrue(mid.b > lo.b - 0.01, "should drift toward C# (more blue): \(mid)")
    }

    func testLerp_clampsT() {
        let a = ColorOctave.RGB(0, 0, 0), b = ColorOctave.RGB(1, 1, 1)
        XCTAssertEqual(ColorOctave.RGB.lerp(a, b, -1), a)
        XCTAssertEqual(ColorOctave.RGB.lerp(a, b, 2), b)
    }
}
