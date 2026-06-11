// FlashGuardTests.swift
// Echoelmusic — WCAG 2.3.1 visual-safety primitive (pure).

import XCTest
@testable import Echoelmusic

final class FlashGuardTests: XCTestCase {

    func testMaxFlashHz_isThreePerWCAG() {
        XCTAssertEqual(FlashGuard.maxFlashHz, 3.0, accuracy: 1e-9)
    }

    func testSafeFrequency_clampsToMax() {
        XCTAssertEqual(FlashGuard.safeFrequency(5.0), 3.0, accuracy: 1e-9)
        XCTAssertEqual(FlashGuard.safeFrequency(2.0), 2.0, accuracy: 1e-9)
        XCTAssertEqual(FlashGuard.safeFrequency(-1.0), 0.0, accuracy: 1e-9)
    }

    func testSafeFrequency_reduceMotionStopsOscillation() {
        XCTAssertEqual(FlashGuard.safeFrequency(2.0, reduceMotion: true), 0.0, accuracy: 1e-9)
    }

    func testSafeFrequency_nonFiniteIsZero() {
        XCTAssertEqual(FlashGuard.safeFrequency(.nan), 0.0, accuracy: 1e-9)
        XCTAssertEqual(FlashGuard.safeFrequency(.infinity), 0.0, accuracy: 1e-9)
    }

    func testIsFlash_darkToBright_isFlash() {
        XCTAssertTrue(FlashGuard.isFlash(from: 0.0, to: 0.5))   // big swing from dark
    }

    func testIsFlash_smallDelta_isNotFlash() {
        XCTAssertFalse(FlashGuard.isFlash(from: 0.5, to: 0.55)) // 0.05 < 0.10
    }

    func testIsFlash_bothBright_isNotFlash() {
        XCTAssertFalse(FlashGuard.isFlash(from: 0.85, to: 0.98)) // darker state ≥ 0.80
    }

    func testLimitedLuminance_capsStep() {
        XCTAssertEqual(FlashGuard.limitedLuminance(from: 0.0, to: 1.0), 0.10, accuracy: 1e-9)  // up-capped
        XCTAssertEqual(FlashGuard.limitedLuminance(from: 1.0, to: 0.0), 0.90, accuracy: 1e-9)  // down-capped
        XCTAssertEqual(FlashGuard.limitedLuminance(from: 0.50, to: 0.55), 0.55, accuracy: 1e-9) // within cap
    }
}
