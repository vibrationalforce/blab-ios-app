// BreathSwellTests.swift
// Echoel — the 0.1 Hz breath-swell gain curve (the medical coherence pacer).
// A raised-cosine swell that rides between (1 - depth) and 1 across each ~10 s
// cycle, pacing the listener toward 6 breaths/min (Shaffer & Meehan 2020;
// Leslie/Picard 2019). See scratchpads/RESEARCH_MEDITATION_ALGORITHM_2026-07-07.md.

#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

final class BreathSwellTests: XCTestCase {

    typealias P = PolySynthVoice

    func testFullGainAtPhaseZero() {
        // Phase 0 = the top of the breath: no attenuation for any depth.
        for d in [Float(0), 0.1, 0.22, 0.5] {
            XCTAssertEqual(P.breathGain(phase: 0, depth: d), 1, accuracy: 1e-6,
                           "phase 0 is always full gain (depth \(d))")
        }
    }

    func testTroughAtPhasePi() {
        // Phase π = the bottom of the breath: gain dips to exactly (1 - depth).
        for d in [Float(0), 0.1, 0.22, 0.5] {
            XCTAssertEqual(P.breathGain(phase: .pi, depth: d), 1 - d, accuracy: 1e-6,
                           "phase π dips to 1-depth (depth \(d))")
        }
    }

    func testZeroDepthIsAlwaysUnity() {
        // depth 0 = off = a true no-op at every phase.
        for i in 0...16 {
            let phase = Float(i) / 16 * 2 * .pi
            XCTAssertEqual(P.breathGain(phase: phase, depth: 0), 1, accuracy: 1e-6)
        }
    }

    func testGainStaysWithinTheEnvelope() {
        // Across a whole cycle the gain never leaves [1-depth, 1] — no boost, no
        // silence, no click-inducing overshoot.
        let d: Float = 0.22
        for i in 0...200 {
            let phase = Float(i) / 200 * 2 * .pi
            let g = P.breathGain(phase: phase, depth: d)
            XCTAssertGreaterThanOrEqual(g, 1 - d - 1e-6)
            XCTAssertLessThanOrEqual(g, 1 + 1e-6)
        }
    }

    func testSixBreathsPerMinute() {
        // 0.1 Hz = one full breath every 10 s = 6 breaths per minute (the resonance
        // target). Guards the constant against an accidental edit.
        XCTAssertEqual(P.breathSwellHz, 0.1, accuracy: 1e-6)
        XCTAssertEqual(60 * P.breathSwellHz, 6, accuracy: 1e-4, "6 breaths per minute")
    }
}
#endif
