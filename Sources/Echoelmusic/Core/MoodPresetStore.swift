// MoodPresetStore.swift
// Echoel — the library of composition moods: curated factory moods + user-saved
// moods. User moods persist as Codable JSON in the App Group; factory moods are
// always present (read-only baselines) and are not persisted. Mirrors PatchStore
// exactly so every library in the app behaves identically (favorites + recents
// rank the list on-device, no backend).

import Foundation
import Observation

@MainActor
@Observable
public final class MoodPresetStore {

    /// All moods: factory presets first, then user-saved.
    public private(set) var moods: [MoodPreset]
    /// Ids the user has starred (factory or user — ids are stable).
    public private(set) var favorites: Set<UUID>
    /// Recently-recalled ids, most-recent first (capped).
    public private(set) var recents: [UUID]

    @ObservationIgnored private static let maxRecents = 12
    @ObservationIgnored private let store = AppGroupStore(subdirectory: "MoodPresets")
    @ObservationIgnored private static let fileName = "userMoodPresets"
    @ObservationIgnored private static let metaName = "moodPresetMeta"
    @ObservationIgnored private static let factoryIDs: Set<UUID> = Set(MoodPreset.factory.map { $0.id })

    private struct Meta: Codable { var favorites: [UUID]; var recents: [UUID] }

    public init() {
        // Element-tolerant (see AppGroupStore.loadLossyArray) — one unreadable mood must not
        // empty the user's whole library on the next save. Unordered list ⇒ compact.
        let user = (store.loadLossyArray(MoodPreset.self, name: Self.fileName) ?? []).compactMap { $0 }
        // Drop any accidental factory duplicates from the user file.
        let cleanedUser = user.filter { !Self.factoryIDs.contains($0.id) }
        self.moods = MoodPreset.factory + cleanedUser
        let meta = store.load(Meta.self, name: Self.metaName)
        self.favorites = Set(meta?.favorites ?? [])
        self.recents = meta?.recents ?? []
    }

    public func isFavorite(id: UUID) -> Bool { favorites.contains(id) }

    public func toggleFavorite(id: UUID) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        persistMeta()
    }

    /// Record that a mood was recalled (drives the recents ranking).
    public func markUsed(id: UUID) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
        persistMeta()
    }

    /// Personalized order: favorites first, then most-recently-used, then the
    /// store's natural order (factory then user). Pure on-device ranking.
    public var sortedMoods: [MoodPreset] {
        Self.ranked(moods, favorites: favorites, recents: recents)
    }

    /// Pure ranking (testable, no I/O).
    static func ranked(_ moods: [MoodPreset], favorites: Set<UUID>, recents: [UUID]) -> [MoodPreset] {
        let recentRank = Dictionary(recents.enumerated().map { ($1, $0) },
                                    uniquingKeysWith: { first, _ in first })
        return moods.enumerated().sorted { l, r in
            let lf = favorites.contains(l.element.id) ? 0 : 1
            let rf = favorites.contains(r.element.id) ? 0 : 1
            if lf != rf { return lf < rf }                 // favorites first
            let lr = recentRank[l.element.id] ?? Int.max
            let rr = recentRank[r.element.id] ?? Int.max
            if lr != rr { return lr < rr }                 // more recently used first
            return l.offset < r.offset                      // else natural order
        }.map { $0.element }
    }

    /// True for read-only built-in moods.
    public func isFactory(_ mood: MoodPreset) -> Bool {
        Self.factoryIDs.contains(mood.id)
    }

    /// Insert or update a mood (factory presets are never overwritten — callers
    /// should "Save As" a copy with a fresh id to keep edits).
    public func save(_ mood: MoodPreset) {
        guard !isFactory(mood) else { return }
        if let i = moods.firstIndex(where: { $0.id == mood.id }) {
            moods[i] = mood
        } else {
            moods.append(mood)
        }
        persist()
    }

    /// Save `mood` under a new name as a brand-new user mood; returns it.
    @discardableResult
    public func saveAs(_ mood: MoodPreset, name: String) -> MoodPreset {
        var copy = mood
        copy.id = UUID()
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        moods.append(copy)
        persist()
        return copy
    }

    public func delete(id: UUID) {
        guard !Self.factoryIDs.contains(id) else { return }
        moods.removeAll { $0.id == id }
        favorites.remove(id)
        recents.removeAll { $0 == id }
        persist()
    }

    private func persist() {
        let user = moods.filter { !Self.factoryIDs.contains($0.id) }
        store.save(user, name: Self.fileName)
        persistMeta()
    }

    private func persistMeta() {
        store.save(Meta(favorites: Array(favorites), recents: recents), name: Self.metaName)
    }
}
