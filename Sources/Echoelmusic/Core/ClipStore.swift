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
        let saved = store.load([Clip?].self, name: Self.fileName)
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
