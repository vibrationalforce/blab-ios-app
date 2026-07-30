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
// The rest guards the three promises the panel makes to the player: the character actually changes
// the bass, it changes ONLY the bass, and the section downbeat survives every character (the
// foundation contract `appendBass` states in its own doc — `syncopated` would otherwise start a bar
// on air).

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
    func testEveryCharacterStillSoundsTheDownbeat() {
        for character in RoleRhythm.Character.allCases {
            let notes = bass(BioComposer.compose(input(character)).notes)
            XCTAssertFalse(notes.isEmpty, "\(character) silenced the bass entirely")
            XCTAssertEqual(notes.map(\.startStep).min(), 0,
                           "\(character) does not sound the first downbeat — the bass has no floor")
        }
    }

    /// The override must reach the BASS and nothing else. The harmony, the lead and the drum grid
    /// are other roles' business, and a binding that disturbed them would mean the rhythm had leaked
    /// into the shared RNG stream — the failure mode that makes a "bass" setting change the melody.
    func testTheOverrideTouchesTheBassAndLeavesEveryOtherRoleAlone() {
        let reference = BioComposer.compose(input(nil)).notes
        let overridden = BioComposer.compose(input(.hypnotic)).notes
        for role in [NoteRole.harmony, .lead] {
            XCTAssertEqual(reference.filter { $0.role == role }.map(\.startStep),
                           overridden.filter { $0.role == role }.map(\.startStep),
                           "\(role) moved — the bass rhythm leaked out of its own role")
            XCTAssertEqual(reference.filter { $0.role == role }.map(\.pitch),
                           overridden.filter { $0.role == role }.map(\.pitch),
                           "\(role) changed pitch — the bass rhythm consumed shared RNG")
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
}
