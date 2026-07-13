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

    /// Only MIDI/pattern clips actually render today. The arrangement may show the
    /// other lanes, but must not pretend they play until their engine exists.
    public var isPlayable: Bool { self == .midi }
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
    /// Parameter automation the clip carries (automation-in-track cycle 4).
    /// Ticks are CLIP-RELATIVE (0 = the clip's first step), so the lanes travel
    /// with the clip wherever it is launched or placed. Clip automation is clip
    /// CONTENT — it plays whenever the clip plays, like its notes.
    public var automation: [AutomationLane]

    public init(
        id: UUID = UUID(),
        name: String,
        colorIndex: Int = 0,
        kind: ClipKind = .midi,
        drums: DrumPattern? = nil,
        melody: MelodyClip? = nil,
        mediaRef: String? = nil,
        automation: [AutomationLane] = []
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.kind = kind
        self.drums = drums
        self.melody = melody
        self.mediaRef = mediaRef
        self.automation = automation
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, colorIndex, kind, drums, melody, mediaRef, automation
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
        automation = (try? c.decode([AutomationLane].self, forKey: .automation)) ?? []
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
