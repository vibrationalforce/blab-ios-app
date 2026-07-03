//
//  CameraAnalyzerRippleTests.swift
//  Echoelmusic — rPPG uncorroborated-ripple guard.
//
//  Tests the pure `CameraAnalyzer.isUncorroboratedRipple` gate that stops a mid-amplitude
//  MOTION wobble (elevated amplitude but ZERO autocorrelation) from being peak-counted into
//  a steady, self-agreeing false rate — the device-log 2026-07-03 pulse jump (54→82 at
//  amp≈0.06 / acf=0.00). Guarded by canImport(AVFoundation): CameraAnalyzer only compiles
//  where AVFoundation exists.
//

#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

final class CameraAnalyzerRippleTests: XCTestCase {

    typealias A = CameraAnalyzer

    func testArtifact_elevatedAmplitudeNoPeriodicity_isRipple() {
        // The exact device-log signature: amp≈0.06, acf=0.00 → flagged.
        XCTAssertTrue(A.isUncorroboratedRipple(amplitude: 0.06, autoStrength: 0.00))
        XCTAssertTrue(A.isUncorroboratedRipple(amplitude: 0.10, autoStrength: 0.10))
    }

    func testRestingLock_lowAmplitude_isNotRipple() {
        // A steady resting lock (this device: amp 0.017–0.026) is below the band — spared
        // even though its autocorrelation may be weak.
        XCTAssertFalse(A.isUncorroboratedRipple(amplitude: 0.025, autoStrength: 0.10))
        XCTAssertFalse(A.isUncorroboratedRipple(amplitude: 0.045, autoStrength: 0.00))
    }

    func testRealPulse_withPeriodicity_isNotRipple() {
        // A real pulse carries autocorrelation even at elevated amplitude (device first-lock:
        // amp≈0.11, acf≈0.32) → NOT a ripple, must pass through.
        XCTAssertFalse(A.isUncorroboratedRipple(amplitude: 0.11, autoStrength: 0.32))
        XCTAssertFalse(A.isUncorroboratedRipple(amplitude: 0.06, autoStrength: 0.20))
    }

    func testHardMotion_isLeftToTheHardGate() {
        // At/above the hard motion threshold (0.20) the ORIGINAL isMotionAmplitude gate owns
        // the window; the soft gate deliberately does not double-count it.
        XCTAssertFalse(A.isUncorroboratedRipple(amplitude: 0.25, autoStrength: 0.00))
        XCTAssertTrue(A.isMotionAmplitude(0.25))
    }

    func testBandBoundaries() {
        // Lower bound is exclusive at 0.05; upper bound inclusive at 0.20; strength gate at 0.15.
        XCTAssertFalse(A.isUncorroboratedRipple(amplitude: 0.05, autoStrength: 0.00)) // == lower bound
        XCTAssertTrue(A.isUncorroboratedRipple(amplitude: 0.051, autoStrength: 0.00))
        XCTAssertTrue(A.isUncorroboratedRipple(amplitude: 0.20, autoStrength: 0.14))
        XCTAssertFalse(A.isUncorroboratedRipple(amplitude: 0.10, autoStrength: 0.15)) // == strength gate
    }
}

#endif
