// HRVNormalizationTests.swift
// Pins the ONE shared HRV normalization contract that the camera, BLE strap, and
// HealthKit sources now all route through — so identical physiology reads identically
// into the [0,1] hrvNormalized knob (the 3-team consistency audit, 2026-07-23).

import XCTest
@testable import Echoelmusic

final class HRVNormalizationTests: XCTestCase {

    func testCeilingIsHundredMs() {
        XCTAssertEqual(HRVNormalization.ceilingMs, 100.0, accuracy: 1e-9)
    }

    func testExcellentHRVMapsToOne() {
        XCTAssertEqual(HRVNormalization.normalize(100), 1.0, accuracy: 1e-9)
    }

    func testMidRangeIsLinear() {
        // 60 ms → 0.60 — the value that USED to read 0.30 from the camera (÷200) and
        // 0.60 from the strap (÷100). Now both agree.
        XCTAssertEqual(HRVNormalization.normalize(60), 0.60, accuracy: 1e-9)
        XCTAssertEqual(HRVNormalization.normalize(20), 0.20, accuracy: 1e-9)
    }

    func testAboveCeilingClampsToOne() {
        XCTAssertEqual(HRVNormalization.normalize(150), 1.0, accuracy: 1e-9)
        XCTAssertEqual(HRVNormalization.normalize(10_000), 1.0, accuracy: 1e-9)
    }

    func testZeroAndNegativeAndNonFiniteAreZero() {
        XCTAssertEqual(HRVNormalization.normalize(0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(HRVNormalization.normalize(-5), 0.0, accuracy: 1e-9)
        XCTAssertEqual(HRVNormalization.normalize(.nan), 0.0, accuracy: 1e-9)
        XCTAssertEqual(HRVNormalization.normalize(.infinity), 0.0, accuracy: 1e-9)
    }

    func testOutputAlwaysInUnitRange() {
        for ms in stride(from: -50.0, through: 500.0, by: 7.0) {
            let v = HRVNormalization.normalize(ms)
            XCTAssertGreaterThanOrEqual(v, 0.0)
            XCTAssertLessThanOrEqual(v, 1.0)
        }
    }
}
