// MusicalFrameTests.swift
// Echoel — the DMMW musical-parameter snapshot: safe construction/clamping and the
// "is there live musical content?" gate that renderers (visual/light) subscribe on.

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
import Foundation
@testable import Echoelmusic

final class MusicalFrameTests: XCTestCase {

    func testNote_clampsAmplitude_andGuardsNonFinite() {
        XCTAssertEqual(MusicalNote(frequencyHz: 440, amplitude: 2).amplitude, 1, accuracy: 1e-9)
        XCTAssertEqual(MusicalNote(frequencyHz: 440, amplitude: -1).amplitude, 0, accuracy: 1e-9)
        XCTAssertEqual(MusicalNote(frequencyHz: .nan, amplitude: .nan).frequencyHz, 0, accuracy: 1e-9)
        XCTAssertEqual(MusicalNote(frequencyHz: .nan, amplitude: .nan).amplitude, 0, accuracy: 1e-9)
    }

    func testInit_clampsLevelsAndPhase() {
        let f = MusicalFrame(beatPhase: 1.7, trackLevels: [2, -1, 0.5], masterLevel: 9)
        XCTAssertEqual(f.beatPhase, 1, accuracy: 1e-9)
        XCTAssertEqual(f.trackLevels, [1, 0, 0.5])
        XCTAssertEqual(f.masterLevel, 1, accuracy: 1e-9)
    }

    func testRootPitchClass_normalizes() {
        XCTAssertEqual(MusicalFrame(rootPitchClass: 14).rootPitchClass, 2)
        XCTAssertEqual(MusicalFrame(rootPitchClass: 5).rootPitchClass, 5)
        XCTAssertEqual(MusicalFrame(rootPitchClass: -1).rootPitchClass, -1)   // unknown
        XCTAssertEqual(MusicalFrame(rootPitchClass: -3).rootPitchClass, -1)   // any negative = unknown
    }

    func testTempo_rejectsNonPositiveAndNonFinite() {
        XCTAssertEqual(MusicalFrame(tempoBPM: 120).tempoBPM, 120, accuracy: 1e-9)
        XCTAssertEqual(MusicalFrame(tempoBPM: -5).tempoBPM, 0, accuracy: 1e-9)
        XCTAssertEqual(MusicalFrame(tempoBPM: .infinity).tempoBPM, 0, accuracy: 1e-9)
    }

    func testSilent_isNotSounding() {
        XCTAssertFalse(MusicalFrame.silent.isSounding)
        XCTAssertTrue(MusicalFrame.silent.notes.isEmpty)
    }

    func testIsSounding_requiresNotesAndLevel() {
        let notesNoLevel = MusicalFrame(notes: [MusicalNote(frequencyHz: 440, amplitude: 1)], masterLevel: 0)
        XCTAssertFalse(notesNoLevel.isSounding)
        let levelNoNotes = MusicalFrame(masterLevel: 0.8)
        XCTAssertFalse(levelNoNotes.isSounding)
        let live = MusicalFrame(notes: [MusicalNote(frequencyHz: 440, amplitude: 1)], masterLevel: 0.8)
        XCTAssertTrue(live.isSounding)
    }

    func testEquatable() {
        let a = MusicalFrame(timestamp: 100, notes: [MusicalNote(frequencyHz: 440, amplitude: 0.5)],
                             rootPitchClass: 9, tempoBPM: 120, masterLevel: 0.7)
        let b = MusicalFrame(timestamp: 100, notes: [MusicalNote(frequencyHz: 440, amplitude: 0.5)],
                             rootPitchClass: 9, tempoBPM: 120, masterLevel: 0.7)
        XCTAssertEqual(a, b)
    }
}
#endif
