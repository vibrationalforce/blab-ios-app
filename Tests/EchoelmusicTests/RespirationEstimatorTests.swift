// RespirationEstimatorTests.swift
// Echoel — recovering breathing from the heart-rate signal via RSA: feed a synthetic
// HR series modulated at a known breathing rate and check the recovered rate, the
// [0,1] amplitude range, in-phase tracking, and the no-signal fallback.

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
import Foundation
@testable import Echoelmusic

final class RespirationEstimatorTests: XCTestCase {

    /// Feed `seconds` of HR = base + swing·sin(2π·f·t) at `dt` spacing.
    private func run(ratePerMin: Double, swing: Double = 4, base: Double = 62,
                     seconds: Double = 120, dt: Double = 0.1) -> RespirationEstimator {
        var est = RespirationEstimator()
        let f = ratePerMin / 60.0
        var t = 0.0
        while t <= seconds {
            let hr = base + swing * sin(2 * Double.pi * f * t)
            est.ingest(heartRate: hr, at: t)
            t += dt
        }
        return est
    }

    func testRecoversSixPerMinute() {
        let est = run(ratePerMin: 6)
        XCTAssertEqual(est.ratePerMinute, 6, accuracy: 1.0)
        XCTAssertGreaterThan(est.confidence, 0.5)
    }

    func testRecoversTwelvePerMinute() {
        let est = run(ratePerMin: 12)
        XCTAssertEqual(est.ratePerMinute, 12, accuracy: 1.5)
    }

    func testAmplitudeAlwaysInRange() {
        var est = RespirationEstimator()
        let f = 6.0 / 60.0
        var t = 0.0
        while t <= 90 {
            est.ingest(heartRate: 62 + 4 * sin(2 * Double.pi * f * t), at: t)
            XCTAssertGreaterThanOrEqual(est.amplitude, 0.0)
            XCTAssertLessThanOrEqual(est.amplitude, 1.0)
            t += 0.1
        }
    }

    func testAmplitudeTracksBreathInPhase() {
        // Over the steady-state window, (amplitude-0.5) should correlate positively
        // with the HR swing: HR high (inhale, RSA speed-up) → ball toward full.
        var est = RespirationEstimator()
        let f = 6.0 / 60.0
        var t = 0.0
        var sumAB = 0.0, sumBB = 0.0
        while t <= 120 {
            let swing = sin(2 * Double.pi * f * t)
            est.ingest(heartRate: 62 + 4 * swing, at: t)
            if t > 60 {                                  // after warmup
                sumAB += (est.amplitude - 0.5) * swing
                sumBB += swing * swing
            }
            t += 0.1
        }
        XCTAssertGreaterThan(sumBB, 0)
        XCTAssertGreaterThan(sumAB / sumBB, 0, "amplitude must move with the breath, not against it")
    }

    func testNoOscillation_staysNeutral_lowConfidence() {
        var est = RespirationEstimator()
        var t = 0.0
        while t <= 60 { est.ingest(heartRate: 62, at: t); t += 0.1 }
        XCTAssertEqual(est.amplitude, 0.5, accuracy: 0.1)
        XCTAssertLessThan(est.confidence, 0.4)
    }

    func testIgnoresNonFiniteAndOutOfRangeSamples() {
        var est = RespirationEstimator()
        est.ingest(heartRate: .nan, at: 0)
        est.ingest(heartRate: 9999, at: 0.1)
        est.ingest(heartRate: -5, at: 0.2)
        // No valid sample ingested → safe neutral defaults, no crash.
        XCTAssertEqual(est.amplitude, 0.5, accuracy: 1e-9)
        XCTAssertEqual(est.ratePerMinute, 0, accuracy: 1e-9)
    }

    func testReset_clearsState() {
        var est = run(ratePerMin: 6, seconds: 60)
        est.reset()
        XCTAssertEqual(est.amplitude, 0.5, accuracy: 1e-9)
        XCTAssertEqual(est.ratePerMinute, 0, accuracy: 1e-9)
        XCTAssertEqual(est.confidence, 0, accuracy: 1e-9)
    }

    func testToleratesTimeGaps() {
        var est = RespirationEstimator()
        est.ingest(heartRate: 62, at: 0)
        est.ingest(heartRate: 66, at: 0.1)
        est.ingest(heartRate: 60, at: 30)   // big gap — must not crash or NaN
        XCTAssertFalse(est.amplitude.isNaN)
        XCTAssertGreaterThanOrEqual(est.amplitude, 0.0)
        XCTAssertLessThanOrEqual(est.amplitude, 1.0)
    }
}
#endif
