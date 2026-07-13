// AutomationClipLayerTests.swift
// Automation-in-track cycle 4 — automation IN the clip: a clip carries its own
// lanes (relative ticks, they travel with the clip), legacy clip JSON decodes
// with an empty list, and the player plays a fired clip's lanes as CLIP CONTENT
// — like its notes: independent of the global automation switch, winning over a
// global lane on the same parameter, never persisted into the global doc.

import XCTest
import Foundation
@testable import Echoelmusic

// MARK: - Clip model (pure)

final class ClipAutomationCodableTests: XCTestCase {

    func testLegacyClipJSON_decodesWithEmptyAutomation() throws {
        // A clip saved BEFORE the automation field existed (no key at all).
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Old","colorIndex":2,
         "drums":{"steps":[[true,false]],"accents":[[false,false]]}}
        """.data(using: .utf8) ?? Data()
        let clip = try JSONDecoder().decode(Clip.self, from: legacy)
        XCTAssertTrue(clip.automation.isEmpty, "legacy clips must load lossless with no lanes")
        XCTAssertEqual(clip.name, "Old")
    }

    func testClipAutomation_roundTripsThroughJSON() throws {
        var lane = AutomationLane(parameter: "masterLevel")
        lane.addPoint(tick: 0, value: 0.2)
        lane.addPoint(tick: 960, value: 0.9, curve: .hold)
        let clip = Clip(name: "Swell", automation: [lane])
        let data = try JSONEncoder().encode(clip)
        let back = try JSONDecoder().decode(Clip.self, from: data)
        XCTAssertEqual(back.automation, [lane], "clip lanes must survive save/load verbatim")
    }
}

// MARK: - Player clip layer (@MainActor)

@MainActor
final class AutomationPlayerClipLayerTests: XCTestCase {

    private func cleanPlayer() -> AutomationPlayer {
        let auto = AutomationPlayer()
        for t in AutomationTarget.allCases { auto.clear(target: t) }
        auto.setClipLanes([])
        return auto
    }

    private func lane(_ parameter: String, value: Double) -> AutomationLane {
        var l = AutomationLane(parameter: parameter)
        l.addPoint(tick: 0, value: value)
        return l
    }

    func testClipLanes_playWhileGlobalAutomationIsOff() {
        let auto = cleanPlayer()
        auto.enabled = false
        auto.setClipLanes([lane("masterLevel", value: 0.25)])
        // The clip layer's value at step 0 is readable through the same
        // real-value mapping the enum route uses.
        XCTAssertEqual(auto.clipAppliedValue(forParameter: "masterLevel", atStep: 0) ?? -1,
                       0.25, accuracy: 1e-9,
                       "clip automation is clip CONTENT — it plays like the clip's notes")
    }

    func testClipLane_winsOverGlobalLaneOnSameParameter() {
        let auto = cleanPlayer()
        auto.enabled = true
        auto.addPoint(target: .masterLevel, beat: 0, value: 1.0)
        auto.setClipLanes([lane("masterLevel", value: 0.1)])
        XCTAssertEqual(auto.clipAppliedValue(forParameter: "masterLevel", atStep: 0) ?? -1,
                       0.1, accuracy: 1e-9)
        // The global lane still reads its own value — precedence is applied at
        // dispatch (clip layer writes AFTER the global write each step).
        XCTAssertEqual(auto.appliedValue(for: .masterLevel, atStep: 0) ?? -1, 1.0,
                       accuracy: 1e-9)
        auto.clear(target: .masterLevel)
        auto.setClipLanes([])
        auto.enabled = false
    }

    func testClipLane_enumAliasKeyPath_mapsThroughEnumCurve() {
        let auto = cleanPlayer()
        // filterCutoff via keyPath alias at normalized 0.5 = ×1 on the LOG curve.
        auto.setClipLanes([lane(AutomationTarget.filterCutoff.keyPath, value: 0.5)])
        XCTAssertEqual(auto.clipAppliedValue(forParameter: "filterCutoff", atStep: 0) ?? 0,
                       1.0, accuracy: 1e-6, "clip lanes keep the enum curves — filter stays log")
        auto.setClipLanes([])
    }

    func testClipLanes_neverPersistIntoTheGlobalDoc() {
        let auto = cleanPlayer()
        auto.setClipLanes([lane("ddsp.osc.harmonicity", value: 0.7)])
        XCTAssertFalse(auto.lanes.contains { $0.parameter == "ddsp.osc.harmonicity" },
                       "the clip layer is transient — the clip itself persists it")
        // A fresh player (reloading the persisted doc) starts with no clip layer.
        let reloaded = AutomationPlayer()
        XCTAssertTrue(reloaded.clipLanes.isEmpty)
        auto.setClipLanes([])
    }

    func testSetClipLanes_emptyClearsTheLayer() {
        let auto = cleanPlayer()
        auto.setClipLanes([lane("masterLevel", value: 0.3)])
        auto.setClipLanes([])
        XCTAssertNil(auto.clipAppliedValue(forParameter: "masterLevel", atStep: 0),
                     "loading a clip without automation must silence the previous clip's lanes")
    }

    func testClipExtraKeyPathLane_dispatchesThroughRouter() {
        let reg = EchoelParameterRegistry()
        reg.register(DDSPParameterCatalog.descriptors)
        let router = ParameterApplyRouter(registry: reg)
        var got: Float?
        router.bind("ddsp.osc.harmonicity") { got = $0 }

        let auto = cleanPlayer()
        auto.wire(router: router)
        auto.enabled = false   // clip content plays regardless
        auto.setClipLanes([lane("ddsp.osc.harmonicity", value: 0.5)])
        auto.applyStep(0)
        XCTAssertEqual(got ?? -1, 0.5, accuracy: 1e-6,
                       "0…1 linear descriptor: normalized 0.5 = real 0.5")
        auto.setClipLanes([])
    }
}
