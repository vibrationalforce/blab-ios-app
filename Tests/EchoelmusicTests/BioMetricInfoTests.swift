// BioMetricInfoTests.swift
// Echoel — the tap-to-explain bio copy. Asserts every metric is fully explained
// and that the safety/scope disclaimer is present and correct.

import XCTest
@testable import Echoelmusic

final class BioMetricInfoTests: XCTestCase {

    func testEveryMetricIsFullyExplained() {
        for m in BioMetric.allCases {
            XCTAssertFalse(m.title.isEmpty, "\(m) title")
            XCTAssertFalse(m.unit.isEmpty, "\(m) unit")
            XCTAssertFalse(m.summary.isEmpty, "\(m) summary")
            XCTAssertGreaterThan(m.detail.count, 40, "\(m) detail should be a real explanation")
        }
    }

    func testRosterCoversTheDisplayedMetrics() {
        XCTAssertEqual(BioMetric.allCases.count, 7)
        XCTAssertEqual(Set(BioMetric.allCases),
                       [.heartRate, .hrv, .rmssd, .sdnn, .pnn50, .coherence, .breath])
    }

    func testDisclaimerIsPresentAndSafe() {
        let d = BioMetric.disclaimer.lowercased()
        XCTAssertTrue(d.contains("not"), "must state it is NOT a medical device")
        XCTAssertTrue(d.contains("diagnos"), "must state not for diagnosis")
        XCTAssertTrue(d.contains("self-observation"))
    }

    func testNoEsotericClaims() {
        // Brand rule: no esoteric terminology in user-facing copy.
        let banned = ["healing", "chakra", "solfeggio", "quantum", "aura"]
        for m in BioMetric.allCases {
            let text = (m.summary + " " + m.detail).lowercased()
            for term in banned {
                XCTAssertFalse(text.contains(term), "\(m) copy must avoid '\(term)'")
            }
        }
    }
}
