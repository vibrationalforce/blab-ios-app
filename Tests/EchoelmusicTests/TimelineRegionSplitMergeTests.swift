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

    // MARK: - Front-trim (leading edge — founder "auch vorne ziehen")

    func testTrimmedStart_movingRight_shortensAndAdvancesOffset() {
        // 480 ticks = one quarter = 0.5 s @ 120 BPM. Trim the front by a quarter.
        let r = region(start: 0, length: 1920, offset: 0)
        let t = try! XCTUnwrap(r.trimmedStart(toTick: 480, bpm: 120))
        XCTAssertEqual(t.startTick, 480, "leading edge moved right")
        XCTAssertEqual(t.endTick, r.endTick, "end held fixed")
        XCTAssertEqual(t.lengthTicks, 1440, "length shrank by the trimmed amount")
        XCTAssertEqual(t.contentOffsetSeconds, 0.5, accuracy: 1e-9,
                       "media offset advances so the content stays put")
        XCTAssertEqual(t.id, r.id, "same region, just trimmed")
    }

    func testTrimmedStart_movingLeft_extendsAndReducesOffset() {
        // Region starts at tick 960 with 1.0 s of media pre-roll; extend the front left.
        let r = region(start: 960, length: 960, offset: 1.0)
        let t = try! XCTUnwrap(r.trimmedStart(toTick: 480, bpm: 120))   // 480 ticks left = 0.5 s
        XCTAssertEqual(t.startTick, 480)
        XCTAssertEqual(t.endTick, r.endTick, "end held fixed")
        XCTAssertEqual(t.lengthTicks, 1440, "length grew by the revealed amount")
        XCTAssertEqual(t.contentOffsetSeconds, 0.5, accuracy: 1e-9,
                       "offset reduced by the revealed media time")
    }

    func testTrimmedStart_cannotRevealBeforeMediaStart() {
        // Only 0.5 s (480 ticks @ 120 BPM) of pre-roll — can't extend the front further left.
        let r = region(start: 960, length: 960, offset: 0.5)
        let t = try! XCTUnwrap(r.trimmedStart(toTick: 0, bpm: 120))
        XCTAssertEqual(t.startTick, 480, "clamped to the media start (960 - 480 ticks)")
        XCTAssertEqual(t.contentOffsetSeconds, 0, accuracy: 1e-9, "offset bottoms out at 0")
        XCTAssertEqual(t.endTick, r.endTick)
    }

    func testTrimmedStart_midiOffsetZero_cannotFrontExtend() {
        // A MIDI/offset-0 region has no earlier media → the front can't extend left.
        let r = region(start: 480, length: 480, offset: 0)
        XCTAssertNil(r.trimmedStart(toTick: 0, bpm: 120), "no pre-roll ⇒ front-extend is a no-op")
        // …but it can still trim right (shorten from the front).
        let t = try! XCTUnwrap(r.trimmedStart(toTick: 600, bpm: 120))
        XCTAssertEqual(t.startTick, 600)
        XCTAssertEqual(t.endTick, 960, "end held fixed")
    }

    func testTrimmedStart_clampsAtEndAndNoOp() {
        let r = region(start: 100, length: 800)                        // 100…900
        let atEnd = try! XCTUnwrap(r.trimmedStart(toTick: 5000, bpm: 120))
        XCTAssertEqual(atEnd.startTick, 899, "clamped to keep ≥ 1 tick")
        XCTAssertEqual(atEnd.lengthTicks, 1)
        XCTAssertNil(r.trimmedStart(toTick: 100, bpm: 120), "start unchanged ⇒ nil")
    }

    // MARK: - Merge (the undo of a split)

    func testAbuts_sameLaneClipTouchingMediaContiguous_true() {
        // a is 480 ticks = 0.25 s @ 120 BPM; b's media starts exactly there.
        let a = region(start: 0, length: 480, offset: 0)
        let b = region(start: 480, length: 480, offset: 0.25)   // media-contiguous
        XCTAssertTrue(a.abuts(b, bpm: 120))
    }

    func testAbuts_gap_or_differentClip_false() {
        let a = region(start: 0, length: 480, offset: 0)
        XCTAssertFalse(a.abuts(region(start: 500, length: 480, offset: 0.25), bpm: 120), "gap ⇒ not mergeable")
        let otherClip = TimelineRegion(laneID: lane, clipID: UUID(), startTick: 480, lengthTicks: 480)
        XCTAssertFalse(a.abuts(otherClip, bpm: 120), "different clip ⇒ not mergeable (lossy)")
    }

    /// A second piece whose media was TRIMMED/NUDGED after the split must NOT rejoin —
    /// merging would silently drop the trim (the ui-state review's lossy-merge guard).
    func testAbuts_mediaDiscontinuous_false() {
        let a = region(start: 0, length: 480, offset: 0)        // ends media at 0.25 s @120
        let trimmed = region(start: 480, length: 480, offset: 0.9)  // user nudged the media
        XCTAssertFalse(a.abuts(trimmed, bpm: 120), "trimmed piece ⇒ Join must refuse (lossless)")
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
        XCTAssertTrue(first.abuts(second, bpm: 120), "a clean split is always rejoinable")
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
        // Unique lane/clip so this test counts only ITS regions — a fresh TimelineStore
        // may load a persisted document (AppGroupStore falls back to Application Support),
        // so absolute counts would flake on re-run. Delta on our own lane instead.
        let lane = UUID()
        let clip = UUID()
        func mine() -> [TimelineRegion] { store.document.regions.filter { $0.laneID == lane } }
        store.addRegion(TimelineRegion(laneID: lane, clipID: clip, startTick: 0, lengthTicks: 1920))
        store.addRegion(TimelineRegion(laneID: lane, clipID: clip, startTick: 1920, lengthTicks: 1920))
        XCTAssertEqual(mine().count, 2)

        // Razor at tick 960 (inside the first region only) → 3 of ours.
        store.splitRegions(atTick: 960, bpm: 120)
        XCTAssertEqual(mine().count, 3, "only the crossed region splits")

        // Join at 960 → back to 2 of ours.
        store.mergeRegions(atTick: 960, bpm: 120)
        XCTAssertEqual(mine().count, 2, "the two pieces at the tick rejoin")
        XCTAssertTrue(mine().contains { $0.startTick == 0 && $0.lengthTicks == 1920 },
                      "the rejoined region spans the original first bar again")
    }

    // MARK: - Overlap rule (C5 — clip game: the moved clip wins)

    /// Fresh store + one real lane + regions; returns (store, laneID).
    @MainActor
    private func overlapFixture(_ regions: [(start: Int, len: Int, offset: Double)])
        -> (TimelineStore, UUID, [TimelineRegion]) {
        let store = TimelineStore()
        store.addLane(kind: .audio, name: "ovl-\(UUID())")
        let lane = store.document.lanes.last!.id
        let clip = UUID()
        let made = regions.map { spec in
            TimelineRegion(laneID: lane, clipID: clip, startTick: spec.start,
                           lengthTicks: spec.len, contentOffsetSeconds: spec.offset)
        }
        made.forEach { store.addRegion($0) }
        return (store, lane, made)
    }

    func testOverlap_moveOntoTail_trimsNeighbourToAbut() {
        // n = 0…960; move m (480 long) to 480 → n's tail is cut: n = 0…480.
        let (store, lane, made) = overlapFixture([(0, 960, 0), (1920, 480, 0)])
        let n = made[0], m = made[1]
        store.moveRegion(id: m.id, toStartTick: 480, laneOffset: 0, bpm: 120)
        let regions = store.document.regions.filter { $0.laneID == lane }
        XCTAssertEqual(regions.count, 2)
        let nNow = regions.first { $0.id == n.id }
        XCTAssertEqual(nNow?.lengthTicks, 480, "neighbour's tail trimmed to abut the drop")
        XCTAssertEqual(regions.first { $0.id == m.id }?.startTick, 480)
        store.undo()
        XCTAssertEqual(store.document.regions.first { $0.id == n.id }?.lengthTicks, 960,
                       "move + overlap reshaping revert in ONE undo step")
    }

    func testOverlap_moveOntoHead_frontTrimsNeighbour_offsetAdvances() {
        // n = 960…1920 (offset 1.0); move m (480 long) to 720 → overlap 960…1200.
        // n must now start at 1200 with its media offset advanced by 240 ticks = 0.25 s @120.
        let (store, lane, made) = overlapFixture([(960, 960, 1.0), (2880, 480, 0)])
        let n = made[0], m = made[1]
        store.moveRegion(id: m.id, toStartTick: 720, laneOffset: 0, bpm: 120)
        let nNow = store.document.regions.first { $0.id == n.id }
        XCTAssertEqual(nNow?.startTick, 1200, "neighbour front-trimmed to the drop's end")
        XCTAssertEqual(nNow?.endTick, 1920, "neighbour's end unchanged")
        XCTAssertEqual(nNow?.contentOffsetSeconds ?? 0, 1.25, accuracy: 1e-9,
                       "media offset advances so the content stays put")
        _ = lane
    }

    func testOverlap_fullyCoveredNeighbour_isSwallowed() {
        // n = 600…840 sits fully inside the drop zone of m (480…1440) → n vanishes.
        let (store, lane, made) = overlapFixture([(600, 240, 0), (1920, 960, 0)])
        let n = made[0], m = made[1]
        store.moveRegion(id: m.id, toStartTick: 480, laneOffset: 0, bpm: 120)
        XCTAssertNil(store.document.regions.first { $0.id == n.id }, "covered neighbour removed")
        XCTAssertEqual(store.document.regions.filter { $0.laneID == lane }.count, 1)
        store.undo()
        XCTAssertNotNil(store.document.regions.first { $0.id == n.id }, "undo brings it back")
    }

    func testOverlap_containerSplitsAroundDrop() {
        // n = 0…1920; drop m (480 long) at 480 → n splits into 0…480 and 960…1920,
        // the right piece's offset advanced by 960 ticks = 1.0 s @120.
        let (store, lane, made) = overlapFixture([(0, 1920, 0), (3840, 480, 0)])
        let n = made[0], m = made[1]
        store.moveRegion(id: m.id, toStartTick: 480, laneOffset: 0, bpm: 120)
        let laneRegions = store.document.regions.filter { $0.laneID == lane }
        XCTAssertEqual(laneRegions.count, 3, "container became two pieces around the drop")
        XCTAssertTrue(laneRegions.contains { $0.id == n.id && $0.startTick == 0 && $0.lengthTicks == 480 },
                      "left piece keeps the container's identity")
        let right = laneRegions.first { $0.id != n.id && $0.id != m.id }
        XCTAssertEqual(right?.startTick, 960)
        XCTAssertEqual(right?.endTick, 1920)
        XCTAssertEqual(right?.contentOffsetSeconds ?? 0, 1.0, accuracy: 1e-9)
    }

    func testOverlap_withoutBPM_legacyKeepsOverlap() {
        let (store, lane, made) = overlapFixture([(0, 960, 0), (1920, 480, 0)])
        let n = made[0], m = made[1]
        store.moveRegion(id: m.id, toStartTick: 480, laneOffset: 0)   // no bpm → no rule
        XCTAssertEqual(store.document.regions.first { $0.id == n.id }?.lengthTicks, 960,
                       "without bpm the neighbour is untouched (legacy)")
        _ = lane
    }

    // MARK: - Edge magnetism (C4 — clip game: snapWithEdges, pure)

    func testSnapWithEdges_edgeWins_whenCloserThanGridAndInsideMagnet() {
        // Grid = beat (480). Tick 950: grid line at 960 (dist 10), edge at 955 (dist 5).
        let t = TimelineSnap.snapWithEdges(950, to: .beat, edges: [955], magnetTicks: 30)
        XCTAssertEqual(t, 955, "a closer edge inside the magnet beats the grid")
    }

    func testSnapWithEdges_gridWins_whenCloserThanEdge() {
        // Tick 958: grid at 960 (dist 2), edge at 940 (dist 18) — grid is closer.
        let t = TimelineSnap.snapWithEdges(958, to: .beat, edges: [940], magnetTicks: 30)
        XCTAssertEqual(t, 960, "the grid wins when it is the nearer pull")
    }

    func testSnapWithEdges_offGrid_edgesStillAttract_elseFree() {
        // Snap off: stepless — but an edge inside the magnet window still catches.
        XCTAssertEqual(TimelineSnap.snapWithEdges(950, to: .off, edges: [955], magnetTicks: 30),
                       955, "snap off: edges still attract (butt-join feel)")
        XCTAssertEqual(TimelineSnap.snapWithEdges(700, to: .off, edges: [955], magnetTicks: 30),
                       700, "snap off + no edge in range: fully stepless")
    }

    func testSnapWithEdges_noEdges_behavesLikePlainSnap() {
        XCTAssertEqual(TimelineSnap.snapWithEdges(950, to: .beat, edges: [], magnetTicks: 30),
                       TimelineSnap.snap(950, to: .beat))
        XCTAssertEqual(TimelineSnap.snapWithEdges(-40, to: .off, edges: [], magnetTicks: 30), 0,
                       "never negative")
    }

    // MARK: - Multi-select Combine + batch delete (C3 — clip game)

    func testCombineRegions_sameLane_spansEarliestToLatest_keepsFirstIdentity() {
        let store = TimelineStore()
        store.addLane(kind: .audio, name: "combine-\(UUID())")
        let lane = store.document.lanes.last!.id
        let clip = UUID()
        let a = TimelineRegion(laneID: lane, clipID: clip, startTick: 480, lengthTicks: 480,
                               contentOffsetSeconds: 1.0)
        let b = TimelineRegion(laneID: lane, clipID: clip, startTick: 1440, lengthTicks: 480)
        store.addRegion(a); store.addRegion(b)
        store.combineRegions(ids: [a.id, b.id])
        let mine = store.document.regions.filter { $0.laneID == lane }
        XCTAssertEqual(mine.count, 1, "two selected regions became one")
        XCTAssertEqual(mine.first?.id, a.id, "keeps the earliest region's identity")
        XCTAssertEqual(mine.first?.startTick, 480)
        XCTAssertEqual(mine.first?.lengthTicks, 1920 - 480, "spans across the gap to b's end")
        XCTAssertEqual(mine.first?.contentOffsetSeconds ?? 0, 1.0, accuracy: 1e-9,
                       "keeps the earliest region's media offset")
        store.undo()
        XCTAssertEqual(store.document.regions.filter { $0.laneID == lane }.count, 2,
                       "combine is one undo step")
    }

    func testCombineRegions_crossLane_orSingle_isNoOp() {
        let store = TimelineStore()
        store.addLane(kind: .audio, name: "cxA-\(UUID())")
        store.addLane(kind: .audio, name: "cxB-\(UUID())")
        let lanes = store.document.lanes.suffix(2)
        let a = TimelineRegion(laneID: lanes.first!.id, clipID: UUID(), startTick: 0, lengthTicks: 480)
        let b = TimelineRegion(laneID: lanes.last!.id, clipID: UUID(), startTick: 0, lengthTicks: 480)
        store.addRegion(a); store.addRegion(b)
        let before = store.document.regions.count
        store.combineRegions(ids: [a.id, b.id])   // different lanes → refuse
        store.combineRegions(ids: [a.id])          // single → refuse
        XCTAssertEqual(store.document.regions.count, before, "cross-lane/single combine is a no-op")
    }

    func testRemoveRegions_batch_isOneUndoStep() {
        let store = TimelineStore()
        store.addLane(kind: .midi, name: "batch-\(UUID())")
        let lane = store.document.lanes.last!.id
        let clip = UUID()
        let a = TimelineRegion(laneID: lane, clipID: clip, startTick: 0, lengthTicks: 480)
        let b = TimelineRegion(laneID: lane, clipID: clip, startTick: 480, lengthTicks: 480)
        store.addRegion(a); store.addRegion(b)
        store.removeRegions(ids: [a.id, b.id])
        XCTAssertTrue(store.document.regions.filter { $0.laneID == lane }.isEmpty)
        store.undo()
        XCTAssertEqual(store.document.regions.filter { $0.laneID == lane }.count, 2,
                       "batch delete reverts in ONE step")
    }

    // MARK: - Undo / Redo (C2 — clip game)

    func testUndo_revertsMove_andRedoReapplies() {
        let store = TimelineStore()
        // A REAL lane: undo's restore drops regions whose lane is gone (orphan guard),
        // so history tests must place their region on a lane the document knows.
        store.addLane(kind: .audio, name: "undoMove-\(UUID())")
        let lane = store.document.lanes.last!.id
        let clip = UUID()
        let r = TimelineRegion(laneID: lane, clipID: clip, startTick: 480, lengthTicks: 960)
        store.addRegion(r)
        store.moveRegion(id: r.id, toStartTick: 1920)
        func mine() -> TimelineRegion? { store.document.regions.first { $0.id == r.id } }
        XCTAssertEqual(mine()?.startTick, 1920)
        XCTAssertTrue(store.canUndo)

        store.undo()
        XCTAssertEqual(mine()?.startTick, 480, "undo reverts the move")
        XCTAssertTrue(store.canRedo)

        store.redo()
        XCTAssertEqual(mine()?.startTick, 1920, "redo re-applies the move")
    }

    func testUndo_revertsDelete_regionComesBack() {
        let store = TimelineStore()
        store.addLane(kind: .audio, name: "undoDel-\(UUID())")   // real lane (orphan guard)
        let lane = store.document.lanes.last!.id
        let clip = UUID()
        let r = TimelineRegion(laneID: lane, clipID: clip, startTick: 0, lengthTicks: 960)
        store.addRegion(r)
        store.removeRegion(id: r.id)
        XCTAssertNil(store.document.regions.first { $0.id == r.id })
        store.undo()
        XCTAssertNotNil(store.document.regions.first { $0.id == r.id },
                        "undo brings the deleted region back")
    }

    func testNewEdit_clearsRedo() {
        let store = TimelineStore()
        store.addLane(kind: .audio, name: "undoFork-\(UUID())")  // real lane (orphan guard)
        let lane = store.document.lanes.last!.id
        let clip = UUID()
        let r = TimelineRegion(laneID: lane, clipID: clip, startTick: 0, lengthTicks: 960)
        store.addRegion(r)
        store.moveRegion(id: r.id, toStartTick: 960)
        store.undo()
        XCTAssertTrue(store.canRedo)
        store.moveRegion(id: r.id, toStartTick: 1920)   // a fresh edit forks history
        XCTAssertFalse(store.canRedo, "a new edit clears the redo branch")
    }

    func testNoOpCommand_pushesNoUndoState() {
        let store = TimelineStore()
        let lane = UUID(); let clip = UUID()
        let r = TimelineRegion(laneID: lane, clipID: clip, startTick: 100, lengthTicks: 800)
        store.addRegion(r)
        // No-ops WHILE r exists, so each hits its intended guard (reviewer note: undoing
        // first would make the edge split no-op on unknown-id instead of the edge guard).
        store.splitRegion(id: r.id, atTick: 100, bpm: 120)   // edge split = no-op
        store.removeRegion(id: UUID())                       // unknown id = no-op
        store.undo()                                         // pops the ONE addRegion snapshot
        XCTAssertFalse(store.canUndo, "no-op commands must not create dead undo steps")
    }

    // MARK: - Drag-to-move (C1 — clip game: horizontal time + vertical lane change)

    func testMoveRegion_laneOffset_movesToSameKindLane() {
        let store = TimelineStore()
        store.addLane(kind: .audio, name: "moveA-\(UUID())")
        store.addLane(kind: .audio, name: "moveB-\(UUID())")
        let lanes = store.document.lanes.suffix(2)
        let from = lanes.first!, to = lanes.last!
        let r = TimelineRegion(laneID: from.id, clipID: UUID(), startTick: 480, lengthTicks: 960)
        store.addRegion(r)
        store.moveRegion(id: r.id, toStartTick: 1920, laneOffset: 1)
        let moved = store.document.regions.first { $0.id == r.id }!
        XCTAssertEqual(moved.startTick, 1920, "time moved")
        XCTAssertEqual(moved.laneID, to.id, "landed on the next same-kind lane")
    }

    func testMoveRegion_laneOffset_kindMismatch_keepsLaneButMovesTime() {
        let store = TimelineStore()
        store.addLane(kind: .audio, name: "kindA-\(UUID())")
        store.addLane(kind: .midi, name: "kindM-\(UUID())")
        let lanes = store.document.lanes.suffix(2)
        let from = lanes.first!
        let r = TimelineRegion(laneID: from.id, clipID: UUID(), startTick: 0, lengthTicks: 960)
        store.addRegion(r)
        store.moveRegion(id: r.id, toStartTick: 960, laneOffset: 1)
        let moved = store.document.regions.first { $0.id == r.id }!
        XCTAssertEqual(moved.startTick, 960, "time still moves")
        XCTAssertEqual(moved.laneID, from.id, "audio clip refuses a MIDI lane")
    }

    func testMoveRegion_laneOffset_outOfRange_keepsLane_andTickClampsAtZero() {
        let store = TimelineStore()
        store.addLane(kind: .video, name: "solo-\(UUID())")
        let from = store.document.lanes.last!
        let r = TimelineRegion(laneID: from.id, clipID: UUID(), startTick: 480, lengthTicks: 480)
        store.addRegion(r)
        store.moveRegion(id: r.id, toStartTick: -300, laneOffset: 99)
        let moved = store.document.regions.first { $0.id == r.id }!
        XCTAssertEqual(moved.startTick, 0, "negative target clamps to the song start")
        XCTAssertEqual(moved.laneID, from.id, "no lane beyond the last — stays put")
    }

    func testRemoveRegion_deletesOnlyThatRegion() {
        let store = TimelineStore()
        let lane = UUID(); let clip = UUID()
        func mine() -> [TimelineRegion] { store.document.regions.filter { $0.laneID == lane } }
        let keep = TimelineRegion(laneID: lane, clipID: clip, startTick: 0, lengthTicks: 1920)
        let drop = TimelineRegion(laneID: lane, clipID: clip, startTick: 1920, lengthTicks: 1920)
        store.addRegion(keep)
        store.addRegion(drop)
        XCTAssertEqual(mine().count, 2)

        store.removeRegion(id: drop.id)
        XCTAssertEqual(mine().count, 1, "only the targeted region is deleted")
        XCTAssertTrue(mine().contains { $0.id == keep.id }, "the other region survives")
        XCTAssertFalse(mine().contains { $0.id == drop.id }, "the deleted region is gone")
    }

    func testDuplicated_freshIdAtEndTick_sameContent() {
        // Self-contained: the `region(...)` helper is private to the sibling class
        // TimelineRegionSplitMergeTests and not visible here — construct directly.
        let lane = UUID(); let clip = UUID()
        let r = TimelineRegion(laneID: lane, clipID: clip, startTick: 240,
                               lengthTicks: 960, contentOffsetSeconds: 1.25)
        let dup = r.duplicated()
        XCTAssertNotEqual(dup.id, r.id, "the duplicate gets a fresh identity")
        XCTAssertEqual(dup.startTick, r.endTick, "lands right after the original by default")
        XCTAssertEqual(dup.lengthTicks, r.lengthTicks)
        XCTAssertEqual(dup.laneID, r.laneID)
        XCTAssertEqual(dup.clipID, r.clipID, "shares the same clip — no new slot")
        XCTAssertEqual(dup.contentOffsetSeconds, r.contentOffsetSeconds, accuracy: 1e-9)
    }

    func testDuplicateRegion_appendsCopyAfterOriginalOnSameLane() {
        let store = TimelineStore()
        let lane = UUID(); let clip = UUID()
        func mine() -> [TimelineRegion] { store.document.regions.filter { $0.laneID == lane } }
        let r = TimelineRegion(laneID: lane, clipID: clip, startTick: 0, lengthTicks: 1920)
        store.addRegion(r)

        store.duplicateRegion(id: r.id)
        XCTAssertEqual(mine().count, 2, "a duplicate is added")
        let dup = try? XCTUnwrap(mine().first { $0.id != r.id })
        XCTAssertEqual(dup?.startTick, 1920, "the copy starts at the original's end")
        XCTAssertEqual(dup?.clipID, clip, "shares the same clip")
    }

    func testMoveRegion_setsStartTick_clampedAtZero() {
        let store = TimelineStore()
        let lane = UUID(); let clip = UUID()
        func mine() -> [TimelineRegion] { store.document.regions.filter { $0.laneID == lane } }
        let r = TimelineRegion(laneID: lane, clipID: clip, startTick: 0, lengthTicks: 1920)
        store.addRegion(r)

        store.moveRegion(id: r.id, toStartTick: 960)
        XCTAssertEqual(mine().first { $0.id == r.id }?.startTick, 960, "start moves to the target tick")

        store.moveRegion(id: r.id, toStartTick: -500)
        XCTAssertEqual(mine().first { $0.id == r.id }?.startTick, 0, "a negative target clamps to 0")
    }

    // MARK: - Per-region Join with next (founder 2026-07-15: from the clip's menu)

    func testMergeRegionWithNext_rejoinsTheSplitPiece_onlyThisRegion() {
        let store = TimelineStore()
        let lane = UUID(); let clip = UUID()
        func mine() -> [TimelineRegion] { store.document.regions.filter { $0.laneID == lane } }
        let r = TimelineRegion(laneID: lane, clipID: clip, startTick: 0, lengthTicks: 1920)
        store.addRegion(r)
        // Split it into two abutting pieces at tick 960.
        store.splitRegion(id: r.id, atTick: 960, bpm: 120)
        XCTAssertEqual(mine().count, 2, "cut into two pieces")
        XCTAssertTrue(store.canMergeRegionWithNext(id: r.id, bpm: 120), "the first piece can rejoin")

        // Join from the FIRST piece's own menu → one region spanning the bar again.
        store.mergeRegionWithNext(id: r.id, bpm: 120)
        XCTAssertEqual(mine().count, 1, "the two pieces rejoin into one")
        XCTAssertTrue(mine().contains { $0.id == r.id && $0.startTick == 0 && $0.lengthTicks == 1920 },
                      "the rejoined region keeps the first piece's identity + spans the whole bar")
    }

    func testMergeRegionWithNext_noSuccessor_isNoOp() {
        let store = TimelineStore()
        let lane = UUID(); let clip = UUID()
        func mine() -> [TimelineRegion] { store.document.regions.filter { $0.laneID == lane } }
        let solo = TimelineRegion(laneID: lane, clipID: clip, startTick: 0, lengthTicks: 1920)
        store.addRegion(solo)
        XCTAssertFalse(store.canMergeRegionWithNext(id: solo.id, bpm: 120), "nothing follows it")
        store.mergeRegionWithNext(id: solo.id, bpm: 120)
        XCTAssertEqual(mine().count, 1, "no successor ⇒ Join is a no-op")
    }

    func testMergeRegionWithNext_trimmedSuccessor_refuses() {
        let store = TimelineStore()
        let lane = UUID(); let clip = UUID()
        func mine() -> [TimelineRegion] { store.document.regions.filter { $0.laneID == lane } }
        let a = TimelineRegion(laneID: lane, clipID: clip, startTick: 0, lengthTicks: 480, contentOffsetSeconds: 0)
        // Abutting on the grid but media-DISCONTINUOUS (nudged) → lossless Join must refuse.
        let nudged = TimelineRegion(laneID: lane, clipID: clip, startTick: 480, lengthTicks: 480, contentOffsetSeconds: 0.9)
        store.addRegion(a)
        store.addRegion(nudged)
        XCTAssertFalse(store.canMergeRegionWithNext(id: a.id, bpm: 120), "media discontinuity blocks Join")
        store.mergeRegionWithNext(id: a.id, bpm: 120)
        XCTAssertEqual(mine().count, 2, "the trimmed piece is NOT swallowed")
    }

    func testSplitRegions_atEdge_isNoOp() {
        let store = TimelineStore()
        let lane = UUID(); let clip = UUID()
        func mineCount() -> Int { store.document.regions.filter { $0.laneID == lane }.count }
        store.addRegion(TimelineRegion(laneID: lane, clipID: clip, startTick: 0, lengthTicks: 1920))
        let before = mineCount()
        store.splitRegions(atTick: 0, bpm: 120)      // start edge
        store.splitRegions(atTick: 5000, bpm: 120)   // past the region
        XCTAssertEqual(mineCount(), before, "edge/outside razor changes nothing")
    }
}
