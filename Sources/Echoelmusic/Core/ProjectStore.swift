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
        // Element-tolerant (see AppGroupStore.loadLossyArray): one unreadable project is
        // dropped instead of taking the whole library down with it — the previous decode
        // returned nil for the entire file and the next save wrote the emptied list back.
        // These are re-sorted anyway, so a hole cannot mean anything positional.
        projects = (store.loadLossyArray(Project.self, name: fileName) ?? [])
            .compactMap { $0 }
            .sorted { $0.savedAt > $1.savedAt }
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

    // MARK: - Sharing (cross-device / community)

    /// Encode a project to portable, human-diffable JSON for sharing (AirDrop,
    /// Files, Messages) or cross-device transfer. Self-contained: style, key, tempo,
    /// the synth patch, the notes and the drum grid all travel in one document.
    public func exportData(_ project: Project) -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(project)
    }

    /// Import a shared project document. The decoded project gets a FRESH id (so
    /// importing your own export never overwrites the original) and is saved to the
    /// top of the library. Returns the saved project, or nil if the data isn't a
    /// valid Echoel session.
    @discardableResult
    public func importProject(from data: Data) -> Project? {
        guard var p = try? JSONDecoder().decode(Project.self, from: data) else { return nil }
        p.id = UUID()
        return save(p)
    }

    /// Import from a (security-scoped) file URL — the `fileImporter` path.
    @discardableResult
    public func importProject(from url: URL) -> Project? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return importProject(from: data)
    }

    private func persist() {
        _ = store.save(projects, name: fileName)
    }
}
