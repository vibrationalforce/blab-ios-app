// APanicUnbendsTheVoiceTests.swift
// Echoel — #945 / #945b. Blocking bundle. END-TO-END BEHAVIOUR throughout, on a shipped,
// constructible type (`Tests/CISmoke/CLAUDE.md` §1). There is NO source-text claim in this
// file. ⛔ #945b: the first version of this line said "plus ONE source-text claim that is
// labelled as such" — there was none, and in a header whose whole job is honest labelling
// that is the defect §1 exists to prevent. Found by the mandatory reviewer.
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
// So every breath note after a bend sounds AT THE BENT PITCH for the rest of the session, and
// nothing restores the NOMINAL (a later note-on or legato note-off overwrites it with an
// in-tune value — but with the controller unplugged, the case this exists for, no such event
// arrives).
//
// ⛔ #945b — AND HOW FAR OFF WAS UNDERSTATED BY TWO ORDERS, in the direction that makes a
// defect look ignorable. The first version said "up to two semitones", reading
// `event.value * 2.0` as if the bend applied to the note being played. The ONE production
// producer is `MIDIBusPublisher`'s `onPitchBend`, and it writes `note: 0` unconditionally
// (`docs/architecture.html` states the same fact), so `case .pitchBend`'s
// `event.note > 0 ? event.note : 69` fallback fires on EVERY REAL BEND and the base is A4.
// Measured: −1 → 392 Hz, 0 → 440 Hz, +1 → 493.88 Hz, i.e. **+22 to +26 semitones above this
// voice's nominal — roughly two octaves**. And the centre value is not exempt: a wheel
// springing back to 0 strands the voice at A4 exactly the same, so the trigger is "any bend
// message at all", not "nudge the wheel". Claim 1b drives that centre case for that reason.
// ⚠️ The first version's helper also took a `note:` and both call sites passed 60 — a shape
// production can never emit. A guard that drives an impossible configuration measures nothing
// about the shipped path (#367).
//
// ⚠️ WHAT THE SCOPE ACTUALLY IS. ⛔ #945b: the first version of this paragraph said "only
// `panic()` changes" and that was false. `panic()` is what `PanicFanOut` calls for this voice
// (`releaseAllNotes()`), which `panicAllNotesOff()` fans out, which is reached from the panic
// BUTTON, from `stopEverything(reason:)` AND from `pausePlaybackKeepingSession()` — so the
// pitch resets on every Stop and on the playback-only pause too. What is genuinely unchanged
// is the NOTE-OFF path: inside one continuous take the breath still follows the last played
// note, and claim 3 pins exactly that.
// NEEDS-FOUNDER-VERIFY: MIDI-Keyboard anschließen, eine Note spielen, Pitch-Bend-Rad bewegen
// und LOSLASSEN (Mitte genügt); dann "Body voice" einschalten und atmen — der Atemton muss
// auf der Grundstimmung liegen, nicht zwei Oktaven darüber. Und die offene Frage: nach jedem
// Stop und jeder Pause springt der Atemton auf A2 zurück, auch wenn die Komposition in einer
// anderen Tonart läuft (diese Stimme kennt die Tonart nicht) — richtig so, oder soll er die
// zuletzt gespielte Note über einen Stop hinweg behalten?
//
// ⚠️ HONEST GRADING. There is no local Swift toolchain (§0), so both implementations were
// transcribed into Python and every assertion in this file driven against each, with the
// expectations derived from the algebra rather than read off a printed value (#442).
// **10 assertions. 2 are REGRESSION CATCHES** — the two "panic restores the nominal", one
// after a full bend and one after a CENTRED one, red on the parent and green here.
// **8 are COUNTERWEIGHTS (#343)**, green on both, and they are the point of the file: without
// them "panic unbends" is satisfied by a panic that also resets the pitch DURING play
// (claim 3), by a `playNote()` that stopped inheriting the pitch at all (claim 2, which is
// what makes this a user-visible defect rather than a tidy-up), or by a panic that drops one
// of the three latches it already cleared (claim 4).
// **0 broken, 0 red on this worktree.**
//
// ⛔ THE FIRST TWO DRAFTS OF THIS BLOCK WERE BOTH WRONG, and the second one only because the
// first repair did not go far enough. Draft 1 said "7 assertions, 2 REGRESSION CATCHES" —
// both numbers guessed from the shape of the file rather than counted, and both in the
// FLATTERING direction (#433/#464). Draft 2 counted honestly and got 8 / 1 / 7 — correct FOR
// THE FILE AS IT THEN STOOD, and that file drove a bend shape production cannot emit (see the
// `bend(_:)` helper). Fixing the shape and adding claim 1b changes the arithmetic again.
// **The lesson is not "count" — it is that a grading is only as good as the SCENARIO it
// grades**, and this file's scenario was wrong while its arithmetic was right.
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

    /// #945b — `note: 0`, because that is what the ONE production producer emits:
    /// `MIDIBusPublisher.onPitchBend` writes it unconditionally. The first version took a
    /// `note:` and both call sites passed 60 — a shape the shipped path can never produce, so
    /// it measured nothing about it (#367). With 0, `case .pitchBend`'s
    /// `event.note > 0 ? event.note : 69` fallback fires and the base is A4, which is the whole
    /// reason the residual is two octaves rather than two semitones.
    private func bend(_ value: Float) -> ControllerEvent {
        ControllerEvent(timestamp: 3, kind: .pitchBend, channel: 1, note: 0, value: value, auxCC: 0)
    }

    /// claim 1 — the whole point. After a bend, `panic()` must leave the voice on the pitch it
    /// would have with no controller attached, because the breath path inherits that pitch.
    func testPanicRestoresThePitchABendLeftBehind() {
        let v = BioReactiveSynthVoice()
        let nominal = v.nominalFrequencyForTests
        v.applyControllerForTests(note(60, on: true))
        v.applyControllerForTests(bend(1.0))
        let bent = v.synth.frequency

        // precondition, or claim 1 is vacuous: the bend really moved the pitch (#367). It is
        // compared against the NOMINAL, not against C4 — with `note: 0` the bend does not
        // build on the key being held at all, it lands near A4 regardless (#945b).
        XCTAssertGreaterThan(bent, nominal * 2, """
            The bend left the voice within an octave of its nominal, so the restore below \
            proves little. Re-derive: the producer sends `note: 0`, `case .pitchBend` falls \
            back to note 69, so the base is A4 and value 1.0 lands at 440 * 2^(2/12).
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

    /// claim 1b (#945b) — THE CASE THAT MAKES THIS A REAL DEFECT RATHER THAN AN EDGE ONE, and
    /// the one the first version could not express because its helper took a `note:`. A bend
    /// value of ZERO is what a wheel sends when it springs back to centre — every keyboard, on
    /// every release. Because the producer sends `note: 0`, that centre message still strands
    /// the voice at A4, two octaves above nominal. So the trigger is not "nudge the wheel"; it
    /// is "any pitch-bend message at all".
    func testEvenABendReturnedToCentreStrandsTheVoiceUntilPanic() {
        let v = BioReactiveSynthVoice()
        let nominal = v.nominalFrequencyForTests
        v.applyControllerForTests(note(60, on: true))
        v.applyControllerForTests(bend(0))                 // wheel back at centre

        XCTAssertGreaterThan(v.synth.frequency, nominal * 2, """
            A centred bend left the voice near its nominal. If `case .pitchBend` learned to \
            ignore a centred value, or the producer stopped sending `note: 0`, this claim and \
            the two-octave arithmetic in this file's header must be rewritten together — the \
            header argues from exactly this fallback.
            """)

        v.panic()

        XCTAssertEqual(v.synth.frequency, nominal, accuracy: 1e-3, """
            `panic()` did not restore the nominal after a CENTRED bend. This is the common \
            case, not the edge one: releasing the wheel sends it, so an ordinary keyboard \
            leaves the breath voice two octaves high with no control able to fix it.
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
        v.applyControllerForTests(bend(1.0))
        let bent = v.synth.frequency
        v.applyControllerForTests(note(60, on: false))      // release, no panic

        XCTAssertEqual(v.synth.frequency, bent, accuracy: 1e-3, """
            Lifting the key reset the pitch. A note-off is an ordinary part of playing, and \
            the voice keeps its pitch across one so the body can take the note over.

            ⚠️ #945b — THIS PINS TODAY'S ANSWER, NOT A LAW (#364). If the founder answers the \
            open question in this file's header with "the breath tone always keeps its own \
            nominal", the natural implementation restores the pitch when the last key lifts — \
            and this claim is what must change in the same commit, not an obstacle to it.
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
