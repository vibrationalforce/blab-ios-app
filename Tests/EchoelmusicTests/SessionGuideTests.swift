//
//  SessionGuideTests.swift
//  Echoelmusic — Bio
//
//  Proves the Session guide law: it starts at the user's natural pace, eases DOWN
//  toward resonance without jerk, never guides UP, backs off when the body isn't
//  following (low coherence), and always stays in the safe pace window — for any
//  input including hostile/degenerate ones.
//

import XCTest
@testable import Echoelmusic

final class SessionGuideTests: XCTestCase {

    private let acc = 1e-9

    // MARK: - Construction / clamping

    func testStartsAtMeasuredPaceAndEasesTowardResonance() {
        let g = SessionGuide(measuredBreathsPerMinute: 12, resonancePace: 6, descentSeconds: 180)
        XCTAssertEqual(g.startPace, 12, accuracy: acc)
        XCTAssertEqual(g.resonancePace, 6, accuracy: acc)
        // At t=0 → natural pace; well into the descent with a following body → near resonance.
        XCTAssertEqual(g.targetBpm(atSeconds: 0, coherence: 1), 12, accuracy: acc)
        XCTAssertEqual(g.targetBpm(atSeconds: 10_000, coherence: 1), 6, accuracy: 1e-6)
    }

    func testNeverGuidesUpWhenAlreadySlow() {
        // User already breathing at 5/min (slower than the 6/min target) → hold at 5,
        // never speed them up to 6.
        let g = SessionGuide(measuredBreathsPerMinute: 5, resonancePace: 6)
        XCTAssertEqual(g.startPace, 6, accuracy: acc, "start floored to the target, not below")
        for t in [0.0, 60, 180, 600] {
            let bpm = g.targetBpm(atSeconds: t, coherence: 1)
            XCTAssertEqual(bpm, 6, accuracy: acc, "a slow breather is held at target, never sped up")
        }
    }

    func testResonancePaceClampedToEvidenceWindow() {
        // A wild personalized pace is clamped into [4.5, 7].
        XCTAssertEqual(SessionGuide(measuredBreathsPerMinute: 12, resonancePace: 0.5).resonancePace,
                       4.5, accuracy: acc)
        XCTAssertEqual(SessionGuide(measuredBreathsPerMinute: 12, resonancePace: 40).resonancePace,
                       7.0, accuracy: acc)
    }

    func testMeasuredPaceClampedAndGuarded() {
        // NaN / absurd measured rates fall back / clamp into the safe window.
        XCTAssertEqual(SessionGuide(measuredBreathsPerMinute: .nan).startPace, 12, accuracy: acc)
        XCTAssertEqual(SessionGuide(measuredBreathsPerMinute: 999).startPace,
                       SessionGuide.paceCeiling, accuracy: acc)
        XCTAssertEqual(SessionGuide(measuredBreathsPerMinute: -3).startPace,
                       SessionGuide.defaultResonancePace, accuracy: acc,
                       "sub-floor measured pace → held at the resonance target")
    }

    // MARK: - The guide law

    func testMonotonicNonIncreasingInTime() {
        let g = SessionGuide(measuredBreathsPerMinute: 14, resonancePace: 6, descentSeconds: 120)
        var prev = Double.infinity
        for t in stride(from: 0.0, through: 300, by: 5) {
            let bpm = g.targetBpm(atSeconds: t, coherence: 0.8)
            XCTAssertLessThanOrEqual(bpm, prev + 1e-9, "pace must never rise over time")
            prev = bpm
        }
    }

    func testStaysWithinSafeWindowForAnyInput() {
        let g = SessionGuide(measuredBreathsPerMinute: 16, resonancePace: 5.5, descentSeconds: 90)
        for t in stride(from: -50.0, through: 2000, by: 7) {
            for c in [-1.0, 0, 0.3, 0.7, 1, 2, .nan] {
                let bpm = g.targetBpm(atSeconds: t, coherence: c)
                XCTAssertGreaterThanOrEqual(bpm, g.resonancePace - 1e-9)
                XCTAssertLessThanOrEqual(bpm, g.startPace + 1e-9)
            }
        }
    }

    func testLowCoherenceHoldsPaceCloserToNatural() {
        // At the same instant, an unsettled body (low coherence) is guided LESS far
        // down than a settled one — the guide backs off, it doesn't force the pace.
        let g = SessionGuide(measuredBreathsPerMinute: 12, resonancePace: 6, descentSeconds: 120)
        let settled = g.targetBpm(atSeconds: 120, coherence: 1.0)
        let unsettled = g.targetBpm(atSeconds: 120, coherence: 0.0)
        XCTAssertLessThan(settled, unsettled, "a following body descends further")
        XCTAssertGreaterThan(unsettled, g.resonancePace, "an unsettled body isn't dragged to the floor")
    }

    func testTargetHzMatchesBpmOverSixty() {
        let g = SessionGuide(measuredBreathsPerMinute: 12, resonancePace: 6)
        let bpm = g.targetBpm(atSeconds: 30, coherence: 0.5)
        XCTAssertEqual(g.targetHz(atSeconds: 30, coherence: 0.5), bpm / 60, accuracy: acc)
        // And that Hz is trivially flash-safe (breath paces are ~0.1 Hz).
        XCTAssertLessThan(g.targetHz(atSeconds: 30, coherence: 0.5), EntrainmentEngine.maxVisualFlashHz)
    }

    // MARK: - smoothstep

    func testSmoothstepEndsAreFlatAndClamped() {
        XCTAssertEqual(SessionGuide.smoothstep(0), 0, accuracy: acc)
        XCTAssertEqual(SessionGuide.smoothstep(1), 1, accuracy: acc)
        XCTAssertEqual(SessionGuide.smoothstep(0.5), 0.5, accuracy: acc)
        XCTAssertEqual(SessionGuide.smoothstep(-2), 0, accuracy: acc)
        XCTAssertEqual(SessionGuide.smoothstep(3), 1, accuracy: acc)
    }
}
