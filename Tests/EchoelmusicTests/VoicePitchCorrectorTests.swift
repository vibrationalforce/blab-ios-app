// VoicePitchCorrectorTests.swift
// Echoel — Voice Live VL1+VL2 (the Syng legacy): the autotune maths must snap
// to the SESSION key on the SESSION Kammerton grid (432 ≠ 440!), converge
// deterministically at partial retune speeds, and the harmony intervals must
// be scale-true (a third above E in C major is G, +3 — never a blind +4).

import XCTest
@testable import Echoelmusic

final class VoicePitchCorrectorTests: XCTestCase {

    private let cMajor = MusicalKey(root: 0, scale: .major)
    private let cMinor = MusicalKey(root: 0, scale: .minor)

    // MARK: - VL1: correction targets

    func testSharpA440InputSnapsToA() {
        var corrector = VoicePitchCorrector(key: MusicalKey(root: 9, scale: .minor),
                                            a4Hz: 440, strength: 1, retuneSpeed: 1)
        // 445 Hz ≈ A4 + 19.6 cents → target A4 (midi 69) at 440 Hz.
        let c = corrector.process(detectedHz: 445, dt: 0.01)
        XCTAssertEqual(c.targetMidi, 69)
        XCTAssertEqual(c.targetHz ?? 0, 440, accuracy: 1e-9)
        XCTAssertEqual(Double(c.ratio), 440.0 / 445.0, accuracy: 1e-4)
    }

    func testKammerton432GridShiftsTheTarget() {
        // THE Echoel test: at a 432 Hz session, a sung 440 is ~32 cents SHARP
        // of A — the corrector must pull DOWN to 432, not accept 440.
        var corrector = VoicePitchCorrector(key: MusicalKey(root: 9, scale: .minor),
                                            a4Hz: 432, strength: 1, retuneSpeed: 1)
        let c = corrector.process(detectedHz: 440, dt: 0.01)
        XCTAssertEqual(c.targetMidi, 69)
        XCTAssertEqual(c.targetHz ?? 0, 432, accuracy: 1e-9)
        XCTAssertEqual(Double(c.ratio), 432.0 / 440.0, accuracy: 1e-4)
    }

    func testOutOfKeyNoteSnapsToNearestScaleTone() {
        var corrector = VoicePitchCorrector(key: cMajor, a4Hz: 440,
                                            strength: 1, retuneSpeed: 1)
        // C#4 (midi 61) exactly: nearest in C major is C (60) or D (62) — the
        // tie resolves to the LOWER note (deterministic contract).
        let cSharp = 440.0 * pow(2.0, (61.0 - 69.0) / 12.0)
        let c = corrector.process(detectedHz: cSharp, dt: 0.01)
        XCTAssertEqual(c.targetMidi, 60)
    }

    func testStrengthScalesTheCorrection() {
        var half = VoicePitchCorrector(key: cMajor, a4Hz: 440,
                                       strength: 0.5, retuneSpeed: 1)
        // 30 cents sharp of A4... A4 not in C major? A IS in C major (degree 5).
        let sharpA = 440.0 * pow(2.0, 30.0 / 1200.0)
        let c = half.process(detectedHz: sharpA, dt: 0.01)
        // Full correction would be −30 cents; strength 0.5 applies −15.
        XCTAssertEqual(c.appliedCents, -15, accuracy: 0.5)
    }

    func testRetuneSpeedConvergesMonotonically() {
        var slow = VoicePitchCorrector(key: cMajor, a4Hz: 440,
                                       strength: 1, retuneSpeed: 0.5)
        let sharpA = 440.0 * pow(2.0, 40.0 / 1200.0)
        var last = 0.0
        for _ in 0..<100 {
            let c = slow.process(detectedHz: sharpA, dt: 0.01)
            XCTAssertLessThanOrEqual(c.appliedCents, last + 1e-9,
                                     "correction must move monotonically toward the target")
            last = c.appliedCents
        }
        // After 1 s at speed 0.5 (τ ≈ 180 ms) the correction is essentially complete.
        XCTAssertEqual(last, -40, accuracy: 2.0)
    }

    func testUnvoicedRelaxesTowardBypass() {
        var corrector = VoicePitchCorrector(key: cMajor, a4Hz: 440,
                                            strength: 1, retuneSpeed: 1)
        _ = corrector.process(detectedHz: 452, dt: 0.01)   // establish a correction
        var c = VoicePitchCorrection.bypass
        for _ in 0..<20 { c = corrector.process(detectedHz: nil, dt: 0.05) }
        XCTAssertNil(c.targetMidi)
        XCTAssertEqual(Double(c.ratio), 1.0, accuracy: 1e-3)
    }

    func testGarbageInputIsBypassNotCrash() {
        var corrector = VoicePitchCorrector(key: cMajor, a4Hz: 440)
        XCTAssertEqual(corrector.process(detectedHz: 0, dt: 0.01).targetMidi, nil)
        XCTAssertEqual(corrector.process(detectedHz: -5, dt: 0.01).targetMidi, nil)
        XCTAssertEqual(corrector.process(detectedHz: .nan, dt: .nan).targetMidi, nil)
        let r = corrector.process(detectedHz: .infinity, dt: 0.01).ratio
        XCTAssertTrue(r.isFinite)
    }

    func testNearestInKeyTieBreaksLow() {
        // fracMidi exactly between two in-key notes → lower wins.
        XCTAssertEqual(VoicePitchCorrector.nearestInKeyMidi(to: 61.0, key: cMajor), 60)
        // Slightly above the midpoint → upper wins.
        XCTAssertEqual(VoicePitchCorrector.nearestInKeyMidi(to: 61.2, key: cMajor), 62)
        // In-key input maps to itself.
        XCTAssertEqual(VoicePitchCorrector.nearestInKeyMidi(to: 64.05, key: cMajor), 64)
    }

    // MARK: - VL2: scale-true harmony intervals

    func testDiatonicThirdsInCMajor() {
        // C→E is a major third (+4); E→G and D→F are minor thirds (+3).
        XCTAssertEqual(VoiceHarmony.interval(from: 60, degreesUp: 2, key: cMajor), 4)
        XCTAssertEqual(VoiceHarmony.interval(from: 64, degreesUp: 2, key: cMajor), 3)
        XCTAssertEqual(VoiceHarmony.interval(from: 62, degreesUp: 2, key: cMajor), 3)
    }

    func testDiatonicThirdInCMinorIsMinor() {
        XCTAssertEqual(VoiceHarmony.interval(from: 60, degreesUp: 2, key: cMinor), 3)
    }

    func testFifthAndOctaveWrap() {
        XCTAssertEqual(VoiceHarmony.interval(from: 60, degreesUp: 4, key: cMajor), 7)
        // B4 (71): a third above wraps the octave → D5 (74), +3.
        XCTAssertEqual(VoiceHarmony.interval(from: 71, degreesUp: 2, key: cMajor), 3)
        // A full scale walk up = one octave.
        XCTAssertEqual(VoiceHarmony.interval(from: 60, degreesUp: 7, key: cMajor), 12)
    }

    func testNegativeDegreesGoBelow() {
        // A third below C4 in C major is A3 (−3).
        XCTAssertEqual(VoiceHarmony.interval(from: 60, degreesUp: -2, key: cMajor), -3)
    }

    func testOutOfKeyInputIsQuantizedFirst() {
        // C#4 quantizes to C4 (tie → lower); the interval contract is measured
        // from the QUANTIZED note (the corrector snaps the voice first in the
        // VL3 chain), so the third above lands on E: C(60) + 4.
        let iv = VoiceHarmony.interval(from: 61, degreesUp: 2, key: cMajor)
        XCTAssertEqual(iv, 4)
        XCTAssertEqual(cMajor.quantize(61) + iv, 64, "harmony lands on E")
    }

    func testPentatonicScaleDegrees() {
        let cPentMinor = MusicalKey(root: 0, scale: .pentatonicMinor)
        // Degrees: C Eb F G Bb. Two degrees above C is F (+5).
        XCTAssertEqual(VoiceHarmony.interval(from: 60, degreesUp: 2, key: cPentMinor), 5)
    }
}
