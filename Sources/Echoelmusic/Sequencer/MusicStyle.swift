// MusicStyle.swift
// Echoel — the curated genre identity behind the bio-generative engine. Echoel is
// NOT a beat-maker; it generates the harmonic/melodic STARTING MATERIAL for a
// professional production — pads, chords, leads, arps, atmospheres — across many
// genres, driven by the body. Two genres carry a beat (Dub Techno, Trap); all the
// rest are non-beat layers you finish in your DAW.
//
//   Beat-driven:
//     • Dub Techno — deep dub chords, tape echo, sub-bass
//     • Trap       — booming 808 sub-bass, crisp hats, dark melody
//   Non-beat harmonic material (pads · chords · leads · arps · FX):
//     • Vaporwave · 80s Synth-Pop · Disco · Synthwave · Early Synth (Berlin
//       School) · Futuristic · Sci-Fi · Psytrance · Esoteric Meditation
//   Bio-ambient:
//     • Self-Observation — no drums, breath-paced, sync-free
//
// Genre subtitles are descriptive sound characters only — no artist, label, or
// film names anywhere user-facing (App Store-safe, no implied endorsement).
//
// A style fixes what makes a genre recognisable (tempo window, scale, whether it
// is beat-driven, default transport, and — for the harmonic genres — a chord
// progression / voicing / arp profile). The biodata then animates the detail.
// Pure value type — no audio, no SwiftUI — so it is fully unit-tested.

import Foundation

/// How a non-beat genre voices its harmonic material.
public struct HarmonicProfile: Sendable, Equatable {
    /// Chord roots as scale degrees, spread across the bar (e.g. [0, 3] = i → IV).
    public var progression: [Int]
    /// Scale-degree offsets forming each chord ([0,2,4] = triad, [0,2,4,6] = 7th).
    public var chordTones: [Int]
    /// Octave for the pad/chord layer (MIDI 60 = C4).
    public var padOctave: Int
    /// Octave for the lead layer.
    public var leadOctave: Int
    /// Break chords into a rising arpeggio (true) or hold them as a pad (false).
    public var arpeggiated: Bool
    /// 0 = no lead (drone), 1 = a busy lead line.
    public var leadDensity: Float

    public init(progression: [Int], chordTones: [Int], padOctave: Int,
                leadOctave: Int, arpeggiated: Bool, leadDensity: Float) {
        self.progression = progression
        self.chordTones = chordTones
        self.padOctave = padOctave
        self.leadOctave = leadOctave
        self.arpeggiated = arpeggiated
        self.leadDensity = leadDensity
    }
}

/// The sound world a take is generated in.
public enum MusicStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case dubTechno
    case trap
    case vaporwave
    case eighties
    case disco
    case synthwave
    case earlySynth
    case futuristic
    case sciFi
    case psytrance
    case esotericMeditation
    case selfObservation

    public var id: String { rawValue }

    /// UI title.
    public var displayName: String {
        switch self {
        case .dubTechno:          return "Dub Techno"
        case .trap:               return "Trap"
        case .vaporwave:          return "Vaporwave"
        case .eighties:           return "80s Synth-Pop"
        case .disco:              return "Disco"
        case .synthwave:          return "Synthwave"
        case .earlySynth:         return "Early Synth"
        case .futuristic:         return "Futuristic"
        case .sciFi:              return "Sci-Fi"
        case .psytrance:          return "Psytrance"
        case .esotericMeditation: return "Esoteric Meditation"
        case .selfObservation:    return "Self-Observation"
        }
    }

    /// A short sound-character subtitle. Purely descriptive — no artist, label,
    /// or film names (App Store-safe, no implied endorsement).
    public var lineage: String {
        switch self {
        case .dubTechno:          return "Deep dub chords · tape echo · sub-bass"
        case .trap:               return "Booming 808 sub-bass · crisp hats · dark melody"
        case .vaporwave:          return "Slowed · dreamy · nostalgic maj7 pads"
        case .eighties:           return "Bright analog keys · gated-reverb era"
        case .disco:              return "Lush string stabs · four-on-the-floor era"
        case .synthwave:          return "Neon arpeggios · retro-future drive"
        case .earlySynth:         return "Berlin School · sequenced analog pulses"
        case .futuristic:         return "Clean, shimmering, wide suspended chords"
        case .sciFi:              return "Eerie atmospheres · deep-space mood"
        case .psytrance:          return "Rolling minor arpeggio · Goa lineage"
        case .esotericMeditation: return "Drone · ethereal pads · deep ambient"
        case .selfObservation:    return "Ambient · breath-paced · sync-free"
        }
    }

    /// The BPM window a take locks within (Studio mode clamps into this).
    public var tempoRange: ClosedRange<Double> {
        switch self {
        case .dubTechno:          return 118...128
        case .trap:               return 130...150
        case .vaporwave:          return 60...80
        case .eighties:           return 108...120
        case .disco:              return 115...125
        case .synthwave:          return 80...100
        case .earlySynth:         return 100...120
        case .futuristic:         return 90...110
        case .sciFi:              return 70...90
        case .psytrance:          return 140...150
        case .esotericMeditation: return 50...70
        case .selfObservation:    return 50...100
        }
    }

    /// The BPM a fresh take starts at, inside `tempoRange`.
    public var defaultTempo: Double {
        switch self {
        case .dubTechno:          return 124
        case .trap:               return 140
        case .vaporwave:          return 70
        case .eighties:           return 114
        case .disco:              return 120
        case .synthwave:          return 88
        case .earlySynth:         return 110
        case .futuristic:         return 100
        case .sciFi:              return 80
        case .psytrance:          return 145
        case .esotericMeditation: return 60
        case .selfObservation:    return 70
        }
    }

    /// The dark/bright, genre-appropriate scale a take defaults to.
    public var scale: Scale {
        switch self {
        case .dubTechno:          return .dorian
        case .trap:               return .harmonicMinor
        case .vaporwave:          return .major
        case .eighties:           return .major
        case .disco:              return .mixolydian
        case .synthwave:          return .minor
        case .earlySynth:         return .dorian
        case .futuristic:         return .lydian
        case .sciFi:              return .phrygian
        case .psytrance:          return .phrygian
        case .esotericMeditation: return .lydian
        case .selfObservation:    return .minor
        }
    }

    /// Whether the style carries drums (only the two beat genres do).
    public var isBeatDriven: Bool {
        self == .dubTechno || self == .trap
    }

    /// How a non-beat style voices its harmony. Beat genres + self-observation
    /// don't use this (their melody is bespoke) but return a sane default so the
    /// switch stays total.
    public var harmonicProfile: HarmonicProfile {
        switch self {
        case .vaporwave:
            return HarmonicProfile(progression: [0, 3], chordTones: [0, 2, 4, 6],
                                   padOctave: 4, leadOctave: 5, arpeggiated: false, leadDensity: 0.25)
        case .eighties:
            return HarmonicProfile(progression: [0, 4, 5, 3], chordTones: [0, 2, 4],
                                   padOctave: 4, leadOctave: 5, arpeggiated: true, leadDensity: 0.5)
        case .disco:
            return HarmonicProfile(progression: [0, 3, 4], chordTones: [0, 2, 4, 6],
                                   padOctave: 4, leadOctave: 5, arpeggiated: false, leadDensity: 0.5)
        case .synthwave:
            return HarmonicProfile(progression: [0, 5, 3, 4], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 5, arpeggiated: true, leadDensity: 0.6)
        case .earlySynth:
            return HarmonicProfile(progression: [0, 0], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 4, arpeggiated: true, leadDensity: 0.4)
        case .futuristic:
            return HarmonicProfile(progression: [0, 1], chordTones: [0, 2, 4],
                                   padOctave: 4, leadOctave: 6, arpeggiated: false, leadDensity: 0.3)
        case .sciFi:
            return HarmonicProfile(progression: [0, 1], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false, leadDensity: 0.3)
        case .psytrance:
            return HarmonicProfile(progression: [0], chordTones: [0, 2, 4],
                                   padOctave: 2, leadOctave: 4, arpeggiated: true, leadDensity: 0.7)
        case .esotericMeditation:
            return HarmonicProfile(progression: [0], chordTones: [0, 2, 4, 6],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false, leadDensity: 0.0)
        case .dubTechno, .trap, .selfObservation:
            return HarmonicProfile(progression: [0, 3], chordTones: [0, 2, 4],
                                   padOctave: 4, leadOctave: 5, arpeggiated: false, leadDensity: 0.3)
        }
    }

    /// The transport a fresh take of this style defaults to: meditation follows
    /// the heart (sync-free); everything else locks to a BPM for DAW handoff.
    public var defaultMode: ComposerMode {
        switch self {
        case .selfObservation, .esotericMeditation: return .flowFree
        default:                                     return .studioLocked
        }
    }
}
