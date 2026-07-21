// IntroAttenuationTests.swift
// Echoel — task #77 (founder ear-feedback 2026-07-21): bar-0 lead softening.

import XCTest
@testable import Echoelmusic

final class IntroAttenuationTests: XCTestCase {

    private func note(role: NoteRole, velocity: Float) -> Note {
        Note(pitch: 60, startStep: 0, lengthSteps: 1, velocity: velocity, role: role)
    }

    func testApply_notFirstBar_returnsNotesUnchanged() {
        let notes = [note(role: .lead, velocity: 0.9), note(role: .bass, velocity: 0.8)]
        let result = IntroAttenuation.apply(notes, isFirstBar: false)
        XCTAssertEqual(result, notes)
    }

    func testApply_firstBar_scalesOnlyLeadVelocity() {
        let lead = note(role: .lead, velocity: 0.9)
        let bass = note(role: .bass, velocity: 0.8)
        let harmony = note(role: .harmony, velocity: 0.7)
        let result = IntroAttenuation.apply([lead, bass, harmony], isFirstBar: true)

        XCTAssertEqual(result[0].velocity, 0.9 * IntroAttenuation.leadFactor, accuracy: 1e-6)
        XCTAssertEqual(result[1].velocity, 0.8, accuracy: 1e-6, "bass must stay untouched")
        XCTAssertEqual(result[2].velocity, 0.7, accuracy: 1e-6, "harmony must stay untouched")
    }

    func testApply_firstBar_leadQuieterThanNotFirstBar() {
        // The concrete regression this exists for: the SAME lead note must sound
        // softer in bar 0 than it would in any later loop bar.
        let lead = note(role: .lead, velocity: 0.85)
        let bar0 = IntroAttenuation.apply([lead], isFirstBar: true)
        let laterBar = IntroAttenuation.apply([lead], isFirstBar: false)
        XCTAssertLessThan(bar0[0].velocity, laterBar[0].velocity)
    }

    func testApply_clampsResultToUnitRange() {
        let loudLead = note(role: .lead, velocity: 1.0)
        let result = IntroAttenuation.apply([loudLead], isFirstBar: true)
        XCTAssertGreaterThanOrEqual(result[0].velocity, 0)
        XCTAssertLessThanOrEqual(result[0].velocity, 1)
    }

    func testApply_emptyNotes_isEmpty() {
        XCTAssertTrue(IntroAttenuation.apply([], isFirstBar: true).isEmpty)
    }

    func testLeadFactor_isBetweenZeroAndOneExclusive() {
        // A factor of 1 would be a no-op (missing the whole point); 0 would silence
        // the melody outright rather than soften it.
        XCTAssertGreaterThan(IntroAttenuation.leadFactor, 0)
        XCTAssertLessThan(IntroAttenuation.leadFactor, 1)
    }
}
