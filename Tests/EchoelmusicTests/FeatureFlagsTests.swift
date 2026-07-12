// FeatureFlagsTests.swift
// Echoel — S0 of the spatial expansion: the flag switchboard must be OFF by
// default (Release bit-identical), overridable per injected store, and its
// keys stable + distinct (they are the staged-rollout contract).

import XCTest
@testable import Echoelmusic

final class FeatureFlagsTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "FeatureFlagsTests-\(UUID().uuidString)")!
    }

    func testEveryFlagDefaultsOff() {
        let d = freshDefaults()
        for key in FeatureFlags.Key.allCases {
            XCTAssertFalse(FeatureFlags.isOn(key, defaults: d),
                           "\(key.rawValue) must be OFF when absent (Release default)")
        }
    }

    func testSetAndReadRoundTrip() {
        let d = freshDefaults()
        FeatureFlags.set(.spatialEngine, true, defaults: d)
        XCTAssertTrue(FeatureFlags.isOn(.spatialEngine, defaults: d))
        // Only the touched flag flips — neighbours stay OFF.
        XCTAssertFalse(FeatureFlags.isOn(.bioSpace, defaults: d))
        FeatureFlags.set(.spatialEngine, false, defaults: d)
        XCTAssertFalse(FeatureFlags.isOn(.spatialEngine, defaults: d))
    }

    func testKeysAreDistinctAndNamespaced() {
        let raws = FeatureFlags.Key.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count, "flag keys must be unique")
        for r in raws {
            XCTAssertTrue(r.hasPrefix("feature."), "\(r) must live in the feature.* namespace")
        }
    }
}
