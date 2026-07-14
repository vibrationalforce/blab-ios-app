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

    // MARK: - Clip edit — split / merge (founder 2026-07-14 "Clips schneiden und zusammenfügen")

    /// Split the region `id` at an absolute tick into two abutting regions ("cut").
    /// No-op if the tick is at/outside the region's edges. `bpm` advances the second
    /// piece's media offset so audio/video plays seamlessly across the cut.
    public func splitRegion(id: UUID, atTick tick: Int, bpm: Double) {
        guard let i = document.regions.firstIndex(where: { $0.id == id }),
              let (first, second) = document.regions[i].split(at: tick, bpm: bpm) else { return }
        document.regions[i] = first
        document.regions.append(second)
        persist()
    }

    /// Razor: split EVERY region the playhead crosses at `tick` (the DAW "split at
    /// playhead" gesture — no per-region selection needed). No-op if the tick is
    /// inside no region.
    public func splitRegions(atTick tick: Int, bpm: Double) {
        var newPieces: [TimelineRegion] = []
        for i in document.regions.indices {
            if let (first, second) = document.regions[i].split(at: tick, bpm: bpm) {
                document.regions[i] = first
                newPieces.append(second)
            }
        }
        guard !newPieces.isEmpty else { return }
        document.regions.append(contentsOf: newPieces)
        persist()
    }

    /// Join at playhead: merge every pair of same-lane/clip regions that abut exactly
    /// at `tick` (the inverse of the razor — rejoins pieces a split created there).
    /// No-op if no such pair meets at `tick`. Iterates to convergence so several
    /// lanes (or a chain) meeting at the tick all rejoin.
    public func mergeRegions(atTick tick: Int) {
        var regions = document.regions
        var didMerge = false
        var changed = true
        while changed {
            changed = false
            outer: for a in regions.indices where regions[a].endTick == tick {
                for b in regions.indices where a != b && regions[a].abuts(regions[b]) {
                    regions[a] = regions[a].merged(with: regions[b])
                    regions.remove(at: b)
                    didMerge = true; changed = true
                    break outer
                }
            }
        }
        guard didMerge else { return }
        document.regions = regions
        persist()
    }

    // MARK: - Lane edits

    public func addLane(kind: ClipKind, name: String? = nil) {
        let count = document.lanes.filter { $0.kind == kind && !$0.isBio }.count
        let lane = TimelineLane(name: name ?? "\(kind.displayName) \(count + 1)", kind: kind)
        document.lanes.append(lane)
        persist()
    }

    /// Add a track that plays a built-in Echoel instrument (founder 2026-07-13:
    /// "EchoelDrums, Echoelbreak, EchoelSampler etc"). Named after the instrument,
    /// numbered per-instrument so a second EchoelDrums reads "EchoelDrums 2".
    public func addInstrumentTrack(_ instrument: TrackInstrument, name: String? = nil) {
        let count = document.lanes.filter { $0.builtinInstrument == instrument }.count
        let laneName = name ?? (count == 0 ? instrument.displayName
                                           : "\(instrument.displayName) \(count + 1)")
        let lane = TimelineLane(name: laneName, kind: instrument.clipKind,
                                builtinInstrument: instrument)
        document.lanes.append(lane)
        persist()
    }

    /// Assign (or clear, with nil) a track's built-in Echoel instrument.
    public func setBuiltinInstrument(id: UUID, _ instrument: TrackInstrument?) {
        guard let i = document.lanes.firstIndex(where: { $0.id == id }) else { return }
        document.lanes[i].builtinInstrument = instrument
        persist()
    }

    /// Toggle a track's record-arm (founder: "jede Spur soll ein record Button
    /// haben"). Persisted intent; the per-source capture engine reads it.
    public func toggleArm(id: UUID) {
        guard let i = document.lanes.firstIndex(where: { $0.id == id }) else { return }
        document.lanes[i].isArmed.toggle()
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

    /// B2 stereo position, clamped −1…1 (0 = center). State only, like level —
    /// the surface pushes the roll-slot pan into the melodic voices.
    public func setLanePan(id: UUID, _ pan: Float) {
        guard let i = document.lanes.firstIndex(where: { $0.id == id }) else { return }
        document.lanes[i].pan = max(-1, min(1, pan))
        persist()
    }

    /// Per-instrument TRANSPOSE in whole semitones (founder 2026-07-14: "Wenn einzelne
    /// Instrumenten Elemente im synth nen transpose Button haben ist das kool"), clamped
    /// ±48 (±4 octaves) to match the voice. State only — the region player pitches each
    /// lane's voice on load (rollTransposeSink / slotTransposeSink).
    public func setLaneTranspose(id: UUID, _ semitones: Int) {
        guard let i = document.lanes.firstIndex(where: { $0.id == id }) else { return }
        document.lanes[i].transposeSemitones = max(-48, min(48, semitones))
        persist()
    }

    /// Per-instrument DETUNE in cents (founder 2026-07-14 "transpose detune"), clamped
    /// ±100 (±1 semitone) to match the voice. State only — the region player detunes
    /// each lane's voice on load (rollDetuneSink / slotDetuneSink), like transpose.
    public func setLaneDetune(id: UUID, _ cents: Float) {
        guard let i = document.lanes.firstIndex(where: { $0.id == id }) else { return }
        document.lanes[i].detuneCents = max(-100, min(100, cents.isFinite ? cents : 0))
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

    /// One-tap "make the generative instrument audible again" (#22, "alles ist still"):
    /// unmute the roll-slot lane, lift a zeroed fader, clear any foreign solo. Pure
    /// logic lives on the document; this persists it.
    public func unsilenceRollSlot() {
        document.unsilenceRollSlot()
        persist()
    }

    // MARK: - AUv3 track assignment (U3) — persisted plugin DATA, no engine routing

    /// Assign (or clear, with nil) the track's instrument plugin. Pure persisted
    /// intent — the track head shows it; per-lane engine routing waits for
    /// multi-roll (today all MIDI lanes share one melodic voice).
    public func setLaneInstrument(id: UUID, _ instrument: AUPluginRef?) {
        guard let i = document.lanes.firstIndex(where: { $0.id == id }) else { return }
        document.lanes[i].instrument = instrument
        persist()
    }

    /// Set the track's ordered insert-FX chain (signal order). Persisted display
    /// foundation; empty clears it.
    public func setLaneEffects(id: UUID, _ effects: [AUPluginRef]) {
        guard let i = document.lanes.firstIndex(where: { $0.id == id }) else { return }
        document.lanes[i].effects = effects
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
