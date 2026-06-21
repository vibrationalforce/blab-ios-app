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
}
#endif
