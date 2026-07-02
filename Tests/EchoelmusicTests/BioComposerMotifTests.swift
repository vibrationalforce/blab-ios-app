// BioComposerMotifTests.swift
// Echoel — guards the melodic MOTIF engine (Cycle 3, "singt statt noodelt").
// motifDeltas turns the melody from a random walk into a stated + answered + resolved
// contour. Pure + deterministic, so its musical guarantees are unit-tested directly.

import XCTest
@testable import Echoelmusic

final class BioComposerMotifTests: XCTestCase {

    private func deltas(count: Int, bias: Float = 0.5, weird: Float = 0, seed: UInt64) -> [Int] {
        var rng = SeededRNG(seed: seed)
        return BioComposer.motifDeltas(count: count, directionBias: bias, weird: weird, rng: &rng)
    }

    func testLengthMatchesCount() {
        for n in [1, 2, 5, 8, 13] {
            XCTAssertEqual(deltas(count: n, seed: 42).count, n)
        }
        XCTAssertEqual(deltas(count: 0, seed: 42).count, 0)   // guard
    }

    func testDeterministic() {
        let a = deltas(count: 8, bias: 0.6, weird: 0.3, seed: 123)
        let b = deltas(count: 8, bias: 0.6, weird: 0.3, seed: 123)
        XCTAssertEqual(a, b, "same seed + params must reproduce the same motif")
    }

    func testStepwiseWhenNotWeird() {
        // weird == 0 → every move is a single scale step (a smooth, singable line),
        // never a random 2–3 leap. This is the core "not a random walk" guarantee.
        for seed in UInt64(1)...UInt64(20) {
            for d in deltas(count: 8, bias: 0.5, weird: 0, seed: seed) {
                XCTAssertEqual(abs(d), 1, "seed \(seed): non-weird motif must be stepwise")
            }
        }
    }

    func testWeirdWidensIntervals() {
        // weird == 1 → the cell uses wider (2–3 step) leaps, so at least one big
        // interval appears (the resolution step stays a single step).
        let maxAbs = deltas(count: 8, bias: 0.5, weird: 1, seed: 7).map { abs($0) }.max() ?? 0
        XCTAssertGreaterThanOrEqual(maxAbs, 2, "weird motif should contain a wide leap")
    }

    func testResolvesTowardCentre() {
        // The final step opposes the accumulated direction so phrases settle instead
        // of drifting off the top/bottom — the "answer resolves" cue.
        for seed in UInt64(1)...UInt64(30) {
            let d = deltas(count: 8, bias: 0.7, weird: 0.2, seed: seed)
            let net = d.dropLast().reduce(0, +)
            if net > 0 { XCTAssertLessThanOrEqual(d.last ?? 0, 0, "seed \(seed): rising phrase must settle down") }
            if net < 0 { XCTAssertGreaterThanOrEqual(d.last ?? 0, 0, "seed \(seed): falling phrase must lift back") }
        }
    }

    func testDirectionBiasLeansUp() {
        // A high upward bias (inhale) produces more up-steps than a low bias, in
        // aggregate — the breath still steers the contour direction.
        func upCount(bias: Float) -> Int {
            var total = 0
            for seed in UInt64(1)...UInt64(40) {
                total += deltas(count: 8, bias: bias, weird: 0, seed: seed).filter { $0 > 0 }.count
            }
            return total
        }
        XCTAssertGreaterThan(upCount(bias: 0.95), upCount(bias: 0.05),
                             "an upward (inhale) bias should yield more rising steps")
    }

    func testRepetitionNotRandomWalk() {
        // A motif restates its cell: across a long line the number of DISTINCT delta
        // values stays small (a cell vocabulary), unlike a random walk which would
        // spread across many. weird 0 → deltas ∈ {-1, +1} only.
        let set = Set(deltas(count: 16, bias: 0.5, weird: 0, seed: 99))
        XCTAssertLessThanOrEqual(set.count, 2, "a stepwise motif uses a tiny delta vocabulary")
    }
}
