// UserMidiRegionStoreTests.swift
// H12 (founder v281 "Wo bleibt Midi Clip? … keine Drums sondern irgendwelche
// Töne"): locks `ensureUserMidiRegion` — the USER-clip twin of
// `ensureComposerRegion`. Opening a secondary MIDI track's door must land on a
// real, user-owned MIDI clip + loop-window region (created once), so the region
// player's kind routing (slotKindSink → sub/sampler; the kit arm is gone since the
// 2026-07-26 drums removal) has something to play. Laws:
// creates once, idempotent via the existing region, `composerOwned == false`
// (generate/evolve may NEVER rewrite the user's clip), honest nil on a full
// grid, MIDI/non-bio lanes only.
//
// Pattern notes (from LaneCompositionStoreTests): both stores persist to the
// real App-Group fallback, so every test uses uniquely named lanes, restores
// the ClipStore slots it touched, and removes its lanes.

import XCTest
@testable import Echoelmusic

@MainActor
final class UserMidiRegionStoreTests: XCTestCase {

    // MARK: - Fixtures

    /// Add a uniquely named MIDI lane; delta-scoped like the neighbour suites so
    /// a persisted document from earlier runs can never flake the assertions.
    private func addMidiLane(_ store: TimelineStore) -> UUID {
        store.addLane(kind: .midi, name: "h12-\(UUID())")
        return store.document.lanes.last!.id
    }

    /// The founder's exact flow: an EchoelDrums instrument track (uniquely named).
    private func addDrumsLane(_ store: TimelineStore) -> UUID {
        store.addInstrumentTrack(.drums, name: "h12-drums-\(UUID())")
        return store.document.lanes.last!.id
    }

    /// Remove this test's regions + lane so the persisted document stays tidy.
    private func removeLane(_ store: TimelineStore, _ laneID: UUID) {
        let ids = Set(store.document.regions(in: laneID).map(\.id))
        if !ids.isEmpty { store.removeRegions(ids: ids) }
        store.removeLaneIfEmpty(id: laneID)
    }

    /// Restore the shared ClipStore to a snapshot (slot-exact), so this suite
    /// never leaks grid state into other suites.
    private func restoreSlots(_ clips: ClipStore, _ before: [Clip?]) {
        for i in 0..<ClipStore.slotCount {
            if let c = before[i] { clips.setClip(at: i, c) } else { clips.clear(at: i) }
        }
    }

    // MARK: - Creation

    func testEnsureUserMidiRegion_createsUserClipRegion_onDrumsInstrumentTrack() {
        let store = TimelineStore()
        let clips = ClipStore()
        let before = clips.slots
        defer { restoreSlots(clips, before) }
        if clips.firstEmptySlotIndex == nil { clips.clear(at: 0) }   // need one free slot
        let laneID = addDrumsLane(store)
        defer { removeLane(store, laneID) }

        let region = store.ensureUserMidiRegion(for: laneID, clipStore: clips, loopBars: 8)
        XCTAssertNotNil(region, "an empty drums track gets its own MIDI clip + region")
        XCTAssertEqual(region?.laneID, laneID)
        XCTAssertEqual(region?.startTick, 0)
        XCTAssertEqual(region?.lengthTicks, 8 * TimelineTime.ticksPerBar,
                       "region spans exactly the active loop window")
        XCTAssertEqual(store.document.regions(in: laneID).count, 1)

        let clip = region.flatMap { clips.clip(id: $0.clipID) }
        XCTAssertEqual(clip?.kind, .midi)
        XCTAssertEqual(clip?.composerOwned, false,
                       "this is the USER'S clip — generate/evolve may never rewrite it")
        XCTAssertEqual(clip?.name.hasPrefix("MIDI · "), true)
        XCTAssertEqual(clip?.melody?.notes.isEmpty, true, "starts empty — the user draws")
    }

    // MARK: - Idempotence

    func testEnsureUserMidiRegion_idempotent_returnsSameRegion_createsNothingNew() {
        let store = TimelineStore()
        let clips = ClipStore()
        let before = clips.slots
        defer { restoreSlots(clips, before) }
        if clips.firstEmptySlotIndex == nil { clips.clear(at: 0) }
        let laneID = addMidiLane(store)
        defer { removeLane(store, laneID) }

        let first = store.ensureUserMidiRegion(for: laneID, clipStore: clips, loopBars: 4)
        let filledAfterFirst = clips.filledClips.count
        let second = store.ensureUserMidiRegion(for: laneID, clipStore: clips, loopBars: 4)
        XCTAssertEqual(first?.id, second?.id, "second open reuses the SAME region")
        XCTAssertEqual(store.document.regions(in: laneID).count, 1)
        XCTAssertEqual(clips.filledClips.count, filledAfterFirst, "no duplicate clip")
    }

    /// A lane that ALREADY has a MIDI region (e.g. the user placed a clip, or a
    /// prior open created one) returns that region — first by startTick.
    func testEnsureUserMidiRegion_existingRegion_isReturned_notDuplicated() {
        let store = TimelineStore()
        let clips = ClipStore()
        let before = clips.slots
        defer { restoreSlots(clips, before) }
        clips.clear(at: 0)
        let laneID = addMidiLane(store)
        defer { removeLane(store, laneID) }

        let user = Clip(name: "User take",
                        melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0)]))
        guard let slot = clips.firstEmptySlotIndex else { return XCTFail("no free slot") }
        clips.setClip(at: slot, user)
        store.addRegion(TimelineRegion(laneID: laneID, clipID: user.id,
                                       startTick: 0, lengthTicks: 1920))

        let filledBefore = clips.filledClips.count
        let region = store.ensureUserMidiRegion(for: laneID, clipStore: clips, loopBars: 4)
        XCTAssertEqual(region?.clipID, user.id, "the existing MIDI region is the editor target")
        XCTAssertEqual(store.document.regions(in: laneID).count, 1, "nothing created")
        XCTAssertEqual(clips.filledClips.count, filledBefore)
        XCTAssertEqual(clips.clip(id: user.id)?.melody?.notes.count, 1,
                       "user clip content untouched")
    }

    // MARK: - Honest refusals

    func testEnsureUserMidiRegion_fullGrid_returnsNil_withoutDisplacingUserClips() {
        let store = TimelineStore()
        let clips = ClipStore()
        let before = clips.slots
        defer { restoreSlots(clips, before) }
        // Fill EVERY free slot with a user clip.
        while let free = clips.firstEmptySlotIndex {
            clips.setClip(at: free, Clip(name: "User \(free)",
                                         melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0)])))
        }
        let fullSlots = clips.slots
        let laneID = addMidiLane(store)
        defer { removeLane(store, laneID) }

        XCTAssertNil(store.ensureUserMidiRegion(for: laneID, clipStore: clips, loopBars: 4),
                     "full grid → honest nil, not displacement")
        XCTAssertTrue(store.document.regions(in: laneID).isEmpty, "no region without a clip")
        XCTAssertEqual(clips.slots, fullSlots, "every user clip untouched")
    }

    func testEnsureUserMidiRegion_refusesNonMidiAndUnknownLane() {
        let store = TimelineStore()
        let clips = ClipStore()
        let before = clips.slots
        defer { restoreSlots(clips, before) }
        store.addLane(kind: .audio, name: "h12-audio-\(UUID())")
        let audioLane = store.document.lanes.last!.id
        defer { removeLane(store, audioLane) }

        XCTAssertNil(store.ensureUserMidiRegion(for: audioLane, clipStore: clips, loopBars: 4))
        XCTAssertTrue(store.document.regions(in: audioLane).isEmpty)
        XCTAssertNil(store.ensureUserMidiRegion(for: UUID(), clipStore: clips, loopBars: 4),
                     "unknown lane → nil, no side effects")
    }

    /// The region add is ONE region-history step (via addRegion); undo removes
    /// the region while the clip keeps its slot — same behaviour as
    /// ensureComposerRegion and the audio/video import paths.
    func testEnsureUserMidiRegion_undoRevertsRegion_clipSlotRemains() {
        let store = TimelineStore()
        let clips = ClipStore()
        let before = clips.slots
        defer { restoreSlots(clips, before) }
        if clips.firstEmptySlotIndex == nil { clips.clear(at: 0) }
        let laneID = addMidiLane(store)
        defer { removeLane(store, laneID) }

        guard let region = store.ensureUserMidiRegion(for: laneID, clipStore: clips,
                                                      loopBars: 2) else {
            return XCTFail("region must exist")
        }
        store.undo()
        XCTAssertTrue(store.document.regions(in: laneID).isEmpty,
                      "ONE undo step reverts the region add")
        XCTAssertNotNil(clips.clip(id: region.clipID),
                        "clip slot survives undo (outside the region history)")
    }
}
