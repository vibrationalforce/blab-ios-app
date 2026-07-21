// BioEngineTests.swift
// Echoelmusic — Bio Engine Tests
//
// Tests for BioSnapshot, BioDataSource, and EchoelBioEngine state management.
// Uses non-HealthKit platform stub for pure computation testing.

import XCTest
@testable import Echoelmusic

// MARK: - BioSnapshot Tests

final class BioSnapshotTests: XCTestCase {

    func testDefaults() {
        let snapshot = BioSnapshot()
        XCTAssertEqual(snapshot.heartRate, 72.0)
        XCTAssertEqual(snapshot.hrvNormalized, 0.5)
        XCTAssertEqual(snapshot.hrvRMSSD, 50.0)
        XCTAssertEqual(snapshot.breathRate, 12.0)
        XCTAssertEqual(snapshot.breathPhase, 0.5)
        XCTAssertEqual(snapshot.coherence, 0.5)
        XCTAssertEqual(snapshot.lfHfRatio, 1.0)
    }

    func testSource_default() {
        let snapshot = BioSnapshot()
        XCTAssertEqual(snapshot.source, .fallback)
    }

    func testMutation() {
        var snapshot = BioSnapshot()
        snapshot.heartRate = 80.0
        snapshot.hrvNormalized = 0.8
        snapshot.coherence = 0.9
        XCTAssertEqual(snapshot.heartRate, 80.0)
        XCTAssertEqual(snapshot.hrvNormalized, 0.8)
        XCTAssertEqual(snapshot.coherence, 0.9)
    }

    func testTimestamp() {
        let before = Date()
        let snapshot = BioSnapshot()
        let after = Date()
        XCTAssertGreaterThanOrEqual(snapshot.timestamp, before)
        XCTAssertLessThanOrEqual(snapshot.timestamp, after)
    }

    func testSendable() {
        // BioSnapshot must be Sendable for cross-actor use
        let snapshot = BioSnapshot()
        let sendableCopy: any Sendable = snapshot
        XCTAssertNotNil(sendableCopy)
    }
}

// MARK: - BioDataSource Tests

final class BioDataSourceTests: XCTestCase {

    func testAllSources() {
        XCTAssertEqual(BioDataSource.healthKit.rawValue, "HealthKit")
        XCTAssertEqual(BioDataSource.appleWatch.rawValue, "Apple Watch")
        XCTAssertEqual(BioDataSource.chestStrap.rawValue, "Chest Strap")
        XCTAssertEqual(BioDataSource.arkit.rawValue, "ARKit Face")
        XCTAssertEqual(BioDataSource.microphone.rawValue, "Microphone")
        XCTAssertEqual(BioDataSource.fallback.rawValue, "Simulated")
    }

    func testSendable() {
        let source: any Sendable = BioDataSource.healthKit
        XCTAssertNotNil(source)
    }
}

// MARK: - EchoelBioEngine State Tests

@MainActor
final class EchoelBioEngineTests: XCTestCase {

    func testSharedInstance() {
        let engine = EchoelBioEngine.shared
        XCTAssertNotNil(engine)
        // Singleton returns same instance
        XCTAssertTrue(engine === EchoelBioEngine.shared)
    }

    func testInitialState() {
        let engine = EchoelBioEngine.shared
        XCTAssertFalse(engine.isStreaming)
        XCTAssertFalse(engine.isAuthorized)
    }

    func testDefaultSmoothedValues() {
        let engine = EchoelBioEngine.shared
        XCTAssertEqual(engine.smoothHeartRate, 72.0)
        XCTAssertEqual(engine.smoothHRV, 0.5)
        XCTAssertEqual(engine.smoothCoherence, 0.5)
        XCTAssertEqual(engine.smoothBreathPhase, 0.5)
        XCTAssertEqual(engine.smoothBreathDepth, 0.5)
    }

    func testAudioParameters_returnsFloats() {
        let engine = EchoelBioEngine.shared
        let params = engine.audioParameters()
        XCTAssertEqual(params.coherence, Float(engine.smoothCoherence), accuracy: 0.001)
        XCTAssertEqual(params.hrv, Float(engine.smoothHRV), accuracy: 0.001)
        XCTAssertEqual(params.heartRate, Float(engine.smoothHeartRate), accuracy: 0.001)
        XCTAssertEqual(params.breathPhase, Float(engine.smoothBreathPhase), accuracy: 0.001)
        XCTAssertEqual(params.breathDepth, Float(engine.smoothBreathDepth), accuracy: 0.001)
    }

    func testAudioParameters_valuesInRange() {
        let params = EchoelBioEngine.shared.audioParameters()
        // All normalized values should be in [0, 1]
        XCTAssertGreaterThanOrEqual(params.coherence, 0.0)
        XCTAssertLessThanOrEqual(params.coherence, 1.0)
        XCTAssertGreaterThanOrEqual(params.hrv, 0.0)
        XCTAssertLessThanOrEqual(params.hrv, 1.0)
        XCTAssertGreaterThanOrEqual(params.breathPhase, 0.0)
        XCTAssertLessThanOrEqual(params.breathPhase, 1.0)
        XCTAssertGreaterThanOrEqual(params.breathDepth, 0.0)
        XCTAssertLessThanOrEqual(params.breathDepth, 1.0)
    }

    func testStartStreaming() {
        let engine = EchoelBioEngine.shared
        engine.startStreaming()
        XCTAssertTrue(engine.isStreaming)
    }

    func testStopStreaming() {
        let engine = EchoelBioEngine.shared
        engine.startStreaming()
        engine.stopStreaming()
        XCTAssertFalse(engine.isStreaming)
    }

    func testRequestAuthorization_nonHealthKitPlatform() async {
        // On Linux/non-HealthKit: always returns false
        let result = await EchoelBioEngine.shared.requestAuthorization()
        XCTAssertFalse(result)
    }

    func testSnapshot_defaultValues() {
        let snapshot = EchoelBioEngine.shared.snapshot
        XCTAssertEqual(snapshot.heartRate, 72.0)
        XCTAssertEqual(snapshot.coherence, 0.5)
        XCTAssertEqual(snapshot.source, .fallback)
    }
}

// MARK: - RMSSD Algorithm Tests (Pure Math)

final class RMSSDAlgorithmTests: XCTestCase {

    /// Standalone RMSSD calculation matching EchoelBioEngine's algorithm
    private func calculateRMSSD(rrIntervals: [Double]) -> Double {
        guard rrIntervals.count >= 2 else { return 0.0 }

        var sumSquaredDiffs: Double = 0.0
        var count = 0

        for i in 1..<rrIntervals.count {
            let diff = rrIntervals[i] - rrIntervals[i - 1]
            sumSquaredDiffs += diff * diff
            count += 1
        }

        guard count > 0 else { return 0.0 }
        return (sumSquaredDiffs / Double(count)).squareRoot()
    }

    /// Standalone coherence calculation matching EchoelBioEngine's algorithm
    private func calculateCoherence(rrIntervals: [Double]) -> Double {
        guard rrIntervals.count >= 10 else { return 0.0 }

        let diffs = zip(rrIntervals.dropFirst(), rrIntervals).map { $0 - $1 }
        guard !diffs.isEmpty else { return 0.0 }
        let mean = diffs.reduce(0, +) / Double(diffs.count)
        let variance = diffs.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(diffs.count)

        return max(0.0, min(1.0, 1.0 - (variance / 2000.0)))
    }

    func testRMSSD_regularHeartbeat() {
        // Perfectly regular 60 BPM (1000ms intervals)
        let intervals = [Double](repeating: 1000.0, count: 20)
        let rmssd = calculateRMSSD(rrIntervals: intervals)
        XCTAssertEqual(rmssd, 0.0, accuracy: 0.001, "Constant intervals should have zero RMSSD")
    }

    func testRMSSD_alternatingIntervals() {
        // Alternating 950ms/1050ms
        let intervals = (0..<20).map { $0 % 2 == 0 ? 950.0 : 1050.0 }
        let rmssd = calculateRMSSD(rrIntervals: intervals)
        XCTAssertEqual(rmssd, 100.0, accuracy: 0.001, "100ms alternation = 100ms RMSSD")
    }

    func testRMSSD_insufficientData() {
        let rmssd = calculateRMSSD(rrIntervals: [1000.0])
        XCTAssertEqual(rmssd, 0.0)
    }

    func testRMSSD_twoIntervals() {
        let rmssd = calculateRMSSD(rrIntervals: [1000.0, 1050.0])
        XCTAssertEqual(rmssd, 50.0, accuracy: 0.001)
    }

    func testRMSSD_normalization() {
        // RMSSD normalization: 100ms → 1.0, 20ms → 0.2
        let rmssdNormalizationMax = 100.0
        let rmssd = 50.0
        let normalized = min(rmssd / rmssdNormalizationMax, 1.0)
        XCTAssertEqual(normalized, 0.5, accuracy: 0.001)
    }

    func testRMSSD_normalization_clamps() {
        let rmssdNormalizationMax = 100.0
        let rmssd = 150.0 // Above max
        let normalized = min(rmssd / rmssdNormalizationMax, 1.0)
        XCTAssertEqual(normalized, 1.0, "Should clamp to 1.0")
    }

    func testCoherence_regularPattern() {
        // Very regular sinusoidal HRV → high coherence
        let intervals = (0..<20).map { 1000.0 + 20.0 * sin(Double($0) * 0.5) }
        let coherence = calculateCoherence(rrIntervals: intervals)
        XCTAssertGreaterThan(coherence, 0.8, "Regular pattern should yield high coherence")
    }

    func testCoherence_erraticPattern() {
        // Large random-like jumps → low coherence
        let intervals: [Double] = [500, 1200, 600, 1100, 550, 1300, 700, 1000, 450, 1250, 800, 900]
        let coherence = calculateCoherence(rrIntervals: intervals)
        XCTAssertLessThan(coherence, 0.5, "Erratic pattern should yield low coherence")
    }

    func testCoherence_constantIntervals() {
        // Perfect regularity
        let intervals = [Double](repeating: 1000.0, count: 15)
        let coherence = calculateCoherence(rrIntervals: intervals)
        XCTAssertEqual(coherence, 1.0, accuracy: 0.001, "Zero variance = maximum coherence")
    }

    func testCoherence_insufficientData() {
        let coherence = calculateCoherence(rrIntervals: [1000, 1010, 990])
        XCTAssertEqual(coherence, 0.0, "Need ≥10 intervals")
    }

    func testCoherence_bounds() {
        // Coherence must always be in [0, 1]
        let patterns: [[Double]] = [
            [Double](repeating: 1000.0, count: 15),
            (0..<15).map { Double($0) * 100.0 },
            (0..<15).map { _ in 1000.0 + Double.random(in: -500...500) }
        ]

        for pattern in patterns {
            let coherence = calculateCoherence(rrIntervals: pattern)
            XCTAssertGreaterThanOrEqual(coherence, 0.0, "Coherence must be ≥ 0")
            XCTAssertLessThanOrEqual(coherence, 1.0, "Coherence must be ≤ 1")
        }
    }

    func testEMA_smoothing() {
        // Test exponential moving average with alpha=0.15
        let alpha = 0.15
        var smoothed = 0.5

        // Apply 10 samples of value 1.0
        for _ in 0..<10 {
            smoothed = smoothed * (1.0 - alpha) + 1.0 * alpha
        }

        // After 10 steps from 0.5 toward 1.0 with alpha=0.15
        // Expected: 0.5 * (0.85^10) + 1.0 * (1 - 0.85^10)
        let expected = 0.5 * pow(0.85, 10) + 1.0 * (1.0 - pow(0.85, 10))
        XCTAssertEqual(smoothed, expected, accuracy: 0.001)
        XCTAssertGreaterThan(smoothed, 0.5, "Should move toward 1.0")
        XCTAssertLessThan(smoothed, 1.0, "Should not reach 1.0 in 10 steps")
    }
}
