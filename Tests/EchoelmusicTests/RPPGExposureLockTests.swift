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
}
