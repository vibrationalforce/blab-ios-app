// SkillLevel.swift
// Echoel — "for everyone, from noob to pro." One progressive-disclosure dial that
// keeps the default UI minimal (the core USP: heartbeat → music → meditate/export)
// and reveals depth as the producer wants it. Nothing is ever removed — higher
// levels only ADD surfaces. Pure value type, fully unit-tested.

import Foundation

/// How much of the studio is on screen. Each level is a superset of the previous.
public enum SkillLevel: String, CaseIterable, Sendable, Identifiable, Comparable {
    /// Essentials only — Create + Meditate. The heartbeat instrument, nothing to
    /// learn first.
    case beginner
    /// Adds song-building — the Songs (clips / arrangement) tab.
    case producer
    /// Adds professional routing + recording — Sessions and Connect (MIDI / OSC /
    /// ADM-OSC / lighting).
    case pro

    public var id: String { rawValue }

    /// Sort order for `Comparable` (beginner < producer < pro).
    private var rank: Int {
        switch self {
        case .beginner: return 0
        case .producer: return 1
        case .pro:      return 2
        }
    }

    public static func < (lhs: SkillLevel, rhs: SkillLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    public var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .producer: return "Producer"
        case .pro:      return "Pro"
        }
    }

    /// One-line description for the picker.
    public var blurb: String {
        switch self {
        case .beginner: return "Just the essentials — your heartbeat makes music."
        case .producer: return "Adds song-building (Songs) for full productions."
        case .pro:      return "Adds Sessions + Connect (MIDI, OSC, immersive audio, lighting)."
        }
    }

    // MARK: - Surface gates (each higher level a superset)

    /// The Songs (clips / arrangement) tab — from Producer up.
    public var showsSongs: Bool { self >= .producer }

    /// The Sessions recorder + Connect (routing / lighting) tabs — Pro only.
    public var showsProTabs: Bool { self >= .pro }
}
