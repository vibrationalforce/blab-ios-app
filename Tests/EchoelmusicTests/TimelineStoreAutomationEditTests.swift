// Automation-in-Spur S1 — song-absolute precision-edit parity on the TimelineStore.
// The inline row already writes document.automation via add/move/removeAutomationPoint.
// The precision editor (AutomationView, S2) needs the remaining per-keyframe ops —
// set-value-only, curve, curvature, and clear — on the SAME song-absolute store, so
// the deep editor stops mutating the disconnected loop layer (AutomationPlayer.lanes).
// Pure store round-trips; no UI, no device (PLAN_AUTOMATION_IN_TRACK_2026-07-20.md).

import XCTest
@testable import Echoelmusic

final class TimelineStoreAutomationEditTests: XCTestCase {

    private let param = AutomationTarget.masterLevel.rawValue

    @MainActor
    func testSetAutomationValue_revaluesTheKeyframeWithoutMoving() throws {
        let store = TimelineStore()
        guard let p = store.addAutomationPoint(parameter: param, tick: 480, value: 0.2) else {
            return XCTFail("no point")
        }
        store.setAutomationValue(parameter: param, id: p.id, normalized: 0.9)
        let lane = store.automationLane(forParameter: param)
        let firstValue = try XCTUnwrap(lane?.points.first?.value)
        XCTAssertEqual(firstValue, 0.9, accuracy: 1e-9)
        XCTAssertEqual(lane?.points.first?.tick, 480, "value-only edit must not move the point")
    }

    @MainActor
    func testSetAutomationCurve_andCurvature() {
        let store = TimelineStore()
        guard let p = store.addAutomationPoint(parameter: param, tick: 0, value: 0.5) else {
            return XCTFail("no point")
        }
        store.setAutomationCurve(parameter: param, id: p.id, .hold)
        XCTAssertEqual(store.automationLane(forParameter: param)?.points.first?.curve, .hold)

        store.setAutomationCurvature(parameter: param, id: p.id, 0.7)
        XCTAssertEqual(store.automationLane(forParameter: param)?.points.first?.curvature ?? 0,
                       0.7, accuracy: 1e-9)
    }

    @MainActor
    func testClearAutomation_dropsTheLaneEntirely() {
        let store = TimelineStore()
        _ = store.addAutomationPoint(parameter: param, tick: 0, value: 0.3)
        _ = store.addAutomationPoint(parameter: param, tick: 960, value: 0.8)
        XCTAssertNotNil(store.automationLane(forParameter: param))

        store.clearAutomation(parameter: param)
        XCTAssertNil(store.automationLane(forParameter: param),
                     "clearing leaves no ghost lane — the row's empty state returns")
    }

    @MainActor
    func testUnknownParameterOrID_noCrashNoChange() throws {
        let store = TimelineStore()
        guard let p = store.addAutomationPoint(parameter: param, tick: 240, value: 0.4) else {
            return XCTFail("no point")
        }
        // Unknown parameter: nothing to touch, must not create a lane.
        store.setAutomationValue(parameter: "does.not.exist", id: p.id, normalized: 0.1)
        XCTAssertNil(store.automationLane(forParameter: "does.not.exist"))
        // Unknown id on a real lane: leaves the existing keyframe intact.
        store.setAutomationValue(parameter: param, id: UUID(), normalized: 0.1)
        let intact = try XCTUnwrap(store.automationLane(forParameter: param)?.points.first?.value)
        XCTAssertEqual(intact, 0.4, accuracy: 1e-9)
    }

    @MainActor
    func testAliasIdentity_precisionEditHitsTheSameLaneAsTheRow() throws {
        // The row may have created the lane under the legacy rawValue; a precision
        // edit addressed by the registry keyPath alias must reach the SAME lane
        // (never split master automation into two curves).
        let store = TimelineStore()
        guard let p = store.addAutomationPoint(parameter: "masterLevel", tick: 0, value: 0.5) else {
            return XCTFail("no point")
        }
        store.setAutomationValue(parameter: "master.amp.level", id: p.id, normalized: 0.25)
        let aliased = try XCTUnwrap(store.automationLane(forParameter: "masterLevel")?.points.first?.value)
        XCTAssertEqual(aliased, 0.25, accuracy: 1e-9, "alias edit must land on the same lane")
    }
}
