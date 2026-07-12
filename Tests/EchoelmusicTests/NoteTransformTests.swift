// NoteTransformTests.swift
// Echoel — Strum + Humanize as pure, deterministic selection transforms (A2).

import XCTest
import Foundation
@testable import Echoelmusic

final class NoteTransformTests: XCTestCase {

    private func chord(_ pitches: [Int], start: Int = 0, length: Int = 480,
                       velocity: Float = 0.8) -> [Note] {
        pitches.map { Note(pitch: $0, startTick: start, lengthTicks: length, velocity: velocity) }
    }

    // MARK: Strum

    func testStrum_fansChordAcrossSpread_keepsReleasePoint() {
        let out = NoteTransform.strum(chord([60, 64, 67]), spreadTicks: 60)
        let byPitch = { (p: Int) in out.first { $0.pitch == p }! }
        XCTAssertEqual(byPitch(60).startTick, 0, "lowest note anchors the strum (upward)")
        XCTAssertEqual(byPitch(64).startTick, 30)
        XCTAssertEqual(byPitch(67).startTick, 60)
        for n in out {
            XCTAssertEqual(n.endTick, 480, "every strummed note keeps the chord's release point")
        }
    }

    func testStrum_downward_reversesOrder() {
        let out = NoteTransform.strum(chord([60, 64, 67]), spreadTicks: 60, upward: false)
        XCTAssertEqual(out.first { $0.pitch == 67 }!.startTick, 0)
        XCTAssertEqual(out.first { $0.pitch == 60 }!.startTick, 60)
    }

    func testStrum_velocitySlope_rampsAcrossStrum() {
        let out = NoteTransform.strum(chord([60, 64, 67]), spreadTicks: 60, velocitySlope: -0.5)
        XCTAssertEqual(out.first { $0.pitch == 60 }!.velocity, 0.8, accuracy: 1e-6)
        XCTAssertEqual(out.first { $0.pitch == 64 }!.velocity, 0.6, accuracy: 1e-6)
        XCTAssertEqual(out.first { $0.pitch == 67 }!.velocity, 0.4, accuracy: 1e-6)
    }

    func testStrum_singleNotesAndSeparateStarts_passThrough() {
        let notes = [Note(pitch: 60, startTick: 0, lengthTicks: 240),
                     Note(pitch: 64, startTick: 240, lengthTicks: 240)]
        XCTAssertEqual(NoteTransform.strum(notes, spreadTicks: 60), notes,
                       "no chord (distinct starts) → untouched")
    }

    func testStrum_twoChordsTransformIndependently() {
        let bar = chord([60, 64], start: 0) + chord([62, 65], start: 960)
        let out = NoteTransform.strum(bar, spreadTicks: 40)
        XCTAssertEqual(out.first { $0.pitch == 64 }!.startTick, 40)
        XCTAssertEqual(out.first { $0.pitch == 62 }!.startTick, 960)
        XCTAssertEqual(out.first { $0.pitch == 65 }!.startTick, 1000)
    }

    func testStrum_preservesInputOrderAndIDs() {
        let input = chord([67, 60, 64])
        let out = NoteTransform.strum(input, spreadTicks: 60)
        XCTAssertEqual(out.map(\.id), input.map(\.id), "stable order for the UI")
    }

    func testStrum_lengthNeverBelowOneTick() {
        // A strum wider than the chord's length must not produce zero/negative lengths.
        let out = NoteTransform.strum(chord([60, 64, 67], length: 30), spreadTicks: 120)
        XCTAssertTrue(out.allSatisfy { $0.lengthTicks >= 1 })
    }

    func testStrum_zeroSpreadZeroSlope_isIdentity() {
        let input = chord([60, 64, 67])
        XCTAssertEqual(NoteTransform.strum(input, spreadTicks: 0), input)
    }

    // MARK: Humanize

    func testHumanize_isDeterministicAndOrderIndependent() {
        let input = chord([60, 64, 67])
        let a = NoteTransform.humanize(input, timingTicks: 8, velocityJitter: 0.2, seed: 5)
        let b = NoteTransform.humanize(Array(input.reversed()), timingTicks: 8, velocityJitter: 0.2, seed: 5)
        for n in a {
            let m = b.first { $0.id == n.id }!
            XCTAssertEqual(n.startTick, m.startTick, "per-ID seeding → order must not matter")
            XCTAssertEqual(n.velocity, m.velocity)
        }
    }

    func testHumanize_staysWithinBounds() {
        let input = chord([60, 64, 67], start: 100, velocity: 0.5)
        let out = NoteTransform.humanize(input, timingTicks: 6, velocityJitter: 0.3, seed: 11)
        for (i, n) in out.enumerated() {
            XCTAssertLessThanOrEqual(abs(n.startTick - input[i].startTick), 6)
            XCTAssertGreaterThanOrEqual(n.velocity, 0); XCTAssertLessThanOrEqual(n.velocity, 1)
            XCTAssertEqual(n.lengthTicks, input[i].lengthTicks, "length untouched")
        }
    }

    func testHumanize_actuallyVariesAcrossNotes() {
        let input = chord([60, 62, 64, 65, 67, 69, 71, 72])
        let out = NoteTransform.humanize(input, timingTicks: 8, velocityJitter: 0.2, seed: 3)
        XCTAssertTrue(Set(out.map { $0.startTick - 0 }).count > 1
                        || Set(out.map(\.velocity)).count > 1,
                      "distinct note IDs must get distinct jitter")
    }

    func testHumanize_zeroSettings_isIdentity() {
        let input = chord([60, 64])
        XCTAssertEqual(NoteTransform.humanize(input, timingTicks: 0, velocityJitter: 0, seed: 1), input)
    }

    func testHumanize_neverPushesStartBelowZero() {
        let input = [Note(pitch: 60, startTick: 1, lengthTicks: 100)]
        for seed in UInt64(0)..<UInt64(20) {
            let out = NoteTransform.humanize(input, timingTicks: 10, velocityJitter: 0, seed: seed)
            XCTAssertGreaterThanOrEqual(out[0].startTick, 0)
        }
    }
}
