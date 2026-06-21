// BreathPacerTests.swift
// Echoelmusic — the breathing guide transport (pattern-driven advance + safety).

import XCTest
@testable import Echoelmusic

@MainActor
final class BreathPacerTests: XCTestCase {

    // MARK: Defaults

    func testDefaultsToResonance_noHolds() {
        let p = BreathPacer()
        XCTAssertEqual(p.pattern.id, "resonance")
        XCTAssertFalse(p.pattern.hasHolds)
    }

    // MARK: Transport

    func testDoesNotAdvanceWhileStopped() {
        let p = BreathPacer()
        let before = p.guidance
        p.tick(1.0)
        XCTAssertEqual(p.guidance, before, accuracy: 1e-12)
    }

    func testGuidanceStaysInRange_acrossPatterns() {
        for pat in BreathPattern.curated {
            let p = BreathPacer()
            p.pattern = pat
            p.start()
            for _ in 0..<1000 {
                p.tick(0.033)
                XCTAssertGreaterThanOrEqual(p.guidance, 0.0, pat.id)
                XCTAssertLessThanOrEqual(p.guidance, 1.0, pat.id)
            }
        }
    }

    // MARK: Resonance never instructs a hold

    func testResonance_neverInstructsHold() {
        let p = BreathPacer() // resonance default
        p.start()
        for _ in 0..<2000 {
            p.tick(0.05)
            XCTAssertTrue(p.instruction == "Breathe in" || p.instruction == "Breathe out")
            XCTAssertFalse(p.phaseKind.isHold)
        }
    }

    // MARK: Hold patterns DO instruct holds (the new opt-in behaviour)

    func testBox_instructsHoldAtSomePoint() {
        let p = BreathPacer()
        p.pattern = .box
        p.start()
        var sawHold = false
        for _ in 0..<2000 {
            p.tick(0.05)
            if p.instruction == "Hold" { sawHold = true; break }
        }
        XCTAssertTrue(sawHold, "Box breathing must reach a Hold phase")
    }

    // MARK: Period — resonance cycle is 10 s, guidance returns near start

    func testResonance_completesCycleInTenSeconds() {
        let p = BreathPacer()
        p.reset()
        p.start()
        let startGuidance = p.guidance
        var t = 0.0
        while t < 10.0 { p.tick(0.01); t += 0.01 }
        XCTAssertEqual(p.guidance, startGuidance, accuracy: 0.03)
    }

    // MARK: Switching pattern restarts the cycle cleanly (no mid-breath jump on start)

    func testChangingPattern_resetsCycle() {
        let p = BreathPacer()
        p.start()
        for _ in 0..<50 { p.tick(0.05) }   // advance into the cycle
        p.pattern = .coherent              // should reset cycleTime → start of inhale
        XCTAssertLessThan(p.guidance, 0.05, "a fresh pattern starts empty (inhale start)")
        XCTAssertEqual(p.instruction, "Breathe in")
    }

    // MARK: Safety copy

    func testContraindications_presentForBothNoHoldAndHold() {
        XCTAssertFalse(BreathPacer.contraindications.isEmpty)
        XCTAssertFalse(BreathPattern.holdContraindications.isEmpty)
    }
}
