// TuningDetectorTests.swift
// Echoel — the "hear the tuning" brain. Pure math → runs on Linux ci.yml.

import XCTest
@testable import Echoelmusic

final class TuningDetectorTests: XCTestCase {

    private let det = TuningDetector()

    /// Frequencies for a list of MIDI notes at a given concert pitch.
    private func freqs(_ midi: [Int], a4: Double) -> [Double] {
        midi.map { a4 * pow(2.0, Double($0 - 69) / 12.0) }
    }

    // C major scale (C D E F G A B), a couple of octaves, repeated for weight.
    private let cMajorMIDI = [60, 62, 64, 65, 67, 69, 71, 72, 64, 67, 60, 65, 69, 67, 64, 60]
    // A natural-minor scale (A B C D E F G).
    private let aMinorMIDI = [69, 71, 72, 74, 76, 77, 79, 81, 72, 76, 69, 74, 77, 76, 72, 69]

    func testDetectsCMajorAt440() throws {
        let r = try XCTUnwrap(det.analyze(frequencies: freqs(cMajorMIDI, a4: 440)))
        XCTAssertEqual(r.keyRoot, 0)          // C
        XCTAssertFalse(r.isMinor)
        XCTAssertEqual(r.a4Hz, 440, accuracy: 0.5)
        XCTAssertGreaterThan(r.confidence, 0.6)
    }

    func testDetectsAMinorAt440() throws {
        let r = try XCTUnwrap(det.analyze(frequencies: freqs(aMinorMIDI, a4: 440)))
        XCTAssertEqual(r.keyRoot, 9)          // A
        XCTAssertTrue(r.isMinor)
        XCTAssertGreaterThan(r.confidence, 0.5)
    }

    func testDetectsKammerton432() throws {
        let r = try XCTUnwrap(det.analyze(frequencies: freqs(cMajorMIDI, a4: 432)))
        XCTAssertEqual(r.a4Hz, 432, accuracy: 0.7)
        XCTAssertLessThan(r.centsOffset, -25)   // ≈ −31.8 cents flat of 440
        XCTAssertEqual(r.keyRoot, 0)            // key still recovered at the detected tuning
    }

    func testDetectsKammerton444() throws {
        let r = try XCTUnwrap(det.analyze(frequencies: freqs(cMajorMIDI, a4: 444)))
        XCTAssertEqual(r.a4Hz, 444, accuracy: 0.7)
        XCTAssertGreaterThan(r.centsOffset, 10)
    }

    func testSnapsToNearestPreset() throws {
        let r = try XCTUnwrap(det.analyze(frequencies: freqs(cMajorMIDI, a4: 432)))
        XCTAssertEqual(r.snappedA4(), 432, accuracy: 0.01)   // 432 is a preset
    }

    func testTooFewSamplesReturnsNil() {
        XCTAssertNil(det.analyze(frequencies: [440, 440, 440]))
    }

    func testRejectsOutOfRangeAndKeepsValid() {
        // Garbage (0, NaN, 50000) dropped; the C-major content still classifies.
        var input = freqs(cMajorMIDI, a4: 440)
        input += [0, .nan, 50_000, -10]
        let r = det.analyze(frequencies: input)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.keyRoot, 0)
    }

    func testKeyNameFormatting() {
        let t = DetectedTuning(a4Hz: 440, keyRoot: 9, isMinor: true,
                               confidence: 0.8, centsOffset: 0, sampleCount: 20)
        XCTAssertEqual(t.keyName, "A minor")
    }

    func testCorrelationIdentityIsOne() {
        let v = TuningDetector.majorProfile
        XCTAssertEqual(TuningDetector.correlation(v, v), 1.0, accuracy: 1e-9)
    }
}
