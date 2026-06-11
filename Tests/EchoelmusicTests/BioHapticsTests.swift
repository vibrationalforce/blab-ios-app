// BioHapticsTests.swift
// Echoelmusic — pure bio→haptic-cue mapping (eyes-free performance feedback).

import XCTest
@testable import Echoelmusic

final class BioHapticsTests: XCTestCase {

    // MARK: - HapticCue clamps its inputs

    func testHapticCue_clampsIntensitySharpnessAndDuration() {
        let c = HapticCue(kind: .transient, intensity: 2, sharpness: -1, duration: -5)
        XCTAssertEqual(c.intensity, 1, accuracy: 1e-9)
        XCTAssertEqual(c.sharpness, 0, accuracy: 1e-9)
        XCTAssertEqual(c.duration, 0, accuracy: 1e-9)
    }

    // MARK: - beat()

    func testBeat_downbeat_isStrongAndSharpTransient() {
        let c = BioHaptics.beat(isDownbeat: true)
        XCTAssertEqual(c.kind, .transient)
        XCTAssertEqual(c.intensity, 1.0, accuracy: 1e-6)
        XCTAssertEqual(c.sharpness, 0.9, accuracy: 1e-6)
        XCTAssertEqual(c.duration, 0, accuracy: 1e-9)
    }

    func testBeat_accent_isStrongButLessSharpThanDownbeat() {
        let c = BioHaptics.beat(isDownbeat: false, accent: true)
        XCTAssertEqual(c.intensity, 0.85, accuracy: 1e-6)
        XCTAssertEqual(c.sharpness, 0.7, accuracy: 1e-6)
        XCTAssertLessThan(c.sharpness, BioHaptics.beat(isDownbeat: true).sharpness)
    }

    func testBeat_offbeat_isSoftAndDull() {
        let c = BioHaptics.beat(isDownbeat: false)
        XCTAssertEqual(c.intensity, 0.45, accuracy: 1e-6)
        XCTAssertEqual(c.sharpness, 0.35, accuracy: 1e-6)
    }

    func testBeat_downbeatStrongerThanOffbeat() {
        XCTAssertGreaterThan(
            BioHaptics.beat(isDownbeat: true).intensity,
            BioHaptics.beat(isDownbeat: false).intensity
        )
    }

    // MARK: - breathPulse() swell (raised cosine)

    func testBreathPulse_phaseZero_zeroIntensity() {
        XCTAssertEqual(BioHaptics.breathPulse(breathPhase: 0, coherence: 0.5).intensity, 0, accuracy: 1e-6)
    }

    func testBreathPulse_phaseHalf_peakIntensity() {
        XCTAssertEqual(BioHaptics.breathPulse(breathPhase: 0.5, coherence: 0.5).intensity, 1.0, accuracy: 1e-6)
    }

    func testBreathPulse_phaseQuarter_midIntensity() {
        XCTAssertEqual(BioHaptics.breathPulse(breathPhase: 0.25, coherence: 0.5).intensity, 0.5, accuracy: 1e-6)
    }

    func testBreathPulse_phaseOne_returnsToZero() {
        XCTAssertEqual(BioHaptics.breathPulse(breathPhase: 1.0, coherence: 0.5).intensity, 0, accuracy: 1e-6)
    }

    func testBreathPulse_isContinuousWithDuration() {
        let c = BioHaptics.breathPulse(breathPhase: 0.5, coherence: 0.5, duration: 0.2)
        XCTAssertEqual(c.kind, .continuous)
        XCTAssertEqual(c.duration, 0.2, accuracy: 1e-6)
    }

    // MARK: - breathPulse() sharpness eases with coherence

    func testBreathPulse_highCoherence_isSoft() {
        XCTAssertEqual(BioHaptics.breathPulse(breathPhase: 0.5, coherence: 1.0).sharpness, 0, accuracy: 1e-6)
    }

    func testBreathPulse_lowCoherence_isSharp() {
        XCTAssertEqual(BioHaptics.breathPulse(breathPhase: 0.5, coherence: 0.0).sharpness, 1.0, accuracy: 1e-6)
    }

    func testBreathPulse_coherenceInvertsToSharpness() {
        // sharpness = 1 - coherence
        XCTAssertEqual(BioHaptics.breathPulse(breathPhase: 0.5, coherence: 0.3).sharpness, 0.7, accuracy: 1e-6)
    }

    func testBreathPulse_clampsOutOfRangePhase() {
        XCTAssertEqual(BioHaptics.breathPulse(breathPhase: -1, coherence: 0.5).intensity, 0, accuracy: 1e-6)
        XCTAssertEqual(BioHaptics.breathPulse(breathPhase: 2, coherence: 0.5).intensity, 0, accuracy: 1e-6)
    }
}
