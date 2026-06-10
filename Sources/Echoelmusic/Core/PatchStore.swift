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

    @ObservationIgnored private let store = AppGroupStore(subdirectory: "Patches")
    @ObservationIgnored private static let fileName = "userPatches"
    @ObservationIgnored private static let factoryIDs: Set<UUID> = Set(SynthPatch.factory.map { $0.id })

    public init() {
        let user = store.load([SynthPatch].self, name: Self.fileName) ?? []
        // Drop any accidental factory duplicates from the user file.
        let cleanedUser = user.filter { !Self.factoryIDs.contains($0.id) }
        self.patches = SynthPatch.factory + cleanedUser
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
        persist()
    }

    private func persist() {
        let user = patches.filter { !Self.factoryIDs.contains($0.id) }
        store.save(user, name: Self.fileName)
    }
}
