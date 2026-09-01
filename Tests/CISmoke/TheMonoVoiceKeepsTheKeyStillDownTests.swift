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
// wrong answer. The render's `smoothedFreq` one-pole carries the pitch across without a click
// (τ ≈ 2.1 ms — a de-click, NOT a portamento; see the measurement below). Note-ON priority is
// deliberately UNCHANGED: a new key still re-attacks, which is what shipped and what a player
// expects.
//
// ⚠️ SAME NOTE NUMBER TWICE IS DEDUPED, and on an MPE controller that is a real (rare) case:
// two fingers can sound one pitch on two member channels. This voice does not read
// `event.channel` at all (`TheMPEInputHasNoZonesTests` claim 2 pins that), so it cannot tell
// them apart, and the honest behaviour is one entry per note number. Said here rather than
// discovered later.
//
// ⚠️ A STRANDED KEY HAS THREE NETS, AND THE FIRST DRAFT HAD ONLY THE WEAKEST. The Skeptic's
// objection is the real risk: a note-off that never arrives (cable pulled, SPSC queue flooded)
// leaves an entry behind. #943 answered with a CAP, and #943's mandatory review showed the cap
// answers the wrong question — it bounds MEMORY, while ONE stranded entry already produces
// "a voice that can never be released". Worse, the stack REMOVED a recovery the old single
// `Bool` had for free: back then any later note-off cleared the latch. So, in order of who
// gets there first: entries carry their arrival time and a SUPERSEDED one older than a minute
// is pruned on the next note event (claim 7, and claim 7b pins that a real chord and a lone
// held key are exempt); `panic()` clears everything immediately (claim 4); the cap is the last
// net, for a burst faster than the window (claim 6).

// ⚠️ HONEST GRADING, and there is NO local Swift toolchain, so "RED before GREEN" is
// established the only way available (`Tests/CISmoke/CLAUDE.md` §0): the note-priority path
// was transcribed into Python in THREE versions and every assertion in this file — **27**,
// across eight claims — driven against each. The three trees matter separately, and #943b
// exists because of the middle one:
//   OLD  = the shipped single `Bool` (pre-#943)
//   #943 = the stack, as committed — no prune
//   NEW  = this worktree: stack + `pruneStaleHolds`
//
// · **8 are REGRESSION CATCHES** — red on OLD, green here: both of claim 1's state
//   assertions, all five of claim 2 (three behavioural + the two that read the `.noteOff`
//   branch as source text), and both halves of claim 7b's first case.
// · **19 are COUNTERWEIGHTS (#343)** — green on OLD and here. That is the point of most of
//   them; they are what stops the cure from being worse than the disease.
// · **2 of those 19 are red on the MIDDLE tree**, and they are the whole reason for #943b:
//   claim 7's pair passes on OLD (any note-off cleared the `Bool`), FAILS on #943 as
//   committed, and passes again here. A delta graded only against OLD would have booked them
//   as ordinary counterweights and shown nothing — the regression they name lived entirely
//   between two of my own commits.
// · **0 assertions are red on this worktree, and 0 were broken by this slice.**
//
// ⚠️ FOUR of the 19 are VACUOUSLY green on OLD and are said so rather than counted as wins:
// claim 1's "pitch unchanged" (the old path left the frequency behind while silencing the
// voice), claim 2's "does not call `playNote`" (that branch had no fallback at all to call
// it with), and both of claim 6 (there was no stack to bound or to empty).
//
// ⚠️ WHAT THIS CANNOT PROVE. It is arithmetic and state, not audio. No test in this bundle
// can hear the fallback.
// NEEDS-FOUNDER-VERIFY: MIDI-Keyboard anschließen, zwei Tasten halten, die UNTERE loslassen
// (es darf sich NICHTS ändern), dann die OBERE loslassen — die Note muss auf die untere
// wechseln OHNE neuen Anschlag und OHNE Klick.
//
// ⛔ AND THE FIRST VERSION OF THAT ASK SAID "die Note muss zur unteren GLEITEN" — a PORTAMENTO,
// which this instance cannot produce, so the founder would have spent a device session
// reporting a correct build as broken. Measured by #943's review: the render's one-pole is
// `smoothedFreq += glideCoeff * (frequency - smoothedFreq)` with `glideCoeff = 0.01`, and the
// ONLY writer of `glideCoeff` is the POLY engine's per-voice fan-out — nothing writes it on
// this instance. τ ≈ 100 samples ≈ 2.1 ms at 48 kHz. That is a de-click, not a glide, and the
// ask now asks for what the code delivers (§6 of `.claude/rules/context.md`: a question to the
// founder is more expensive than any measurement).

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
    func testLiftingTheSoundingKeyFallsBackToTheOneStillHeld() throws {
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

        // ⛔ #943b — THE THREE ASSERTIONS ABOVE ARE ALL SATISFIED BY A RE-ATTACK, i.e. by
        // `if wasTop { playNote(frequency: …) }`, which is the ONE thing this file's header and
        // the source comment argue is wrong. Green for a reason other than its own name (#367),
        // found by #943's mandatory review. Whether the move is HEARD as a glide cannot be
        // asserted here — whether `playNote` is CALLED can, and that is the half that decides
        // between a moving note and a fresh transient.
        let branch = try noteOffBranch()
        XCTAssertTrue(branch.contains("synth.frequency ="), """
            The `.noteOff` fallback no longer writes `synth.frequency` directly. If it moved to \
            another route, re-anchor here on that route — but if it now calls `playNote`, the \
            player hears a fresh attack for LIFTING a finger.
            """)
        XCTAssertFalse(branch.contains("playNote("), """
            The `.noteOff` branch calls `playNote(`, which runs `synth.noteOn` and re-arms the \
            attack, the filter envelope, the onset chiff and the drift counters. Lifting a \
            finger must MOVE the note, not restart it.
            """)
    }

    /// The brace-matched `case .noteOff:` branch of `apply(controller:)`, as source text.
    /// Anchored on the case label, which occurs once in that member.
    private func noteOffBranch() throws -> String {
        let voice = "Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift"
        // Same shape as the sibling guards' `repoRoot()` (#416 — one way to find the tree):
        // SKIP when there is no checkout at all, FAIL when a named file moved (#454).
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        let url = root.appendingPathComponent(voice)
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("\(voice) is missing while the tree is present — renamed or moved. Re-anchor.")
            return ""
        }
        let code = SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
        guard code.components(separatedBy: "case .noteOff:").count - 1 == 1,
              let start = code.range(of: "case .noteOff:"),
              let end = code.range(of: "case .pitchBend:", range: start.upperBound..<code.endIndex)
        else {
            XCTFail("""
                Could not bracket the `.noteOff` branch between `case .noteOff:` and \
                `case .pitchBend:` in \(voice). This scan found nothing rather than nothing \
                wrong (#454) — re-anchor it in the same commit as whatever moved those cases.
                """)
            return ""
        }
        return String(code[start.upperBound..<end.lowerBound])
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

    /// claim 7 — #943b, and it exists because #943 REMOVED a recovery the old single `Bool`
    /// gave for free. Back then a lost note-off left the latch stuck, but playing and
    /// releasing ANY key cleared it. With a stack, the released key falls back LEGATO to the
    /// stranded one — forever, and every later note-off re-lands on the phantom. Found by
    /// #943's mandatory review; the cap does NOT address it (one stranded entry is already
    /// "a voice that can never be released"; the cap only bounds memory).
    func testAStrandedKeyIsForgottenOnceThePlayerHasMovedOn() {
        let v = BioReactiveSynthVoice()
        v.applyControllerForTests(note(60, on: true, at: 0))      // cable pulled: no note-off
        v.applyControllerForTests(note(62, on: true, at: 3600))   // an hour later, play D
        v.applyControllerForTests(note(62, on: false, at: 3601))  // …and release it
        XCTAssertFalse(v.isPlayingNote, """
            A key stranded by a lost note-off still holds the voice after the player has moved \
            on. Playing and releasing another key must end in silence, the way it did before \
            the stack existed — otherwise `panic()` is the ONLY escape from a dropped message.
            """)
        XCTAssertFalse(v.heldByControllerForTests, """
            …and breath play stays dead, which is the half that costs a whole session.
            """)
    }

    /// claim 7b (COUNTERWEIGHT, #343) — and the prune must not eat a REAL chord. Without this,
    /// claim 7 is satisfied by forgetting keys aggressively, which is the #943 bug again.
    func testARealChordIsNotPrunedAndALoneKeyIsNeverPrunedAtAnyAge() {
        let v = BioReactiveSynthVoice()
        v.applyControllerForTests(note(60, on: true, at: 0))
        let c4 = v.synth.frequency
        v.applyControllerForTests(note(64, on: true, at: 1))      // an ordinary chord voicing
        v.applyControllerForTests(note(64, on: false, at: 2))
        XCTAssertTrue(v.isPlayingNote, "a one-second-old chord must not be pruned")
        XCTAssertEqual(v.synth.frequency, c4, accuracy: 1e-3, "…and C4 must take over")

        // ⛔ THE FIRST VERSION OF THIS SECOND HALF ASSERTED SOMETHING FALSE, and the arithmetic
        // caught it before the test ran: it held C for two hours, played E over it, released E,
        // and expected C back. The prune drops C exactly then — being SUPERSEDED for over a
        // minute IS the rule. The invariant that really holds is narrower, and is the one a
        // drone player relies on: a stack of ONE is never pruned, at any age.
        let drone = BioReactiveSynthVoice()
        drone.applyControllerForTests(note(60, on: true, at: 0))
        XCTAssertTrue(drone.isPlayingNote, "precondition: the drone sounds")
        drone.applyControllerForTests(note(60, on: false, at: 7200))   // two hours later
        XCTAssertFalse(drone.isPlayingNote, """
            A single key held for two hours did not release on its own note-off. The prune must \
            never touch a stack of one, and the note-off must still find its own entry there.
            """)
        XCTAssertFalse(drone.heldByControllerForTests, "…and the latch must clear with it")
    }

    /// claim 6 — the Skeptic's objection, made executable. Note-offs that never arrive must not
    /// grow an unbounded list of phantom keys.
    func testLostNoteOffsCannotGrowWithoutBound() {
        let v = BioReactiveSynthVoice()
        for n in 0..<200 {
            v.applyControllerForTests(note(UInt8(n % 128), on: true, at: TimeInterval(n)))
        }
        // ⛔ #943b — THIS ASSERTED THE LITERAL 16 BESIDE `maxHeldNotes = 16` IN THE SOURCE.
        // A second copy of a threshold the shipped type owns (`Tests/CISmoke/CLAUDE.md` §6),
        // and a live #364 trap: the source comment expressly invites changing the number
        // ("the exact number is not musical"), so raising it to 32 would have reddened a
        // correct commit. Asserted against the shipped cap instead.
        XCTAssertLessThanOrEqual(v.heldNoteCountForTests, v.maxHeldNotesForTests, """
            The held-key stack grew past its own cap on 200 note-ons with no note-off. An \
            unbounded stack of phantom keys is a WORSE failure than the silence this fix cures: \
            the voice would sound forever with nothing under a finger.
            """)
        v.panic()
        XCTAssertEqual(v.heldNoteCountForTests, 0, "panic must empty it regardless of how it filled")
    }
}
