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
}
#endif
