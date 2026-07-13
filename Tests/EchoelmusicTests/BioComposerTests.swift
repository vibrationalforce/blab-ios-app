// BioComposerTests.swift
// Echoel — the genre-driven generative core: biodata → Dub Techno / Trap / ambient.
// Asserts the musical invariants (always in key, genre-correct drum patterns,
// tempo locked to the style window) and exact determinism from a seed.

import XCTest
@testable import Echoelmusic

final class BioComposerTests: XCTestCase {

    private func input(coherence: Float = 0.5, hr: Float = 70,
                       breathPhase: Float = 0, seed: UInt64 = 0x5EED,
                       key: MusicalKey = MusicalKey(root: 0, scale: .minor),
                       style: MusicStyle = .dubTechno,
                       mode: ComposerMode = .studioLocked,
                       lockedTempo: Double = 124) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: hr, hrvNormalized: 0.5, coherence: coherence,
                          breathPhase: breathPhase, breathDepth: 0.5, key: key,
                          style: style, mode: mode, lockedTempo: lockedTempo, seed: seed)
    }

    // MARK: - Determinism

    func testDeterministicForSameInput() {
        let a = BioComposer.compose(input())
        let b = BioComposer.compose(input())
        XCTAssertEqual(a, b, "same inputs + seed must produce identical music")
    }

    func testDifferentSeedChangesMusic() {
        let a = BioComposer.compose(input(seed: 1))
        let b = BioComposer.compose(input(seed: 2))
        XCTAssertNotEqual(a, b, "a different seed should vary the take")
    }

    func testSeededRNGIsDeterministic() {
        var a = SeededRNG(seed: 99)
        var b = SeededRNG(seed: 99)
        XCTAssertEqual(a.next(), b.next())
        for _ in 0..<100 {
            let u = a.unit()
            XCTAssertGreaterThanOrEqual(u, 0)
            XCTAssertLessThan(u, 1)
        }
    }

    // MARK: - In-key, in-bar, valid (all styles)

    func testEveryNoteIsInKey() {
        for style in MusicStyle.allCases {
            for scale in Scale.allCases {
                for root in [0, 5, 7, 9] {
                    let key = MusicalKey(root: root, scale: scale)
                    let comp = BioComposer.compose(
                        input(coherence: 0.2, hr: 110, key: key, style: style, seed: 42))
                    for note in comp.notes {
                        XCTAssertTrue(key.contains(note.pitch),
                                      "\(style): \(key.name): pitch \(note.pitch) must be in key")
                    }
                }
            }
        }
    }

    func testNotesStayWithinTheBarAndAreValid() {
        for style in MusicStyle.allCases {
            let comp = BioComposer.compose(input(coherence: 0.1, hr: 120, style: style))
            XCTAssertFalse(comp.notes.isEmpty, "\(style) should produce notes")
            for note in comp.notes {
                XCTAssertGreaterThanOrEqual(note.startStep, 0)
                XCTAssertLessThan(note.startStep, BioComposer.stepCount)
                XCTAssertGreaterThanOrEqual(note.lengthSteps, 1)
                XCTAssertLessThanOrEqual(note.startStep + note.lengthSteps, BioComposer.stepCount,
                                         "\(style): a note never crosses the bar line")
                XCTAssertGreaterThanOrEqual(note.velocity, 0)
                XCTAssertLessThanOrEqual(note.velocity, 1)
            }
        }
    }

    // MARK: - Drums are genre-shaped

    func testDrumGridDimensionsAllStyles() {
        for style in MusicStyle.allCases {
            let comp = BioComposer.compose(input(hr: 100, style: style))
            XCTAssertEqual(comp.drumSteps.count, 8)
            XCTAssertEqual(comp.drumAccents.count, 8)
            XCTAssertTrue(comp.drumSteps.allSatisfy { $0.count == 16 })
            XCTAssertTrue(comp.drumAccents.allSatisfy { $0.count == 16 })
        }
    }

    func testSelfObservationHasNoDrums() {
        let comp = BioComposer.compose(input(hr: 90, style: .selfObservation, mode: .flowFree))
        XCTAssertFalse(comp.hasDrums, "self-observation stays ambient — a pure sustained drone, no drums")
    }

    func testSustainedFlächeIsStillWhenCalm_AliveWhenAroused() {
        // Founder 2026-07-11: "Kompositionen müssen nicht statisch im Takt sein … am
        // Herzschlag orientierte Rhythmen, punktierte und Synkopen" — this SUPERSEDES
        // the 2026-07-07/09 "still even when aroused" rule. The resolution (his own "je
        // nach Biofeedback individuell"): a CALM body keeps the still held Fläche the
        // founder liked; an AROUSED body re-articulates the SAME pad on a dotted/
        // syncopated pulse — pad timbre only (never the rejected exposed wave-lead),
        // in-key, bar-tight, one grounding bass root.
        for style in [MusicStyle.selfObservation, .esotericMeditation] {
            // CALM: high coherence + low heart rate → the still drone (unchanged).
            let calm = BioComposer.compose(
                input(coherence: 0.95, hr: 52, style: style, mode: .flowFree))
            XCTAssertEqual(calm.notes.filter { $0.role == .bass }.count, 1,
                           "\(style) calm: one sustained bass root, not a walking line")
            for n in calm.notes {
                XCTAssertGreaterThanOrEqual(n.lengthSteps, 4,
                    "\(style) calm: a settled body holds the Fläche (got len \(n.lengthSteps))")
            }

            // AROUSED: low coherence + high heart rate → rhythmic life in the PAD.
            let aroused = BioComposer.compose(
                input(coherence: 0.05, hr: 130, style: style, mode: .flowFree))
            XCTAssertEqual(aroused.notes.filter { $0.role == .bass }.count, 1,
                           "\(style) aroused: still ONE grounding bass root (no walking line)")
            XCTAssertFalse(aroused.notes.contains { $0.role == .lead },
                           "\(style) aroused: the movement is in the pad, never an exposed lead")
            // The pad MOVES: more onset positions than the calm take, with at least one
            // short (<4-step) dotted/tresillo re-articulation, all inside the bar.
            let arousedStarts = Set(aroused.notes.map { $0.startStep }).count
            let calmStarts = Set(calm.notes.map { $0.startStep }).count
            XCTAssertGreaterThan(arousedStarts, calmStarts,
                                 "\(style) aroused: the Fläche breaks into a rhythmic pulse")
            XCTAssertTrue(aroused.notes.contains { $0.lengthSteps < 4 },
                          "\(style) aroused: dotted/syncopated re-articulations appear")
            for n in aroused.notes {
                XCTAssertLessThanOrEqual(n.startStep + n.lengthSteps, BioComposer.stepCount,
                    "\(style) aroused: re-articulation stays inside the bar (loop stays tight)")
            }
        }
    }

    // MARK: - B8 offbeat: trap's aroused 808 pedal fills the quarter grid

    func testHeartbeatActive_arousalGate() {
        // The shared "aroused enough to move" gate: needs a section ≥ a quarter (4
        // steps) AND body energy ≥ 0.5. Both the pad re-articulation and trap's
        // quarter-pedal read this one definition.
        XCTAssertTrue(BioComposer.heartbeatActive(energy: 0.5, secLen: 4))
        XCTAssertTrue(BioComposer.heartbeatActive(energy: 0.83, secLen: 8))
        XCTAssertFalse(BioComposer.heartbeatActive(energy: 0.49, secLen: 8), "below-arousal stays still")
        XCTAssertFalse(BioComposer.heartbeatActive(energy: 0.9, secLen: 3), "too-short section stays held")
    }

    func testTrap_arousedBassFillsTheQuarterGrid() {
        // Founder-diagnosed (V2 / Trap 132 lock + active body): trap's held-root 808
        // on {0,8} left beats 2 & 4 empty — "die Viertel fehlen". An AROUSED body now
        // drives a root PEDAL on the quarter grid {0,4,8,12}, one pitch class per
        // chord section (a moving 808, trap's signature), still lead-free, in-key.
        let comp = BioComposer.compose(input(coherence: 0.05, hr: 130, style: .trap))
        let bass = comp.notes.filter { $0.role == .bass }
        XCTAssertEqual(Set(bass.map { $0.startStep }), [0, 4, 8, 12],
                       "aroused trap bass anchors every quarter")
        XCTAssertFalse(comp.notes.contains { $0.role == .lead },
                       "the 808 pedal is bass, never a re-introduced exposed lead")
        // Each 8-step chord section holds ONE root pitch class (a pedal, not a walk).
        let sectionA = bass.filter { $0.startStep < 8 }.map { $0.pitch }
        let sectionB = bass.filter { $0.startStep >= 8 }.map { $0.pitch }
        XCTAssertEqual(Set(sectionA).count, 1, "first section pedals one root")
        XCTAssertEqual(Set(sectionB).count, 1, "second section pedals one root")
        for n in bass {
            XCTAssertLessThanOrEqual(n.startStep + n.lengthSteps, BioComposer.stepCount,
                                     "the pedal stays inside the bar")
        }
    }

    func testTrap_calmBassStaysTheHeldRoot() {
        // A calm body (low energy) keeps the pre-B8 held root per section {0,8},
        // len 8 — the still low end is preserved bit-for-bit, only arousal moves it.
        let comp = BioComposer.compose(input(coherence: 0.95, hr: 52, style: .trap))
        let bass = comp.notes.filter { $0.role == .bass }
        XCTAssertEqual(Set(bass.map { $0.startStep }), [0, 8], "calm trap holds two roots")
        for n in bass {
            XCTAssertEqual(n.lengthSteps, 8, "calm trap root is held for the whole section")
        }
    }

    func testTrap_arousedBassIsDeterministic() {
        let a = BioComposer.compose(input(coherence: 0.05, hr: 130, style: .trap, seed: 0xB8))
        let b = BioComposer.compose(input(coherence: 0.05, hr: 130, style: .trap, seed: 0xB8))
        XCTAssertEqual(a, b, "the quarter pedal is seed-deterministic")
    }

    func testSustainedFlächeJourneysWithProgressionPhase() throws {
        // Founder 2026-07-11: "bleibt auf Flächen liegen … soll weitergehen und sich
        // mit dem Herzschlag weiterentwickeln." A sustained Fläche stays STILL within a
        // bar (one held chord + one held bass), but WHICH chord advances with
        // progressionPhase — so across bars/evolves the pad travels through its
        // progression instead of freezing. Verify both halves of that contract.
        for style in [MusicStyle.selfObservation, .esotericMeditation] {
            let chordCount = style.harmonicProfile.progression.count
            XCTAssertGreaterThan(chordCount, 1, "\(style) needs a journey to travel")

            // The held bass root must MOVE as the phase advances through the progression.
            var roots: Set<Int> = []
            for phase in 0..<chordCount {
                var inp = input(hr: 60, style: style, mode: .flowFree)
                inp.progressionPhase = phase
                let bass = BioComposer.compose(inp).notes.filter { $0.role == .bass }
                XCTAssertEqual(bass.count, 1,
                               "\(style) phase \(phase): still ONE held bass root per bar")
                let root = try XCTUnwrap(bass.first).pitch
                roots.insert(root)
            }
            XCTAssertGreaterThan(roots.count, 1,
                                 "\(style): the Fläche must move through >1 chord as the phase advances")

            // Per-bar stillness preserved at a non-zero phase: a handful of held notes,
            // nothing short (no busy pulse re-introduced by the journey).
            var inp = input(hr: 60, style: style, mode: .flowFree)
            inp.progressionPhase = 1
            let notes = BioComposer.compose(inp).notes
            XCTAssertLessThanOrEqual(notes.count, 8,
                                     "\(style): still a handful of held notes, not a pulse grid")
            for n in notes {
                XCTAssertGreaterThanOrEqual(n.lengthSteps, 4,
                    "\(style): journey keeps sustained notes (got len \(n.lengthSteps))")
            }
        }
    }

    func testProgressionPhaseIsInertForMelodicGenresAtZero() {
        // Backward-compat: phase 0 must reproduce the original take exactly for the
        // (unoffered) melodic genres, so existing seeds/behaviour are untouched.
        for style in [MusicStyle.eighties, .classical, .jazz] {
            var a = input(hr: 80, style: style)
            a.progressionPhase = 0
            let b = input(hr: 80, style: style)   // default phase is 0
            XCTAssertEqual(BioComposer.compose(a), BioComposer.compose(b),
                           "\(style): phase 0 must equal the default (no behaviour change)")
        }
    }

    func testSustainedIsExactlyTheKnownFlächen() {
        // The sustained-Fläche flag holds for exactly the six calm genres (decoupled
        // from the offered roster since 2026-07-11 — all genres are offered now, but
        // only these hold one chord per bar with no lead).
        for style in MusicStyle.allCases {
            let expected = MusicStyle.sustainedFlächen.contains(style)
            XCTAssertEqual(style.harmonicProfile.sustained, expected,
                           "\(style): sustained-Fläche flag ⟺ membership in sustainedFlächen")
        }
    }

    func testCuratedGenresArePureBarTightFlächen() {
        // The founder's deal (2026-07-09, refined 2026-07-11): NO lead melody anywhere
        // in the offered roster (the movement lives in the pad, never an exposed wave-
        // lead), and every note ends exactly inside the bar so the WAV loop stays tight.
        // Two body states: a CALM body holds the Fläche (no short stabs); an AROUSED
        // body may re-articulate the pad on a dotted/syncopated grid — but still no
        // lead and still bar-tight.
        for style in MusicStyle.sustainedFlächen {
            for seed in UInt64(1)...10 {
                // CALM → held Fläche, no short stabs.
                let calm = BioComposer.compose(
                    input(coherence: 0.9, hr: 58, seed: seed, style: style))
                XCTAssertFalse(calm.notes.isEmpty, "\(style): a Fläche still sounds")
                for n in calm.notes {
                    XCTAssertNotEqual(n.role, .lead,
                        "\(style) seed \(seed) calm: no lead melody in a pure Fläche")
                    XCTAssertGreaterThanOrEqual(n.lengthSteps, 4,
                        "\(style) seed \(seed) calm: Flächen hold — no short stabs (len \(n.lengthSteps))")
                    XCTAssertLessThanOrEqual(n.startStep + n.lengthSteps, BioComposer.stepCount,
                        "\(style) seed \(seed) calm: note overruns the bar — loop not tight")
                }
                // AROUSED → pad may re-articulate (short onsets allowed), but still no
                // lead and still bar-tight.
                let aroused = BioComposer.compose(
                    input(coherence: 0.1, hr: 120, seed: seed, style: style))
                for n in aroused.notes {
                    XCTAssertNotEqual(n.role, .lead,
                        "\(style) seed \(seed) aroused: rhythm stays in the pad, no lead")
                    XCTAssertLessThanOrEqual(n.startStep + n.lengthSteps, BioComposer.stepCount,
                        "\(style) seed \(seed) aroused: re-articulation overruns the bar — loop not tight")
                }
            }
        }
    }

    // MARK: - Heartbeat-oriented onsets (founder 2026-07-11: "am Herzschlag orientierte
    // Rhythmen, punktierte und Synkopen" — pure generator, calm=still / active=alive)

    func testHeartbeatOnsets_calmIsOneHeldOnset() {
        // Below the still→alive threshold the section is one held onset (unchanged Fläche).
        let onsets = BioComposer.heartbeatOnsets(secStart: 0, secLen: 16, energy: 0.2, syncopation: 0.2)
        XCTAssertEqual(onsets.count, 1, "a calm body holds the chord as one onset")
        XCTAssertEqual(onsets[0].start, 0)
        XCTAssertEqual(onsets[0].len, 16, "the single onset spans the whole section")
    }

    func testHeartbeatOnsets_shortSectionStaysHeld() {
        // Too-short a section can't carry a groove — always one onset.
        let onsets = BioComposer.heartbeatOnsets(secStart: 4, secLen: 3, energy: 0.95, syncopation: 0.5)
        XCTAssertEqual(onsets.count, 1)
        XCTAssertEqual(onsets[0].start, 4)
        XCTAssertEqual(onsets[0].len, 3)
    }

    func testHeartbeatOnsets_activeSubdividesIntoShortDottedNotes() {
        // An aroused body breaks the held chord into several shorter (dotted/tresillo)
        // re-articulations.
        let onsets = BioComposer.heartbeatOnsets(secStart: 0, secLen: 16, energy: 0.9, syncopation: 0.3)
        XCTAssertGreaterThan(onsets.count, 1, "an active body re-articulates the chord")
        XCTAssertTrue(onsets.contains { $0.len < 4 }, "dotted/syncopated short notes appear")
    }

    func testHeartbeatOnsets_coverTheSectionContiguouslyAndTight() {
        // Whatever the energy, the onsets tile [secStart, secStart+secLen) exactly —
        // contiguous, no gaps, nothing overruns the bar (so the WAV loop stays tight).
        for energy in [Float(0.2), 0.55, 0.75, 0.95] {
            let start = 0, secLen = 16
            let onsets = BioComposer.heartbeatOnsets(secStart: start, secLen: secLen,
                                                     energy: energy, syncopation: 0.4)
            XCTAssertEqual(onsets.first?.start, start, "starts on the section downbeat")
            XCTAssertEqual(onsets.reduce(0) { $0 + $1.len }, secLen,
                           "energy \(energy): onsets sum to exactly the section length")
            // Contiguity: each onset begins where the previous ended.
            for i in 1..<onsets.count {
                XCTAssertEqual(onsets[i].start, onsets[i - 1].start + onsets[i - 1].len,
                               "energy \(energy): no gap/overlap between onsets")
            }
            XCTAssertEqual((onsets.last?.start ?? 0) + (onsets.last?.len ?? 0), start + secLen,
                           "energy \(energy): the last onset ends exactly at the bar edge")
        }
    }

    func testHeartbeatOnsets_moreEnergyIsNotLessMovement() {
        // Monotonic-ish: a fully aroused body has at least as many onsets as a gently
        // active one (more life, never less).
        let gentle = BioComposer.heartbeatOnsets(secStart: 0, secLen: 16, energy: 0.55, syncopation: 0)
        let aroused = BioComposer.heartbeatOnsets(secStart: 0, secLen: 16, energy: 0.95, syncopation: 0)
        XCTAssertGreaterThanOrEqual(aroused.count, gentle.count,
                                    "a busier body carries at least as many re-articulations")
    }

    // MARK: - Lead taming (founder 2026-07-11: "Genres klingen teilweise überladen und
    // unangenehm bis piepsig künstlich")

    func testTameLeadPitchFoldsPiercingHighsDownKeepingPitchClass() {
        // Above the ceiling → folded down by whole octaves (pitch class preserved → in key).
        XCTAssertEqual(BioComposer.tameLeadPitch(96, ceiling: 84), 84, "an octave above C6 folds to C6")
        XCTAssertEqual(BioComposer.tameLeadPitch(100, ceiling: 84), 76, "folds repeatedly until under the ceiling")
        XCTAssertEqual(BioComposer.tameLeadPitch(84, ceiling: 84), 84, "at the ceiling is untouched")
        XCTAssertEqual(BioComposer.tameLeadPitch(72, ceiling: 84), 72, "a note already in range is untouched")
        // Pitch class always preserved.
        for p in stride(from: 60, through: 120, by: 1) {
            XCTAssertEqual(BioComposer.tameLeadPitch(p, ceiling: 84) % 12, p % 12,
                           "\(p): folding keeps the pitch class (stays in key)")
        }
    }

    func testLeadsNeverPierceTheCeilingAcrossGenres() {
        // No generated lead note sits in the piercing top octaves — even for a busy body
        // on the brightest/highest genres (this is the "piepsig künstlich" fix).
        let melodic = MusicStyle.allCases.filter {
            !$0.harmonicProfile.sustained && $0.harmonicProfile.leadDensity > 0
        }
        for style in melodic {
            for root in [0, 5, 9] {
                let key = MusicalKey(root: root, scale: style.scale)
                let comp = BioComposer.compose(
                    input(coherence: 0.1, hr: 130, key: key, style: style, seed: 3))
                for n in comp.notes where n.role == .lead {
                    XCTAssertLessThanOrEqual(n.pitch, 84,
                        "\(style) root \(root): lead \(n.pitch) is piercingly high (> C6)")
                }
            }
        }
    }

    func testOnlyBeatGenresCarryDrums() {
        for style in MusicStyle.allCases {
            let comp = BioComposer.compose(input(hr: 100, style: style))
            XCTAssertEqual(comp.hasDrums, style.isBeatDriven,
                           "\(style): drums present iff the genre is beat-driven")
        }
    }

    // MARK: - Archetype grooves (audit B5 — track indices: 0 kick · 1 snare · 2 hat · 5 perc)

    func testFourOnFloorKicksEveryBeat() {
        let comp = BioComposer.compose(input(hr: 100, style: .disco))
        for s in [0, 4, 8, 12] { XCTAssertTrue(comp.drumSteps[0][s], "disco kick on step \(s)") }
        XCTAssertTrue(comp.drumSteps[4][4] && comp.drumSteps[4][12], "disco backbeat clap on 2 & 4")
    }

    func testBackbeatSnareOnTwoAndFour() {
        let comp = BioComposer.compose(input(hr: 100, style: .rock))
        XCTAssertTrue(comp.drumSteps[1][4] && comp.drumSteps[1][12], "rock snare on 2 & 4")
        XCTAssertTrue(comp.drumAccents[1][4] && comp.drumAccents[1][12], "backbeat is accented")
        XCTAssertTrue(comp.drumSteps[0][0], "rock kick anchors the 1")
    }

    func testOffbeatSkankOnTheOffbeats() {
        let comp = BioComposer.compose(input(hr: 100, style: .ska))
        for s in [2, 6, 10, 14] { XCTAssertTrue(comp.drumSteps[5][s], "ska skank stab on step \(s)") }
    }

    func testHalfTimeSnareOnBeatThree() {
        let comp = BioComposer.compose(input(hr: 100, style: .doom))
        XCTAssertTrue(comp.drumSteps[1][8], "half-time snare on beat 3")
        XCTAssertTrue(comp.drumAccents[1][8], "the beat-3 hit carries the accent")
        XCTAssertFalse(comp.drumSteps[1][4], "no backbeat snare on 2 — this is half-time")
    }

    func testArchetypeBeatIsDeterministicAndSettlesWithCoherence() {
        // Same seed → identical groove; a settled body (calm > 0.7) must produce a
        // SUBSET of the energetic take's hits (the backbone stays, extras drop).
        let a = BioComposer.compose(input(coherence: 0.2, hr: 110, style: .punk, seed: 7))
        let b = BioComposer.compose(input(coherence: 0.2, hr: 110, style: .punk, seed: 7))
        XCTAssertEqual(a.drumSteps, b.drumSteps)
        let settled = BioComposer.compose(input(coherence: 0.9, hr: 60, style: .punk, seed: 7))
        for t in 0..<8 {
            for s in 0..<16 where settled.drumSteps[t][s] {
                XCTAssertTrue(a.drumSteps[t][s],
                              "settled hit (\(t),\(s)) must exist in the energetic take too")
            }
        }
    }

    func testHarmonicGenresProduceLayeredMaterial() {
        // A pad/chord genre yields several simultaneous notes (a chord), not a
        // single line — that's the production starting material.
        let comp = BioComposer.compose(input(hr: 80, style: .vaporwave, mode: .studioLocked))
        XCTAssertGreaterThanOrEqual(comp.notes.count, 4, "vaporwave voices a full chord")
        let onDownbeat = comp.notes.filter { $0.startStep == 0 }
        XCTAssertGreaterThanOrEqual(onDownbeat.count, 2, "chord tones stack on the same step")
    }

    func testCalmBodyDropsThePulseIntoADrone() {
        // Founder ear-feedback ("könnte mehr Drone mäßig sein"): as the body settles
        // the busy pulse layer must fall away so the texture becomes a sustained
        // pad + bass + sparse lead — a drone. A high-coherence (calm) take therefore
        // carries FEWER notes than a low-coherence (aroused) take of the same genre
        // and seed, and the difference is exactly the dropped pulse voices.
        // (Uses .futuristic — a RETIRED melodic profile that still carries the
        // pulse layer. The curated roster is sustained Flächen now, where the
        // pulse never exists in the first place.)
        let aroused = BioComposer.compose(
            input(coherence: 0.2, hr: 96, seed: 7, style: .futuristic))
        let calm = BioComposer.compose(
            input(coherence: 0.95, hr: 58, seed: 7, style: .futuristic))
        XCTAssertLessThan(calm.notes.count, aroused.notes.count,
                          "a calm body drops the pulse layer → fewer notes (drone)")
        // The drone still has a chord (pad + bass), not silence.
        XCTAssertGreaterThanOrEqual(calm.notes.count, 4,
                                    "the calm drone keeps its pad + bass foundation")
    }

    func testHarmonicGenresHaveABassFoundation() {
        // Every harmonic genre now anchors each chord with a bass root an octave
        // below the pad, so the loop reads full, never thin/floating.
        for style in [MusicStyle.vaporwave, .eighties, .disco, .synthwave,
                      .earlySynth, .futuristic, .sciFi, .psytrance] {
            let comp = BioComposer.compose(input(hr: 72, style: style, mode: .studioLocked))
            let profile = style.harmonicProfile
            // The lowest note must sit at or below the pad octave's root (the bass).
            let padRoot = MusicalKey(root: 0, scale: .minor).degree(0, octave: profile.padOctave)
            let lowest = comp.notes.map { $0.pitch }.min() ?? Int.max
            XCTAssertLessThan(lowest, padRoot, "\(style) needs a bass note below the pad")
        }
    }

    func testHarmonicLeadStaysInKey() {
        // The lead is built from chord tones only — so every generated note is in
        // key (no weird/aimless intervals), across many seeds.
        let key = MusicalKey(root: 3, scale: .minor)
        for seed in UInt64(1)...UInt64(40) {
            let comp = BioComposer.compose(input(hr: 96, seed: seed, key: key,
                                                 style: .synthwave, mode: .studioLocked))
            for note in comp.notes {
                XCTAssertTrue(key.contains(note.pitch), "every note must be consonant/in-key")
            }
        }
    }

    func testHarmonicTakesVaryAcrossSeeds() {
        // Regression for "immer derselbe Tonwechsel": across many seeds a harmonic
        // genre must produce more than one distinct opening pitch set — the seed now
        // drives chord rotation + lead opening, not just velocity humanization.
        let key = MusicalKey(root: 0, scale: .minor)
        var openings = Set<Int>()
        for seed in UInt64(1)...UInt64(30) {
            let comp = BioComposer.compose(
                input(hr: 80, seed: seed, key: key, style: .synthwave, mode: .studioLocked))
            // The highest note on the first downbeat = the take's opening colour.
            let firstStep = comp.notes.filter { $0.startStep == 0 }.map { $0.pitch }
            if let top = firstStep.max() { openings.insert(top) }
        }
        XCTAssertGreaterThan(openings.count, 1, "harmonic takes must not all open identically")
    }

    func testDubSecondChordVariesAcrossSeeds() {
        // Individuality survives the Fläche move (founder 2026-07-09: "trotzdem …
        // immer individuell"): the sustained dub progression still rotates/cadences
        // by seed, so the second half's chord varies across takes.
        var seconds = Set<Int>()
        for seed in UInt64(1)...UInt64(30) {
            let comp = BioComposer.compose(
                input(coherence: 0.05, hr: 70, seed: seed, style: .dubTechno))
            // Lowest pitch in the second half (steps 8…15) = that chord's root region.
            let secondHalf = comp.notes.filter { $0.startStep >= 8 }.map { $0.pitch }
            if let root = secondHalf.min() { seconds.insert(root) }
        }
        XCTAssertGreaterThan(seconds.count, 1, "dub's second chord must vary across seeds")
    }

    func testDubTechnoIsFourOnTheFloor() {
        // Kick on every quarter, regardless of energy — the dub pulse.
        for hr in [Float(55), 90, 125] {
            let comp = BioComposer.compose(input(coherence: 0.5, hr: hr, style: .dubTechno))
            for s in [0, 4, 8, 12] {
                XCTAssertTrue(comp.drumSteps[0][s], "dub kick at step \(s) (hr \(hr))")
            }
            // Offbeat closed-hat tick.
            for s in [2, 6, 10, 14] {
                XCTAssertTrue(comp.drumSteps[2][s], "dub offbeat hat at step \(s)")
            }
            // Deep sub on 1 and 3.
            XCTAssertTrue(comp.drumSteps[6][0]); XCTAssertTrue(comp.drumSteps[6][8])
        }
    }

    func testTrapHasHalfTimeSnareAndRollingHats() {
        let comp = BioComposer.compose(input(coherence: 0.3, hr: 120, style: .trap))
        // Snare + clap on beat 3 (step 8).
        XCTAssertTrue(comp.drumSteps[1][8], "trap snare on the half-time backbeat")
        XCTAssertTrue(comp.drumSteps[4][8], "trap clap layered on the backbeat")
        // Rolling 16th hats fill the bar.
        XCTAssertEqual(comp.drumSteps[2].filter { $0 }.count, 16, "trap hats are 16ths")
        // 808 sub mirrors the kick.
        XCTAssertTrue(comp.drumSteps[0][0]); XCTAssertTrue(comp.drumSteps[6][0])
        XCTAssertTrue(comp.drumSteps[0][6]); XCTAssertTrue(comp.drumSteps[6][6])
        // Open-hat lift into the loop.
        XCTAssertTrue(comp.drumSteps[3][15], "trap open-hat into the loop")
    }

    func testTrapEnergyAddsKickSyncopation() {
        // High HR (>0.5 energy) adds the step-3 kick; low HR does not.
        let calm = BioComposer.compose(input(coherence: 0.5, hr: 60, style: .trap))
        let busy = BioComposer.compose(input(coherence: 0.5, hr: 120, style: .trap))
        XCTAssertFalse(calm.drumSteps[0][3], "low energy → no step-3 kick")
        XCTAssertTrue(busy.drumSteps[0][3], "high energy → syncopated step-3 kick")
    }

    func testDubFlächeStaysStillWhateverTheBodyDoes() {
        // Founder 2026-07-09: dub is a pure sustained Fläche now — the offbeat
        // stabs are retired. An aroused body must NOT re-densify the texture
        // (stillness IS the quality); the body speaks through tempo, velocity,
        // the beat layer and FX instead.
        let calm = BioComposer.compose(input(coherence: 0.95, hr: 70, style: .dubTechno))
        let busy = BioComposer.compose(input(coherence: 0.05, hr: 70, style: .dubTechno))
        XCTAssertEqual(busy.notes.count, calm.notes.count,
                       "the dub Fläche keeps the same held material at any arousal")
    }

    // MARK: - Tempo locks to the style window

    func testTempoClampsIntoStyleWindow() {
        // Studio mode clamps the requested BPM into the genre's range.
        XCTAssertEqual(BioComposer.tempo(for: input(style: .dubTechno, mode: .studioLocked,
                                                    lockedTempo: 75)), 118,
                       "dub clamps up to its 118 floor")
        XCTAssertEqual(BioComposer.tempo(for: input(style: .trap, mode: .studioLocked,
                                                    lockedTempo: 75)), 130,
                       "trap clamps up to its 130 floor")
        XCTAssertEqual(BioComposer.tempo(for: input(style: .dubTechno, mode: .studioLocked,
                                                    lockedTempo: 124)), 124,
                       "a BPM inside the window is kept")
        XCTAssertEqual(BioComposer.tempo(for: input(style: .selfObservation, mode: .studioLocked,
                                                    lockedTempo: 75)), 75,
                       "self-observation window (46–78) keeps 75")
    }

    func testFlowTempoFollowsHeart() {
        // At zero coherence Flow follows the heart exactly (no entrainment pull).
        XCTAssertEqual(BioComposer.tempo(for: input(coherence: 0, hr: 128, mode: .flowFree)), 128,
                       "Flow mode follows the heart at zero coherence")
        XCTAssertEqual(BioComposer.tempo(for: input(coherence: 0, hr: 220, mode: .flowFree)), 160,
                       "Flow tempo is clamped to a musical ceiling")
    }

    func testFlowTempoPulledTowardResonanceByCoherence() {
        // Two-clock entrainment: as coherence rises, a fast heart's pulse is drawn
        // DOWN toward the ~72 BPM resonance band (groove settles with the body).
        let fastHeart = Float(120)
        let lowCoh  = BioComposer.tempo(for: input(coherence: 0.0, hr: fastHeart, mode: .flowFree))
        let midCoh  = BioComposer.tempo(for: input(coherence: 0.5, hr: fastHeart, mode: .flowFree))
        let fullCoh = BioComposer.tempo(for: input(coherence: 1.0, hr: fastHeart, mode: .flowFree))
        XCTAssertEqual(lowCoh, 120, accuracy: 1e-6, "no pull at zero coherence")
        XCTAssertLessThan(midCoh, lowCoh, "coherence pulls the pulse down")
        XCTAssertEqual(fullCoh, 72, accuracy: 1e-6, "full coherence converges to the resonance band")
    }

    // MARK: - Tempo-adaptive Spielart (founder 2026-07-11: "auf 75 ok, auf 132 zu hektisch
    // … je nach bpm adaptiv die Spielart anpassen um immer einen guten Vibe zu kreieren")

    func testTempoDensityScale_slowStaysFull() {
        // At/below the comfortable baseline the take is UNCHANGED (the good-at-75 case).
        XCTAssertEqual(BioComposer.tempoDensityScale(bpm: 60), 1.0, accuracy: 1e-6)
        XCTAssertEqual(BioComposer.tempoDensityScale(bpm: 75), 1.0, accuracy: 1e-6)
        XCTAssertEqual(BioComposer.tempoDensityScale(bpm: 84), 1.0, accuracy: 1e-6)
    }

    func testTempoDensityScale_thinsAsTempoClimbs() {
        let s100 = BioComposer.tempoDensityScale(bpm: 100)
        let s132 = BioComposer.tempoDensityScale(bpm: 132)
        let s160 = BioComposer.tempoDensityScale(bpm: 160)
        XCTAssertLessThan(s100, 1.0, "above the baseline the take thins")
        XCTAssertLessThan(s132, s100, "faster → thinner (monotonic)")
        XCTAssertLessThan(s160, s132, "faster still → thinner still")
    }

    func testTempoDensityScale_neverThinnerThanHalf() {
        XCTAssertGreaterThanOrEqual(BioComposer.tempoDensityScale(bpm: 300), 0.5,
                                    "the line is thinned, never gutted")
    }

    func testFastTakeIsNotBusierThanSlowTake() {
        // The founder's exact case: Disco at a fast tempo must not carry MORE lead notes
        // than the same genre/seed at a comfortable tempo (constant-ish notes-per-second).
        for style in [MusicStyle.disco, .eighties, .synthwave, .psytrance] {
            let slow = BioComposer.compose(input(hr: 72, seed: 11, style: style,
                                                 mode: .studioLocked, lockedTempo: 74))
            let fast = BioComposer.compose(input(hr: 72, seed: 11, style: style,
                                                 mode: .studioLocked, lockedTempo: 150))
            let slowLead = slow.notes.filter { $0.role == .lead }.count
            let fastLead = fast.notes.filter { $0.role == .lead }.count
            XCTAssertLessThanOrEqual(fastLead, slowLead,
                                     "\(style): a fast take must not be busier than a slow one")
        }
    }

    // MARK: - Ambient self-observation note bounds

    func testAmbientNoteCountStaysInBounds() {
        for hr in stride(from: Float(45), through: 130, by: 5) {
            for coh in stride(from: Float(0), through: 1, by: 0.1) {
                let comp = BioComposer.compose(
                    input(coherence: coh, hr: hr, style: .selfObservation, mode: .flowFree))
                XCTAssertGreaterThanOrEqual(comp.notes.count, 2)
                XCTAssertLessThanOrEqual(comp.notes.count, 8)
            }
        }
    }

    // MARK: - Coherence-aware groove sparsity

    private func drumHits(_ c: BioComposition) -> Int {
        c.drumSteps.reduce(0) { $0 + $1.filter { $0 }.count }
    }

    /// High coherence must settle the GROOVE too — never more hits than an aroused
    /// body, with the genre backbone intact. (Rhythmic analog of the density servo.)
    func testGroove_highCoherenceNeverBusierThanAroused() {
        for style in [MusicStyle.dubTechno, .trap] {
            var sawStrictlyFewer = false
            for seed in UInt64(1)...24 {
                let aroused = BioComposer.compose(input(coherence: 0.2, hr: 115, style: style, seed: seed))
                let settled = BioComposer.compose(input(coherence: 0.95, hr: 115, style: style, seed: seed))
                XCTAssertLessThanOrEqual(drumHits(settled), drumHits(aroused),
                                         "\(style): settled groove must not exceed aroused (seed \(seed))")
                if drumHits(settled) < drumHits(aroused) { sawStrictlyFewer = true }
            }
            XCTAssertTrue(sawStrictlyFewer, "\(style): settling must actually thin some takes")
        }
    }

    func testGroove_backboneSurvivesHighCoherence() {
        // The signature stays even when settled: trap keeps its half-time snare +
        // 16th hats; dub keeps four-on-the-floor.
        let trap = BioComposer.compose(input(coherence: 0.97, hr: 115, style: .trap))
        XCTAssertTrue(trap.drumSteps[1][8], "trap snare backbone survives")
        XCTAssertEqual(trap.drumSteps[2].filter { $0 }.count, 16, "trap 16th hats survive")
        let dub = BioComposer.compose(input(coherence: 0.97, hr: 115, style: .dubTechno))
        for s in [0, 4, 8, 12] { XCTAssertTrue(dub.drumSteps[0][s], "dub four-on-floor survives") }
    }

    // MARK: - Live velocity humanization

    private func uniformNotes(_ v: Float = 0.8, count: Int = 8) -> [Note] {
        (0..<count).map { Note(pitch: 60 + $0, startStep: $0, lengthSteps: 1, velocity: v) }
    }

    func testHumanize_zeroAmountIsIdentity() {
        let notes = uniformNotes()
        let out = BioComposer.humanizeVelocity(notes, amount: 0, seed: 0x5EED)
        XCTAssertEqual(out.map(\.velocity), notes.map(\.velocity), "amount 0 → no change")
    }

    func testHumanize_variesButStaysMusicalAndDeterministic() {
        let notes = uniformNotes(0.8)
        let a = BioComposer.humanizeVelocity(notes, amount: 0.25, seed: 0x5EED)
        let b = BioComposer.humanizeVelocity(notes, amount: 0.25, seed: 0x5EED)
        XCTAssertEqual(a.map(\.velocity), b.map(\.velocity), "seeded → reproducible")
        XCTAssertFalse(a.allSatisfy { $0.velocity == 0.8 }, "uniform input must gain variation")
        for n in a {
            XCTAssertGreaterThanOrEqual(n.velocity, 0.05)
            XCTAssertLessThanOrEqual(n.velocity, 1)
        }
        // ±18% cap at full humanize: stays within a sane band of the source velocity.
        let full = BioComposer.humanizeVelocity(notes, amount: 1, seed: 0x5EED)
        for n in full { XCTAssertLessThanOrEqual(abs(n.velocity - 0.8), 0.8 * 0.18 + 1e-6) }
    }

    // MARK: - Coherence-convergence servo (Phase 1, science-grounded)

    /// Validated direction: rising coherence must CONVERGE the music toward calm —
    /// monotonically lowering density (`busy`) — as the body's reward for self-regulation.
    func testServo_higherCoherenceMonotonicallyLowersBusy() {
        var last = Float.greatestFiniteMagnitude
        for coh in stride(from: Float(0), through: 1, by: 0.1) {
            let s = BioComposer.musicalState(coherence: coh, hrvNormalized: 0.5, heartRateBPM: 80)
            XCTAssertLessThanOrEqual(s.busy, last + 1e-6, "busy must not rise as coherence rises")
            last = s.busy
        }
        // The convergence is decisive, not marginal: full coherence is much sparser.
        let lowCoh  = BioComposer.musicalState(coherence: 0, hrvNormalized: 0.5, heartRateBPM: 80).busy
        let highCoh = BioComposer.musicalState(coherence: 1, hrvNormalized: 0.5, heartRateBPM: 80).busy
        XCTAssertLessThan(highCoh, lowCoh * 0.6, "high coherence converges to a notably sparser take")
    }

    /// Consonance convergence: rising coherence must lower effective melodic tension
    /// (more consonant when settled), unchanged at zero coherence.
    func testServo_coherenceLowersEffectiveTension() {
        XCTAssertEqual(BioComposer.effectiveTension(0.8, coherence: 0), 0.8, accuracy: 1e-6)
        let mid  = BioComposer.effectiveTension(0.8, coherence: 0.5)
        let full = BioComposer.effectiveTension(0.8, coherence: 1)
        XCTAssertLessThan(mid, 0.8)
        XCTAssertLessThan(full, mid)
        XCTAssertEqual(full, 0.8 * 0.4, accuracy: 1e-6, "full coherence → 40% tension")
        XCTAssertGreaterThanOrEqual(full, 0)
    }

    /// The textbook stress signature (↑HR, ↓HRV) must raise arousal and density.
    func testServo_stressSignatureRaisesArousalAndBusy() {
        let calmBody     = BioComposer.musicalState(coherence: 0.5, hrvNormalized: 0.9, heartRateBPM: 55)
        let stressedBody = BioComposer.musicalState(coherence: 0.5, hrvNormalized: 0.1, heartRateBPM: 115)
        XCTAssertGreaterThan(stressedBody.arousal, calmBody.arousal)
        XCTAssertGreaterThan(stressedBody.busy, calmBody.busy)
    }

    /// All outputs stay in [0,1] across the whole physiological envelope.
    func testServo_outputsStayNormalized() {
        for hr in stride(from: Double(40), through: 180, by: 10) {
            for hrv in stride(from: Float(0), through: 1, by: 0.25) {
                for coh in stride(from: Float(0), through: 1, by: 0.25) {
                    let s = BioComposer.musicalState(coherence: coh, hrvNormalized: hrv, heartRateBPM: hr)
                    for v in [s.calm, s.vagal, s.energy, s.arousal, s.busy] {
                        XCTAssertGreaterThanOrEqual(v, 0)
                        XCTAssertLessThanOrEqual(v, 1)
                    }
                }
            }
        }
    }
}
