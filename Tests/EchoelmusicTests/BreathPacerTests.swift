// BreathPacerTests.swift
// Echoelmusic — resonance-breathing guide (pure advance + safety bounds).

import XCTest
@testable import Echoelmusic

@MainActor
final class BreathPacerTests: XCTestCase {

    // MARK: Safety bounds

    func testTargetRate_clampedToSafeWindow() {
        let p = BreathPacer()
        p.targetRate = 0.1
        XCTAssertEqual(p.targetRate, BreathPacer.minRate, accuracy: 1e-9)
        p.targetRate = 999
        XCTAssertEqual(p.targetRate, BreathPacer.maxRate, accuracy: 1e-9)
        p.targetRate = 6.0
        XCTAssertEqual(p.targetRate, 6.0, accuracy: 1e-9)
    }

    func testInhaleFraction_clamped() {
        let p = BreathPacer()
        p.inhaleFraction = 0.01
        XCTAssertEqual(p.inhaleFraction, 0.3, accuracy: 1e-9)
        p.inhaleFraction = 0.99
        XCTAssertEqual(p.inhaleFraction, 0.6, accuracy: 1e-9)
    }

    func testNeverInstructsBreathHold() {
        let p = BreathPacer()
        p.start()
        for _ in 0..<2000 {
            p.tick(0.05)
            XCTAssertTrue(p.instruction == "Breathe in" || p.instruction == "Breathe out")
        }
    }

    // MARK: Transport

    func testDoesNotAdvanceWhileStopped() {
        let p = BreathPacer()
        p.tick(1.0)
        XCTAssertEqual(p.phase, 0.0, accuracy: 1e-12)
    }

    func testGuidanceStaysInRange() {
        let p = BreathPacer()
        p.start()
        for _ in 0..<1000 {
            p.tick(0.033)
            XCTAssertGreaterThanOrEqual(p.guidance, 0.0)
            XCTAssertLessThanOrEqual(p.guidance, 1.0)
        }
    }

    // MARK: Pace easing — a rate jump must not jerk the applied pace

    func testEffectiveRateEasesNotJumps() {
        let p = BreathPacer()
        p.targetRate = 6.0
        p.reset()
        XCTAssertEqual(p.effectiveRate, 6.0, accuracy: 1e-9)
        p.targetRate = 12.0
        p.start()
        p.tick(0.1)   // max change 0.5/s * 0.1 = 0.05 bpm
        XCTAssertLessThan(p.effectiveRate, 6.2)
        XCTAssertGreaterThan(p.effectiveRate, 6.0)
    }

    // MARK: Period — at 6 bpm one full cycle is 10 s

    func testSixBpm_completesOneCycleInTenSeconds() {
        let p = BreathPacer()
        p.targetRate = 6.0
        p.reset()        // effectiveRate := targetRate (6.0), so the whole run is at 6 bpm
        p.start()
        var t = 0.0
        while t < 10.0 { p.tick(0.01); t += 0.01 }
        // After 10 s at 6 bpm, phase wraps once back near 0.
        XCTAssertEqual(p.phase, 0.0, accuracy: 0.02)
    }

    // MARK: Pure curve

    func testGuidanceCurve_exhaleStartsFull_inhaleEndsFull() {
        // phase 0 = exhale start → lungs full (1).
        XCTAssertEqual(BreathPacer.guidance(phase: 0.0, inhaleFraction: 0.4), 1.0, accuracy: 1e-6)
        // just before wrap = inhale peak → full (1).
        XCTAssertEqual(BreathPacer.guidance(phase: 0.999, inhaleFraction: 0.4), 1.0, accuracy: 1e-2)
        // exhale end / inhale start (phase = 1 - inhaleFraction) → empty (0).
        XCTAssertEqual(BreathPacer.guidance(phase: 0.6, inhaleFraction: 0.4), 0.0, accuracy: 1e-6)
    }

    func testContraindications_presentAndNonMedicalGuidanceShipped() {
        XCTAssertFalse(BreathPacer.contraindications.isEmpty)
    }
}
