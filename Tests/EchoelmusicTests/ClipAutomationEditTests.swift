// ClipAutomationEditTests.swift
// Automation-in-Spur L1 / S2a: pins the pure array-level edit brain the clip
// automation canvas (S2b) will call before handing the result to
// ClipStore.setClipAutomation. Geometry expectations reference
// AutomationCanvasMath's public constants so they stay robust to the tick model.

import XCTest
@testable import Echoelmusic

final class ClipAutomationEditTests: XCTestCase {

    private let span = AutomationCanvasMath.barTicks
    private var step: Int { AutomationCanvasMath.snapTicks }

    // MARK: - upsert: create lane

    func testUpsert_onEmpty_createsLaneWithSnappedPoint() {
        let out = ClipAutomationEdit.upsertPoint([], parameter: "ddsp.filter.cutoff",
                                                 tick: 2 * step, value: 0.5, spanTicks: span)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].parameter, "ddsp.filter.cutoff")
        XCTAssertEqual(out[0].points.count, 1)
        XCTAssertEqual(out[0].points[0].tick,
                       AutomationCanvasMath.snappedTick(2 * step, spanTicks: span))
        XCTAssertEqual(out[0].points[0].value, 0.5, accuracy: 1e-9)
    }

    func testUpsert_differentParameter_addsSecondLane() {
        var out = ClipAutomationEdit.upsertPoint([], parameter: "mix.level",
                                                 tick: 0, value: 0.3, spanTicks: span)
        out = ClipAutomationEdit.upsertPoint(out, parameter: "ddsp.reverb.mix",
                                             tick: 0, value: 0.7, spanTicks: span)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(Set(out.map(\.parameter)), ["mix.level", "ddsp.reverb.mix"])
    }

    // MARK: - upsert: add vs update

    func testUpsert_sameParameterDifferentTick_addsKeyframe() {
        var out = ClipAutomationEdit.upsertPoint([], parameter: "mix.level",
                                                 tick: 0, value: 0.2, spanTicks: span)
        out = ClipAutomationEdit.upsertPoint(out, parameter: "mix.level",
                                             tick: 4 * step, value: 0.8, spanTicks: span)
        XCTAssertEqual(out.count, 1, "same parameter → same lane")
        XCTAssertEqual(out[0].points.count, 2)
    }

    func testUpsert_sameSnappedTick_updatesValue_noDuplicate() {
        var out = ClipAutomationEdit.upsertPoint([], parameter: "mix.level",
                                                 tick: 2 * step, value: 0.2, spanTicks: span)
        // Re-draw over the same step: value replaced, not stacked.
        out = ClipAutomationEdit.upsertPoint(out, parameter: "mix.level",
                                             tick: 2 * step, value: 0.9, spanTicks: span)
        XCTAssertEqual(out[0].points.count, 1)
        XCTAssertEqual(out[0].points[0].value, 0.9, accuracy: 1e-9)
    }

    func testUpsert_differentRawTicksSnappingToSameStep_collapseToOneKeyframe() {
        // The load-bearing snap-collision contract: two DIFFERENT raw ticks that
        // both snap to the same step must UPDATE one keyframe, not stack two. If
        // snapping ever regressed to identity, these would land as two points.
        let a = 2 * step - step / 3
        let b = 2 * step + step / 3
        XCTAssertEqual(AutomationCanvasMath.snappedTick(a, spanTicks: span),
                       AutomationCanvasMath.snappedTick(b, spanTicks: span),
                       "test premise: both raw ticks snap to the same step")
        var out = ClipAutomationEdit.upsertPoint([], parameter: "mix.level",
                                                 tick: a, value: 0.2, spanTicks: span)
        out = ClipAutomationEdit.upsertPoint(out, parameter: "mix.level",
                                             tick: b, value: 0.9, spanTicks: span)
        XCTAssertEqual(out[0].points.count, 1, "same snapped step → one keyframe")
        XCTAssertEqual(out[0].points[0].value, 0.9, accuracy: 1e-9)
    }

    // MARK: - clamping (inherited from AutomationLane/Point)

    func testUpsert_clampsValueIntoUnit() {
        let out = ClipAutomationEdit.upsertPoint([], parameter: "mix.level",
                                                 tick: 0, value: 2.0, spanTicks: span)
        XCTAssertEqual(out[0].points[0].value, 1.0, accuracy: 1e-9)
    }

    func testUpsert_clampsTickIntoSpan() {
        let out = ClipAutomationEdit.upsertPoint([], parameter: "mix.level",
                                                 tick: span + 5 * step, value: 0.5, spanTicks: span)
        XCTAssertEqual(out[0].points[0].tick,
                       AutomationCanvasMath.snappedTick(span + 5 * step, spanTicks: span))
        XCTAssertLessThanOrEqual(out[0].points[0].tick, span)
    }

    // MARK: - move

    func testMovePoint_movesAndUpdatesValue() {
        let created = ClipAutomationEdit.upsertPoint([], parameter: "mix.level",
                                                     tick: 0, value: 0.2, spanTicks: span)
        let id = created[0].points[0].id
        let out = ClipAutomationEdit.movePoint(created, id: id,
                                               toTick: 4 * step, value: 0.6, spanTicks: span)
        XCTAssertEqual(out[0].points[0].tick,
                       AutomationCanvasMath.snappedTick(4 * step, spanTicks: span))
        XCTAssertEqual(out[0].points[0].value, 0.6, accuracy: 1e-9)
    }

    func testMovePoint_unknownID_isNoOp() {
        let created = ClipAutomationEdit.upsertPoint([], parameter: "mix.level",
                                                     tick: 0, value: 0.2, spanTicks: span)
        let out = ClipAutomationEdit.movePoint(created, id: UUID(),
                                               toTick: 4 * step, value: 0.6, spanTicks: span)
        XCTAssertEqual(out, created)
    }

    // MARK: - remove + prune

    func testRemovePoint_prunesEmptyLaneByDefault() {
        let created = ClipAutomationEdit.upsertPoint([], parameter: "mix.level",
                                                     tick: 0, value: 0.2, spanTicks: span)
        let id = created[0].points[0].id
        let out = ClipAutomationEdit.removePoint(created, id: id)
        XCTAssertTrue(out.isEmpty, "a cleared parameter is pruned, not left as a dead empty lane")
    }

    func testRemovePoint_keepsEmptyLaneWhenPruneOff() {
        let created = ClipAutomationEdit.upsertPoint([], parameter: "mix.level",
                                                     tick: 0, value: 0.2, spanTicks: span)
        let id = created[0].points[0].id
        let out = ClipAutomationEdit.removePoint(created, id: id, pruneEmptyLanes: false)
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].isEmpty)
    }

    func testRemovePoint_oneOfTwoKeepsLane() {
        var created = ClipAutomationEdit.upsertPoint([], parameter: "mix.level",
                                                     tick: 0, value: 0.2, spanTicks: span)
        created = ClipAutomationEdit.upsertPoint(created, parameter: "mix.level",
                                                 tick: 4 * step, value: 0.8, spanTicks: span)
        let firstID = created[0].points[0].id
        let out = ClipAutomationEdit.removePoint(created, id: firstID)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].points.count, 1)
        XCTAssertNotEqual(out[0].points[0].id, firstID)
    }

    // MARK: - laneIndex + targeting

    func testLaneIndex_findsAndMisses() {
        let out = ClipAutomationEdit.upsertPoint([], parameter: "mix.level",
                                                 tick: 0, value: 0.5, spanTicks: span)
        XCTAssertEqual(ClipAutomationEdit.laneIndex(for: "mix.level", in: out), 0)
        XCTAssertNil(ClipAutomationEdit.laneIndex(for: "nope", in: out))
    }

    func testUpsert_targetsOnlyItsOwnLane() {
        var out = ClipAutomationEdit.upsertPoint([], parameter: "a", tick: 0, value: 0.1, spanTicks: span)
        out = ClipAutomationEdit.upsertPoint(out, parameter: "b", tick: 0, value: 0.2, spanTicks: span)
        out = ClipAutomationEdit.upsertPoint(out, parameter: "a", tick: 4 * step, value: 0.9, spanTicks: span)
        let a = out.first { $0.parameter == "a" }
        let b = out.first { $0.parameter == "b" }
        XCTAssertEqual(a?.points.count, 2)
        XCTAssertEqual(b?.points.count, 1, "editing 'a' must not touch 'b'")
    }

    // MARK: - curvature

    func testSetCurvature_bendsSegment() {
        let created = ClipAutomationEdit.upsertPoint([], parameter: "mix.level",
                                                     tick: 0, value: 0.5, spanTicks: span)
        let id = created[0].points[0].id
        let out = ClipAutomationEdit.setCurvature(created, id: id, 0.7)
        XCTAssertEqual(out[0].points[0].curvature, 0.7, accuracy: 1e-9)
    }
}
