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

    func testSustainedDroneStaysStill_evenWhenTheBodyIsAroused() {
        // Founder 2026-07-07: "echte Musik … alles reduzieren dafür qualitativ
        // hochwertiger" + "die Trancepads im Hintergrund sind teilweise schon sehr
        // gut". A HIGH heart rate + LOW coherence = an aroused body (calm ≤ 0.6),
        // exactly the state that used to switch on the busy 8th/16th inner pulse +
        // walking bass (device log 1783424951: 27 notes). The meditative Fläche must
        // now stay a still, sustained drone regardless of arousal — the good pad
        // held, the noodle gone.
        for style in [MusicStyle.selfObservation, .esotericMeditation] {
            let comp = BioComposer.compose(
                input(coherence: 0.05, hr: 130, style: style, mode: .flowFree))
            let pitched = comp.notes
            // Reduced: a held chord (≤4 tones) + one bass, not a 27-note noodle.
            XCTAssertLessThanOrEqual(pitched.count, 8,
                                     "\(style): a drone is a handful of held notes, not a pulse grid")
            // Exactly one grounding bass root — no walking line.
            let bass = pitched.filter { $0.role == .bass }
            XCTAssertEqual(bass.count, 1, "\(style): one sustained bass root, not a walking line")
            // NOTHING is a short 8th/16th stab — every note is sustained (the pulse
            // layer produced lengthSteps 1–2; a held pad spans most of the bar).
            for n in pitched {
                XCTAssertGreaterThanOrEqual(n.lengthSteps, 4,
                    "\(style): sustained drone has no short pulse notes (got len \(n.lengthSteps))")
            }
        }
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

    func testSustainedIsExactlyTheCuratedRoster() {
        // Founder 2026-07-09: every OFFERED genre is a pure sustained Fläche;
        // the retired (unoffered) genres keep their old melodic profiles.
        for style in MusicStyle.allCases {
            let expected = MusicStyle.curated.contains(style)
            XCTAssertEqual(style.harmonicProfile.sustained, expected,
                           "\(style): sustained-Fläche flag ⟺ curated roster membership")
        }
    }

    func testCuratedGenresArePureBarTightFlächen() {
        // The founder's deal (2026-07-09): no lead melody anywhere in the offered
        // roster, only held pad/bass material — and every note ends exactly inside
        // the bar so the WAV loop stays tight for post-processing. Checked across
        // seeds AND body states (an aroused body must not re-awaken a lead).
        for style in MusicStyle.curated {
            for seed in UInt64(1)...10 {
                for (coh, hr) in [(Float(0.9), Float(58)), (Float(0.1), Float(120))] {
                    let comp = BioComposer.compose(
                        input(coherence: coh, hr: hr, seed: seed, style: style))
                    XCTAssertFalse(comp.notes.isEmpty, "\(style): a Fläche still sounds")
                    for n in comp.notes {
                        XCTAssertNotEqual(n.role, .lead,
                            "\(style) seed \(seed): no lead melody in a pure Fläche")
                        XCTAssertGreaterThanOrEqual(n.lengthSteps, 4,
                            "\(style) seed \(seed): Flächen hold — no short stabs (len \(n.lengthSteps))")
                        XCTAssertLessThanOrEqual(n.startStep + n.lengthSteps, BioComposer.stepCount,
                            "\(style) seed \(seed): note overruns the bar — loop not tight")
                    }
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
