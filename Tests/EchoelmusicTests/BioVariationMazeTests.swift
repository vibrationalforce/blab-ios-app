// BioVariationMazeTests.swift
// The bio-curated "idea-maze": propose N variations of the same piece, score each by
// how closely its groove-density matches what the body asks for, rank best-first.
// Pure + deterministic → every platform (Linux CI).

import XCTest
@testable import Echoelmusic

final class BioVariationMazeTests: XCTestCase {

    private func input(coherence: Float = 0.5, hrv: Float = 0.5, hr: Float = 70,
                       seed: UInt64 = 0x5EED) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: hr, hrvNormalized: hrv, coherence: coherence, seed: seed)
    }

    // MARK: Determinism

    func testExploreIsDeterministic() {
        let base = input()
        let a = BioVariationMaze.explore(base: base, count: 6)
        let b = BioVariationMaze.explore(base: base, count: 6)
        XCTAssertEqual(a, b)
    }

    func testVariantSeedDeterministicAndDistinct() {
        let base: UInt64 = 0xABCDEF
        XCTAssertEqual(BioVariationMaze.variantSeed(base: base, index: 3),
                       BioVariationMaze.variantSeed(base: base, index: 3))
        XCTAssertNotEqual(BioVariationMaze.variantSeed(base: base, index: 1),
                          BioVariationMaze.variantSeed(base: base, index: 2))
        XCTAssertNotEqual(BioVariationMaze.variantSeed(base: base, index: 1), base)
    }

    // MARK: Shape

    func testExploreReturnsRequestedCount() {
        let lb = BioVariationMaze.explore(base: input(), count: 5)
        XCTAssertEqual(lb.candidates.count, 5)
    }

    func testCountClampsToAtLeastOne() {
        let lb = BioVariationMaze.explore(base: input(), count: 0)
        XCTAssertEqual(lb.candidates.count, 1)
    }

    func testCountOneIsJustTheBaseTake() {
        let base = input(seed: 0xC0FFEE)
        let lb = BioVariationMaze.explore(base: base, count: 1)
        XCTAssertEqual(lb.candidates.count, 1)
        XCTAssertEqual(lb.best?.seed, base.seed)
        // Candidate 0 reproduces the current take exactly.
        XCTAssertEqual(lb.best?.composition, BioComposer.compose(base))
    }

    // MARK: realizedDensity — drumless fallback (cells == 0 → note term only)

    func testRealizedDensityDrumlessUsesNotesOnly() {
        let empty = BioComposition(notes: [], drumSteps: [], drumAccents: [], suggestedTempo: 120)
        XCTAssertEqual(BioVariationMaze.realizedDensity(empty), 0, accuracy: 1e-9)
    }

    func testFirstCandidateSetIncludesBaseSeed() {
        let base = input(seed: 0x1234_5678)
        let lb = BioVariationMaze.explore(base: base, count: 4)
        XCTAssertTrue(lb.candidates.contains { $0.seed == base.seed },
                      "the base take must be in the leaderboard for comparison")
    }

    // MARK: Ranking

    func testCandidatesRankedByScoreDescending() {
        let lb = BioVariationMaze.explore(base: input(), count: 8)
        let scores = lb.candidates.map(\.score)
        XCTAssertEqual(scores, scores.sorted(by: >), "leaderboard must be best-first")
    }

    func testBestMinimisesGapToTarget() {
        let lb = BioVariationMaze.explore(base: input(), count: 8)
        guard let best = lb.best else { return XCTFail("no candidates") }
        let bestGap = abs(best.realizedDensity - lb.targetDensity)
        for c in lb.candidates {
            XCTAssertLessThanOrEqual(bestGap, abs(c.realizedDensity - lb.targetDensity) + 1e-9)
        }
    }

    func testTieBreakIsDeterministicBySeed() {
        // Two runs must produce identical ordering even when scores tie.
        let a = BioVariationMaze.explore(base: input(), count: 8).candidates.map(\.seed)
        let b = BioVariationMaze.explore(base: input(), count: 8).candidates.map(\.seed)
        XCTAssertEqual(a, b)
    }

    func testEqualScoresBreakSeedAscending() {
        // Actually pin the tie-break DIRECTION: adjacent equal-score candidates must be
        // ordered by ascending seed (flipping the comparator would fail this).
        let cands = BioVariationMaze.explore(base: input(), count: 12).candidates
        for (lhs, rhs) in zip(cands, cands.dropFirst()) where lhs.score == rhs.score {
            XCTAssertLessThan(lhs.seed, rhs.seed, "equal scores must sort seed-ascending")
        }
    }

    // MARK: Bounds + transparency

    func testScoresAndDensitiesInUnitRange() {
        let lb = BioVariationMaze.explore(base: input(), count: 6)
        XCTAssertTrue((0...1).contains(lb.targetDensity))
        for c in lb.candidates {
            XCTAssertTrue((0...1).contains(c.score), "score \(c.score)")
            XCTAssertTrue((0...1).contains(c.realizedDensity), "density \(c.realizedDensity)")
        }
    }

    func testTargetMatchesBioComposerMusicalState() {
        let base = input(coherence: 0.3, hrv: 0.6, hr: 88)
        let lb = BioVariationMaze.explore(base: base, count: 2)
        let expected = Double(BioComposer.musicalState(
            coherence: 0.3, hrvNormalized: 0.6, heartRateBPM: 88).busy)
        XCTAssertEqual(lb.targetDensity, expected, accuracy: 1e-9)
    }

    // MARK: The body actually curates — calm asks for less than arousal

    func testCalmBodyAsksForLessDensityThanArousedBody() {
        let calm    = BioVariationMaze.explore(base: input(coherence: 0.95, hrv: 0.9, hr: 58), count: 2)
        let aroused = BioVariationMaze.explore(base: input(coherence: 0.05, hrv: 0.2, hr: 115), count: 2)
        XCTAssertLessThan(calm.targetDensity, aroused.targetDensity,
                          "a settled body should request a sparser take than an aroused one")
    }

    // MARK: score() unit behaviour

    func testScoreIsOneOnExactMatchAndFallsWithGap() {
        XCTAssertEqual(BioVariationMaze.score(realizedDensity: 0.4, targetDensity: 0.4), 1, accuracy: 1e-9)
        XCTAssertEqual(BioVariationMaze.score(realizedDensity: 0.9, targetDensity: 0.4), 0.5, accuracy: 1e-9)
        XCTAssertEqual(BioVariationMaze.score(realizedDensity: 1, targetDensity: 0), 0, accuracy: 1e-9)
    }
}
