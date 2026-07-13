// VideoResyncPolicyTests.swift
// Echoelmusic — Sequencer tests
//
// Pure, deterministic coverage for the video↔audio drift-correction policy.

import XCTest
@testable import Echoelmusic

final class VideoResyncPolicyTests: XCTestCase {

    // MARK: - Deadband → hold

    func testResolve_zeroDrift_holds() {
        let action = VideoResyncPolicy.resolve(expectedSourceSeconds: 4.0,
                                               observedSeconds: 4.0,
                                               dt: 0.033,
                                               regionSwitchedOrWrapped: false)
        XCTAssertEqual(action, .hold)
    }

    func testResolve_subFrameDrift_holds() {
        // 0.02 s < 0.033 s deadband → hold (a seek would only add judder).
        let action = VideoResyncPolicy.resolve(expectedSourceSeconds: 4.0,
                                               observedSeconds: 4.02,
                                               dt: 0.033,
                                               regionSwitchedOrWrapped: false)
        XCTAssertEqual(action, .hold)
    }

    func testResolve_exactlyAtDeadbandEdge_holds() {
        // magnitude == deadband → hold (inclusive edge).
        let action = VideoResyncPolicy.resolve(expectedSourceSeconds: 1.0,
                                               observedSeconds: 1.0 + VideoResyncPolicy.deadbandSeconds,
                                               dt: 0.033,
                                               regionSwitchedOrWrapped: false)
        XCTAssertEqual(action, .hold)
    }

    // MARK: - Medium drift → clamped / proportional nudge

    func testResolve_mediumDrift_nudgesWithinThreePercent() {
        // Large-ish drift inside the band saturates the ±3% clamp.
        let action = VideoResyncPolicy.resolve(expectedSourceSeconds: 4.0,
                                               observedSeconds: 4.20, // +0.20 ahead
                                               dt: 0.033,
                                               regionSwitchedOrWrapped: false)
        guard case let .nudgeRate(rate) = action else {
            return XCTFail("expected nudgeRate, got \(action)")
        }
        XCTAssertGreaterThanOrEqual(rate, VideoResyncPolicy.minRate)
        XCTAssertLessThanOrEqual(rate, VideoResyncPolicy.maxRate)
        // Player AHEAD (observed > expected) → slow down → clamped to the min rate.
        XCTAssertEqual(rate, VideoResyncPolicy.minRate, accuracy: 1e-6)
    }

    func testResolve_behindPlayer_speedsUp_clamped() {
        // Player BEHIND (observed < expected) → speed up → clamped to the max rate.
        let action = VideoResyncPolicy.resolve(expectedSourceSeconds: 4.0,
                                               observedSeconds: 3.80, // -0.20 behind
                                               dt: 0.033,
                                               regionSwitchedOrWrapped: false)
        guard case let .nudgeRate(rate) = action else {
            return XCTFail("expected nudgeRate, got \(action)")
        }
        XCTAssertEqual(rate, VideoResyncPolicy.maxRate, accuracy: 1e-6)
    }

    func testResolve_smallInBandDrift_proportionalUnclamped() {
        // 0.05 s drift: past the 0.033 deadband, delta = 0.05 * 0.5 = 0.025 < 0.03 → unclamped.
        let action = VideoResyncPolicy.resolve(expectedSourceSeconds: 0.0,
                                               observedSeconds: 0.05, // ahead
                                               dt: 0.033,
                                               regionSwitchedOrWrapped: false)
        guard case let .nudgeRate(rate) = action else {
            return XCTFail("expected nudgeRate, got \(action)")
        }
        XCTAssertEqual(rate, 0.975, accuracy: 1e-5) // 1 - 0.025
        XCTAssertGreaterThan(rate, VideoResyncPolicy.minRate)
        XCTAssertLessThan(rate, VideoResyncPolicy.maxRate)
    }

    // MARK: - Large drift / wrap → hard seek

    func testResolve_largeDrift_hardSeeksToExpected() {
        let action = VideoResyncPolicy.resolve(expectedSourceSeconds: 4.0,
                                               observedSeconds: 4.5, // 0.5 > 0.25
                                               dt: 0.033,
                                               regionSwitchedOrWrapped: false)
        XCTAssertEqual(action, .hardSeek(toSeconds: 4.0))
    }

    func testResolve_regionWrap_hardSeeksEvenWithSmallDrift() {
        // Zero drift but a wrap this tick → still a hard seek to expected.
        let action = VideoResyncPolicy.resolve(expectedSourceSeconds: 0.0,
                                               observedSeconds: 0.0,
                                               dt: 0.033,
                                               regionSwitchedOrWrapped: true)
        XCTAssertEqual(action, .hardSeek(toSeconds: 0.0))
    }

    func testResolve_justOverHardSeekThreshold_hardSeeks() {
        let d = VideoResyncPolicy.hardSeekThresholdSeconds + 0.001
        let action = VideoResyncPolicy.resolve(expectedSourceSeconds: 2.0,
                                               observedSeconds: 2.0 + d,
                                               dt: 0.033,
                                               regionSwitchedOrWrapped: false)
        XCTAssertEqual(action, .hardSeek(toSeconds: 2.0))
    }

    func testResolve_exactlyAtHardSeekThreshold_nudgesNotSeeks() {
        // magnitude == threshold is NOT > threshold → still a nudge.
        let action = VideoResyncPolicy.resolve(expectedSourceSeconds: 2.0,
                                               observedSeconds: 2.0 + VideoResyncPolicy.hardSeekThresholdSeconds,
                                               dt: 0.033,
                                               regionSwitchedOrWrapped: false)
        guard case .nudgeRate = action else {
            return XCTFail("expected nudgeRate at threshold edge, got \(action)")
        }
    }

    // MARK: - Guards / edge cases

    func testResolve_nonFiniteObserved_hardSeeksToExpected() {
        let action = VideoResyncPolicy.resolve(expectedSourceSeconds: 3.0,
                                               observedSeconds: .nan,
                                               dt: 0.033,
                                               regionSwitchedOrWrapped: false)
        XCTAssertEqual(action, .hardSeek(toSeconds: 3.0))
    }

    func testResolve_nonFiniteExpected_recoversToZero() {
        let action = VideoResyncPolicy.resolve(expectedSourceSeconds: .infinity,
                                               observedSeconds: 5.0,
                                               dt: 0.033,
                                               regionSwitchedOrWrapped: false)
        // expected sanitized to 0, drift = 5.0 > 0.25 → hard seek to 0.
        XCTAssertEqual(action, .hardSeek(toSeconds: 0.0))
    }

    func testResolve_zeroDt_isSafe() {
        // dt is not divided by; zero must not crash or alter the decision.
        let action = VideoResyncPolicy.resolve(expectedSourceSeconds: 1.0,
                                               observedSeconds: 1.0,
                                               dt: 0.0,
                                               regionSwitchedOrWrapped: false)
        XCTAssertEqual(action, .hold)
    }

    func testResolve_negativeDt_isSafe() {
        let action = VideoResyncPolicy.resolve(expectedSourceSeconds: 1.0,
                                               observedSeconds: 1.5, // 0.5 > 0.25
                                               dt: -1.0,
                                               regionSwitchedOrWrapped: false)
        XCTAssertEqual(action, .hardSeek(toSeconds: 1.0))
    }

    func testResolve_isDeterministic() {
        let a = VideoResyncPolicy.resolve(expectedSourceSeconds: 4.0, observedSeconds: 4.2,
                                          dt: 0.033, regionSwitchedOrWrapped: false)
        let b = VideoResyncPolicy.resolve(expectedSourceSeconds: 4.0, observedSeconds: 4.2,
                                          dt: 0.033, regionSwitchedOrWrapped: false)
        XCTAssertEqual(a, b)
    }
}
