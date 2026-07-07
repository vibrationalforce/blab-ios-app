// RPPGExposureLockTests.swift
// Echoel — guards the rPPG exposure-lock predicates (device log 2026-07-02: the
// exposure locked onto a washed-out frame (bright=0.62) and never produced a pulse
// the whole session). The lock must refuse a bright/flooded scene, and a locked
// scene that drifts bright must be flagged for re-settle.

import XCTest
@testable import Echoelmusic

final class RPPGExposureLockTests: XCTestCase {

    typealias P = CameraRPPGBioPublisher

    func testLocksOnlyWhenFingerPresentAndDark() {
        XCTAssertTrue(P.canLockNow(fingerDetected: true, brightness: 0.30),
                      "a present finger on a dark PPG scene should lock")
        XCTAssertTrue(P.canLockNow(fingerDetected: true, brightness: 0.13),
                      "healthy PPG brightness (~0.13) should lock")
    }

    func testRefusesToLockAWashedFrame() {
        // The exact device-log failure: finger present but bright=0.62 → must NOT lock.
        XCTAssertFalse(P.canLockNow(fingerDetected: true, brightness: 0.62),
                       "must not lock a flooded/bright frame (the bpm=0-forever bug)")
        XCTAssertFalse(P.canLockNow(fingerDetected: true, brightness: 0.90))
    }

    func testNoLockWithoutFinger() {
        XCTAssertFalse(P.canLockNow(fingerDetected: false, brightness: 0.20),
                       "no finger → never lock, even on a dark scene")
    }

    func testWashoutDetection() {
        XCTAssertTrue(P.isWashedOut(brightness: 0.80, red: 0.50), "bright 0.80 is washed")
        XCTAssertTrue(P.isWashedOut(brightness: 0.30, red: 0.95), "clipped red is washed")
        XCTAssertFalse(P.isWashedOut(brightness: 0.30, red: 0.60), "healthy PPG scene is not washed")
        XCTAssertFalse(P.isWashedOut(brightness: 0.13, red: 0.40), "a good lock (0.13) must not trip re-settle")
    }

    func testHealthyLockSurvivesWashoutThreshold() {
        // A brightness that locks must also be safely below the washout threshold, so
        // the lock isn't immediately re-settled (no oscillation).
        for b in [Float(0.13), 0.25, 0.40, 0.55] {
            if P.canLockNow(fingerDetected: true, brightness: b) {
                XCTAssertFalse(P.isWashedOut(brightness: b, red: 0.5),
                               "a lockable brightness \(b) must not be flagged washed out")
            }
        }
    }

    // MARK: - Strict→permissive lock ceiling (device log 1783401421: lock at
    // bright=0.34 froze a too-bright exposure — acf ≈ 0 the whole take)

    func testStrictCeiling_blocksTheBadLock_allowsTheGoodOne() {
        let early = P.lockBrightnessCeiling(fingerPresentTicks: 10)
        XCTAssertLessThan(Float(0.19), early, "the proven-good dark lock (0.19) must pass the strict phase")
        XCTAssertGreaterThanOrEqual(Float(0.34), early, "the proven-bad bright lock (0.34) must WAIT in the strict phase")
    }

    func testCeiling_fallsBackToPermissiveAfterStrictWindow() {
        let late = P.lockBrightnessCeiling(fingerPresentTicks: P.strictLockWindowTicks)
        XCTAssertLessThan(Float(0.34), late, "after the strict window, 0.34 may lock (late soft lock beats none)")
        XCTAssertFalse(P.canLockNow(fingerDetected: true, brightness: 0.62),
                       "the permissive fallback still refuses a washed frame")
    }

    // MARK: - Bright-lock recovery (weak periodicity on a full window)

    func testWeakTicks_notDiagnosticUntilWindowFull_orWhenSettled() {
        XCTAssertEqual(P.weakTicksStep(current: 50, windowFull: false, acf: 0.0, confidence: 0.0, settled: false), 0,
                       "a filling window is not evidence — reset")
        XCTAssertEqual(P.weakTicksStep(current: 50, windowFull: true, acf: 0.0, confidence: 0.0, settled: true), 0,
                       "a settled pulse is never disturbed")
    }

    func testWeakTicks_accumulateOnWeak_decayFastOnStrong_holdBetween() {
        XCTAssertEqual(P.weakTicksStep(current: 3, windowFull: true, acf: 0.05, confidence: 0.0, settled: false), 4)
        XCTAssertEqual(P.weakTicksStep(current: 4, windowFull: true, acf: 0.81, confidence: 0.0, settled: false), 2,
                       "strong acf pays the counter down twice as fast")
        XCTAssertEqual(P.weakTicksStep(current: 4, windowFull: true, acf: 0.3, confidence: 0.0, settled: false), 4,
                       "between floor and strong: hold")
        XCTAssertEqual(P.weakTicksStep(current: 1, windowFull: true, acf: 0.9, confidence: 0.0, settled: false), 0,
                       "decay never goes negative")
    }

    // MARK: - Confidence counts as pulse evidence (device log 1783410930: relock 2/2
    // fired on acf≈0 while the analyzer read a real 76–83 bpm at conf 0.6–0.78 —
    // the relock collapsed a WORKING signal to conf 0.03)

    func testWeakTicks_confidentPulseIsNotWeak_evenWithZeroAcf() {
        XCTAssertEqual(P.weakTicksStep(current: 40, windowFull: true, acf: 0.0, confidence: 0.78, settled: false), 38,
                       "conf 0.78 with acf 0 is a working pulse — pay the counter DOWN (the relock-2/2 kill)")
        XCTAssertEqual(P.weakTicksStep(current: 40, windowFull: true, acf: 0.0, confidence: 0.45, settled: false), 40,
                       "middling confidence: hold, don't accumulate toward a relock")
    }

    func testWeakTicks_stillAccumulatesWhenBothChannelsAreDead() {
        // The case the recovery exists for (log 1783401421 + relock 1/2 of 1783410930):
        // full window, acf ≈ 0 AND conf ≈ 0 → no pulse evidence at all → accumulate.
        XCTAssertEqual(P.weakTicksStep(current: 40, windowFull: true, acf: 0.03, confidence: 0.0, settled: false), 41,
                       "acf and confidence both dead → the lock IS bad, keep counting")
    }

    func testWeakRelock_firesAtThreshold_andIsBounded() {
        XCTAssertFalse(P.weakLockNeedsResettle(weakTicks: P.weakRelockAfterTicks - 1, relocksUsed: 0))
        XCTAssertTrue(P.weakLockNeedsResettle(weakTicks: P.weakRelockAfterTicks, relocksUsed: 0))
        XCTAssertTrue(P.weakLockNeedsResettle(weakTicks: P.weakRelockAfterTicks, relocksUsed: P.maxWeakRelocks - 1))
        XCTAssertFalse(P.weakLockNeedsResettle(weakTicks: 10_000, relocksUsed: P.maxWeakRelocks),
                       "the budget is hard — an inherently weak placement can never thrash the lock")
    }
}
