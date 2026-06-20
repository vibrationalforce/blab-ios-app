// ResonanceFinderTests.swift
// Echoel — the personalized resonance-frequency core: the safe candidate grid and
// the parabolic peak estimate that turns a coarse sweep into a refined rate.

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
@testable import Echoelmusic

final class ResonanceFinderTests: XCTestCase {

    func testCandidateRates_coverSafeWindowDescending() {
        XCTAssertEqual(ResonanceFinder.candidateRates, [7.0, 6.5, 6.0, 5.5, 5.0])
    }

    func testCandidateRates_stayWithinBounds() {
        for r in ResonanceFinder.candidateRates {
            XCTAssertGreaterThanOrEqual(r, ResonanceFinder.minRate)
            XCTAssertLessThanOrEqual(r, ResonanceFinder.maxRate)
        }
    }

    func testBestRate_emptyReturnsNil() {
        XCTAssertNil(ResonanceFinder.bestRate(from: []))
    }

    func testBestRate_singleSampleReturnsThatRateClamped() {
        XCTAssertEqual(ResonanceFinder.bestRate(from: [.init(rate: 6.0, score: 0.7)]), 6.0)
        // Out-of-window single sample is clamped into the safe window.
        XCTAssertEqual(ResonanceFinder.bestRate(from: [.init(rate: 9.0, score: 0.7)]),
                       ResonanceFinder.maxRate)
    }

    func testBestRate_clearInteriorPeakSymmetricReturnsCentre() {
        // Symmetric scores peaking at 5.5 → vertex sits exactly on 5.5.
        let s: [ResonanceSample] = [
            .init(rate: 6.5, score: 0.3),
            .init(rate: 6.0, score: 0.6),
            .init(rate: 5.5, score: 0.9),
            .init(rate: 5.0, score: 0.6),
        ]
        let r = ResonanceFinder.bestRate(from: s)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!, 5.5, accuracy: 1e-6)
    }

    func testBestRate_skewedPeakInterpolatesBetweenNeighbours() {
        // Peak candidate 6.0 but the 5.5 neighbour scores higher than 6.5 →
        // refined estimate pulls slightly toward 5.5 (below 6.0), stays in range.
        let s: [ResonanceSample] = [
            .init(rate: 6.5, score: 0.50),
            .init(rate: 6.0, score: 0.90),
            .init(rate: 5.5, score: 0.70),
        ]
        let r = ResonanceFinder.bestRate(from: s)
        XCTAssertNotNil(r)
        XCTAssertLessThan(r!, 6.0)
        XCTAssertGreaterThan(r!, 5.5)
    }

    func testBestRate_peakAtEdgeNotRefined() {
        // Highest score at the fastest candidate → no interior neighbour, return it.
        let s: [ResonanceSample] = [
            .init(rate: 7.0, score: 0.9),
            .init(rate: 6.5, score: 0.6),
            .init(rate: 6.0, score: 0.4),
        ]
        XCTAssertEqual(ResonanceFinder.bestRate(from: s), 7.0)
    }

    func testBestRate_ignoresNonFiniteSamples() {
        let s: [ResonanceSample] = [
            .init(rate: .nan, score: 0.99),
            .init(rate: 6.0, score: .infinity),
            .init(rate: 5.5, score: 0.8),
        ]
        XCTAssertEqual(ResonanceFinder.bestRate(from: s), 5.5)
    }

    func testBestRate_alwaysWithinSafeWindow() {
        // Even a degenerate triple can't push the estimate out of bounds.
        let s: [ResonanceSample] = [
            .init(rate: 5.0, score: 0.9),
            .init(rate: 5.5, score: 0.8999),
            .init(rate: 6.0, score: 0.1),
        ]
        let r = ResonanceFinder.bestRate(from: s)
        XCTAssertNotNil(r)
        XCTAssertGreaterThanOrEqual(r!, ResonanceFinder.minRate)
        XCTAssertLessThanOrEqual(r!, ResonanceFinder.maxRate)
    }
}
#endif
