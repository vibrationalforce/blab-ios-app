// FXPresetStore.swift
// Echoel — the user's own saved FX presets. Persist as Codable JSON in the App
// Group (same discipline as PatchStore). The curated COMMUNITY library is a
// separate, bundled, read-only set; this store holds only the presets the user
// saved on this device, plus on-device personalization (favorites + recents) so
// the list ranks itself to the user with no backend.

import Foundation
import Observation

@MainActor
@Observable
public final class FXPresetStore {

    /// User-saved presets, most-recent save last.
    public private(set) var presets: [FXPreset]
    /// Ids the user has starred.
    public private(set) var favorites: Set<UUID>
    /// Recently-applied ids, most-recent first (capped).
    public private(set) var recents: [UUID]

    @ObservationIgnored private static let maxRecents = 12
    @ObservationIgnored private let store = AppGroupStore(subdirectory: "FXPresets")
    @ObservationIgnored private static let fileName = "userFXPresets"
    @ObservationIgnored private static let metaName = "userFXPresetMeta"

    private struct Meta: Codable { var favorites: [UUID]; var recents: [UUID] }

    public init() {
        self.presets = store.load([FXPreset].self, name: Self.fileName) ?? []
        let meta = store.load(Meta.self, name: Self.metaName)
        self.favorites = Set(meta?.favorites ?? [])
        self.recents = meta?.recents ?? []
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
        favorites.remove(id)
        recents.removeAll { $0 == id }
        persist()
    }

    public func isFavorite(id: UUID) -> Bool { favorites.contains(id) }

    public func toggleFavorite(id: UUID) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        persistMeta()
    }

    /// Record that a preset was applied (drives the recents ranking).
    public func markUsed(id: UUID) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
        persistMeta()
    }

    /// Personalized order: favorites first, then most-recently-used, then
    /// newest-saved. Pure on-device ranking — no backend.
    public var sortedPresets: [FXPreset] {
        Self.ranked(presets, favorites: favorites, recents: recents)
    }

    /// Pure ranking (testable, no I/O).
    static func ranked(_ presets: [FXPreset], favorites: Set<UUID>, recents: [UUID]) -> [FXPreset] {
        let recentRank = Dictionary(recents.enumerated().map { ($1, $0) },
                                    uniquingKeysWith: { first, _ in first })
        return presets.enumerated().sorted { l, r in
            let lf = favorites.contains(l.element.id) ? 0 : 1
            let rf = favorites.contains(r.element.id) ? 0 : 1
            if lf != rf { return lf < rf }                 // favorites first
            let lr = recentRank[l.element.id] ?? Int.max
            let rr = recentRank[r.element.id] ?? Int.max
            if lr != rr { return lr < rr }                 // more recently used first
            return l.offset > r.offset                      // else newest save first
        }.map { $0.element }
    }

    private func persist() {
        store.save(presets, name: Self.fileName)
        persistMeta()
    }

    private func persistMeta() {
        store.save(Meta(favorites: Array(favorites), recents: recents), name: Self.metaName)
    }
}
