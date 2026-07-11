// BioModulationTests.swift
// Echoel — the universal bio-binding spine: manual-by-default, optionally
// body-driven, heartbeat-as-clock. Full manual access must always hold.

import XCTest
@testable import Echoelmusic

final class BioModulationTests: XCTestCase {

    private func bio(hr: Float = 60, hrv: Float = 0.5, breath: Float = 0.5,
                     coherence: Float = 0.5, motion: Float = 0.5) -> BioSampleFrame {
        BioSampleFrame(timestamp: 0, heartRateBPM: hr, hrvNormalized: hrv,
                       breathRate: 6, breathPhase: breath, coherence: coherence,
                       motionEnergy: motion, source: .fallback)
    }

    // MARK: source normalisation (the ONE canonical ModSource — Q1 de-dup 2026-07-11)

    func testHeartRateNormalisation() {
        XCTAssertEqual(ModSource.heartRate.normalizedValue(from: bio(hr: 40)), 0, accuracy: 1e-6)
        XCTAssertEqual(ModSource.heartRate.normalizedValue(from: bio(hr: 200)), 1, accuracy: 1e-6)
        XCTAssertEqual(ModSource.heartRate.normalizedValue(from: bio(hr: 120)), 0.5, accuracy: 1e-6)
    }

    func testSignalsClampedToUnit() {
        XCTAssertEqual(ModSource.motion.normalizedValue(from: bio(motion: 9)), 1, accuracy: 1e-6)
        XCTAssertEqual(ModSource.coherence.normalizedValue(from: bio(coherence: -3)), 0, accuracy: 1e-6)
    }

    func testEverySourceHasName() {
        for s in ModSource.allCases { XCTAssertFalse(s.displayName.isEmpty) }
    }

    // MARK: manual control always works (no preset lock-in)

    func testManual_returnsClampedBase_evenWithBio() {
        let p = BoundParameter(base: 250, range: 0...1000, source: nil, amount: 1)
        XCTAssertEqual(p.resolved(from: bio(hr: 200)), 250, accuracy: 1e-9, "manual ignores bio")
        XCTAssertFalse(p.isBound)
    }

    func testManual_baseClampedToRange() {
        let p = BoundParameter(base: 5000, range: 0...1000)
        XCTAssertEqual(p.resolved(from: nil), 1000, accuracy: 1e-9)
    }

    // MARK: bio binding

    func testBound_pushesTowardMaxAsSignalRises() {
        var p = BoundParameter(base: 100, range: 100...500, source: .heartRate, amount: 1)
        XCTAssertEqual(p.resolved(from: bio(hr: 40)), 100, accuracy: 1e-9)   // signal 0
        XCTAssertEqual(p.resolved(from: bio(hr: 200)), 500, accuracy: 1e-9)  // signal 1 → +span
        p.amount = 0.5
        XCTAssertEqual(p.resolved(from: bio(hr: 200)), 300, accuracy: 1e-9)  // +half span
    }

    func testNegativeAmount_pushesDown() {
        let p = BoundParameter(base: 500, range: 100...500, source: .breathPhase, amount: -1)
        XCTAssertEqual(p.resolved(from: bio(breath: 1)), 100, accuracy: 1e-9)
    }

    func testBound_butNoFrame_fallsBackToManual() {
        let p = BoundParameter(base: 300, range: 0...1000, source: .heartRate, amount: 1)
        XCTAssertEqual(p.resolved(from: nil), 300, accuracy: 1e-9)
    }

    func testAmountClampedToBipolarUnit() {
        let p = BoundParameter(base: 0, range: 0...10, source: .coherence, amount: 9)
        XCTAssertEqual(p.amount, 1, accuracy: 1e-9)
    }

    // MARK: persistence (Q7 bind-a-knob UI must survive relaunch)

    func testBoundParameter_codableRoundTrip() throws {
        let p = BoundParameter(base: 220, range: 20...2000, source: .coherence, amount: -0.6)
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(BoundParameter.self, from: data)
        XCTAssertEqual(back, p, "a bound parameter round-trips so bindings persist")
        XCTAssertEqual(back.resolved(from: bio(coherence: 1)),
                       p.resolved(from: bio(coherence: 1)), accuracy: 1e-9,
                       "the decoded binding resolves identically")
    }

    func testBoundParameter_manualCodableRoundTrip() throws {
        let p = BoundParameter(base: 0.5, range: 0...1)   // source nil = manual
        let back = try JSONDecoder().decode(BoundParameter.self,
                                            from: try JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
        XCTAssertNil(back.source, "a manual (unbound) parameter stays manual after decode")
    }

    // MARK: clock — heartbeat vs BPM-lock

    func testFixedBPMClock() {
        let c = ClockSource.fixedBPM(120)
        XCTAssertEqual(c.effectiveBPM(heartRateBPM: 999), 120, accuracy: 1e-9, "lock ignores HR")
        XCTAssertEqual(c.beatSeconds(heartRateBPM: 0), 0.5, accuracy: 1e-9)
        XCTAssertFalse(c.isHeartbeat)
    }

    func testHeartbeatClock_followsHR_clamped() {
        let c = ClockSource.heartbeat
        XCTAssertEqual(c.effectiveBPM(heartRateBPM: 72), 72, accuracy: 1e-9)
        XCTAssertEqual(c.effectiveBPM(heartRateBPM: 10), 40, accuracy: 1e-9)  // clamp floor
        XCTAssertEqual(c.effectiveBPM(heartRateBPM: 500), 200, accuracy: 1e-9) // clamp ceil
        XCTAssertTrue(c.isHeartbeat)
    }
}
