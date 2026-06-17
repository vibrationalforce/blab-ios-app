// ArrangementStore.swift
// Echoel — the editable song timeline, persisted as JSON in the App Group.
// Pure data + structural edits (add / remove / move / resize / rename / assign
// clip). Playback lives in ArrangementPlayer; capturing the live transport into
// clips stays in the Session grid. The store never touches audio.

import Foundation
import Observation

@MainActor
@Observable
public final class ArrangementStore {

    public private(set) var arrangement: Arrangement

    @ObservationIgnored private let store = AppGroupStore(subdirectory: "Arrangement")
    @ObservationIgnored private static let fileName = "song"

    public init() {
        self.arrangement = store.load(Arrangement.self, name: Self.fileName) ?? Arrangement()
    }

    public var sections: [ArrangementSection] { arrangement.sections }
    public var isEmpty: Bool { arrangement.sections.isEmpty }
    public var totalBars: Int { arrangement.totalBars }

    // MARK: - Structural edits

    /// Append a new section (defaults to a 1-bar silent gap until a clip is set).
    public func addSection(clipID: UUID? = nil, name: String = "Section", colorIndex: Int = 0, lengthBars: Int = 1) {
        let section = ArrangementSection(
            clipID: clipID, name: name, colorIndex: colorIndex, lengthBars: lengthBars
        )
        arrangement.sections.append(section)
        persist()
    }

    public func remove(at index: Int) {
        guard arrangement.sections.indices.contains(index) else { return }
        arrangement.sections.remove(at: index)
        persist()
    }

    public func remove(id: UUID) {
        arrangement.sections.removeAll { $0.id == id }
        persist()
    }

    /// Move the section at `index` by `offset` slots (clamped), preserving order.
    public func move(at index: Int, by offset: Int) {
        guard arrangement.sections.indices.contains(index) else { return }
        let target = index + offset
        guard arrangement.sections.indices.contains(target) else { return }
        let section = arrangement.sections.remove(at: index)
        arrangement.sections.insert(section, at: target)
        persist()
    }

    public func setLength(id: UUID, bars: Int) {
        guard let i = arrangement.sections.firstIndex(where: { $0.id == id }) else { return }
        arrangement.sections[i].lengthBars = max(1, bars)
        persist()
    }

    public func rename(id: UUID, to name: String) {
        guard let i = arrangement.sections.firstIndex(where: { $0.id == id }) else { return }
        arrangement.sections[i].name = name
        persist()
    }

    public func setClip(id: UUID, clipID: UUID?, name: String? = nil, colorIndex: Int? = nil) {
        guard let i = arrangement.sections.firstIndex(where: { $0.id == id }) else { return }
        arrangement.sections[i].clipID = clipID
        if let name { arrangement.sections[i].name = name }
        if let colorIndex { arrangement.sections[i].colorIndex = colorIndex }
        persist()
    }

    public func clearAll() {
        arrangement.sections.removeAll()
        persist()
    }

    private func persist() {
        store.save(arrangement, name: Self.fileName)
    }
}
