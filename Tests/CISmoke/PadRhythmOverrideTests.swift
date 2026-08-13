// PadRhythmOverrideTests.swift
// Echoel — the PAD rhythm override is an OVERRIDE, in the BLOCKING bundle (#253 A4).
//
// ⚠️ WHY ALL FOUR CALLS HERE SPELL `gate: 0.8, accent: 0.4, evolve: 0.2` (#581). Those three
// were literals INSIDE `roleRhythmOnsets` until the founder asked for the section that exposes
// them; they are now required arguments, deliberately without defaults, so that a forgetful call
// site fails to compile instead of silently doing nothing (#431/#440/#443). The numbers written
// here are the exact literals the function used to carry, so every assertion below tests what it
// tested before — this file's subject is the CHARACTER override, not the shape dials, and #581
// must not quietly change what it measures. A shape-dial test belongs in the #581 guard.
//
// ⭐ THE FIRST TEST IS THE ONE THAT MATTERS, and it matters more here than it did for the bass. The
// pad is the biggest audible surface in a take (the drums are gone since #166/#167), and the founder
// curated these genres by ear TWICE (#81, #125: "erst eine individuelle Variation und dann klingt
// plötzlich alles gleich"). A character that leaked into the default path would not merely re-voice
// one layer — it would re-articulate every genre's chords on ONE grid, which is that defect exactly.
// So `padRhythm: nil` must produce a BYTE-IDENTICAL take, asserted against the whole note list.
//
// The rest guards what the row promises: it reaches EVERY non-arpeggiated pad path (Fläche, chop
// grid and held chord alike), it keeps the genre's RATE rather than becoming a second tempo control,
// it never overlaps two chords into a smear, and an arpeggiated genre keeps its pitch figure.

import XCTest
@testable import Echoelmusic

final class PadRhythmOverrideTests: XCTestCase {

    /// Three genres chosen for their three DIFFERENT pad paths, so the override is tested where it
    /// actually behaves differently rather than three times on one branch:
    ///   · `.disco`     → `.stab` articulation, the chop grid (`chordOnsets` beats/offbeats).
    ///   · `.dubTechno` → `sustained` profile, the heartbeat Fläche.
    ///   · `.synthwave` → `arpeggiated`, the pitch-cycling path.
    /// Verified against `MusicStyle.harmonicProfile` rather than assumed; if a future curation pass
    /// changes one of these, the assertions below say which promise broke.
    private func input(_ style: MusicStyle, _ rhythm: RoleRhythm.Character?) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: 132, hrvNormalized: 0.3, coherence: 0.3,
                          breathPhase: 0.25, breathDepth: 0.7,
                          key: MusicalKey(root: 0, scale: .minor),
                          style: style, mode: .studioLocked, lockedTempo: 132,
                          seed: 0xA4B0, padRhythm: rhythm)
    }

    private func pad(_ notes: [Note]) -> [Note] {
        notes.filter { $0.role == .harmony }
    }

    /// ⛔ THE GOLDEN LAW, AND AN HONEST ACCOUNT OF WHAT HOLDS IT — because the first version of this
    /// test held NOTHING and said the opposite.
    ///
    /// It composed `Input(…, padRhythm: nil)` against `Input(…)` with `padRhythm` left to default,
    /// i.e. **the same value twice**, and then claimed to catch an RNG leak "for free". That is a
    /// tautology: it re-ran one input and compared it with itself. The shape was inherited from
    /// `BassRhythmOverrideTests` (fixed there in the same commit), which inherited it from the
    /// `voiceLeading`/`humanize`/`suggestJourney` switches before it — so the law this repo leans on
    /// hardest has never actually been asserted anywhere.
    ///
    /// What genuinely holds byte-identity is CONSTRUCTION, verified by reading: `rng.next()` for the
    /// rhythm seed sits inside `if let character = padRhythm`, `chordOnsets` is RNG-free, the
    /// `arpStep` hoist is integer arithmetic, and the four legacy branches are untouched inside the
    /// `else`. A test cannot check that without a literal fixture captured from the pre-feature
    /// revision, and this repo has no local toolchain to capture one.
    ///
    /// So this test asserts the strongest thing that IS checkable and would catch the realistic
    /// regression — someone dropping the `if let` and applying a character unconditionally: the
    /// default take must be the GENRE'S OWN articulation, which means it must not equal ANY of the
    /// six characters' output, and it must still carry the tresillo's 3-step hold that every gated
    /// character shortens.
    func testTheDefaultTakeIsTheGenresOwnArticulationAndNotAnyCharacters() {
        for style in [MusicStyle.disco, .dubTechno, .synthwave] {
            let plain = pad(BioComposer.compose(input(style, nil)).notes)
            XCTAssertFalse(plain.isEmpty, "\(style)")
            let signature = plain.map { [$0.startStep, $0.lengthSteps] }
            for character in RoleRhythm.Character.allCases {
                let overridden = pad(BioComposer.compose(input(style, character)).notes)
                XCTAssertNotEqual(signature, overridden.map { [$0.startStep, $0.lengthSteps] },
                                  "\(style): the DEFAULT take equals \(character)'s — a character is being applied unconditionally")
            }
        }
        // The calm-Fläche signature: `heartbeatOnsets` groups a tresillo 3-3-2, and no character can
        // produce that 3 at gate 0.8 × its scale (the longest, `sparse`/`flowing` at 1.0, rounds to 2
        // from a room of 3). A held 3 therefore proves the untouched path ran.
        let flaeche = pad(BioComposer.compose(input(.dubTechno, nil)).notes)
        XCTAssertTrue(flaeche.contains { $0.lengthSteps >= 3 },
                      "the sustained genre lost its held onset — the default path did not run")
    }

    /// ⛔ THE ROW IS NOT DEAD ON ANY PAD PATH. This is the assertion the bass row could NOT make —
    /// there, a settled body or a sustained genre legitimately ignores the setting, which had to be
    /// disclosed as a caveat. Here every path routes through the same override, so "at least one
    /// character changes the pad" must hold for the chop grid, the Fläche AND the arp alike. If a
    /// future refactor re-branches one of them past the binding, exactly this turns red.
    func testEveryPadPathIsReachedByAtLeastOneCharacter() {
        for style in [MusicStyle.disco, .dubTechno, .synthwave] {
            let reference = pad(BioComposer.compose(input(style, nil)).notes)
            XCTAssertFalse(reference.isEmpty, "\(style) has no pad at all — cannot test its rhythm")
            let changed = RoleRhythm.Character.allCases.contains { character in
                let overridden = pad(BioComposer.compose(input(style, character)).notes)
                return overridden.map(\.startStep) != reference.map(\.startStep)
                    || overridden.map(\.lengthSteps) != reference.map(\.lengthSteps)
                    || overridden.map(\.velocity) != reference.map(\.velocity)
            }
            XCTAssertTrue(changed, "\(style): not one character changed the pad — the row is inert here")
        }
    }

    /// ⛔ THE RATE STAYS THE GENRE'S — pinned on the pure core, where it is exact, rather than
    /// through a genre where it is not.
    ///
    /// This is the assertion that catches the mistake I actually made while building A4: the density
    /// was first derived by asking `chordOnsets` on EVERY path, including the arpeggiated one — where
    /// the articulation value describes a chord grid the genre never plays. On synthwave that answer
    /// was ~3× the arp's real rate, so the row would have tripled the note count and behaved as a
    /// tempo control. A composer-level note-count band cannot see that (the foundation prepend
    /// already moves the count by up to one per section, which swamps the signal), but the core can:
    /// `driving` is the plain even spread, so at a density derived from `rate/len` it must land within
    /// ONE onset of that rate. ±1 and not equality because `round(density · 16)` is then sampled
    /// through a `len`-wide window — 3-in-5 genuinely lands 4 — and pretending otherwise would be a
    /// test that pins arithmetic noise instead of the contract.
    /// ⚠️ WHAT THIS BUNDLE DOES *NOT* PIN, recorded rather than left to be discovered: nothing here
    /// asserts WHICH source the caller counts the rate from — `chordOnsets` on the chord paths vs the
    /// arp's own `arpStep` grid. Getting that wrong was the real bug in A4's first draft, and the
    /// commit message claimed this next test would have caught it. It would not: it calls the core
    /// with a hand-supplied density and never exercises the caller's choice. A discriminating test
    /// needs a body state where the two sources actually differ, and they only do so in a narrow
    /// window (`busy ≤ 0.6` while `busy + syncopation·0.15 ≥ 0.6`, i.e. arp rate 1 vs stab 2) that
    /// cannot be hit from the public `Input` without pinning the arousal maths itself — which would
    /// be a test of `musicalState`, not of this feature. Left unpinned on purpose, said out loud.
    func testTheDerivedDensityReproducesTheRateItWasDerivedFrom() {
        for (rate, len) in [(1, 4), (2, 5), (3, 5), (3, 6), (2, 8), (4, 8)] {
            let onsets = BioComposer.roleRhythmOnsets(secStart: 0, secLen: len, sectionIndex: 0,
                                                      character: .driving,
                                                      density: Float(rate) / Float(len),
                                                      gate: 0.8, accent: 0.4, evolve: 0.2,
                                                      seed: 9)
            XCTAssertLessThanOrEqual(abs(onsets.count - rate), 1,
                                     "rate \(rate)/\(len) produced \(onsets.count) onsets — the density derivation drifted")
        }
    }

    /// The same claim at the composer level, deliberately as a LOOSE band and labelled as such: a
    /// character may legitimately thin the pad (`sparse` squares its density) or add the foundation
    /// onset to every section, so the only thing worth asserting here is that no character silences
    /// the pad or blows its rate apart. The exact derivation is pinned in the test above.
    func testNoCharacterSilencesOrExplodesTheGenresChordRate() {
        for style in [MusicStyle.disco, .dubTechno, .synthwave] {
            let reference = pad(BioComposer.compose(input(style, nil)).notes).count
            XCTAssertGreaterThan(reference, 0, "\(style)")
            for character in RoleRhythm.Character.allCases {
                let count = pad(BioComposer.compose(input(style, character)).notes).count
                XCTAssertGreaterThan(count, 0, "\(style)/\(character) silenced the pad")
                XCTAssertLessThanOrEqual(count, reference * 3,
                                         "\(style)/\(character) blew the chord rate apart")
            }
        }
    }

    /// ⛔ TWO CHORDS MUST NOT OVERLAP. A pad is a block of simultaneous pitches, so an onset that
    /// runs into the next one does not sound like a longer chord — it sounds like two chords fighting
    /// for the same voices on a shared polyphony budget, which is the pad-dropout class of defect
    /// (#205's voice-stealing). `roleRhythmOnsets` measures every length against the room it has;
    /// this is the proof, checked per pitch so a block of four voices is not mistaken for four
    /// overlapping onsets.
    func testNoTwoChordOnsetsOverlapOnTheSamePitch() {
        for style in [MusicStyle.disco, .dubTechno, .synthwave] {
            for character in RoleRhythm.Character.allCases {
                let notes = pad(BioComposer.compose(input(style, character)).notes)
                for pitch in Set(notes.map(\.pitch)) {
                    let line = notes.filter { $0.pitch == pitch }.sorted { $0.startStep < $1.startStep }
                    for (a, b) in zip(line, line.dropFirst()) {
                        XCTAssertLessThanOrEqual(a.startStep + a.lengthSteps, b.startStep,
                                                 "\(style)/\(character): pitch \(pitch) at \(a.startStep) runs into \(b.startStep)")
                    }
                }
            }
        }
    }

    /// Nothing zero-length, nothing silent, nothing outside the loop — the #205/#176 law, on the
    /// layer where a gate fraction multiplies a length and a level multiplier multiplies a velocity.
    func testEveryPadNoteIsAudibleAndInsideTheLoop() {
        for style in [MusicStyle.disco, .dubTechno, .synthwave] {
            for character in RoleRhythm.Character.allCases {
                for note in pad(BioComposer.compose(input(style, character)).notes) {
                    XCTAssertGreaterThanOrEqual(note.lengthSteps, 1, "\(style)/\(character)")
                    XCTAssertGreaterThan(note.velocity, 0, "\(style)/\(character)")
                    XCTAssertLessThanOrEqual(note.velocity, 1, "\(style)/\(character)")
                    XCTAssertGreaterThanOrEqual(note.startStep, 0, "\(style)/\(character)")
                    XCTAssertLessThanOrEqual(note.startStep + note.lengthSteps, BioComposer.stepCount,
                                             "\(style)/\(character) left the 16-step loop")
                }
            }
        }
    }

    /// ⛔ AN ARPEGGIATED GENRE KEEPS ITS PITCH FIGURE. The override decides WHEN notes land, never
    /// which pitch sounds — that is `ArpFigure`'s job. Playing the full chord block on an arp genre
    /// would have been a timbral rewrite hiding inside a rhythm control, and the cheap way to catch
    /// it is that a block emits every voice at the SAME step while an arp emits one voice per step.
    func testAnArpeggiatedGenreStaysAnArpeggioAndDoesNotBecomeABlockChord() {
        for character in RoleRhythm.Character.allCases {
            let notes = pad(BioComposer.compose(input(.synthwave, character)).notes)
            XCTAssertFalse(notes.isEmpty, "\(character) silenced the arp")
            let perStep = Dictionary(grouping: notes, by: \.startStep)
            for (step, group) in perStep {
                XCTAssertEqual(group.count, 1,
                               "\(character): \(group.count) simultaneous pitches at step \(step) — the arp became a block chord")
            }
        }
    }

    /// Determinism, and it is worth its own assertion because the binding draws ONE seed per section
    /// from the shared stream and then holds it: a per-step draw would make `flowing`'s cell flips
    /// and `dynamic`'s level jitter re-roll on every call.
    func testTheSameCharacterTwiceIsTheSamePad() {
        for character in RoleRhythm.Character.allCases {
            let first = pad(BioComposer.compose(input(.disco, character)).notes)
            let second = pad(BioComposer.compose(input(.disco, character)).notes)
            XCTAssertEqual(first.map(\.startStep), second.map(\.startStep), "\(character)")
            XCTAssertEqual(first.map(\.lengthSteps), second.map(\.lengthSteps), "\(character)")
            XCTAssertEqual(first.map(\.velocity), second.map(\.velocity), "\(character)")
        }
    }

    /// The pure generator's own contract, tested directly so a failure points at the core rather
    /// than at a genre: a section always sounds, its first onset IS the section downbeat (the chord's
    /// harmonic foundation), and the level is a MULTIPLIER around 1 rather than an absolute level.
    func testTheOnsetGeneratorAlwaysSoundsTheSectionDownbeat() {
        for character in RoleRhythm.Character.allCases {
            for secStart in [0, 5, 10] {
                let onsets = BioComposer.roleRhythmOnsets(secStart: secStart, secLen: 5,
                                                          sectionIndex: secStart / 5,
                                                          character: character, density: 0.25,
                                                          gate: 0.8, accent: 0.4, evolve: 0.2,
                                                          seed: 0xA4)
                XCTAssertFalse(onsets.isEmpty, "\(character)@\(secStart) produced no onset")
                XCTAssertEqual(onsets.first?.start, secStart,
                               "\(character)@\(secStart) does not sound the section downbeat")
                for onset in onsets {
                    XCTAssertGreaterThanOrEqual(onset.len, 1, "\(character)@\(secStart)")
                    XCTAssertLessThanOrEqual(onset.start + onset.len, secStart + 5,
                                             "\(character)@\(secStart) left its section")
                    XCTAssertGreaterThan(onset.level, 0, "\(character)@\(secStart)")
                    XCTAssertLessThan(onset.level, 2,
                                      "\(character)@\(secStart): level is a multiplier around 1, not a level")
                }
            }
        }
    }

    /// A zero-or-negative section length must return nothing rather than trap or invent an onset —
    /// `composeHarmonic` guards `secEnd > secStart` today, so this is a boundary that holds by
    /// contract and not by luck, and the guard is what lets the caller stay simple.
    func testAnEmptySectionProducesNoOnsets() {
        XCTAssertTrue(BioComposer.roleRhythmOnsets(secStart: 4, secLen: 0, sectionIndex: 0,
                                                   character: .driving, density: 0.5,
                                                   gate: 0.8, accent: 0.4, evolve: 0.2,
                                                   seed: 1).isEmpty)
        XCTAssertTrue(BioComposer.roleRhythmOnsets(secStart: 4, secLen: -3, sectionIndex: 0,
                                                   character: .driving, density: 0.5,
                                                   gate: 0.8, accent: 0.4, evolve: 0.2,
                                                   seed: 1).isEmpty)
    }

    /// The stored preference defaults to "the genre's own", and an unknown stored value reads the
    /// same way — the one line between a fresh install and every genre re-articulating on one grid.
    func testTheStoredDefaultAndAnUnknownValueBothMeanTheGenresOwnRhythm() {
        XCTAssertEqual(StudioDefaultKeys.padRhythm.value, "")
        XCTAssertNil(RoleRhythm.Character(rawValue: StudioDefaultKeys.padRhythm.value))
        XCTAssertNil(RoleRhythm.Character(rawValue: "shuffling"))
        XCTAssertNotEqual(StudioDefaultKeys.padRhythm.key, StudioDefaultKeys.bassRhythm.key,
                          "the two rows would share one stored value")
    }
}
