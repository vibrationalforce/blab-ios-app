// PatchStore.swift
// Echoel — the library of synth sounds: factory presets + user-saved patches.
// User patches persist as Codable JSON in the App Group; factory presets are
// always present (read-only baselines) and are not persisted.

import Foundation
import Observation

@MainActor
@Observable
public final class PatchStore {

    /// All patches: factory presets first, then user-saved.
    public private(set) var patches: [SynthPatch]
    /// Ids the user has starred (factory or user — ids are stable).
    public private(set) var favorites: Set<UUID>
    /// Recently-recalled ids, most-recent first (capped).
    public private(set) var recents: [UUID]

    @ObservationIgnored private static let maxRecents = 12
    @ObservationIgnored private let store = AppGroupStore(subdirectory: "Patches")
    @ObservationIgnored private static let fileName = "userPatches"
    @ObservationIgnored private static let metaName = "patchMeta"
    @ObservationIgnored private static let factoryIDs: Set<UUID> = Set(SynthPatch.factory.map { $0.id })

    private struct Meta: Codable { var favorites: [UUID]; var recents: [UUID] }

    public init() {
        // Element-tolerant: one unreadable patch is dropped, the rest of the library
        // survives. The all-or-nothing array decode used to return nil for the whole file,
        // and the next `saveUser()` wrote that empty array back — a single bad patch
        // permanently destroyed every sound the user had saved. Order is irrelevant here
        // (this is a library, not a grid), so compacting the holes away is correct.
        let user = (store.loadLossyArray(SynthPatch.self, name: Self.fileName) ?? []).compactMap { $0 }
        // Drop any accidental factory duplicates from the user file.
        let cleanedUser = user.filter { !Self.factoryIDs.contains($0.id) }
        self.patches = SynthPatch.factory + cleanedUser
        let meta = store.load(Meta.self, name: Self.metaName)
        self.favorites = Set(meta?.favorites ?? [])
        self.recents = meta?.recents ?? []
    }

    public func isFavorite(id: UUID) -> Bool { favorites.contains(id) }

    public func toggleFavorite(id: UUID) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        persistMeta()
    }

    /// Record that a patch was recalled (drives the recents ranking).
    public func markUsed(id: UUID) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
        persistMeta()
    }

    /// Personalized order: favorites first, then most-recently-used, then the
    /// store's natural order (factory then user). Pure on-device ranking.
    public var sortedPatches: [SynthPatch] {
        Self.ranked(patches, favorites: favorites, recents: recents)
    }

    /// Pure ranking (testable, no I/O).
    static func ranked(_ patches: [SynthPatch], favorites: Set<UUID>, recents: [UUID]) -> [SynthPatch] {
        let recentRank = Dictionary(recents.enumerated().map { ($1, $0) },
                                    uniquingKeysWith: { first, _ in first })
        return patches.enumerated().sorted { l, r in
            let lf = favorites.contains(l.element.id) ? 0 : 1
            let rf = favorites.contains(r.element.id) ? 0 : 1
            if lf != rf { return lf < rf }                 // favorites first
            let lr = recentRank[l.element.id] ?? Int.max
            let rr = recentRank[r.element.id] ?? Int.max
            if lr != rr { return lr < rr }                 // more recently used first
            return l.offset < r.offset                      // else natural order
        }.map { $0.element }
    }

    /// True for read-only built-in presets.
    public func isFactory(_ patch: SynthPatch) -> Bool {
        Self.factoryIDs.contains(patch.id)
    }

    /// Insert or update a patch (factory presets are never overwritten — callers
    /// should "Save As" a copy with a fresh id to keep edits).
    public func save(_ patch: SynthPatch) {
        guard !isFactory(patch) else { return }
        if let i = patches.firstIndex(where: { $0.id == patch.id }) {
            patches[i] = patch
        } else {
            patches.append(patch)
        }
        persist()
    }

    /// Save `patch` under a new name as a brand-new user patch; returns it.
    @discardableResult
    public func saveAs(_ patch: SynthPatch, name: String) -> SynthPatch {
        var copy = patch
        copy.id = UUID()
        copy.name = name
        patches.append(copy)
        persist()
        return copy
    }

    public func delete(id: UUID) {
        guard !Self.factoryIDs.contains(id) else { return }
        patches.removeAll { $0.id == id }
        favorites.remove(id)
        recents.removeAll { $0 == id }
        persist()
    }

    private func persist() {
        let user = patches.filter { !Self.factoryIDs.contains($0.id) }
        store.save(user, name: Self.fileName)
        persistMeta()
    }

    private func persistMeta() {
        store.save(Meta(favorites: Array(favorites), recents: recents), name: Self.metaName)
    }
}
