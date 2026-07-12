// ParameterToolCoreTests.swift
// EchoelAI N4 — tool logic called directly, model mocked away entirely:
// list/search passthrough, set-parameter validation + clamp + control-plane
// apply, unknown-keyPath error the planner can correct from. Plus: the
// vocabulary data file must exist in the bundle and parse.

import XCTest
import Foundation
@testable import Echoelmusic

@MainActor
final class ParameterToolCoreTests: XCTestCase {

    private func makeRegistry() -> EchoelParameterRegistry {
        let r = EchoelParameterRegistry()
        r.register(DDSPParameterCatalog.descriptors)
        return r
    }

    func testList_emptyQuery_isFullInventory() {
        let r = makeRegistry()
        XCTAssertEqual(ParameterToolCore.list(registry: r, query: "").count,
                       DDSPParameterCatalog.descriptors.count)
        XCTAssertEqual(ParameterToolCore.list(registry: r, query: "cutoff").map(\.keyPath),
                       ["ddsp.filter.cutoff"])
    }

    func testSet_appliesClampedRealValue_onControlPlane() throws {
        let r = makeRegistry()
        var applied: (String, Float)?
        let result = try ParameterToolCore.set(keyPath: "ddsp.env.sustain",
                                               normalizedValue: 0.25,
                                               registry: r) { d, v in
            applied = (d.keyPath, v)
        }
        XCTAssertEqual(applied?.0, "ddsp.env.sustain")
        XCTAssertEqual(applied?.1 ?? -1, 0.25, accuracy: 1e-6)   // 0…1 range
        XCTAssertEqual(result.appliedValue, 0.25, accuracy: 1e-6)
    }

    func testSet_normalizedOutOfRange_clampsToParameterBounds() throws {
        let r = makeRegistry()
        var value: Float = -1
        _ = try ParameterToolCore.set(keyPath: "ddsp.filter.cutoff",
                                      normalizedValue: 7,
                                      registry: r) { _, v in value = v }
        XCTAssertEqual(value, 18_000)   // planner can never leave the range
        _ = try ParameterToolCore.set(keyPath: "ddsp.filter.cutoff",
                                      normalizedValue: -2,
                                      registry: r) { _, v in value = v }
        XCTAssertEqual(value, 20)
    }

    func testSet_unknownKeyPath_throwsCorrectableToolError() {
        let r = makeRegistry()
        XCTAssertThrowsError(try ParameterToolCore.set(keyPath: "ddsp.nope.x",
                                                       normalizedValue: 0.5,
                                                       registry: r) { _, _ in
            XCTFail("apply must not run for unknown keyPath")
        }) { error in
            guard case EchoelAIError.toolFailed(let message) = error else {
                return XCTFail("expected toolFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("ddsp.nope.x"),
                          "error must name the offending keyPath")
        }
    }

    func testVocabularyDataFile_existsInRepoAndParses() throws {
        // The seed vocabulary is DATA (no consumer yet). Bundle.module lookup
        // is exercised where SPM processes Resources/; the repo-path read
        // keeps the test meaningful on every CI (Linux included).
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/EchoelmusicTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/Echoelmusic/Resources/EchoelAI/echoelai-vocabulary.json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["version"] as? Int, 1)
        let terms = json?["terms"] as? [[String: Any]]
        XCTAssertEqual(terms?.count, 4)
        XCTAssertEqual(terms?.first?["term"] as? String, "treibender")
    }
}
