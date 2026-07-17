// Clip.swift
// Echoel — launchable session clips: a saved drum pattern and/or melody that can
// be fired into the live transport (Ableton-session style). Pure value types, so
// clips persist as JSON and round-trip cleanly.

import Foundation

/// A saved drum grid (steps + accents), shaped like PatternEngine's state.
public struct DrumPattern: Codable, Sendable, Equatable {
    public var steps: [[Bool]]
    public var accents: [[Bool]]
    public init(steps: [[Bool]], accents: [[Bool]]) {
        self.steps = steps
        self.accents = accents
    }
}

/// A saved melodic phrase (absolute-pitch notes from the piano roll).
public struct MelodyClip: Codable, Sendable, Equatable {
    public var notes: [Note]
    public init(notes: [Note]) { self.notes = notes }

    /// Founder v287/v288 "Es wird kein midi Clip erzeugt": flatten a loop's per-bar
    /// (bar-relative) note arrays into ONE clip-absolute note array — bar `b`'s notes
    /// shifted by `b × ticksPerBar` — so the generative take can be MIRRORED into a
    /// composer-owned MIDI clip that shows + edits on the arrange timeline. This is
    /// the exact inverse of `RegionNoteWindow.barSlices` (the region player's
    /// windowing), so the placed clip plays back the identical bars. Pure + lossless:
    /// a plain tick shift preserves every note field (velocity / role / operators /
    /// mpe). Foundation-only → unit-tested on Linux CI (lives here, not on the
    /// SwiftUI-gated studio view, so the pure test compiles without SwiftUI).
    public static func flatten(loopBars bars: [[Note]]) -> [Note] {
        var out: [Note] = []
        for (barIndex, bar) in bars.enumerated() {
            let offset = barIndex * TimelineTime.ticksPerBar
            for note in bar {
                var shifted = note
                shifted.startTick = note.startTick + offset
                out.append(shifted)
            }
        }
        return out
    }
}

/// What a clip carries. The DMMW main view is a clip-typed timeline (audio · MIDI ·
/// video · visual) — `ClipKind` is that type. `.midi` is the existing pattern clip
/// (drums/melody) and the only kind that PLAYS today; audio/video/visual are the
/// scaffolding for the typed arrangement and are surfaced honestly (`isPlayable`)
/// until their engines ship. See docs/dev/DMMW_ARCHITECTURE.md.
public enum ClipKind: String, Codable, Sendable, CaseIterable {
    case midi, audio, video, visual

    public var displayName: String {
        switch self {
        case .midi:   return "MIDI"
        case .audio:  return "Audio"
        case .video:  return "Video"
        case .visual: return "Visual"
        }
    }

    public var systemImage: String {
        switch self {
        case .midi:   return "pianokeys"
        case .audio:  return "waveform"
        case .video:  return "film"
        case .visual: return "sparkles"
        }
    }

    /// Kinds a timeline PLAYBACK engine drives today. `isPlayable` reads this set,
    /// so enabling video is a ONE-LINE change here once the AVPlayer video engine is
    /// device-verified (add `.video`) — not scattered `== .midi` checks.
    public static let timelineEngineKinds: Set<ClipKind> = [.midi]

    /// Only kinds with a shipped, device-verified engine render on the timeline. The
    /// arrangement may show the other lanes, but must not pretend they play.
    public var isPlayable: Bool { Self.timelineEngineKinds.contains(self) }

    /// Kinds that carry an external media file via `mediaRef` (vs. inline
    /// pattern/melody). Pure classifier — true today for audio/video/visual.
    public var isMediaCarrier: Bool {
        switch self {
        case .midi:                    return false
        case .audio, .video, .visual:  return true
        }
    }
}

/// A launchable cell: a typed clip (MIDI pattern today; audio/video/visual carry a
/// `mediaRef`), with a name + color.
public struct Clip: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var colorIndex: Int
    public var kind: ClipKind
    public var drums: DrumPattern?
    public var melody: MelodyClip?
    /// Asset/file reference for audio/video/visual clips; nil for a MIDI pattern clip.
    public var mediaRef: String?
    /// The media's NATIVE duration in seconds, measured on device at import (audio/
    /// video). `nil` when unknown (older clips / not measured). The transport players
    /// need it to detect a clip SHORTER than its placed span (video `.exhausted` /
    /// audio EOF), so it is persisted with the clip rather than re-measured each launch.
    public var nativeDurationSeconds: Double?
    /// The media's NATIVE tempo in BPM — a property of the AUDIO itself (task #54
    /// Warp): seeded from the import bar-guess (`TempoMatch`), user-correctable in
    /// the editor ("Clip BPM"). `0` = unknown → the clip NEVER warps. Clamped to
    /// `AudioClipRegion.nativeBPMRange` when set; older documents decode as 0
    /// (bit-identical playback, nothing pruned). MIDI clips ignore it.
    public var nativeBPM: Double
    /// Parameter automation the clip carries (automation-in-track cycle 4).
    /// Ticks are CLIP-RELATIVE (0 = the clip's first step), so the lanes travel
    /// with the clip wherever it is launched or placed. Clip automation is clip
    /// CONTENT — it plays whenever the clip plays, like its notes.
    public var automation: [AutomationLane]
    /// OWNERSHIP guard (per-lane composition Slice A): `true` marks a clip the
    /// COMPOSER created for a lane's override take — only these may be rewritten
    /// by a later generate/evolve. A user-captured/imported/placed clip is `false`
    /// forever, so the per-lane composer can NEVER clobber user content. Set
    /// ONLY in the composer write path; every other creation path leaves the
    /// default. Older clips decode as `false` (user-owned — the safe side).
    public var composerOwned: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        colorIndex: Int = 0,
        kind: ClipKind = .midi,
        drums: DrumPattern? = nil,
        melody: MelodyClip? = nil,
        mediaRef: String? = nil,
        nativeDurationSeconds: Double? = nil,
        nativeBPM: Double = 0,
        automation: [AutomationLane] = [],
        composerOwned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.kind = kind
        self.drums = drums
        self.melody = melody
        self.mediaRef = mediaRef
        self.nativeDurationSeconds = nativeDurationSeconds
        self.nativeBPM = Clip.clampedNativeBPM(nativeBPM)
        self.automation = automation
        self.composerOwned = composerOwned
    }

    /// `0` stays 0 (unknown — never warps); anything else clamps into the ONE
    /// musical range shared with the editor model (`AudioClipRegion.nativeBPMRange`).
    public static func clampedNativeBPM(_ bpm: Double) -> Double {
        guard bpm.isFinite, bpm > 0 else { return 0 }
        return Swift.min(AudioClipRegion.nativeBPMRange.upperBound,
                         Swift.max(AudioClipRegion.nativeBPMRange.lowerBound, bpm))
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, colorIndex, kind, drums, melody, mediaRef, nativeDurationSeconds
        case nativeBPM, automation, composerOwned
    }

    // Forward/backward-compatible decode: clips saved before `kind`/`mediaRef` existed
    // load as MIDI pattern clips, so no library is lost on upgrade.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "Clip"
        colorIndex = (try? c.decode(Int.self, forKey: .colorIndex)) ?? 0
        kind = (try? c.decode(ClipKind.self, forKey: .kind)) ?? .midi
        drums = try? c.decode(DrumPattern.self, forKey: .drums)
        melody = try? c.decode(MelodyClip.self, forKey: .melody)
        mediaRef = try? c.decode(String.self, forKey: .mediaRef)
        nativeDurationSeconds = try? c.decode(Double.self, forKey: .nativeDurationSeconds)
        // Pre-warp clips carry no tempo — 0 = unknown, never warps (bit-identical).
        nativeBPM = Clip.clampedNativeBPM((try? c.decode(Double.self, forKey: .nativeBPM)) ?? 0)
        automation = (try? c.decode([AutomationLane].self, forKey: .automation)) ?? []
        // Pre-Slice-A clips carry no ownership mark — user-owned (never rewritten).
        composerOwned = (try? c.decode(Bool.self, forKey: .composerOwned)) ?? false
    }

    /// True if the clip carries no content (per kind).
    public var isEmpty: Bool {
        switch kind {
        case .midi:
            return (drums?.steps.flatMap { $0 }.contains(true) ?? false) == false
                && (melody?.notes.isEmpty ?? true)
        case .audio, .video, .visual:
            return (mediaRef?.isEmpty ?? true)
        }
    }
}
