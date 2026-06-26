// MicrotonalTuningTests.swift
// Echoel — the tone-system substrate the vocal autotune snaps to. 12-TET must
// match standard MIDI frequencies; quarter tones must be 50 cents; snap must
// find the nearest in-scale pitch + signed cent error; non-octave systems must
// repeat at their own period; everything stays anchored to the Kammerton.

import XCTest
@testable import Echoelmusic

final class MicrotonalTuningTests: XCTestCase {

    private let acc = 0.01   // cents / Hz tolerance

    // MARK: 12-TET sanity vs. concert pitch

    func test12TET_degreesMatchSemitones() {
        let edo12 = TuningSystem.named("edo12")
        XCTAssertEqual(edo12.degreeCount, 12)
        for (i, c) in edo12.degreesCents.enumerated() {
            XCTAssertEqual(c, Double(i) * 100, accuracy: acc)
        }
    }

    func test12TET_referenceAtA_givesConcertPitch() {
        // Root = A (MIDI 69); 1/1 reference at A4 = 440 Hz; degree 12 = A5 = 880.
        let edo12 = TuningSystem.named("edo12")
        let ref = TuningSystem.reference(rootMidi: 69, tuning: TuningReference(a4Hz: 440))
        XCTAssertEqual(ref, 440, accuracy: acc)
        XCTAssertEqual(edo12.frequency(degree: 0, reference: ref), 440, accuracy: acc)
        XCTAssertEqual(edo12.frequency(degree: 12, reference: ref), 880, accuracy: acc)
        XCTAssertEqual(edo12.frequency(degree: 7, reference: ref), 440 * pow(2, 7.0/12), accuracy: acc)
    }

    func test12TET_followsKammerton() {
        // The whole system shifts with the concert-pitch reference (432 vs 440).
        let edo12 = TuningSystem.named("edo12")
        let ref432 = TuningSystem.reference(rootMidi: 69, tuning: TuningReference(a4Hz: 432))
        XCTAssertEqual(edo12.frequency(degree: 0, reference: ref432), 432, accuracy: acc)
    }

    // MARK: quarter tones

    func testQuarterTones_are50Cents() {
        let edo24 = TuningSystem.named("edo24")
        XCTAssertEqual(edo24.degreeCount, 24)
        XCTAssertEqual(edo24.degreesCents[1], 50, accuracy: acc)
        XCTAssertEqual(edo24.degreesCents[3], 150, accuracy: acc)
    }

    // MARK: snap — the autotune target

    func testSnap_exactDegree_zeroError() {
        let edo12 = TuningSystem.named("edo12")
        let ref = 440.0
        let r = edo12.snap(frequencyHz: 440, reference: ref)
        XCTAssertEqual(r.cents, 0, accuracy: acc)
        XCTAssertEqual(r.frequencyHz, 440, accuracy: acc)
        XCTAssertEqual(r.degree, 0)
    }

    func testSnap_sharpInput_pullsDown() {
        // +30 cents above A4 should snap back to A4 with +30 error (input sharp).
        let edo12 = TuningSystem.named("edo12")
        let sharp = 440.0 * pow(2, 30.0 / 1200)
        let r = edo12.snap(frequencyHz: sharp, reference: 440)
        XCTAssertEqual(r.frequencyHz, 440, accuracy: 0.1)
        XCTAssertEqual(r.cents, 30, accuracy: 0.1)   // + = sharp → corrector pulls down
    }

    func testSnap_flatInput_pushesUp() {
        let edo12 = TuningSystem.named("edo12")
        let flat = 440.0 * pow(2, -40.0 / 1200)
        let r = edo12.snap(frequencyHz: flat, reference: 440)
        XCTAssertEqual(r.frequencyHz, 440, accuracy: 0.1)
        XCTAssertEqual(r.cents, -40, accuracy: 0.1)
    }

    func testSnap_quarterTone_reachableOnlyIn24TET() {
        // A pitch ~50 cents sharp of A snaps to A in 12-TET but is in-scale in 24-TET.
        let ref = 440.0
        let neutral = 440.0 * pow(2, 50.0 / 1200)
        let in12 = TuningSystem.named("edo12").snap(frequencyHz: neutral, reference: ref)
        XCTAssertEqual(abs(in12.cents), 50, accuracy: 0.5)        // 12-TET can't reach it
        let in24 = TuningSystem.named("edo24").snap(frequencyHz: neutral, reference: ref)
        XCTAssertEqual(in24.cents, 0, accuracy: 0.5)              // 24-TET lands on it
    }

    func testSnap_nearPeriodBoundary_findsNearest() {
        // 20 cents below the octave should snap UP to the octave (next period),
        // not down to the major seventh.
        let edo12 = TuningSystem.named("edo12")
        let nearOctave = 440.0 * pow(2, (1200.0 - 20) / 1200.0)
        let r = edo12.snap(frequencyHz: nearOctave, reference: 440)
        XCTAssertEqual(r.frequencyHz, 880, accuracy: 0.5)
        XCTAssertEqual(r.degree, 12)
    }

    // MARK: negative / wrapping degrees

    func testFrequency_negativeDegreeWrapsDown() {
        let edo12 = TuningSystem.named("edo12")
        XCTAssertEqual(edo12.frequency(degree: -12, reference: 440), 220, accuracy: acc)
        XCTAssertEqual(edo12.frequency(degree: -1, reference: 440),
                       440 * pow(2, -1.0/12), accuracy: acc)
    }

    // MARK: non-octave system

    func testBohlenPierce_repeatsAtTritave() {
        let bp = TuningSystem.named("bohlen-pierce")
        XCTAssertEqual(bp.degreeCount, 13)
        XCTAssertEqual(bp.periodCents, 1901.955, accuracy: 0.01)
        // One full period above the tonic = a perfect twelfth (3:1), not 2:1.
        let oneTritave = bp.frequency(degree: 13, reference: 440)
        XCTAssertEqual(oneTritave, 440 * 3, accuracy: 0.5)
    }

    // MARK: library integrity

    func testLibrary_defaultsAreSane() {
        XCTAssertEqual(TuningSystem.library.first?.id, "edo12", "12-TET is the safe default")
        for t in TuningSystem.library {
            XCTAssertFalse(t.degreesCents.isEmpty, "\(t.id) has degrees")
            XCTAssertEqual(t.degreesCents.first, 0, accuracy: acc, "\(t.id) starts at the tonic")
            XCTAssertGreaterThan(t.periodCents, 0, "\(t.id) has a positive period")
            // strictly ascending within the period
            XCTAssertEqual(t.degreesCents, t.degreesCents.sorted(), "\(t.id) is ascending")
        }
    }

    func testNamed_unknownFallsBackTo12TET() {
        XCTAssertEqual(TuningSystem.named("does-not-exist").id, "edo12")
    }

    // MARK: pitch-class retune table (the synth wiring) — 12-TET must be a no-op

    func test12TET_pitchClassCents_allZero() {
        let table = TuningSystem.named("edo12").pitchClassCents(root: 0)
        XCTAssertEqual(table.count, 12)
        for c in table { XCTAssertEqual(c, 0, accuracy: acc) }
    }

    func test24TET_pitchClassCents_allZero_supersetOf12() {
        // 24-TET contains every 12-TET position exactly → the 12 notes don't move.
        for c in TuningSystem.named("edo24").pitchClassCents(root: 0) {
            XCTAssertEqual(c, 0, accuracy: acc)
        }
    }

    func testJustMajor_retunesDiatonicTones() {
        let t = TuningSystem.named("just-major").pitchClassCents(root: 0)
        XCTAssertEqual(t[0], 0, accuracy: 0.1)        // tonic
        XCTAssertEqual(t[2], 3.91, accuracy: 0.2)     // just major 2nd (9/8)
        XCTAssertEqual(t[4], -13.69, accuracy: 0.2)   // just major 3rd (5/4) is flat
        XCTAssertEqual(t[7], 1.96, accuracy: 0.2)     // just 5th (3/2)
    }

    func testPitchClassCents_followsRoot() {
        // The just major-3rd deviation should sit on E (pc 4) for C, on G (pc 7) for E.
        let cMajor = TuningSystem.named("just-major").pitchClassCents(root: 0)
        let eMajor = TuningSystem.named("just-major").pitchClassCents(root: 4)
        XCTAssertEqual(cMajor[4], -13.69, accuracy: 0.2)
        XCTAssertEqual(eMajor[(4 + 4) % 12], -13.69, accuracy: 0.2)
    }

    func testNonOctaveSystem_noChromaticRetune() {
        for c in TuningSystem.named("bohlen-pierce").pitchClassCents(root: 0) {
            XCTAssertEqual(c, 0, accuracy: acc)
        }
    }

    func testMeantone_presentWithPureMajorThird() {
        // 1/4-comma meantone is in the library and gives a ~386¢ (pure 5:4) major third.
        let m = TuningSystem.named("meantone-quarter")
        XCTAssertEqual(m.id, "meantone-quarter", "meantone is registered (named() fell back?)")
        XCTAssertEqual(m.degreeCount, 12)
        XCTAssertEqual(m.degreesCents[4], 386.3, accuracy: 0.3)   // pure major third
        XCTAssertEqual(m.degreesCents[7], 696.6, accuracy: 0.3)   // narrow meantone fifth
    }
}
