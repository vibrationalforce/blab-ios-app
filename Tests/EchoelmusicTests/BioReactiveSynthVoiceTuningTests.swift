// BioReactiveSynthVoiceTuningTests.swift
// Echoel — the bio voice must honor the concert pitch (Kammerton) like every other
// melodic voice. Regression for "Kammerton A4 ignored by the bio voices": the note→Hz
// path was a hardcoded-440 static, so a lane bio unit droned at 440 while the rest of
// the instrument retuned to e.g. A=432.

import XCTest
@testable import Echoelmusic

@MainActor
final class BioReactiveSynthVoiceTuningTests: XCTestCase {

    func testDefaultsToA440() {
        let v = BioReactiveSynthVoice()
        XCTAssertEqual(v.soundingFrequency(forMIDINote: 69), 440, accuracy: 1e-3, "A4 default")
    }

    func testHonorsKammertonAt432() {
        let v = BioReactiveSynthVoice()
        v.setTuning(a4Hz: 432)
        XCTAssertEqual(v.soundingFrequency(forMIDINote: 69), 432, accuracy: 1e-3, "A4 = 432 after retune")
        XCTAssertEqual(v.soundingFrequency(forMIDINote: 81), 864, accuracy: 1e-2, "octave up tracks A4")
        XCTAssertEqual(v.soundingFrequency(forMIDINote: 57), 216, accuracy: 1e-2, "octave down tracks A4")
    }

    func testEqualTemperamentRatioIsPreservedAcrossA4() {
        // A semitone is always 2^(1/12) regardless of the reference — only the anchor moves.
        let v = BioReactiveSynthVoice()
        v.setTuning(a4Hz: 442)
        let a4 = v.soundingFrequency(forMIDINote: 69)
        let aSharp4 = v.soundingFrequency(forMIDINote: 70)
        XCTAssertEqual(aSharp4 / a4, powf(2, 1.0 / 12), accuracy: 1e-5)
    }

    func testNonFiniteTuningIsRejected_noStuckOscillator() {
        // A NaN would slip through min/max and poison a4Hz → silent oscillator.
        let v = BioReactiveSynthVoice()
        v.setTuning(a4Hz: 432)
        v.setTuning(a4Hz: .nan)                                 // must be a no-op
        XCTAssertEqual(v.soundingFrequency(forMIDINote: 69), 432, accuracy: 1e-3, "NaN ignored; last good tuning kept")
        v.setTuning(a4Hz: .infinity)
        XCTAssertTrue(v.soundingFrequency(forMIDINote: 69).isFinite, "infinity ignored; frequency stays finite")
    }

    func testTuningClampsToMusicalRange() {
        let v = BioReactiveSynthVoice()
        v.setTuning(a4Hz: 100)                                  // absurdly low
        XCTAssertEqual(v.soundingFrequency(forMIDINote: 69), 380, accuracy: 1e-3, "clamped up to floor")
        v.setTuning(a4Hz: 9999)                                 // absurdly high
        XCTAssertEqual(v.soundingFrequency(forMIDINote: 69), 500, accuracy: 1e-3, "clamped down to ceiling")
    }

    // MARK: - Performance panic (the controller-held latch)

    /// A lost external note-off leaves `heldByController` true, and `consumeBioEventsIfFresh`
    /// then refuses EVERY breath onset — breath play is dead for the rest of the session with
    /// no UI control able to clear it. `panic()` exists to break that latch.
    ///
    /// SCOPE, stated plainly: this pins that `panic()` clears the latch and that
    /// `releaseNote()` does not — i.e. that `panic()` is not a trivial alias. It does NOT pin
    /// the CALL SITE. `EchoelStudioView.panicAllNotesOff()` is private on a `View` struct and
    /// unreachable from XCTest, so nothing here fails if someone reverts that line to
    /// `bioVoice.releaseNote()`. (An earlier version of this comment claimed it would — it
    /// could not. See task #168 for making the panic fan-out itself testable.)
    func testBioPanic_clearsAStuckControllerHeldLatch() {
        let noteOn = ControllerEvent(timestamp: 1, kind: .noteOn, channel: 1,
                                     note: 60, value: 0.8, auxCC: 0)

        let voice = BioReactiveSynthVoice()
        voice.applyControllerForTests(noteOn)     // external note-on…
        // …and NO matching note-off ever arrives (cable pulled mid-note).
        XCTAssertTrue(voice.isPlayingNote, "precondition: the controller note must be sounding")
        XCTAssertTrue(voice.heldByControllerForTests, "precondition: the latch must be set")

        voice.panic()

        XCTAssertFalse(voice.isPlayingNote, "panic must release the sounding note")
        XCTAssertFalse(voice.heldByControllerForTests,
                       "panic left the controller latch set — breath play stays dead")

        let releaseOnly = BioReactiveSynthVoice()
        releaseOnly.applyControllerForTests(noteOn)
        releaseOnly.releaseNote()
        XCTAssertTrue(releaseOnly.heldByControllerForTests,
                      "releaseNote() alone still leaves the latch set — that is WHY panic() exists")
    }
}
