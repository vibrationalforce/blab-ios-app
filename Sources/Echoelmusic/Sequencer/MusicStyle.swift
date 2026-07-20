// MusicStyle.swift
// Echoel — the curated genre identity behind the bio-generative engine. It
// generates DAW-ready STARTING MATERIAL — harmony, melody AND the genre's
// defining groove — across many genres, driven by the body.
//
//   Signature beats (hand-built):
//     • Dub Techno — deep dub chords, tape echo, sub-bass
//     • Trap       — booming 808 sub-bass, crisp hats, dark pads
//   Archetype beats (audit B5, 2026-07-04 — every beat-driven genre now carries
//   its groove via `beatArchetype`: four-on-floor / backbeat / offbeat / half-time):
//     • Disco · 80s · Early Synth · Futuristic · Psytrance · Synthwave (floor)
//     • Rock · Punk · Rock'n'Roll · Heavy Metal · Jazz · Oriental (backbeat)
//     • Ska · Rocksteady · Klezmer (offbeat skank)  ·  Doom · Vaporwave · Sci-Fi (half-time)
//   Drum-free by design:
//     • Classical · Meditation · Self-Observation (breath-paced, sync-free)
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
    /// A TRUE sustained drone: hold ONE root and the full chord for the whole
    /// section — NO walking bass, NO inner 8th/16th pulse layer, regardless of the
    /// body's arousal. For the meditative Fläche the stillness IS the quality
    /// (founder 2026-07-07: "echte Musik … nach echtem Wasser … alles reduzieren
    /// dafür qualitativ hochwertiger"). Movement comes from the slow evolve, the
    /// tape+hall space and the body — not from note density.
    public var sustained: Bool

    public init(progression: [Int], chordTones: [Int], padOctave: Int,
                leadOctave: Int, arpeggiated: Bool, leadDensity: Float,
                sustained: Bool = false) {
        self.progression = progression
        self.chordTones = chordTones
        self.padOctave = padOctave
        self.leadOctave = leadOctave
        self.arpeggiated = arpeggiated
        self.leadDensity = leadDensity
        self.sustained = sustained
    }
}

/// The sound world a take is generated in.
public enum MusicStyle: String, Codable, CaseIterable, Sendable, Identifiable {

    /// The sustained Flächen — the calm genres that hold ONE chord per bar and
    /// carry NO lead. Kept as the invariant the calm-stillness tests assert against
    /// (decoupled from the offered roster since 2026-07-11). Source of truth is the
    /// `sustained` profile flag; this list must equal `allCases.filter { sustained }`
    /// (guarded in MusicStyleTests).
    public static let sustainedFlächen: [MusicStyle] = [
        .selfObservation, .esotericMeditation, .vaporwave, .dubTechno, .trap, .sciFi
    ]

    /// Logical genre groups the Genre picker sorts into (founder 2026-07-11: "Alles
    /// rein. Logisch sortiert. Gehe tief rein" — SUPERSEDES the 2026-07-08 six-calm
    /// curation). Every genre is now offered, organised by sound-world so the calm
    /// meditative identity stays first while rock/energetic/acoustic worlds open up.
    public enum Category: String, CaseIterable, Identifiable, Sendable {
        case meditative   // ambient Flächen — the relaxation core, listed first
        case electronic   // beats & synth grooves
        case rock         // driven power-chord energy
        case acoustic     // acoustic / world / modal

        public var id: String { rawValue }

        /// Picker section header.
        public var title: String {
            switch self {
            case .meditative: return "Meditativ & Ambient"
            case .electronic: return "Elektronisch & Beats"
            case .rock:       return "Rock & Energie"
            case .acoustic:   return "Akustisch & Global"
            }
        }

        /// The genres in this group, in display order.
        public var genres: [MusicStyle] {
            switch self {
            case .meditative: return [.selfObservation, .esotericMeditation, .vaporwave, .sciFi]
            case .electronic: return [.dubTechno, .trap, .psytrance, .synthwave,
                                      .earlySynth, .eighties, .disco, .futuristic]
            case .rock:       return [.rock, .punk, .rocknroll, .heavyMetal, .doom]
            case .acoustic:   return [.classical, .jazz, .klezmer, .oriental, .ska, .rocksteady]
            }
        }
    }

    /// Which logical group this genre belongs to (total — every case mapped exactly
    /// once; guarded in MusicStyleTests).
    public var category: Category {
        switch self {
        case .selfObservation, .esotericMeditation, .vaporwave, .sciFi:
            return .meditative
        case .dubTechno, .trap, .psytrance, .synthwave, .earlySynth, .eighties, .disco, .futuristic:
            return .electronic
        case .rock, .punk, .rocknroll, .heavyMetal, .doom:
            return .rock
        case .classical, .jazz, .klezmer, .oriental, .ska, .rocksteady:
            return .acoustic
        }
    }

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
        case .trap:               return "Booming 808 sub-bass · crisp hats · dark pads"
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

    /// The rhythmic skeleton a genre's generated beat is built on (audit B5).
    /// `signature` = the genre has its own hand-built beat function (dub, trap);
    /// `none` = deliberately drum-free (classical, meditation, self-observation).
    public enum BeatArchetype: Sendable, Equatable {
        case none
        case signature
        case fourOnFloor   // kick every beat, offbeat hats, backbeat clap
        case backbeat      // kick 1(+3), snare 2 & 4, driving 8th hats
        case offbeat       // kick anchor, skank stabs on the offbeats
        case halfTime      // sparse kick, snare on 3, heavy air
    }

    /// Which groove skeleton this genre carries. Drives the generic beat
    /// builders in `BioComposer`; tempo feel comes from `tempoRange` (B4).
    public var beatArchetype: BeatArchetype {
        switch self {
        case .dubTechno, .trap:                                 return .signature
        case .disco, .eighties, .earlySynth, .futuristic,
             .psytrance, .synthwave:                            return .fourOnFloor
        case .rock, .punk, .rocknroll, .heavyMetal,
             .jazz, .oriental:                                  return .backbeat
        case .ska, .rocksteady, .klezmer:                       return .offbeat
        case .doom, .vaporwave, .sciFi:                         return .halfTime
        case .classical, .esotericMeditation, .selfObservation: return .none
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
        // Fläche window (founder 2026-07-07 "langsamere Vibes"): the ceiling
        // drops 100 -> 78 so an elevated pulse octave-folds DOWN — the pad can
        // never race; the floor still admits a deep resting pulse (46).
        case .selfObservation:    return 46...78
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
        case .selfObservation:    return 58
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
        // WARM SYNTH ONLY (founder 2026-07-07: "Real Instruments raus, das klingt
        // trashig … wir wollen tendenziell den warmen Synth-Sound, vermeide plastisch
        // und verzerrt klingende Real-Instrument-Emulationen"). Every lead resolves to
        // a warm synth patch — no Violin/Clarinet/Trumpet/Oboe/Flute/Metallic
        // emulations. Genre character now comes from the synth's own envelope +
        // brightness (a "nuance in the base synth"), not from imitating an instrument.
        // Still ≥6 distinct so leads keep some variety across genres.
        // ANGENEHMES SPEKTRUM (founder 2026-07-07: "die Melodien sind bei manchen
        // Genres super laut und unangenehm im Ohr, kein angenehmes Spektrum … die
        // meisten Genres hauen ihre Melodie unangenehm heraus. Das soll schön und
        // entspannt sein"). The piercing bright leads — "Bright Lead" (spectralShape
        // bright, resonance + vibrato, sustain 0.7), "Glass Bell" (brightness 0.8),
        // "Vapor Lead" (bright, resonance) — are gone from EVERY genre. Warm, mellow
        // leads only (Soft Keys / Warm Strings / Hollow Reed / Pluck / Choir Vox /
        // Deep Sub): pure warm synth, gentle top end, no shrill spectrum. Genre
        // character comes from envelope + progression, not a piercing lead.
        // DE-HOMOGENISED (founder 2026-07-20: "die Genres klingen teilweise gleich").
        // The 2026-07-07 warm-only pass had collapsed NINE lead-bearing genres onto the
        // identical "Soft Keys" lead — the single biggest "they all sound the same" tell.
        // Every lead-bearing genre is now spread across the SIX approved warm patches so
        // no patch carries more than three (guarded in MusicStyleLeadTests), while every
        // lead stays inside the warm set — no shrill "Bright Lead"/"Glass Bell"/"Vapor
        // Lead" and no plastic real-instrument emulation ever returns. Character now
        // reads distinctly per genre (a plucky rock'n'roll vs a reedy rock vs Rhodes
        // jazz) without any bright/harsh reintroduction. Exact per-genre timbre is
        // device-tunable; the INVARIANT is: warm-set only + spread.
        switch self {
        case .dubTechno:          return "Pluck"         // sustained — unused
        case .trap:               return "Soft Keys"     // sustained — unused
        case .vaporwave:          return "Warm Strings"  // sustained — unused
        case .eighties:           return "Soft Keys"
        case .disco:              return "Warm Strings"  // was Soft Keys (spread)
        case .synthwave:          return "Warm Strings"
        case .earlySynth:         return "Pluck"
        case .futuristic:         return "Hollow Reed"
        case .sciFi:              return "Choir Vox"      // sustained — unused
        case .psytrance:          return "Pluck"
        case .esotericMeditation: return "Choir Vox"     // sustained — unused
        case .classical:          return "Soft Keys"
        case .jazz:               return "Soft Keys"     // warm Rhodes-style keys
        case .klezmer:            return "Hollow Reed"   // reedy + warm
        case .oriental:           return "Choir Vox"
        case .punk:               return "Choir Vox"     // was Soft Keys (spread)
        case .rocknroll:          return "Pluck"         // was Soft Keys — twangy plucked feel
        case .rock:               return "Hollow Reed"   // was Soft Keys — warm organ-ish lead
        case .ska:                return "Warm Strings"  // was Soft Keys (spread)
        case .rocksteady:         return "Choir Vox"     // was Soft Keys (spread)
        case .heavyMetal:         return "Deep Sub"      // was Hollow Reed — low + dark fits metal
        case .doom:               return "Deep Sub"
        case .selfObservation:    return "Choir Vox"     // sustained — unused
        }
    }

    /// Per-genre MIX GLUE (relative role levels, applied as velocity multipliers
    /// at generate time — velocity scales each voice's amplitude, so this is a
    /// pure level move, no audio-thread change). LEAD PULLED BACK across the board
    /// (founder 2026-07-07: "die meisten Genres hauen ihre Melodie unangenehm
    /// heraus … soll schön und entspannt sein") — the lead used to sit +5…+18%
    /// FORWARD in the synth genres; now it's tucked UNDER the pad (0.85–0.92)
    /// everywhere, so the melody supports the texture instead of blasting over it.
    /// Bass/pad glue unchanged. Everything stays gentle (0.85–1.18), no clip.
    public var mixLevels: (bass: Float, harmony: Float, lead: Float) {
        switch self {
        case .dubTechno, .trap:                       return (1.18, 0.94, 0.88)
        case .ska, .rocksteady, .disco:               return (1.10, 0.96, 0.90)
        case .synthwave, .eighties, .vaporwave, .earlySynth:
                                                      return (1.00, 0.94, 0.90)
        case .futuristic, .sciFi, .psytrance:         return (1.00, 0.92, 0.88)
        case .classical, .jazz, .klezmer, .oriental:  return (1.00, 1.00, 0.90)
        case .punk, .rock, .rocknroll, .heavyMetal, .doom:
                                                      return (1.10, 0.92, 0.90)
        case .esotericMeditation, .selfObservation:   return (0.95, 1.05, 0.85)
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

    /// Whether the style carries drums. Since audit B5 (2026-07-04) this is every
    /// genre whose archetype isn't `.none` — only classical/meditation/
    /// self-observation stay drum-free by design.
    public var isBeatDriven: Bool {
        beatArchetype != .none
    }

    /// How a non-beat style voices its harmony. Beat genres + self-observation
    /// don't use this (their melody is bespoke) but return a sane default so the
    /// switch stays total.
    public var harmonicProfile: HarmonicProfile {
        switch self {
        case .vaporwave:
            // PURE FLÄCHE (founder 2026-07-09): NO lead, sustained. Character =
            // the dreamy maj7 I→IV swell one register above the darker genres.
            return HarmonicProfile(progression: [0, 3], chordTones: [0, 2, 4, 6],
                                   padOctave: 4, leadOctave: 5, arpeggiated: false,
                                   leadDensity: 0.0, sustained: true)
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
            // PURE FLÄCHE (founder 2026-07-09: "reine Wellen-Töne stechen raus …
            // besser wenn die komplett weg sind — nur chillige mystische Flächen"):
            // NO lead, sustained. Character = phrygian i→♭II drift in a low
            // register — the eerie deep-space slide, held, never a tune.
            return HarmonicProfile(progression: [0, 1], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false,
                                   leadDensity: 0.0, sustained: true)
        case .psytrance:
            return HarmonicProfile(progression: [0], chordTones: [0, 2, 4],
                                   padOctave: 2, leadOctave: 4, arpeggiated: true, leadDensity: 0.7)
        case .esotericMeditation:
            // WEITERGEHEN (founder 2026-07-11: "bleibt auf Flächen liegen … soll
            // weitergehen und sich mit dem Herzschlag weiterentwickeln"). A frozen
            // single-chord drone [0] can never move; a gentle lydian journey (I → II
            // → V, the #4 shimmer) lets the held pad TRAVEL. Still sustained + NO lead
            // — one chord is held per bar (stillness preserved), but WHICH chord
            // advances with the bio-cadenced evolve (see BioComposer.progressionPhase).
            return HarmonicProfile(progression: [0, 1, 4], chordTones: [0, 2, 4, 6],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false,
                                   leadDensity: 0.0, sustained: true)
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
            // Rockakkorde (founder 2026-07-11): a real POWER CHORD = root + fifth +
            // octave root ([0,4,7]), the chunky rock/punk voicing, not a bare dyad.
            return HarmonicProfile(progression: [0, 3, 4], chordTones: [0, 4, 7],
                                   padOctave: 3, leadOctave: 4, arpeggiated: false, leadDensity: 0.4)
        case .rocknroll:
            return HarmonicProfile(progression: [0, 3, 4], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false, leadDensity: 0.5)
        case .rock:
            // Rockakkorde (founder 2026-07-11): full power chord (root + fifth + octave).
            return HarmonicProfile(progression: [0, 5, 3, 4], chordTones: [0, 4, 7],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false, leadDensity: 0.5)
        case .ska:
            return HarmonicProfile(progression: [0, 3, 4], chordTones: [0, 2, 4],
                                   padOctave: 4, leadOctave: 5, arpeggiated: true, leadDensity: 0.5)
        case .rocksteady:
            return HarmonicProfile(progression: [0, 5, 3, 4], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 4, arpeggiated: false, leadDensity: 0.4)
        case .heavyMetal:
            // Rockakkorde (founder 2026-07-11): low, dark power chord (root+fifth+octave)
            // in phrygian — the metal chug.
            return HarmonicProfile(progression: [0, 1, 0], chordTones: [0, 4, 7],
                                   padOctave: 2, leadOctave: 4, arpeggiated: false, leadDensity: 0.5)
        case .doom:
            // Rockakkorde (founder 2026-07-11): crushing downtuned power chord.
            return HarmonicProfile(progression: [0], chordTones: [0, 4, 7],
                                   padOctave: 2, leadOctave: 3, arpeggiated: false, leadDensity: 0.2)
        case .dubTechno:
            // PURE FLÄCHE (founder 2026-07-09): NO lead, sustained — the bespoke
            // offbeat stabs are retired from the flow (see BioComposer.compose).
            // Character = deep dorian m7 chords an octave under vaporwave; the
            // tape echo + the signature dub beat carry the genre.
            return HarmonicProfile(progression: [0, 3], chordTones: [0, 2, 4, 6],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false,
                                   leadDensity: 0.0, sustained: true)
        case .trap:
            // PURE FLÄCHE (founder 2026-07-09): the dark-bell lead — the exposed
            // pure-wave line the founder flagged as "zu laut, unangenehm" — is
            // GONE. Character = harmonic-minor i→VI in a low, smoky register;
            // the 808 beat + FX space do the talking.
            return HarmonicProfile(progression: [0, 5], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false,
                                   leadDensity: 0.0, sustained: true)
        case .selfObservation:
            // A TRUE DRONE, not a melody-over-chord-change (founder 2026-07-07:
            // "der Sound ist noch nicht sphärisch und beruhigend … reine
            // meditative Flächen … kohärentes Timbre am Start"). One sustained
            // tonic (no chord movement = maximally still + coherent), a lush open
            // 7th voicing, dropped an octave for warmth, and NO lead line
            // (leadDensity 0 = pure Fläche, no noodling). This is the single
            // biggest fix for "trashig/nicht sphärisch": the take opens on a
            // stable, wide, still pad instead of a wandering tune. AESTHETIC
            // (timbre evidence is thin) but consistent with the replicated
            // finding that tempo — not melodic activity — drives arousal, so a
            // still drone at ~58 bpm is the calmest possible starting material.
            // See scratchpads/RESEARCH_MEDITATION_ALGORITHM_2026-07-07.md.
            // WEITERGEHEN (founder 2026-07-11: "es soll ja weitergehen und sich mit
            // dem Herzschlag weiterentwickeln"). The single frozen tonic [0] is what
            // "bleibt auf der Fläche liegen"; a gentle minor journey (i → VI → iv, all
            // diatonic, resolves back to i at the wrap) lets it TRAVEL while staying
            // calm. Still one chord HELD per bar (per-bar stillness preserved) + NO
            // lead — the chord that is held advances with progressionPhase, so the pad
            // develops across bars/evolves instead of holding one chord forever.
            return HarmonicProfile(progression: [0, 5, 3], chordTones: [0, 2, 4, 6],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false,
                                   leadDensity: 0.0, sustained: true)
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
