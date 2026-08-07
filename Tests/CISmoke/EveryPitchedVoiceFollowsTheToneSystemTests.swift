// EveryPitchedVoiceFollowsTheToneSystemTests.swift
// Echoel — #338. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ THE DEFECT THIS PINS: `applyTuning()` fanned the selected tone system's retune table to
// FOUR primary voices (synth, touch, lead, sub) and stopped. Two live paths were left on plain
// 12-TET while everything else moved — the founder's "Bass teilweise nicht in tune" (#312), same
// shape, two levels further out:
//   · the LANE RACK, which routes every multi-roll lane note to one of its poly/sub/bio units.
//     `feature.multiRoll` is REGISTERED ON (`EchoelmusicApp`), so the poly/sub half is a default
//     install. (The BIO units also need `voiceKindRouting` — likewise registered ON — and a track
//     the user set to `TrackInstrument.bioVoice`. Two flags and a user choice, not one flag; the
//     first draft of this header said one, which overstates the reach of the rack's bio half.)
//   · the GLOBAL `bioVoice`, whose external-MIDI note-on path (`apply(controller:)`) is not
//     gated by `isArmed` — the performer always leads — and whose drain is installed at launch
//     by `bioVoice.start(subscribing: bus)`.
//
// ⛔ THE JUSTIFICATION THAT KEPT IT ALIVE, written down so it cannot come back. The comment in
// `applyTuning()` read: "THIS VIEW's `bioVoice` instance never sounds — nothing calls `arm()`
// on it (task #277)". The `arm()` fact is TRUE; the conclusion does not follow. `arm()` gates
// ONLY the BREATH trigger (`consumeBioEventsIfFresh`'s `guard isArmed, …`). That is the SECOND
// time in this one function that something checkable stood in for a reason about behaviour —
// API surface (which covered the sub, this voice and the rack in one sentence), and this latch.
// ⛔ The first draft said THIRD and counted "API surface for the LEAD" as its own instance. That
// is false and the quoted excuse refutes it: "exists on exactly three reachable objects (all
// `PolySynthVoice`)" — `leadSynth` IS a `PolySynthVoice?`, so it was inside that set, and
// `PolySynthVoice.setTuningCents` has always existed. The lead was an omission with no stated
// reason at all. Corrected here and in both source files, because a session that greps for the
// lead's supposed excuse finds nothing and then discounts the half that is true.
// The same wrong conclusion was ALSO load-bearing in `EchoelDDSP.swift`, where it read "a voice
// that CANNOT BE HEARD"; corrected there in the same commit.
//
// WHAT EACH HALF CAN AND CANNOT SHOW:
//   · the numeric tests drive the REAL shipped mapping (`BioReactiveSynthVoice.soundingFrequency`)
//     and are a true behavioural check;
//   · ⛔ BUT NOT OF BIT-IDENTITY WITH THE PRE-#338 EXPRESSION, which the first draft claimed here
//     and in the `soundingFrequency` doc. The field defaults to an all-zero table, so BOTH sides
//     of that comparison already run the new `* exp2f(0)` path — `XCTAssertEqual(before, after)`
//     is true by construction and could not have detected a change. Bit-identity is an ARGUMENT,
//     not a measurement this file makes: `exp2f(+0.0)` is exactly `1.0` (an exact libm case) and
//     IEEE-754 multiplication by `1.0` is exact for every finite value, with no FMA contraction
//     because there is no add. What the file DOES measure is that the default path returns
//     EXACTLY the 12-TET frequency (`==`, not `accuracy:`) — which is the premise that argument
//     needs, and is why the fan is safe to apply unconditionally;
//   · the fan tests read SOURCE TEXT, because `applyTuning()` is a private method on a SwiftUI
//     view this bundle cannot build. Weaker than behavioural, stronger than nothing, and it is
//     the link that was actually broken. Same shape as `SubBassFollowsTheToneSystemTests`.
//   · NOTHING here shows that a rack lane or a MIDI keyboard sounds in tune ON A DEVICE. That is
//     a listen, with a non-12-TET system selected, and it stays open.
//
// ⛔ HONEST GRADING, because the flattering version would be "seven guards, all regressions".
// THIS FILE CANNOT BE GRADED AGAINST THE PARENT TREE AT ALL: every behavioural test calls
// `BioReactiveSynthVoice.setTuningCents`, which the same commit creates, so the bundle does not
// compile there and NO assertion has a verdict. That is the #464 situation, said plainly rather
// than dressed up. What IS established — by transcribing `SourceText.codeOnly` and running it
// against `git show HEAD:` rather than by a test run — is that NINE of the twelve source-text
// needles WOULD be red on the parent: the two studio fans, the three rack-family fans, the two
// `attachAll` seeds and the two setter latches. `LaneVoiceRack` has no `setTuningCents` at all
// there, and `attachAll` seeds neither axis.
// `testTheArmLatchGatesOnlyTheBreathPathNotMIDI`'s three needles are GREEN on both sides by
// construction: it is a PREMISE anchor (#367), not a regression, and it says so where it stands.

import Foundation
import XCTest
@testable import Echoelmusic

// `@MainActor` on the case, not per test: `BioReactiveSynthVoice` is `@MainActor @Observable`,
// so constructing one from a nonisolated body is a Swift 6 error.
@MainActor
final class EveryPitchedVoiceFollowsTheToneSystemTests: XCTestCase {

    private static let twelveTET = [Float](repeating: 0, count: 12)

    // MARK: - Behaviour: the bio voice's own mapping

    /// The safety property the unconditional fan rests on. 12-TET is the DEFAULT tone system and
    /// its table is all zeros, so if an all-zero table were not exactly a no-op, #338 would have
    /// retuned every existing session.
    ///
    /// ⚠️ WHAT THIS CAN AND CANNOT SHOW — the first draft got it wrong and claimed bit-identity
    /// with the PRE-#338 expression. It cannot: `tuningCents` already defaults to all zeros, so
    /// `before` and `after` BOTH traverse the new `* exp2f(0)` factor and their equality holds by
    /// construction. What it does show is the premise the bit-identity ARGUMENT needs — that the
    /// default path lands on EXACTLY the 12-TET frequency, asserted with `==` and not
    /// `accuracy:`, which the first draft also got wrong (it allowed ±1 mHz while calling itself
    /// bit-identical). From there the argument is arithmetic, not measurement: `exp2f(+0.0)` is
    /// exactly `1.0` and IEEE-754 multiplication by `1.0` is exact for every finite value.
    func testTwelveTETLeavesTheBioVoiceExactlyWhereItWas() {
        let voice = BioReactiveSynthVoice()
        let before = voice.soundingFrequency(forMIDINote: 69)
        voice.setTuningCents(Self.twelveTET)
        let after = voice.soundingFrequency(forMIDINote: 69)

        XCTAssertEqual(before, 440, """
            A4 is no longer EXACTLY 440 Hz on the default (12-TET, A=440) path. Exact, not \
            "close": the whole reason #338 could be fanned unconditionally is that the retune \
            factor is exactly 1 for an all-zero table.
            """)
        XCTAssertEqual(after, 440, """
            Explicitly installing the 12-TET table moved A4 off exactly 440 Hz. `applyTuning()` \
            pushes this table on every launch with the default tone system selected, so this is \
            the value a first-run user hears.
            """)
        XCTAssertEqual(before, after, """
            An all-zero (12-TET) table moved the bio voice's pitch. It must not: 12-TET is the \
            shipped default, so the #338 fan is only safe to apply unconditionally as long as \
            zeros are exactly a no-op.
            """)
    }

    /// The whole point of #338: a deviating degree must actually move the voice, by exactly the
    /// amount the tone system asks for. −300 is the shipped library's real maximum (Hirajōshi's
    /// leading tone, pinned by `SubBassFollowsTheToneSystemTests`); −50 is a mid-range case.
    func testADeviatingPitchClassMovesTheBioVoiceByExactlyThatMuch() {
        for expected in [Float(-50), Float(-300), Float(+21.5)] {
            let voice = BioReactiveSynthVoice()
            let plain = voice.soundingFrequency(forMIDINote: 69)
            var cents = Self.twelveTET
            cents[9] = expected                 // pitch class A — the class of MIDI 69
            voice.setTuningCents(cents)
            let moved = 1200 * log2(Double(voice.soundingFrequency(forMIDINote: 69)) / Double(plain))

            XCTAssertEqual(moved, Double(expected), accuracy: 0.05, """
                A \(expected)-cent degree moved the bio voice by \(moved) cents instead. This is \
                the beating a performer hears when the voice under their fingers follows a \
                different intonation from the pad it plays against.
                """)
        }
    }

    /// The table is read BY PITCH CLASS, not by note — the same octave must take the same
    /// deviation, or the retune is a per-note offset masquerading as a tone system.
    ///
    /// ⛔ THE OCTAVE RATIOS ALONE CANNOT FAIL FOR THAT REASON (#367), and the first draft asserted
    /// only those. A3/A4/A5 all land on index 9 under ANY `% 12`-style indexing, correct or not —
    /// and they stay exact octaves under a body that ignores `tuningCents` completely. So each
    /// octave is ALSO checked against the DEVIATED frequency, and a NEIGHBOURING pitch class is
    /// left at zero and checked to have stayed put: together those bite, the ratios alone do not.
    func testTheDeviationFollowsThePitchClassAcrossOctaves() {
        let voice = BioReactiveSynthVoice()
        var cents = Self.twelveTET
        cents[9] = -50                          // pitch class A only; A♯ (index 10) stays 0
        voice.setTuningCents(cents)

        let a4 = Double(voice.soundingFrequency(forMIDINote: 69))
        let a3 = Double(voice.soundingFrequency(forMIDINote: 57))
        let a5 = Double(voice.soundingFrequency(forMIDINote: 81))
        let expectedA4 = 440.0 * pow(2.0, -50.0 / 1200.0)

        XCTAssertEqual(a4, expectedA4, accuracy: 1e-3, """
            A4 did not take pitch class A's −50 cents at all — so the octave ratios below would \
            pass on a body that ignores the table entirely. This assertion is what makes them \
            mean something.
            """)
        XCTAssertEqual(a4 / a3, 2.0, accuracy: 1e-4, """
            A3 and A4 no longer sit an exact octave apart under a retuned pitch class A. The \
            deviation is indexed by pitch class precisely so octaves stay octaves.
            """)
        XCTAssertEqual(a5 / a4, 2.0, accuracy: 1e-4, "A4→A5 is no longer an exact octave.")

        let aSharp4 = Double(voice.soundingFrequency(forMIDINote: 70))
        XCTAssertEqual(aSharp4, 440.0 * pow(2.0, 1.0 / 12.0), accuracy: 1e-3, """
            A♯4 moved although its pitch class was left at 0 cents. The deviation is leaking \
            across pitch classes — a per-note or per-octave offset, not a tone system.
            """)
    }

    /// Concert pitch and tone system are INDEPENDENT axes and must compose, not overwrite. This is
    /// the pairing that #114 (Kammerton) and #312 (tone system) each found broken separately.
    func testTheRetuneComposesWithConcertPitchOnTheBioVoice() {
        let voice = BioReactiveSynthVoice()
        var cents = Self.twelveTET
        cents[9] = -50
        voice.setTuning(a4Hz: 432)
        voice.setTuningCents(cents)

        let expected = 432.0 * pow(2.0, -50.0 / 1200.0)
        XCTAssertEqual(Double(voice.soundingFrequency(forMIDINote: 69)), expected, accuracy: 0.01, """
            A=432 and a −50-cent degree did not compose on the bio voice. They are two separate \
            tunings — the Kammerton moves the whole instrument, the tone system moves one degree \
            within it — and applying only one of them is out of tune with everything else.
            """)
    }

    /// The setter must reject a malformed table rather than partially apply it or poison the
    /// mapping. A wrong SIZE would retune the wrong pitch classes; a NaN entry would make
    /// `soundingFrequency` return NaN, which is the stuck-silent-oscillator failure class the
    /// `setTuning` guard beside it already exists for.
    func testTheSetterKeepsTheLastGoodTuningRatherThanApplyingRubbish() {
        let voice = BioReactiveSynthVoice()
        var good = Self.twelveTET
        good[9] = -50
        voice.setTuningCents(good)
        let reference = voice.soundingFrequency(forMIDINote: 69)

        voice.setTuningCents([0, 0, 0])
        XCTAssertEqual(voice.soundingFrequency(forMIDINote: 69), reference, """
            A 3-entry table was accepted, so the last good tuning was lost. Anything but exactly \
            12 entries must leave the voice on the tuning it already had.
            """)

        var poisoned = Self.twelveTET
        poisoned[9] = .nan
        voice.setTuningCents(poisoned)
        XCTAssertEqual(voice.soundingFrequency(forMIDINote: 69), reference, """
            A NaN cent value was accepted. `exp2f(NaN)` is NaN, so the oscillator frequency would \
            become NaN and the voice would go permanently silent — the exact failure the sibling \
            `setTuning(a4Hz:)` guard was written for.
            """)
        XCTAssertTrue(voice.soundingFrequency(forMIDINote: 69).isFinite,
                      "The sounding frequency stopped being finite after a rubbish table.")
    }

    // MARK: - Wiring: does anything actually hand the table over?

    /// The link that was actually broken, half one: the studio must fan the table to BOTH voices
    /// it was skipping. A correct mapping nobody calls is the same defect with more steps.
    func testTheStudioFansTheToneSystemToTheBioVoiceAndTheRack() throws {
        let code = SourceText.codeOnly(try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift"))

        XCTAssertTrue(code.contains("bioVoice.setTuningCents("), """
            `applyTuning()` no longer hands the tone system's retune table to the global bio \
            voice. It sounds on external MIDI note-on — `apply(controller:)` is NOT gated by \
            `isArmed`, which gates only the breath trigger — so without this fan a plugged-in \
            keyboard plays 12-TET against a retuned instrument. That "arm() has no caller so it \
            never sounds" reasoning is exactly what #338 removed; do not restore it.
            """)
        XCTAssertTrue(code.contains("laneVoiceRack.setTuningCents("), """
            `applyTuning()` no longer hands the tone system's retune table to the lane rack. \
            `feature.multiRoll` is registered ON, so a secondary lane sounds on a default install \
            and would play plain 12-TET against the primary voices — up to 300 cents apart in \
            Hirajōshi. This is #338; do not remove the fan without removing the rack.
            """)
    }

    /// Half two, and the one a "tidy this up" pass would break: the rack fan must reach ALL THREE
    /// voice families it owns. Poly and sub alone would leave the bio units — the ones a track set
    /// to `TrackInstrument.bioVoice` plays — silently on 12-TET, which is the #338 defect surviving
    /// inside its own fix. Deliberately the same shape as the `setTuning(a4Hz:)` fan directly above
    /// it in the source: two ways to push a tuning is how the two axes drifted apart in the first
    /// place (#416).
    func testTheRackFanReachesPolySubAndBioAlike() throws {
        let code = SourceText.codeOnly(try source("Sources/Echoelmusic/Sequencer/LaneVoiceRack.swift"))
        guard let start = code.range(of: "public func setTuningCents(") else {
            return XCTFail("`LaneVoiceRack.setTuningCents` is gone — the rack has lost the tone-system axis entirely (#338).")
        }
        let body = code[start.lowerBound...].prefix(600)

        // ⛔ ANCHOR ON THE CALL, NOT THE LOOP HEADER. The first draft matched `" in voices {"`,
        // which `for v in voices { v.setInsert(fx) }` satisfies — and the sibling
        // `setTuning(a4Hz:)` fans to the SAME three families with byte-identical headers, so a
        // future reordering that put it inside this window would have kept the test green over a
        // gutted body. The receiver letters are part of the needle for the same reason (#408).
        for (receiver, family) in [("v", "voices"), ("s", "subs"), ("b", "bios")] {
            XCTAssertTrue(body.contains("in \(family) { \(receiver).setTuningCents(cents) }"), """
                `LaneVoiceRack.setTuningCents` no longer fans the TABLE to `\(family)`. All three \
                families are pitched and `noteOn` routes lane notes to all three, so one omitted \
                family is one lane playing 12-TET against the others — #338 surviving inside its \
                own fix. Its sibling `setTuning(a4Hz:)` fans to the same three; keep them \
                identical in shape.
                """)
        }
    }

    /// The half a source scan for the fan CANNOT see, and the one both reviewers found: the rack
    /// does not exist yet when `applyTuning()` runs. `EchoelStudioView.onAppear` is the first
    /// SYNCHRONOUS appear pass; `LaneVoiceRack.attachAll` runs later from `EchoelmusicApp`'s async
    /// startup task (that file states the ordering in its own words, twice). So the fan iterates
    /// three empty arrays, and without a latch every multi-roll lane wakes up in plain 12-TET
    /// until the user next touches the Key or Tuning picker — verbatim the defect #338 closes.
    ///
    /// Both axes: the A4 fan has had the identical exposure since it was written. Seeding only
    /// the tone system would leave the rack's two tuning axes able to disagree at launch.
    func testTheRackRemembersItsTuningUntilItsVoicesExist() throws {
        let code = SourceText.codeOnly(try source("Sources/Echoelmusic/Sequencer/LaneVoiceRack.swift"))
        guard let attach = code.range(of: "public func attachAll(to audioEngine: AudioEngine)") else {
            return XCTFail("`LaneVoiceRack.attachAll` is gone — the rack's voices are created somewhere else now, and the launch-order reasoning below needs redoing.")
        }
        let attachBody = code[attach.lowerBound...].prefix(2400)

        XCTAssertTrue(attachBody.contains("setTuningCents(tuningCents)"), """
            `attachAll` no longer seeds the freshly-created voices with the latched tone system. \
            The fan in `applyTuning()` runs BEFORE this — the arrays are empty then — so without \
            this line the rack silently plays 12-TET for the whole session after a relaunch.
            """)
        XCTAssertTrue(attachBody.contains("setTuning(a4Hz: tuningA4Hz)"), """
            `attachAll` no longer seeds the latched CONCERT PITCH. Same launch-ordering hole as \
            the tone system, and seeding only one axis lets the rack's two tunings disagree.
            """)

        for setter in ["public func setTuning(a4Hz: Double)", "public func setTuningCents(_ cents: [Float])"] {
            guard let r = code.range(of: setter) else {
                return XCTFail("`\(setter)` is gone from LaneVoiceRack — the latch has lost a writer.")
            }
            let stored = setter.contains("a4Hz") ? "tuningA4Hz = a4Hz" : "tuningCents = cents"
            XCTAssertTrue(code[r.lowerBound...].prefix(400).contains(stored), """
                `\(setter)` fans to the voices but no longer LATCHES the value. A setter that \
                only fans is a no-op whenever it is called before `attachAll` — which is exactly \
                when `applyTuning()`/`applyConcertPitch(_:)` call it at launch.
                """)
        }
    }

    /// The premise the whole slice rests on, checked rather than assumed (#367): the breath latch
    /// really does gate ONLY the breath path. If a future change put `isArmed` in front of the
    /// controller path too, the "it sounds on MIDI today" reasoning above would stop being true
    /// and this file's justification would need rewriting rather than silently ageing.
    func testTheArmLatchGatesOnlyTheBreathPathNotMIDI() throws {
        let code = SourceText.codeOnly(try source("Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift"))

        // ⛔ SCOPED, NOT COUNTED. The first draft asserted that the literal `"guard isArmed"`
        // appears exactly once file-wide. That reddens the blocking bundle for a benign clause
        // reorder (`guard breathPlayEnabled, isArmed, …`) or a `guard self.isArmed`, with zero
        // change in safety — the #364 way to get a guard deleted. What the slice actually claims
        // is a statement about WHERE the latch is read, so read the two function bodies.
        guard let breath = code.range(of: "func consumeBioEventsIfFresh") else {
            return XCTFail("`consumeBioEventsIfFresh` is gone — the breath path this premise is about no longer exists.")
        }
        XCTAssertTrue(code[breath.lowerBound...].prefix(600).contains("isArmed"), """
            The breath path no longer reads `isArmed`. #338's justification is that the latch \
            gates THIS path and only this one; if the gate has moved, the justification must be \
            rewritten rather than left to age.
            """)

        guard let midi = code.range(of: "private func apply(controller event: ControllerEvent)") else {
            return XCTFail("`apply(controller:)` is gone — the external-MIDI path this slice reasons about no longer exists.")
        }
        let midiBody = code[midi.lowerBound...].prefix(900)
        XCTAssertFalse(midiBody.contains("isArmed"), """
            The external-MIDI path has gained an `isArmed` gate. #338's reasoning — "the global \
            bio voice sounds today, because the MIDI path is NOT gated; the performer always \
            leads" — is a claim about exactly that. Revisit the fan's justification; do not just \
            delete this assertion.
            """)
        XCTAssertTrue(midiBody.contains("soundingFrequency(forMIDINote:"), """
            The external-MIDI note-on no longer resolves its pitch through `soundingFrequency`, \
            which is where both tuning axes live. A MIDI note that computes its own Hz would \
            bypass the Kammerton (#114) and the tone system (#338) at once.
            """)
    }

    // MARK: - helpers

    private func source(_ path: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        // Gate on the DIRECTORY, not on each file: a per-file `fileExists` would turn a genuine
        // deletion into a green skip, which is the catastrophe this bundle exists against (#472).
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than reporting \
                a green this file did not earn.
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
