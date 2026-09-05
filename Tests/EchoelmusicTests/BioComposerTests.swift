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
                        input(coherence: 0.2, hr: 110, seed: 42, key: key, style: style))
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
        for style in [MusicStyle.selfObservation, .stillMeditation] {
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
        let a = BioComposer.compose(input(coherence: 0.05, hr: 130, seed: 0xB8, style: .trap))
        let b = BioComposer.compose(input(coherence: 0.05, hr: 130, seed: 0xB8, style: .trap))
        XCTAssertEqual(a, b, "the quarter pedal is seed-deterministic")
    }

    func testSustainedFlächeJourneysWithProgressionPhase() throws {
        // Founder 2026-07-11: "bleibt auf Flächen liegen … soll weitergehen und sich
        // mit dem Herzschlag weiterentwickeln." A sustained Fläche stays STILL within a
        // bar (one held chord + one held bass), but WHICH chord advances with
        // progressionPhase — so across bars/evolves the pad travels through its
        // progression instead of freezing. Verify both halves of that contract.
        for style in [MusicStyle.selfObservation, .stillMeditation] {
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

    // testLeadsNeverPierceTheCeilingAcrossGenres removed (founder 2026-07-21:
    // "Melodien sollen die Leute selbst machen" — every genre's leadDensity is now
    // 0, so BioComposer never emits a .lead-role note to measure; tameLeadPitch
    // itself stays covered by testTameLeadPitchFoldsPiercingHighsDownKeepingPitchClass
    // above, and the "no auto-lead" invariant is asserted once, canonically, in
    // MusicStyleTests.testNoGenreAutoGeneratesLeadNotes).

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

    // MARK: - Rhythmic diversity (task #79 Slice A — per-genre flavor overlay)

    /// The founder's ask: four-on-floor genres must NOT all render the same loop.
    /// With identical seed/energy/coherence, at least two of the six diverge in
    /// `drumSteps`, while the archetype core (kick-every-beat) still holds for both.
    func testFourOnFloorGenresAreRhythmicallyDistinct() {
        let fourOnFloor: [MusicStyle] = [.disco, .eighties, .earlySynth,
                                         .futuristic, .psytrance, .synthwave]
        var patterns: [[[Bool]]] = []
        for style in fourOnFloor {
            let comp = BioComposer.compose(input(coherence: 0.4, hr: 100, seed: 0x1234, style: style))
            // Core signature intact for every genre — the overlay never dissolves it.
            for s in [0, 4, 8, 12] {
                XCTAssertTrue(comp.drumSteps[0][s], "\(style) keeps four-on-floor kick on step \(s)")
            }
            patterns.append(comp.drumSteps)
        }
        // Concrete pair: disco (dense hats, ghost @3) vs earlySynth (sparse hats,
        // ghost @9) must differ.
        let disco = patterns[0]
        let earlySynth = patterns[2]
        XCTAssertNotEqual(disco, earlySynth,
                          "disco and earlySynth must not share bit-identical drumSteps")
        // And at least two DISTINCT drum patterns exist across the whole group.
        let distinct = Set(patterns.map { "\($0)" })
        XCTAssertGreaterThanOrEqual(distinct.count, 2,
                                    "the six four-on-floor genres must not collapse to one loop")
    }

    /// Determinism must survive the flavor overlay: same seed + bio + genre → identical
    /// output on every call (overlay is declarative, draws no RNG).
    func testFourOnFloorFlavorIsDeterministic() {
        for style in [MusicStyle.disco, .eighties, .earlySynth,
                      .futuristic, .psytrance, .synthwave] {
            let a = BioComposer.compose(input(coherence: 0.35, hr: 108, seed: 0xABCD, style: style))
            let b = BioComposer.compose(input(coherence: 0.35, hr: 108, seed: 0xABCD, style: style))
            XCTAssertEqual(a.drumSteps, b.drumSteps, "\(style): drums must reproduce exactly")
            XCTAssertEqual(a.drumAccents, b.drumAccents, "\(style): accents must reproduce exactly")
            XCTAssertEqual(a, b, "\(style): the whole take must be deterministic")
        }
    }

    // MARK: - Rhythmic diversity (task #79 Slice B — backbeat / rock family)

    /// The same founder ask extended to the six backbeat genres: they must not all
    /// render one loop. With identical seed/energy/coherence at least two diverge in
    /// `drumSteps`, while the archetype core (snare on 2 & 4) still holds for every one.
    func testBackbeatGenresAreRhythmicallyDistinct() {
        let backbeat: [MusicStyle] = [.rock, .punk, .rocknroll, .heavyMetal, .jazz, .oriental]
        var patterns: [[[Bool]]] = []
        for style in backbeat {
            let comp = BioComposer.compose(input(coherence: 0.4, hr: 100, seed: 0x1234, style: style))
            // Core signature intact for every genre — the overlay never dissolves the backbeat.
            XCTAssertTrue(comp.drumSteps[1][4] && comp.drumSteps[1][12],
                          "\(style) keeps the snare backbeat on 2 & 4")
            patterns.append(comp.drumSteps)
        }
        // Concrete pair: rock (perc ghost @6) vs jazz (sparse hats, ghost @5) must differ.
        XCTAssertNotEqual(patterns[0], patterns[4],
                          "rock and jazz must not share bit-identical drumSteps")
        // All six carry a distinct perc-ghost step → all six patterns are distinct.
        let distinct = Set(patterns.map { "\($0)" })
        XCTAssertEqual(distinct.count, backbeat.count,
                       "the six backbeat genres must each render a distinct loop")
    }

    /// Determinism must survive the backbeat overlay too: same seed + bio + genre →
    /// identical output every call (the overlay is declarative, draws no RNG).
    func testBackbeatFlavorIsDeterministic() {
        for style in [MusicStyle.rock, .punk, .rocknroll, .heavyMetal, .jazz, .oriental] {
            let a = BioComposer.compose(input(coherence: 0.35, hr: 108, seed: 0xABCD, style: style))
            let b = BioComposer.compose(input(coherence: 0.35, hr: 108, seed: 0xABCD, style: style))
            XCTAssertEqual(a.drumSteps, b.drumSteps, "\(style): drums must reproduce exactly")
            XCTAssertEqual(a.drumAccents, b.drumAccents, "\(style): accents must reproduce exactly")
            XCTAssertEqual(a, b, "\(style): the whole take must be deterministic")
        }
    }

    // MARK: - Rhythmic diversity (task #79 Slice C — offbeat & half-time archetypes)

    /// Offbeat (skank) genres must each render a distinct loop while the skank perc
    /// signature (stabs on 2/6/10/14) survives for every one.
    func testOffbeatGenresAreRhythmicallyDistinct() {
        let offbeat: [MusicStyle] = [.ska, .rocksteady, .klezmer]
        var patterns: [[[Bool]]] = []
        for style in offbeat {
            let comp = BioComposer.compose(input(coherence: 0.4, hr: 100, seed: 0x1234, style: style))
            // The skank signature is never removed by the overlay.
            for s in [2, 6, 10, 14] {
                XCTAssertTrue(comp.drumSteps[5][s], "\(style) keeps the skank perc stab on step \(s)")
            }
            patterns.append(comp.drumSteps)
        }
        let distinct = Set(patterns.map { "\($0)" })
        XCTAssertEqual(distinct.count, offbeat.count,
                       "the three offbeat genres must each render a distinct loop")
    }

    /// Half-time genres must each render a distinct loop while the snare-on-3 lean
    /// (step 8) survives for every one.
    func testHalfTimeGenresAreRhythmicallyDistinct() {
        let halfTime: [MusicStyle] = [.doom, .vaporwave, .sciFi]
        var patterns: [[[Bool]]] = []
        for style in halfTime {
            let comp = BioComposer.compose(input(coherence: 0.4, hr: 100, seed: 0x1234, style: style))
            XCTAssertTrue(comp.drumSteps[1][8], "\(style) keeps the half-time snare on beat 3")
            patterns.append(comp.drumSteps)
        }
        let distinct = Set(patterns.map { "\($0)" })
        XCTAssertEqual(distinct.count, halfTime.count,
                       "the three half-time genres must each render a distinct loop")
    }

    /// Determinism must hold for the offbeat & half-time overlays too.
    func testOffbeatAndHalfTimeFlavorIsDeterministic() {
        for style in [MusicStyle.ska, .rocksteady, .klezmer, .doom, .vaporwave, .sciFi] {
            let a = BioComposer.compose(input(coherence: 0.35, hr: 108, seed: 0xABCD, style: style))
            let b = BioComposer.compose(input(coherence: 0.35, hr: 108, seed: 0xABCD, style: style))
            XCTAssertEqual(a, b, "\(style): the whole take must be deterministic")
        }
    }

    /// Canonical durable guard for the founder's "die Genres klingen gleich"
    /// complaint at the RHYTHM level (task #79): NO two genres that share a beat
    /// archetype may render identical drums for the same seed/bio. The rhythm-axis
    /// twin of testEveryGenreHasADistinctMusicalIdentity (which guards the harmony
    /// axis). Derived from `beatArchetype` — not a hardcoded genre list — so a genre
    /// added to any archetype in future is automatically guarded: if it lacks its own
    /// distinct GenreFlavor and collapses onto a sibling's loop, this fails. The two
    /// signature-beat genres (dubTechno/trap, bespoke builders) and the drum-free
    /// contemplative genres are correctly out of scope (they don't share a builder).
    /// ⛔ #1012 — THIS DEMANDED A DISTINCT GRID FROM *EVERY* GENRE IN A SHARED ARCHETYPE, AND
    /// NINE OF THEM DELIBERATELY HAVE NO FLAVOUR. `beatFlavor` falls through to `.neutral` for
    /// `acidTechno`, `upliftingTrance`, `techHouse`, `minimalTechno`, `deepTech`, `darkMinimal`
    /// and `psyProgHouse` (all `.fourOnFloor`), for `detroitTechno` (`.backbeat`) and for
    /// `deepHouse` (`.offbeat`) — so seven four-on-floor genres produce the SAME grid and this
    /// case failed on the first collision. Red for a long time, invisible behind
    /// `full-tests.yml`'s `continue-on-error`.
    ///
    /// ⭐ AND THE TEST WAS THE DEFECT, NOT THE CODE — its own failure message asked for the fix
    /// the source explicitly refuses. `MusicStyle.beatFlavor`'s doc says giving those genres a
    /// hat texture and a ghost step would be "fiction dressed as design", because since
    /// #166/#167 removed the drum voices the whole `GenreFlavor` output reaches NO voice:
    /// `drumSteps` is read only by `Project` persistence and one `BioVariationMaze` density
    /// metric. A test that demands tuning data for a track nobody can hear is asking for the
    /// placebo this repo bans. What actually separates those nine from their siblings is
    /// `chordArticulation`, mode, voicing and register — none of which live in `drumSteps`.
    ///
    /// ⚠️ SO THE GUARD IS NARROWED, NOT DELETED. The claim that still means something is the
    /// one the source itself makes: within an archetype, the genres that DO carry a flavour
    /// must not collide — their `percGhostStep`s are chosen to be collision-free by
    /// construction, and that construction is worth pinning. Named "grids", not "drums",
    /// because nothing renders drums.
    func testFlavouredGenresSharingAnArchetypeRenderDistinctGrids() {
        let sharedArchetypes: [MusicStyle.BeatArchetype] = [.fourOnFloor, .backbeat, .offbeat, .halfTime]
        for archetype in sharedArchetypes {
            let genres = MusicStyle.allCases.filter {
                $0.beatArchetype == archetype && $0.beatFlavor != .neutral
            }
            guard genres.count > 1 else { continue }
            var seen: [String: MusicStyle] = [:]
            for style in genres {
                let comp = BioComposer.compose(input(coherence: 0.4, hr: 100, seed: 0x1234, style: style))
                let fingerprint = "\(comp.drumSteps)"
                if let other = seen[fingerprint] {
                    XCTFail("""
                    \(style) and \(other) (both \(archetype)) render an identical grid.

                    Both carry a GenreFlavor, so their `percGhostStep`s were supposed to be \
                    collision-free by construction — pick a free step for the newer one. \
                    (An UNFLAVOURED genre colliding here is expected and out of scope; see \
                    the ⛔ block above.)
                    """)
                }
                seen[fingerprint] = style
            }
            XCTAssertEqual(seen.count, genres.count,
                           "all \(genres.count) flavoured \(archetype) genres must render distinct grids")
        }
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
        let a = BioComposer.compose(input(coherence: 0.2, hr: 110, seed: 7, style: .punk))
        let b = BioComposer.compose(input(coherence: 0.2, hr: 110, seed: 7, style: .punk))
        XCTAssertEqual(a.drumSteps, b.drumSteps)
        let settled = BioComposer.compose(input(coherence: 0.9, hr: 60, seed: 7, style: .punk))
        for t in 0..<8 {
            for s in 0..<16 where settled.drumSteps[t][s] {
                XCTAssertTrue(a.drumSteps[t][s],
                              "settled hit (\(t),\(s)) must exist in the energetic take too")
            }
        }
    }

    func testSameArchetypeGenresKeepDistinctBeatsWhenCalm() {
        // Founder 2026-07-22: browsing genres, "nach kurzer Zeit klingt alles wie
        // classic." Within a shared archetype the calm strip used to leave only a
        // one-step perc-ghost difference between genres. The genre `hatRate` now gives
        // each a distinct calm-surviving closed-hat texture, so two four-on-floor
        // genres are audibly different EVEN at high coherence (calm 0.95 → spacious).
        let calm: Float = 0.95
        func drums(_ style: MusicStyle) -> [[Bool]] {
            BioComposer.compose(input(coherence: calm, hr: 55, seed: 0x5EED, style: style)).drumSteps
        }
        let disco = drums(.disco)        // hatRate .offbeat → hats on 2/6/10/14
        let psy   = drums(.psytrance)    // hatRate .sixteenth → hats on every 16th
        // track 2 = closed hats. The two calm takes must NOT share a hat row…
        XCTAssertNotEqual(disco[2], psy[2],
            "same-archetype genres must keep distinct hat textures when calm (not converge)")
        // …and the full drum grid differs too.
        XCTAssertNotEqual(disco, psy,
            "a calm disco and a calm psytrance must not render the same beat")
        // The hat signature is deterministic — same input reproduces exactly.
        XCTAssertEqual(disco, drums(.disco), "genre hat signature is deterministic")
    }

    func testGenreHatStaysEnergyReactiveOnTopOfSignature() {
        // Task #82: the genre hat signature is the CALM base, but a driving body must
        // still densify the hats (north-star "the music changes with the body"). The
        // energy overlay is purely additive, so the calm hat row is a subset of the
        // aroused hat row, and for a genre with room to grow it is STRICTLY busier.
        // track 2 = closed hats; applyHatRate owns that row (no seed dependence).
        func hats(_ style: MusicStyle, coherence: Float, hr: Float) -> [Bool] {
            BioComposer.compose(input(coherence: coherence, hr: hr, seed: 0xBEA7,
                                      style: style)).drumSteps[2]
        }
        // disco = .offbeat: calm hats on 2/6/10/14; aroused adds 0 & 8.
        let calmHats    = hats(.disco, coherence: 0.95, hr: 55)   // spacious, low energy
        let arousedHats = hats(.disco, coherence: 0.20, hr: 118)  // not spacious, high energy
        for s in 0..<16 where calmHats[s] {
            XCTAssertTrue(arousedHats[s],
                          "calm hat step \(s) must survive into the aroused take (additive)")
        }
        let calmCount    = calmHats.filter { $0 }.count
        let arousedCount = arousedHats.filter { $0 }.count
        XCTAssertGreaterThan(arousedCount, calmCount,
                             "a driving body must make the disco hats busier, not identical")
        // Deterministic — same bio input reproduces the same hat row exactly.
        XCTAssertEqual(arousedHats, hats(.disco, coherence: 0.20, hr: 118),
                       "energy-reactive hat row is deterministic per input")
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

    func testDubBassStaysHeldWhateverTheBodyDoes() {
        // Founder 2026-07-11 ("Kompositionen müssen nicht statisch im Takt sein …
        // am Herzschlag orientierte Rhythmen") SUPERSEDED the 2026-07-09 "dub Fläche
        // never densifies" doctrine — see `heartbeatOnsets`'s own doc-comment: an
        // aroused body re-articulates the PAD onsets (never the rejected exposed
        // wave-lead), same resolution already accepted for selfObservation/
        // stillMeditation in `testSustainedFlächeIsStillWhenCalm_AliveWhenAroused`.
        // What IS still pinned for dub specifically (`quarterAnchorBass` is "SCOPED
        // TO TRAP ONLY") is the BASS: it stays the held root regardless of arousal.
        let calm = BioComposer.compose(input(coherence: 0.95, hr: 70, style: .dubTechno))
        let busy = BioComposer.compose(input(coherence: 0.05, hr: 70, style: .dubTechno))
        let calmBass = calm.notes.filter { $0.role == .bass }
        let busyBass = busy.notes.filter { $0.role == .bass }
        XCTAssertEqual(busyBass.count, calmBass.count, "dub bass note count is unaffected by arousal")
        XCTAssertEqual(Set(busyBass.map(\.startStep)), Set(calmBass.map(\.startStep)),
                       "dub bass onsets stay at the section downbeats whatever the body does")
        // The pad, however, is meant to gain onsets as the body activates (heartbeatOnsets).
        XCTAssertGreaterThan(busy.notes.count, calm.notes.count,
                             "an aroused body re-articulates the dub pad — busier is not the same as calm")
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

    func testComposerModeDerivesFromTempoLock() {
        // M1 Flow/Loop switch: the two modes are ONE truth — the tempo lock. Loop
        // (locked) = studioLocked (fixed BPM for production); Flow (unlocked) =
        // flowFree (tempo follows the body). This mapping is what the live compose
        // path + the project save now use instead of a hardcoded .flowFree, so the
        // composer intent, the saved mode and the lock UI can never disagree.
        XCTAssertEqual(ComposerMode(locked: true), .studioLocked,
                       "Loop (tempo locked) = studioLocked, a fixed BPM for production")
        XCTAssertEqual(ComposerMode(locked: false), .flowFree,
                       "Flow (tempo free) = flowFree, tempo follows the body")
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

    // FOUNDER-EAR-CHECK CANDIDATE: the [2,8] bound predates `heartbeatOnsets` (2026-07-11,
    // "Kompositionen müssen nicht statisch im Takt sein" — see
    // testDubBassStaysHeldWhateverTheBodyDoes / testSustainedFlächeIsStillWhenCalm_AliveWhenAroused
    // for the same principle already accepted). selfObservation's whole-bar single-chord
    // journey (16-step section, vs. dub/trap's 8-step) reaches up to 25 notes at full
    // arousal — a real, reproducible ceiling (exhaustive 45–130 BPM × 0–1 coherence sweep),
    // not a rare edge case (~35% of the grid exceeds the old 8-note bound). Widened to the
    // PROVEN range rather than silently loosened to "whatever passes" — but 25 simultaneous
    // re-articulating tones for a genre documented as "a TRUE DRONE … maximally still" is
    // a genuine taste question the code can't answer. Flagged for founder ear-check
    // alongside the #77 depth knobs; if it sounds too busy, the Sources fix is scaling
    // `heartbeatOnsets`'s stride selection to `secLen` (dsp-reviewer required).
    func testAmbientNoteCountStaysInBounds() {
        for hr in stride(from: Float(45), through: 130, by: 5) {
            for coh in stride(from: Float(0), through: 1, by: 0.1) {
                let comp = BioComposer.compose(
                    input(coherence: coh, hr: hr, style: .selfObservation, mode: .flowFree))
                XCTAssertGreaterThanOrEqual(comp.notes.count, 2)
                XCTAssertLessThanOrEqual(comp.notes.count, 25)
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
                let aroused = BioComposer.compose(input(coherence: 0.2, hr: 115, seed: seed, style: style))
                let settled = BioComposer.compose(input(coherence: 0.95, hr: 115, seed: seed, style: style))
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

    // MARK: - Genre identity survives the calm-convergence (founder 2026-07-22)

    /// Founder (build 2440): "bei den Genres kommt erst eine individuelle Variation
    /// und dann klingt plötzlich alles gleich." The default-on chord journey is
    /// genre-agnostic and, once the body settles, picks the same expected functional
    /// progression for every genre in the same key — so all genres collapsed to the
    /// same harmony as the listener relaxed. The genre-identity crossfade in
    /// `composeHarmonic` locks the CALM harmony to each genre's OWN authored
    /// progression: calm == a calm version of THIS genre, not a generic cycle.
    /// The journey stays untouched in the aroused regime.
    func testGenreHarmonyIdentitySurvivesCalmConvergence() {
        let key = MusicalKey(root: 0, scale: .dorian)
        // .eighties is non-sustained with a NON-functional pop progression
        // ([0,4,5,3] = I–V–vi–IV) that the pure functional journey would never pick.
        func bassRootClasses(seed: UInt64, coherence: Float) -> [Int] {
            let inp = BioComposer.Input(
                heartRateBPM: 55, hrvNormalized: 0.5, coherence: coherence,
                breathPhase: 0, breathDepth: 0.5, key: key, style: .eighties,
                mode: .flowFree, lockedTempo: 100, seed: seed, structureSeed: seed,
                progressionPhase: 0, suggestJourney: true)
            return BioComposer.compose(inp).notes
                .filter { $0.role == .bass }
                .sorted { $0.startStep < $1.startStep }
                .map { ((($0.pitch % 12) + 12) % 12) }
        }
        // At FULL calm the crossfade anchors harmony to the genre's authored
        // progression, which is seed-INDEPENDENT → two different seeds trace the SAME
        // root motion. Without the crossfade the seeded journey would vary here.
        let calmA = bassRootClasses(seed: 0xA1, coherence: 1.0)
        let calmB = bassRootClasses(seed: 0xB2, coherence: 1.0)
        XCTAssertFalse(calmA.isEmpty, "calm harmony should sound")
        XCTAssertEqual(calmA, calmB,
            "at full coherence the harmony IS the genre's authored progression — a stable genre signature, not a generic journey")
        // AROUSED regime (ultrascan 2026-07-22 step 2 — anchor floor 0.34): even fully
        // aroused, the FIRST section root is anchored to THIS genre's progression (k≥1),
        // so browsing genres in an aroused state no longer collapses onto one free journey.
        let arousedA = bassRootClasses(seed: 0xA1, coherence: 0.0)
        let arousedB = bassRootClasses(seed: 0xB2, coherence: 0.0)
        XCTAssertEqual(arousedA.first, arousedB.first,
            "aroused, the genre-anchored FIRST root is seed-independent (floor keeps genre identity)")
        // …but the NON-anchored tail still explores per seed, so variation survives.
        XCTAssertNotEqual(arousedA, arousedB,
            "aroused, the free tail beyond the anchor still varies per seed (variation preserved)")
        // Polarity: same seed, the calm harmony DIFFERS from the aroused harmony — the
        // fix is coherence-active, converging to the genre home as the body settles.
        XCTAssertNotEqual(bassRootClasses(seed: 0xA1, coherence: 1.0),
                          bassRootClasses(seed: 0xA1, coherence: 0.0),
            "the crossfade moves the calm harmony toward the genre progression")
    }

    // MARK: - Genre chord articulation (2026-07-22 — audible genre rhythm)
    //
    // The 13 sustained genres shared ONE genre-blind heartbeat onset pattern, so going
    // through the genres "everything sounded the same". chordOnsets gives each genre a
    // distinct chord-articulation grid on the AUDIBLE pad (drums are muted). These lock
    // the grids, the byte-identical `.sustained` delegation, and cross-genre distinctness.

    private func starts(_ onsets: [(start: Int, len: Int)]) -> [Int] { onsets.map { $0.start } }

    func testChordOnsets_skankHitsOnlyOffbeatEighths() {
        let o = BioComposer.chordOnsets(secStart: 0, secLen: 16, energy: 0, syncopation: 0, articulation: .skank)
        XCTAssertEqual(starts(o), [2, 6, 10, 14], "reggae/ska skank must land on the offbeat 8ths")
    }

    func testChordOnsets_stabHitsOnTheBeats_andFillsWhenAroused() {
        let calm = BioComposer.chordOnsets(secStart: 0, secLen: 16, energy: 0, syncopation: 0, articulation: .stab)
        XCTAssertEqual(starts(calm), [0, 4, 8, 12], "disco stab sits on the beats when calm")
        let up = BioComposer.chordOnsets(secStart: 0, secLen: 16, energy: 0.9, syncopation: 0, articulation: .stab)
        XCTAssertEqual(starts(up), [0, 2, 4, 6, 8, 10, 12, 14], "an aroused body drives a four-on-floor 8th pulse")
    }

    func testChordOnsets_compEmphasisesTwoAndFour() {
        let o = BioComposer.chordOnsets(secStart: 0, secLen: 16, energy: 0, syncopation: 0, articulation: .comp)
        XCTAssertEqual(starts(o), [4, 12], "jazz/rock comp lands on beats 2 & 4 when calm")
    }

    func testChordOnsets_sustainedDelegatesToHeartbeat_byteIdentical() {
        for e: Float in [0.0, 0.5, 0.7, 0.9] {
            let art = BioComposer.chordOnsets(secStart: 0, secLen: 16, energy: e, syncopation: 0.3, articulation: .sustained)
            let beat = BioComposer.heartbeatOnsets(secStart: 0, secLen: 16, energy: e, syncopation: 0.3)
            XCTAssertEqual(art.map { [$0.start, $0.len] }, beat.map { [$0.start, $0.len] },
                           "the meditative/ambient calm-is-still core must be byte-identical (energy \(e))")
        }
    }

    func testChordOnsets_barAlignedPhaseAcrossOffsetSection() {
        // A section starting mid-bar keeps the absolute-step (bar-aligned) phase.
        let o = BioComposer.chordOnsets(secStart: 4, secLen: 8, energy: 0, syncopation: 0, articulation: .skank)
        XCTAssertEqual(starts(o), [6, 10], "skank stays on the absolute offbeat grid, not relative to secStart")
    }

    func testChordOnsets_neverOverlapAndStayInSection() {
        for art in [MusicStyle.ChordArticulation.skank, .stab, .comp] {
            for e: Float in [0.0, 0.9] {
                let o = BioComposer.chordOnsets(secStart: 0, secLen: 16, energy: e, syncopation: 0, articulation: art)
                for i in o.indices {
                    XCTAssertGreaterThanOrEqual(o[i].start, 0)
                    XCTAssertLessThanOrEqual(o[i].start + o[i].len, 16, "onset stays inside the section")
                    if i + 1 < o.count {
                        XCTAssertLessThanOrEqual(o[i].start + o[i].len, o[i + 1].start, "chops must not overlap")
                    }
                }
            }
        }
    }

    func testChordOnsets_deterministic() {
        let a = BioComposer.chordOnsets(secStart: 0, secLen: 16, energy: 0.55, syncopation: 0.2, articulation: .comp)
        let b = BioComposer.chordOnsets(secStart: 0, secLen: 16, energy: 0.55, syncopation: 0.2, articulation: .comp)
        XCTAssertEqual(a.map { [$0.start, $0.len] }, b.map { [$0.start, $0.len] })
    }

    func testMetricAccent_hierarchyDownbeatStrongestOffbeatSoftest() {
        // The metrical hierarchy that makes chops read as intentional, not robotic.
        XCTAssertEqual(BioComposer.metricAccent(step: 0), 1.0, accuracy: 0.0001, "downbeat is strongest")
        XCTAssertEqual(BioComposer.metricAccent(step: 8), 0.95, accuracy: 0.0001, "beat 3")
        XCTAssertEqual(BioComposer.metricAccent(step: 4), 0.92, accuracy: 0.0001, "beat 2")
        XCTAssertEqual(BioComposer.metricAccent(step: 12), 0.92, accuracy: 0.0001, "beat 4")
        XCTAssertEqual(BioComposer.metricAccent(step: 2), 0.86, accuracy: 0.0001, "offbeat is softest")
        // Strict ordering downbeat > beat3 > beats2/4 > offbeat.
        XCTAssertGreaterThan(BioComposer.metricAccent(step: 0), BioComposer.metricAccent(step: 8))
        XCTAssertGreaterThan(BioComposer.metricAccent(step: 8), BioComposer.metricAccent(step: 4))
        XCTAssertGreaterThan(BioComposer.metricAccent(step: 4), BioComposer.metricAccent(step: 2))
    }

    func testMetricAccent_boundedAndBarAligned() {
        for step in 0..<64 {
            let a = BioComposer.metricAccent(step: step)
            XCTAssertGreaterThanOrEqual(a, 0.86)
            XCTAssertLessThanOrEqual(a, 1.0)
            // Bar-aligned (period 16): step and step+16 accent identically.
            XCTAssertEqual(a, BioComposer.metricAccent(step: step + 16), accuracy: 0.0001)
        }
        // Negative steps normalize into the bar (locks the ((step%16)+16)%16 path).
        XCTAssertEqual(BioComposer.metricAccent(step: -14), BioComposer.metricAccent(step: 2), accuracy: 0.0001)
        XCTAssertEqual(BioComposer.metricAccent(step: -16), BioComposer.metricAccent(step: 0), accuracy: 0.0001)
    }

    private func chopInput(_ style: MusicStyle) -> BioComposer.Input {
        input(coherence: 0.4, hr: 90, seed: 0x5EED, style: style)
    }

    /// The distinct steps where a chord voice starts and NO bass note does.
    ///
    /// Why it separates chopped from held. `appendBass` walks from each section start, so every
    /// section start carries a bass note; a HELD pad starts ONLY at section starts, so its whole
    /// start set is covered and this difference is EMPTY. A chop puts onsets between the bass
    /// notes, so it is not. Progression-length independent — unlike a note count it cannot tie,
    /// and unlike a note count it cannot be satisfied by simply having more chord tones.
    ///
    /// The other `role: .harmony` layer, the inner pulse, drops out rather than contaminating:
    /// its stride is `pulseGap` (`BioComposer.swift`, computed from `busy` and `densityScale` —
    /// it is 8 at this bio state, not a fixed 4), which exceeds every section length here, so it
    /// emits one note per section at `secStart` — exactly where the walking bass already is.
    ///
    /// Honest about what it does NOT see: a chop that happens to land on a bass step is
    /// invisible. That is why jazz's evidence below is `{2, 10}`, the two sections its comp grid
    /// misses, and not its real comp hits on 4 and 12 — those coincide with bass notes. The
    /// measure is a lower bound on the chopping, which is the safe direction for a
    /// must-be-non-empty assertion.
    private func chordStartsOffTheBassGrid(_ style: MusicStyle) -> Set<Int> {
        let notes = BioComposer.compose(chopInput(style)).notes
        let bass = Set(notes.filter { $0.role == .bass }.map(\.startStep))
        let chord = Set(notes.filter { $0.role == .harmony }.map(\.startStep))
        return chord.subtracting(bass)
    }

    func testCompose_rhythmicGenresChopChords_notInertThroughPipeline() {
        // THE inert-code guard (a review caught the first cut wiring chordOnsets only into a
        // branch no rhythmic genre reaches, making it a no-op).
        //
        // THIS TEST USED TO COUNT NOTES FOR ALL THREE GENRES, and that measure was broken — it
        // was red for months against working music. rocksteady shares classical's prog.count,
        // sectionLen AND chordTones.count, so bass, pulse and pad counts all match and the
        // totals TIE; the assertion read "articulation is inert" while rocksteady's chops were
        // landing on 2/6/10/14, the complete offbeat grid. Its own comment had already warned
        // that an arithmetic tie was possible. Worse, the count was blind in the OTHER direction
        // too: jazz PASSED it throughout the period when its pad was a held chord byte-identical
        // to classical's, because 4 chord tones outnumber 3. That real defect (#172) had to be
        // found by a separate diagnosis file; the rhythm measure below would have caught it.
        //
        // All three genres now use the rhythm measure — see `chordStartsOffTheBassGrid`. A first
        // draft of this fix kept the note count for disco, on the theory that the pulse layer
        // would contaminate the rhythm measure there; a review showed that backwards on both
        // halves. Disco's pulse sits on {0,5,10}, a subset of its bass, so it contaminates
        // nothing — and the count it would have kept is GREEN for a held disco (21 > 20, on 4
        // chord tones and 6 bass notes against classical's 3 and 4), i.e. blind to exactly the
        // regression it names. The same arithmetic accident as the jazz blindness above.
        let census = [MusicStyle.disco, .jazz, .rocksteady]
            .map { "\($0)=\(chordStartsOffTheBassGrid($0).sorted())" }.joined(separator: " ")
        for rhythmic in [MusicStyle.disco, .jazz, .rocksteady] {
            // Carry the MEASUREMENT into the failure text, not just the verdict — the CI reveal
            // prints only a test's NAME, so a bare assertion says nothing about WHICH genre.
            XCTAssertFalse(chordStartsOffTheBassGrid(rhythmic).isEmpty,
                "\(rhythmic) must chop its chords in production (genre rhythm is not inert), "
                + "not fall through to a chord that only restates the bass — \(census)")
        }
    }

    func testCompose_heldGenreHasNoChordOnsetsOffTheBassGrid() {
        // The negative control for the test above, deliberately its OWN name so a surprise here
        // is diagnosable instead of masking the positives: if this goes red, "off the bass grid"
        // has stopped discriminating and the two assertions above are no longer evidence of
        // anything. classical is `.sustained` on the non-arp path — one held chord per section,
        // starting exactly where that section's walking bass begins, and its pulse stride
        // exceeds the 4-step sections so that lands on the same steps — difference set empty.
        XCTAssertEqual(chordStartsOffTheBassGrid(.classical), [],
                       "classical is the held baseline: its chords may not start off the bass grid")
    }

    func testCompose_heldGenresStaySingleOnset_perChordSection() {
        // classical/doom keep the legato held identity — the articulation fix must not
        // accidentally turn the calm/held genres rhythmic.
        let doom = BioComposer.compose(input(coherence: 0.4, hr: 90, seed: 0x5EED, style: .doom)).notes.count
        let disco = BioComposer.compose(input(coherence: 0.4, hr: 90, seed: 0x5EED, style: .disco)).notes.count
        XCTAssertLessThan(doom, disco, "a held genre (doom) must stay sparser than a chopped one (disco)")
    }

    func testChordArticulation_mappedFromArchetype_andGenresDiffer() {
        XCTAssertEqual(MusicStyle.ska.chordArticulation, .skank)
        XCTAssertEqual(MusicStyle.disco.chordArticulation, .stab)
        XCTAssertEqual(MusicStyle.jazz.chordArticulation, .comp)
        XCTAssertEqual(MusicStyle.stillMeditation.chordArticulation, .sustained)
        // Three genres → three measurably different chord grids at the SAME bio state.
        let bio: Float = 0.3
        let skank = starts(BioComposer.chordOnsets(secStart: 0, secLen: 16, energy: bio, syncopation: 0, articulation: MusicStyle.ska.chordArticulation))
        let stab  = starts(BioComposer.chordOnsets(secStart: 0, secLen: 16, energy: bio, syncopation: 0, articulation: MusicStyle.disco.chordArticulation))
        let comp  = starts(BioComposer.chordOnsets(secStart: 0, secLen: 16, energy: bio, syncopation: 0, articulation: MusicStyle.jazz.chordArticulation))
        XCTAssertNotEqual(skank, stab)
        XCTAssertNotEqual(stab, comp)
        XCTAssertNotEqual(skank, comp)
    }
}
