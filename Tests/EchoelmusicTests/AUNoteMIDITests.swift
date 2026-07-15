// AUNoteMIDITests.swift
// H5a — the pure MIDI mapping laws for per-lane AU instruments (Linux-CI):
// transpose folds into the SAME function for note-on and note-off (offs always
// mirror their on's final pitch), out-of-range pitches DROP (never fold), and
// NoteVoice velocity 0…1 maps into audible MIDI 1…127.

import XCTest
@testable import Echoelmusic

final class AUNoteMIDITests: XCTestCase {

    // MARK: - transposedPitch

    func testTransposedPitch_inRange_appliesShift() {
        XCTAssertEqual(AUNoteMIDI.transposedPitch(60, transpose: 0), 60)
        XCTAssertEqual(AUNoteMIDI.transposedPitch(60, transpose: -12), 48)
        XCTAssertEqual(AUNoteMIDI.transposedPitch(60, transpose: 7), 67)
    }

    func testTransposedPitch_boundaries_areValid() {
        XCTAssertEqual(AUNoteMIDI.transposedPitch(0, transpose: 0), 0)
        XCTAssertEqual(AUNoteMIDI.transposedPitch(127, transpose: 0), 127)
        XCTAssertEqual(AUNoteMIDI.transposedPitch(120, transpose: 7), 127)
    }

    func testTransposedPitch_outOfRange_dropsNotFolds() {
        XCTAssertNil(AUNoteMIDI.transposedPitch(120, transpose: 12), "above 127 drops")
        XCTAssertNil(AUNoteMIDI.transposedPitch(5, transpose: -12), "below 0 drops")
        XCTAssertNil(AUNoteMIDI.transposedPitch(-1, transpose: 0), "invalid input drops")
        XCTAssertNil(AUNoteMIDI.transposedPitch(128, transpose: 0))
    }

    // MARK: - midiVelocity

    func testMidiVelocity_mapsUnitRangeToAudibleMIDI() {
        XCTAssertEqual(AUNoteMIDI.midiVelocity(1.0), 127)
        XCTAssertEqual(AUNoteMIDI.midiVelocity(0.5), 64, "0.5 * 127 rounds to 64")
        XCTAssertEqual(AUNoteMIDI.midiVelocity(0), 1, "an on-event never maps to 0 (= off on many synths)")
    }

    func testMidiVelocity_clampsAndGuardsNonFinite() {
        XCTAssertEqual(AUNoteMIDI.midiVelocity(2.0), 127, "over-unity clamps")
        XCTAssertEqual(AUNoteMIDI.midiVelocity(-1), 1)
        XCTAssertEqual(AUNoteMIDI.midiVelocity(.nan), 1, "non-finite ⇒ quietest, never a crash")
        XCTAssertEqual(AUNoteMIDI.midiVelocity(.infinity), 1)
    }
}
