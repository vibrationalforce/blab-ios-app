// TheMonoVoiceKeepsTheKeyStillDownTests.swift
// Echoel — #943. Blocking bundle. BEHAVIOURAL, not a source-text scan.
//
// ⭐ THE DEFECT, AND IT NEEDS NO MPE — ANY KEYBOARD HITS IT. `apply(controller:)` handled
// `.noteOff` by clearing one `Bool` and releasing, WITHOUT asking which key was lifted:
//
//     case .noteOff:
//         heldByController = false
//         releaseNote()
//
// So hold C, hold E, lift C — and the instrument goes SILENT while a finger is still on E.
// This is the classic mono-synth note-priority bug, and it has a second half that is worse
// than the first: `heldByController` is also the gate that hands the voice back to the BREATH
// envelope (`guard isArmed, breathPlayEnabled, !heldByController`). So a mis-cleared latch does
// not merely stop the note — it lets the body start playing the voice underneath a key that is
// physically down. A player reads that as the instrument fighting them.
//
// ⚠️ WHY THE FIX IS LEGATO AND NOT A RE-ATTACK. When the TOP key is lifted and another is still
// held, this writes `synth.frequency` directly instead of calling `playNote`. `playNote` runs
// `synth.noteOn`, which re-arms the attack, the filter envelope, the onset chiff and the drift
// counters — a fresh transient. Hearing a new attack because you LIFTED a finger is its own
// wrong answer. The render's `smoothedFreq` one-pole (~2 ms) glides the pitch, so the note
// simply moves. Note-ON priority is deliberately UNCHANGED: a new key still re-attacks, which
// is what shipped and what a player expects.
//
// ⚠️ SAME NOTE NUMBER TWICE IS DEDUPED, and on an MPE controller that is a real (rare) case:
// two fingers can sound one pitch on two member channels. This voice does not read
// `event.channel` at all (`TheMPEInputHasNoZonesTests` claim 2 pins that), so it cannot tell
// them apart, and the honest behaviour is one entry per note number. Said here rather than
// discovered later.
//
// ⚠️ THE STACK IS BOUNDED, because the Skeptic's objection is the real risk: a note-off that
// never arrives (cable pulled, SPSC queue flooded) leaves an entry behind, and an unbounded
// list of them would keep the voice sounding forever with no key down — a WORSE failure than
// the bug being fixed. `panic()` clears the whole stack (that is what `panic()` is for), and
// the cap drops the OLDEST entry, which is the one least likely to still be under a finger.

// ⚠️ HONEST GRADING, and there is NO local Swift toolchain, so "RED before GREEN" is
// established the only way available: both note-priority implementations — the shipped `Bool`
// and the stack — were transcribed into Python and all 18 assertions of the six claims below
// driven against each.
// **FIVE are REGRESSION CATCHES**, red on the shipped code and green here: claim 1's
// "still sounding" and "latch still set", and all three of claim 2. Thirteen are
// COUNTERWEIGHTS (#343), green on both — they are what stops the cure from being worse than
// the disease, and two of them are VACUOUSLY green on the old code and said so rather than
// counted as wins: claim 1's "pitch unchanged" passed only because the old path left the
// frequency behind while silencing the voice, and claim 6's bound had no stack to bound.
//
// ⚠️ WHAT THIS CANNOT PROVE. It is arithmetic and state, not audio. That the LEGATO fallback
// is heard as a pitch move rather than a click is the render's `smoothedFreq` one-pole doing
// its job, and no test in this bundle can hear it — NEEDS-FOUNDER-VERIFY: MIDI-Keyboard
// anschließen, zwei Tasten halten, die UNTERE loslassen (nichts darf sich ändern), dann die
// OBERE loslassen (die Note muss zur unteren GLEITEN, ohne neuen Anschlag).

import Foundation
import XCTest
@testable import Echoelmusic

@MainActor
final class TheMonoVoiceKeepsTheKeyStillDownTests: XCTestCase {

    private func note(_ n: UInt8, on: Bool, at t: TimeInterval) -> ControllerEvent {
        ControllerEvent(timestamp: t, kind: on ? .noteOn : .noteOff, channel: 1,
                        note: n, value: on ? 0.8 : 0, auxCC: 0)
    }

    /// claim 1 — the whole point. Lifting a key that is NOT the sounding one must change
    /// nothing audible.
    func testLiftingTheLowerOfTwoHeldKeysKeepsTheVoiceSounding() {
        let v = BioReactiveSynthVoice()
        v.applyControllerForTests(note(60, on: true, at: 1))     // C4 down
        v.applyControllerForTests(note(64, on: true, at: 2))     // E4 down — E4 now sounds
        let e4 = v.synth.frequency

        v.applyControllerForTests(note(60, on: false, at: 3))    // lift C4, E4 still down

        XCTAssertTrue(v.isPlayingNote, """
            Lifting a key that was NOT sounding silenced the voice. E4 is still physically \
            held; the instrument must keep playing it.
            """)
        XCTAssertTrue(v.heldByControllerForTests, """
            The controller latch cleared while a key is still down. That gate also hands the \
            voice to the BREATH envelope, so the body would start playing underneath the \
            player's finger.
            """)
        XCTAssertEqual(v.synth.frequency, e4, accuracy: 1e-3, """
            The sounding pitch moved when a non-sounding key was lifted.
            """)
    }

    /// claim 2 — the other direction, and the one that must be LEGATO. Lifting the key that IS
    /// sounding falls back to the one still held, without a fresh attack.
    func testLiftingTheSoundingKeyFallsBackToTheOneStillHeld() {
        let v = BioReactiveSynthVoice()
        v.applyControllerForTests(note(60, on: true, at: 1))
        let c4 = v.synth.frequency
        v.applyControllerForTests(note(64, on: true, at: 2))

        v.applyControllerForTests(note(64, on: false, at: 3))    // lift E4, C4 still down

        XCTAssertTrue(v.isPlayingNote, "C4 is still held — the voice must not stop")
        XCTAssertTrue(v.heldByControllerForTests, "C4 is still held — the latch must stay set")
        XCTAssertEqual(v.synth.frequency, c4, accuracy: 1e-3, """
            The voice did not fall back to the key still under the finger. Last-note priority \
            means the remaining key takes over.
            """)
    }

    /// claim 3 (COUNTERWEIGHT, #343) — the ordinary single-key case must be untouched. Without
    /// this, claim 1 is satisfied by never releasing anything.
    func testTheLastKeyUpStillReleasesTheVoice() {
        let v = BioReactiveSynthVoice()
        v.applyControllerForTests(note(60, on: true, at: 1))
        v.applyControllerForTests(note(60, on: false, at: 2))
        XCTAssertFalse(v.isPlayingNote, "one key down, one key up — the note must stop")
        XCTAssertFalse(v.heldByControllerForTests, """
            The latch stayed set with no key down — breath play would never come back. That is \
            the failure this fix must not introduce while curing the opposite one.
            """)

        let two = BioReactiveSynthVoice()
        two.applyControllerForTests(note(60, on: true, at: 1))
        two.applyControllerForTests(note(64, on: true, at: 2))
        two.applyControllerForTests(note(64, on: false, at: 3))
        two.applyControllerForTests(note(60, on: false, at: 4))
        XCTAssertFalse(two.isPlayingNote, "both keys up — the note must stop")
        XCTAssertFalse(two.heldByControllerForTests, "both keys up — the latch must clear")
    }

    /// claim 4 (COUNTERWEIGHT) — `panic()` still clears everything. The stack is exactly the
    /// state a stuck-note panic exists to throw away.
    func testPanicClearsTheWholeHeldStack() {
        let v = BioReactiveSynthVoice()
        v.applyControllerForTests(note(60, on: true, at: 1))
        v.applyControllerForTests(note(64, on: true, at: 2))
        v.applyControllerForTests(note(67, on: true, at: 3))

        v.panic()

        XCTAssertFalse(v.isPlayingNote, "panic must release the sounding note")
        XCTAssertFalse(v.heldByControllerForTests, "panic must clear the whole stack, not one entry")

        // And a straggling note-off for a key panic already forgot must not resurrect anything.
        v.applyControllerForTests(note(60, on: false, at: 4))
        XCTAssertFalse(v.isPlayingNote, """
            A note-off arriving after panic re-started the voice. Panic means "forget every \
            key"; a late message about one of them is not a reason to sound again.
            """)
        XCTAssertFalse(v.heldByControllerForTests, "…and it must not set the latch either")
    }

    /// claim 5 — the same note number twice is ONE entry. This voice never reads
    /// `event.channel`, so it cannot tell two fingers on one pitch apart; one note-off must
    /// therefore end it rather than leaving a ghost that keeps the voice sounding forever.
    func testTheSameNoteTwiceLeavesNoGhost() {
        let v = BioReactiveSynthVoice()
        v.applyControllerForTests(note(60, on: true, at: 1))
        v.applyControllerForTests(note(60, on: true, at: 2))     // same pitch, second finger
        v.applyControllerForTests(note(60, on: false, at: 3))
        XCTAssertFalse(v.isPlayingNote, """
            A repeated note-on left a ghost entry behind, so one note-off no longer stops the \
            voice. Without channels there is no second note to keep — dedupe by note number.
            """)
        XCTAssertFalse(v.heldByControllerForTests, "…and the latch must clear with it")
    }

    /// claim 6 — the Skeptic's objection, made executable. Note-offs that never arrive must not
    /// grow an unbounded list of phantom keys.
    func testLostNoteOffsCannotGrowWithoutBound() {
        let v = BioReactiveSynthVoice()
        for n in 0..<200 {
            v.applyControllerForTests(note(UInt8(n % 128), on: true, at: TimeInterval(n)))
        }
        XCTAssertLessThanOrEqual(v.heldNoteCountForTests, 16, """
            The held-key stack grew past its cap on \(200) note-ons with no note-off. An \
            unbounded stack of phantom keys is a WORSE failure than the silence this fix cures: \
            the voice would sound forever with nothing under a finger.
            """)
        v.panic()
        XCTAssertEqual(v.heldNoteCountForTests, 0, "panic must empty it regardless of how it filled")
    }
}
