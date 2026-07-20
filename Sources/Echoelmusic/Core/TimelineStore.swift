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

    // MARK: - Undo / Redo (clip game C2 — founder 2026-07-15 "seamless workflow")

    /// REGION-array snapshots BEFORE each region edit (value-type copies — cheap). Kept
    /// off observation; the observable `canUndo`/`canRedo` flags drive the toolbar
    /// buttons. Deliberately NOT whole-document snapshots: lanes/mixer/automation are
    /// not part of this history, so an undo can never silently revert a fader move,
    /// rename, or instrument assignment made after the region edit (reviewer-caught
    /// cross-contamination). All 11 snapshotted commands mutate ONLY `document.regions`.
    /// EchoelAI's "mach das rückgängig" will call exactly `undo()` (store-first, plan C6).
    @ObservationIgnored private var undoStack: [[TimelineRegion]] = []
    @ObservationIgnored private var redoStack: [[TimelineRegion]] = []
    public private(set) var canUndo = false
    public private(set) var canRedo = false
    private static let undoDepth = 50

    /// Call AFTER a method's guards pass and BEFORE its first mutation, so every
    /// snapshot equals exactly one real user command (no dead undo steps).
    private func snapshotForUndo() {
        undoStack.append(document.regions)
        if undoStack.count > Self.undoDepth { undoStack.removeFirst() }
        redoStack.removeAll()
        syncUndoFlags()
    }

    /// Restore a snapshot, dropping regions whose lane no longer exists (a lane deleted
    /// AFTER the snapshot must not resurrect invisible orphans that inflate the song end).
    private func restoreRegions(_ regions: [TimelineRegion]) {
        document.regions = regions.filter { r in document.lanes.contains { $0.id == r.laneID } }
    }

    /// Revert the last region edit. No-op with an empty history.
    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document.regions)
        restoreRegions(previous)
        persist()
        syncUndoFlags()
    }

    /// Re-apply the last undone edit. No-op unless the previous action was `undo()`.
    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document.regions)
        restoreRegions(next)
        persist()
        syncUndoFlags()
    }

    private func syncUndoFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: - Region edits (persist per edit)

    public func addRegion(_ region: TimelineRegion) {
        snapshotForUndo()
        document.regions.append(region)
        persist()
    }

    public func removeRegion(id: UUID) {
        guard document.regions.contains(where: { $0.id == id }) else { return }
        snapshotForUndo()
        document.regions.removeAll { $0.id == id }
        persist()
    }

    /// Duplicate a region: append an identical copy (fresh id) right AFTER it on the
    /// same lane, sharing the same clip (regions may share a clipID → no new slot).
    /// The arrangement's "copy" verb, alongside split/join/delete/move.
    public func duplicateRegion(id: UUID) {
        guard let r = document.regions.first(where: { $0.id == id }) else { return }
        snapshotForUndo()
        document.regions.append(r.duplicated())
        persist()
    }

    /// Move a region's start (caller applies snap/magnet first — the store
    /// stays gesture-agnostic). Clamped ≥ 0. Passing `bpm` applies the C5
    /// overlap rule (the moved clip wins) inside the same undo step.
    public func moveRegion(id: UUID, toStartTick tick: Int, bpm: Double? = nil) {
        guard let i = document.regions.firstIndex(where: { $0.id == id }) else { return }
        snapshotForUndo()
        document.regions[i].startTick = max(0, tick)
        if let bpm { resolveOverlaps(around: id, bpm: bpm) }
        persist()
    }

    /// Drag-to-move (clip game C1): move a region in TIME and optionally to another
    /// LANE `laneOffset` rows away. The lane change only applies when the target row
    /// exists AND has the same kind (an audio clip can't land on a MIDI lane) — else
    /// the region keeps its lane and only the time move applies. One store method =
    /// one command, so the future EchoelAI edit tools call exactly this (plan
    /// PLAN_CLIP_GAME_2026-07-15: store-first, gestures stay thin).
    ///
    /// C5 overlap rule (opt-in via `bpm`): the MOVED clip wins — neighbours it now
    /// overlaps are trimmed to make room, fully-covered ones are removed, and a
    /// neighbour that fully contains the drop is split into the two surrounding
    /// pieces. All inside THIS command's one undo step. `bpm` drives the media-offset
    /// maths (nil = legacy behaviour, overlaps left as-is).
    public func moveRegion(id: UUID, toStartTick tick: Int, laneOffset: Int,
                           bpm: Double? = nil) {
        guard let i = document.regions.firstIndex(where: { $0.id == id }) else { return }
        snapshotForUndo()
        document.regions[i].startTick = max(0, tick)
        if laneOffset != 0,
           let fromIdx = document.lanes.firstIndex(where: { $0.id == document.regions[i].laneID }) {
            let targetIdx = fromIdx + laneOffset
            if document.lanes.indices.contains(targetIdx),
               document.lanes[targetIdx].kind == document.lanes[fromIdx].kind,
               !document.lanes[targetIdx].isBio {
                document.regions[i].laneID = document.lanes[targetIdx].id
            }
        }
        if let bpm { resolveOverlaps(around: id, bpm: bpm) }
        persist()
    }

    /// C5 — "the edited clip wins": reshape every SAME-LANE region that overlaps
    /// region `id` so playback stays unambiguous (the DAW overwrite rule). Left
    /// overlappers keep their head (tail trimmed to abut), right overlappers keep
    /// their tail (front-trimmed via `trimmedStart`, media offset advancing so the
    /// content stays put), containers split into both surviving pieces, fully-covered
    /// neighbours drop. Pure region maths (`split`/`trimmedStart`); the CALLER's
    /// snapshot already covers this, so the whole command stays one undo step.
    private func resolveOverlaps(around id: UUID, bpm: Double) {
        guard let e = document.regions.first(where: { $0.id == id }) else { return }
        var result: [TimelineRegion] = []
        result.reserveCapacity(document.regions.count)
        for r in document.regions {
            // Untouched: the edited region itself, other lanes, and non-overlappers.
            if r.id == e.id || r.laneID != e.laneID
                || r.endTick <= e.startTick || r.startTick >= e.endTick {
                result.append(r)
                continue
            }
            let coversLeft = r.startTick < e.startTick
            let coversRight = r.endTick > e.endTick
            if coversLeft && coversRight {
                // r fully contains e → keep the piece before AND the piece after.
                if let (left, rest) = r.split(at: e.startTick, bpm: bpm) {
                    result.append(left)
                    if let right = rest.trimmedStart(toTick: e.endTick, bpm: bpm) {
                        result.append(right)
                    }
                }
            } else if coversLeft {
                // r sticks out to the left → trim its tail to abut e.
                var left = r
                left.lengthTicks = e.startTick - r.startTick   // ≥ 1 (strictly left)
                result.append(left)
            } else if coversRight {
                // r sticks out to the right → front-trim it to start at e's end.
                if let right = r.trimmedStart(toTick: e.endTick, bpm: bpm) {
                    result.append(right)
                }
            }
            // else: r fully inside e → swallowed (dropped).
        }
        document.regions = result
    }

    /// Resize a region (trim); minimum one tick so a region can't vanish.
    public func resizeRegion(id: UUID, lengthTicks: Int) {
        guard let i = document.regions.firstIndex(where: { $0.id == id }) else { return }
        snapshotForUndo()
        document.regions[i].lengthTicks = max(1, lengthTicks)
        persist()
    }

    /// CLIP-6a review: set ONLY a region's own gain (clamped 0…2) — the media
    /// window (offset/length, tick twin) stays byte-identical. The edit door
    /// uses this for a gain-only Done so the seed's file-duration clamp or a
    /// tempo shift under the sheet can never rewrite the region's musical
    /// length (the CLIP-4 untouched-Done guarantee). No-op when unchanged.
    public func setRegionGain(id: UUID, _ gain: Float) {
        guard let i = document.regions.firstIndex(where: { $0.id == id }) else { return }
        let g = min(2, max(0, gain.isFinite ? gain : 1))
        guard document.regions[i].gain != g else { return }
        snapshotForUndo()
        document.regions[i].gain = g
        persist()
    }

    /// CLIP-4: write the audio-clip EDIT door's trimmed media window back to a
    /// placed region — content offset (file seconds, the audio authority; the
    /// tick twin follows so the two offsets never diverge) + musical length +
    /// the region's own gain (CLIP-6, clamped 0…2). The region's song position
    /// (startTick) stays — trimming the media never moves the clip in the song.
    /// No-op when nothing changed (no undo spam).
    public func setAudioRegionWindow(id: UUID, contentOffsetSeconds: Double,
                                     lengthTicks: Int, bpm: Double, gain: Float = 1) {
        guard let i = document.regions.firstIndex(where: { $0.id == id }) else { return }
        let offset = max(0, contentOffsetSeconds)
        let length = max(1, lengthTicks)
        let g = min(2, max(0, gain.isFinite ? gain : 1))
        guard document.regions[i].contentOffsetSeconds != offset
                || document.regions[i].lengthTicks != length
                || document.regions[i].gain != g else { return }
        snapshotForUndo()
        document.regions[i].contentOffsetSeconds = offset
        document.regions[i].contentOffsetTicks = TimelineTime.ticks(fromSeconds: offset, bpm: bpm)
        document.regions[i].lengthTicks = length
        document.regions[i].gain = g
        persist()
    }

    /// Trim/extend a region's LEADING edge to an absolute tick, holding the end fixed
    /// (front-trim; the media offset shifts so the content stays put). Caller applies snap.
    /// No-op if the start can't move (clamped by the region's own trimmedStart).
    public func trimRegionStart(id: UUID, toTick tick: Int, bpm: Double) {
        guard let i = document.regions.firstIndex(where: { $0.id == id }),
              let trimmed = document.regions[i].trimmedStart(toTick: tick, bpm: bpm) else { return }
        snapshotForUndo()
        document.regions[i] = trimmed
        persist()
    }

    // MARK: - Clip edit — split / merge (founder 2026-07-14 "Clips schneiden und zusammenfügen")

    /// Split the region `id` at an absolute tick into two abutting regions ("cut").
    /// No-op if the tick is at/outside the region's edges. `bpm` advances the second
    /// piece's media offset so audio/video plays seamlessly across the cut.
    public func splitRegion(id: UUID, atTick tick: Int, bpm: Double) {
        guard let i = document.regions.firstIndex(where: { $0.id == id }),
              let (first, second) = document.regions[i].split(at: tick, bpm: bpm) else { return }
        snapshotForUndo()
        document.regions[i] = first
        document.regions.append(second)
        persist()
    }

    /// Razor: split EVERY region the playhead crosses at `tick` (the DAW "split at
    /// playhead" gesture — no per-region selection needed). No-op if the tick is
    /// inside no region.
    public func splitRegions(atTick tick: Int, bpm: Double) {
        // Work on a local copy so the undo snapshot lands only when something splits.
        var regions = document.regions
        var newPieces: [TimelineRegion] = []
        for i in regions.indices {
            if let (first, second) = regions[i].split(at: tick, bpm: bpm) {
                regions[i] = first
                newPieces.append(second)
            }
        }
        guard !newPieces.isEmpty else { return }
        snapshotForUndo()
        document.regions = regions + newPieces
        persist()
    }

    /// Join at playhead: merge every pair of same-lane/clip regions that abut exactly
    /// at `tick` AND are media-contiguous (the inverse of the razor — rejoins pieces a
    /// split created there, but refuses if the second piece was trimmed/nudged, which
    /// `abuts` checks via `bpm`). No-op if no such pair meets at `tick`. Iterates to
    /// convergence so several lanes (or a chain) meeting at the tick all rejoin.
    public func mergeRegions(atTick tick: Int, bpm: Double) {
        var regions = document.regions
        var didMerge = false
        var changed = true
        while changed {
            changed = false
            outer: for a in regions.indices where regions[a].endTick == tick {
                for b in regions.indices where a != b && regions[a].abuts(regions[b], bpm: bpm) {
                    regions[a] = regions[a].merged(with: regions[b])
                    regions.remove(at: b)
                    didMerge = true; changed = true
                    break outer
                }
            }
        }
        guard didMerge else { return }
        snapshotForUndo()
        document.regions = regions
        persist()
    }

    /// Per-region "Join with next" (founder 2026-07-15: join from the clip's OWN
    /// long-press menu, not a separate toolbar razor). Merges region `id` with the
    /// same-lane/clip region that abuts right AFTER it AND is media-contiguous — the
    /// lossless inverse of a split. Only THIS region's join; other lanes are
    /// untouched (unlike the playhead-wide `mergeRegions`). No-op if nothing valid
    /// follows it (e.g. the next piece was trimmed/nudged → `abuts` refuses).
    public func mergeRegionWithNext(id: UUID, bpm: Double) {
        guard let ai = document.regions.firstIndex(where: { $0.id == id }) else { return }
        let a = document.regions[ai]
        guard let bi = document.regions.firstIndex(where: { $0.id != id && a.abuts($0, bpm: bpm) })
        else { return }
        let merged = a.merged(with: document.regions[bi])
        snapshotForUndo()
        document.regions.remove(at: bi)
        // Removal may have shifted `a`'s index — re-find by id before writing back.
        if let newAI = document.regions.firstIndex(where: { $0.id == id }) {
            document.regions[newAI] = merged
        }
        persist()
    }

    /// Combine SELECTED regions into one (clip game C3 — founder 2026-07-15A: "Wenn man
    /// mehrere Clips markiert soll auch combine gehen"). All must sit on the SAME lane
    /// AND reference the SAME clip (H12/M4 data-loss guard: the combined region keeps
    /// ONE clipID, so combining regions of DIFFERENT clips silently discarded every
    /// other clip's content from the span — refused now, and the UI verb disables via
    /// `canCombineRegions`). The result spans from the earliest start to the latest
    /// end and keeps the earliest region's identity/clip/media-offset (for split
    /// pieces this equals the lossless join; across gaps the one clip simply plays
    /// through the span). One history step. A true content-merge of different clips
    /// (time-shifted note union into a new clip) is a deliberate later cycle — it
    /// must allocate a clip slot and answer audio/video semantics first.
    public func combineRegions(ids: Set<UUID>) {
        guard canCombineRegions(ids: ids) else { return }
        let selected = document.regions.filter { ids.contains($0.id) }
        guard let earliest = selected.min(by: { $0.startTick < $1.startTick }),
              let endMax = selected.map(\.endTick).max() else { return }
        snapshotForUndo()
        var combined = earliest
        combined.lengthTicks = endMax - earliest.startTick
        document.regions.removeAll { ids.contains($0.id) }
        document.regions.append(combined)
        persist()
    }

    /// Whether the selection can combine losslessly: ≥2 regions, one lane, ONE clip.
    /// Pure read — drives the Combine button's enabled state so the guard above is
    /// legible, not a silent no-op.
    public func canCombineRegions(ids: Set<UUID>) -> Bool {
        let selected = document.regions.filter { ids.contains($0.id) }
        guard selected.count >= 2, let first = selected.first else { return false }
        return selected.allSatisfy { $0.laneID == first.laneID && $0.clipID == first.clipID }
    }

    /// Batch delete (clip game C3): remove every selected region in ONE history step.
    public func removeRegions(ids: Set<UUID>) {
        guard document.regions.contains(where: { ids.contains($0.id) }) else { return }
        snapshotForUndo()
        document.regions.removeAll { ids.contains($0.id) }
        persist()
    }

    /// Whether region `id` has a valid same-lane/clip successor to Join with — drives
    /// the enable/disable of the clip menu's "Join with next" verb. Pure read.
    public func canMergeRegionWithNext(id: UUID, bpm: Double) -> Bool {
        guard let a = document.regions.first(where: { $0.id == id }) else { return false }
        return document.regions.contains { $0.id != id && a.abuts($0, bpm: bpm) }
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
    /// lane's voice on load AND live per transport step (refreshMixer; CLIP-3 review).
    public func setLaneTranspose(id: UUID, _ semitones: Int) {
        guard let i = document.lanes.firstIndex(where: { $0.id == id }) else { return }
        document.lanes[i].transposeSemitones = max(-48, min(48, semitones))
        persist()
    }

    /// Per-instrument DETUNE in cents (founder 2026-07-14 "transpose detune"), clamped
    /// ±100 (±1 semitone) to match the voice. State only — the region player detunes
    /// each lane's voice on load AND live per step (refreshMixer), like transpose.
    public func setLaneDetune(id: UUID, _ cents: Float) {
        guard let i = document.lanes.firstIndex(where: { $0.id == id }) else { return }
        document.lanes[i].detuneCents = max(-100, min(100, cents.isFinite ? cents : 0))
        persist()
    }

    /// Per-instrument OKTAVER direction (founder 2026-07-14 "transpose detune und
    /// Oktaver"), clamped −1…+1 to match the voice (−1 sub-octave, +1 upper, 0 off).
    /// State only — the region player octaves each lane's voice on load AND live
    /// per step (refreshMixer), like transpose/detune.
    public func setLaneOctave(id: UUID, _ direction: Int) {
        guard let i = document.lanes.firstIndex(where: { $0.id == id }) else { return }
        document.lanes[i].octaveDouble = max(-1, min(1, direction))
        persist()
    }

    /// EchoelSampler track (S2-W3): assign (or clear, with nil) the persisted
    /// sample REF this lane's sampler unit plays ("drum:<Name>" / "lib:<Category>/
    /// <Name>" bundle refs, or a mediaRef-style absolute path — see
    /// TimelineLane.samplePath). State only, persisted like setLaneOctave; a
    /// change is STRUCTURAL (content identity, like patch/instrument), so the
    /// playing region player pulls it in via refreshStructure → prime →
    /// slotSampleSink, never through the mixer merge.
    public func setLaneSample(_ laneID: UUID, path: String?) {
        guard let i = document.lanes.firstIndex(where: { $0.id == laneID }) else { return }
        document.lanes[i].samplePath = path
        persist()
    }

    /// Per-instrument SYNTH PATCH (#23, founder: "each MIDI track carries its own
    /// optional SynthPatch"). Assign this lane's own timbre, or clear with nil =
    /// follow the shared/global melodic voice. State only, persisted like
    /// setLaneSample; a change is STRUCTURAL (what sounds changes — timbre
    /// identity), so the region player pulls it in via prime → slotPatchSink on
    /// the next region load (secondary lanes today; the primary-lane sink lands in
    /// S2b). NOT part of the region undo history (lane fields never are — undo
    /// touches only regions).
    public func setLanePatch(_ laneID: UUID, patch: SynthPatch?) {
        guard let i = document.lanes.firstIndex(where: { $0.id == laneID }) else { return }
        document.lanes[i].patch = patch
        persist()
    }

    // MARK: - Per-track composition (Slice A2 — founder 2026-07-17 "Genre, Sound,
    // Mix, FX, Mood, Synth kommt alles in ein Instrument")

    /// Assign (or clear, with nil) this lane's own GENRE — the per-track composer
    /// (LaneComposerInput, Slice A) then composes this lane in its own style
    /// against the same body take. nil = follow the song's global genre. State
    /// only, persisted like setLaneOctave; NOT part of the region undo history
    /// (lane fields never are — undo must not revert a composition choice).
    public func setLaneGenreOverride(_ laneID: UUID, genre: MusicStyle?) {
        guard let i = document.lanes.firstIndex(where: { $0.id == laneID }) else { return }
        document.lanes[i].genreOverride = genre
        persist()
    }

    /// Assign (or clear, with nil) this lane's own MOOD profile (the 8
    /// composition-character dimensions). nil = follow the song's global mood.
    public func setLaneMood(_ laneID: UUID, mood: MoodProfile?) {
        guard let i = document.lanes.firstIndex(where: { $0.id == laneID }) else { return }
        document.lanes[i].mood = mood
        persist()
    }

    /// Assign (or clear, with nil) this lane's own melodic VARIATION seed — the
    /// DETAIL seed the per-lane composer uses (the shared structure skeleton stays,
    /// so lanes remain voices of the same piece). The seed itself may come from a
    /// UI dice roll; the ENGINE stays deterministic because the rolled value is
    /// persisted here and replayed bit-identically. nil = follow the song.
    public func setLaneVariationSeed(_ laneID: UUID, seed: UInt64?) {
        guard let i = document.lanes.firstIndex(where: { $0.id == laneID }) else { return }
        document.lanes[i].variationSeed = seed
        persist()
    }

    /// Slice A2 — the EXPLICIT act that makes a lane's composition override
    /// audible: make sure the lane owns a composer-owned clip + a region inside
    /// the active loop window [0, loopBars×ticksPerBar), so the generate/evolve
    /// fan-out (`applyLaneOverrides` → `ClipStore.updateComposerMelody`, which
    /// only ever writes `composerOwned` clips) has somewhere to land its notes.
    /// Called from the track panel exactly when an override is set — generate()
    /// itself never invents regions.
    ///
    /// - Idempotent: a composer-owned clip region already inside the window ⇒
    ///   true, nothing created (a second override on the same lane reuses it).
    /// - Full clip grid ⇒ HONEST abort: returns false, logs, touches nothing —
    ///   user clips are never displaced (the never-clobber law).
    /// - MIDI, non-bio lanes only (the per-lane composer composes only those).
    /// - Undo: the region add goes through `addRegion` → ONE region undo step,
    ///   like every structural region edit. Undoing removes the region; the clip
    ///   stays in its slot (clip slots sit outside the region history, same as
    ///   the audio/video import paths).
    @discardableResult
    public func ensureComposerRegion(for laneID: UUID, clipStore: ClipStore,
                                     loopBars: Int,
                                     ticksPerBar: Int = TimelineTime.ticksPerBar) -> Bool {
        guard let lane = document.lanes.first(where: { $0.id == laneID }),
              lane.kind == .midi, !lane.isBio else { return false }
        let windowTicks = max(1, loopBars) * max(1, ticksPerBar)
        // Already provided for → done (idempotent).
        if document.regions(in: laneID).contains(where: { region in
            region.startTick < windowTicks
                && (clipStore.clip(id: region.clipID)?.composerOwned ?? false)
        }) {
            return true
        }
        guard let slot = clipStore.firstEmptySlotIndex else {
            log.log(.warning, category: .audio,
                    "ensureComposerRegion: clip grid full (\(ClipStore.slotCount) slots) — no composer clip for lane \(lane.name)")
            return false
        }
        let clip = Clip(name: "Composed · \(lane.name)", colorIndex: slot, kind: .midi,
                        melody: MelodyClip(notes: []), composerOwned: true)
        clipStore.setClip(at: slot, clip)
        addRegion(TimelineRegion(laneID: laneID, clipID: clip.id,
                                 startTick: 0, lengthTicks: windowTicks))
        log.log(.info, category: .audio,
                "ensureComposerRegion: created 'Composed · \(lane.name)' (slot \(slot), \(max(1, loopBars)) bars)")
        return true
    }

    /// H12 (founder v281 "Wo bleibt Midi Clip?"): the USER-clip twin of
    /// `ensureComposerRegion` — make sure a MIDI lane has a real, user-owned
    /// clip + region to edit when its track door opens. `addInstrumentTrack`
    /// creates ONLY the lane; without this, opening an EchoelDrums track fell
    /// back to the SHARED live-take roll (poly voice — "keine Drums sondern
    /// irgendwelche Töne"), because the kit routing only runs in region
    /// playback (slotKindSink), which never runs without a region.
    ///
    /// - Lane already has ANY region ⇒ return its FIRST MIDI region, create
    ///   nothing (never a duplicate; nil if none of its regions is MIDI).
    /// - Else: clip "MIDI · <lane>" (kind .midi, empty melody,
    ///   `composerOwned: false` — this is THE USER'S clip, generate/evolve
    ///   may never rewrite it) in the first free slot + a region spanning
    ///   [0, loopBars×ticksPerBar) via `addRegion` (ONE region undo step).
    /// - Full clip grid ⇒ HONEST nil + warning — user clips are never
    ///   displaced (the never-clobber law).
    /// - MIDI, non-bio lanes only.
    public func ensureUserMidiRegion(for laneID: UUID, clipStore: ClipStore,
                                     loopBars: Int,
                                     ticksPerBar: Int = TimelineTime.ticksPerBar) -> TimelineRegion? {
        guard let lane = document.lanes.first(where: { $0.id == laneID }),
              lane.kind == .midi, !lane.isBio else { return nil }
        let laneRegions = document.regions(in: laneID)
        if !laneRegions.isEmpty {
            return laneRegions.first { clipStore.clip(id: $0.clipID)?.kind == .midi }
        }
        guard let slot = clipStore.firstEmptySlotIndex else {
            log.log(.warning, category: .audio,
                    "ensureUserMidiRegion: clip grid full (\(ClipStore.slotCount) slots) — no MIDI clip for lane \(lane.name)")
            return nil
        }
        let clip = Clip(name: "MIDI · \(lane.name)", colorIndex: slot, kind: .midi,
                        melody: MelodyClip(notes: []), composerOwned: false)
        clipStore.setClip(at: slot, clip)
        let region = TimelineRegion(laneID: laneID, clipID: clip.id,
                                    startTick: 0,
                                    lengthTicks: max(1, loopBars) * max(1, ticksPerBar))
        addRegion(region)
        log.log(.info, category: .audio,
                "ensureUserMidiRegion: created 'MIDI · \(lane.name)' (slot \(slot), \(max(1, loopBars)) bars)")
        return region
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

    /// #22 follow-up: restore the shared roll slot's audibility for an explicit
    /// user Start (see TimelineDocument.healRollSlotAudibility). Persists (and
    /// thereby notifies every mixer mirror) only when something changed.
    /// Mixer state sits outside the region undo history by design — the heal
    /// is the user's own Start intent, not an edit to revert.
    @discardableResult
    public func healRollSlotAudibility() -> Bool {
        guard document.healRollSlotAudibility() else { return false }
        persist()
        return true
    }

    /// Remove an EMPTY lane (regions must move/delete first — no silent data loss).
    public func removeLaneIfEmpty(id: UUID) {
        guard document.regions(in: id).isEmpty else { return }
        document.lanes.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Arrangement automation (T1 — inline timeline automation row)
    // `document.automation` is the song-ABSOLUTE automation layer (480-PPQ ticks,
    // same base as regions). Playback is already wired: TimelineRegionPlayer
    // pushes these lanes into AutomationPlayer's timeline layer on play() AND on
    // every structural refresh — and an automation change IS structural
    // (`structurallyEqual` compares it), so a persisted edit here reaches a
    // playing song via the existing refreshStructure path. These were the FIRST
    // writers of the field (until T1 it was play-only scaffolding).
    //
    // UNDO: deliberately OUTSIDE the region undo history — the undo stack
    // snapshots ONLY `document.regions` (see snapshotForUndo's contract), so
    // automation edits are not undoable today. Documented limit, not extended
    // here (extending the history to a second field would cross-contaminate
    // region undo — the exact hazard that contract exists to prevent).

    /// Lane index for a parameter, matched under EITHER identity (legacy enum
    /// rawValue or registry keyPath alias) so "masterLevel" and
    /// "master.amp.level" can never split into two lanes.
    private func automationLaneIndex(forParameter parameter: String) -> Int? {
        document.automation.firstIndex {
            TimelineAutomationRowMath.sameParameter($0.parameter, parameter)
        }
    }

    /// The song-absolute automation lane for a parameter (alias-aware). nil =
    /// no lane yet (the first added point creates it).
    public func automationLane(forParameter parameter: String) -> AutomationLane? {
        automationLaneIndex(forParameter: parameter).map { document.automation[$0] }
    }

    /// Add a keyframe at a song-absolute tick (normalized value 0…1). Creates
    /// the lane on first use — the inline row's empty-state tap lands here.
    @discardableResult
    public func addAutomationPoint(parameter: String, tick: Int,
                                   value: Double) -> AutomationPoint? {
        guard !parameter.isEmpty else { return nil }
        let idx: Int
        if let existing = automationLaneIndex(forParameter: parameter) {
            idx = existing
        } else {
            document.automation.append(AutomationLane(parameter: parameter))
            idx = document.automation.count - 1
        }
        let p = document.automation[idx].addPoint(tick: max(0, tick), value: value)
        persist()
        return p
    }

    /// Move + revalue a keyframe in one committed gesture (the row's point-drag
    /// commits ONCE on release — never per drag frame: each persist here is a
    /// structural change, and a per-frame commit would relocate-storm a playing
    /// song; HARNESS_LEDGER 2026-07-16).
    public func moveAutomationPoint(parameter: String, id: UUID, toTick tick: Int,
                                    normalized value: Double) {
        guard let i = automationLaneIndex(forParameter: parameter) else { return }
        document.automation[i].movePoint(id: id, toTick: max(0, tick))
        document.automation[i].setValue(id: id, value)
        persist()
    }

    /// Remove a keyframe; a lane emptied by the removal is dropped entirely
    /// (no ghost lanes in the document — the row's empty state returns).
    public func removeAutomationPoint(parameter: String, id: UUID) {
        guard let i = automationLaneIndex(forParameter: parameter) else { return }
        document.automation[i].removePoint(id: id)
        if document.automation[i].isEmpty { document.automation.remove(at: i) }
        persist()
    }

    // MARK: Precision edits (S1 — the deep editor authors THIS store, not the
    // loop layer). Value-only / curve / curvature mirror AutomationPlayer's
    // per-keyframe ops but on the song-absolute document lane, so the precision
    // sheet and the inline row edit ONE curve. Each commits once (structural
    // persist, HARNESS_LEDGER relocate-storm law). Unknown parameter/id = no-op.

    /// Revalue a keyframe in place (no tick change) — the precision editor's typed
    /// value field and its vertical point-drag land here.
    public func setAutomationValue(parameter: String, id: UUID, normalized value: Double) {
        guard let i = automationLaneIndex(forParameter: parameter) else { return }
        document.automation[i].setValue(id: id, value)
        persist()
    }

    /// Set a keyframe's segment shape (Linear glide vs Hold step).
    public func setAutomationCurve(parameter: String, id: UUID, _ curve: AutomationCurve) {
        guard let i = automationLaneIndex(forParameter: parameter) else { return }
        document.automation[i].setCurve(id: id, curve)
        persist()
    }

    /// Bend the segment leaving a keyframe (the canvas' vertical between-points drag).
    public func setAutomationCurvature(parameter: String, id: UUID, _ curvature: Double) {
        guard let i = automationLaneIndex(forParameter: parameter) else { return }
        document.automation[i].setCurvature(id: id, curvature)
        persist()
    }

    /// Clear a parameter's automation entirely — the lane is dropped (no ghost
    /// lanes; matches the precision sheet's "Clear" and removeAutomationPoint's
    /// empty-lane contract).
    public func clearAutomation(parameter: String) {
        guard let i = automationLaneIndex(forParameter: parameter) else { return }
        document.automation.remove(at: i)
        persist()
    }

    // MARK: - Persistence

    /// H5b: fires after EVERY persisted document change (assignment edits, lane
    /// removal, undo/redo — all mutation paths funnel through persist), so the
    /// app can reconcile per-lane hosted AU instruments. The consumer must be
    /// cheap + idempotent (LaneAUInstrumentHost.syncAssignments is a dict diff).
    @ObservationIgnored public var onDocumentChanged: (() -> Void)?

    private func persist() {
        try? store.save(document, name: Self.fileName)
        onDocumentChanged?()
    }
}
