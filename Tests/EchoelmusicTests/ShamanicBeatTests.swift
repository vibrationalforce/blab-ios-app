// ShamanicBeatTests.swift
// Echoel — the shamanic ur-rhythm (BeatMode.pulse, founder 2026-07-06C "Beat soll
// ausschaltbar sein und tendenziell eher schamanisch ur-rhythmisch"). Pure
// Foundation, so ci.yml EXECUTES these on Linux. Pins the musical laws:
// a steady quarter pulse that never disappears, accents that breathe 1↔3,
// spaciousness as a strict subset, and determinism from the seed.

import XCTest
import Foundation
@testable import Echoelmusic

final class ShamanicBeatTests: XCTestCase {

    private let kick = 0   // BeatPlayer.trackNames order: Kick first
    private let perc = 5

    func testShamanicBeat_gridDimensions_matchEngine() {
        let (steps, accents) = BioComposer.shamanicBeat(seed: 7, energy: 0.5, calm: 0.5)
        XCTAssertEqual(steps.count, BioComposer.trackCount)
        XCTAssertEqual(accents.count, BioComposer.trackCount)
        XCTAssertTrue(steps.allSatisfy { $0.count == BioComposer.stepCount })
    }

    func testShamanicBeat_steadyQuarterPulse_alwaysPresent() {
        // The trance base must survive EVERY body state — calm, aroused, extremes.
        for (energy, calm) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0), (0.5, 0.5)] {
            let (steps, accents) = BioComposer.shamanicBeat(seed: 42,
                                                            energy: Float(energy),
                                                            calm: Float(calm))
            for s in [0, 4, 8, 12] {
                XCTAssertTrue(steps[kick][s], "quarter pulse missing at step \(s) (e=\(energy) c=\(calm))")
            }
            XCTAssertTrue(accents[kick][0] && accents[kick][8], "the 1/3 call-answer accents must always breathe")
        }
    }

    func testShamanicBeat_spaciousBody_isBarePulse() {
        // High coherence strips every extra: exactly the four quarters, nothing else.
        let (steps, _) = BioComposer.shamanicBeat(seed: 9, energy: 0.9, calm: 0.95)
        let kickHits = (0..<BioComposer.stepCount).filter { steps[kick][$0] }
        XCTAssertEqual(kickHits, [0, 4, 8, 12], "spacious = the bare walk")
        XCTAssertFalse(steps[perc].contains(true), "no perc turn when the body is spacious")
    }

    func testShamanicBeat_spacious_isStrictSubsetOfDriven_sameSeed() {
        // Unconditional rng draws → same seed, calmer body = subset, never a re-roll.
        let (driven, _) = BioComposer.shamanicBeat(seed: 1234, energy: 0.8, calm: 0.2)
        let (spacious, _) = BioComposer.shamanicBeat(seed: 1234, energy: 0.8, calm: 0.9)
        for t in 0..<BioComposer.trackCount {
            for s in 0..<BioComposer.stepCount where spacious[t][s] {
                XCTAssertTrue(driven[t][s], "spacious hit (t\(t) s\(s)) not present in the driven take")
            }
        }
    }

    func testShamanicBeat_deterministic_perSeed() {
        let a = BioComposer.shamanicBeat(seed: 77, energy: 0.6, calm: 0.3)
        let b = BioComposer.shamanicBeat(seed: 77, energy: 0.6, calm: 0.3)
        XCTAssertEqual(a.steps, b.steps)
        XCTAssertEqual(a.accents, b.accents)
    }

    func testSilentBeat_isCompletelyEmpty() {
        let (steps, accents) = BioComposer.silentBeat()
        XCTAssertEqual(steps.count, BioComposer.trackCount)
        XCTAssertFalse(steps.contains { $0.contains(true) })
        XCTAssertFalse(accents.contains { $0.contains(true) })
    }
}
