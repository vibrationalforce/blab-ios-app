//
//  BioModulationMapTests.swift
//  Echoelmusic — REIHENFOLGE item 2 LIVE readout spine
//
//  Verifies the live bio-driver amount extractor: normalization, clamping,
//  NaN-safety, and the id↔driver contract with the canonical BioSoundMapping list
//  (so no routing row can render a live bar that is silently stuck at 0).
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

    // MARK: - id ↔ driver contract (single source of truth = BioSoundMapping)

    func testEveryMappingID_resolvesToADriver() {
        // Every static routing row must have a live driver, or its bar would be
        // stuck at 0 forever (silent dead readout).
        for m in BioSoundMapping.all {
            XCTAssertNotNil(BioModulationMap.Driver(rawValue: m.id),
                            "BioSoundMapping id '\(m.id)' has no matching driver")
        }
    }

    func testUnknownMappingID_yieldsZero_notCrash() {
        XCTAssertEqual(BioModulationMap.amount(forMappingID: "nope", in: frame()), 0)
    }

    func testMappingID_matchesDirectDriverAmount() {
        let f = frame(coherence: 0.61)
        XCTAssertEqual(
            BioModulationMap.amount(forMappingID: "coherence", in: f),
            BioModulationMap.amount(.coherence, in: f), accuracy: 1e-6)
    }

    // MARK: - Driver amounts

    func testCoherence_passesThroughFrameValue() {
        XCTAssertEqual(BioModulationMap.amount(.coherence, in: frame(coherence: 0.73)), 0.73, accuracy: 1e-5)
    }

    func testHRV_passesThroughNormalized() {
        XCTAssertEqual(BioModulationMap.amount(.hrv, in: frame(hrv: 0.31)), 0.31, accuracy: 1e-5)
    }

    func testBreath_passesThroughPhase() {
        XCTAssertEqual(BioModulationMap.amount(.breath, in: frame(breath: 0.9)), 0.9, accuracy: 1e-5)
    }

    func testHeartRate_normalizesOnCanonicalSpan() {
        // (120 - 40) / (200 - 40) = 0.5
        XCTAssertEqual(BioModulationMap.amount(.heartRate, in: frame(hr: 120)), 0.5, accuracy: 1e-5)
    }

    func testHeartRate_clampsBelowFloor() {
        XCTAssertEqual(BioModulationMap.amount(.heartRate, in: frame(hr: 30)), 0, accuracy: 1e-6)
    }

    func testHeartRate_clampsAboveCeiling() {
        XCTAssertEqual(BioModulationMap.amount(.heartRate, in: frame(hr: 260)), 1, accuracy: 1e-6)
    }

    // MARK: - Robustness

    func testNonFiniteDriver_yieldsZero_notNaN() {
        let a = BioModulationMap.amount(.coherence, in: frame(coherence: .nan))
        XCTAssertEqual(a, 0)
        XCTAssertFalse(a.isNaN)
    }

    func testAllMappingAmounts_inUnitRange() {
        let f = frame(hr: 200, hrv: 1.0, breath: 1.0, coherence: 1.0)
        for m in BioSoundMapping.all {
            let a = BioModulationMap.amount(forMappingID: m.id, in: f)
            XCTAssertGreaterThanOrEqual(a, 0)
            XCTAssertLessThanOrEqual(a, 1)
        }
    }
}
