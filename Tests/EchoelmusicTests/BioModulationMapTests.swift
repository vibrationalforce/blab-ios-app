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
        hr: Float = 72, hrv: Float = 0.5, breath: Float = 0.5, coherence: Float = 0.5,
        breathRate: Float = 12
    ) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: 0, heartRateBPM: hr, hrvNormalized: hrv, breathRate: breathRate,
            breathPhase: breath, coherence: coherence, motionEnergy: 0, source: .ble
        )
    }

    // MARK: - measured vs. zero (the display gate)

    func testMeasuredAmount_isNilForUnmeasuredFields_notZero() {
        // The panel this feeds explains the bio→sound mapping, so "0.00" there is a
        // claim about the body. `amount` cannot express the difference — it returns a
        // clamped number where 0 is both "bottom of scale" and "never measured".
        let unmeasured = frame(hr: 0, hrv: 0, coherence: 0)
        XCTAssertNil(BioModulationMap.measuredAmount(forMappingID: "coherence", in: unmeasured))
        XCTAssertNil(BioModulationMap.measuredAmount(forMappingID: "hrv", in: unmeasured))
        XCTAssertNil(BioModulationMap.measuredAmount(forMappingID: "heartRate", in: unmeasured))
        // …while `amount` still answers 0 for the same frame, unchanged.
        XCTAssertEqual(BioModulationMap.amount(forMappingID: "coherence", in: unmeasured), 0)
    }

    func testMeasuredAmount_passesRealReadingsThroughUnchanged() {
        let f = frame(hr: 120, hrv: 0.31, coherence: 0.73)
        XCTAssertEqual(BioModulationMap.measuredAmount(forMappingID: "coherence", in: f) ?? -1,
                       0.73, accuracy: 1e-5)
        XCTAssertEqual(BioModulationMap.measuredAmount(forMappingID: "hrv", in: f) ?? -1,
                       0.31, accuracy: 1e-5)
    }

    func testMeasuredAmount_breathIsGatedOnTheRATE_notOnThePhase() {
        // The breath row is the trap in this whole rule. Its VALUE is `breathPhase`,
        // where 0 is a genuine position (exhale start) — so the phase cannot say whether
        // anything was measured. Only `breathRate` can: the strap and the face-cam
        // publish 0, and the HealthKit path leaves the phase at a 0.5 PLACEHOLDER that
        // would otherwise render as the most confident number on a panel of honest "—"s.

        // Phase 0 with a real rate: a measured reading of 0, correctly shown.
        XCTAssertEqual(BioModulationMap.measuredAmount(forMappingID: "breath",
                                                       in: frame(breath: 0, breathRate: 12)) ?? -1,
                       0, accuracy: 1e-6)
        // No rate: nil, whatever the phase says.
        XCTAssertNil(BioModulationMap.measuredAmount(forMappingID: "breath",
                                                     in: frame(breath: 0, breathRate: 0)))
        // The exact HealthKit shape — a 0.5 phase placeholder and no rate.
        XCTAssertNil(BioModulationMap.measuredAmount(forMappingID: "breath",
                                                     in: frame(breath: 0.5, breathRate: 0)),
                     "the HealthKit 0.5 phase placeholder must never render as a reading")
        // Implausible rates are absences too — you cannot breathe once a minute.
        XCTAssertNil(BioModulationMap.measuredAmount(forMappingID: "breath",
                                                     in: frame(breathRate: 1)))
        XCTAssertNil(BioModulationMap.measuredAmount(forMappingID: "breath",
                                                     in: frame(breathRate: 200)))
    }

    func testMeasuredAmount_unknownID_isNil() {
        XCTAssertNil(BioModulationMap.measuredAmount(forMappingID: "nope", in: frame()))
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
