// ClipStore.swift
// Echoel — the session grid of launchable clips. Holds a fixed set of slots,
// persisted as JSON in the App Group. Capture/launch wiring (snapshotting the
// live PatternEngine + PianoRollModel) lives in the one-view Clips panel, which
// has those engines in the environment; the store is pure data.

import Foundation
import Observation

@MainActor
@Observable
public final class ClipStore {

    public static let slotCount = 8

    /// Fixed grid of slots; `nil` = empty cell.
    public private(set) var slots: [Clip?]

    @ObservationIgnored private let store = AppGroupStore(subdirectory: "Clips")
    @ObservationIgnored private static let fileName = "clips"

    public init() {
        // Element-tolerant, POSITIONALLY (see AppGroupStore.loadLossyArray). This grid is the
        // one store where a hole must be KEPT, not compacted: the index IS the slot, so
        // dropping a corrupt clip would shift every later one into the wrong cell AND fail the
        // count check below — turning one bad clip into all eight lost. `[Clip?]` already means
        // "nil = empty cell", so an unreadable clip degrades to exactly that: its own cell
        // empties, the other seven survive.
        let saved = store.loadLossyArray(Clip?.self, name: Self.fileName)?.map { $0 ?? nil }
        if let saved, saved.count == Self.slotCount {
            self.slots = saved
        } else {
            self.slots = Array(repeating: nil, count: Self.slotCount)
        }
    }

    /// Look up a clip by its stable id (used by the Arrangement player to
    /// resolve a section's `clipID` into content to load).
    public func clip(id: UUID) -> Clip? {
        slots.compactMap { $0 }.first { $0.id == id }
    }

    /// Non-empty clips, in slot order — the palette an Arrangement section picks
    /// from.
    public var filledClips: [Clip] { slots.compactMap { $0 } }

    /// The first empty slot, or `nil` when the 8-slot grid is full. The audio /
    /// video import path lands a fresh clip here; a full grid surfaces to the
    /// user as "clip grid full" rather than silently overwriting. Pure lookup.
    public var firstEmptySlotIndex: Int? { slots.firstIndex(where: { $0 == nil }) }

    public func setClip(at index: Int, _ clip: Clip) {
        guard slots.indices.contains(index) else { return }
        slots[index] = clip
        persist()
    }

    /// H11: replace a clip's MIDI content by clip id (the clip-scoped editor's
    /// write-back — the first content-level clip edit; all timeline edits so
    /// far only moved region tick-windows). Whole-value write (Clip/MelodyClip
    /// are value types) so the region player, which re-reads
    /// `clip(id:)?.melody?.notes` at region onsets, never sees a torn state —
    /// a mid-play save becomes audible at the next onset, like any DAW.
    /// Returns false (writing nothing) for an unknown id.
    @discardableResult
    public func updateMelody(id: UUID, notes: [Note]) -> Bool {
        guard let i = slots.firstIndex(where: { $0?.id == id }),
              slots[i]?.kind == .midi else { return false }   // melody is MIDI content only
        slots[i]?.melody = MelodyClip(notes: notes)
        persist()
        return true
    }

    /// Per-lane composition Slice A: the COMPOSER's write-back — like
    /// `updateMelody` (whole-value write, next-onset audibility) but hard-gated
    /// on `Clip.composerOwned`, so an automatic generate/evolve can rewrite ONLY
    /// clips the composer itself created for a lane's override take. A
    /// user-captured/imported clip (`composerOwned == false`) is refused —
    /// returns false, writes nothing (the never-clobber law). No-op (true,
    /// no persist) when the notes are already identical, so the ~30 s evolve
    /// tick doesn't spam App-Group persistence.
    @discardableResult
    public func updateComposerMelody(id: UUID, notes: [Note]) -> Bool {
        guard let i = slots.firstIndex(where: { $0?.id == id }),
              let clip = slots[i], clip.kind == .midi, clip.composerOwned
        else { return false }
        guard clip.melody?.notes != notes else { return true }   // unchanged → no persist
        slots[i]?.melody = MelodyClip(notes: notes)
        persist()
        return true
    }

    /// Automation-in-Spur L1 (Item 1): the clip-scoped automation editor's
    /// write-back — sets the parameter-automation lanes the clip carries
    /// (`Clip.automation`, clip-relative ticks). Whole-value write like
    /// `updateMelody` so the region player, which re-reads `clip(id:)?.automation`
    /// and calls `setClipAutomation` at region onsets, never sees a torn state —
    /// a mid-play save becomes audible at the next onset. Applies to ANY clip
    /// kind (automation plays whenever the clip plays, MIDI or audio). No-op
    /// (true, no persist) when the lanes are VALUE-equal to what the clip already
    /// holds — so a read-modify-write editor that mutates `clip.automation` in
    /// place (preserving lane/point `id`s) doesn't spam App-Group persistence on
    /// a gesture that lands on the same value. (A caller that reconstructs lanes
    /// with fresh `id`s each write defeats the skip — `AutomationLane`/`Point`
    /// equality includes `id` — and will persist every time; the S2 editor keeps
    /// ids stable.) Returns false (writing nothing) for an unknown id.
    @discardableResult
    public func setClipAutomation(id: UUID, lanes: [AutomationLane]) -> Bool {
        guard let i = slots.firstIndex(where: { $0?.id == id }),
              var clip = slots[i] else { return false }
        guard clip.automation != lanes else { return true }   // unchanged → no persist
        clip.automation = lanes
        slots[i] = clip
        persist()
        return true
    }

    public func rename(at index: Int, to name: String) {
        guard slots.indices.contains(index), var clip = slots[index] else { return }
        clip.name = name
        slots[index] = clip
        persist()
    }

    public func clear(at index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index] = nil
        persist()
    }

    private func persist() {
        store.save(slots, name: Self.fileName)
    }
}
