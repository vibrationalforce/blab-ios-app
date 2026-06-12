// MusicalKeyTests.swift
// Echoel — the key/scale model behind "set your own key" + the bio composer.
// Hand-computed expectations for pitch classes, in-key snapping, and degrees.

import XCTest
@testable import Echoelmusic

final class MusicalKeyTests: XCTestCase {

    func testRootNormalizes() {
        XCTAssertEqual(MusicalKey(root: 12, scale: .major).root, 0)
        XCTAssertEqual(MusicalKey(root: -1, scale: .major).root, 11)
        XCTAssertEqual(MusicalKey(root: 14, scale: .major).root, 2)
    }

    func testPitchClassesCMinor() {
        // C natural minor: C D D# F G G# A#  → 0 2 3 5 7 8 10
        XCTAssertEqual(MusicalKey(root: 0, scale: .minor).pitchClasses, [0, 2, 3, 5, 7, 8, 10])
    }

    func testPitchClassesAMinorPentatonic() {
        // A minor pentatonic: A C D E G → 9 0 2 4 7
        XCTAssertEqual(MusicalKey(root: 9, scale: .pentatonicMinor).pitchClasses, [9, 0, 2, 4, 7])
    }

    func testContains() {
        let cMajor = MusicalKey(root: 0, scale: .major)
        XCTAssertTrue(cMajor.contains(64), "E4 is in C major")
        XCTAssertFalse(cMajor.contains(61), "C#4 is not in C major")
        XCTAssertTrue(cMajor.contains(72), "C5 is in C major (octave-agnostic)")
    }

    func testQuantizeSnapsToNearestLowerOnTie() {
        let cMajor = MusicalKey(root: 0, scale: .major)
        // C#4 (61): C(60) down1 vs D(62) up1 → tie → lower wins → 60
        XCTAssertEqual(cMajor.quantize(61), 60)
        // F#4 (66): F(65) down1 vs G(67) up1 → tie → 65
        XCTAssertEqual(cMajor.quantize(66), 65)
        // already in key → unchanged
        XCTAssertEqual(cMajor.quantize(67), 67)
    }

    func testQuantizeChromaticIsIdentity() {
        let chrom = MusicalKey(root: 3, scale: .chromatic)
        for n in 48...72 { XCTAssertEqual(chrom.quantize(n), n) }
    }

    func testDegreeMapsToMIDI() {
        let cMajor = MusicalKey(root: 0, scale: .major)
        XCTAssertEqual(cMajor.degree(0, octave: 4), 60, "C4")
        XCTAssertEqual(cMajor.degree(2, octave: 4), 64, "E4 (third degree)")
        XCTAssertEqual(cMajor.degree(7, octave: 4), 72, "wraps an octave → C5")
        XCTAssertEqual(cMajor.degree(-1, octave: 4), 59, "B3 below C4")
    }

    func testDegreePentatonicWrap() {
        // A minor pentatonic, octave 4: degrees A C D E G then A5
        let key = MusicalKey(root: 9, scale: .pentatonicMinor)
        let a4 = key.degree(0, octave: 4)          // (4+1)*12 + 9 = 69 (A4)
        XCTAssertEqual(a4, 69)
        XCTAssertEqual(key.degreesPerOctave, 5)
        XCTAssertEqual(key.degree(5, octave: 4), 69 + 12, "one octave up → A5")
    }

    func testNameAndCodableRoundTrip() throws {
        let key = MusicalKey(root: 7, scale: .dorian)
        XCTAssertEqual(key.name, "G Dorian")
        let data = try JSONEncoder().encode(key)
        XCTAssertEqual(try JSONDecoder().decode(MusicalKey.self, from: data), key)
    }

    func testAllScalesNonEmptyAndInRange() {
        for scale in Scale.allCases {
            XCTAssertFalse(scale.intervals.isEmpty)
            XCTAssertTrue(scale.intervals.allSatisfy { (0...11).contains($0) })
            XCTAssertEqual(scale.intervals, scale.intervals.sorted(), "ascending")
        }
    }
}
