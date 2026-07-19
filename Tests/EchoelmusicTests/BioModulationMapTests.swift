//
//  BioModulationMapTests.swift
//  Echoelmusic — REIHENFOLGE item 2 readout spine
//
//  Verifies the pure bio→sound readout model: driver normalization, clamping,
//  NaN-safety, and that `amounts(for:)` mirrors `links` in order/count.
//

import XCTest
@testable import Echoelmusic

final class BioModulationMapTests: XCTestCase {

    private func frame(
        hr: Float = 72, hrv: Float = 0.5, breath: Float = 0.5, coherence: Float = 0.5
    ) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: 0, heartRateBPM: hr, hrvNormalized: hrv, breathRate: 12,
            breathPhase: breath, coherence: coherence, motionEnergy: 0, source: .ble
        )
    }

    // MARK: - Canonical map shape

    func testLinks_coverAllFourDrivers_inStableOrder() {
        let drivers = BioModulationMap.links.map(\.driver)
        XCTAssertEqual(drivers, [.coherence, .heartRate, .hrv, .breath])
    }

    func testAmounts_mirrorsLinks_orderAndCount() {
        let pairs = BioModulationMap.amounts(for: frame())
        XCTAssertEqual(pairs.count, BioModulationMap.links.count)
        XCTAssertEqual(pairs.map(\.link.id), BioModulationMap.links.map(\.id))
    }

    // MARK: - Driver amounts

    func testCoherence_passesThroughFrameValue() {
        let a = BioModulationMap.amount(.coherence, in: frame(coherence: 0.73))
        XCTAssertEqual(a, 0.73, accuracy: 1e-5)
    }

    func testHRV_passesThroughNormalized() {
        let a = BioModulationMap.amount(.hrv, in: frame(hrv: 0.31))
        XCTAssertEqual(a, 0.31, accuracy: 1e-5)
    }

    func testBreath_passesThroughPhase() {
        let a = BioModulationMap.amount(.breath, in: frame(breath: 0.9))
        XCTAssertEqual(a, 0.9, accuracy: 1e-5)
    }

    func testHeartRate_normalizesOnCanonicalSpan() {
        // (120 - 40) / (200 - 40) = 0.5
        let a = BioModulationMap.amount(.heartRate, in: frame(hr: 120))
        XCTAssertEqual(a, 0.5, accuracy: 1e-5)
    }

    func testHeartRate_clampsBelowFloor() {
        // 30 BPM is below the 40 floor → clamps to 0, never negative.
        let a = BioModulationMap.amount(.heartRate, in: frame(hr: 30))
        XCTAssertEqual(a, 0, accuracy: 1e-6)
    }

    func testHeartRate_clampsAboveCeiling() {
        let a = BioModulationMap.amount(.heartRate, in: frame(hr: 260))
        XCTAssertEqual(a, 1, accuracy: 1e-6)
    }

    // MARK: - Robustness

    func testNonFiniteDriver_yieldsZero_notNaN() {
        let a = BioModulationMap.amount(.coherence, in: frame(coherence: .nan))
        XCTAssertEqual(a, 0)
        XCTAssertFalse(a.isNaN)
    }

    func testAllAmounts_inUnitRange() {
        let f = frame(hr: 200, hrv: 1.0, breath: 1.0, coherence: 1.0)
        for (_, amount) in BioModulationMap.amounts(for: f) {
            XCTAssertGreaterThanOrEqual(amount, 0)
            XCTAssertLessThanOrEqual(amount, 1)
        }
    }
}
