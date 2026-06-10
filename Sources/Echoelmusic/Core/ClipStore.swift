// ClipStore.swift
// Echoel — the session grid of launchable clips. Holds a fixed set of slots,
// persisted as JSON in the App Group. Capture/launch wiring (snapshotting the
// live PatternEngine + PianoRollModel) lives in ClipView, which has those
// engines in the environment; the store is pure data.

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

    public func setClip(at index: Int, _ clip: Clip) {
        guard slots.indices.contains(index) else { return }
        slots[index] = clip
        persist()
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
