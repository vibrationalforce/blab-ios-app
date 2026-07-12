// EchoelParameterRegistryTests.swift
// EchoelAI N2 — registration (replace-by-keyPath, stable order), substring +
// token search, normalization round-trip, and the real DDSP inventory.

import XCTest
import Foundation
@testable import Echoelmusic

@MainActor
final class EchoelParameterRegistryTests: XCTestCase {

    private func makeRegistry() -> EchoelParameterRegistry {
        let r = EchoelParameterRegistry()
        r.register(DDSPParameterCatalog.descriptors)
        return r
    }

    // MARK: - Registration

    func testRegister_allDescriptorsQueryable() {
        let r = makeRegistry()
        XCTAssertEqual(r.all().count, DDSPParameterCatalog.descriptors.count)
        XCTAssertNotNil(r.descriptor(for: "ddsp.filter.cutoff"))
    }

    func testRegister_replacesByKeyPath_keepsPositionAndCount() {
        let r = makeRegistry()
        let countBefore = r.all().count
        let posBefore = r.all().firstIndex { $0.keyPath == "ddsp.filter.cutoff" }
        r.register([ParameterDescriptor(keyPath: "ddsp.filter.cutoff",
                                        displayName: "Cutoff v2",
                                        min: 40, max: 12_000, defaultValue: 500,
                                        unit: "Hz")])
        XCTAssertEqual(r.all().count, countBefore)          // replaced, not appended
        XCTAssertEqual(r.descriptor(for: "ddsp.filter.cutoff")?.displayName, "Cutoff v2")
        XCTAssertEqual(r.all().firstIndex { $0.keyPath == "ddsp.filter.cutoff" }, posBefore)
    }

    // MARK: - Search

    func testSearch_emptyQuery_returnsEverything() {
        let r = makeRegistry()
        XCTAssertEqual(r.search(query: "").count, r.all().count)
        XCTAssertEqual(r.search(query: "   ").count, r.all().count)
    }

    func testSearch_substring_caseInsensitive() {
        let r = makeRegistry()
        let hits = r.search(query: "CUTOFF")
        XCTAssertEqual(hits.map(\.keyPath), ["ddsp.filter.cutoff"])
    }

    func testSearch_multiToken_allTokensMustMatch() {
        let r = makeRegistry()
        // "env" alone matches four envelope stages; adding "attack" narrows to one.
        XCTAssertEqual(r.search(query: "env").count, 4)
        XCTAssertEqual(r.search(query: "env attack").map(\.keyPath), ["ddsp.env.attack"])
        // A token that matches nothing empties the result.
        XCTAssertTrue(r.search(query: "env nonexistent").isEmpty)
    }

    func testSearch_matchesDisplayNameAndUnit() {
        let r = makeRegistry()
        XCTAssertTrue(r.search(query: "reverb").count >= 2)      // display names
        XCTAssertFalse(r.search(query: "hz").isEmpty)            // unit
    }

    // MARK: - Normalization (the tool write path's safety rail)

    func testNormalization_roundTripAndClamp() {
        let d = ParameterDescriptor(keyPath: "t.x", displayName: "X",
                                    min: 100, max: 200, defaultValue: 150)
        XCTAssertEqual(d.denormalized(0), 100)
        XCTAssertEqual(d.denormalized(1), 200)
        XCTAssertEqual(d.denormalized(0.5), 150)
        // Out-of-range tool values clamp — a planner can't leave the range.
        XCTAssertEqual(d.denormalized(-3), 100)
        XCTAssertEqual(d.denormalized(9), 200)
        XCTAssertEqual(d.normalized(150), 0.5, accuracy: 1e-6)
        XCTAssertEqual(d.normalized(d.denormalized(0.33)), 0.33, accuracy: 1e-5)
    }

    func testNormalization_degenerateRange_isSafe() {
        let d = ParameterDescriptor(keyPath: "t.y", displayName: "Y",
                                    min: 5, max: 5, defaultValue: 5)
        XCTAssertEqual(d.normalized(5), 0)    // no divide-by-zero
    }

    // MARK: - Inventory integrity (data about the REAL engine)

    func testDDSPCatalog_keyPathsUniqueAndWellFormed() {
        let keyPaths = DDSPParameterCatalog.descriptors.map(\.keyPath)
        XCTAssertEqual(Set(keyPaths).count, keyPaths.count, "keyPaths must be unique")
        for kp in keyPaths {
            XCTAssertTrue(kp.hasPrefix("ddsp."), "\(kp) must carry the module prefix")
            XCTAssertEqual(kp.split(separator: ".").count, 3,
                           "\(kp) must be modul.sektion.parameter")
        }
    }

    func testDDSPCatalog_rangesContainDefaults() {
        for d in DDSPParameterCatalog.descriptors {
            XCTAssertLessThan(d.min, d.max, d.keyPath)
            XCTAssertTrue((d.min...d.max).contains(d.defaultValue),
                          "\(d.keyPath) default outside range")
        }
    }

    func testDescriptor_codableRoundTrip() throws {
        let d = DDSPParameterCatalog.descriptors[0]
        let back = try JSONDecoder().decode(ParameterDescriptor.self,
                                            from: JSONEncoder().encode(d))
        XCTAssertEqual(back, d)
    }
}
