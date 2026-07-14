// TakeRecorderTests.swift
// Pure tests for the per-lane capture coordinator. No engine → every platform.

import XCTest
@testable import Echoelmusic

final class TakeRecorderTests: XCTestCase {

    private let midiLane = UUID()
    private let bioLane = UUID()

    func testIdleUntilStarted() {
        var rec = TakeRecorder()
        XCTAssertFalse(rec.isRecording)
        rec.noteOn(pitch: 60, velocity: 0.8, atTick: 0)   // ignored while idle
        XCTAssertEqual(rec.finish(atTick: 480), [])
    }

    func testMIDITakeProducesAClipOnTheLane() {
        var rec = TakeRecorder()
        rec.start(targets: [(midiLane, .midiInput)], anchorTick: 0)
        XCTAssertTrue(rec.isRecording)
        XCTAssertEqual(rec.midiLaneCount, 1)
        // Play a note from tick 0 to 240.
        rec.noteOn(pitch: 60, velocity: 0.9, atTick: 0)
        rec.noteOff(pitch: 60, atTick: 240)
        let takes = rec.finish(atTick: 480)
        XCTAssertEqual(takes.count, 1)
        XCTAssertEqual(takes[0].laneID, midiLane)
        XCTAssertEqual(takes[0].clip.kind, .midi)
        XCTAssertEqual(takes[0].clip.melody?.notes.count, 1)
        XCTAssertEqual(takes[0].startTick, 0)
        XCTAssertFalse(rec.isRecording)   // reset to idle
    }

    func testAnchorMakesNotesClipRelative() {
        var rec = TakeRecorder()
        // Recording starts at bar 2 (tick 3840).
        rec.start(targets: [(midiLane, .midiInput)], anchorTick: 3840)
        rec.noteOn(pitch: 64, velocity: 0.8, atTick: 3840)   // exactly at the anchor
        rec.noteOff(pitch: 64, atTick: 3960)
        let takes = rec.finish(atTick: 4320)
        XCTAssertEqual(takes.count, 1)
        // Clip-relative: the note that arrived AT the anchor starts at tick 0.
        XCTAssertEqual(takes[0].clip.melody?.notes.first?.startTick, 0)
        XCTAssertEqual(takes[0].startTick, 3840)
    }

    func testEmptyTakeIsDropped() {
        var rec = TakeRecorder()
        rec.start(targets: [(midiLane, .midiInput)], anchorTick: 0)
        // No notes played.
        XCTAssertEqual(rec.finish(atTick: 480), [])
    }

    func testHeldNoteIsFlushedOnFinish() {
        var rec = TakeRecorder()
        rec.start(targets: [(midiLane, .midiInput)], anchorTick: 0)
        rec.noteOn(pitch: 67, velocity: 0.8, atTick: 100)
        // never released → finish flushes it
        let takes = rec.finish(atTick: 500)
        XCTAssertEqual(takes.count, 1)
        XCTAssertEqual(takes[0].clip.melody?.notes.count, 1)
    }

    func testBioTakeProducesAutomation() {
        var rec = TakeRecorder()
        rec.start(targets: [(bioLane, .bio)], anchorTick: 0)
        XCTAssertEqual(rec.bioLaneCount, 1)
        // Capture a few well-spaced samples (recorder decimates by min interval).
        rec.captureBio(value: 0.2, atTick: 0)
        rec.captureBio(value: 0.5, atTick: 240)
        rec.captureBio(value: 0.8, atTick: 480)
        let takes = rec.finish(atTick: 960)
        XCTAssertEqual(takes.count, 1)
        XCTAssertEqual(takes[0].laneID, bioLane)
        XCTAssertFalse(takes[0].clip.automation.isEmpty)
    }

    func testMultipleArmedLanesEachGetATake() {
        var rec = TakeRecorder()
        rec.start(targets: [(midiLane, .midiInput), (bioLane, .bio)], anchorTick: 0)
        rec.noteOn(pitch: 48, velocity: 0.8, atTick: 0)
        rec.noteOff(pitch: 48, atTick: 120)
        rec.captureBio(value: 0.4, atTick: 0)
        rec.captureBio(value: 0.6, atTick: 240)
        let takes = rec.finish(atTick: 480)
        XCTAssertEqual(Set(takes.map(\.laneID)), [midiLane, bioLane])
    }

    func testAudioAndVideoSourcesCaptureNothingYet() {
        var rec = TakeRecorder()
        rec.start(targets: [(UUID(), .audioInput), (UUID(), .videoCapture), (UUID(), .none)],
                  anchorTick: 0)
        XCTAssertEqual(rec.midiLaneCount, 0)
        XCTAssertEqual(rec.bioLaneCount, 0)
        XCTAssertEqual(rec.finish(atTick: 480), [])
    }

    func testCancelProducesNoTakeAndResets() {
        var rec = TakeRecorder()
        rec.start(targets: [(midiLane, .midiInput)], anchorTick: 0)
        rec.noteOn(pitch: 60, velocity: 0.8, atTick: 0)
        rec.cancel()
        XCTAssertFalse(rec.isRecording)
        XCTAssertEqual(rec.finish(atTick: 480), [])
    }
}
