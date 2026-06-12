// MusicStyle.swift
// Echoel — the curated genre identity behind the bio-generative engine. The app
// does NOT make generic beats; it generates in exactly two sound worlds, plus a
// sync-free ambient mode for self-observation:
//
//   • Dub Techno — Echochord · Basic Channel · Moritz von Oswald: steady 4/4
//     pulse, offbeat ticks, deep sub, hypnotic chord stabs drenched in delay.
//   • Trap       — 808 Mafia · Southside · Metro Boomin: half-time snare, rolling
//     hats, syncopated 808 sub, dark harmonic-minor bells.
//   • Self-Observation — no drums, breath-paced, sync-free; the body alone.
//
// A style fixes the things that make a genre recognisable (tempo window, scale,
// whether it is beat-driven, default transport). The biodata then animates the
// detail inside that frame. Pure value type — no audio, no SwiftUI — so it is
// fully unit-tested.

import Foundation

/// The sound world a take is generated in.
public enum MusicStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case dubTechno
    case trap
    case selfObservation

    public var id: String { rawValue }

    /// UI title.
    public var displayName: String {
        switch self {
        case .dubTechno:       return "Dub Techno"
        case .trap:            return "Trap"
        case .selfObservation: return "Self-Observation"
        }
    }

    /// The sound lineage, shown as a subtitle so the reference is explicit.
    public var lineage: String {
        switch self {
        case .dubTechno:       return "Echochord · Basic Channel · Moritz von Oswald"
        case .trap:            return "808 Mafia · Southside · Metro Boomin"
        case .selfObservation: return "Ambient · breath-paced · sync-free"
        }
    }

    /// The BPM window a take locks within (Studio mode clamps into this).
    public var tempoRange: ClosedRange<Double> {
        switch self {
        case .dubTechno:       return 118...128
        case .trap:            return 130...150
        case .selfObservation: return 50...100
        }
    }

    /// The BPM a fresh take starts at, inside `tempoRange`.
    public var defaultTempo: Double {
        switch self {
        case .dubTechno:       return 124
        case .trap:            return 140
        case .selfObservation: return 70
        }
    }

    /// The dark, genre-appropriate scale a take defaults to.
    public var scale: Scale {
        switch self {
        case .dubTechno:       return .dorian          // classic dub minor-with-a-lift
        case .trap:            return .harmonicMinor    // ominous, raised-7th tension
        case .selfObservation: return .minor            // calm natural minor
        }
    }

    /// Whether the style carries drums (false = ambient, melody only).
    public var isBeatDriven: Bool { self != .selfObservation }

    /// The transport a fresh take of this style defaults to: beat-driven styles
    /// lock to a BPM for DAW handoff; self-observation follows the heart.
    public var defaultMode: ComposerMode {
        isBeatDriven ? .studioLocked : .flowFree
    }
}
