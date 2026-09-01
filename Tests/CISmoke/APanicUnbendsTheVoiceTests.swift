// APanicUnbendsTheVoiceTests.swift
// Echoel — #945. Blocking bundle. END-TO-END BEHAVIOUR on a shipped, constructible type
// (`Tests/CISmoke/CLAUDE.md` §1), plus ONE source-text claim that is labelled as such.
//
// ⭐ THE DEFECT, AND IT IS THE FOURTH INSTANCE OF ONE THIS FILE'S SIBLINGS ALREADY FIXED
// THREE TIMES. `panic()` exists to break state a controller left behind when no control can
// clear it — its own doc block says so, and it clears `heldNotes` (#943), `expressionGain`
// (#939) and `renderCutoffScale` (#942) for exactly that reason. It did NOT clear the fourth
// thing a controller writes: the PITCH.
//
// `case .pitchBend` writes `synth.frequency` directly. `panic()` then releases the note, so
// nothing is sounding and the bend looks gone. It is not: the BREATH path calls
// `playNote()` with NO frequency argument (`consumeBioEventsIfFresh`, and `arm()` likewise),
// and `playNote`'s own doc says it opens the envelope "at the synth's current frequency".
// So every breath note after a bend sounds AT THE BENT PITCH — up to two semitones off, for
// the rest of the session, with no control that can put it back. Plug a controller in, nudge
// the wheel, unplug it, switch to breath play: the instrument is detuned and the panic button
// does not help.
//
// ⚠️ WHAT THIS SLICE DELIBERATELY DOES **NOT** DECIDE. That the breath voice follows the last
// PLAYED note during ordinary performance is left exactly as it is. It is arguably the point
// — play a note, then let the body swell it — and it is a founder's ear question, not a
// cleanup. Only `panic()` changes, because panic already means "forget every controller",
// and it was forgetting three of the four things.
// NEEDS-FOUNDER-VERIFY: MIDI-Keyboard anschließen, eine Note spielen, Pitch-Bend-Rad ganz
// hochziehen, loslassen; dann "Body voice" einschalten und atmen — der Atemton muss auf der
// Grundstimmung liegen, NICHT auf der verbogenen. Und: SOLL der Atemton überhaupt der zuletzt
// gespielten Note folgen, oder immer auf seiner eigenen Stimmung bleiben?
//
// ⚠️ HONEST GRADING. There is no local Swift toolchain (§0), so both implementations were
// transcribed into Python and every assertion in this file driven against each, with the
// expectations derived from the algebra rather than read off a printed value (#442).
// **8 assertions. Exactly 1 is a REGRESSION CATCH** — claim 1's "panic restores the nominal
// pitch", red on the parent and green here. **7 are COUNTERWEIGHTS (#343)**, green on both,
// and they are the point of the file: without them "panic unbends" is satisfied by a panic
// that also resets the pitch DURING play (claim 3), by a `playNote()` that stopped inheriting
// the pitch at all (claim 2, which is what makes claim 1 a user-visible defect rather than a
// tidy-up), or by a panic that drops one of the three latches it already cleared (claim 4).
// **0 broken, 0 red on this worktree.**
//
// ⛔ AND MY FIRST DRAFT OF THIS BLOCK SAID "7 assertions, 2 REGRESSION CATCHES" — both numbers
// guessed from the shape of the file rather than counted, and both in the FLATTERING direction
// (#433/#464): the count was one low and the catch count one high, because claim 1's
// PRECONDITION passes on the parent too — a bend raises the pitch on both trees, which is the
// whole reason it is a precondition. Corrected by running the transcription, not by re-reading.
//
// ⚠️ THE FILE DOES NOT COMPILE AGAINST THE PARENT: `nominalFrequencyForTests` is new in this
// commit. Every assertion still HAS a meaning there — the accessor reads a value the parent's
// voice also carries — which is why the grading above is a real verdict rather than "not
// gradable". Said plainly so it cannot read as "green there" (#488).
//
// ⚠️ NO Hz LITERAL IS PINNED. `EchoelDDSP.frequency`'s default and `tuningA4Hz` both belong to
// shipped types; restating either here would be the #416 defect, and pinning 110.0 would redden
// a legitimate voicing change (#364). Every assertion is a RATIO or a comparison against a
// value read back from the voice itself.

import Foundation
import XCTest
@testable import Echoelmusic

@MainActor
final class APanicUnbendsTheVoiceTests: XCTestCase {

    private func note(_ n: UInt8, on: Bool) -> ControllerEvent {
        ControllerEvent(timestamp: on ? 1 : 2, kind: on ? .noteOn : .noteOff, channel: 1,
                        note: n, value: on ? 0.8 : 0, auxCC: 0)
    }

    private func bend(_ value: Float, note n: UInt8) -> ControllerEvent {
        ControllerEvent(timestamp: 3, kind: .pitchBend, channel: 1, note: n, value: value, auxCC: 0)
    }

    /// claim 1 — the whole point. After a bend, `panic()` must leave the voice on the pitch it
    /// would have with no controller attached, because the breath path inherits that pitch.
    func testPanicRestoresThePitchABendLeftBehind() {
        let v = BioReactiveSynthVoice()
        let nominal = v.nominalFrequencyForTests
        v.applyControllerForTests(note(60, on: true))
        v.applyControllerForTests(bend(1.0, note: 60))
        let bent = v.synth.frequency

        // precondition, or claim 1 is vacuous: the bend really moved the pitch (#367).
        XCTAssertGreaterThan(bent, v.soundingFrequency(forMIDINote: 60), """
            The bend did not raise the pitch at all, so the restore below proves nothing. \
            Re-derive: value 1.0 is +2 semitones, a ratio of 2^(2/12).
            """)

        v.panic()

        XCTAssertEqual(v.synth.frequency, nominal, accuracy: 1e-3, """
            `panic()` left the bent pitch on the voice. It clears the held-key stack (#943), \
            `expressionGain` (#939) and `renderCutoffScale` (#942) precisely because a \
            controller can strand each of them — and the PITCH is the fourth thing a \
            controller writes. It matters because the breath path calls `playNote()` with no \
            frequency and inherits whatever is there, so every breath note stays detuned for \
            the rest of the session with no control that can fix it.
            """)
    }

    /// claim 2 — and the breath note really does inherit it, which is what makes claim 1 a
    /// defect rather than a tidy-up. COUNTERWEIGHT: green on both trees.
    func testTheBreathNoteSoundsAtWhateverPitchTheVoiceCarries() {
        let v = BioReactiveSynthVoice()
        v.applyControllerForTests(note(60, on: true))
        v.applyControllerForTests(note(60, on: false))
        let afterPlaying = v.synth.frequency

        v.arm()   // `arm()` is `isArmed = true; playNote()` — the same frequency-less call
                  // the breath onset makes.

        XCTAssertTrue(v.isPlayingNote, "precondition: arming sounds the voice")
        XCTAssertEqual(v.synth.frequency, afterPlaying, accuracy: 1e-3, """
            A frequency-less `playNote()` no longer inherits the voice's current pitch. If \
            that changed on purpose, claim 1 above is no longer describing a user-visible \
            defect and this file's header must be rewritten in the same commit — the header \
            argues from exactly this inheritance.
            """)
    }

    /// claim 3 (COUNTERWEIGHT) — panic must not become a tuning reset that fires during play.
    /// Without this, claim 1 is satisfied by clearing the pitch on every note-off too, which
    /// would cut short the "play a note, then breathe it" gesture the header protects.
    func testOrdinaryPlayingIsNotUnbent() {
        let v = BioReactiveSynthVoice()
        v.applyControllerForTests(note(60, on: true))
        v.applyControllerForTests(bend(1.0, note: 60))
        let bent = v.synth.frequency
        v.applyControllerForTests(note(60, on: false))      // release, no panic

        XCTAssertEqual(v.synth.frequency, bent, accuracy: 1e-3, """
            Lifting the key reset the pitch. Only `panic()` may do that — a note-off is an \
            ordinary part of playing, and the voice keeps its pitch across one so the body \
            can take the note over.
            """)
    }

    /// claim 4 (COUNTERWEIGHT) — the three latches panic already cleared must stay cleared.
    /// This file adds a fourth line to that method; a regression that drops one of the other
    /// three would otherwise be invisible here.
    func testPanicStillClearsTheThreeLatchesItAlreadyDid() {
        let v = BioReactiveSynthVoice()
        v.applyControllerForTests(note(60, on: true))
        v.applyControllerForTests(
            ControllerEvent(timestamp: 4, kind: .channelPressure, channel: 1,
                            note: 60, value: 1.0, auxCC: 0))
        v.applyControllerForTests(
            ControllerEvent(timestamp: 5, kind: .slide, channel: 1,
                            note: 60, value: 1.0, auxCC: 74))

        v.panic()

        XCTAssertEqual(v.synth.expressionGain, 1, accuracy: 1e-6,
                       "#939's press latch survived a panic")
        XCTAssertEqual(v.synth.renderCutoffScale, 1, accuracy: 1e-6,
                       "#942's slide latch survived a panic")
        XCTAssertFalse(v.heldByControllerForTests, "#943's held-key stack survived a panic")
    }
}
