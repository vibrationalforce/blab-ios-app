// AutomationPlayerParameterEditingTests.swift
// Automation-in-track cycle 3 — the player edits lanes by PARAMETER STRING
// (legacy rawValue, keyPath alias, or a free registry keyPath), so ONE UI code
// path serves every target. Enum lanes stay structural (string edits land in
// the same slot, saved names untouched); a first edit on an unknown keyPath
// creates its lane; string and enum routes are the same data.

import XCTest
import Foundation
@testable import Echoelmusic

@MainActor
final class AutomationPlayerParameterEditingTests: XCTestCase {

    private let extraKeyPath = "ddsp.osc.brightness"

    private func cleanPlayer() -> AutomationPlayer {
        let auto = AutomationPlayer()
        for t in AutomationTarget.allCases { auto.clear(target: t) }
        auto.removeLane(parameter: extraKeyPath)
        return auto
    }

    // MARK: - String route = enum route (same lane, both identities)

    func testAddPointByRawValue_landsInEnumSlot() {
        let auto = cleanPlayer()
        let p = auto.addPoint(parameter: "masterLevel", beat: 1, value: 0.25)
        XCTAssertNotNil(p)
        XCTAssertEqual(auto.points(for: .masterLevel).count, 1)
        XCTAssertEqual(auto.points(forParameter: "masterLevel").count, 1)
        auto.clear(target: .masterLevel)
    }

    func testAddPointByKeyPathAlias_landsInSameEnumSlot() {
        let auto = cleanPlayer()
        _ = auto.addPoint(parameter: AutomationTarget.tempo.keyPath, beat: 0, value: 0.5)
        XCTAssertEqual(auto.points(for: .tempo).count, 1)
        // The persisted identity stays the legacy rawValue (migration invariant).
        XCTAssertEqual(auto.lane(for: .tempo).parameter, "tempo")
        auto.clear(target: .tempo)
    }

    // MARK: - Free keyPath lanes: created on first edit, fully editable

    func testFirstEditOnUnknownKeyPath_createsItsLane() {
        let auto = cleanPlayer()
        XCTAssertNil(auto.lane(forParameter: extraKeyPath))
        let p = auto.addPoint(parameter: extraKeyPath, beat: 2, value: 0.8)
        XCTAssertNotNil(p)
        XCTAssertEqual(auto.points(forParameter: extraKeyPath).count, 1)
        auto.removeLane(parameter: extraKeyPath)
    }

    func testFullEditCycleOnKeyPathLane() {
        let auto = cleanPlayer()
        guard let p = auto.addPoint(parameter: extraKeyPath, beat: 0, value: 0.2) else {
            return XCTFail("addPoint must create the lane and the point")
        }
        auto.setValue(parameter: extraKeyPath, id: p.id, normalized: 0.9)
        XCTAssertEqual(auto.points(forParameter: extraKeyPath).first?.value ?? 0, 0.9,
                       accuracy: 1e-9)
        auto.movePoint(parameter: extraKeyPath, id: p.id, toBeat: 3, normalized: 0.4)
        let moved = auto.points(forParameter: extraKeyPath).first
        XCTAssertEqual(moved?.tick, AutomationPlayer.tick(forBeat: 3))
        XCTAssertEqual(moved?.value ?? 0, 0.4, accuracy: 1e-9)
        auto.setCurve(parameter: extraKeyPath, id: p.id, .hold)
        XCTAssertEqual(auto.points(forParameter: extraKeyPath).first?.curve, .hold)
        auto.setCurvature(parameter: extraKeyPath, id: p.id, 0.5)
        XCTAssertEqual(auto.points(forParameter: extraKeyPath).first?.curvature ?? 0, 0.5,
                       accuracy: 1e-9)
        auto.removePoint(parameter: extraKeyPath, id: p.id)
        XCTAssertTrue(auto.points(forParameter: extraKeyPath).isEmpty)
        auto.removeLane(parameter: extraKeyPath)
    }

    func testClearByParameter_keepsEnumLaneStructural() {
        let auto = cleanPlayer()
        _ = auto.addPoint(parameter: "masterLevel", beat: 0, value: 1)
        auto.clear(parameter: "masterLevel")
        XCTAssertTrue(auto.points(for: .masterLevel).isEmpty)
        XCTAssertTrue(auto.lanes.contains { $0.parameter == "masterLevel" },
                      "clearing an enum lane empties it, never removes it")
    }

    func testEmptyParameterString_isSafeNoop() {
        let auto = cleanPlayer()
        XCTAssertNil(auto.addPoint(parameter: "", beat: 0, value: 0.5))
        XCTAssertNil(auto.lane(forParameter: ""))
        XCTAssertTrue(auto.points(forParameter: "").isEmpty)
    }

    // MARK: - The UI's picker source (placebo law: bound-only extras)

    func testExtraAutomatableDescriptors_emptyWithoutRouter() {
        let auto = cleanPlayer()
        XCTAssertTrue(auto.extraAutomatableDescriptors.isEmpty,
                      "no router wired → no extra parameters offered (no dead lanes)")
    }

    func testExtraAutomatableDescriptors_boundOnly_andNeverEnumAliased() {
        let reg = EchoelParameterRegistry()
        reg.register(DDSPParameterCatalog.descriptors)
        // Register + bind an enum-aliased keyPath explicitly (it is NOT in the
        // DDSP catalog) so the enum filter itself is load-bearing here: without
        // it this descriptor WOULD appear in the extras.
        reg.register([ParameterDescriptor(keyPath: AutomationTarget.filterCutoff.keyPath,
                                          displayName: "Filter cutoff scale",
                                          min: 0.25, max: 4, defaultValue: 1)])
        let router = ParameterApplyRouter(registry: reg)
        router.bind(extraKeyPath) { _ in }
        // Bound AND registered — but enum-aliased, so it must never duplicate
        // into the extras: filter cutoff already lives on the legacy target.
        router.bind(AutomationTarget.filterCutoff.keyPath) { _ in }

        let auto = cleanPlayer()
        auto.wire(router: router)
        let extras = auto.extraAutomatableDescriptors.map(\.keyPath)
        XCTAssertEqual(extras, [extraKeyPath])
    }
}
