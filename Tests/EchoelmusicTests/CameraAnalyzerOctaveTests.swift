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
        // At/below the 0.4 gate, peak-counting still leads (low-SNR fingertip windows).
        XCTAssertEqual(A.autoTrust(estimate: 100, autoBPM: 75, autoStrength: 0.4), 100, accuracy: 0.001)
        XCTAssertEqual(A.autoTrust(estimate: 100, autoBPM: 75, autoStrength: 0.35), 100, accuracy: 0.001)
    }

    func testAutoTrust_moderateAcfNowPulls() {
        // Data-backed (device logs 2026-06-30): autocorrelation is reliable from acf≈0.4,
        // exactly where peak-counting wanders — so a MODERATE 0.5 now nudges the estimate
        // toward the steady fundamental instead of leaving it to chase the noisy count.
        let pulled = A.autoTrust(estimate: 100, autoBPM: 60, autoStrength: 0.5)
        XCTAssertLessThan(pulled, 100)
        XCTAssertGreaterThan(pulled, 60)
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

    // MARK: - Motion-amplitude reject (false-lock guard)

    func testMotionAmplitude_plausiblePulse_isNotMotion() {
        // Real fingertip pulse AC seen in device logs: up to ~0.16 (strongest clean lock).
        XCTAssertFalse(A.isMotionAmplitude(0.03))
        XCTAssertFalse(A.isMotionAmplitude(0.08))
        XCTAssertFalse(A.isMotionAmplitude(0.16))   // strongest real lock observed → kept
    }

    func testMotionAmplitude_largeSwing_isMotion() {
        // Hard-press / re-grip windows (device logs: 0.22–0.33, and a 0.76 swing) → motion.
        XCTAssertTrue(A.isMotionAmplitude(0.22))
        XCTAssertTrue(A.isMotionAmplitude(0.33))
        XCTAssertTrue(A.isMotionAmplitude(0.76))
    }

    func testMotionAmplitude_gateBoundary() {
        // Gate is `> 0.20`: at/below 0.20 is kept, just above is rejected.
        XCTAssertFalse(A.isMotionAmplitude(0.20))
        XCTAssertTrue(A.isMotionAmplitude(0.2001))
    }

    // MARK: - Motion-window confidence bleed (don't wipe a good lock on a blip)

    func testMotionBleed_strongAcf_bleedsGently() {
        // A brief pressure blip while the autocorrelation still confirms a strong pulse
        // (acf > 0.4) must barely dent confidence — it's applied per-sample (~15-30/tick),
        // so it stays near 1. Device log 2026-07-02: conf 0.96 → 0.00 in one tick was the bug.
        XCTAssertEqual(A.motionBleed(autoStrength: 0.5), 0.98, accuracy: 0.0001)
        XCTAssertEqual(A.motionBleed(autoStrength: 0.9), 0.98, accuracy: 0.0001)
        // Even compounded across a whole tick, a strong-acf lock survives the 0.35 gate.
        XCTAssertGreaterThan(0.96 * pow(A.motionBleed(autoStrength: 0.7), 20), 0.35)
    }

    func testMotionBleed_weakAcf_bleedsHard() {
        // The true motion / false-lock case (amp≈0.76, acf≈0.2) still bleeds hard so a
        // motion run can neither earn nor hold a lock — preserves the false-lock guard.
        XCTAssertEqual(A.motionBleed(autoStrength: 0.2), 0.6, accuracy: 0.0001)
        XCTAssertEqual(A.motionBleed(autoStrength: 0.0), 0.6, accuracy: 0.0001)
        // Compounded across a tick it collapses well below the lock gate.
        XCTAssertLessThan(0.96 * pow(A.motionBleed(autoStrength: 0.2), 15), 0.35)
    }

    func testMotionBleed_gateBoundaryIsExclusive() {
        // Boundary is `> 0.4`: exactly 0.4 is still the hard bleed, just above is gentle.
        XCTAssertEqual(A.motionBleed(autoStrength: 0.4), 0.6, accuracy: 0.0001)
        XCTAssertEqual(A.motionBleed(autoStrength: 0.401), 0.98, accuracy: 0.0001)
    }

    // MARK: - Finger-frame red-floor hysteresis (limit-cycle fix)

    func testFingerFrame_acquiresOnlyAboveHardFloor() {
        // Not yet detected: needs R > 0.28 (red-dominant). 0.30 acquires; 0.25 does not.
        XCTAssertTrue(A.isFingerFrame(avgR: 0.30, avgG: 0.10, avgB: 0.08, wasDetected: false))
        XCTAssertFalse(A.isFingerFrame(avgR: 0.25, avgG: 0.10, avgB: 0.08, wasDetected: false))
    }

    func testFingerFrame_holdsThroughDipsOnceAcquired() {
        // The 2026-07-02 device-log regression: once acquired, a lit finger dipping to
        // R≈0.21–0.25 must STILL read as present so the window stays continuous and
        // the pulse can lock — the old single 0.28 floor dropped these → bpm never locked.
        XCTAssertTrue(A.isFingerFrame(avgR: 0.25, avgG: 0.10, avgB: 0.08, wasDetected: true))
        XCTAssertTrue(A.isFingerFrame(avgR: 0.21, avgG: 0.09, avgB: 0.07, wasDetected: true))
    }

    func testFingerFrame_holdsThroughOwnDarkExposureLock() {
        // The 2026-07-15 device-log regression (build 2361, session 2, 92 s NO lock):
        // the app's own strict-dark exposure lock froze exposure at bright≈0.08–0.10,
        // which puts a genuinely-held finger at R≈0.15–0.17 — BELOW the old 0.18 hold
        // floor → finger=no → window flush → re-acquire needs 0.28 which the dark lock
        // never reaches = limit cycle. Session 3 proved bright 0.10 LOCKS (q 0.97) when
        // the detector holds. The hold floor must sit below the dark lock's R output.
        XCTAssertTrue(A.isFingerFrame(avgR: 0.17, avgG: 0.07, avgB: 0.05, wasDetected: true))
        XCTAssertTrue(A.isFingerFrame(avgR: 0.15, avgG: 0.06, avgB: 0.05, wasDetected: true))
        XCTAssertTrue(A.isFingerFrame(avgR: 0.13, avgG: 0.05, avgB: 0.04, wasDetected: true))
    }

    func testFingerFrame_releasesBelowHoldFloor() {
        // Finger truly gone: below the 0.12 hold floor it releases even when previously
        // held (log t=1141: R=0.09 with the finger actually drifting off stays released).
        XCTAssertFalse(A.isFingerFrame(avgR: 0.10, avgG: 0.04, avgB: 0.03, wasDetected: true))
        XCTAssertFalse(A.isFingerFrame(avgR: 0.09, avgG: 0.04, avgB: 0.03, wasDetected: true))
    }

    func testFingerFrame_redDominanceGatesRejectNonFinger() {
        // A bright but non-red scene (R not dominant over G/B) is rejected at EITHER floor,
        // so the relaxed hold floor can't false-hold on ambient light.
        XCTAssertFalse(A.isFingerFrame(avgR: 0.40, avgG: 0.39, avgB: 0.38, wasDetected: true))
        XCTAssertFalse(A.isFingerFrame(avgR: 0.40, avgG: 0.39, avgB: 0.38, wasDetected: false))
    }

    func testFingerFrame_saturatedFrameCountsAsPresent() {
        // All channels clipped (finger pressed too hard / torch washout): still present,
        // so the lock holds through a saturated spell instead of dropping to no-finger.
        XCTAssertTrue(A.isFingerFrame(avgR: 0.95, avgG: 0.94, avgB: 0.93, wasDetected: false))
    }

    // MARK: - Adaptive refractory (dicrotic-notch reject)

    func testRefractory_noPlausiblePeriod_fallsBackTo300ms() {
        XCTAssertEqual(A.refractorySeconds(autoBPM: 0), 0.3, accuracy: 0.0001)
        XCTAssertEqual(A.refractorySeconds(autoBPM: 39), 0.3, accuracy: 0.0001)   // below floor
        XCTAssertEqual(A.refractorySeconds(autoBPM: 181), 0.3, accuracy: 0.0001)  // above ceiling
    }

    func testRefractory_isHalfTheBeatPeriod() {
        // 60 bpm → 1.0 s beat → 0.5 s refractory (rejects the ~0.4 s dicrotic notch,
        // keeps the next 1.0 s-away beat). The device-log inflation case (auto≈55-65).
        XCTAssertEqual(A.refractorySeconds(autoBPM: 60), 0.5, accuracy: 0.0001)
        XCTAssertEqual(A.refractorySeconds(autoBPM: 55), 0.5 * 60.0 / 55.0, accuracy: 0.0001)
    }

    func testRefractory_clampedToRange() {
        // Slow rate would give >0.6 → clamp 0.6; fast rate <0.3 → clamp 0.3 (≤200 bpm).
        XCTAssertEqual(A.refractorySeconds(autoBPM: 45), 0.6, accuracy: 0.0001)   // 0.5*60/45=0.667→0.6
        XCTAssertEqual(A.refractorySeconds(autoBPM: 150), 0.3, accuracy: 0.0001)  // 0.5*60/150=0.2→0.3
    }

    // MARK: - Physiological slew limiter (audit 2026-07-02, P0.1)

    func testSlew_clampsImplausibleJumpUp() {
        // The acf=0 runaway: estimate 60, a bad window wants 140. Over ~0.27 s
        // (a typical window cadence) at 8 bpm/s the committed value can move ≤ ~2.16.
        let out = A.slewLimited(previous: 60, target: 140, maxDelta: 8.0 * 0.27)
        XCTAssertEqual(out, 62.16, accuracy: 0.001)
    }

    func testSlew_clampsImplausibleJumpDown() {
        let out = A.slewLimited(previous: 120, target: 40, maxDelta: 8.0 * 0.5)
        XCTAssertEqual(out, 116.0, accuracy: 0.001) // 120 - 4
    }

    func testSlew_passesPlausibleChange() {
        // A change within the allowed delta is untouched — a genuine ramp still tracks.
        XCTAssertEqual(A.slewLimited(previous: 60, target: 63, maxDelta: 8.0), 63, accuracy: 0.001)
        XCTAssertEqual(A.slewLimited(previous: 60, target: 55, maxDelta: 8.0), 55, accuracy: 0.001)
    }

    func testSlew_zeroDeltaIsNoLimit() {
        // No elapsed time (or first commit) → the limiter must not clamp.
        XCTAssertEqual(A.slewLimited(previous: 60, target: 140, maxDelta: 0), 140, accuracy: 0.001)
    }
}
#endif
