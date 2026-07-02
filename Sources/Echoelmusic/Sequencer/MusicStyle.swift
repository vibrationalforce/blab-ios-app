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
//       School) · Futuristic · Sci-Fi · Psytrance · Deep Ambient
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
    case classical
    case jazz
    case klezmer
    case oriental
    case punk
    case rocknroll
    case rock
    case ska
    case rocksteady
    case heavyMetal
    case doom
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
        case .esotericMeditation: return "Deep Ambient"
        case .classical:          return "Classical"
        case .jazz:               return "Jazz"
        case .klezmer:            return "Klezmer"
        case .oriental:           return "Oriental"
        case .punk:               return "Punk"
        case .rocknroll:          return "Rock 'n' Roll"
        case .rock:               return "Rock"
        case .ska:                return "Ska"
        case .rocksteady:         return "Rocksteady"
        case .heavyMetal:         return "Heavy Metal"
        case .doom:               return "Doom"
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
        case .classical:          return "Chamber strings · clean counterpoint"
        case .jazz:               return "Warm Rhodes · seventh chords"
        case .klezmer:            return "Reedy clarinet · ornamented minor"
        case .oriental:           return "Modal phrygian · reed & strings"
        case .punk:               return "Fast power chords · raw drive"
        case .rocknroll:          return "Twangy mixolydian · boogie"
        case .rock:               return "Driven power chords · anthemic"
        case .ska:                return "Bright offbeat skank"
        case .rocksteady:         return "Mellow offbeat · warm organ"
        case .heavyMetal:         return "Dark phrygian · low power chords"
        case .doom:               return "Crushing slow · downtuned drone"
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
        case .classical:          return 60...110
        case .jazz:               return 80...150
        case .klezmer:            return 90...170
        case .oriental:           return 80...140
        case .punk:               return 160...210
        case .rocknroll:          return 140...185
        case .rock:               return 110...155
        case .ska:                return 120...165
        case .rocksteady:         return 80...110
        case .heavyMetal:         return 130...185
        case .doom:               return 50...80
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
        case .classical:          return 84
        case .jazz:               return 112
        case .klezmer:            return 128
        case .oriental:           return 104
        case .punk:               return 185
        case .rocknroll:          return 162
        case .rock:               return 132
        case .ska:                return 142
        case .rocksteady:         return 95
        case .heavyMetal:         return 160
        case .doom:               return 62
        case .selfObservation:    return 70
        }
    }

    /// Genre swing (shuffle) amount, 0…0.5 — GROOVE CYCLE 2. Fed to
    /// `PatternEngine.setSwing` on Generate so odd 16ths land late for a rolling,
    /// human feel instead of dead-on-grid (the "sounds like a machine" tell). The
    /// melody rides the same clock, so it swings with the beat. Values are musical:
    /// jazz/rock'n'roll shuffle hard (~2:1 triplet at 0.33), the reggae family
    /// (ska/rocksteady) bounces, dance genres get a subtle push, and rigid genres
    /// (psytrance, rock, metal, classical rubato, ambient) stay straight at 0.
    public var swing: Double {
        switch self {
        case .jazz:               return 0.34   // the defining swung-8th feel (~2:1)
        case .rocknroll:          return 0.28   // heavy shuffle
        case .rocksteady:         return 0.22   // laid-back reggae bounce
        case .klezmer:            return 0.20
        case .ska:                return 0.18   // offbeat skank lift
        case .vaporwave:          return 0.15   // dragged, behind the beat
        case .disco:              return 0.14
        case .trap:               return 0.12   // subtle hat/triplet lean
        case .oriental:           return 0.10
        case .dubTechno:          return 0.08   // near-straight, tiny push
        case .eighties:           return 0.06
        case .synthwave, .earlySynth, .futuristic, .sciFi, .psytrance,
             .esotericMeditation, .classical, .punk, .rock, .heavyMetal,
             .doom, .selfObservation:
            return 0.0                          // straight / free — grid swing would hurt these
        }
    }

    /// The factory `SynthPatch` name the dedicated LEAD voice takes on for this
    /// genre (multitimbral Step 2b). The lead line then reads as a distinct
    /// instrument sitting over the pad/bass — a synthwave lead vs a jazz Rhodes
    /// vs a klezmer clarinet — instead of one fixed lead everywhere. Names must
    /// exist in `SynthPatch.factory`; the generator falls back to "Bright Lead"
    /// if a name is ever missing.
    public var leadPatchName: String {
        switch self {
        case .dubTechno:          return "Pluck"
        case .trap:               return "Glass Bell"
        case .vaporwave:          return "Vapor Lead"
        case .eighties:           return "Bright Lead"
        case .disco:              return "Trumpet"
        case .synthwave:          return "Bright Lead"
        case .earlySynth:         return "Pluck"
        case .futuristic:         return "Glass Bell"
        case .sciFi:              return "Metallic"
        case .psytrance:          return "Bright Lead"
        case .esotericMeditation: return "Flute"
        case .classical:          return "Violin"
        case .jazz:               return "Soft Keys"    // warm Rhodes
        case .klezmer:            return "Clarinet"
        case .oriental:           return "Oboe"
        case .punk:               return "Bright Lead"
        case .rocknroll:          return "Hollow Reed"  // sax-like honk
        case .rock:               return "Bright Lead"
        case .ska:                return "Trumpet"       // ska horn line
        case .rocksteady:         return "Hollow Reed"
        case .heavyMetal:         return "Metallic"
        case .doom:               return "Metallic"
        case .selfObservation:    return "Flute"
        }
    }

    /// Per-genre MIX GLUE (relative role levels, applied as velocity multipliers
    /// at generate time — velocity scales each voice's amplitude, so this is a
    /// pure level move, no audio-thread change). Keeps each genre balanced: bass
    /// firmer in dub/trap/heavy, lead forward in synth genres, pads back in dense
    /// takes, everything gentle (0.85–1.2) so nothing clips or disappears.
    public var mixLevels: (bass: Float, harmony: Float, lead: Float) {
        switch self {
        case .dubTechno, .trap:                       return (1.18, 0.92, 1.00)
        case .ska, .rocksteady, .disco:               return (1.12, 0.95, 1.05)
        case .synthwave, .eighties, .vaporwave, .earlySynth:
                                                      return (1.00, 0.90, 1.15)
        case .futuristic, .sciFi, .psytrance:         return (1.00, 0.88, 1.18)
        case .classical, .jazz, .klezmer, .oriental:  return (1.00, 1.00, 1.06)
        case .punk, .rock, .rocknroll, .heavyMetal, .doom:
                                                      return (1.12, 0.90, 1.10)
        case .esotericMeditation, .selfObservation:   return (0.95, 1.05, 0.98)
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
        case .classical:          return .major
        case .jazz:               return .dorian
        case .klezmer:            return .harmonicMinor
        case .oriental:           return .phrygian
        case .punk:               return .major
        case .rocknroll:          return .mixolydian
        case .rock:               return .minor
        case .ska:                return .major
        case .rocksteady:         return .major
        case .heavyMetal:         return .phrygian
        case .doom:               return .phrygian
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
        case .classical:
            return HarmonicProfile(progression: [0, 3, 4, 0], chordTones: [0, 2, 4],
                                   padOctave: 4, leadOctave: 5, arpeggiated: false, leadDensity: 0.45)
        case .jazz:
            return HarmonicProfile(progression: [0, 3, 5, 1], chordTones: [0, 2, 4, 6],
                                   padOctave: 4, leadOctave: 5, arpeggiated: false, leadDensity: 0.6)
        case .klezmer:
            return HarmonicProfile(progression: [0, 3, 4], chordTones: [0, 2, 4],
                                   padOctave: 4, leadOctave: 5, arpeggiated: false, leadDensity: 0.7)
        case .oriental:
            return HarmonicProfile(progression: [0, 1], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false, leadDensity: 0.7)
        case .punk:
            return HarmonicProfile(progression: [0, 3, 4], chordTones: [0, 4],
                                   padOctave: 3, leadOctave: 4, arpeggiated: false, leadDensity: 0.4)
        case .rocknroll:
            return HarmonicProfile(progression: [0, 3, 4], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false, leadDensity: 0.5)
        case .rock:
            return HarmonicProfile(progression: [0, 5, 3, 4], chordTones: [0, 4],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false, leadDensity: 0.5)
        case .ska:
            return HarmonicProfile(progression: [0, 3, 4], chordTones: [0, 2, 4],
                                   padOctave: 4, leadOctave: 5, arpeggiated: true, leadDensity: 0.5)
        case .rocksteady:
            return HarmonicProfile(progression: [0, 5, 3, 4], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 4, arpeggiated: false, leadDensity: 0.4)
        case .heavyMetal:
            return HarmonicProfile(progression: [0, 1, 0], chordTones: [0, 4],
                                   padOctave: 2, leadOctave: 4, arpeggiated: false, leadDensity: 0.5)
        case .doom:
            return HarmonicProfile(progression: [0], chordTones: [0, 4],
                                   padOctave: 2, leadOctave: 3, arpeggiated: false, leadDensity: 0.2)
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
