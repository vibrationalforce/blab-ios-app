//
//  HealthWritePolicyTests.swift
//  Echoel — rules for opt-in write-back of our own measurements to Apple Health.
//  Pure logic — runs on every CI host (no HealthKit needed).
//

import XCTest
@testable import Echoelmusic

final class HealthWritePolicyTests: XCTestCase {

    private func frame(_ source: BioSource, hr: Float = 72, breath: Float = 14) -> BioSampleFrame {
        BioSampleFrame(timestamp: 0, heartRateBPM: hr, hrvNormalized: 0.5,
                       breathRate: breath, breathPhase: 0.5, coherence: 0,
                       motionEnergy: 0, source: source)
    }

    func test_disabled_neverWrites() {
        XCTAssertFalse(HealthWritePolicy.shouldWrite(frame: frame(.cameraPPG), enabled: false,
                                                     authorized: true, lastWriteAt: 0, now: 1000))
    }

    func test_unauthorized_neverWrites() {
        XCTAssertFalse(HealthWritePolicy.shouldWrite(frame: frame(.cameraPPG), enabled: true,
                                                     authorized: false, lastWriteAt: 0, now: 1000))
    }

    func test_onlyWritesSelfMeasuredSources_notCircular() {
        // camera rPPG and BLE are ours → write; HealthKit/Watch/Oura/fallback are not.
        for s in [BioSource.cameraPPG, .ble] {
            XCTAssertTrue(HealthWritePolicy.isWritableSource(s), "\(s) should be writable")
        }
        for s in [BioSource.healthKit, .watch, .oura, .fallback] {
            XCTAssertFalse(HealthWritePolicy.isWritableSource(s), "\(s) must NOT be written (circular/foreign)")
        }
        XCTAssertFalse(HealthWritePolicy.shouldWrite(frame: frame(.healthKit), enabled: true,
                                                     authorized: true, lastWriteAt: 0, now: 1000),
                       "must never echo HealthKit data back")
    }

    func test_throttle_minGapEnforced() {
        let now = 1000.0
        XCTAssertFalse(HealthWritePolicy.shouldWrite(frame: frame(.ble), enabled: true, authorized: true,
                                                     lastWriteAt: now - 5, now: now), "5 s < gap")
        XCTAssertTrue(HealthWritePolicy.shouldWrite(frame: frame(.ble), enabled: true, authorized: true,
                                                    lastWriteAt: now - HealthWritePolicy.minWriteGap, now: now))
    }

    func test_implausibleHeartRate_dropped() {
        XCTAssertFalse(HealthWritePolicy.shouldWrite(frame: frame(.cameraPPG, hr: 5), enabled: true,
                                                     authorized: true, lastWriteAt: 0, now: 1000))
        XCTAssertFalse(HealthWritePolicy.shouldWrite(frame: frame(.cameraPPG, hr: 400), enabled: true,
                                                     authorized: true, lastWriteAt: 0, now: 1000))
        XCTAssertFalse(HealthWritePolicy.shouldWrite(frame: frame(.cameraPPG, hr: .nan), enabled: true,
                                                     authorized: true, lastWriteAt: 0, now: 1000))
    }

    func test_values_writesHR_andRespiratoryWhenInRange() {
        let v1 = HealthWritePolicy.values(for: frame(.ble, hr: 72, breath: 14))
        XCTAssertEqual(v1.heartRate, 72, accuracy: 0.001)
        XCTAssertEqual(v1.respiratoryRate ?? -1, 14, accuracy: 0.001)
        // Out-of-range / non-finite breath → no respiratory sample, HR still present.
        let v2 = HealthWritePolicy.values(for: frame(.ble, hr: 72, breath: 99))
        XCTAssertNil(v2.respiratoryRate)
        XCTAssertEqual(v2.heartRate, 72, accuracy: 0.001)
    }
}
