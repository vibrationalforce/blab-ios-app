//
//  CameraRPPGTrustTests.swift
//  Echoelmusic — rPPG "earn trust" gate.
//
//  Tests the pure `CameraRPPGBioPublisher.pulseTrustworthy(confidence:autoStrength:)` gate.
//  A reading may move the shown pulse / latch the tempo only when it is BOTH confident AND
//  corroborated by real periodicity (autocorrelation) — so a poorly-placed finger, where the
//  peak-counter self-agrees on a noisy signal, can no longer show or seed a fantasy number
//  (device log 2026-07-04: acf 0.14 / conf 0.90 "settled" at a wrong 79 bpm; true pulse ~54).
//

#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

final class CameraRPPGTrustTests: XCTestCase {

    typealias P = CameraRPPGBioPublisher

    func testRealLock_confidentAndCorroborated_isTrusted() {
        // This device's real locks: strong acf (0.57–0.84) with confidence.
        XCTAssertTrue(P.pulseTrustworthy(confidence: 0.90, autoStrength: 0.80))
        XCTAssertTrue(P.pulseTrustworthy(confidence: 0.72, autoStrength: 0.65)) // the true late lock (bpm 54–55)
    }

    func testBadReading_confidentButNoPeriodicity_isRejected() {
        // The exact device-log failure: high confidence from peak-count self-agreement, but
        // the autocorrelation found almost nothing → must NOT be trusted (would have shown 79).
        XCTAssertFalse(P.pulseTrustworthy(confidence: 0.90, autoStrength: 0.14))
        XCTAssertFalse(P.pulseTrustworthy(confidence: 0.86, autoStrength: 0.16))
    }

    func testLowConfidence_isRejected_evenWithPeriodicity() {
        XCTAssertFalse(P.pulseTrustworthy(confidence: 0.50, autoStrength: 0.90))
    }

    func testBoundaries() {
        // Confidence gate at displayThreshold (0.6), acf gate at trustAutoFloor (0.4).
        XCTAssertTrue(P.pulseTrustworthy(confidence: P.displayThreshold, autoStrength: P.trustAutoFloor))
        XCTAssertFalse(P.pulseTrustworthy(confidence: P.displayThreshold, autoStrength: 0.39))
        XCTAssertFalse(P.pulseTrustworthy(confidence: 0.59, autoStrength: 0.90))
    }
}
#endif
