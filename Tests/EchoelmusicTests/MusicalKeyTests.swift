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
        // Tonarten expansion 2026-07-09 (standard catalog definitions only —
        // Ableton-proprietary "Bulgarian"/"Polymode" deliberately NOT shipped).
        XCTAssertEqual(Scale.neapolitanMinor.intervals, [0, 1, 3, 5, 7, 8, 11])
        XCTAssertEqual(Scale.neapolitanMajor.intervals, [0, 1, 3, 5, 7, 9, 11])
        XCTAssertEqual(Scale.romanianMinor.intervals,   [0, 2, 3, 6, 7, 9, 10])
        XCTAssertEqual(Scale.persian.intervals,         [0, 1, 4, 5, 6, 8, 11])
        XCTAssertEqual(Scale.hirajoshi.intervals,       [0, 2, 3, 7, 8])
        XCTAssertEqual(Scale.iwato.intervals,           [0, 1, 5, 6, 10])
        XCTAssertEqual(Scale.insen.intervals,           [0, 1, 5, 7, 10])
        XCTAssertEqual(Scale.yo.intervals,              [0, 2, 5, 7, 9])
        XCTAssertEqual(Scale.inSakura.intervals,        [0, 1, 5, 7, 8])
        XCTAssertEqual(Scale.egyptian.intervals,        [0, 2, 5, 7, 10])
        XCTAssertEqual(Scale.pelog.intervals,           [0, 1, 3, 7, 8])
        XCTAssertEqual(Scale.enigmatic.intervals,       [0, 1, 4, 6, 8, 10, 11])
        XCTAssertEqual(Scale.prometheus.intervals,      [0, 2, 4, 6, 9, 10])
        XCTAssertEqual(Scale.augmented.intervals,       [0, 3, 4, 7, 8, 11])
        XCTAssertEqual(Scale.tritone.intervals,         [0, 1, 4, 6, 7, 10])
        XCTAssertEqual(Scale.hungarianMajor.intervals,  [0, 3, 4, 6, 7, 9, 10])
        XCTAssertEqual(Scale.bebopMajor.intervals,      [0, 2, 4, 5, 7, 8, 9, 11])
        XCTAssertEqual(Scale.majorLocrian.intervals,    [0, 2, 4, 5, 6, 8, 10])
        // Ableton-Live-12-list gap-close 2026-07-12 (founder screenshots) —
        // again standard catalog definitions only ("Pelog Tembung" stays out).
        XCTAssertEqual(Scale.lydianAugmented.intervals,  [0, 2, 4, 6, 8, 9, 11])
        XCTAssertEqual(Scale.spanishEightTone.intervals, [0, 1, 3, 4, 5, 6, 8, 10])
        XCTAssertEqual(Scale.kumoi.intervals,            [0, 2, 3, 7, 9])
        // Messiaen modes = their repeating step pattern tiled over the octave
        // (3: 2-1-1 ×3 · 4: 1-1-3-1 ×2 · 5: 1-4-1 ×2 · 6: 2-2-1-1 ×2 ·
        // 7: 1-1-1-2-1 ×2; modes 1/2 are wholeTone/diminishedHalfWhole above).
        XCTAssertEqual(Scale.messiaen3.intervals, [0, 2, 3, 4, 6, 7, 8, 10, 11])
        XCTAssertEqual(Scale.messiaen4.intervals, [0, 1, 2, 5, 6, 7, 8, 11])
        XCTAssertEqual(Scale.messiaen5.intervals, [0, 1, 5, 6, 7, 11])
        XCTAssertEqual(Scale.messiaen6.intervals, [0, 2, 4, 5, 6, 8, 10, 11])
        XCTAssertEqual(Scale.messiaen7.intervals, [0, 1, 2, 3, 5, 6, 7, 8, 9, 11])
    }

    func testMessiaenModes_areModesOfLimitedTransposition() {
        // The defining property: each mode maps onto itself under transposition
        // by its period (mode 3: 4 semitones; modes 4/5/6/7: 6 semitones).
        // This locks the interval tables to the mathematics, not to a source.
        let periods: [(Scale, Int)] = [(.messiaen3, 4), (.messiaen4, 6),
                                       (.messiaen5, 6), (.messiaen6, 6), (.messiaen7, 6)]
        for (scale, period) in periods {
            let set = Set(scale.intervals)
            let transposed = Set(scale.intervals.map { ($0 + period) % 12 })
            XCTAssertEqual(set, transposed, "\(scale) must be invariant under +\(period) semitones")
        }
    }

    func testEveryScale_quantizeAlwaysLandsInScale() {
        // The touch surface + composer rely on quantize() reaching an in-scale
        // note within its ±6 semitone search — must hold for every roster scale,
        // including the sparse pentatonics (largest gap ≤ 5 semitones).
        for scale in Scale.allCases {
            let key = MusicalKey(root: 4, scale: scale)
            for n in 48...84 {
                XCTAssertTrue(key.contains(key.quantize(n)),
                              "\(scale): quantize(\(n)) must land in scale")
            }
        }
    }

    func testEveryScale_intervalsStrictlyAscendingFromZero() {
        for scale in Scale.allCases {
            let iv = scale.intervals
            XCTAssertEqual(iv.first, 0, "\(scale): root must be degree 0")
            XCTAssertEqual(iv, iv.sorted(), "\(scale): ascending")
            XCTAssertEqual(Set(iv).count, iv.count, "\(scale): no duplicate degrees")
            XCTAssertTrue(iv.allSatisfy { (0..<12).contains($0) }, "\(scale): one octave")
        }
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
