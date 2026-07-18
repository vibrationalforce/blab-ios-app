// BioEgressPolicyTests.swift
// Echoelmusic — App Store 5.1.3: HealthKit-store data never leaves the device.
// The OSC/ADM senders forward only Echoel-measured sources; this pins the rule.

import XCTest
@testable import Echoelmusic

final class BioEgressPolicyTests: XCTestCase {

    func testOwnMeasurements_mayStreamOffDevice() {
        XCTAssertTrue(BioEgressPolicy.allowsEgress(.cameraPPG), "camera rPPG is Echoel's own measurement")
        XCTAssertTrue(BioEgressPolicy.allowsEgress(.ble), "BLE strap is Echoel's own measurement")
        XCTAssertTrue(BioEgressPolicy.allowsEgress(.fallback), "demo generator carries no real health data")
        // faceCam is measured on-device like rPPG; only abstracted [0..1] expression
        // channels egress, never the image.
        XCTAssertTrue(BioEgressPolicy.allowsEgress(.faceCam), "face expression is Echoel's own on-device measurement")
    }

    func testHealthKitStoreSources_neverStreamOffDevice() {
        // 5.1.3: anything read out of the HealthKit store (or bridges that route
        // through it) stays on the device — a user-typed UDP host could be anywhere.
        XCTAssertFalse(BioEgressPolicy.allowsEgress(.healthKit))
        XCTAssertFalse(BioEgressPolicy.allowsEgress(.watch))
        XCTAssertFalse(BioEgressPolicy.allowsEgress(.oura))
    }

    func testEverySourceHasAnExplicitRuling() {
        // A new BioSource case must consciously pick a side (the switch in the
        // policy is exhaustive; this documents the full current census).
        let all: [BioSource] = [.fallback, .healthKit, .oura, .ble, .watch, .cameraPPG, .faceCam]
        for source in all {
            _ = BioEgressPolicy.allowsEgress(source)   // must not trap; compile-time exhaustive
        }
        XCTAssertEqual(all.count, 7, "update this census when BioSource grows")
    }
}
