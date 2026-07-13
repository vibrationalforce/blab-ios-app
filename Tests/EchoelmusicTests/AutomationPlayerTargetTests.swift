// AutomationPlayerTargetTests.swift
// Automation-in-track cycle 2 — AutomationPlayer speaks registry keyPaths:
// each legacy enum target carries a stable keyPath alias (both identities
// readable, saved data NEVER rewritten), unknown keyPath lanes survive
// load/save instead of being dropped, and extra keyPath lanes dispatch
// through ParameterApplyRouter while the three legacy targets keep their
// exact curves (filter stays log — no linear regression).

import XCTest
import Foundation
@testable import Echoelmusic

@MainActor
final class AutomationPlayerTargetTests: XCTestCase {

    private let extraKeyPath = "ddsp.amp.level"

    private func cleanPlayer() -> AutomationPlayer {
        let auto = AutomationPlayer()
        for t in AutomationTarget.allCases { auto.clear(target: t) }
        auto.removeLane(parameter: extraKeyPath)
        return auto
    }

    // MARK: - keyPath identity (alias, both directions)

    func testEveryTargetHasStableKeyPath() {
        XCTAssertEqual(AutomationTarget.masterLevel.keyPath, "master.amp.level")
        XCTAssertEqual(AutomationTarget.tempo.keyPath, "transport.tempo.bpm")
        XCTAssertEqual(AutomationTarget.filterCutoff.keyPath, "ddsp.filter.cutoffScale")
        for t in AutomationTarget.allCases {
            XCTAssertEqual(t.keyPath.split(separator: ".").count, 3,
                           "\(t.keyPath) must be modul.sektion.parameter")
        }
    }

    func testForParameter_acceptsLegacyRawValueAndKeyPath() {
        for t in AutomationTarget.allCases {
            XCTAssertEqual(AutomationTarget.forParameter(t.rawValue), t)
            XCTAssertEqual(AutomationTarget.forParameter(t.keyPath), t)
        }
        XCTAssertNil(AutomationTarget.forParameter("ddsp.osc.brightness"))
        XCTAssertNil(AutomationTarget.forParameter(""))
    }

    // MARK: - No silent rename, no data loss

    func testEnumLanesKeepLegacyParameterNames() {
        let auto = cleanPlayer()
        auto.addPoint(target: .masterLevel, beat: 0, value: 0.4)
        // The stored identity stays the legacy rawValue — saved JSON is not rewritten.
        XCTAssertEqual(auto.lane(for: .masterLevel).parameter, "masterLevel")
    }

    func testAdoptLane_keyPathNamedEnumLane_isAliasMatchedNotDuplicated() {
        let auto = cleanPlayer()
        var lane = AutomationLane(parameter: AutomationTarget.masterLevel.keyPath)
        lane.addPoint(tick: 0, value: 0.7)
        auto.adoptLane(lane)
        // Alias-matched into the enum slot: readable under the enum, count unchanged.
        XCTAssertEqual(auto.lane(for: .masterLevel).points.first?.value ?? 0, 0.7,
                       accuracy: 1e-9)
        let enumMatches = auto.lanes.filter {
            AutomationTarget.forParameter($0.parameter) == .masterLevel
        }
        XCTAssertEqual(enumMatches.count, 1)
        auto.clear(target: .masterLevel)
    }

    func testExtraKeyPathLane_survivesAdoptAndReload() {
        let auto = cleanPlayer()
        var lane = AutomationLane(parameter: extraKeyPath)
        lane.addPoint(tick: 0, value: 0.5)
        auto.adoptLane(lane)
        XCTAssertTrue(auto.lanes.contains { $0.parameter == extraKeyPath })
        // A fresh instance loads the persisted doc — the extra lane is NOT dropped.
        let reloaded = AutomationPlayer()
        XCTAssertTrue(reloaded.lanes.contains { $0.parameter == extraKeyPath },
                      "unknown keyPath lanes must survive load (no data loss)")
        reloaded.removeLane(parameter: extraKeyPath)
    }

    // MARK: - Legacy curves preserved (the migration must not change sound)

    func testAppliedValueForKeyPath_matchesEnumCurveIncludingLog() {
        let auto = cleanPlayer()
        auto.addPoint(target: .filterCutoff, beat: 0, value: 0.5)
        // keyPath route returns the SAME log-mapped multiplier as the enum route.
        XCTAssertEqual(auto.appliedValue(forKeyPath: "ddsp.filter.cutoffScale", atStep: 0) ?? 0,
                       auto.appliedValue(for: .filterCutoff, atStep: 0) ?? -1, accuracy: 1e-9)
        XCTAssertEqual(auto.appliedValue(forKeyPath: "filterCutoff", atStep: 0) ?? 0, 1,
                       accuracy: 1e-6, "0.5 on the log curve is ×1 — must stay log")
        XCTAssertNil(auto.appliedValue(forKeyPath: "ddsp.osc.brightness", atStep: 0),
                     "non-enum keyPaths have no enum curve — nil, not a guess")
        auto.clear(target: .filterCutoff)
    }

    // MARK: - Extra lanes dispatch through the router

    func testApplyStep_dispatchesExtraLaneThroughRouter() {
        let reg = EchoelParameterRegistry()
        reg.register(DDSPParameterCatalog.descriptors)
        let router = ParameterApplyRouter(registry: reg)
        var got: Float?
        router.bind(extraKeyPath) { got = $0 }

        let auto = cleanPlayer()
        auto.wire(router: router)
        var lane = AutomationLane(parameter: extraKeyPath)
        lane.addPoint(tick: 0, value: 0.5)
        auto.adoptLane(lane)
        auto.enabled = true
        auto.applyStep(0)
        // ddsp.amp.level is 0…1 linear → normalized 0.5 = real 0.5.
        XCTAssertEqual(got ?? -1, 0.5, accuracy: 1e-6)
        auto.removeLane(parameter: extraKeyPath)
        auto.enabled = false
    }

    func testApplyStep_disabled_skipsExtraLanes() {
        let reg = EchoelParameterRegistry()
        reg.register(DDSPParameterCatalog.descriptors)
        let router = ParameterApplyRouter(registry: reg)
        var called = false
        router.bind(extraKeyPath) { _ in called = true }

        let auto = cleanPlayer()
        auto.wire(router: router)
        var lane = AutomationLane(parameter: extraKeyPath)
        lane.addPoint(tick: 0, value: 0.9)
        auto.adoptLane(lane)
        auto.enabled = false
        auto.applyStep(0)
        XCTAssertFalse(called, "automation off must silence extra lanes too")
        auto.removeLane(parameter: extraKeyPath)
    }

    func testRemoveLane_removesOnlyExtras_neverEnumSlots() {
        let auto = cleanPlayer()
        let before = auto.lanes.count
        auto.removeLane(parameter: "masterLevel")          // enum slot: protected
        XCTAssertEqual(auto.lanes.count, before, "enum lanes are structural — not removable")
        var lane = AutomationLane(parameter: extraKeyPath)
        lane.addPoint(tick: 0, value: 0.1)
        auto.adoptLane(lane)
        auto.removeLane(parameter: extraKeyPath)
        XCTAssertFalse(auto.lanes.contains { $0.parameter == extraKeyPath })
    }
}
