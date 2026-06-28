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
            XCTAssertEqual(scale.intervals.first, 0, "starts on the root")
            XCTAssertEqual(Set(scale.intervals).count, scale.intervals.count, "no duplicate degrees in \(scale)")
            XCTAssertFalse(scale.displayName.isEmpty)
            XCTAssertFalse(scale.shortTag.isEmpty)
        }
    }

    func testScaleDisplayNamesAndTagsAreUnique() {
        XCTAssertEqual(Set(Scale.allCases.map(\.displayName)).count, Scale.allCases.count)
        XCTAssertEqual(Set(Scale.allCases.map(\.shortTag)).count, Scale.allCases.count)
    }

    func testNewScales_haveExpectedIntervals() {
        XCTAssertEqual(Scale.locrian.intervals,        [0, 1, 3, 5, 6, 8, 10])
        XCTAssertEqual(Scale.melodicMinor.intervals,   [0, 2, 3, 5, 7, 9, 11])
        XCTAssertEqual(Scale.lydianDominant.intervals, [0, 2, 4, 6, 7, 9, 10])
        XCTAssertEqual(Scale.altered.intervals,        [0, 1, 3, 4, 6, 8, 10])
        XCTAssertEqual(Scale.bebopDominant.intervals,  [0, 2, 4, 5, 7, 9, 10, 11])
        XCTAssertEqual(Scale.bluesMinor.intervals,     [0, 3, 5, 6, 7, 10])
        XCTAssertEqual(Scale.bluesMajor.intervals,     [0, 2, 3, 4, 7, 9])
        XCTAssertEqual(Scale.wholeTone.intervals,      [0, 2, 4, 6, 8, 10])
        XCTAssertEqual(Scale.diminishedWholeHalf.intervals, [0, 2, 3, 5, 6, 8, 9, 11])
        XCTAssertEqual(Scale.diminishedHalfWhole.intervals, [0, 1, 3, 4, 6, 7, 9, 10])
        // World / exotic additions.
        XCTAssertEqual(Scale.phrygianDominant.intervals, [0, 1, 4, 5, 7, 8, 10])
        XCTAssertEqual(Scale.harmonicMajor.intervals,    [0, 2, 4, 5, 7, 8, 11])
        XCTAssertEqual(Scale.hungarianMinor.intervals,   [0, 2, 3, 6, 7, 8, 11])
        XCTAssertEqual(Scale.doubleHarmonic.intervals,   [0, 1, 4, 5, 7, 8, 11])
    }

    func testNewScale_codableRoundTrip() throws {
        // raw values are the case names; new cases must round-trip for persisted keys.
        for scale in [Scale.locrian, .lydianDominant, .bluesMinor, .wholeTone] {
            let key = MusicalKey(root: 2, scale: scale)
            let data = try JSONEncoder().encode(key)
            XCTAssertEqual(try JSONDecoder().decode(MusicalKey.self, from: data), key)
        }
    }

    func testWholeTone_quantizeStaysInScale() {
        let wt = MusicalKey(root: 0, scale: .wholeTone)   // C D E F# G# A#
        for n in 60...72 { XCTAssertTrue(wt.contains(wt.quantize(n)), "quantized \(n) in scale") }
    }
}
