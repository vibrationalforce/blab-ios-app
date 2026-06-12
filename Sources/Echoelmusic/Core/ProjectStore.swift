// ProjectStore.swift
// Echoel — the saved-projects library. Persists Projects as one JSON array in the
// App Group container (survives relaunch, shared with extensions). Newest first.

import Foundation

@MainActor
@Observable
public final class ProjectStore {

    /// Saved projects, newest first.
    public private(set) var projects: [Project] = []

    @ObservationIgnored private let store: AppGroupStore
    @ObservationIgnored private let fileName = "projects.json"

    public init(store: AppGroupStore = AppGroupStore()) {
        self.store = store
        projects = store.load([Project].self, name: fileName)?.sorted { $0.savedAt > $1.savedAt } ?? []
    }

    /// Insert or update a project (matched by id), then persist. Returns the saved
    /// project (with a refreshed `savedAt`).
    @discardableResult
    public func save(_ project: Project) -> Project {
        var p = project
        p.savedAt = Date()
        projects.removeAll { $0.id == p.id }
        projects.insert(p, at: 0)
        persist()
        return p
    }

    public func delete(id: UUID) {
        projects.removeAll { $0.id == id }
        persist()
    }

    public func project(id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    private func persist() {
        _ = store.save(projects, name: fileName)
    }
}
