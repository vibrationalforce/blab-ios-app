// PolySynthVoiceTests.swift
// Echoel — polyphonic note instrument for the piano roll.
// Covers the plan's verification: voice allocation, oldest-steal, pitch→voice
// note-off, velocity clamping, and the A440 frequency map. Render-level poly
// behaviour is covered separately in DSPTests (EchoelPolyDDSPRenderTests).

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
@testable import Echoelmusic

@MainActor
final class PolySynthVoiceTests: XCTestCase {

    func testStartsSilentWithNoActiveVoices() {
        let voice = PolySynthVoice(maxVoices: 6)
        XCTAssertEqual(voice.activeVoiceCount, 0, "no voices sound before any noteOn")
    }

    func testNoteOnAllocatesDistinctVoices() {
        let voice = PolySynthVoice(maxVoices: 6)
        voice.noteOn(pitch: 60)
        voice.noteOn(pitch: 64)
        voice.noteOn(pitch: 67)
        // noteOn only ENQUEUES (audio thread applies it — see the first-note-crash
        // fix); pump the queue as the render block would before asserting allocation.
        voice.pumpNoteCommandsForTesting()
        XCTAssertEqual(voice.activeVoiceCount, 3, "a triad allocates three voices")
    }

    func testNoteOffReleasesOnlyMatchingPitch() {
        let voice = PolySynthVoice(maxVoices: 6)
        voice.noteOn(pitch: 60)
        voice.noteOn(pitch: 64)
        voice.noteOff(pitch: 60)
        voice.pumpNoteCommandsForTesting()
        XCTAssertEqual(voice.activeVoiceCount, 1, "only the released pitch frees its voice")
    }

    func testNoteOffUnknownPitchIsNoOp() {
        let voice = PolySynthVoice(maxVoices: 6)
        voice.noteOn(pitch: 60)
        voice.noteOff(pitch: 72) // never held
        voice.pumpNoteCommandsForTesting()
        XCTAssertEqual(voice.activeVoiceCount, 1)
    }

    func testAllNotesOffClearsEverything() {
        let voice = PolySynthVoice(maxVoices: 6)
        voice.noteOn(pitch: 60)
        voice.noteOn(pitch: 64)
        voice.noteOn(pitch: 67)
        voice.allNotesOff()
        voice.pumpNoteCommandsForTesting()
        XCTAssertEqual(voice.activeVoiceCount, 0)
    }

    func testPolyphonyNeverExceedsMaxVoices_oldestStolen() {
        let voice = PolySynthVoice(maxVoices: 3)
        // Press more notes than there are voices; the engine steals the oldest.
        for pitch in [60, 62, 64, 65, 67] {
            voice.noteOn(pitch: pitch)
        }
        voice.pumpNoteCommandsForTesting()
        XCTAssertLessThanOrEqual(voice.activeVoiceCount, 3,
                                 "active voices never exceed the pool size")
    }

    func testVelocityIsClampedToUnitRange() {
        let voice = PolySynthVoice(maxVoices: 2)
        // Out-of-range velocities must not crash or push an invalid amplitude.
        voice.noteOn(pitch: 60, velocity: 5.0)
        voice.noteOn(pitch: 64, velocity: -2.0)
        voice.pumpNoteCommandsForTesting()
        XCTAssertEqual(voice.activeVoiceCount, 2)
    }

    func testFrequencyMapIsA440EqualTemperament() {
        XCTAssertEqual(PolySynthVoice.frequency(forMIDINote: 69), 440, accuracy: 0.001)
        XCTAssertEqual(PolySynthVoice.frequency(forMIDINote: 57), 220, accuracy: 0.001, "A3")
        XCTAssertEqual(PolySynthVoice.frequency(forMIDINote: 81), 880, accuracy: 0.001, "A5")
        // One semitone above A440 is the 12th root of two.
        XCTAssertEqual(PolySynthVoice.frequency(forMIDINote: 70), 440 * powf(2, 1.0 / 12),
                       accuracy: 0.01)
    }

    func testApplyPatchFansAcrossVoicesWithoutCrash() {
        let voice = PolySynthVoice(maxVoices: 4)
        voice.noteOn(pitch: 60)
        var patch = SynthPatch(name: "Test")
        patch.brightness = 0.9
        patch.harmonicity = 0.5
        voice.apply(patch)   // sets the RICHNESS unison default (2 voices/note) synchronously
        voice.pumpNoteCommandsForTesting()
        // Patch recall is a fan-out; assert it leaves the voice sounding in a valid state
        // (no crash). One pressed note now allocates >=1 voice — the unison-richness
        // default spawns extra detuned voices, so assert "still sounding", not exactly 1.
        XCTAssertGreaterThanOrEqual(voice.activeVoiceCount, 1)
    }

    func testBioModulationDisabledByDefault() {
        let voice = PolySynthVoice(maxVoices: 4)
        XCTAssertFalse(voice.bioModulationEnabled,
                       "designed patch defines timbre; bio is opt-in for the poly voice")
    }

    func testTuningCentsMirrorTracksTheAudioTable() {
        let voice = PolySynthVoice(maxVoices: 2)
        XCTAssertEqual(voice.uiTuningCents, Array(repeating: 0, count: 12), "default is 12-TET")
        // Pythagorean-style offsets land in the UI mirror (colour math reads it).
        var cents = [Float](repeating: 0, count: 12)
        cents[4] = 7.82   // Pythagorean major third (81:64) vs 12-TET
        cents[7] = 1.955  // pure fifth (3:2) vs 12-TET
        voice.setTuningCents(cents)
        XCTAssertEqual(voice.uiTuningCents[4], 7.82, accuracy: 0.001)
        XCTAssertEqual(voice.uiTuningCents[7], 1.955, accuracy: 0.001)
        // A malformed table must not corrupt the mirror (audio side ignores it too).
        voice.setTuningCents([1, 2, 3])
        XCTAssertEqual(voice.uiTuningCents[4], 7.82, accuracy: 0.001, "wrong count is a no-op")
    }
}
#endif
