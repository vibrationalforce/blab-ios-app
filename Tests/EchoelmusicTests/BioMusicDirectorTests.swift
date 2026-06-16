// BioMusicDirectorTests.swift
// Echoelmusic — bio→music direction (privacy-safe summary + deterministic fallback).
// The on-device LLM path is iOS 26-only and device-gated; these cover the always-
// available, no-LLM logic that the feature degrades to on iOS 18.

import XCTest
@testable import Echoelmusic

final class BioMusicDirectorTests: XCTestCase {

    private func frame(hr: Float, coherence: Float, breath: Float) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: 0, heartRateBPM: hr, hrvNormalized: 0.5,
            breathRate: breath, breathPhase: 0, coherence: coherence,
            motionEnergy: 0, source: .fallback)
    }

    func testSummaryBucketsArousalSteadinessBreath() {
        let calm = BioStateSummary(from: frame(hr: 55, coherence: 0.8, breath: 6))
        XCTAssertEqual(calm.arousal, "low")
        XCTAssertEqual(calm.steadiness, "steady and coherent")
        XCTAssertEqual(calm.breath, "slow")

        let amped = BioStateSummary(from: frame(hr: 120, coherence: 0.1, breath: 22))
        XCTAssertEqual(amped.arousal, "high")
        XCTAssertEqual(amped.steadiness, "restless")
        XCTAssertEqual(amped.breath, "fast")
    }

    func testSummaryPromptIsAdjectivesOnly_noBiometrics() {
        // The prompt handed to the model must not leak raw numbers/identifiers.
        let p = BioStateSummary(from: frame(hr: 123, coherence: 0.42, breath: 17)).prompt
        XCTAssertFalse(p.contains("123"))
        XCTAssertFalse(p.contains("17"))
        XCTAssertTrue(p.contains("arousal"))
    }

    func testFallbackIsDeterministicAndInRange() {
        let f = frame(hr: 58, coherence: 0.7, breath: 6)
        let a = BioDirectionFallback.direction(for: f)
        let b = BioDirectionFallback.direction(for: f)
        XCTAssertEqual(a, b)                      // pure / deterministic
        XCTAssertEqual(a.genre, "deep ambient")  // low arousal → ambient
        XCTAssertEqual(a.space, "hall")
    }

    func testFallbackHighArousalIsEnergetic() {
        let d = BioDirectionFallback.direction(for: frame(hr: 130, coherence: 0.2, breath: 24))
        XCTAssertEqual(d.genre, "psytrance")
        XCTAssertEqual(d.mood, "tense")          // restless → tense
        XCTAssertEqual(d.space, "room")
    }

    func testGateOffByDefaultInTestEnvironment() {
        // The simulator/test host has no on-device model → gate must be closed,
        // guaranteeing no accidental LLM/cloud path in CI.
        XCTAssertFalse(OnDeviceModelGate.isOnDeviceLLMAvailable)
    }
}
