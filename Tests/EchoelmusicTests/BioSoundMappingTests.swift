// BioSoundMappingTests.swift
// Pins the fixed body→sound routing map (REIHENFOLGE item 2: "which parameters does
// my biofeedback move?"). This is a STABLE design fact rendered in the reachable bio
// guide — a pure value, so it needs no live 10 Hz observation and is CI-verifiable.
// The routing (which source drives which target) mirrors EchoelDDSP.applyBioReactive.

import XCTest
@testable import Echoelmusic

final class BioSoundMappingTests: XCTestCase {

    func testMapCoversTheFourStripMetrics_inStripOrder() {
        // Same four sources the bio strip shows, same display order (HR·HRV·Coh·Breath),
        // so the guide reads top-to-bottom consistently with the strip.
        XCTAssertEqual(BioSoundMapping.all.map(\.id),
                       ["heartRate", "hrv", "coherence", "breath"])
    }

    func testEveryEntryIsFullyPopulated() {
        for m in BioSoundMapping.all {
            XCTAssertFalse(m.source.isEmpty, "\(m.id) needs a source label")
            XCTAssertFalse(m.target.isEmpty, "\(m.id) needs a target label")
            XCTAssertFalse(m.direction.isEmpty, "\(m.id) needs a direction phrase")
        }
    }

    func testIdsAreUnique() {
        XCTAssertEqual(Set(BioSoundMapping.all.map(\.id)).count, BioSoundMapping.all.count)
    }

    // The routing targets must match the real applyBioReactive design (audited):
    // coherence→brightness/filter/harmonics, HR→vibrato, HRV→reverb, breath→filter motion.
    func testRoutingTargetsMatchTheEngineDesign() {
        func target(_ id: String) -> String {
            BioSoundMapping.all.first { $0.id == id }?.target.lowercased() ?? ""
        }
        XCTAssertTrue(target("coherence").contains("filter") || target("coherence").contains("bright"))
        XCTAssertTrue(target("heartRate").contains("vibrato"))
        XCTAssertTrue(target("hrv").contains("reverb") || target("hrv").contains("space"))
        XCTAssertTrue(target("breath").contains("filter") || target("breath").contains("swell"))
    }

    // No wellness/therapy/esoteric claim anywhere in the copy (brand red line).
    func testCopyMakesNoHealthClaim() {
        let banned = ["heal", "cure", "therapy", "medical", "diagnos", "chakra", "solfeggio"]
        for m in BioSoundMapping.all {
            let blob = "\(m.source) \(m.target) \(m.direction)".lowercased()
            for word in banned {
                XCTAssertFalse(blob.contains(word), "\(m.id) copy must not contain '\(word)'")
            }
        }
    }
}
