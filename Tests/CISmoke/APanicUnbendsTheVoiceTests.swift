// APanicUnbendsTheVoiceTests.swift
// Echoel — #945 / #945b / #946 / #948 / #948b. Blocking bundle. END-TO-END BEHAVIOUR throughout, on a shipped,
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
// ⛔ HOW FAR OFF — THE ANSWER CHANGED TWICE, AND THE SECOND TIME BY FIXING THE CODE. #945
// first said "up to two semitones", reading `event.value * 2.0` as if the bend applied to the
// note being played. #945b measured the tree instead and found TWO OCTAVES: `case .pitchBend`
// fell back to note 69 (A4 = 440 Hz) on every production bend, because the ONE producer,
// `MIDIBusPublisher.onPitchBend`, writes `note: 0` unconditionally. Measured on that tree:
// −1 → 392 Hz, 0 → 440 Hz, +1 → 493.88 Hz. A centred wheel was not exempt either — value 0
// still wrote 440 Hz — so the trigger was "any bend message at all".
//
// ⭐ **#948 REMOVED THAT FALLBACK.** The base is the note the voice is SOUNDING — the wire's
// note if a future zone parser supplies one, else the top of #943's held stack, else
// `lastSoundingNote` (the note the breath took over when the last finger lifted), and only a
// voice that has played nothing at all falls through to its nominal.
//
// ⛔ #948b — THE THIRD BRANCH IS THERE BECAUSE #948's FIRST DRAFT STOPPED AT THE NOMINAL, and
// this header said "a centred wheel is a NO-OP again" while that was TRUE only with a key
// held. Lift the key and `releaseNote()` leaves the pitch alone so the body can take the note
// over (claim 3); a centred bend then snapped the drone home. The bug #948 exists to remove is
// "a bend message does something it has no business doing", and the first fix reproduced it one
// case along. Found by the mandatory reviewer. Claim 6b is that case, and it is red on BOTH
// earlier trees.
//
// ⚠️ WHAT SHRANK AND WHAT DID NOT. The BEND's own contribution is back to ±2 semitones. The
// residual `panic()` has to clear is NOT: it is the last played note plus that bend — hold C4
// with the wheel off centre and pull the cable and the voice sits ~17 semitones high. Ordinary
// playing alone already strands it, which is exactly why claim 1b drives that. Reading
// "±2 semitones" as "how far panic travels" makes the restore look nearly unnecessary, which
// is the same flattering direction this header scolds #945's first draft for.
//
// Claim 1b, which used to drive the centre case, now drives ORDINARY PLAYING: a centred bend
// no longer moves anything, so as written it would have measured nothing ABOUT CENTRED BENDS
// while staying green — a vacuous green (#488) under the file's strongest heading.
//
// ⚠️ #945b's helper took a `note:` and both call sites passed 60 — a shape production can
// never emit. A guard that drives an impossible configuration measures nothing about the
// shipped path (#367). The helper still sends `note: 0` for that reason; claim 8 is the only
// one that sets a note, and it exists to pin the branch that a zone parser will use.
//
// ⚠️ WHAT THE SCOPE ACTUALLY IS. ⛔ #945b: the first version of this paragraph said "only
// `panic()` changes" and that was false. `panic()` is what `PanicFanOut` calls for this voice
// (`releaseAllNotes()`), which `panicAllNotesOff()` fans out, which is reached from the panic
// BUTTON, from `stopEverything(reason:)` AND from `pausePlaybackKeepingSession()` — so the
// pitch resets on every Stop and on the playback-only pause too. What is genuinely unchanged
// is the NOTE-OFF path: inside one continuous take the breath still follows the last played
// note, and claim 3 pins exactly that.
// NEEDS-FOUNDER-VERIFY: MIDI-Keyboard anschließen, eine Note halten und das Pitch-Bend-Rad
// bewegen — die GEHALTENE Note muss sich um bis zu zwei Halbtöne biegen (vor #948 sprang sie
// auf A4, egal was gespielt wurde). Rad zurück in die Mitte: die Note muss exakt wieder da
// sein, wo sie war. Dann Stop drücken, "Body voice" einschalten und atmen — der Atemton muss
// auf der Grundstimmung liegen. Und die offene Frage bleibt: nach jedem
// Stop und jeder Pause springt der Atemton auf A2 zurück, auch wenn die Komposition in einer
// anderen Tonart läuft (diese Stimme kennt die Tonart nicht) — richtig so, oder soll er die
// zuletzt gespielte Note über einen Stop hinweg behalten?
//
// ⚠️ HONEST GRADING, AND IT NAMES ITS BASELINE, because this file now spans three commits and
// "the parent" means a different tree for different claims. No local Swift toolchain (§0), so
// each implementation was transcribed into Python and every assertion driven against it, with
// the expectations derived from the algebra (#442).
//
// **20 assertions.** Against the tree #948 was cut from (#946): **5 REGRESSION CATCHES** —
// claims 5, 6, 6b, 7 and 9, all of them the bend base — and **15 COUNTERWEIGHTS (#343)**.
// Against #948's own first draft, ONE catch: claim 6b. Against #945b's tree: claim 1c's two
// tuning assertions. Against the tree the file was BORN on (pre-#945, no pitch restore at
// all): the panic-restore assertions of claims 1 and 1b. Every reading is stated because
// quoting only the newest inflates what THIS commit proves, and quoting only the oldest hides
// what the file as a whole pins. **0 broken, 0 red on the worktree.**
//
// No local Swift toolchain, so all three implementations were transcribed into Python and
// every assertion driven against each. The witness is the ALGEBRA, not a file — a scratch
// script cannot be committed (`.claude/rules/context.md` §5), so citing its path would leave
// this grading resting on something no later reader can open. Re-derive by hand: nominal is
// `soundingFrequency(45)` = 110 Hz at 12-TET/A440; C4 is 261.63; a full bend is ×2^(2/12) =
// 1.1225. Pre-#948 every bend based on A4, so claim 5 read 493.88/261.63 = 1.888 (expected
// 1.1225) → red; claim 6 read 440 against 261.63 → red; claim 7 read 493.88/110 = 4.490 → red;
// claims 6b and 9 read 440 against 261.63 and against 110 → red. On #948's first draft claim
// 6b read 110 against 261.63 → red, and that one alone. Everything else is green on every
// tree that compiles the file.
//
// ⛔ THE GRADING OF THIS FILE HAS NOW BEEN WRONG THREE TIMES, each for a different reason, and
// the sequence is worth more than any of the numbers. Draft 1 GUESSED (7/2 instead of 8/1), in
// the flattering direction (#433/#464). Draft 2 counted honestly and was right for the file as
// it then stood — but that file drove a bend shape production cannot emit, so the ARITHMETIC
// was right and the SCENARIO was wrong. Draft 3 was right for both and named no baseline,
// which stops meaning anything the moment a file outlives one commit.
// **A grading is a verdict about a SCENARIO measured against a NAMED tree.** Miss any of the
// three and the number reads as more than it is.
//
// ⚠️ THE FILE COMPILES AGAINST BOTH THE PRE-#948 TREE AND #948's FIRST DRAFT — it uses no API
// either of them lacked — so all five catches are real reds there, not build errors. It does NOT compile against the pre-#945
// tree (`nominalFrequencyForTests` is new there); every assertion still HAS a meaning, said
// plainly so it cannot read as "green there" (#488).
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
    /// it measured nothing about it (#367). Since #948 a `note: 0` bend takes its base from
    /// the top of the held stack, or from the voice's nominal when nothing is held; claim 8 is
    /// the only place that sets a note, to pin the branch a zone parser will use.
    private func bend(_ value: Float) -> ControllerEvent {
        ControllerEvent(timestamp: 3, kind: .pitchBend, channel: 1, note: 0, value: value, auxCC: 0)
    }

    /// claim 1 — the whole point. After a bend, `panic()` must leave the voice on the pitch it
    /// would have with no controller attached, because the breath path inherits that pitch.
    func testPanicRestoresThePitchABendLeftBehind() {
        let v = BioReactiveSynthVoice()
        let nominal = v.nominalFrequencyForTests
        v.applyControllerForTests(note(60, on: true))
        let played = v.synth.frequency
        v.applyControllerForTests(bend(1.0))
        let bent = v.synth.frequency

        // TWO preconditions, or claim 1 is vacuous (#367). ⛔ #948: the single precondition
        // that stood here compared only against the NOMINAL, which the NOTE-ON alone already
        // satisfies — it would have stayed green even if the bend had become a no-op. The
        // first line below is the one that actually asks whether the BEND moved anything.
        XCTAssertGreaterThan(bent, played * 1.05, """
            The bend did not move the pitch off the note being played, so the restore below \
            proves nothing about bends. Re-derive: `case .pitchBend` maps value 1.0 to +2 \
            semitones, a ratio of ~1.122 against the sounding note (#948).
            """)
        XCTAssertGreaterThan(bent, nominal * 1.5, """
            The bent pitch is close to the nominal, so `panic()` restoring the nominal below \
            would be nearly indistinguishable from doing nothing.
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

    /// claim 1b — ORDINARY PLAYING, NO CONTROLLER MISCHIEF AT ALL: play a note, lift it,
    /// Stop. The breath tone must come home to the nominal.
    ///
    /// ⛔ #948 REPLACED THIS CLAIM'S SCENARIO, and the reason is the point. #945b drove a
    /// CENTRED bend here, because on that tree a wheel springing back to centre still wrote
    /// A4 — so "any bend message at all" was the trigger. #948 made a centred bend a no-op,
    /// which is what "centred" means; the old scenario therefore measured nothing ABOUT
    /// CENTRED BENDS — its assertions would still have been green and still meaningful about
    /// panic restoring the nominal, which is precisely the shape of half-empty precondition
    /// the ⛔ inside claim 1 diagnoses. A vacuous green (#488) under the file's strongest
    /// heading is worse than no claim. What is left
    /// worth pinning is the plainer half: after a take, a Stop puts the drone back on its own
    /// pitch, so the next breath is in tune with the composition rather than with whatever
    /// key was pressed last.
    func testPanicRestoresTheNominalAfterOrdinaryPlayingToo() {
        let v = BioReactiveSynthVoice()
        let nominal = v.nominalFrequencyForTests
        v.applyControllerForTests(note(60, on: true))

        XCTAssertGreaterThan(v.synth.frequency, nominal * 1.5, """
            precondition: the note played is far enough from the nominal that restoring it \
            below is distinguishable from doing nothing (#367).
            """)

        v.applyControllerForTests(note(60, on: false))
        v.panic()

        XCTAssertEqual(v.synth.frequency, nominal, accuracy: 1e-3, """
            `panic()` did not restore the nominal after ordinary playing. No bend is involved \
            here: `playNote(frequency:)` writes `synth.frequency` on every note-on, and the \
            frequency-less breath `playNote()` inherits whatever is left there (claim 2). \
            Without this line the drone follows the last key pressed for the rest of the \
            session, across every Stop.
            """)
    }

    /// claim 1c (#946) — THE NOMINAL MUST GO THROUGH THE VOICE'S OWN TUNING, and until #946 it
    /// did not. `EchoelStudioView` fans BOTH tuning axes into this voice — `setTuningCents`
    /// (the tone system's per-pitch-class table, relative to the key root) at `:4448` and
    /// `setTuning(a4Hz:)` (concert pitch) at `:4480` — and then the voice's own resting pitch
    /// bypassed both, because it was `EchoelDDSP.frequency`'s raw struct default. With a maqām
    /// or just-intonation table selected, or A4 moved to 432, every played note was retuned and
    /// the breath drone alone was not. Same defect family as #114's concert-pitch gap and
    /// #312's felt sub, one voice further along, and the comments around those two fan-out
    /// sites say so themselves.
    ///
    /// ⚠️ BIT-IDENTICAL UNDER THE DEFAULTS, which is why this is a correctness fix and not a
    /// voicing change: `soundingFrequency(forMIDINote: 45)` at 12-TET/A440 is
    /// `440 * 2^(-24/12)` = **exactly** 110.0, the shipped default. It only differs where the
    /// user has already asked for a different tuning.
    func testTheRestingPitchFollowsBothTuningAxes() {
        let plain = BioReactiveSynthVoice()
        let shipped = EchoelDDSP().frequency   // every parameter defaults; nothing to mistype

        // 1c-i — the pair this derivation rests on: note 45 IS the note the shipped default
        // sounds. If `EchoelDDSP.frequency`'s default moves, this goes red rather than the
        // drone silently drifting a semitone from every other voice.
        XCTAssertEqual(plain.nominalFrequencyForTests, shipped, accuracy: 1e-3, """
            The voice's resting pitch is no longer the pitch `EchoelDDSP` ships. Either the \
            struct default moved or `nominalMIDINote` did; they are one pair and must move \
            together, or the breath drone lands a step away from every played note.
            """)

        // 1c-ii — concert pitch reaches it. THE REGRESSION.
        let retuned = BioReactiveSynthVoice()
        retuned.setTuning(a4Hz: 432)
        XCTAssertLessThan(retuned.nominalFrequencyForTests, shipped - 1, """
            Moving concert pitch to 432 Hz left the breath drone at the 440-based pitch. \
            `EchoelStudioView.applyConcertPitch` fans `setTuning(a4Hz:)` into THIS voice on \
            purpose; a resting pitch that ignores it is the #114 gap one voice further along.
            """)

        // 1c-iii — and the tone system reaches it. Also THE REGRESSION. A table that lowers
        // pitch class A (note 45 % 12 == 9) must move the drone with it.
        var cents = [Float](repeating: 0, count: 12)
        cents[9] = -50
        let bent = BioReactiveSynthVoice()
        bent.setTuningCents(cents)
        XCTAssertLessThan(bent.nominalFrequencyForTests, shipped - 1, """
            A tone-system table that retunes pitch class A left the breath drone at 12-TET. \
            `applyTuning()` fans `setTuningCents` into this voice; with a maqām or just table \
            selected every played note moved and the drone alone did not.
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

    /// claim 5 (#948) — **THE FIX ITSELF.** A bend bends the note under your finger. Before
    /// #948 the base was A4 on every production bend, so holding C4 and pushing the wheel
    /// jumped the voice to 493.88 Hz — nearly two octaves up — instead of to a note a
    /// semitone-and-a-bit above C4.
    ///
    /// The assertion is a RATIO against a frequency read back from the voice itself, so it
    /// survives any tuning table and any concert pitch (#364) and pins no Hz literal (#416).
    func testABendBendsTheNoteThatIsSounding() {
        let v = BioReactiveSynthVoice()
        let sounding = v.soundingFrequency(forMIDINote: 60)
        v.applyControllerForTests(note(60, on: true))
        v.applyControllerForTests(bend(1.0))

        XCTAssertEqual(v.synth.frequency / sounding, powf(2, 2.0 / 12), accuracy: 1e-4, """
            A full bend did not land two semitones above the note being held. On the pre-#948 \
            tree this ratio was ~1.888 (440 Hz base against C4) rather than ~1.122, because \
            `case .pitchBend` fell back to note 69 whenever the event carried no note — which \
            the one production producer, `MIDIBusPublisher.onPitchBend`, always does.
            """)
    }

    /// claim 6 (#948) — a CENTRED wheel changes nothing. This is the message every keyboard
    /// sends when a finger leaves the wheel, so on the pre-#948 tree it was the single most
    /// common way to detune the voice: value 0 wrote 440 Hz regardless of what was playing.
    func testACentredBendIsANoOp() {
        let v = BioReactiveSynthVoice()
        v.applyControllerForTests(note(60, on: true))
        let played = v.synth.frequency
        v.applyControllerForTests(bend(0))

        XCTAssertEqual(v.synth.frequency, played, accuracy: 1e-3, """
            A bend at CENTRE moved the pitch. Releasing the wheel sends exactly this message, \
            so an ordinary player would hear the held note jump for no reason. Re-derive: \
            value 0 → 0 semitones → the base unchanged, and since #948 the base is the note \
            being held. Claim 6b drives the harder half of this, after the key is lifted.
            """)
    }

    /// claim 7 (#948) — with NO key down, the bend works from THIS VOICE'S nominal, not from
    /// A4. Since #948b this is the LAST branch, reached only by a voice that has played
    /// nothing at all; its home is the resting pitch claim 1c pinned to both tuning axes.
    ///
    /// ⚠️ THIS PINS TODAY'S ANSWER, NOT A LAW (#364), and it is the assertion most exposed to
    /// this file's own open founder question. If the founder answers that the breath tone
    /// should keep the last played note across a Stop, branch 4 changes and this claim is what
    /// must change in the same commit — not an obstacle to it.
    func testABendWithNoKeyDownWorksFromTheVoicesOwnNominal() {
        let v = BioReactiveSynthVoice()
        let nominal = v.nominalFrequencyForTests
        v.applyControllerForTests(bend(1.0))

        XCTAssertEqual(v.synth.frequency / nominal, powf(2, 2.0 / 12), accuracy: 1e-4, """
            A bend with nothing held did not build on the voice's nominal. On the pre-#948 \
            tree this ratio was ~4.49 — the A4 fallback against a nominal two octaves below \
            it — which is the two-octave strand this file's header describes.
            """)
    }


    /// claim 6b (#948b) — **THE CASE #948's FIRST DRAFT GOT WRONG, and the reviewer found it,
    /// not a guard.** Lift the key, then let the wheel spring back. `releaseNote()` never
    /// touches `frequency`, so the voice is still sounding the note the body just took over
    /// (claim 3). A centred bend must leave it exactly there.
    ///
    /// #948's first version based a keyless bend on `nominalFrequency`, so this snapped the
    /// drone home — a bend message doing something it has no business doing, which is the very
    /// defect #948 exists to remove. RED on the pre-#948 tree (440 Hz) AND on #948's own first
    /// draft (the nominal); green only with `lastSoundingNote` as branch 3.
    func testACentredBendAfterTheKeyIsLiftedIsAlsoANoOp() {
        let v = BioReactiveSynthVoice()
        v.applyControllerForTests(note(60, on: true))
        v.applyControllerForTests(note(60, on: false))
        let takenOver = v.synth.frequency
        v.applyControllerForTests(bend(0))

        XCTAssertEqual(v.synth.frequency, takenOver, accuracy: 1e-3, """
            A centred bend moved the pitch after the key was lifted. That is the state the \
            breath tone lives in — the body has taken the note over — and releasing the wheel \
            is not a gesture, it is what a finger leaving it sends. Re-derive: `case \
            .pitchBend` branch 3 is `lastSoundingNote`; without it the base falls through to \
            the nominal and the drone is yanked home.
            """)
    }

    /// claim 9 (#948b) — and `panic()` clears that latch, so the memory of a played note does
    /// not outlive the thing panic exists to end. Without the clear, a bend arriving after a
    /// Stop would rebuild the pitch panic had just put back.
    func testPanicClearsTheSoundingNoteMemoryToo() {
        let v = BioReactiveSynthVoice()
        let nominal = v.nominalFrequencyForTests
        v.applyControllerForTests(note(60, on: true))
        v.applyControllerForTests(note(60, on: false))
        v.panic()
        v.applyControllerForTests(bend(0))

        XCTAssertEqual(v.synth.frequency, nominal, accuracy: 1e-3, """
            A bend after a panic rebuilt the pre-panic pitch. `lastSoundingNote` is controller \
            state exactly like the three latches claim 4 covers; panic's contract is that \
            nothing a controller left behind survives it, and it restores the nominal on the \
            same line.
            """)
    }

    /// claim 8 (COUNTERWEIGHT, #948) — the wire still wins when it says something. Nothing
    /// produces a bend with a note today, but a zone-aware parser (RPN 6,6, still absent) will:
    /// an MPE member channel's bend belongs to ITS note, not to whatever the mono stack last
    /// saw. Green on BOTH trees — this branch is the one shape #948 did not change, and it is
    /// asserted so a later "simplify to the held stack" edit cannot quietly drop it.
    func testAnExplicitNoteOnTheEventStillWinsOverTheHeldStack() {
        let v = BioReactiveSynthVoice()
        let e3 = v.soundingFrequency(forMIDINote: 52)
        v.applyControllerForTests(note(60, on: true))
        v.applyControllerForTests(
            ControllerEvent(timestamp: 3, kind: .pitchBend, channel: 1,
                            note: 52, value: 0, auxCC: 0))

        XCTAssertEqual(v.synth.frequency, e3, accuracy: 1e-3, """
            A bend that named its own note was based on the sounding note instead. Today's \
            order puts the event's note first: explicit information from the wire outranks \
            inference, and a member channel's bend belongs to ITS note.

            ⚠️ THE TRADE, NOT AN INSTRUCTION (#364). On ONE monophonic voice this yanks the \
            sounding pitch to a note that is not sounding — which is what this test drives. A \
            zone-aware slice could reasonably decide a mono voice should IGNORE bends for \
            non-sounding notes; if it does, this claim changes with it.
            """)
    }
}
