// NoteTests.swift
// Echoelmusic — the shared Note model + piano-roll editing API.

import XCTest
@testable import Echoelmusic

final class NoteTests: XCTestCase {

    func testInit_clampsLengthAndVelocity() {
        let a = Note(pitch: 60, startStep: 0, lengthSteps: 0, velocity: 2)
        XCTAssertEqual(a.lengthSteps, 1, "length clamps to >= 1")
        XCTAssertEqual(a.velocity, 1, "velocity clamps to <= 1")

        let b = Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: -1)
        XCTAssertEqual(b.lengthSteps, 4)
        XCTAssertEqual(b.velocity, 0, "velocity clamps to >= 0")
    }

    func testEndStepAndCovers() {
        let note = Note(pitch: 60, startStep: 4, lengthSteps: 3)
        XCTAssertEqual(note.endStep, 7, "endStep is start + length (exclusive)")
        XCTAssertFalse(note.covers(step: 3))
        XCTAssertTrue(note.covers(step: 4), "start is inclusive")
        XCTAssertTrue(note.covers(step: 6))
        XCTAssertFalse(note.covers(step: 7), "end is exclusive")
    }

    func testCodableRoundTrip() throws {
        let note = Note(pitch: 67, startStep: 2, lengthSteps: 5, velocity: 0.7)
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(Note.self, from: data)
        XCTAssertEqual(decoded, note)
    }
}

#if canImport(SwiftUI)
@MainActor
final class PianoRollModelTests: XCTestCase {

    func testAdd_clampsLengthToBarBoundary() {
        let model = PianoRollModel()
        let note = model.add(pitch: 60, startStep: 14, lengthSteps: 8)
        XCTAssertEqual(note.lengthSteps, PianoRollModel.stepCount - 14,
                       "length is clamped so the note never crosses the loop boundary")
    }

    func testNoteAtPitchStep_findsCoveringNote() {
        let model = PianoRollModel()
        model.add(pitch: 60, startStep: 4, lengthSteps: 4) // covers 4..7
        XCTAssertNotNil(model.note(atPitch: 60, step: 6))
        XCTAssertNil(model.note(atPitch: 60, step: 8))
        XCTAssertNil(model.note(atPitch: 61, step: 6), "different pitch")
    }

    func testRemoveAndEdit() {
        let model = PianoRollModel()
        let note = model.add(pitch: 62, startStep: 0, lengthSteps: 2, velocity: 0.5)
        model.setVelocity(id: note.id, 0.9)
        model.setLength(id: note.id, lengthSteps: 6)
        let edited = model.notes.first { $0.id == note.id }
        XCTAssertEqual(edited?.velocity, 0.9)
        XCTAssertEqual(edited?.lengthSteps, 6)

        model.remove(id: note.id)
        XCTAssertTrue(model.notes.isEmpty)
    }

    func testLoadReplacesNotes() {
        let model = PianoRollModel()
        model.add(pitch: 60, startStep: 0)
        model.load([Note(pitch: 72, startStep: 8, lengthSteps: 2)])
        XCTAssertEqual(model.notes.count, 1)
        XCTAssertEqual(model.notes.first?.pitch, 72)
    }
}
#endif
