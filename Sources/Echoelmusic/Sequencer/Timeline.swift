// Timeline.swift
// Echoel — the song-absolute beat-grid data model (approved Arrange-timeline
// plan, Stage 1). Pure value types; persists as JSON via AppGroupStore.
//
// TIME MODEL: song-absolute ticks, Int, 480 PPQ (= Note.ticksPerQuarter — ONE
// musical resolution app-wide for content; Transport's 24-ppq position converts
// via `ticksPerTransportStep`). "Stufenlos" (stepless) positioning is
// tick-precise: at 120 BPM one tick ≈ 1 ms — effectively continuous, yet exact,
// Codable without float drift, and snap-exact when a region IS on the grid.
//
// Regions reference the existing `Clip` (which already carries
// kind: midi/audio/video/visual + mediaRef) — one media model, no parallel type.

import Foundation

/// One horizontal lane on the arrange timeline. `kind` reuses `ClipKind` for
/// media lanes; `isBio` marks the biofeedback automation lane (founder
/// 2026-07-09: "Bio-Spur aufs Grid — ja").
public struct TimelineLane: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: ClipKind
    /// True for the bio lane: it renders an automation curve (recorded from
    /// EngineBus bio frames) instead of media regions.
    public var isBio: Bool
    /// K2a mixer strip (persisted with the document): fader gain 0…2, 1 = unity.
    public var level: Float
    public var isMuted: Bool
    public var isSoloed: Bool
    /// B2 stereo position: −1 (hard left) … +1 (hard right), 0 = center.
    public var pan: Float
    /// U3 AUv3-structure: the plugin this track plays through. `instrument` is the
    /// MIDI voice (nil = internal/unset); `effects` is the ordered insert chain.
    /// Pure persisted DATA — the engine routing to per-lane voices arrives with
    /// multi-roll; this is the honest model + the display foundation for the
    /// founder's "sichtbare Instrument/FX-Belegung pro Spur".
    public var instrument: AUPluginRef?
    public var effects: [AUPluginRef]
    /// The built-in Echoel instrument this track plays (founder 2026-07-13:
    /// "EchoelDrums, Echoelbreak, EchoelSampler etc"). `nil` = a plain MIDI/audio
    /// lane with no assigned voice. Drives the track name/icon + its record source.
    public var builtinInstrument: TrackInstrument?
    /// Record-arm: this track is armed to capture its input on the next take
    /// (founder: "jede Spur soll ein record Button haben"). Persisted intent —
    /// the per-source capture engine reads it; arming never records by itself.
    public var isArmed: Bool
    /// Per-track EchoelSynth sound (founder 2026-07-14: "Sound und texture wird
    /// auch Teil von Echoel Synth" + "alles in Instrumente aufgeteilt … optional
    /// anschalten"). `nil` = the track uses today's global sound (no behavior
    /// change); a set patch is this lane's own voice character. Persisted DATA —
    /// the composer/voice wiring (LaneVoiceRack) applies it in a follow-up module;
    /// this is the additive foundation, bit-identical while nil.
    public var patch: SynthPatch?
    /// Per-track COMPOSITION group (founder 2026-07-14: "Genre und Variation pro MIDI-
    /// Spur einzeln … Mood kommt zu Genre und Variationen"). Each `nil` = the track
    /// follows the GLOBAL composition choice (no behavior change); when set, the
    /// per-lane composer composes THIS lane in its own genre / mood / variation, so
    /// several genres sound at once. Persisted DATA — the per-lane composer wiring
    /// lands in a follow-up module; additive/bit-identical while all nil.
    public var genreOverride: MusicStyle?
    public var mood: MoodProfile?
    public var variationSeed: UInt64?
    /// Per-instrument TRANSPOSE in whole semitones (founder 2026-07-14: "Wenn einzelne
    /// Instrumenten Elemente im synth nen transpose Button haben ist das kool"). Shifts
    /// THIS lane's SOUNDING pitch (e.g. bass −12, a layer +7) on the voice's MIDI→Hz
    /// path — non-destructive: the written notes keep their pitch, only the rendered
    /// frequency moves. 0 = no shift (bit-identical). Persisted DATA; the voice wiring
    /// reads it per lane (primary lane via `rollTransposeSink`, secondary lanes via
    /// `slotTransposeSink`).
    public var transposeSemitones: Int
    /// Per-instrument DETUNE in cents (founder 2026-07-14: "transpose detune und Oktaver").
    /// The FINE-pitch twin of `transposeSemitones` (which is whole semitones): a small
    /// continuous offset (±100¢ = ±1 semitone) folded into the SAME voice MIDI→Hz path,
    /// so a lane can sit a few cents sharp/flat for analog-style thickening or a beating
    /// detune against another lane. Non-destructive (written notes keep their pitch);
    /// 0 = no detune (bit-identical). Persisted DATA; read per lane like transpose
    /// (primary via `rollDetuneSink`, secondary via `slotDetuneSink`).
    public var detuneCents: Float

    public init(id: UUID = UUID(), name: String, kind: ClipKind, isBio: Bool = false,
                level: Float = 1, isMuted: Bool = false, isSoloed: Bool = false,
                pan: Float = 0, instrument: AUPluginRef? = nil, effects: [AUPluginRef] = [],
                builtinInstrument: TrackInstrument? = nil, isArmed: Bool = false,
                patch: SynthPatch? = nil, genreOverride: MusicStyle? = nil,
                mood: MoodProfile? = nil, variationSeed: UInt64? = nil,
                transposeSemitones: Int = 0, detuneCents: Float = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isBio = isBio
        self.level = level
        self.isMuted = isMuted
        self.isSoloed = isSoloed
        self.pan = pan
        self.instrument = instrument
        self.effects = effects
        self.builtinInstrument = builtinInstrument
        self.isArmed = isArmed
        self.patch = patch
        self.genreOverride = genreOverride
        self.mood = mood
        self.variationSeed = variationSeed
        self.transposeSemitones = transposeSemitones
        self.detuneCents = detuneCents
    }

    /// What this track's record button captures — derived from its kind + built-in
    /// instrument (founder: "Audio für Audio Inputs, Midi für Midi Input die
    /// Biofeedback Instrumente"). Pure; the capture engine per source lands next.
    public var recordSource: RecordSource {
        if isBio { return .bio }
        if let inst = builtinInstrument { return inst.recordSource }
        switch kind {
        case .midi:   return .midiInput
        case .audio:  return .audioInput
        case .video:  return .videoCapture
        case .visual: return .none
        }
    }

    /// Backward-compatible decode: documents stored before the K2a mixer strip
    /// carry no mix keys — they decode to unity/unmuted, not a decode failure.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(ClipKind.self, forKey: .kind)
        isBio = try c.decodeIfPresent(Bool.self, forKey: .isBio) ?? false
        level = try c.decodeIfPresent(Float.self, forKey: .level) ?? 1
        isMuted = try c.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isSoloed = try c.decodeIfPresent(Bool.self, forKey: .isSoloed) ?? false
        pan = try c.decodeIfPresent(Float.self, forKey: .pan) ?? 0   // pre-B2 docs: center
        instrument = try c.decodeIfPresent(AUPluginRef.self, forKey: .instrument)
        effects = try c.decodeIfPresent([AUPluginRef].self, forKey: .effects) ?? []
        // Pre-2026-07-13 docs carry no instrument/arm keys — decode to unset/disarmed.
        builtinInstrument = try c.decodeIfPresent(TrackInstrument.self, forKey: .builtinInstrument)
        isArmed = try c.decodeIfPresent(Bool.self, forKey: .isArmed) ?? false
        // Pre-2026-07-14 docs carry no per-track patch — decode to nil (global sound).
        patch = try c.decodeIfPresent(SynthPatch.self, forKey: .patch)
        // Per-track composition group (genre/mood/variation) — absent in older docs ⇒
        // nil = follow the global composition choice.
        genreOverride = try c.decodeIfPresent(MusicStyle.self, forKey: .genreOverride)
        mood = try c.decodeIfPresent(MoodProfile.self, forKey: .mood)
        variationSeed = try c.decodeIfPresent(UInt64.self, forKey: .variationSeed)
        // Pre-2026-07-14 docs carry no per-track transpose ⇒ 0 (no shift, bit-identical).
        transposeSemitones = try c.decodeIfPresent(Int.self, forKey: .transposeSemitones) ?? 0
        // Pre-2026-07-14 docs carry no per-track detune ⇒ 0 (no offset, bit-identical).
        detuneCents = try c.decodeIfPresent(Float.self, forKey: .detuneCents) ?? 0
    }
}

/// A placed region: `clipID` resolves content via `ClipStore`; position/length
/// are song-absolute 480-PPQ ticks. For audio/video, `contentOffsetSeconds`
/// trims into the media (same semantics as `AudioClipRegion.startSeconds`).
public struct TimelineRegion: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var laneID: UUID
    public var clipID: UUID
    public var startTick: Int
    public var lengthTicks: Int
    public var contentOffsetSeconds: Double
    /// Trim-in in TICKS — the MIDI twin of `contentOffsetSeconds` (M1b reviewer
    /// HIGH): seconds are the right domain for MEDIA (audio/video files play in
    /// real time), but MIDI content lives in ticks, and a seconds-stored trim
    /// re-converted at PLAY-time tempo shifts the note window whenever the tempo
    /// changed since the edit (split @120 → play @112 = 128 ticks off). Split and
    /// front-trim maintain BOTH fields; MIDI playback reads this one (exact at any
    /// tempo), media playback keeps reading seconds. Legacy regions decode as 0 —
    /// consumers fall back to the seconds conversion for them.
    public var contentOffsetTicks: Int

    public init(id: UUID = UUID(), laneID: UUID, clipID: UUID,
                startTick: Int, lengthTicks: Int, contentOffsetSeconds: Double = 0,
                contentOffsetTicks: Int = 0) {
        self.id = id
        self.laneID = laneID
        self.clipID = clipID
        self.startTick = max(0, startTick)
        self.lengthTicks = max(1, lengthTicks)
        self.contentOffsetSeconds = max(0, contentOffsetSeconds)
        self.contentOffsetTicks = max(0, contentOffsetTicks)
    }

    private enum CodingKeys: String, CodingKey {
        case id, laneID, clipID, startTick, lengthTicks, contentOffsetSeconds
        case contentOffsetTicks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        laneID = try c.decode(UUID.self, forKey: .laneID)
        clipID = try c.decode(UUID.self, forKey: .clipID)
        startTick = max(0, try c.decode(Int.self, forKey: .startTick))
        lengthTicks = max(1, try c.decode(Int.self, forKey: .lengthTicks))
        contentOffsetSeconds = max(0, (try? c.decode(Double.self, forKey: .contentOffsetSeconds)) ?? 0)
        // Legacy regions (pre-M1b) carry no tick offset — 0 signals "fall back to
        // the seconds conversion" to consumers.
        contentOffsetTicks = max(0, (try? c.decode(Int.self, forKey: .contentOffsetTicks)) ?? 0)
    }

    public var endTick: Int { startTick + lengthTicks }

    /// Split this region at an ABSOLUTE tick into two abutting pieces (clip edit —
    /// "cut"). Returns nil when `tick` is not strictly inside (`startTick < tick <
    /// endTick`) — a split at an edge is a no-op. The first piece keeps this region's
    /// identity (shortened); the second gets a fresh id, starts at `tick`, and
    /// advances `contentOffsetSeconds` by the elapsed media time so audio/video plays
    /// seamlessly across the cut (MIDI, offset 0, is unaffected). Pure + testable.
    public func split(at tick: Int, bpm: Double) -> (TimelineRegion, TimelineRegion)? {
        guard tick > startTick, tick < endTick else { return nil }
        var first = self
        first.lengthTicks = tick - startTick
        var second = self
        second.id = UUID()
        second.startTick = tick
        second.lengthTicks = endTick - tick
        second.contentOffsetSeconds = contentOffsetSeconds
            + TimelineTime.seconds(fromTicks: tick - startTick, bpm: bpm)
        // Tick twin, maintained in the tick domain directly — exact at any tempo.
        second.contentOffsetTicks = contentOffsetTicks + (tick - startTick)
        return (first, second)
    }

    /// Trim or extend the LEADING edge to an absolute `newStart` tick, holding the END
    /// fixed (front-trim — founder 2026-07-15 "nicht nur hinten … sondern auch vorne").
    /// The media offset shifts by the moved distance so the content under the clip stays
    /// put (the reverse of `split`'s offset advance): dragging the left edge RIGHT trims
    /// the front and advances `contentOffsetSeconds`; dragging it LEFT reveals earlier
    /// media and reduces the offset. Clamped so the clip keeps ≥ 1 tick, never starts
    /// before tick 0, and never reveals media before its own start (offset ≥ 0 — so a
    /// MIDI/offset-0 region can only trim, not front-extend). Returns nil when the start
    /// doesn't move. Pure + testable.
    public func trimmedStart(toTick newStart: Int, bpm: Double) -> TimelineRegion? {
        let offsetTicks = TimelineTime.ticks(fromSeconds: contentOffsetSeconds, bpm: bpm)
        let minStart = Swift.max(0, startTick - offsetTicks)   // extending left bottoms out at the media start
        let maxStart = endTick - 1                             // keep ≥ 1 tick
        guard maxStart >= minStart else { return nil }
        let clampedStart = Swift.min(Swift.max(newStart, minStart), maxStart)
        guard clampedStart != startTick else { return nil }
        var r = self
        r.startTick = clampedStart
        r.lengthTicks = endTick - clampedStart
        r.contentOffsetSeconds = Swift.max(0, contentOffsetSeconds
            + TimelineTime.seconds(fromTicks: clampedStart - startTick, bpm: bpm))
        // Tick twin, maintained in the tick domain directly — exact at any tempo.
        r.contentOffsetTicks = Swift.max(0, contentOffsetTicks + (clampedStart - startTick))
        return r
    }

    /// Whether `other` abuts this region on the SAME lane + clip (this region's end
    /// meets the other's start) AND is contiguous IN THE MEDIA — the mergeable case
    /// (the undo of a split). Regions of DIFFERENT clips never merge (which content
    /// would win is undefined). The media-offset check makes Join lossless: a clean
    /// split advances the second piece's `contentOffsetSeconds` by exactly this
    /// elapsed time, so it always passes; but if the user then trims/nudges that
    /// piece, the offsets no longer line up and Join correctly refuses (rejoining
    /// would silently drop the trim). `bpm` converts this region's length to seconds.
    public func abuts(_ other: TimelineRegion, bpm: Double) -> Bool {
        guard laneID == other.laneID, clipID == other.clipID, endTick == other.startTick
        else { return false }
        let expectedOffset = contentOffsetSeconds
            + TimelineTime.seconds(fromTicks: lengthTicks, bpm: bpm)
        return abs(other.contentOffsetSeconds - expectedOffset) < 1e-6
    }

    /// Merge `other` (which must `abuts` this) into one region spanning both — keeps
    /// this region's id + `contentOffsetSeconds` (its media start). Pure + testable.
    public func merged(with other: TimelineRegion) -> TimelineRegion {
        var r = self
        r.lengthTicks = other.endTick - startTick
        return r
    }

    /// A copy of this region with a FRESH identity, placed at `startTick` (default:
    /// right AFTER this region, i.e. its `endTick`). Same lane, clip, length and
    /// media offset — the duplicate plays identical content, just later on the grid.
    /// Regions may share a `clipID`, so duplicating needs no new clip slot. Pure.
    public func duplicated(atStartTick tick: Int? = nil) -> TimelineRegion {
        var copy = self
        copy.id = UUID()
        copy.startTick = max(0, tick ?? endTick)
        return copy
    }
}

/// The whole timeline document: ordered lanes + their regions.
public struct TimelineDocument: Codable, Sendable, Equatable {
    public var lanes: [TimelineLane]
    public var regions: [TimelineRegion]
    /// Parameter automation for the ARRANGEMENT (automation-in-track cycle 5).
    /// Ticks are song-ABSOLUTE (480-PPQ, same base as regions), so a lane is the
    /// authoritative curve a parameter follows across the whole song. Played back
    /// via the timeline player's absolute playhead; wins over global loop + clip
    /// automation while the song plays.
    public var automation: [AutomationLane]

    public init(lanes: [TimelineLane] = [], regions: [TimelineRegion] = [],
                automation: [AutomationLane] = []) {
        self.lanes = lanes
        self.regions = regions
        self.automation = automation
    }

    private enum CodingKeys: String, CodingKey { case lanes, regions, automation }

    /// Backward-compatible decode: documents saved before the automation field
    /// (or before any given key) load with empty defaults, never a decode failure.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lanes = try c.decodeIfPresent([TimelineLane].self, forKey: .lanes) ?? []
        regions = try c.decodeIfPresent([TimelineRegion].self, forKey: .regions) ?? []
        automation = try c.decodeIfPresent([AutomationLane].self, forKey: .automation) ?? []
    }

    public func regions(in laneID: UUID) -> [TimelineRegion] {
        regions.filter { $0.laneID == laneID }.sorted { $0.startTick < $1.startTick }
    }

    /// Total song length in ticks (end of the last region; ≥ 0).
    public var endTick: Int { regions.map(\.endTick).max() ?? 0 }

    /// The tick at which a newly-imported clip should START on `laneID` so it
    /// sits AFTER the lane's existing content (no overlap) — the end of the
    /// lane's last region, or 0 for an empty lane. Pure; the audio/video import
    /// path appends here so repeated imports stack in time.
    public func nextStartTick(inLane laneID: UUID) -> Int {
        regions(in: laneID).map(\.endTick).max() ?? 0
    }

    // MARK: - Lane mixer math (K2a — pure, Linux-CI-tested)

    /// A lane's audible gain: 0 when muted (mute wins over its own solo) or when
    /// any OTHER lane is soloed and this one isn't; otherwise its fader level,
    /// clamped 0…2. Unknown lane → 0 (nothing to hear).
    public func effectiveGain(for laneID: UUID) -> Float {
        guard let lane = lanes.first(where: { $0.id == laneID }) else { return 0 }
        if lane.isMuted { return 0 }
        if lanes.contains(where: { $0.isSoloed }) && !lane.isSoloed { return 0 }
        return max(0, min(2, lane.level))
    }

    /// The gain the ONE shared Piano-Roll slot plays at: the first non-bio MIDI
    /// lane owns the roll until A1 (multi-roll) gives every MIDI lane its own.
    /// No MIDI lane → unity (the roll is not represented on the timeline).
    public var rollSlotGain: Float {
        guard let lane = lanes.first(where: { $0.kind == .midi && !$0.isBio }) else { return 1 }
        return effectiveGain(for: lane.id)
    }

    /// #22 follow-up (founder log v255: `generate[start] … rollMixGain=0.00`
    /// then a 15 s silent session and an exit): make the ONE shared roll slot
    /// audible again for an explicit user Start. ONE law, not two (review
    /// MEDIUM): this is a gated DELEGATE to `unsilenceRollSlot` — the same
    /// heal the #22 "Ton an" banner button applies — so Start and the banner
    /// can never drift. The gate uses the codebase-wide ≤ 0.001 audibility
    /// threshold (review MEDIUM: `== 0` left a crack — a persisted 0.0005
    /// level was gated silent everywhere yet refused the heal). Returns true
    /// when anything changed. Callers invoke this ONLY on an explicit user
    /// Start — tapping Start IS the intent "I want to hear it"; automatic
    /// paths (evolve/re-seed) must never rewrite the mix.
    public mutating func healRollSlotAudibility() -> Bool {
        guard lanes.contains(where: { $0.kind == .midi && !$0.isBio }),
              rollSlotGain <= 0.001 else { return false }
        let before = self
        unsilenceRollSlot()
        return self != before
    }

    /// The stereo position the ONE shared Piano-Roll slot plays at (B2 — the
    /// rollSlotGain mirror for pan). Clamped −1…1; mute/solo do NOT touch pan
    /// (audibility is gain's job). No MIDI lane → center.
    public var rollSlotPan: Float {
        guard let lane = lanes.first(where: { $0.kind == .midi && !$0.isBio }) else { return 0 }
        return max(-1, min(1, lane.pan))
    }

    /// The whole-semitone TRANSPOSE the ONE shared Piano-Roll slot plays at (the
    /// rollSlotPan mirror for pitch — founder 2026-07-14 per-instrument Transpose).
    /// Clamped ±48; no MIDI lane → 0 (no shift). The surface's onChange pushes it into
    /// both melodic voices live, so a primary-lane transpose edit is heard immediately.
    public var rollSlotTranspose: Int {
        guard let lane = lanes.first(where: { $0.kind == .midi && !$0.isBio }) else { return 0 }
        return max(-48, min(48, lane.transposeSemitones))
    }

    /// The fine DETUNE in cents the ONE shared Piano-Roll slot plays at (the
    /// rollSlotTranspose twin for cents — founder 2026-07-14 "transpose detune").
    /// Clamped ±100¢; no MIDI lane → 0. The surface's onChange pushes it into both
    /// melodic voices live, so a primary-lane detune edit is heard immediately.
    public var rollSlotDetune: Float {
        guard let lane = lanes.first(where: { $0.kind == .midi && !$0.isBio }) else { return 0 }
        return max(-100, min(100, lane.detuneCents))
    }

    /// Why the roll-slot lane is INAUDIBLE (nil = audible), so the UI can explain a
    /// silent generative instrument in plain words. Founder 2026-07-14 ("alles ist
    /// still", verified from the device log): the generative melody plays through the
    /// first MIDI lane, and a MUTED "MIDI 1" (or a foreign solo, or a 0 fader) gated
    /// every noteOn off with no visible reason — the classic silent-instrument trap.
    /// Mirrors `effectiveGain`'s precedence exactly (mute > foreign-solo > level).
    public enum RollSilenceReason: String, Sendable, Equatable {
        case muted, otherSoloed, levelZero
    }

    public var rollSlotSilenceReason: RollSilenceReason? {
        guard let lane = lanes.first(where: { $0.kind == .midi && !$0.isBio }) else { return nil }
        if lane.isMuted { return .muted }
        if lanes.contains(where: { $0.isSoloed }) && !lane.isSoloed { return .otherSoloed }
        if lane.level <= 0.001 { return .levelZero }
        return nil
    }

    /// One-tap "make the generative instrument audible again": unmute the roll-slot
    /// lane, lift a zeroed fader back to unity, and clear any OTHER lane's solo (the
    /// user explicitly asked to hear the instrument). No-op when already audible or
    /// when there is no MIDI lane. Idempotent.
    public mutating func unsilenceRollSlot() {
        guard let idx = lanes.firstIndex(where: { $0.kind == .midi && !$0.isBio }) else { return }
        lanes[idx].isMuted = false
        if lanes[idx].level <= 0.001 { lanes[idx].level = 1 }
        for i in lanes.indices where i != idx && lanes[i].isSoloed { lanes[i].isSoloed = false }
    }

    /// H4 (live mixer while playing): merge ONLY the sink-applied per-lane voice
    /// fields (mute/solo/level/pan + transpose/detune — CLIP-3 review) from
    /// `fresh` into this document, matched by lane id. Lane membership,
    /// order, regions and every other field stay untouched — the region player's
    /// playback snapshot must keep its lane ranks stable (its pumps are rank-keyed),
    /// so a mid-play lane add/remove in `fresh` is deliberately IGNORED here.
    /// KNOWN ASYMMETRY (accepted): a lane ADDED and soloed mid-play never enters the
    /// snapshot, so its solo cannot gate the playing lanes — consistent with the
    /// structure freeze (that lane can't sound until restart either).
    /// Returns true when anything changed (the caller re-pushes gains/pans then).
    public mutating func mergeMixer(from fresh: TimelineDocument) -> Bool {
        var changed = false
        for i in lanes.indices {
            guard let live = fresh.lanes.first(where: { $0.id == lanes[i].id }) else {
                // Snapshot lane DELETED from the store mid-play: its stale solo would
                // otherwise keep every OTHER lane at effectiveGain 0 until stop while
                // the UI shows no solo anywhere (review MEDIUM). Membership stays
                // ignored, but the cross-lane solo bit must reconcile.
                if lanes[i].isSoloed { lanes[i].isSoloed = false; changed = true }
                continue
            }
            if lanes[i].isMuted != live.isMuted { lanes[i].isMuted = live.isMuted; changed = true }
            if lanes[i].isSoloed != live.isSoloed { lanes[i].isSoloed = live.isSoloed; changed = true }
            if lanes[i].level != live.level { lanes[i].level = live.level; changed = true }
            if lanes[i].pan != live.pan { lanes[i].pan = live.pan; changed = true }
            // CLIP-3 review: transpose/detune are sink-applied per-lane voice fields
            // exactly like pan — they flow LIVE here, never through a relocate (a
            // scrub during playback must not flush voices at ~8 Hz).
            if lanes[i].transposeSemitones != live.transposeSemitones {
                lanes[i].transposeSemitones = live.transposeSemitones; changed = true
            }
            if lanes[i].detuneCents != live.detuneCents {
                lanes[i].detuneCents = live.detuneCents; changed = true
            }
        }
        return changed
    }

    /// CLIP-3: true when `a` and `b` differ at most in NON-SOUND-STRUCTURAL state —
    /// the per-lane fields `mergeMixer` flows per step (mute/solo/level/pan +
    /// transpose/detune, all sink-applied to the lane's voice without a reload)
    /// plus lane rename and record-arm. Everything that changes WHAT sounds at a tick counts
    /// as structural: region set (move/trim/split/delete/add), lane membership,
    /// ORDER (pump ranks!), kind/instrument, and the automation lanes. The playing
    /// TimelineRegionPlayer relocates only on a structural change; mixer-only edits
    /// keep flowing through the cheap merge (no voice re-attack). Pure — tested.
    public static func structurallyEqual(_ a: TimelineDocument, _ b: TimelineDocument) -> Bool {
        guard a.regions == b.regions, a.automation == b.automation,
              a.lanes.count == b.lanes.count else { return false }
        for (la, lb) in zip(a.lanes, b.lanes) {
            var n = la
            n.isMuted = lb.isMuted
            n.isSoloed = lb.isSoloed
            n.level = lb.level
            n.pan = lb.pan
            n.name = lb.name
            n.isArmed = lb.isArmed
            n.transposeSemitones = lb.transposeSemitones
            n.detuneCents = lb.detuneCents
            if n != lb { return false }
        }
        return true
    }
}

// MARK: - Musical constants + conversions

public enum TimelineTime {
    /// One shared content resolution: 480 ticks per quarter (Note's PPQ).
    public static let ticksPerQuarter = Note.ticksPerQuarter          // 480
    public static let ticksPerBeat = ticksPerQuarter                  // 4/4: beat = quarter
    public static let beatsPerBar = 4
    public static let ticksPerBar = ticksPerBeat * beatsPerBar        // 1920
    /// Transport publishes 16th-note steps; one step = 120 content ticks.
    public static let ticksPerTransportStep = ticksPerQuarter / 4     // 120

    /// Transport's absolute step (bar*16+step) → song-absolute content tick.
    public static func tick(fromAbsoluteStep step: Int) -> Int {
        step * ticksPerTransportStep
    }

    /// Ticks → seconds at a tempo (for sample-accurate audio scheduling).
    public static func seconds(fromTicks ticks: Int, bpm: Double) -> Double {
        guard bpm > 0 else { return 0 }
        return Double(ticks) / Double(ticksPerQuarter) * (60.0 / bpm)
    }

    /// Seconds → ticks at a tempo (the inverse of `seconds(fromTicks:)`, rounded).
    /// Used by front-trim to convert a media offset into the furthest the leading edge
    /// may extend left without revealing media before its start.
    public static func ticks(fromSeconds seconds: Double, bpm: Double) -> Int {
        guard bpm > 0 else { return 0 }
        return Int((seconds * bpm / 60.0 * Double(ticksPerQuarter)).rounded())
    }
}

// MARK: - Snap engine (pure — the "Snap-to-Beat ABER AUCH stufenlos" contract)

/// Grid resolutions the magnet can snap to. `.off` = stepless everywhere
/// (identity). Raw values are persisted (@AppStorage) — keep stable.
public enum SnapResolution: String, Codable, CaseIterable, Sendable {
    case bar, beat, eighth, sixteenth, tripletEighth, off

    /// Grid spacing in ticks (nil = no grid / stepless).
    public var ticks: Int? {
        switch self {
        case .bar:           return TimelineTime.ticksPerBar          // 1920
        case .beat:          return TimelineTime.ticksPerBeat         // 480
        case .eighth:        return TimelineTime.ticksPerBeat / 2     // 240
        case .sixteenth:     return TimelineTime.ticksPerBeat / 4     // 120
        case .tripletEighth: return TimelineTime.ticksPerBeat / 3     // 160
        case .off:           return nil
        }
    }

    public var displayName: String {
        switch self {
        case .bar:           return "Bar"
        case .beat:          return "Beat"
        case .eighth:        return "1/8"
        case .sixteenth:     return "1/16"
        case .tripletEighth: return "1/8T"
        case .off:           return "Off"
        }
    }
}

public enum TimelineSnap {

    /// Snap a tick to the nearest grid line of `resolution`. `.off` (or a
    /// gesture-level bypass) returns the tick unchanged — stepless. Never
    /// returns negative.
    public static func snap(_ tick: Int, to resolution: SnapResolution) -> Int {
        guard let grid = resolution.ticks, grid > 0 else { return max(0, tick) }
        let snapped = Int((Double(tick) / Double(grid)).rounded()) * grid
        return max(0, snapped)
    }

    /// Magnetic snap: only pull onto the grid when within `magnetTicks` of a
    /// line — otherwise leave the tick free. This is the touch feel the
    /// founder asked for (snaps when close, stepless when you steer away);
    /// `magnetTicks` derives from a screen distance via the current zoom.
    public static func magneticSnap(_ tick: Int, to resolution: SnapResolution,
                                    magnetTicks: Int) -> Int {
        guard let grid = resolution.ticks, grid > 0 else { return max(0, tick) }
        let nearest = snap(tick, to: resolution)
        return abs(nearest - tick) <= magnetTicks ? nearest : max(0, tick)
    }

    /// Move/trim commit snap that ALSO magnetizes to EDGE candidates (neighbour clip
    /// starts/ends — clip game C4, the DAW butt-join feel): the tick lands on the
    /// nearest edge when one sits within `magnetTicks` AND at least as close as the
    /// grid pull; otherwise on the grid. With `.off` the grid exerts no pull at all —
    /// stepless — but edges still attract inside the magnet window, so clips kiss
    /// their neighbours without a grid. Never negative. Pure + testable.
    public static func snapWithEdges(_ tick: Int, to resolution: SnapResolution,
                                     edges: [Int], magnetTicks: Int) -> Int {
        let gridded = snap(tick, to: resolution)          // .off → tick unchanged (≥ 0)
        let gridDist = resolution.ticks == nil ? Int.max : abs(gridded - tick)
        if let edge = edges.min(by: { abs($0 - tick) < abs($1 - tick) }),
           abs(edge - tick) <= magnetTicks, abs(edge - tick) <= gridDist {
            return max(0, edge)
        }
        return gridded
    }
}
