// LaneCompositionStoreTests.swift
// Slice A2 (founder 2026-07-17 "Genre, Sound, Mix, FX, Mood, Synth kommt alles
// in ein Instrument"): locks the per-track composition SETTERS (genre / mood /
// variation persist on the lane, outside the region undo history) and the
// EXPLICIT composer-clip act `ensureComposerRegion` — creates the composer-owned
// "Composed" clip + loop-window region once, idempotently, refuses honestly on a
// full clip grid, and never displaces a user clip (the never-clobber law).
//
// Pattern notes (from TimelineRegionSplitMergeTests / MelodyBarEditTests): both
// stores persist to the real App-Group fallback, so every test uses uniquely
// named lanes, restores the ClipStore slots it touched, and removes its lanes.

import XCTest
@testable import Echoelmusic

@MainActor
final class LaneCompositionStoreTests: XCTestCase {

    // MARK: - Fixtures

    /// Add a uniquely named MIDI lane; delta-scoped like the neighbour suites so
    /// a persisted document from earlier runs can never flake the assertions.
    private func addMidiLane(_ store: TimelineStore) -> UUID {
        store.addLane(kind: .midi, name: "a2-\(UUID())")
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

    // MARK: - Setters (persist; outside the region undo history)

    func testCompositionSetters_persistAcrossReload_andClearToNil() {
        let store = TimelineStore()
        let laneID = addMidiLane(store)
        defer { removeLane(store, laneID) }

        let mood = MoodPreset.factory[0].profile
        store.setLaneGenreOverride(laneID, genre: .trap)
        store.setLaneMood(laneID, mood: mood)
        store.setLaneVariationSeed(laneID, seed: 0xDEAD_BEEF)

        // A fresh store instance loads the persisted document. persist()'s disk
        // write is debounced (task #56 C6) — flush it so the reload sees this
        // edit rather than racing a still-pending write.
        store.flushPendingSave()
        let reloaded = TimelineStore()
        let lane = reloaded.document.lanes.first { $0.id == laneID }
        XCTAssertEqual(lane?.genreOverride, .trap)
        XCTAssertEqual(lane?.mood, mood)
        XCTAssertEqual(lane?.variationSeed, 0xDEAD_BEEF)

        // "Song" resets (nil) clear each override independently.
        store.setLaneGenreOverride(laneID, genre: nil)
        store.setLaneMood(laneID, mood: nil)
        store.setLaneVariationSeed(laneID, seed: nil)
        let cleared = store.document.lanes.first { $0.id == laneID }
        XCTAssertNil(cleared?.genreOverride)
        XCTAssertNil(cleared?.mood)
        XCTAssertNil(cleared?.variationSeed)
    }

    func testCompositionSetters_unknownLane_noOp() {
        let store = TimelineStore()
        let before = store.document
        store.setLaneGenreOverride(UUID(), genre: .jazz)
        store.setLaneMood(UUID(), mood: MoodProfile())
        store.setLaneVariationSeed(UUID(), seed: 7)
        XCTAssertEqual(store.document, before)
    }

    /// The undo history is REGIONS-only by design — undoing a region edit must
    /// never revert a composition choice made after it (same law as fader moves).
    func testCompositionSetters_surviveRegionUndo() {
        let store = TimelineStore()
        let laneID = addMidiLane(store)
        defer { removeLane(store, laneID) }

        store.addRegion(TimelineRegion(laneID: laneID, clipID: UUID(),
                                       startTick: 0, lengthTicks: 480))
        store.setLaneGenreOverride(laneID, genre: .jazz)
        store.undo()   // reverts the region add — never the lane's composition
        XCTAssertTrue(store.document.regions(in: laneID).isEmpty)
        XCTAssertEqual(store.document.lanes.first { $0.id == laneID }?.genreOverride, .jazz)
    }

    // MARK: - ensureComposerRegion (the explicit act that makes Slice A audible)

    func testEnsureComposerRegion_createsOwnedClipRegion_andIsIdempotent() {
        let store = TimelineStore()
        let clips = ClipStore()
        let before = clips.slots
        defer { restoreSlots(clips, before) }
        if clips.firstEmptySlotIndex == nil { clips.clear(at: 0) }   // need one free slot
        let laneID = addMidiLane(store)
        defer { removeLane(store, laneID) }

        XCTAssertTrue(store.ensureComposerRegion(for: laneID, clipStore: clips, loopBars: 8))
        let regions = store.document.regions(in: laneID)
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions.first?.startTick, 0)
        XCTAssertEqual(regions.first?.lengthTicks, 8 * TimelineTime.ticksPerBar,
                       "region spans exactly the active loop window")
        let clip = regions.first.flatMap { clips.clip(id: $0.clipID) }
        XCTAssertEqual(clip?.kind, .midi)
        XCTAssertEqual(clip?.composerOwned, true,
                       "only a composer-owned clip may be rewritten by generate/evolve")
        XCTAssertEqual(clip?.name.hasPrefix("Composed · "), true)

        // Idempotent: a second override on the same lane reuses clip + region.
        let filledBefore = clips.filledClips.count
        XCTAssertTrue(store.ensureComposerRegion(for: laneID, clipStore: clips, loopBars: 8))
        XCTAssertEqual(store.document.regions(in: laneID).count, 1)
        XCTAssertEqual(clips.filledClips.count, filledBefore)
    }

    /// A USER clip region in the window must NOT satisfy the composer's need —
    /// `updateComposerMelody` refuses user clips, so without an owned clip the
    /// override would stay silent. Ensure creates the owned clip alongside.
    func testEnsureComposerRegion_userClipRegionDoesNotCount() {
        let store = TimelineStore()
        let clips = ClipStore()
        let before = clips.slots
        defer { restoreSlots(clips, before) }
        // Need two free slots: the user clip + the composer clip.
        clips.clear(at: 0); clips.clear(at: 1)
        let laneID = addMidiLane(store)
        defer { removeLane(store, laneID) }

        let user = Clip(name: "User take",
                        melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0)]))
        guard let slot = clips.firstEmptySlotIndex else { return XCTFail("no free slot") }
        clips.setClip(at: slot, user)
        store.addRegion(TimelineRegion(laneID: laneID, clipID: user.id,
                                       startTick: 0, lengthTicks: 1920))

        XCTAssertTrue(store.ensureComposerRegion(for: laneID, clipStore: clips, loopBars: 4))
        let regions = store.document.regions(in: laneID)
        XCTAssertEqual(regions.count, 2, "user region stays + owned region added")
        XCTAssertEqual(regions.filter { clips.clip(id: $0.clipID)?.composerOwned == true }.count, 1)
        XCTAssertEqual(clips.clip(id: user.id)?.melody?.notes.count, 1,
                       "user clip content untouched")
    }

    func testEnsureComposerRegion_fullGrid_refusesWithoutDisplacingUserClips() {
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

        XCTAssertFalse(store.ensureComposerRegion(for: laneID, clipStore: clips, loopBars: 4),
                       "full grid → honest refusal, not displacement")
        XCTAssertTrue(store.document.regions(in: laneID).isEmpty, "no region without a clip")
        XCTAssertEqual(clips.slots, fullSlots, "every user clip untouched")
    }

    func testEnsureComposerRegion_refusesNonMidiLane() {
        let store = TimelineStore()
        let clips = ClipStore()
        let before = clips.slots
        defer { restoreSlots(clips, before) }
        store.addLane(kind: .audio, name: "a2-audio-\(UUID())")
        let audioLane = store.document.lanes.last!.id
        defer { removeLane(store, audioLane) }

        XCTAssertFalse(store.ensureComposerRegion(for: audioLane, clipStore: clips, loopBars: 4))
        XCTAssertTrue(store.document.regions(in: audioLane).isEmpty)
    }

    /// The region add is ONE region-history step (via addRegion); undo removes
    /// the region while the clip keeps its slot — same behaviour as the audio /
    /// video import paths (clip slots sit outside the region history).
    func testEnsureComposerRegion_undoRevertsRegion_clipSlotRemains() {
        let store = TimelineStore()
        let clips = ClipStore()
        let before = clips.slots
        defer { restoreSlots(clips, before) }
        if clips.firstEmptySlotIndex == nil { clips.clear(at: 0) }
        let laneID = addMidiLane(store)
        defer { removeLane(store, laneID) }

        XCTAssertTrue(store.ensureComposerRegion(for: laneID, clipStore: clips, loopBars: 2))
        guard let region = store.document.regions(in: laneID).first else {
            return XCTFail("region must exist")
        }
        store.undo()
        XCTAssertTrue(store.document.regions(in: laneID).isEmpty,
                      "ONE undo step reverts the region add")
        XCTAssertNotNil(clips.clip(id: region.clipID),
                        "clip slot survives undo (outside the region history)")
    }
}
