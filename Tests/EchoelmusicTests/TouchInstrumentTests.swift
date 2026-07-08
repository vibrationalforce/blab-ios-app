// TouchInstrumentTests.swift
// Echoel — guards the pure touch→music mapping behind the fullscreen play
// surface (founder 2026-07-07: the visual as a multi-touch instrument).
// Coherence is the contract: every reachable touch MUST land inside the key.

import XCTest
@testable import Echoelmusic

final class TouchInstrumentTests: XCTestCase {

    func testEveryTouchLandsInsideTheKey() {
        // The whole point: whatever the fingers do, it belongs to the sound.
        for scale in [Scale.minor, .major, .dorian, .lydian, .phrygian] {
            let key = MusicalKey(root: 2, scale: scale)   // D-rooted
            for xi in 0...20 {
                for yi in 0...10 {
                    let pitch = TouchPitchMap.pitch(normX: Double(xi) / 20,
                                                    normY: Double(yi) / 10,
                                                    key: key)
                    XCTAssertTrue(key.contains(pitch),
                                  "\(scale) x=\(xi)/20 y=\(yi)/10 → \(pitch) is OUTSIDE the key")
                }
            }
        }
    }

    func testXSweepsOneOctaveOfDegrees_leftIsTonic() {
        let key = MusicalKey(root: 0, scale: .minor)      // C minor
        let left = TouchPitchMap.pitch(normX: 0, normY: 0.5, key: key)
        XCTAssertEqual(left % 12, 0, "far left = the tonic")
        // Rightmost degree stays BELOW the next octave's tonic (one octave across).
        let right = TouchPitchMap.pitch(normX: 0.999, normY: 0.5, key: key)
        XCTAssertLessThan(right, left + 12)
        XCTAssertGreaterThan(right, left)
    }

    func testYBandsAreMonotonic_upIsHigher() {
        let key = MusicalKey(root: 0, scale: .minor)
        let low = TouchPitchMap.pitch(normX: 0.1, normY: 0.05, key: key)
        let mid = TouchPitchMap.pitch(normX: 0.1, normY: 0.5, key: key)
        let high = TouchPitchMap.pitch(normX: 0.1, normY: 0.95, key: key)
        XCTAssertEqual(mid - low, 12, "middle band is one octave above low")
        XCTAssertEqual(high - mid, 12, "top band is one octave above middle")
    }

    func testVelocity_floorsCapsAndRespondsToAreaAndForce() {
        // Feather touch (no force hardware, tiny radius) is audible but soft. Range was
        // lifted so played notes cut through the mix a bit more (floor 0.3, cap 0.95).
        let feather = TouchPitchMap.velocity(forceNorm: 0, radiusPoints: 5)
        XCTAssertEqual(feather, 0.45, accuracy: 0.001)
        // Flat finger (big contact area) plays louder even with zero force reading.
        let flat = TouchPitchMap.velocity(forceNorm: 0, radiusPoints: 30)
        XCTAssertGreaterThan(flat, feather)
        XCTAssertLessThanOrEqual(flat, 0.95)
        // Hard press wins over area; everything stays under the cap.
        let press = TouchPitchMap.velocity(forceNorm: 1.0, radiusPoints: 8)
        XCTAssertEqual(press, 0.95, accuracy: 0.001)
        // Garbage inputs stay clamped.
        XCTAssertGreaterThanOrEqual(TouchPitchMap.velocity(forceNorm: -3, radiusPoints: -10), 0.3)
        XCTAssertLessThanOrEqual(TouchPitchMap.velocity(forceNorm: 9, radiusPoints: 900), 0.95)
    }

    func testSlideRetriggersOnlyOnPitchChange() {
        XCTAssertFalse(TouchPitchMap.slideRetriggers(oldPitch: 60, newPitch: 60),
                       "jitter inside one degree must not machine-gun the note")
        XCTAssertTrue(TouchPitchMap.slideRetriggers(oldPitch: 60, newPitch: 62))
    }

    func testMorphCutoffScale_positionShapesTheTone() {
        // Centre of the surface = neutral (scale 1), regardless of depth.
        XCTAssertEqual(TouchPitchMap.morphCutoffScale(normY: 0.5, depth: 1), 1, accuracy: 0.001)
        // Full depth: bottom = half the cutoff (darker), top = double (brighter).
        XCTAssertEqual(TouchPitchMap.morphCutoffScale(normY: 0, depth: 1), 0.5, accuracy: 0.001)
        XCTAssertEqual(TouchPitchMap.morphCutoffScale(normY: 1, depth: 1), 2.0, accuracy: 0.001)
        // Depth 0 = morph off: always neutral.
        XCTAssertEqual(TouchPitchMap.morphCutoffScale(normY: 0.9, depth: 0), 1, accuracy: 0.001)
        // Monotonic: higher on the surface is never darker.
        var prev: Float = 0
        for yi in 0...10 {
            let s = TouchPitchMap.morphCutoffScale(normY: Double(yi) / 10, depth: 0.6)
            XCTAssertGreaterThanOrEqual(s, prev)
            prev = s
        }
        // Garbage inputs clamp instead of exploding the filter.
        XCTAssertEqual(TouchPitchMap.morphCutoffScale(normY: .nan, depth: .infinity), 1, accuracy: 0.001)
        XCTAssertEqual(TouchPitchMap.morphCutoffScale(normY: 99, depth: 5), 2.0, accuracy: 0.001)
    }

    func testEdgeInputsNeverCrash_andStayInKey() {
        let key = MusicalKey(root: 11, scale: .harmonicMinor)  // B, awkward root
        for (x, y) in [(-1.0, -1.0), (2.0, 2.0), (0.0, 1.0), (1.0, 0.0), (0.5, 1.0)] {
            let p = TouchPitchMap.pitch(normX: x, normY: y, key: key)
            XCTAssertTrue(key.contains(p), "edge (\(x),\(y)) → \(p) must stay in key")
            XCTAssertTrue((0...127).contains(p), "MIDI range")
        }
    }
}
