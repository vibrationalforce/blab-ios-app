// FXPresetStore.swift
// Echoel — the user's own saved FX presets. Persist as Codable JSON in the App
// Group (same discipline as PatchStore). The curated COMMUNITY library is a
// separate, bundled, read-only set (added next cycle); this store holds only the
// presets the user saved on this device.

import Foundation
import Observation

@MainActor
@Observable
public final class FXPresetStore {

    /// User-saved presets, most-recent last.
    public private(set) var presets: [FXPreset]

    @ObservationIgnored private let store = AppGroupStore(subdirectory: "FXPresets")
    @ObservationIgnored private static let fileName = "userFXPresets"

    public init() {
        self.presets = store.load([FXPreset].self, name: Self.fileName) ?? []
    }

    /// Insert (by new id) or update (matching id) a preset, then persist.
    @discardableResult
    public func save(_ preset: FXPreset) -> FXPreset {
        if let i = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[i] = preset
        } else {
            presets.append(preset)
        }
        persist()
        return preset
    }

    public func delete(id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        store.save(presets, name: Self.fileName)
    }
}
