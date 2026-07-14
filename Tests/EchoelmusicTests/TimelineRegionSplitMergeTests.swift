// TimelineRegionSplitMergeTests.swift
// DAW#2 — "Clips schneiden und zusammenfügen". Pure tick-math tests for the
// region split (cut) + merge (join) helpers. No store/actor needed.

import XCTest
@testable import Echoelmusic

final class TimelineRegionSplitMergeTests: XCTestCase {

    private let lane = UUID()
    private let clip = UUID()

    private func region(start: Int, length: Int, offset: Double = 0) -> TimelineRegion {
        TimelineRegion(laneID: lane, clipID: clip, startTick: start,
                       lengthTicks: length, contentOffsetSeconds: offset)
    }

    // MARK: - Split

    func testSplit_insideTick_producesTwoAbuttingPieces() {
        let r = region(start: 0, length: 1920)                 // one bar
        let pieces = r.split(at: 480, bpm: 120)                // cut at beat 1
        let (first, second) = try! XCTUnwrap(pieces)
        XCTAssertEqual(first.startTick, 0)
        XCTAssertEqual(first.lengthTicks, 480)
        XCTAssertEqual(second.startTick, 480)
        XCTAssertEqual(second.lengthTicks, 1440)
        XCTAssertEqual(first.endTick, second.startTick, "pieces must abut with no gap/overlap")
        XCTAssertEqual(first.id, r.id, "first piece keeps the original identity")
        XCTAssertNotEqual(second.id, r.id, "second piece gets a fresh identity")
        XCTAssertEqual(first.laneID, r.laneID)
        XCTAssertEqual(second.clipID, r.clipID)
    }

    func testSplit_advancesSecondPieceMediaOffset() {
        // 480 ticks = one quarter; at 120 BPM a quarter is 0.5 s.
        let r = region(start: 0, length: 1920, offset: 2.0)
        let (_, second) = try! XCTUnwrap(r.split(at: 480, bpm: 120))
        XCTAssertEqual(second.contentOffsetSeconds, 2.0 + 0.5, accuracy: 1e-9,
                       "second piece's media start advances by the elapsed time")
    }

    func testSplit_atOrOutsideEdges_isNil() {
        let r = region(start: 100, length: 800)                 // 100…900
        XCTAssertNil(r.split(at: 100, bpm: 120), "split at start edge = no-op")
        XCTAssertNil(r.split(at: 900, bpm: 120), "split at end edge = no-op")
        XCTAssertNil(r.split(at: 50, bpm: 120), "split before region = no-op")
        XCTAssertNil(r.split(at: 950, bpm: 120), "split after region = no-op")
    }

    func testSplit_totalLengthPreserved() {
        let r = region(start: 240, length: 1000)
        let (first, second) = try! XCTUnwrap(r.split(at: 700, bpm: 90))
        XCTAssertEqual(first.lengthTicks + second.lengthTicks, r.lengthTicks)
    }

    // MARK: - Merge (the undo of a split)

    func testAbuts_sameLaneClipTouching_true() {
        let a = region(start: 0, length: 480)
        let b = region(start: 480, length: 480)                 // starts where a ends
        XCTAssertTrue(a.abuts(b))
    }

    func testAbuts_gap_or_differentClip_false() {
        let a = region(start: 0, length: 480)
        XCTAssertFalse(a.abuts(region(start: 500, length: 480)), "gap ⇒ not mergeable")
        var otherClip = region(start: 480, length: 480)
        otherClip = TimelineRegion(laneID: lane, clipID: UUID(), startTick: 480, lengthTicks: 480)
        XCTAssertFalse(a.abuts(otherClip), "different clip ⇒ not mergeable (lossy)")
    }

    func testMerged_spansBothKeepsFirstIdentity() {
        let a = region(start: 0, length: 480, offset: 1.0)
        let b = region(start: 480, length: 1440)
        let m = a.merged(with: b)
        XCTAssertEqual(m.startTick, 0)
        XCTAssertEqual(m.lengthTicks, 1920, "spans a.start … b.end")
        XCTAssertEqual(m.id, a.id, "merge keeps the first region's identity")
        XCTAssertEqual(m.contentOffsetSeconds, 1.0, "keeps the first region's media start")
    }

    /// Split-then-merge round-trips the geometry (a clean cut is losslessly rejoinable).
    func testSplitThenMerge_roundTripsGeometry() {
        let r = region(start: 0, length: 1920, offset: 0)
        let (first, second) = try! XCTUnwrap(r.split(at: 640, bpm: 120))
        XCTAssertTrue(first.abuts(second))
        let m = first.merged(with: second)
        XCTAssertEqual(m.startTick, r.startTick)
        XCTAssertEqual(m.lengthTicks, r.lengthTicks)
    }
}

/// Store-level razor (split-at-playhead) + join round-trip across the whole document.
@MainActor
final class TimelineStoreSplitMergeTests: XCTestCase {

    func testSplitRegions_razorsEveryCrossedRegion_thenJoinRestores() {
        let store = TimelineStore()
        let lane = UUID()
        let clip = UUID()
        // Two bars back-to-back on one lane; the playhead sits mid-first-bar.
        store.addRegion(TimelineRegion(laneID: lane, clipID: clip, startTick: 0, lengthTicks: 1920))
        store.addRegion(TimelineRegion(laneID: lane, clipID: clip, startTick: 1920, lengthTicks: 1920))
        XCTAssertEqual(store.document.regions.count, 2)

        // Razor at tick 960 (inside the first region only) → 3 regions.
        store.splitRegions(atTick: 960, bpm: 120)
        XCTAssertEqual(store.document.regions.count, 3, "only the crossed region splits")

        // Join at 960 → back to 2.
        store.mergeRegions(atTick: 960)
        XCTAssertEqual(store.document.regions.count, 2, "the two pieces at the tick rejoin")
        // The rejoined region spans the original first bar again.
        XCTAssertTrue(store.document.regions.contains { $0.startTick == 0 && $0.lengthTicks == 1920 })
    }

    func testSplitRegions_atEdge_isNoOp() {
        let store = TimelineStore()
        let lane = UUID(); let clip = UUID()
        store.addRegion(TimelineRegion(laneID: lane, clipID: clip, startTick: 0, lengthTicks: 1920))
        let before = store.document.regions.count
        store.splitRegions(atTick: 0, bpm: 120)      // start edge
        store.splitRegions(atTick: 5000, bpm: 120)   // past the region
        XCTAssertEqual(store.document.regions.count, before, "edge/outside razor changes nothing")
    }
}
