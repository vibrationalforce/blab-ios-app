// BioComposerTests.swift
// Echoel — the generative core: biodata → in-key melody + tempo. Asserts the
// musical invariants (always in key, density/contour respond to bio) and exact
// determinism from a seed, without hand-computing the RNG.

import XCTest
@testable import Echoelmusic

final class BioComposerTests: XCTestCase {

    private func input(coherence: Float = 0.5, hr: Float = 70,
                       breathPhase: Float = 0, seed: UInt64 = 0x5EED,
                       key: MusicalKey = MusicalKey(root: 0, scale: .minor),
                       mode: ComposerMode = .studioLocked) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: hr, hrvNormalized: 0.5, coherence: coherence,
                          breathPhase: breathPhase, breathDepth: 0.5, key: key,
                          mode: mode, lockedTempo: 75, seed: seed)
    }

    func testDeterministicForSameInput() {
        let a = BioComposer.compose(input())
        let b = BioComposer.compose(input())
        XCTAssertEqual(a, b, "same inputs + seed must produce identical music")
    }

    func testDifferentSeedChangesMelody() {
        let a = BioComposer.compose(input(seed: 1))
        let b = BioComposer.compose(input(seed: 2))
        XCTAssertNotEqual(a.notes, b.notes, "a different seed should vary the line")
    }

    func testEveryNoteIsInKey() {
        for scale in Scale.allCases {
            for root in [0, 5, 7, 9] {
                let key = MusicalKey(root: root, scale: scale)
                let comp = BioComposer.compose(input(coherence: 0.2, hr: 110, key: key, seed: 42))
                for note in comp.notes {
                    XCTAssertTrue(key.contains(note.pitch),
                                  "\(key.name): pitch \(note.pitch) must be in key")
                }
            }
        }
    }

    func testLowerCoherenceProducesBusierMelody() {
        let calm = BioComposer.compose(input(coherence: 0.95, hr: 70))
        let busy = BioComposer.compose(input(coherence: 0.05, hr: 70))
        XCTAssertGreaterThan(busy.notes.count, calm.notes.count,
                             "low coherence → more notes (busier)")
    }

    func testNoteCountStaysInBounds() {
        for hr in stride(from: Float(45), through: 130, by: 5) {
            for coh in stride(from: Float(0), through: 1, by: 0.1) {
                let comp = BioComposer.compose(input(coherence: coh, hr: hr))
                XCTAssertGreaterThanOrEqual(comp.notes.count, 2)
                XCTAssertLessThanOrEqual(comp.notes.count, 8)
            }
        }
    }

    func testNotesStayWithinTheBarAndAreValid() {
        let comp = BioComposer.compose(input(coherence: 0.1, hr: 120))
        var lastStart = -1
        for note in comp.notes {
            XCTAssertGreaterThanOrEqual(note.startStep, 0)
            XCTAssertLessThan(note.startStep, BioComposer.stepCount)
            XCTAssertGreaterThan(note.startStep, lastStart, "strictly increasing positions")
            lastStart = note.startStep
            XCTAssertGreaterThanOrEqual(note.lengthSteps, 1)
            XCTAssertLessThanOrEqual(note.startStep + note.lengthSteps, BioComposer.stepCount,
                                     "note never crosses the bar line")
            XCTAssertGreaterThanOrEqual(note.velocity, 0)
            XCTAssertLessThanOrEqual(note.velocity, 1)
        }
    }

    func testTempoStudioLockedVsFlowFree() {
        XCTAssertEqual(BioComposer.tempo(for: input(hr: 128, mode: .studioLocked)), 75,
                       "Studio mode ignores HR and uses the locked BPM")
        XCTAssertEqual(BioComposer.tempo(for: input(hr: 128, mode: .flowFree)), 128,
                       "Flow mode follows the heart")
        XCTAssertEqual(BioComposer.tempo(for: input(hr: 220, mode: .flowFree)), 160,
                       "Flow tempo is clamped to a musical ceiling")
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
}
