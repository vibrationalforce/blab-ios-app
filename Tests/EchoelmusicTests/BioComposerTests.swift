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
        XCTAssertFalse(comp.hasDrums, "self-observation stays ambient — melody only")
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

    func testDubBusierBodyAddsChordStabs() {
        // Low coherence + high HR → both offbeats stab (more notes) than calm.
        let calm = BioComposer.compose(input(coherence: 0.95, hr: 70, style: .dubTechno))
        let busy = BioComposer.compose(input(coherence: 0.05, hr: 70, style: .dubTechno))
        XCTAssertGreaterThan(busy.notes.count, calm.notes.count,
                             "busier body → more dub chord stabs")
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
                       "self-observation window (50–100) keeps 75")
    }

    func testFlowTempoFollowsHeart() {
        XCTAssertEqual(BioComposer.tempo(for: input(hr: 128, mode: .flowFree)), 128,
                       "Flow mode follows the heart")
        XCTAssertEqual(BioComposer.tempo(for: input(hr: 220, mode: .flowFree)), 160,
                       "Flow tempo is clamped to a musical ceiling")
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
}
