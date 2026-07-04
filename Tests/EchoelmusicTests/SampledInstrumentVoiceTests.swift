// SampledInstrumentVoiceTests.swift
// Echoel — real-instrument voice (Apple sampler + GeneralUser GS bank).
// Pure MIDI mapping + graceful-absence behaviour (no soundfont in the test
// bundle → never ready, never crashing — the roll falls back to the synth).

#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

@MainActor
final class SampledInstrumentVoiceTests: XCTestCase {

    func testMidiVelocity_neverZero_andClamped() {
        XCTAssertEqual(SampledInstrumentVoice.midiVelocity(0), 1,
                       "velocity 0 must map to 1 — 0 would be a note-off on the wire")
        XCTAssertEqual(SampledInstrumentVoice.midiVelocity(-1), 1)
        XCTAssertEqual(SampledInstrumentVoice.midiVelocity(1), 127)
        XCTAssertEqual(SampledInstrumentVoice.midiVelocity(2), 127)
        XCTAssertEqual(SampledInstrumentVoice.midiVelocity(0.5), 64)
    }

    func testMidiPitch_clampsToMIDIRange() {
        XCTAssertEqual(SampledInstrumentVoice.midiPitch(-5), 0)
        XCTAssertEqual(SampledInstrumentVoice.midiPitch(60), 60)
        XCTAssertEqual(SampledInstrumentVoice.midiPitch(300), 127)
    }

    func testGracefulWithoutSoundfont() {
        // The test bundle ships no .sf2 → load stays not-ready and every note
        // call is a safe no-op (the router then uses the classic synth).
        let v = SampledInstrumentVoice()
        v.load(program: .grandPiano)
        XCTAssertFalse(v.isReady)
        v.noteOn(pitch: 60, velocity: 0.8)
        v.noteOff(pitch: 60)
        v.allNotesOff()
    }

    func testProgramNumbersAreGM() {
        XCTAssertEqual(SampledInstrumentVoice.Program.grandPiano.rawValue, 0)
        XCTAssertEqual(SampledInstrumentVoice.Program.ePiano.rawValue, 4)
        XCTAssertEqual(SampledInstrumentVoice.Program.strings.rawValue, 48)
        XCTAssertEqual(SampledInstrumentVoice.Program.warmPad.rawValue, 89)
        XCTAssertEqual(SampledInstrumentVoice.Program.fingerBass.rawValue, 33)
    }
}
#endif
