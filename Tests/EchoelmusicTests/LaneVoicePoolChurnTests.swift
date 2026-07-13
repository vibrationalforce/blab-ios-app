// LaneVoicePoolChurnTests.swift
// Multi-Roll (keystone P1) — stability of LaneVoicePool.reconcile under lane churn:
// a lane keeps its slot while others rotate, a freed slot is reused, and an
// OVERFLOW lane is PROMOTED to a real voice when a higher-priority lane leaves.
// These are the exact behaviors the device-gated LaneVoiceRack (B07) depends on,
// so they are pinned here — pure, runs on every platform. Complements the base
// allocation cases in LaneVoicePoolTests.

import XCTest
@testable import Echoelmusic

final class LaneVoicePoolChurnTests: XCTestCase {

    // A held lane must NEVER move slot while it stays active, however many other
    // lanes come and go around it.
    func testChurn_heldLaneKeepsSlotWhileOthersRotate() {
        var pool = LaneVoicePool(capacity: 4)
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        _ = pool.reconcile(activeLaneIDs: [a, b])          // a→0, b→1
        XCTAssertEqual(pool.slot(for: a), 0)
        _ = pool.reconcile(activeLaneIDs: [a, c])          // b gone, c joins
        XCTAssertEqual(pool.slot(for: a), 0, "a must stay on its slot")
        _ = pool.reconcile(activeLaneIDs: [a, d])          // c gone, d joins
        XCTAssertEqual(pool.slot(for: a), 0, "a still stable across full rotation")
        XCTAssertNil(pool.slot(for: b))
        XCTAssertNil(pool.slot(for: c))
    }

    // An overflowed lane (slot == nil) must be PROMOTED to the freed voice when a
    // higher-priority lane is removed — otherwise a capacity-full song never lets
    // a lower lane sound after another stops.
    func testOverflow_promotedWhenHigherPriorityLaneRemoved() {
        var pool = LaneVoicePool(capacity: 2)
        let a = UUID(), b = UUID(), c = UUID()
        let first = pool.reconcile(activeLaneIDs: [a, b, c]) // a→0, b→1, c→nil (overflow)
        XCTAssertEqual(first.map(\.slot), [0, 1, nil])
        XCTAssertTrue(first[2].usesFallback)

        let after = pool.reconcile(activeLaneIDs: [b, c])    // a leaves → slot 0 frees
        XCTAssertEqual(pool.slot(for: b), 1, "b stays put")
        XCTAssertEqual(pool.slot(for: c), 0, "c promoted from fallback into the freed voice")
        XCTAssertEqual(after.first(where: { $0.laneID == c })?.slot, 0)
        XCTAssertNil(pool.slot(for: a))
        XCTAssertEqual(pool.boundCount, 2)
    }

    // Overflow assignment is priority-ordered: the top `capacity` lanes (in
    // activeLaneIDs order) get voices, the rest are fallback — deterministically.
    func testOverflow_orderingManyLanes() {
        var pool = LaneVoicePool(capacity: 3)
        let ids = (0..<5).map { _ in UUID() }
        let t = pool.reconcile(activeLaneIDs: ids)
        XCTAssertEqual(t.map(\.slot), [0, 1, 2, nil, nil])
        XCTAssertEqual(t.map(\.laneID), ids, "returned in priority (input) order")
        XCTAssertEqual(pool.boundCount, 3)
    }

    // Returned order follows the input; each lane's slot is stable regardless of the
    // order it is presented in.
    func testReconcile_reorderingActiveLanes_keepsPerLaneSlots() {
        var pool = LaneVoicePool(capacity: 4)
        let a = UUID(), b = UUID()
        _ = pool.reconcile(activeLaneIDs: [a, b])            // a→0, b→1
        let t = pool.reconcile(activeLaneIDs: [b, a])        // presented reversed
        XCTAssertEqual(t.map(\.laneID), [b, a], "order follows input")
        XCTAssertEqual(t.map(\.slot), [1, 0], "but slots are stable per lane")
    }

    // A full release resets binding state; re-adding a previously-overflowed lane
    // then gives it the lowest free voice.
    func testChurn_fullReleaseThenRebind() {
        var pool = LaneVoicePool(capacity: 2)
        let a = UUID(), b = UUID(), c = UUID()
        _ = pool.reconcile(activeLaneIDs: [a, b, c])         // c overflowed
        XCTAssertEqual(pool.boundCount, 2)
        _ = pool.reconcile(activeLaneIDs: [])                // everything released
        XCTAssertEqual(pool.boundCount, 0)
        let t = pool.reconcile(activeLaneIDs: [c])           // c now gets a real voice
        XCTAssertEqual(t.map(\.slot), [0])
        XCTAssertEqual(pool.slot(for: c), 0)
        XCTAssertNil(pool.slot(for: a))
    }
}
