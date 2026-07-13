// LaneVoiceSlotMapTests.swift
// Multi-Roll cycle 1 — the PURE slot-assignment logic behind LaneVoicePool: a
// fixed pool of N pre-attached voices, lanes bound to a stable slot (reused across
// calls, freed on release, capped at capacity). Deterministic → tested without any
// audio object; the pool is thin @MainActor wiring over this.

import XCTest
import Foundation
@testable import Echoelmusic

final class LaneVoiceSlotMapTests: XCTestCase {

    func testFresh_isEmpty() {
        let m = LaneVoiceSlotMap(capacity: 4)
        XCTAssertEqual(m.assignedCount, 0)
    }

    func testAssign_thenReuseIsStable() {
        var m = LaneVoiceSlotMap(capacity: 4)
        let a = UUID()
        let first = m.slot(for: a)
        XCTAssertEqual(first, 0)
        XCTAssertEqual(m.slot(for: a), 0)   // same lane → same slot, stable
        XCTAssertEqual(m.assignedCount, 1)
    }

    func testDistinctLanes_getLowestFreeSlots() {
        var m = LaneVoiceSlotMap(capacity: 4)
        XCTAssertEqual(m.slot(for: UUID()), 0)
        XCTAssertEqual(m.slot(for: UUID()), 1)
        XCTAssertEqual(m.slot(for: UUID()), 2)
    }

    func testFull_returnsNilForNewLane_existingStillResolve() {
        var m = LaneVoiceSlotMap(capacity: 2)
        let a = UUID(), b = UUID()
        XCTAssertEqual(m.slot(for: a), 0)
        XCTAssertEqual(m.slot(for: b), 1)
        XCTAssertNil(m.slot(for: UUID()))   // pool full → nil (caller falls back to shared voice)
        XCTAssertEqual(m.slot(for: a), 0)   // already-bound lanes still resolve
        XCTAssertEqual(m.slot(for: b), 1)
    }

    func testRelease_freesLowestSlotForReuse() {
        var m = LaneVoiceSlotMap(capacity: 3)
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(m.slot(for: a), 0)
        XCTAssertEqual(m.slot(for: b), 1)
        XCTAssertEqual(m.slot(for: c), 2)
        m.release(b)                        // frees slot 1
        XCTAssertEqual(m.assignedCount, 2)
        XCTAssertEqual(m.slot(for: UUID()), 1)   // new lane takes the freed lowest slot
    }

    func testRelease_unknownLane_isNoOp() {
        var m = LaneVoiceSlotMap(capacity: 2)
        let a = UUID()
        XCTAssertEqual(m.slot(for: a), 0)
        m.release(UUID())                   // not assigned → nothing changes
        XCTAssertEqual(m.assignedCount, 1)
        XCTAssertEqual(m.slot(for: a), 0)
    }

    func testZeroCapacity_alwaysNil() {
        var m = LaneVoiceSlotMap(capacity: 0)
        XCTAssertNil(m.slot(for: UUID()))
        XCTAssertEqual(m.assignedCount, 0)
    }
}
