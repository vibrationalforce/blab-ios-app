// TuningReferenceTests.swift
// Echoel — concert-pitch (Kammerton) and note-frequency math, two-decimal.

import XCTest
@testable import Echoelmusic

final class TuningReferenceTests: XCTestCase {

    func testStandardA4() {
        let t = TuningReference(a4Hz: 440.00)
        XCTAssertEqual(t.frequency(forMIDINote: 69), 440.00, accuracy: 1e-9, "A4 = 440 Hz")
        XCTAssertEqual(t.frequency(forMIDINote: 60), 261.6256, accuracy: 0.001, "Middle C")
        XCTAssertEqual(t.frequency(forMIDINote: 81), 880.00, accuracy: 1e-6, "A5 = 880 Hz (octave up)")
        XCTAssertEqual(t.frequency(forMIDINote: 57), 220.00, accuracy: 1e-6, "A3 = 220 Hz (octave down)")
    }

    func testAlternateConcertPitch() {
        let t = TuningReference(a4Hz: 432.00)
        XCTAssertEqual(t.frequency(forMIDINote: 69), 432.00, accuracy: 1e-9)
        XCTAssertEqual(t.frequencyRounded(forMIDINote: 60), 256.87, accuracy: 0.001,
                       "Middle C at A=432 ≈ 256.87 Hz, two decimals")
    }

    func testNoteNames() {
        XCTAssertEqual(TuningReference.noteName(forMIDINote: 60), "C4")
        XCTAssertEqual(TuningReference.noteName(forMIDINote: 69), "A4")
        XCTAssertEqual(TuningReference.noteName(forMIDINote: 61), "C#4")
    }

    func testPrecisionTwoDecimals() {
        XCTAssertEqual(Precision.two(120), "120.00")
        XCTAssertEqual(Precision.two(75.5), "75.50")
        XCTAssertEqual(Precision.two(440), "440.00")
        XCTAssertEqual(Precision.round2(128.3749), 128.37)
    }

    func testCodableRoundTrip() throws {
        let t = TuningReference(a4Hz: 442.00)
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(TuningReference.self, from: data)
        XCTAssertEqual(back, t)
    }
}
