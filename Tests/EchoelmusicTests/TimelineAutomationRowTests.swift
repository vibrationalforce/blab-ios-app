// TimelineAutomationRowTests.swift
// T1 (founder 2026-07-17 "Automations Sektionen sollten in der Timeline direkt
// sein"): locks the pure geometry/touch law behind the inline timeline
// automation row (TimelineAutomationRowMath — song-absolute tick↔px on the
// clip-grid scale, hit radius, drag preview substitution, alias-aware parameter
// identity) and TimelineStore's first automation WRITE path (lane created on
// first point, alias-merged, kept sorted, emptied lane dropped, deliberately
// OUTSIDE the region undo history).
//
// Pattern notes (from LaneCompositionStoreTests / TimelineRegionSplitMergeTests):
// TimelineStore persists to the real App-Group fallback, so store tests use
// uniquely named parameters and remove every point they added (an emptied lane
// drops out of the document — nothing leaks between runs).

import XCTest
@testable import Echoelmusic

final class TimelineAutomationRowMathTests: XCTestCase {

    // MARK: - Coordinate mapping (song-absolute, clip-grid scale)

    func testXForTick_scalesLinearly_onTheClipGridScale() {
        // ppb 24 → pxPerTick = 24/480 = 0.05: one bar (1920 ticks) = 96 pt,
        // exactly the clip row's 4 beats × 24 pt.
        let pxPerTick = 24.0 / Double(TimelineTime.ticksPerBeat)
        XCTAssertEqual(TimelineAutomationRowMath.x(forTick: 0, pxPerTick: pxPerTick), 0)
        XCTAssertEqual(TimelineAutomationRowMath.x(forTick: TimelineTime.ticksPerBar,
                                                   pxPerTick: pxPerTick), 96, accuracy: 1e-9)
    }

    func testXForTick_guardsDegenerateScale_andNegativeTick() {
        XCTAssertEqual(TimelineAutomationRowMath.x(forTick: 480, pxPerTick: 0), 0)
        XCTAssertEqual(TimelineAutomationRowMath.x(forTick: 480, pxPerTick: -1), 0)
        XCTAssertEqual(TimelineAutomationRowMath.x(forTick: -480, pxPerTick: 0.05), 0)
    }

    func testTickForX_roundsAndClampsIntoSpan() {
        let pxPerTick = 0.05
        XCTAssertEqual(TimelineAutomationRowMath.tick(forX: 96, pxPerTick: pxPerTick,
                                                      maxTick: 7680), 1920)
        // Negative x clamps to 0; beyond the span clamps to maxTick.
        XCTAssertEqual(TimelineAutomationRowMath.tick(forX: -10, pxPerTick: pxPerTick,
                                                      maxTick: 7680), 0)
        XCTAssertEqual(TimelineAutomationRowMath.tick(forX: 1e6, pxPerTick: pxPerTick,
                                                      maxTick: 7680), 7680)
        // Degenerate scale / span never divides or traps.
        XCTAssertEqual(TimelineAutomationRowMath.tick(forX: 50, pxPerTick: 0, maxTick: 7680), 0)
        XCTAssertEqual(TimelineAutomationRowMath.tick(forX: 50, pxPerTick: 0.05, maxTick: 0), 0)
    }

    func testTickX_roundTripIsExactOnTicks() {
        let pxPerTick = 96.0 / Double(TimelineTime.ticksPerBeat)   // max zoom
        for tick in [0, 1, 120, 481, 1920, 7679] {
            let x = TimelineAutomationRowMath.x(forTick: tick, pxPerTick: pxPerTick)
            XCTAssertEqual(TimelineAutomationRowMath.tick(forX: x, pxPerTick: pxPerTick,
                                                          maxTick: 7680), tick)
        }
    }

    // MARK: - Hit-testing

    private func point(tick: Int, value: Double) -> AutomationPoint {
        AutomationPoint(tick: tick, value: value)
    }

    func testNearestPoint_picksTheClosest_andEmptyIsNil() {
        let pxPerTick = 0.05
        let a = point(tick: 0, value: 1)       // x 0,  y 0 (height 64)
        let b = point(tick: 1920, value: 0)    // x 96, y 64
        let hit = TimelineAutomationRowMath.nearestPoint(toX: 90, y: 60,
                                                         points: [a, b],
                                                         pxPerTick: pxPerTick, height: 64)
        XCTAssertEqual(hit?.id, b.id)
        XCTAssertNil(TimelineAutomationRowMath.nearestPoint(toX: 0, y: 0, points: [],
                                                            pxPerTick: pxPerTick, height: 64))
    }

    func testHitPointID_respectsTouchRadius() {
        let pxPerTick = 0.05
        let p = point(tick: 1920, value: 0.5)  // x 96, y 32
        // Inside the 28 pt radius → the point; far away → nil (tap adds there).
        XCTAssertEqual(TimelineAutomationRowMath.hitPointID(atX: 110, y: 40, points: [p],
                                                            pxPerTick: pxPerTick, height: 64),
                       p.id)
        XCTAssertNil(TimelineAutomationRowMath.hitPointID(atX: 300, y: 32, points: [p],
                                                          pxPerTick: pxPerTick, height: 64))
    }

    // MARK: - Drag preview substitution

    func testDisplayPoints_substitutesMovingPoint_andResorts() {
        let a = point(tick: 0, value: 0)
        let b = point(tick: 960, value: 0.5)
        let c = point(tick: 1920, value: 1)
        // Drag b past c: the preview array re-sorts so curve evaluation stays valid.
        let shown = TimelineAutomationRowMath.displayPoints([a, b, c], movingID: b.id,
                                                            toTick: 2400, value: 0.25)
        XCTAssertEqual(shown.map(\.id), [a.id, c.id, b.id])
        XCTAssertEqual(shown.last?.tick, 2400)
        XCTAssertEqual(shown.last?.value ?? -1, 0.25, accuracy: 1e-9)
    }

    func testDisplayPoints_nilID_isIdentity_andValuesClamp() {
        let a = point(tick: 0, value: 0)
        XCTAssertEqual(TimelineAutomationRowMath.displayPoints([a], movingID: nil,
                                                               toTick: 999, value: 9).map(\.id),
                       [a.id])
        let clamped = TimelineAutomationRowMath.displayPoints([a], movingID: a.id,
                                                              toTick: -50, value: 9)
        XCTAssertEqual(clamped.first?.tick, 0)          // tick floors at 0
        XCTAssertEqual(clamped.first?.value, 1)         // value clamps to 0…1
    }

    // MARK: - Parameter identity (alias law)

    func testSameParameter_matchesLegacyRawValueAndKeyPathAlias() {
        XCTAssertTrue(TimelineAutomationRowMath.sameParameter("masterLevel", "master.amp.level"))
        XCTAssertTrue(TimelineAutomationRowMath.sameParameter("transport.tempo.bpm", "tempo"))
        XCTAssertTrue(TimelineAutomationRowMath.sameParameter("free.key.path", "free.key.path"))
        XCTAssertFalse(TimelineAutomationRowMath.sameParameter("masterLevel", "tempo"))
        XCTAssertFalse(TimelineAutomationRowMath.sameParameter("free.key.path", "other.key.path"))
    }
}

// MARK: - TimelineStore automation write path (T1 — the field's first writers)

@MainActor
final class TimelineStoreAutomationTests: XCTestCase {

    /// Unique per-test parameter so the persisted App-Group document can never
    /// flake an assertion; every point added is removed again (emptied lanes
    /// drop out of the document — tidy across runs).
    private func uniqueParameter() -> String { "t1.test.\(UUID().uuidString)" }

    private func removeAll(_ store: TimelineStore, parameter: String) {
        while let lane = store.automationLane(forParameter: parameter),
              let p = lane.points.first {
            store.removeAutomationPoint(parameter: parameter, id: p.id)
        }
    }

    func testAddPoint_createsLaneOnFirstUse_sortedAndPersisted() {
        let store = TimelineStore()
        let parameter = uniqueParameter()
        defer { removeAll(store, parameter: parameter) }

        XCTAssertNil(store.automationLane(forParameter: parameter))
        // Out-of-order adds land sorted; negative tick floors at 0.
        XCTAssertNotNil(store.addAutomationPoint(parameter: parameter, tick: 3840, value: 1))
        XCTAssertNotNil(store.addAutomationPoint(parameter: parameter, tick: -7, value: 0))
        let lane = store.automationLane(forParameter: parameter)
        XCTAssertEqual(lane?.points.map(\.tick), [0, 3840])

        // A fresh store instance loads the persisted document (song-absolute
        // curves are document truth, not player state). persist()'s disk write is
        // debounced (task #56 C6) — flush it so the reload sees this edit rather
        // than racing a still-pending write.
        store.flushPendingSave()
        let reloaded = TimelineStore()
        XCTAssertEqual(reloaded.automationLane(forParameter: parameter)?.points.map(\.tick),
                       [0, 3840])
    }

    func testAliasNamedAdds_landInOneLane_neverSplit() {
        let store = TimelineStore()
        defer {
            removeAll(store, parameter: "masterLevel")
        }
        let before = store.automationLane(forParameter: "masterLevel")?.points.count ?? 0
        store.addAutomationPoint(parameter: "masterLevel", tick: 0, value: 0.5)
        store.addAutomationPoint(parameter: "master.amp.level", tick: 1920, value: 1)
        // Both identities resolve to the SAME lane (delta-scoped: a persisted
        // lane from an earlier run only raises the base count).
        let lane = store.automationLane(forParameter: "master.amp.level")
        XCTAssertEqual(lane?.points.count, before + 2)
        XCTAssertEqual(store.document.automation.filter {
            TimelineAutomationRowMath.sameParameter($0.parameter, "masterLevel")
        }.count, 1)
    }

    func testMovePoint_movesAndRevalues_keepingTheLaneSorted() {
        let store = TimelineStore()
        let parameter = uniqueParameter()
        defer { removeAll(store, parameter: parameter) }

        guard let a = store.addAutomationPoint(parameter: parameter, tick: 0, value: 0),
              store.addAutomationPoint(parameter: parameter, tick: 1920, value: 1) != nil
        else { return XCTFail("add failed") }

        store.moveAutomationPoint(parameter: parameter, id: a.id, toTick: 3840, normalized: 0.25)
        let lane = store.automationLane(forParameter: parameter)
        XCTAssertEqual(lane?.points.map(\.tick), [1920, 3840])   // re-sorted
        let moved = lane?.points.first { $0.id == a.id }
        XCTAssertEqual(moved?.value ?? -1, 0.25, accuracy: 1e-9)
        // Unknown parameter: safe no-op, never a trap.
        store.moveAutomationPoint(parameter: uniqueParameter(), id: a.id,
                                  toTick: 0, normalized: 0)
    }

    func testRemoveLastPoint_dropsTheEmptiedLane() {
        let store = TimelineStore()
        let parameter = uniqueParameter()
        guard let p = store.addAutomationPoint(parameter: parameter, tick: 0, value: 0.5)
        else { return XCTFail("add failed") }
        store.removeAutomationPoint(parameter: parameter, id: p.id)
        XCTAssertNil(store.automationLane(forParameter: parameter))
        XCTAssertFalse(store.document.automation.contains {
            TimelineAutomationRowMath.sameParameter($0.parameter, parameter)
        })
    }

    func testAutomationEdits_stayOutsideTheRegionUndoHistory() {
        // Documented limit (the undo stack snapshots ONLY document.regions):
        // automation edits must never mint an undo step — an undo after drawing
        // a curve must not silently revert a region edit (or vice versa).
        let store = TimelineStore()
        let parameter = uniqueParameter()
        defer { removeAll(store, parameter: parameter) }

        XCTAssertFalse(store.canUndo)
        guard let p = store.addAutomationPoint(parameter: parameter, tick: 0, value: 0.5)
        else { return XCTFail("add failed") }
        store.moveAutomationPoint(parameter: parameter, id: p.id, toTick: 480, normalized: 1)
        XCTAssertFalse(store.canUndo)
        store.removeAutomationPoint(parameter: parameter, id: p.id)
        XCTAssertFalse(store.canUndo)
    }
}
