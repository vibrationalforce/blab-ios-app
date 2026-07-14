// MIDINoteRecorderTests.swift
// Pure tests for the per-track MIDI-record capture core (B20) — open/close,
// re-trigger, velocity-0-as-off, anchor gating, flush, min length. No CoreMIDI →
// runs on every platform.

import XCTest
@testable import Echoelmusic

final class MIDINoteRecorderTests: XCTestCase {

    func testNoteOnBeforeAnchor_isIgnored() {
        var r = MIDINoteRecorder(anchorTick: 2000)
        r.noteOn(pitch: 60, velocity: 0.8, atTick: 1000)   // before anchor
        r.noteOff(pitch: 60, atTick: 1500)
        XCTAssertEqual(r.noteCount, 0)
        XCTAssertTrue(r.notes().isEmpty)
    }

    func testSingleNote_relativeStartLengthVelocityPitch() {
        var r = MIDINoteRecorder(anchorTick: 480)
        r.noteOn(pitch: 60, velocity: 0.7, atTick: 600)    // rel start = 120
        r.noteOff(pitch: 60, atTick: 1080)                 // length = 480
        let notes = r.notes()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].pitch, 60)
        XCTAssertEqual(notes[0].startTick, 120)
        XCTAssertEqual(notes[0].lengthTicks, 480)
        XCTAssertEqual(notes[0].velocity, 0.7, accuracy: 1e-6)
    }

    func testOverlappingPitches_bothCaptured_sorted() {
        var r = MIDINoteRecorder(anchorTick: 0)
        r.noteOn(pitch: 60, velocity: 0.8, atTick: 0)
        r.noteOn(pitch: 64, velocity: 0.8, atTick: 120)
        r.noteOff(pitch: 60, atTick: 480)
        r.noteOff(pitch: 64, atTick: 600)
        let notes = r.notes()
        XCTAssertEqual(notes.map(\.pitch), [60, 64])       // sorted by start (0, 120)
        XCTAssertEqual(notes.map(\.startTick), [0, 120])
        XCTAssertEqual(notes.map(\.lengthTicks), [480, 480])
    }

    func testReTriggerSamePitch_closesPreviousThenOpensNew() {
        var r = MIDINoteRecorder(anchorTick: 0)
        r.noteOn(pitch: 60, velocity: 0.5, atTick: 0)
        r.noteOn(pitch: 60, velocity: 0.9, atTick: 240)    // re-trigger → closes first at 240
        r.noteOff(pitch: 60, atTick: 480)
        let notes = r.notes()
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].startTick, 0)
        XCTAssertEqual(notes[0].lengthTicks, 240)
        XCTAssertEqual(notes[0].velocity, 0.5, accuracy: 1e-6)
        XCTAssertEqual(notes[1].startTick, 240)
        XCTAssertEqual(notes[1].lengthTicks, 240)
        XCTAssertEqual(notes[1].velocity, 0.9, accuracy: 1e-6)
    }

    func testNoteOnZeroVelocity_isTreatedAsNoteOff() {
        var r = MIDINoteRecorder(anchorTick: 0)
        r.noteOn(pitch: 60, velocity: 0.8, atTick: 0)
        r.noteOn(pitch: 60, velocity: 0, atTick: 240)      // running-status note-off
        XCTAssertEqual(r.openCount, 0)
        XCTAssertEqual(r.notes().map(\.lengthTicks), [240])
    }

    func testFlushOpen_closesRemaining() {
        var r = MIDINoteRecorder(anchorTick: 0)
        r.noteOn(pitch: 62, velocity: 0.8, atTick: 0)
        r.noteOn(pitch: 65, velocity: 0.8, atTick: 60)
        XCTAssertEqual(r.openCount, 2)
        r.flushOpen(atTick: 480)
        XCTAssertEqual(r.openCount, 0)
        let notes = r.notes()
        XCTAssertEqual(notes.map(\.pitch), [62, 65])       // start 0 then 60
        XCTAssertEqual(notes.map(\.lengthTicks), [480, 420])
    }

    func testNoteOffWithoutNoteOn_isIgnored() {
        var r = MIDINoteRecorder(anchorTick: 0)
        r.noteOff(pitch: 60, atTick: 200)
        XCTAssertEqual(r.noteCount, 0)
    }

    func testNoteOffAtOnset_clampsToMinLength() {
        var r = MIDINoteRecorder(anchorTick: 0, minLengthTicks: 1)
        r.noteOn(pitch: 60, velocity: 0.8, atTick: 100)
        r.noteOff(pitch: 60, atTick: 100)                  // zero span → clamp to 1
        XCTAssertEqual(r.notes()[0].lengthTicks, 1)
    }

    func testMelody_wrapsCompletedNotes() {
        var r = MIDINoteRecorder(anchorTick: 0)
        r.noteOn(pitch: 60, velocity: 0.8, atTick: 0)
        r.noteOff(pitch: 60, atTick: 240)
        XCTAssertEqual(r.melody().notes.count, 1)
    }
}
