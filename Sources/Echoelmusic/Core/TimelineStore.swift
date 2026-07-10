// TimelineStore.swift
// Echoel — the Arrange beat-grid document store (approved plan, Stage 1b).
// Wraps TimelineDocument (lanes + tick-positioned regions), persisted as JSON in
// the App Group. Structural edits only — playback stays in the players; the
// store never touches audio.
//
// MIGRATION: the first launch without a stored timeline converts the existing
// ArrangementStore song (ordered sections, integer bars) into regions on one
// MIDI lane — losslessly (bar-aligned sections become bar-aligned regions), so
// nobody's song disappears in the restructure. Pure static func → Linux-CI-tested.

import Foundation
import Observation

@MainActor
@Observable
public final class TimelineStore {

    public private(set) var document: TimelineDocument

    @ObservationIgnored private let store = AppGroupStore(subdirectory: "Timeline")
    @ObservationIgnored private static let fileName = "timeline"

    /// True until the one-time legacy migration ran (no stored document yet).
    @ObservationIgnored private var needsBootstrap: Bool

    /// Loads the stored document. When none exists the document stays empty
    /// until `bootstrapIfNeeded(sections:)` runs the one-time migration — the
    /// store is a plain `@State` default in the App, so the legacy sections
    /// arrive later (from the environment) rather than at init.
    public init() {
        if let stored = store.load(TimelineDocument.self, name: Self.fileName) {
            self.document = stored
            self.needsBootstrap = false
        } else {
            self.document = TimelineDocument()
            self.needsBootstrap = true
        }
    }

    /// One-time migration of the legacy arrangement (idempotent; call from the
    /// timeline surface's `.task`). Persists the migrated document.
    public func bootstrapIfNeeded(sections: [ArrangementSection]) {
        guard needsBootstrap else { return }
        needsBootstrap = false
        document = Self.migrate(sections: sections)
        persist()
    }

    // MARK: - Migration (pure, testable)

    /// Legacy song → timeline: sections become back-to-back bar-aligned regions
    /// on one MIDI lane (sections without a clip are silent gaps — they advance
    /// the position but create no region, same as the section player treats
    /// them). Always seeds a second, empty Audio lane so the new surface shows
    /// the multi-lane shape from day one (founder: "mehrere" Lanes).
    public static func migrate(sections: [ArrangementSection]) -> TimelineDocument {
        let midiLane = TimelineLane(name: "MIDI 1", kind: .midi)
        let audioLane = TimelineLane(name: "Audio 1", kind: .audio)
        var regions: [TimelineRegion] = []
        var cursorTick = 0
        for section in sections {
            let lengthTicks = max(1, section.lengthBars) * TimelineTime.ticksPerBar
            if let clipID = section.clipID {
                regions.append(TimelineRegion(
                    laneID: midiLane.id, clipID: clipID,
                    startTick: cursorTick, lengthTicks: lengthTicks
                ))
            }
            cursorTick += lengthTicks
        }
        return TimelineDocument(lanes: [midiLane, audioLane], regions: regions)
    }

    // MARK: - Region edits (persist per edit)

    public func addRegion(_ region: TimelineRegion) {
        document.regions.append(region)
        persist()
    }

    public func removeRegion(id: UUID) {
        document.regions.removeAll { $0.id == id }
        persist()
    }

    /// Move a region's start (caller applies snap/magnet first — the store
    /// stays gesture-agnostic). Clamped ≥ 0.
    public func moveRegion(id: UUID, toStartTick tick: Int) {
        guard let i = document.regions.firstIndex(where: { $0.id == id }) else { return }
        document.regions[i].startTick = max(0, tick)
        persist()
    }

    /// Resize a region (trim); minimum one tick so a region can't vanish.
    public func resizeRegion(id: UUID, lengthTicks: Int) {
        guard let i = document.regions.firstIndex(where: { $0.id == id }) else { return }
        document.regions[i].lengthTicks = max(1, lengthTicks)
        persist()
    }

    // MARK: - Lane edits

    public func addLane(kind: ClipKind, name: String? = nil) {
        let count = document.lanes.filter { $0.kind == kind && !$0.isBio }.count
        let lane = TimelineLane(name: name ?? "\(kind.displayName) \(count + 1)", kind: kind)
        document.lanes.append(lane)
        persist()
    }

    public func renameLane(id: UUID, to name: String) {
        guard let i = document.lanes.firstIndex(where: { $0.id == id }) else { return }
        document.lanes[i].name = name
        persist()
    }

    // MARK: - Lane mixer (K2a) — state only; the SURFACE pushes gains into engines

    public func setLaneLevel(id: UUID, _ level: Float) {
        guard let i = document.lanes.firstIndex(where: { $0.id == id }) else { return }
        document.lanes[i].level = max(0, min(2, level))
        persist()
    }

    public func toggleMute(id: UUID) {
        guard let i = document.lanes.firstIndex(where: { $0.id == id }) else { return }
        document.lanes[i].isMuted.toggle()
        persist()
    }

    public func toggleSolo(id: UUID) {
        guard let i = document.lanes.firstIndex(where: { $0.id == id }) else { return }
        document.lanes[i].isSoloed.toggle()
        persist()
    }

    /// Remove an EMPTY lane (regions must move/delete first — no silent data loss).
    public func removeLaneIfEmpty(id: UUID) {
        guard document.regions(in: id).isEmpty else { return }
        document.lanes.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        try? store.save(document, name: Self.fileName)
    }
}
