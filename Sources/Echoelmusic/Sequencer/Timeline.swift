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

    public init(id: UUID = UUID(), name: String, kind: ClipKind, isBio: Bool = false,
                level: Float = 1, isMuted: Bool = false, isSoloed: Bool = false,
                pan: Float = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isBio = isBio
        self.level = level
        self.isMuted = isMuted
        self.isSoloed = isSoloed
        self.pan = pan
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

    public init(id: UUID = UUID(), laneID: UUID, clipID: UUID,
                startTick: Int, lengthTicks: Int, contentOffsetSeconds: Double = 0) {
        self.id = id
        self.laneID = laneID
        self.clipID = clipID
        self.startTick = max(0, startTick)
        self.lengthTicks = max(1, lengthTicks)
        self.contentOffsetSeconds = max(0, contentOffsetSeconds)
    }

    public var endTick: Int { startTick + lengthTicks }
}

/// The whole timeline document: ordered lanes + their regions.
public struct TimelineDocument: Codable, Sendable, Equatable {
    public var lanes: [TimelineLane]
    public var regions: [TimelineRegion]

    public init(lanes: [TimelineLane] = [], regions: [TimelineRegion] = []) {
        self.lanes = lanes
        self.regions = regions
    }

    public func regions(in laneID: UUID) -> [TimelineRegion] {
        regions.filter { $0.laneID == laneID }.sorted { $0.startTick < $1.startTick }
    }

    /// Total song length in ticks (end of the last region; ≥ 0).
    public var endTick: Int { regions.map(\.endTick).max() ?? 0 }

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

    /// The stereo position the ONE shared Piano-Roll slot plays at (B2 — the
    /// rollSlotGain mirror for pan). Clamped −1…1; mute/solo do NOT touch pan
    /// (audibility is gain's job). No MIDI lane → center.
    public var rollSlotPan: Float {
        guard let lane = lanes.first(where: { $0.kind == .midi && !$0.isBio }) else { return 0 }
        return max(-1, min(1, lane.pan))
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
}
