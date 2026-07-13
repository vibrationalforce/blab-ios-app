// LaneVoicePoolTests.swift
// Multi-Roll (keystone P1) — the pure per-lane voice-allocation contract: slot
// assignment/reuse/overflow, reconciliation on lane add/remove, and the schedule→slot
// plan. No audio, no engine → runs on every platform.

import XCTest
@testable import Echoelmusic

final class LaneVoicePoolTests: XCTestCase {

    private func midiLane(_ name: String) -> TimelineLane { TimelineLane(name: name, kind: .midi) }

    // MARK: LaneVoicePool allocation

    func testReconcile_emptySet_noBindings() {
        var pool = LaneVoicePool(capacity: 4)
        XCTAssertTrue(pool.reconcile(activeLaneIDs: []).isEmpty)
        XCTAssertEqual(pool.boundCount, 0)
    }

    func testReconcile_lanesWithinCapacity_getDistinctSlotsInOrder() {
        var pool = LaneVoicePool(capacity: 4)
        let a = UUID(), b = UUID(), c = UUID()
        let t = pool.reconcile(activeLaneIDs: [a, b, c])
        XCTAssertEqual(t.map(\.slot), [0, 1, 2])       // priority = lane order
        XCTAssertEqual(t.map(\.laneID), [a, b, c])
        XCTAssertEqual(pool.boundCount, 3)
    }

    func testReconcile_isStableAndIdempotent() {
        var pool = LaneVoicePool(capacity: 4)
        let a = UUID(), b = UUID()
        let first = pool.reconcile(activeLaneIDs: [a, b])
        let second = pool.reconcile(activeLaneIDs: [a, b])
        XCTAssertEqual(first, second)                   // same input → same bindings
        XCTAssertEqual(pool.slot(for: a), 0)
        XCTAssertEqual(pool.slot(for: b), 1)
    }

    func testReconcile_overflow_beyondCapacityIsFallback() {
        var pool = LaneVoicePool(capacity: 2)
        let a = UUID(), b = UUID(), c = UUID()
        let t = pool.reconcile(activeLaneIDs: [a, b, c])
        XCTAssertEqual(t.map(\.slot), [0, 1, nil])      // 3rd lane → shared fallback
        XCTAssertTrue(t[2].usesFallback)
        XCTAssertEqual(pool.boundCount, 2)
    }

    func testReconcile_releasedLaneFreesLowestSlotForReuse() {
        var pool = LaneVoicePool(capacity: 2)
        let a = UUID(), b = UUID(), c = UUID()
        _ = pool.reconcile(activeLaneIDs: [a, b])       // a→0, b→1
        // Remove `a`; add `c`. Freed slot 0 is the lowest free → c takes it. b stays at 1.
        _ = pool.reconcile(activeLaneIDs: [b, c])
        XCTAssertEqual(pool.slot(for: b), 1)            // unchanged (stable)
        XCTAssertEqual(pool.slot(for: c), 0)            // reused deterministically
        XCTAssertNil(pool.slot(for: a))                 // released
    }

    func testReconcile_capacityZero_allFallback() {
        var pool = LaneVoicePool(capacity: 0)
        let a = UUID(), b = UUID()
        let t = pool.reconcile(activeLaneIDs: [a, b])
        XCTAssertEqual(t.map(\.slot), [nil, nil])
    }

    func testTwoPools_sameInput_produceEqualBindings() {
        let ids = [UUID(), UUID(), UUID()]
        var p1 = LaneVoicePool(capacity: 2)
        var p2 = LaneVoicePool(capacity: 2)
        XCTAssertEqual(p1.reconcile(activeLaneIDs: ids), p2.reconcile(activeLaneIDs: ids))
        XCTAssertEqual(p1, p2)
    }

    // MARK: LaneVoiceScheduling.plan (schedule → slot)

    func testPlan_regionOnSecondLane_loadsOnlyThatLaneAtOnset() {
        let l1 = midiLane("MIDI 1"), l2 = midiLane("MIDI 2")
        let clip = UUID()
        let region = TimelineRegion(laneID: l2.id, clipID: clip,
                                    startTick: 0, lengthTicks: TimelineTime.ticksPerBar)
        let doc = TimelineDocument(lanes: [l1, l2], regions: [region])
        var pool = LaneVoicePool(capacity: 4)
        let steps = LaneVoiceScheduling.plan(in: doc, fromTick: -1, toTick: 0, pool: &pool)
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].laneID, l1.id)
        XCTAssertEqual(steps[0].slot, 0)
        XCTAssertEqual(steps[0].event, .unchanged)      // l1: empty→empty
        XCTAssertEqual(steps[1].laneID, l2.id)
        XCTAssertEqual(steps[1].slot, 1)
        XCTAssertEqual(steps[1].event, .load(region))   // l2: onset load into slot 1
    }

    func testPlan_ignoresBioAndAudioLanes() {
        var bio = midiLane("Bio"); bio.isBio = true
        let audio = TimelineLane(name: "Audio 1", kind: .audio)
        let m = midiLane("MIDI 1")
        let doc = TimelineDocument(lanes: [bio, audio, m], regions: [])
        var pool = LaneVoicePool(capacity: 4)
        let steps = LaneVoiceScheduling.plan(in: doc, fromTick: 0, toTick: 0, pool: &pool)
        XCTAssertEqual(steps.map(\.laneID), [m.id])     // only the non-bio MIDI lane
        XCTAssertEqual(steps.first?.slot, 0)
    }
}
