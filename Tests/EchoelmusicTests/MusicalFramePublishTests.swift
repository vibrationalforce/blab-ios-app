// MusicalFramePublishTests.swift
// Echoel — the piano roll is the source of "what's sounding now": verify it maps the
// live chord into a MusicalFrame correctly (pitch→Hz at concert pitch, velocity→
// amplitude, summed-velocity master) so renderers colour/move by the right music.

#if canImport(SwiftUI) && canImport(AVFoundation) && canImport(Accelerate)
import XCTest
import Foundation
@testable import Echoelmusic

@MainActor
final class MusicalFramePublishTests: XCTestCase {

    func testEmptyChord_isSilent() {
        let f = PianoRollModel.musicalFrame(forActive: [], a4Hz: 440,
                                            rootPitchClass: 9, scaleName: "minor",
                                            tempoBPM: 120, beatPhase: 0.5)
        XCTAssertTrue(f.notes.isEmpty)
        XCTAssertEqual(f.masterLevel, 0, accuracy: 1e-9)
        XCTAssertFalse(f.isSounding)
        XCTAssertEqual(f.rootPitchClass, 9)
        XCTAssertEqual(f.tempoBPM, 120, accuracy: 1e-9)
    }

    func testA4_mapsTo440_atStandardConcertPitch() {
        let f = PianoRollModel.musicalFrame(forActive: [Note(pitch: 69, startStep: 0)],
                                            a4Hz: 440, rootPitchClass: 9, scaleName: "major",
                                            tempoBPM: 90, beatPhase: 0)
        XCTAssertEqual(f.notes.count, 1)
        XCTAssertEqual(f.notes[0].frequencyHz, 440, accuracy: 1e-6)
        XCTAssertEqual(f.notes[0].amplitude, 0.8, accuracy: 1e-6)  // default velocity
        XCTAssertTrue(f.isSounding)
    }

    func testConcertPitch_shiftsFrequency() {
        let f = PianoRollModel.musicalFrame(forActive: [Note(pitch: 69, startStep: 0)],
                                            a4Hz: 432, rootPitchClass: -1, scaleName: "",
                                            tempoBPM: 0, beatPhase: 0)
        XCTAssertEqual(f.notes[0].frequencyHz, 432, accuracy: 1e-6)
    }

    func testMaster_sumsVelocities_andClamps() {
        let two = [Note(pitch: 60, startStep: 0, lengthSteps: 1, velocity: 0.4),
                   Note(pitch: 64, startStep: 0, lengthSteps: 1, velocity: 0.3)]
        let f = PianoRollModel.musicalFrame(forActive: two, a4Hz: 440, rootPitchClass: 0,
                                            scaleName: "major", tempoBPM: 100, beatPhase: 0.25)
        XCTAssertEqual(f.masterLevel, 0.7, accuracy: 1e-6)

        let loud = (0..<5).map { Note(pitch: 60 + $0, startStep: 0, lengthSteps: 1, velocity: 0.5) }
        let g = PianoRollModel.musicalFrame(forActive: loud, a4Hz: 440, rootPitchClass: 0,
                                            scaleName: "major", tempoBPM: 100, beatPhase: 0)
        XCTAssertEqual(g.masterLevel, 1.0, accuracy: 1e-9)   // 2.5 → clamped
    }

    // MARK: - Inaudible notes must not be published as sounding (device log 2472)

    func testInaudibleChord_publishesAsARest_notAsFiveSilentNotes() {
        // THE LOG LINE THIS COMES FROM, v10.79.355 build 2472:
        //   `visual: bio=1 mfNotes=5 mfAmp=0.000 level=0.00 tone=660 …`
        // Five ACTIVE notes, every amplitude ≈ 0. Not a rest — published silence. It is
        // reachable exactly as `audibleVelocityFloor`'s own doc describes: the mixer bakes
        // its level into compose-time velocity, and 0.05 (humanizer floor) × 0.85 (genre
        // level) × 0.01 (fader) = 0.000425.
        //
        // `active` must keep those notes — it is note bookkeeping (ties, releases, un-mute)
        // and must not depend on level. The FRAME is a different question: it answers "what
        // is sounding", and a note nobody can hear is not sounding.
        //
        // The light/spatial senders were NOT ungated — Art-Net, sACN and ADM-OSC all ask
        // `isSounding` first. Their gate was insufficient: `isSounding` is
        // `!notes.isEmpty && masterLevel > 0`, and five notes at 0.000425 sum to 0.002 > 0,
        // so a chord at about −54 dBFS passed as live. That is what this test pins: the
        // frame must not merely be quiet, it must be EMPTY, because `> 0` is the contract
        // those senders were written against.
        let silent = (0..<5).map {
            Note(pitch: 60 + $0, startStep: 0, lengthSteps: 1, velocity: 0.000425)
        }
        let f = PianoRollModel.musicalFrame(forActive: silent, a4Hz: 440, rootPitchClass: 0,
                                            scaleName: "minor", tempoBPM: 120, beatPhase: 0)
        XCTAssertTrue(f.notes.isEmpty, "an inaudible chord must publish as a rest")
        XCTAssertEqual(f.masterLevel, 0, accuracy: 1e-9)
        XCTAssertFalse(f.isSounding)
    }

    func testAudibleNotesSurvive_whenMixedWithInaudibleOnes() {
        // The filter must not be a mute: one real note among silent ones still sounds, and
        // the master reflects only what is actually heard.
        let mixed = [Note(pitch: 60, startStep: 0, lengthSteps: 1, velocity: 0.0001),
                     Note(pitch: 64, startStep: 0, lengthSteps: 1, velocity: 0.6),
                     Note(pitch: 67, startStep: 0, lengthSteps: 1, velocity: 0.0)]
        let f = PianoRollModel.musicalFrame(forActive: mixed, a4Hz: 440, rootPitchClass: 0,
                                            scaleName: "minor", tempoBPM: 120, beatPhase: 0)
        XCTAssertEqual(f.notes.count, 1)
        XCTAssertEqual(f.notes[0].amplitude, 0.6, accuracy: 1e-6)
        XCTAssertEqual(f.masterLevel, 0.6, accuracy: 1e-6)
    }

    func testTheThreshold_isTheSameOneTheFeltSubAlreadyUses() {
        // ONE audibility rule for the roll, not two that can drift — and the only way to
        // pin that is to exercise BOTH functions against the same value. An earlier version
        // of this test asserted only on `musicalFrame` while carrying this name, so
        // `feltSubPitch` could have been changed to a different threshold tomorrow with
        // every test still green — the exact drift the shared constant exists to prevent.
        let floor = PianoRollModel.audibleVelocityFloorForTests

        func note(_ v: Float) -> [Note] { [Note(pitch: 60, startStep: 0, lengthSteps: 1, velocity: v)] }
        func frame(_ v: Float) -> MusicalFrame {
            PianoRollModel.musicalFrame(forActive: note(v), a4Hz: 440, rootPitchClass: 0,
                                        scaleName: "", tempoBPM: 120, beatPhase: 0)
        }
        func sub(_ v: Float) -> Int? {
            PianoRollModel.feltSubPitch(forActive: note(v), laneAudible: true, hasKindVoice: false, bassOnly: false)
        }

        XCTAssertEqual(frame(floor * 1.01).notes.count, 1)
        XCTAssertEqual(sub(floor * 1.01), 48, "the felt sub must follow the same audible note")

        XCTAssertTrue(frame(floor * 0.99).notes.isEmpty)
        XCTAssertNil(sub(floor * 0.99), "the felt sub must drop the same inaudible note")

        // The boundary itself: both use `>`, so a note exactly AT the floor is excluded by
        // both. Pinned because a drive-by `>` → `>=` in either function is otherwise silent.
        XCTAssertTrue(frame(floor).notes.isEmpty)
        XCTAssertNil(sub(floor))
    }

    func testTheDroppedCount_survivesForTheDeviceLog() {
        // The filter deletes the fault signature that FOUND this bug: `mfNotes=5
        // mfAmp=0.000` becomes `mfNotes=0`, indistinguishable from a genuine rest in the
        // founder's pasted log. `inaudibleNoteCount` is what keeps the two apart — it is
        // diagnostic only, and no renderer may react to it.
        let silent = (0..<5).map { Note(pitch: 60 + $0, startStep: 0, lengthSteps: 1, velocity: 0.000425) }
        let f = PianoRollModel.musicalFrame(forActive: silent, a4Hz: 440, rootPitchClass: 0,
                                            scaleName: "", tempoBPM: 120, beatPhase: 0)
        XCTAssertEqual(f.notes.count, 0)
        XCTAssertEqual(f.inaudibleNoteCount, 5)

        // A genuine rest must NOT look like a silenced chord.
        let rest = PianoRollModel.musicalFrame(forActive: [], a4Hz: 440, rootPitchClass: 0,
                                               scaleName: "", tempoBPM: 120, beatPhase: 0)
        XCTAssertEqual(rest.inaudibleNoteCount, 0)

        // Nor a fully audible chord.
        let loud = (0..<3).map { Note(pitch: 60 + $0, startStep: 0, lengthSteps: 1, velocity: 0.5) }
        XCTAssertEqual(PianoRollModel.musicalFrame(forActive: loud, a4Hz: 440, rootPitchClass: 0,
                                                   scaleName: "", tempoBPM: 120,
                                                   beatPhase: 0).inaudibleNoteCount, 0)
    }
}
#endif
