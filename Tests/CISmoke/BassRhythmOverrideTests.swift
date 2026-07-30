// BassRhythmOverrideTests.swift
// Echoel — the bass rhythm override is an OVERRIDE, in the BLOCKING bundle (#253 A3).
//
// ⭐ THE ONE TEST THAT MATTERS HERE IS THE FIRST ONE, and it is not hygiene. The founder curated
// these genres by ear TWICE (#81, #125: "bei den Genres kommt erst eine individuelle Variation und
// dann klingt plötzlich alles gleich"). A rhythm character that leaked into the default path would
// re-flatten every bassline onto one groove — the exact defect those two tasks fixed, and one nobody
// would see in a diff. So `bassRhythm: nil` must produce a BYTE-IDENTICAL take, and that is asserted
// against the whole note list rather than a summary of it.
//
// The rest guards what the panel actually promises: the character changes the bass, the section
// downbeat survives every character, notes never overlap each other, and the rotation `hypnotic` is
// named after really happens.
//
// ⚠️ EVERY TEST BELOW DEPENDS ON THE WALKING PATH BEING REACHED, and that gate has THREE parts, not
// one: `appendBass` only consults `rhythm` when `!sustained` AND `motion > 0.32`
// (`busy · 0.7 + (1 − calm) · 0.4` — so a SETTLED body ignores the Picker on every genre) AND
// `len >= 4`. The `input(_:)` body below is chosen to clear all three; if a future change to the
// arousal maths drops it under the threshold these tests do not silently pass, because
// `testAtLeastOneCharacterChangesTheBass` fails the moment `rhythm` stops being read at all.
// It also uses `BioComposer.Input`'s DEFAULTS for the H-switches (voiceLead / humanize /
// suggestJourney), where the shipping call site in `EchoelStudioView` sets all three — deliberately,
// so a failure here points at the rhythm binding and not at a change in those.

import XCTest
@testable import Echoelmusic

final class BassRhythmOverrideTests: XCTestCase {

    /// A take with drive in it, so the WALKING bass path is the one under test: a held drone or a
    /// short section returns one sustained root and has no walk for a rhythm to place. `.disco`
    /// with a busy body is the reachable combination: it is NOT in `MusicStyle.sustainedFlächen`
    /// and it reaches `composeHarmonic`'s default branch, where `dubTechno`/`trap` take hand-built
    /// paths and every sustained genre holds a root by profile.
    private func input(_ rhythm: RoleRhythm.Character?) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: 132, hrvNormalized: 0.3, coherence: 0.3,
                          breathPhase: 0.25, breathDepth: 0.7,
                          key: MusicalKey(root: 0, scale: .minor),
                          style: .disco, mode: .studioLocked, lockedTempo: 132,
                          seed: 0xA3B0, bassRhythm: rhythm)
    }

    private func bass(_ notes: [Note]) -> [Note] {
        notes.filter { $0.role == .bass }
    }

    /// ⭐ THE GOLDEN LAW. Same shape as `voiceLeading` / `humanize` / `suggestJourney` before it:
    /// the switch OFF must be indistinguishable from the switch not existing.
    ///
    /// Compared as full note lists, not counts: a rhythm binding that happened to emit the same
    /// NUMBER of notes at different steps, lengths or velocities would pass a count assertion and
    /// still have changed every genre's bassline. The default path must also not touch the RNG —
    /// which this catches for free, because a stolen draw would shift every later note's pitch and
    /// velocity in the whole take, not only the bass.
    func testTheDefaultTakeIsByteIdenticalToTheTakeBeforeThisFeatureExisted() {
        let plain = BioComposer.compose(input(nil))
        let explicitDefault = BioComposer.compose(
            BioComposer.Input(heartRateBPM: 132, hrvNormalized: 0.3, coherence: 0.3,
                              breathPhase: 0.25, breathDepth: 0.7,
                              key: MusicalKey(root: 0, scale: .minor),
                              style: .disco, mode: .studioLocked, lockedTempo: 132,
                              seed: 0xA3B0))
        XCTAssertEqual(plain.notes.count, explicitDefault.notes.count)
        XCTAssertEqual(plain.notes.map(\.startStep), explicitDefault.notes.map(\.startStep))
        XCTAssertEqual(plain.notes.map(\.pitch), explicitDefault.notes.map(\.pitch))
        XCTAssertEqual(plain.notes.map(\.lengthSteps), explicitDefault.notes.map(\.lengthSteps))
        XCTAssertEqual(plain.notes.map(\.velocity), explicitDefault.notes.map(\.velocity))
        XCTAssertEqual(plain.suggestedTempo, explicitDefault.suggestedTempo)
    }

    /// The row is not decoration: at least one character must audibly move the bass. Deliberately
    /// "at least one" and not "all six" — whether a given genre's `motion` reaches the walking path
    /// at this body state is the composer's business, and pinning all six here would be pinning the
    /// genre's arousal maths rather than this feature.
    func testAtLeastOneCharacterChangesTheBass() {
        let reference = bass(BioComposer.compose(input(nil)).notes)
        XCTAssertFalse(reference.isEmpty, "no bass at all — this take cannot test a bass rhythm")
        let changed = RoleRhythm.Character.allCases.contains { character in
            let overridden = bass(BioComposer.compose(input(character)).notes)
            return overridden.map(\.startStep) != reference.map(\.startStep)
                || overridden.map(\.lengthSteps) != reference.map(\.lengthSteps)
                || overridden.map(\.velocity) != reference.map(\.velocity)
        }
        XCTAssertTrue(changed, "not one of the six characters changed the bass — the row is inert")
    }

    /// ⛔ THE FOUNDATION CONTRACT. `appendBass`'s own doc says the section downbeat IS the chord
    /// root, and the sub follows `role: .bass` — so a character that drops it leaves the low end
    /// ungrounded. `syncopated` genuinely would: its rule skips every on-beat below density 0.85
    /// and this binding hands it 0.25 or 0.5. The prepended downbeat is what stops that, and this
    /// is what proves the prepend is still there.
    ///
    /// ⚠️ The prepend is not free of musical consequence and this is the place to record it: it
    /// shifts the `j`-parity the walk uses to alternate root and fifth, and on a section whose
    /// character fires exactly one late cell it makes that cell the "last" one — which is the
    /// walk-up into the next chord's root. So the DEGREES the walk chooses can differ from the
    /// unrotated grid's. That is a re-voicing of the walk, not a break of it, and it is exactly the
    /// kind of thing only the founder's ear can accept or reject.
    func testEveryCharacterStillSoundsTheDownbeat() {
        for character in RoleRhythm.Character.allCases {
            let notes = bass(BioComposer.compose(input(character)).notes)
            XCTAssertFalse(notes.isEmpty, "\(character) silenced the bass entirely")
            XCTAssertEqual(notes.map(\.startStep).min(), 0,
                           "\(character) does not sound the first downbeat — the bass has no floor")
        }
    }

    /// ⛔ NO BASS NOTE MAY RUN INTO THE NEXT ONE. The bass is monophonic to the ear and feeds the
    /// sub; two overlapping low notes are a mud smear, not a chord.
    ///
    /// This is the test the first version of the binding needed and did not have: the PREPENDED
    /// foundation note took a `gap`-based length instead of the room it actually had, so on a
    /// section where the character's first real hit landed one step later, the foundation ran four
    /// steps into it. Now every length is measured against `room`.
    func testNoBassNoteOverlapsTheNextOne() {
        for character in RoleRhythm.Character.allCases {
            let notes = bass(BioComposer.compose(input(character)).notes)
                .sorted { $0.startStep < $1.startStep }
            for (a, b) in zip(notes, notes.dropFirst()) {
                XCTAssertLessThanOrEqual(a.startStep + a.lengthSteps, b.startStep,
                                         "\(character): the note at \(a.startStep) runs into \(b.startStep)")
            }
        }
    }

    /// ⛔ `hypnotic` MUST ACTUALLY ROTATE — the bug this pins was silent and total.
    ///
    /// The binding first passed `bar: step / 16` to `RoleRhythm.hit`. Every step of a take is below
    /// `BioComposer.stepCount == 16`, so that argument was ALWAYS 0 — and `hypnotic`'s whole
    /// identity is `spread(position − bar)`, which at a frozen bar 0 is the plain even spread, i.e.
    /// `driving`'s cells. The one character named after being a slowly-turning figure was the only
    /// one that could not turn, and nothing in the diff or in a count assertion showed it. A take is
    /// ONE bar here, so the thing that advances underneath the rhythm is the chord SECTION.
    ///
    /// Asserted on `startStep` alone and not on the whole note: `hypnotic` and `driving` differ in
    /// gate and accent too, so comparing lengths or velocities would have passed with the bug in
    /// place and pinned nothing.
    ///
    /// ⛔ AND IT MUST NOT LAND ON THE **GENRE'S** GRID EITHER — that second half is the one the first
    /// version of this test was blind to, and it caught a second, subtler form of the same bug. With
    /// the rotation index set to the plain section index, a 3-chord progression (5-step sections)
    /// made `secStart = 5·idx ≡ idx (mod 4)`, the rotation cancelled against the section's own start
    /// cell, and `hypnotic`'s placement came out IDENTICAL to the `nil` take — an override landing
    /// exactly where an override must not land, while still satisfying "≠ driving". Both comparisons
    /// are needed; neither alone is a pin.
    func testHypnoticRotatesTheFigureAcrossSectionsInsteadOfRepeatingAnyoneElsesGrid() {
        let genreOwn = bass(BioComposer.compose(input(nil)).notes).map(\.startStep)
        let driving = bass(BioComposer.compose(input(.driving)).notes).map(\.startStep)
        let hypnotic = bass(BioComposer.compose(input(.hypnotic)).notes).map(\.startStep)
        XCTAssertNotEqual(driving, hypnotic,
                          "hypnotic lands on driving's cells — the rotation index is frozen")
        XCTAssertNotEqual(genreOwn, hypnotic,
                          "hypnotic lands on the genre's own grid — the rotation cancelled itself out")
    }

    /// ⛔ THE FOUNDATION PLAYS IN CHARACTER, not in the genre's shape.
    ///
    /// The prepended downbeat is a note `RoleRhythm` did not select, so it has no `Hit` — and the
    /// first version simply gave it the genre's own length and level. `appendBass` now probes the
    /// character at density 1 (density decides only WHICH cells fire, never the length or the level)
    /// so the foundation carries the character's gate and downbeat accent.
    ///
    /// `syncopated` is the character that proves it: it ducks the on-beat (accent strength 0.3, the
    /// inversion that IS its character) and holds notes for 0.6 of the player's gate, so its
    /// foundation note must be shorter than the genre's own note in the same place. Without the
    /// probe both were the full `gap`.
    ///
    /// The probe may legitimately come back nil — `sparse` refuses any cell that is not a quarter,
    /// `flowing` can flip a cell out even at density 1 — and then the genre's shape is the right
    /// fallback. So this asserts the character where the probe provably applies rather than
    /// demanding all six.
    func testTheForegroundedDownbeatTakesTheCharactersGateAndNotTheGenresLength() {
        guard let plain = bass(BioComposer.compose(input(nil)).notes).first,
              let syncopated = bass(BioComposer.compose(input(.syncopated)).notes).first else {
            return XCTFail("no bass note at the top of the take — the walking path was not reached")
        }
        XCTAssertEqual(plain.startStep, 0)
        XCTAssertEqual(syncopated.startStep, 0)
        XCTAssertLessThan(syncopated.lengthSteps, plain.lengthSteps,
                          "the prepended foundation note ignored the character's gate")
    }

    /// What the override may and may NOT do to the rest of the take.
    ///
    /// ⚠️ IT IS NOT TRUE THAT THE OTHER ROLES ARE UNTOUCHED, and the first version of this test
    /// claimed exactly that. `BioComposer` runs ONE seeded stream for the whole take: the binding
    /// draws a rhythm seed from it and then emits a different NUMBER of bass notes, each consuming
    /// draws for its UUID and its humanised velocity — so every later note's detail shifts. (Nor did
    /// the old assertion even test the half it claimed: `.disco` has `leadDensity: 0.0`, so its
    /// `.lead` note list is empty and comparing two empty arrays passes for free.)
    ///
    /// What must hold is the STRUCTURE: choosing a bass rhythm is a re-roll of the take's detail,
    /// never a change of its tempo, its length, or which roles are present. A binding that silenced
    /// the pad or pushed a note past the loop end would be a real defect, and that is what this pins.
    func testTheOverrideRerollsDetailButNeverTheTakesStructure() {
        let reference = BioComposer.compose(input(nil))
        // The two roles this genre actually sounds (`.disco` has `leadDensity: 0.0`, so asserting a
        // lead here would assert nothing — which is precisely how the old version of this test
        // passed while testing half of what it claimed).
        for role in [NoteRole.bass, .harmony] {
            XCTAssertTrue(reference.notes.contains { $0.role == role },
                          "the reference take has no \(role) — this test cannot guard it")
        }
        for character in RoleRhythm.Character.allCases {
            let overridden = BioComposer.compose(input(character))
            XCTAssertEqual(overridden.suggestedTempo, reference.suggestedTempo,
                           "\(character) changed the tempo — a rhythm character is not a tempo control")
            for role in [NoteRole.bass, .harmony] {
                XCTAssertTrue(overridden.notes.contains { $0.role == role },
                              "\(character) silenced the whole \(role) part")
            }
            for note in bass(overridden.notes) {
                XCTAssertGreaterThanOrEqual(note.startStep, 0)
                XCTAssertLessThanOrEqual(note.startStep + note.lengthSteps, BioComposer.stepCount,
                                         "\(character): a bass note leaves the 16-step loop")
            }
        }
    }

    /// Notes stay inside the loop and never collapse to nothing. A zero-length note is an inaudible
    /// event that still allocates a voice (#205's five velocity-0 notes, #176's missing clamps), and
    /// the gate scaling here multiplies a length by a fraction — exactly where a floor gets lost.
    func testNoNoteIsZeroLengthOrSilent() {
        for character in RoleRhythm.Character.allCases {
            for note in bass(BioComposer.compose(input(character)).notes) {
                XCTAssertGreaterThanOrEqual(note.lengthSteps, 1,
                                            "\(character) produced a zero-length bass note")
                XCTAssertGreaterThan(note.velocity, 0,
                                     "\(character) produced a velocity-0 bass note")
                XCTAssertLessThanOrEqual(note.velocity, 1)
            }
        }
    }

    /// Determinism, which the whole composer rests on: the same input twice is the same take. Worth
    /// its own assertion because the binding draws ONE seed from the shared RNG and then holds it —
    /// an earlier draft drew per step, which made `flowing` and `dynamic` re-roll every call.
    func testTheSameCharacterTwiceIsTheSameBass() {
        for character in RoleRhythm.Character.allCases {
            let first = bass(BioComposer.compose(input(character)).notes)
            let second = bass(BioComposer.compose(input(character)).notes)
            XCTAssertEqual(first.map(\.startStep), second.map(\.startStep))
            XCTAssertEqual(first.map(\.velocity), second.map(\.velocity))
            XCTAssertEqual(first.map(\.lengthSteps), second.map(\.lengthSteps))
        }
    }

    /// The stored preference defaults to "the genre's own", and an unknown stored value reads the
    /// same way. Pinned here rather than only in the keys test because THIS is the conversion the
    /// view performs (`RoleRhythm.Character(rawValue:)`), and it is the one line standing between a
    /// fresh install and an overridden bassline.
    func testTheStoredDefaultAndAnUnknownValueBothMeanTheGenresOwnRhythm() {
        XCTAssertEqual(StudioDefaultKeys.bassRhythm.value, "")
        XCTAssertNil(RoleRhythm.Character(rawValue: StudioDefaultKeys.bassRhythm.value))
        XCTAssertNil(RoleRhythm.Character(rawValue: "galloping"))
    }

    /// The divisor `appendBass` uses to turn an absolute `Hit.velocity` into a multiplier is a term
    /// of `RoleRhythm`'s own velocity formula, and it lived in `BioComposer` as a bare `0.72` for one
    /// commit. Pinned so a re-tune of the base level cannot silently make every bassline quieter:
    /// a hit with no accent must come back at exactly this constant.
    func testTheNeutralVelocityConstantIsTheLevelOfAnUnaccentedHit() {
        let flat = RoleRhythm.Params(character: .driving, density: 1, accent: 0)
        guard let hit = RoleRhythm.hit(bar: 0, cell: 3, cellsPerBar: 16, params: flat, seed: 7) else {
            return XCTFail("density 1 fired no cell")
        }
        XCTAssertEqual(hit.velocity, RoleRhythm.neutralVelocity, accuracy: 1e-6)
    }
}
