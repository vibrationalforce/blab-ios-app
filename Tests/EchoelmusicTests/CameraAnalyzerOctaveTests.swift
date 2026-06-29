//
//  CameraAnalyzerOctaveTests.swift
//  Echoelmusic — rPPG octave-correction guard (task #6).
//
//  Tests the pure `CameraAnalyzer.octaveCorrected` octave-drift corrector. Guarded by
//  canImport(AVFoundation) because CameraAnalyzer (and the helper) only compile where
//  AVFoundation exists.
//

#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

final class CameraAnalyzerOctaveTests: XCTestCase {

    typealias A = CameraAnalyzer

    func testHalfRate_isDoubledToFundamental() {
        // Peak-count window at ~half the true rate (60 ≈ ½ × 120), confident
        // autocorrelation → corrected to the fundamental by ×2.
        XCTAssertEqual(A.octaveCorrected(raw: 60, autoBPM: 120, autoStrength: 0.7), 120, accuracy: 0.001)
    }

    func testDoubleRate_isHalvedToFundamental() {
        // Window at ~double (140 ≈ 2 × 70) → corrected by ×0.5.
        XCTAssertEqual(A.octaveCorrected(raw: 140, autoBPM: 70, autoStrength: 0.7), 70, accuracy: 0.001)
    }

    func testGenuineHRChange_isUntouched() {
        // Ratios inside the protected 0.625…1.6 band must NOT be folded — the guard only
        // acts in explicit octave territory, so a real HR change always passes.
        XCTAssertEqual(A.octaveCorrected(raw: 100, autoBPM: 100, autoStrength: 0.9), 100, accuracy: 0.001) // 1.0
        XCTAssertEqual(A.octaveCorrected(raw: 96, autoBPM: 64, autoStrength: 0.9), 96, accuracy: 0.001)    // 1.5
        XCTAssertEqual(A.octaveCorrected(raw: 70, autoBPM: 100, autoStrength: 0.9), 70, accuracy: 0.001)   // 0.7
    }

    func testWeakPeriodicity_isIgnored() {
        // Below the strength gate the autocorrelation isn't trusted → raw unchanged even
        // in octave territory.
        XCTAssertEqual(A.octaveCorrected(raw: 60, autoBPM: 120, autoStrength: 0.3), 60, accuracy: 0.001)
    }

    func testInvalidInputs_returnRaw() {
        XCTAssertEqual(A.octaveCorrected(raw: 0, autoBPM: 120, autoStrength: 0.9), 0, accuracy: 0.001)
        XCTAssertEqual(A.octaveCorrected(raw: 60, autoBPM: 0, autoStrength: 0.9), 60, accuracy: 0.001)
    }

    func testPhysiologicalBounds_respected() {
        // Doubling must not exceed the 220 ceiling; halving must not drop below 35.
        XCTAssertEqual(A.octaveCorrected(raw: 118, autoBPM: 236, autoStrength: 0.8), 118, accuracy: 0.001) // 2×=236 > 220 → unchanged
        XCTAssertEqual(A.octaveCorrected(raw: 64, autoBPM: 32, autoStrength: 0.8), 64, accuracy: 0.001)    // ½=32 < 35 → unchanged
    }

    func testBandEdges_areExclusive() {
        // Strict inequalities: ratios exactly at the band edges do NOT correct (the
        // conservative default), pinning the gap semantics against future edits.
        XCTAssertEqual(A.octaveCorrected(raw: 60, autoBPM: 100, autoStrength: 0.8), 60, accuracy: 0.001) // r=0.6
        XCTAssertEqual(A.octaveCorrected(raw: 170, autoBPM: 100, autoStrength: 0.8), 170, accuracy: 0.001) // r=1.7
    }

    func testStrengthGateBoundary() {
        // Guard is `> 0.45`: exactly 0.45 returns raw, just above corrects.
        XCTAssertEqual(A.octaveCorrected(raw: 60, autoBPM: 120, autoStrength: 0.45), 60, accuracy: 0.001)
        XCTAssertEqual(A.octaveCorrected(raw: 60, autoBPM: 120, autoStrength: 0.451), 120, accuracy: 0.001)
    }

    func testCorrectedRate_isStableOnRepeat() {
        // Once corrected to the fundamental, re-applying is a no-op (ratio ≈ 1).
        let once = A.octaveCorrected(raw: 60, autoBPM: 120, autoStrength: 0.8)
        XCTAssertEqual(A.octaveCorrected(raw: once, autoBPM: 120, autoStrength: 0.8), once, accuracy: 0.001)
    }

    // MARK: - autoTrust (non-octave dicrotic-notch inflation)

    func testAutoTrust_pullsInflatedEstimateTowardFundamental() {
        // Device-log case: peak-count inflated to 100 while a strong autocorrelation sits
        // at 75 (acf 0.74). Ratio 1.33 is OUTSIDE octave bands, so octaveCorrected can't
        // help — autoTrust nudges the estimate down toward the confident fundamental.
        let pulled = A.autoTrust(estimate: 100, autoBPM: 75, autoStrength: 0.74)
        XCTAssertLessThan(pulled, 100)            // moved toward auto
        XCTAssertGreaterThan(pulled, 75)          // but not overwritten in one window
    }

    func testAutoTrust_strongerAcfPullsHarder() {
        let weak = A.autoTrust(estimate: 100, autoBPM: 75, autoStrength: 0.6)
        let strong = A.autoTrust(estimate: 100, autoBPM: 75, autoStrength: 0.9)
        XCTAssertLessThan(strong, weak)           // higher acf → closer to the fundamental
    }

    func testAutoTrust_weakPeriodicity_leavesEstimate() {
        // At/below the 0.5 gate, peak-counting still leads (low-SNR fingertip windows).
        XCTAssertEqual(A.autoTrust(estimate: 100, autoBPM: 75, autoStrength: 0.5), 100, accuracy: 0.001)
        XCTAssertEqual(A.autoTrust(estimate: 100, autoBPM: 75, autoStrength: 0.45), 100, accuracy: 0.001)
    }

    func testAutoTrust_pullIsCappedAt80Percent() {
        // Even at perfect acf the per-window pull is capped at 80 %: 100 toward 60 → 68.
        let pulled = A.autoTrust(estimate: 100, autoBPM: 60, autoStrength: 1.0)
        XCTAssertEqual(pulled, 68, accuracy: 0.001)
    }

    func testAutoTrust_invalidInputs_returnEstimate() {
        XCTAssertEqual(A.autoTrust(estimate: 0, autoBPM: 75, autoStrength: 0.9), 0, accuracy: 0.001)
        XCTAssertEqual(A.autoTrust(estimate: 100, autoBPM: 0, autoStrength: 0.9), 100, accuracy: 0.001)
    }

    func testAutoTrust_agreementIsNoOp() {
        // When peak-count already agrees with the fundamental, the pull changes nothing.
        XCTAssertEqual(A.autoTrust(estimate: 75, autoBPM: 75, autoStrength: 0.9), 75, accuracy: 0.001)
    }
}
#endif
