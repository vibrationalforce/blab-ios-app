// PrimaryRollClipStoreTests.swift
// Founder v287/v288 "Es wird kein midi Clip erzeugt" (+ v281 "Wo bleibt Midi
// Clip?", "Pianoroll macht Sinn, wenn man einen MIDI Clip generiert"): locks the
// fix that makes the generated take a VISIBLE, editable MIDI clip on the PRIMARY
// roll lane's timeline. The view's `generate()` mirrors the finished loop into a
// composer-OWNED clip+region via `ensureComposerRegion` + `updateComposerMelody`;
// this suite pins the two testable seams that carry it:
//
//   1. `MelodyClip.flatten(loopBars:)` — per-bar (bar-relative) loop notes → one
//      clip-absolute note array, the exact inverse of `RegionNoteWindow.barSlices`
//      (the region player's windowing), so the tile plays back the same bars. It
//      lives on the Foundation-only MelodyClip (not the SwiftUI-gated studio view)
//      precisely so this pure test compiles + runs on Linux CI.
//   2. The generate→evolve STORE contract on one lane: create ONCE, re-feed
//      overwrites (no duplicate region/clip), ownership guards a user clip, a full
//      grid refuses honestly (no crash, no region — the live sound is unaffected).
//
// Pattern notes (from LaneCompositionStoreTests / UserMidiRegionStoreTests): both
// stores persist to the real App-Group fallback, so every test uses uniquely named
// lanes, restores the ClipStore slots it touched, and removes its lanes.

import XCTest
@testable import Echoelmusic

@MainActor
final class PrimaryRollClipStoreTests: XCTestCase {

    // MARK: - Fixtures

    private func addMidiLane(_ store: TimelineStore) -> UUID {
        store.addLane(kind: .midi, name: "primaryroll-\(UUID())")
        return store.document.lanes.last!.id
    }

    private func removeLane(_ store: TimelineStore, _ laneID: UUID) {
        let ids = Set(store.document.regions(in: laneID).map(\.id))
        if !ids.isEmpty { store.removeRegions(ids: ids) }
        store.removeLaneIfEmpty(id: laneID)
    }

    private func restoreSlots(_ clips: ClipStore, _ before: [Clip?]) {
        for i in 0..<ClipStore.slotCount {
            if let c = before[i] { clips.setClip(at: i, c) } else { clips.clear(at: i) }
        }
    }

    // MARK: - flattenLoop (pure — the inverse of RegionNoteWindow.barSlices)

    func testFlattenLoop_shiftsEachBarByTicksPerBar_roundTripsBarSlices() {
        // Two bars of step-aligned notes (safe from the last-half-step clamp).
        let bars: [[Note]] = [
            [Note(pitch: 60, startStep: 0), Note(pitch: 64, startStep: 4)],
            [Note(pitch: 67, startStep: 8)]
        ]
        let flat = MelodyClip.flatten(loopBars: bars)

        // Bar 1's note is shifted by one bar; bar 0's are untouched.
        XCTAssertEqual(flat.count, 3)
        XCTAssertEqual(flat.first(where: { $0.pitch == 60 })?.startTick, 0)
        XCTAssertEqual(flat.first(where: { $0.pitch == 64 })?.startTick, 4 * Note.ticksPerStep)
        XCTAssertEqual(flat.first(where: { $0.pitch == 67 })?.startTick,
                       TimelineTime.ticksPerBar + 8 * Note.ticksPerStep,
                       "bar 1's note is offset by exactly one bar")

        // The region player's exact windowing (offset 0, full loop window) must
        // reproduce the original bars — pitch + bar-relative tick.
        let windowed = RegionNoteWindow.windowed(notes: flat, offsetTicks: 0,
                                                 lengthTicks: 2 * TimelineTime.ticksPerBar)
        let slices = RegionNoteWindow.barSlices(notes: windowed,
                                                regionLengthTicks: 2 * TimelineTime.ticksPerBar)
        XCTAssertEqual(slices.count, 2)
        XCTAssertEqual(Set(slices[0].map(\.pitch)), [60, 64])
        XCTAssertEqual(Set(slices[1].map(\.pitch)), [67])
        XCTAssertEqual(slices[0].first(where: { $0.pitch == 64 })?.startTick,
                       4 * Note.ticksPerStep, "bar-relative tick survives the round trip")
        XCTAssertEqual(slices[1].first?.startTick, 8 * Note.ticksPerStep)
    }

    func testFlattenLoop_preservesNoteFields() {
        let note = Note(pitch: 55, startTick: 120, lengthTicks: 240, velocity: 0.42, role: .bass)
        let flat = MelodyClip.flatten(loopBars: [[], [note]])   // bar 1
        XCTAssertEqual(flat.count, 1)
        let out = flat[0]
        XCTAssertEqual(out.pitch, 55)
        XCTAssertEqual(out.startTick, TimelineTime.ticksPerBar + 120, "shifted one bar")
        XCTAssertEqual(out.lengthTicks, 240, "length untouched")
        XCTAssertEqual(out.velocity, 0.42, accuracy: 0.0001, "velocity untouched")
        XCTAssertEqual(out.role, .bass, "role untouched")
    }

    func testFlattenLoop_emptyAndSingleBar() {
        XCTAssertTrue(MelodyClip.flatten(loopBars: []).isEmpty)
        XCTAssertTrue(MelodyClip.flatten(loopBars: [[]]).isEmpty)
        // A single bar is the classic (barCount 1) case: notes pass through unshifted.
        let one = MelodyClip.flatten(loopBars: [[Note(pitch: 60, startStep: 2)]])
        XCTAssertEqual(one.first?.startTick, 2 * Note.ticksPerStep)
    }

    // MARK: - Generate → Evolve store contract (what syncPrimaryRollClip drives)

    /// The exact sequence `generate()` runs on the primary lane: create the
    /// composer clip+region ONCE, then feed it on generate AND on every evolve.
    /// Result: exactly one region, one composer clip, whose notes are the LATEST
    /// take — no duplicate region and no duplicate clip.
    func testGenerateThenEvolve_oneComposerRegion_notesOverwritten_noDuplicate() {
        let store = TimelineStore()
        let clips = ClipStore()
        let before = clips.slots
        defer { restoreSlots(clips, before) }
        if clips.firstEmptySlotIndex == nil { clips.clear(at: 0) }
        let laneID = addMidiLane(store)
        defer { removeLane(store, laneID) }

        // Generate #1 (user, createIfNeeded): the clip+region is born and fed.
        XCTAssertTrue(store.ensureComposerRegion(for: laneID, clipStore: clips, loopBars: 8))
        let genNotes = MelodyClip.flatten(loopBars: [[Note(pitch: 60, startStep: 0)]])
        for r in store.document.regions(in: laneID) where r.startTick < 8 * TimelineTime.ticksPerBar {
            _ = clips.updateComposerMelody(id: r.clipID, notes: genNotes)
        }
        let filledAfterGenerate = clips.filledClips.count
        let regionAfterGenerate = store.document.regions(in: laneID)
        XCTAssertEqual(regionAfterGenerate.count, 1, "one composer region for the take")
        let clipID = regionAfterGenerate.first!.clipID
        XCTAssertEqual(clips.clip(id: clipID)?.composerOwned, true)
        XCTAssertEqual(clips.clip(id: clipID)?.melody?.notes.map(\.pitch), [60])

        // Evolve (background re-seed, createIfNeeded == false): ensure again is a
        // no-op idempotent, and the feed OVERWRITES the same clip's notes.
        XCTAssertTrue(store.ensureComposerRegion(for: laneID, clipStore: clips, loopBars: 8),
                      "second ensure is idempotent — no new region")
        let evolveNotes = MelodyClip.flatten(loopBars: [[Note(pitch: 67, startStep: 4)]])
        for r in store.document.regions(in: laneID) where r.startTick < 8 * TimelineTime.ticksPerBar {
            _ = clips.updateComposerMelody(id: r.clipID, notes: evolveNotes)
        }
        XCTAssertEqual(store.document.regions(in: laneID).count, 1, "still ONE region")
        XCTAssertEqual(clips.filledClips.count, filledAfterGenerate, "no duplicate clip")
        XCTAssertEqual(clips.clip(id: clipID)?.melody?.notes.map(\.pitch), [67],
                       "evolve rewrote the take in place")
    }

    /// The feed uses `updateComposerMelody`, which refuses non-composer clips: a
    /// user clip that happens to sit on the primary lane is NEVER rewritten.
    func testFeed_leavesUserClipOnLaneUntouched() {
        let store = TimelineStore()
        let clips = ClipStore()
        let before = clips.slots
        defer { restoreSlots(clips, before) }
        clips.clear(at: 0)
        let laneID = addMidiLane(store)
        defer { removeLane(store, laneID) }

        let user = Clip(name: "User take",
                        melody: MelodyClip(notes: [Note(pitch: 48, startStep: 0)]))
        guard let slot = clips.firstEmptySlotIndex else { return XCTFail("no free slot") }
        clips.setClip(at: slot, user)
        store.addRegion(TimelineRegion(laneID: laneID, clipID: user.id,
                                       startTick: 0, lengthTicks: 1920))

        // The generate feed (updateComposerMelody) must NOT rewrite the user clip.
        let take = MelodyClip.flatten(loopBars: [[Note(pitch: 72, startStep: 0)]])
        for r in store.document.regions(in: laneID) {
            _ = clips.updateComposerMelody(id: r.clipID, notes: take)
        }
        XCTAssertEqual(clips.clip(id: user.id)?.melody?.notes.map(\.pitch), [48],
                       "the never-clobber law — user content survives generate/evolve")
    }

    /// Full clip grid: `ensureComposerRegion` refuses (false) and adds NO region —
    /// the honest, visible path (the view flips `composerClipGridFull`); the live
    /// sound path is untouched, so nothing crashes and no user clip is displaced.
    func testFullGrid_ensureRefuses_noRegion_noDisplacement() {
        let store = TimelineStore()
        let clips = ClipStore()
        let before = clips.slots
        defer { restoreSlots(clips, before) }
        while let free = clips.firstEmptySlotIndex {
            clips.setClip(at: free, Clip(name: "User \(free)",
                                         melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0)])))
        }
        let fullSlots = clips.slots
        let laneID = addMidiLane(store)
        defer { removeLane(store, laneID) }

        XCTAssertFalse(store.ensureComposerRegion(for: laneID, clipStore: clips, loopBars: 8),
                       "full grid → honest refusal (view shows composerClipGridFull)")
        XCTAssertTrue(store.document.regions(in: laneID).isEmpty, "no region without a clip")
        XCTAssertEqual(clips.slots, fullSlots, "every user clip untouched")
    }

    // MARK: - hasArrangementContent (transport ▶ routing: live loop vs arrangement)

    /// The core safety predicate: the auto-composer mirror on the primary roll lane
    /// must NOT flip ▶ from the live bio-generative loop to a frozen region. Only real
    /// arrangement content (secondary lane, audio, or a USER clip on the roll) does.
    func testHasArrangementContent_rollComposerMirrorAlone_isFalse_soLiveLoopStillPlays() {
        var doc = TimelineDocument()
        let rollLane = TimelineLane(name: "MIDI 1", kind: .midi)
        doc.lanes = [rollLane]
        let composerClip = UUID()
        doc.regions = [TimelineRegion(laneID: rollLane.id, clipID: composerClip,
                                      startTick: 0, lengthTicks: TimelineTime.ticksPerBar)]
        // Empty project → false (never arrangement).
        XCTAssertFalse(TimelineDocument().hasArrangementContent { _ in false })
        // Only the composer mirror on the roll lane → false → ▶ stays live loop.
        XCTAssertFalse(doc.hasArrangementContent { $0 == composerClip })
        // A USER (non-composer) clip on the roll lane → true (real content).
        XCTAssertTrue(doc.hasArrangementContent { _ in false })
    }

    func testHasArrangementContent_secondaryOrAudioRegion_isTrue() {
        var doc = TimelineDocument()
        let rollLane = TimelineLane(name: "MIDI 1", kind: .midi)
        let secondary = TimelineLane(name: "MIDI 2", kind: .midi)
        doc.lanes = [rollLane, secondary]
        let rollComposer = UUID(), secondaryComposer = UUID()
        doc.regions = [
            TimelineRegion(laneID: rollLane.id, clipID: rollComposer,
                           startTick: 0, lengthTicks: TimelineTime.ticksPerBar),
            TimelineRegion(laneID: secondary.id, clipID: secondaryComposer,
                           startTick: 0, lengthTicks: TimelineTime.ticksPerBar),
        ]
        // A region on a SECONDARY lane is real arrangement content even when both
        // clips are composer-owned → ▶ engages the arrangement (unchanged behaviour).
        XCTAssertTrue(doc.hasArrangementContent { _ in true })
    }
}
