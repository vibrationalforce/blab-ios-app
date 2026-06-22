// AutomationPlayerTests.swift
// Echoel — parameter automation: target mapping, beat/tick conversion, and the
// per-step value the transport would apply (the pure core of applyStep).

import XCTest
@testable import Echoelmusic

@MainActor
final class AutomationPlayerTests: XCTestCase {

    func testTargetMappingRoundTrips() {
        for target in AutomationTarget.allCases {
            let real = target.value(forNormalized: 0.5)
            XCTAssertEqual(real, (target.minValue + target.maxValue) / 2, accuracy: 1e-9)
            // normalized∘value is identity on [0,1].
            let back = target.normalized(forValue: real)
            XCTAssertEqual(back, 0.5, accuracy: 1e-9)
        }
        XCTAssertEqual(AutomationTarget.tempo.value(forNormalized: 0), 40, accuracy: 1e-9)
        XCTAssertEqual(AutomationTarget.tempo.value(forNormalized: 1), 220, accuracy: 1e-9)
        XCTAssertEqual(AutomationTarget.masterLevel.value(forNormalized: 1), 1, accuracy: 1e-9)
    }

    func testMappingClampsOutOfRange() {
        XCTAssertEqual(AutomationTarget.masterLevel.value(forNormalized: 2), 1, accuracy: 1e-9)
        XCTAssertEqual(AutomationTarget.masterLevel.value(forNormalized: -1), 0, accuracy: 1e-9)
    }

    func testBeatTickConversion() {
        XCTAssertEqual(AutomationPlayer.tick(forBeat: 1), Note.ticksPerQuarter)
        XCTAssertEqual(AutomationPlayer.tick(forBeat: 4), Note.ticksPerQuarter * 4)
        XCTAssertEqual(AutomationPlayer.beat(forTick: Note.ticksPerQuarter * 2), 2, accuracy: 1e-9)
    }

    func testEmptyLaneAppliesNothing() {
        let auto = AutomationPlayer()
        auto.clear(target: .tempo)
        XCTAssertNil(auto.appliedValue(for: .tempo, atStep: 0))
    }

    func testAppliedValueFollowsKeyframes() {
        let auto = AutomationPlayer()
        auto.clear(target: .tempo)
        // Ramp 40 → 220 across the bar (beat 0 → beat 4), linear.
        auto.addPoint(target: .tempo, beat: 0, value: 0.0, curve: .linear)
        auto.addPoint(target: .tempo, beat: 4, value: 1.0, curve: .linear)
        // Step 0 (tick 0) = start = 40 BPM.
        XCTAssertEqual(auto.appliedValue(for: .tempo, atStep: 0) ?? 0, 40, accuracy: 0.5)
        // Step 8 (tick 8*120=960 = beat 2 = halfway) ≈ 130 BPM.
        XCTAssertEqual(auto.appliedValue(for: .tempo, atStep: 8) ?? 0, 130, accuracy: 2)
    }

    func testHoldCurveStepsRatherThanGlides() {
        let auto = AutomationPlayer()
        auto.clear(target: .masterLevel)
        auto.addPoint(target: .masterLevel, beat: 0, value: 0.2, curve: .hold)
        auto.addPoint(target: .masterLevel, beat: 4, value: 1.0, curve: .linear)
        // Hold keeps the left value right up to the next keyframe.
        XCTAssertEqual(auto.appliedValue(for: .masterLevel, atStep: 8) ?? 0, 0.2, accuracy: 1e-6)
    }

    func testDisabledMakesAppliedValueIrrelevant_butComputable() {
        // appliedValue is pure (always computes); the on/off gate lives in applyStep.
        let auto = AutomationPlayer()
        auto.enabled = false
        auto.clear(target: .tempo)
        auto.addPoint(target: .tempo, beat: 0, value: 0.5)
        XCTAssertNotNil(auto.appliedValue(for: .tempo, atStep: 0))
    }
}
