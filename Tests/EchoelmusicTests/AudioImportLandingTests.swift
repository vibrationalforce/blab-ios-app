// AudioImportLandingTests.swift
// DAW#3 — "Audio & MIDI richtig integrieren". The audio-import path lands a
// picked file onto a lane through PURE seams: a free clip slot + an append tick
// + the AudioClipFactory clip/region. Only the file copy is impure (device).
// These tests pin the placement math so import can't silently overwrite a clip
// or overlap existing regions.

import XCTest
@testable import Echoelmusic

final class AudioImportLandingTests: XCTestCase {

    // MARK: - TimelineDocument.nextStartTick (append after the lane's content)

    func testNextStartTick_emptyLane_isZero() {
        let doc = TimelineDocument()
        XCTAssertEqual(doc.nextStartTick(inLane: UUID()), 0)
    }

    func testNextStartTick_appendsAfterLastRegionOnThatLane() {
        let lane = UUID(); let clip = UUID()
        let doc = TimelineDocument(regions: [
            TimelineRegion(laneID: lane, clipID: clip, startTick: 0, lengthTicks: 1920),
            TimelineRegion(laneID: lane, clipID: clip, startTick: 1920, lengthTicks: 960),
        ])
        XCTAssertEqual(doc.nextStartTick(inLane: lane), 2880, "end of the last region")
    }

    func testNextStartTick_ignoresOtherLanes() {
        let lane = UUID(); let other = UUID(); let clip = UUID()
        let doc = TimelineDocument(regions: [
            TimelineRegion(laneID: other, clipID: clip, startTick: 0, lengthTicks: 9600),
            TimelineRegion(laneID: lane,  clipID: clip, startTick: 0, lengthTicks: 1920),
        ])
        XCTAssertEqual(doc.nextStartTick(inLane: lane), 1920, "only this lane's regions count")
    }

    // MARK: - AudioClipFactory landing geometry

    func testLanding_placesRegionAtAppendTick_withClipID() {
        let lane = UUID(); let clipID = UUID()
        let existing = TimelineDocument(regions: [
            TimelineRegion(laneID: lane, clipID: UUID(), startTick: 0, lengthTicks: 1920),
        ])
        let startTick = existing.nextStartTick(inLane: lane)
        // 2 s at 120 BPM ≈ one bar → 1920 ticks, placed at the append tick.
        let region = AudioClipFactory.region(forDurationSeconds: 2.0, bpm: 120,
                                             laneID: lane, clipID: clipID,
                                             startTick: startTick, nativeBPM: 120)
        XCTAssertEqual(region.startTick, 1920)
        XCTAssertEqual(region.clipID, clipID)
        XCTAssertEqual(region.laneID, lane)
        XCTAssertGreaterThan(region.lengthTicks, 0, "an imported clip is never zero-length")
    }

    func testLanding_carriesTrimOffsetIntoContentOffset() {
        let region = AudioClipFactory.region(forDurationSeconds: 1.0, bpm: 120,
                                             laneID: UUID(), clipID: UUID(),
                                             startTick: 0, nativeBPM: 120,
                                             contentOffsetSeconds: 0.75)
        XCTAssertEqual(region.contentOffsetSeconds, 0.75, accuracy: 1e-9,
                       "the trim in-point rides along as the region's media start")
    }
}

@MainActor
final class ClipStoreFreeSlotTests: XCTestCase {

    // ClipStore.setClip/clear PERSIST to AppGroupStore, which on Linux CI falls
    // back to a shared Application Support file. Clear every slot before AND after
    // each test so the grid is hermetic — no cross-test / cross-run pollution.
    private func emptied() -> ClipStore {
        let store = ClipStore()
        for i in store.slots.indices { store.clear(at: i) }
        return store
    }

    override func tearDown() {
        let store = ClipStore()
        for i in store.slots.indices { store.clear(at: i) }
        super.tearDown()
    }

    func testFirstEmptySlotIndex_emptyStore_isZero() {
        let store = emptied()
        XCTAssertEqual(store.firstEmptySlotIndex, 0, "an empty grid's first free slot is 0")
    }

    func testFirstEmptySlotIndex_findsGap_thenNilWhenFull() {
        let store = emptied()
        // Fill every slot → no free index.
        for i in store.slots.indices {
            store.setClip(at: i, Clip(name: "c\(i)", kind: .audio, mediaRef: "/x\(i).wav"))
        }
        XCTAssertNil(store.firstEmptySlotIndex, "a full grid has no free slot")

        // Clear one → that index becomes the first free one.
        store.clear(at: 3)
        XCTAssertEqual(store.firstEmptySlotIndex, 3, "the cleared slot is the first free one")
    }
}
