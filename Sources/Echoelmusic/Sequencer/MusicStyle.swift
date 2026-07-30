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
//     • Disco · 80s · Early Synth · Futuristic · Psytrance · Synthwave · Acid Techno (floor)
//     • Rock · Punk · Rock'n'Roll · Heavy Metal · Jazz · Oriental (backbeat)
//     • Ska · Rocksteady · Klezmer · Deep House (offbeat skank)  ·  Doom · Vaporwave · Sci-Fi (half-time)
//   Drum-free by design:
//     • Classical · Meditation · Self-Observation · Drift · Contemplation (breath-paced, sync-free)
//     • Still Drone · Ambient Pulse (#254 batch 2 — the two poles of the ambient family:
//       an unmoving low quartal drone, and the family's only genre with MOTION)
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
    ///
    /// ⛔ **EVERY CURATED GENRE SETS THIS TO 0 TODAY** — no count is given here on purpose: the
    /// number was "25" for weeks and went stale twice in one day as #254 added genres, while the
    /// invariant itself never moved. Verified against `allCases` by
    /// `LeadRoleAbsenceTests` in the blocking bundle. So `composeHarmonic`'s whole melody block is
    /// unreachable and no `.lead`-role note is ever composed. The founder removed these melodies on
    /// 2026-07-09 ("zu laut und zu unnatürlich"); this field is the switch that turned them off and
    /// the switch that would turn them back on. Raising it on ANY genre is a founder decision that
    /// wakes FIVE dormant paths at once — `leadVoice` (a live `PolySynthVoice` attached to the engine
    /// and polling since launch with zero notes to play, and the one that would actually sound), the
    /// Lead mixer fader, `IntroAttenuation.leadFactor`, `tameLeadPitch`, and #253 A5's reverted
    /// Lead-rhythm row. The test's failure message carries the checklist in that order.
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
        .selfObservation, .esotericMeditation, .vaporwave, .dubTechno, .trap, .sciFi, .drift,
        .contemplation,
        // #254 batch 2: `deepDrone` is the stillest of them all. `ambientPulse` is deliberately
        // NOT here — it is the ambient genre that MOVES, and `sustained: true` would suppress
        // exactly the slow sequence that is its whole identity (see `HarmonicProfile.sustained`).
        .deepDrone
    ]

    /// The genres OFFERED in the picker — a curated, brand-fitting palette (founder
    /// 2026-07-24: "Genre is better you decide and curate something that really fits
    /// the brand … Die 6 ruhigen Genres. Aber erfinde noch passende dazu.
    /// Ambient-Meditation-drift-contemplation"). DECOUPLED from the full taxonomy
    /// below: every genre stays categorised (`Category.genres` is complete, so the
    /// enum + every exhaustive switch + stored @AppStorage values are untouched and
    /// reversible) — the picker simply shows only these. Echoel's identity is
    /// immersive · bio-reactive · contemplative (NOT wellness), so the base leans
    /// ambient/drift/cinematic. New ambient-family genres (plan G2) are appended here
    /// as they are built. Reversible: widen or narrow this list, no enum change.
    ///
    /// ⚠️ THE PALETTE IS NO LONGER ALL-CALM, and the invariant that said so is retired.
    /// Until #254 every offered genre was drum-free or a sustained Fläche, and
    /// `MusicStyleTests` asserted exactly that. On 2026-07-30 the founder asked for the
    /// opposite in the same sentence as the ambient ask: "mehr Genres der elektronischen Musik
    /// benötigt, verschiedenste Techno und House Stile aber auch Ambient und meditations Musik,
    /// Trance, acid etc".
    ///
    /// ⚠️ CORRECTION TO THE FIRST VERSION OF THIS PARAGRAPH: it said "a techno or house genre
    /// CANNOT be a sustained Fläche", and that is false — `dubTechno` is a techno genre with
    /// `sustained: true`, and it satisfied the old loop for months. So the old assertion and the
    /// founder's ask were never logically incompatible. What is incompatible is the old assertion
    /// with THESE TWO DESIGNS: an acid line is a sequence and a house chord lands on the offbeat,
    /// so making either one sustained would make it not-acid and not-house — i.e. exactly the
    /// "everything sounds the same" convergence the founder reported twice (#81, #125). The real
    /// choice was therefore between honouring the genres he named and honouring a test-encoded
    /// inference from an earlier curation, and the named genres win. Stating it as a logical
    /// impossibility mattered because that is how a hard-to-reverse removal gets re-justified
    /// without being re-examined — the next batch must make this argument again on its own facts,
    /// not cite this one.
    ///
    /// What is still guarded (and now in the BLOCKING bundle,
    /// `Tests/CISmoke/GenreFamilyDistinctnessTests`, because the other suite cannot fail a
    /// merge — #208): the DEFAULT genre is calm, so a fresh install still opens on a still
    /// Fläche, and the calm family is not crowded out. Widening the palette is allowed;
    /// replacing its centre is a founder call.
    ///
    /// "Reversible" is true for the CODE, not for a user's stored pick: `EchoelStudioView`'s
    /// onAppear snaps a persisted style that is no longer offered back to the default, and
    /// that write is destructive. Widening this list again restores the choice for everyone
    /// going forward, but cannot give an already-migrated user their old genre back.
    public static let offered: [MusicStyle] = [
        .selfObservation, .esotericMeditation, .drift, .contemplation,
        .vaporwave, .sciFi, .classical, .dubTechno,
        // #254 batch 1 (founder 2026-07-30: "mehr Genres der elektronischen Musik benötigt,
        // verschiedenste Techno und House Stile … Trance, acid"). Added HERE and not only to the
        // taxonomy on purpose: before this, ONE of the eight offered genres was electronic
        // (`dubTechno`), so a new electronic genre left out of this list would be a doorless
        // genre — built, categorised, and unreachable. That is the trap this repo keeps paying
        // for. Seven older electronic genres (trap, psytrance, synthwave, earlySynth, eighties,
        // disco, futuristic) stay OUT: they were curated out on 2026-07-24 by ear, and re-offering
        // them is a listening decision, not a side effect of this batch.
        .acidTechno, .deepHouse,
        // #254 batch 2 (same ask, "aber auch Ambient und meditations Musik"). Built SECOND on
        // purpose: batch 1 shifted the palette toward driving genres, and this is the half of the
        // founder's sentence that restores the contemplative centre rather than diluting it —
        // offered calm goes from 7 of 10 to 8 of 12.
        .deepDrone, .ambientPulse
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
        ///
        /// ⛔ These four were GERMAN until 2026-07-29 ("Meditativ & Ambient", "Elektronisch &
        /// Beats", "Rock & Energie", "Akustisch & Global") and shipped that way inside a bundle
        /// whose `CFBundleDevelopmentRegion` is `en` — a top-level picker header in a language
        /// the bundle does not claim to speak. Fixed to English BEFORE any String Catalog
        /// exists, deliberately and in this order: the catalog extracts the base language as
        /// the source text, so a German literal left here would have been frozen as the key
        /// every other language translates FROM. German comes back as a real translation, not
        /// as an accident.
        public var title: String {
            switch self {
            case .meditative: return "Meditative & Ambient"
            case .electronic: return "Electronic & Beats"
            case .rock:       return "Rock & Energy"
            case .acoustic:   return "Acoustic & Global"
            }
        }

        /// The genres in this group, in display order. This is the FULL taxonomy
        /// (every genre categorised) — the picker shows `offeredGenres`, not this.
        public var genres: [MusicStyle] {
            switch self {
            case .meditative: return [.selfObservation, .esotericMeditation, .drift, .contemplation,
                                      .deepDrone, .ambientPulse, .vaporwave, .sciFi]
            case .electronic: return [.dubTechno, .acidTechno, .deepHouse, .trap, .psytrance,
                                      .synthwave, .earlySynth, .eighties, .disco, .futuristic]
            case .rock:       return [.rock, .punk, .rocknroll, .heavyMetal, .doom]
            case .acoustic:   return [.classical, .jazz, .klezmer, .oriental, .ska, .rocksteady]
            }
        }

        /// The subset of this group's genres that are actually OFFERED in the picker
        /// (founder 2026-07-24 curation — see `MusicStyle.offered`). A category with
        /// no offered genres is skipped in the picker (no empty section header).
        public var offeredGenres: [MusicStyle] {
            genres.filter(MusicStyle.offered.contains)
        }
    }

    /// Which logical group this genre belongs to (total — every case mapped exactly
    /// once; guarded in MusicStyleTests).
    public var category: Category {
        switch self {
        case .selfObservation, .esotericMeditation, .drift, .contemplation, .vaporwave, .sciFi,
             .deepDrone, .ambientPulse:
            return .meditative
        case .dubTechno, .acidTechno, .deepHouse, .trap, .psytrance, .synthwave, .earlySynth,
             .eighties, .disco, .futuristic:
            return .electronic
        case .rock, .punk, .rocknroll, .heavyMetal, .doom:
            return .rock
        case .classical, .jazz, .klezmer, .oriental, .ska, .rocksteady:
            return .acoustic
        }
    }

    case dubTechno
    /// #254 batch 1 (founder 2026-07-30 "verschiedenste Techno und House Stile … acid"): the
    /// relentless acid pole — a fast, machine-straight phrygian SEQUENCE (arpeggiated, plain
    /// triads, resonant squelch). Deliberately the opposite of `dubTechno`, the only electronic
    /// genre offered before it: that one is a sustained dorian Fläche at ~124, this one an
    /// arpeggiated phrygian pulse at ~134.
    ///
    /// ⛔ "STABBED ON THE BEAT" IS REMOVED FROM THIS DOC — IT WAS FALSE. It stood here for one
    /// commit, and it is the exact class of comment that makes the next session plan from
    /// fiction. `beatArchetype .fourOnFloor` maps to `chordArticulation .stab`, but
    /// `chordArticulation` documents itself (see it below) as unread by ARPEGGIATED genres:
    /// `composeHarmonic` sends `arpeggiated: true` profiles down the arp branch, which never
    /// looks at the articulation. So acid's `.stab` is inert, and what actually sounds is the arp
    /// rate (`arpStep`) — which at 134 bpm coarsens to 4 or 8 sixteenths, i.e. a broken chord,
    /// not yet a driving 303 line. Making it bite is a separate slice (#254 follow-up), not a
    /// claim to make here.
    ///
    /// ⚠️ ITS REAL NEIGHBOUR IS `psytrance`, NOT `dubTechno`, and this is stated because no test
    /// enforces it: psytrance is also phrygian, also arpeggiated, also four-on-the-floor, and it
    /// is NOT in `offered`, so the distinctness sweep never compares the two. They are separated
    /// on tempo (130…139 vs 140…150), register (padOctave 3 vs 2), chord count ([0,4] vs a single
    /// [0]) and FX (acid is the ONLY genre that enables the resonant chain filter; psytrance rolls
    /// a 16th ping-pong). ⚠️ NOT on rhythm: both coarsen to the same `arpStep` at their default
    /// tempos, so a listener hears the same note RATE — the separation is timbre, harmony and
    /// register only. If psytrance is ever re-offered, listen to them back to back before
    /// shipping both. Asserted where it can be: `Tests/CISmoke/GenreFamilyDistinctnessTests`.
    case acidTechno
    /// #254 batch 1 (same ask, "House Stile"): the warm pole — swung, lush minor 7ths held in a
    /// HIGH register and articulated on the OFFBEAT (the house chord "&"), where acid stabs on
    /// the beat. See `beatArchetype` for why a house genre carries `.offbeat` rather than
    /// `.fourOnFloor`: since #166/#167 the archetype's only audible consequence is the pad's
    /// articulation, and the offbeat skank IS the house chord.
    case deepHouse
    /// #254 batch 2 (founder 2026-07-30 "aber auch Ambient und meditations Musik"): stillness
    /// taken FURTHER than any Fläche already offered, and separated from all six of them on four
    /// axes at once rather than on a different chord.
    ///
    ///   · **`pentatonicMinor`** — no genre in the roster uses a pentatonic scale. Five notes, no
    ///     semitone anywhere, so nothing in the drone can create tension; the six existing calm
    ///     genres are all seven-note modes (minor / lydian / dorian / mixolydian / major /
    ///     phrygian) and every one of them contains SEMITONES — natural minor has 2–3 and 7–8,
    ///     dorian and mixolydian likewise. (An earlier version of this line said "leading-tone
    ///     pull", which is wrong for three of the six: minor, dorian and mixolydian all have a
    ///     flat seventh and therefore no leading tone at all. Semitone tension is the real
    ///     contrast, and it is the one a pentatonic scale genuinely cannot produce.)
    ///   · **Quartal voicing** `[0, 3, 6]` — on a FIVE-note scale those degrees resolve (via
    ///     `MusicalKey.degree`, which wraps past the scale length) to root + fifth + minor tenth:
    ///     an open, wide, neither-major-nor-minor stack. Every other genre is a `[0,2,4]` triad or
    ///     a `[0,2,4,6]` seventh.
    ///   · **`padOctave: 2`** — the lowest of any offered genre (the rest sit at 3 or 4). Only the
    ///     root is genuinely low; the other two voices sit a fifth (+7) and a minor tenth (+15)
    ///     above it — not "an octave above", which is what this line first said. The stack spans
    ///     more than an octave, so it is a wide drone rather than a low mud cluster.
    ///   · **ONE frozen root** `[0]` — the only offered calm genre that does not travel at all.
    ///     `selfObservation` deliberately gained a i–VI–iv journey on 2026-07-11 ("es soll ja
    ///     weitergehen"); this genre is the other answer to the same question, kept because
    ///     stillness that genuinely does not move is a different experience, not a lesser one.
    ///     Movement here comes only from the body, the slow evolve and the long tape space.
    case deepDrone
    /// #254 batch 2 (same ask): the ambient genre that MOVES — and the only calm genre that does.
    /// A slow hypnotic pentatonic-major sequence, not a held pad.
    ///
    /// ⭐ WHY THIS IS NOT "acid but slower", which is the trap it would otherwise fall into: both
    /// are `arpeggiated`, and an arp genre's audible rhythm is `arpStep` in `BioComposer`
    /// (`(busy > 0.6 ? 2 : 4) * (densityScale < 0.8 ? 2 : 1)`), NOT `chordArticulation` — that was
    /// the correction this batch's predecessor had to make. The doubling switches on when
    /// `tempoDensityScale(bpm) < 0.8`, which is above **110 BPM** — solved numerically, not the
    /// "≈ >~106 BPM" the composer's own comment at that line estimates (0.8014 at 109, 0.7952 at
    /// 110). The difference does not matter for either genre here, but the accurate figure is the
    /// one to reason from. This genre's WHOLE tempo window
    /// 78…92 stays above 0.8 (0.925 at 92, 1.0 at ≤84), so it never coarsens: 8th notes when the
    /// body is busy, quarters when it is calm. `acidTechno` at 130…139 is always past the switch
    /// and always doubled. The two therefore differ in note RATE by a factor of two on top of
    /// scale, voicing, register and FX — and that is a traceable consequence of the tempo window,
    /// not an assertion about intent. Pinned in `Tests/CISmoke/GenreFamilyDistinctnessTests`.
    ///
    /// NOT `sustained`: that flag suppresses the inner pulse and the walking bass, which would
    /// delete the sequence. So it is the one calm genre that is lead-BEARING (see `leadPatchName`).
    case ambientPulse
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
    /// G2 (founder 2026-07-24 "erfinde noch passende dazu. Ambient-Meditation-drift-
    /// contemplation"): a drum-free contemplative Fläche — dorian i→v drift held one
    /// octave above the darker meditation/self-observation pads, so it reads airier
    /// and weightless. Distinct scale·progression·register from the other two
    /// drum-free Flächen (guarded by the distinctness tests).
    case drift
    /// G2 (founder 2026-07-24, same ask): a deep, grounded contemplative Fläche —
    /// low mixolydian i→♭VII, held in a LOW register (the opposite pole to drift's
    /// airy float), darkest and slowest of the ambient family. Distinct
    /// scale·progression·register from every other drum-free Fläche.
    case contemplation

    public var id: String { rawValue }

    /// UI title.
    public var displayName: String {
        switch self {
        case .dubTechno:          return "Dub Techno"
        case .acidTechno:         return "Acid Techno"
        case .deepHouse:          return "Deep House"
        // ⚠️ "Still Drone", not "Deep Drone": `esotericMeditation`'s PATCH is already named
        // "Deep Drone" (GenrePatches "DC"), and picking a genre writes its patch into the
        // visible patch field — so a picker entry "Deep Drone" next to a patch field reading
        // "Deep Drone" for a DIFFERENT genre is a real confusion. The genre is renamed rather
        // than the shipped patch, because a user may have saved a copy under that patch name.
        case .deepDrone:          return "Still Drone"
        case .ambientPulse:       return "Ambient Pulse"
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
        case .drift:              return "Drift"
        case .contemplation:      return "Contemplation"
        }
    }

    /// A short sound-character subtitle. Purely descriptive — no artist, label,
    /// or film names (App Store-safe, no implied endorsement).
    public var lineage: String {
        switch self {
        case .dubTechno:          return "Deep dub chords · tape echo · sub-bass"
        // "303" removed: it is a hardware model designation, and this file's own rule (top of
        // file) bans product/artist names in user-facing subtitles. "Squelch" carries the sound.
        case .acidTechno:         return "Squelching resonant sequence · relentless phrygian pulse"
        case .deepHouse:          return "Warm minor 7ths · swung offbeat chord"
        case .deepDrone:          return "One low quartal drone · unmoving · very wide"
        // "hypnotic" removed: it is the closest thing in the roster to altered-state language,
        // and this repo already keeps such words out of shipped strings (esotericMeditation is
        // surfaced as the neutral "Deep Ambient"). The word stays in the internal docs, where
        // it describes the sound accurately without making a claim to a user.
        case .ambientPulse:       return "Slow pentatonic sequence · calm motion"
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
        case .drift:              return "Weightless drift · wide dorian pads · airy"
        case .contemplation:      return "Grounded stillness · low mixolydian pad · unhurried"
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
        // #254 note on .acidTechno: it is here for taxonomy, but the `.stab` articulation
        // this maps to is INERT for it — arpeggiated profiles bypass `chordArticulation`
        // entirely (see that property's own doc). Nothing audible follows from this line
        // for acid today; do not "fix" acid's rhythm by changing the archetype.
        case .disco, .eighties, .earlySynth, .futuristic,
             .psytrance, .synthwave, .acidTechno:               return .fourOnFloor
        // #254: deepHouse is four-to-the-floor MUSICALLY, but the archetype's only audible
        // consequence since #166/#167 (no drum sounds) is `chordArticulation` — and a house
        // chord lands on the OFFBEAT, which is `.skank`. Picking `.fourOnFloor` here would give
        // it acid's on-beat `.stab` and erase the one axis that separates the two new genres.
        // If drums ever return, revisit this line FIRST: the drum pattern would then be a ska
        // upstroke, which is wrong for house.
        case .deepHouse:                                        return .offbeat
        case .rock, .punk, .rocknroll, .heavyMetal,
             .jazz, .oriental:                                  return .backbeat
        case .ska, .rocksteady, .klezmer:                       return .offbeat
        case .doom, .vaporwave, .sciFi:                         return .halfTime
        case .classical, .esotericMeditation, .selfObservation, .drift, .contemplation,
             .deepDrone, .ambientPulse:                         return .none
        }
    }

    /// How the AUDIBLE pad chords are articulated in time — the genre's rhythmic
    /// fingerprint on the layer you actually hear (drums are muted, auto-leads off).
    /// This is the fix for "I go through the genres and after a while everything
    /// sounds the same" (founder 2026-07-22): the 13 `sustained:true` genres all ran
    /// through ONE genre-blind heartbeat onset pattern, so only harmony + timbre
    /// differed — the weakest cues on a held pad. Rhythm is the strongest genre cue,
    /// so it must live on the audible chords. Derived from the existing `beatArchetype`
    /// (which already knows each genre's groove) — no new per-genre table. The bio
    /// `energy` still scales density/intensity ON TOP; the signature is always present
    /// (= "erst individuell"). `.sustained` is the meditative/ambient calm-is-still
    /// core and delegates to the unchanged heartbeat Fläche.
    public enum ChordArticulation: Sendable, Equatable {
        /// Reggae/ska skank — short chord chops on the offbeat 8ths.
        case skank
        /// Disco/house stab — chord on the beats, driving pulse when the body is up.
        case stab
        /// Jazz/rock comp — emphasis on beats 2 & 4 with syncopation when aroused.
        case comp
        /// Meditative/ambient held Fläche — delegates to the heartbeat onsets (calm = still).
        case sustained
    }

    /// The chord articulation for the audible pad, mapped from the genre's groove
    /// archetype. Arpeggiated genres take their own arp path upstream and are
    /// unaffected; only the `sustained:true` pad genres are routed here.
    public var chordArticulation: ChordArticulation {
        switch beatArchetype {
        case .offbeat:                       return .skank
        case .fourOnFloor:                   return .stab
        case .backbeat:                      return .comp
        case .halfTime, .none, .signature:   return .sustained
        }
    }

    /// A tiny per-genre rhythmic fingerprint layered ON TOP of a shared beat
    /// archetype (Slice A, task #79 — "rhythmische Vielfalt"). The 4 archetype
    /// builders in `BioComposer` stay the single source of the core groove
    /// (kick-every-beat, backbeat clap, …); this overlay makes genres that share
    /// an archetype hearably distinct WITHOUT writing one beat function per genre.
    /// Hard-capped at three fields on purpose (Architect: no catch-all for
    /// arbitrary special cases). Purely declarative — no bio, no RNG — so it never
    /// perturbs the seeded melody/percussion draws and stays deterministic.
    /// The closed-hat texture a genre keeps EVEN when the body is calm — the
    /// single most audible rhythmic fingerprint (task #79 follow-up, founder
    /// 2026-07-22 "ich gehe durch die Genres und nach kurzer Zeit klingt alles wie
    /// classic"). Unlike the energy-gated ornaments that strip when settled, a
    /// genre's `hatRate` is RNG-free and always applied, so two same-archetype
    /// genres stay audibly distinct at full calm. `.inherit` (the default) is a
    /// no-op — the archetype's own hats stand (no shipping genre uses it; task #82).
    public enum HatRate: Sendable, Equatable {
        /// No genre override — the archetype's own base+energy hats stand (default;
        /// no shipping genre uses it since task #82).
        case inherit
        /// Closed hats only on the offbeat 8ths (2/6/10/14) — the disco/house "tss".
        case offbeat
        /// Closed hats on every 8th (0…14 by 2) — a driving, busy pulse.
        case driving
        /// Closed hats on every 16th — a rolling, energetic shimmer (psy/DnB).
        case sixteenth
        /// Closed hats on the quarter notes only (0/4/8/12) — laid-back keep-time.
        case quarter
        /// Closed hats only on 1 & 3 (0/8) — maximal air (doom's heavy space).
        case sparse
    }

    public struct GenreFlavor: Sendable, Equatable {
        /// DEPRECATED / vestigial (task #82): no code reads this any more. It used to
        /// tilt the closed-hat texture, but `hatRate` now owns that row and every
        /// shipping genre carries an explicit non-`.inherit` `hatRate`. Retained only
        /// so the per-genre `GenreFlavor` initializers stay source-stable; safe to drop
        /// in a future cleanup once the initializers are updated.
        public var hatDensityBias: Float
        /// The 16th step a single genre-signature perc ghost lands on. Choosing a
        /// distinct step per genre guarantees two same-archetype genres never
        /// produce bit-identical `drumSteps`. Kept off the beat/clap/seeded-perc
        /// slots so it reads as its own fingerprint.
        public var percGhostStep: Int
        /// Adds a syncopated kick push into the "1" (step 14) — an extra hit only,
        /// never touching the on-every-beat kicks that define the archetype.
        public var kickPushEnabled: Bool
        /// The genre's calm-surviving closed-hat texture. `.inherit` (default) leaves
        /// the archetype's own hats untouched; any other value SETS the closed-hat row
        /// deterministically so the genre reads distinctly even when settled (and adds
        /// an additive energy overlay on top — see `applyHatRate`).
        public var hatRate: HatRate
        /// A second genre-signature kick step (an EXTRA hit, like `percGhostStep` but
        /// on the kick track) that survives the calm strip. `-1` = none. Distinct per
        /// genre so same-archetype genres diverge on the kick as well as the perc.
        public var kickCell: Int

        public init(hatDensityBias: Float, percGhostStep: Int, kickPushEnabled: Bool,
                    hatRate: HatRate = .inherit, kickCell: Int = -1) {
            self.hatDensityBias = hatDensityBias
            self.percGhostStep = percGhostStep
            self.kickPushEnabled = kickPushEnabled
            self.hatRate = hatRate
            self.kickCell = kickCell
        }

        /// Neutral overlay — leaves an archetype builder exactly as it was.
        public static let neutral = GenreFlavor(hatDensityBias: 0, percGhostStep: -1,
                                                kickPushEnabled: false)
    }

    /// The genre's rhythmic fingerprint (see `GenreFlavor`). Declared here next to
    /// `beatArchetype` so the per-genre character lives with the rest of the genre
    /// identity. SIX of the seven `.fourOnFloor` genres (Slice A) and the six `.backbeat`
    /// genres (Slice B — rock family) carry a distinct flavor; every other genre
    /// returns `.neutral` (no behaviour change).
    ///
    /// ⚠️ #254's `acidTechno` (`.fourOnFloor`) and `deepHouse` (`.offbeat`) are the two that
    /// deliberately fall through to `.neutral`. That is not an oversight and it costs nothing
    /// TODAY — the whole `GenreFlavor` output reaches no voice since #166/#167 removed the drums
    /// (`drumSteps` is read only by `Project` persistence and one `BioVariationMaze` metric).
    /// Inventing a hat texture and a ghost step for an inaudible track would be fiction dressed
    /// as design. But it means the "unique perc-ghost step" invariant below no longer covers the
    /// whole roster: if drums ever return, these two are the ONLY genres without a fingerprint,
    /// and giving them one is the first thing to do.
    public var beatFlavor: GenreFlavor {
        switch self {
        // The six four-on-floor genres WITH A FLAVOR (acidTechno is a seventh and has none —
        // see the property doc): each gets its own hat texture + a unique
        // perc-ghost step so they stop sharing one loop. Ghost steps are all off
        // the kick beats (0/4/8/12), the claps (4/12) and the seeded perc (7/15).
        case .disco:      return GenreFlavor(hatDensityBias:  0.7, percGhostStep:  3, kickPushEnabled: false, hatRate: .offbeat)
        case .eighties:   return GenreFlavor(hatDensityBias:  0.0, percGhostStep:  5, kickPushEnabled: false, hatRate: .driving,   kickCell: 6)
        case .earlySynth: return GenreFlavor(hatDensityBias: -0.7, percGhostStep:  9, kickPushEnabled: false, hatRate: .quarter)
        case .futuristic: return GenreFlavor(hatDensityBias:  0.0, percGhostStep: 11, kickPushEnabled: true,  hatRate: .sixteenth, kickCell: 10)
        case .psytrance:  return GenreFlavor(hatDensityBias:  0.7, percGhostStep: 13, kickPushEnabled: true,  hatRate: .sixteenth, kickCell: 6)
        case .synthwave:  return GenreFlavor(hatDensityBias: -0.7, percGhostStep:  1, kickPushEnabled: false, hatRate: .sparse)
        // The six backbeat genres (rock family): the perc track is free in this
        // archetype, so each genre's ghost step is collision-free by construction;
        // all six steps are distinct AND off the snare backbeat (4/12) and the
        // kick anchors (0/8/10/6). Hat bias tilts the driving 8th-hat texture:
        // punk/metal drive to 16ths, jazz/oriental breathe. kickPush adds an extra
        // syncopated kick into the "1" for the two most aggressive genres only.
        case .rock:       return GenreFlavor(hatDensityBias:  0.0, percGhostStep:  6, kickPushEnabled: false, hatRate: .driving)
        case .punk:       return GenreFlavor(hatDensityBias:  0.7, percGhostStep: 15, kickPushEnabled: true,  hatRate: .sixteenth, kickCell: 6)
        case .rocknroll:  return GenreFlavor(hatDensityBias:  0.0, percGhostStep:  3, kickPushEnabled: false, hatRate: .offbeat)
        case .heavyMetal: return GenreFlavor(hatDensityBias:  0.7, percGhostStep: 11, kickPushEnabled: true,  hatRate: .sixteenth, kickCell: 2)
        case .jazz:       return GenreFlavor(hatDensityBias: -0.7, percGhostStep:  5, kickPushEnabled: false, hatRate: .quarter)
        case .oriental:   return GenreFlavor(hatDensityBias: -0.7, percGhostStep:  9, kickPushEnabled: false, hatRate: .sparse)
        // The three offbeat (skank) genres WITH A FLAVOR (deepHouse is a fourth and has none —
        // see the property doc): the archetype already occupies perc on
        // the offbeats 2/6/10/14, so each ghost step is chosen from the FREE perc
        // slots (3/11/5) — distinct and never colliding with the skank. Hat bias
        // tilts the skank/quarter-hat texture.
        case .ska:        return GenreFlavor(hatDensityBias:  0.7, percGhostStep:  3, kickPushEnabled: false, hatRate: .offbeat)
        case .rocksteady: return GenreFlavor(hatDensityBias: -0.7, percGhostStep: 11, kickPushEnabled: false, hatRate: .quarter)
        case .klezmer:    return GenreFlavor(hatDensityBias:  0.0, percGhostStep:  5, kickPushEnabled: true,  hatRate: .driving)
        // The three half-time genres: the perc track is free in this archetype, so
        // each ghost step (12/6/10) is collision-free by construction. Sparse bias
        // opens even more air (doom), dense adds 8th motion (sci-fi).
        case .doom:       return GenreFlavor(hatDensityBias: -0.7, percGhostStep: 12, kickPushEnabled: false, hatRate: .sparse)
        case .vaporwave:  return GenreFlavor(hatDensityBias:  0.0, percGhostStep:  6, kickPushEnabled: false, hatRate: .quarter)
        case .sciFi:      return GenreFlavor(hatDensityBias:  0.7, percGhostStep: 10, kickPushEnabled: true,  hatRate: .sixteenth, kickCell: 10)
        default:          return .neutral
        }
    }

    /// The BPM window a take locks within (Studio mode clamps into this).
    public var tempoRange: ClosedRange<Double> {
        switch self {
        case .dubTechno:          return 118...128
        // 130…139 keeps acid ENTIRELY below psytrance's 140…150. The two are close relatives
        // (both phrygian, both arpeggiated, both four-on-the-floor) so every axis that can
        // separate them should: tempo, register, chord count and the filter-vs-ping-pong FX.
        // ⚠️ 139, not 140 — the first version said "disjoint" while both ranges CONTAINED 140.
        // The guard test uses `<=` so it passed either way; the prose was what was wrong, and
        // tightening the range is the honest fix rather than softening the sentence.
        case .acidTechno:         return 130...139
        // Overlaps dubTechno's window on purpose — both really are ~124 genres. They are
        // separated on articulation, scale, register, 7ths and swing, not on tempo.
        case .deepHouse:          return 120...126
        // #254 batch 2. deepDrone goes BELOW every offered genre (contemplation's 44 was the
        // floor).
        // ⚠️ The first version of this line justified the 40 with "at 40 BPM a whole-note tape
        // echo is 6 seconds, which is the point" — and the SAME COMMIT corrected that claim in
        // `GenreFX`: the chain clamps any delay to 2.0 s, so a 6-second echo cannot happen. The
        // reason for going this low is the note pace and the drone's own stillness, nothing about
        // the echo. Closing a trap in one file and leaving it standing in another is worse than
        // not closing it, because the surviving copy reads as independent confirmation.
        //
        // ⚠️ LISTENING ITEM, not a defect: `defaultMode` is `.flowFree`, so the clock is
        // `StudioCalculator.genreTempo(body, into:)`, whose octave fold flips direction at
        // √(2·lo·hi) = 68.1 BPM here. A resting pulse wandering across 68 therefore jumps the
        // tempo between 58 and 40 (×1.45). Every calm genre has a sub-octave window and the same
        // property (contemplation 76.2, drift 84.3, selfObservation 84.7, ambientPulse 119.8) —
        // deepDrone's crossover is simply the lowest, so it sits inside a common resting band.
        // Raising it above ~85 would need an upper bound past 90 BPM, which is no longer a drone.
        // Left as-is deliberately: retuning four shipped windows is a founder listening call.
        case .deepDrone:          return 40...58
        // 78…92 is chosen for an ENGINE reason, not a feel: the arp's `arpStep` doubles only when
        // `tempoDensityScale(bpm) < 0.8` (above 110 BPM), so this whole window stays uncoarsened
        // (0.925 at 92) while `acidTechno` at 130…139 is always doubled (0.69 / 0.65). Widening
        // this range past 110 would silently halve the note rate — check the case doc first.
        // Pinned in `Tests/CISmoke/GenreFamilyDistinctnessTests`, which re-derives 110 from the
        // curve rather than hardcoding it.
        case .ambientPulse:       return 78...92
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
        // ⚠️ THE THREE CALM WINDOWS BELOW: their ceiling is what keeps the pad from
        // racing, and that still holds — nothing here can exceed 78 / 74 / 66 BPM.
        // But the WAY an elevated pulse is brought inside changed on 2026-07-29
        // (`StudioCalculator.genreTempo`), and these comments used to describe the
        // broken version. They said an elevated pulse "octave-folds DOWN". It did —
        // straight past the floor and back onto it, so 79 bpm on Fläche produced 46,
        // the SLOWEST tempo the window allows. Today a body just above the ceiling
        // holds AT the ceiling and only halves once it is closer to the floor's octave
        // (the crossover is √(2·lo·hi): 84.7 Fläche, 84.3 drift, 76.2 contemplation).
        // So: 79–84.7 on Fläche now gives 78, not 46. Calm is preserved by the
        // CEILING, not by a fold — do not "restore" the old behaviour from this note.
        //
        // Fläche window (founder 2026-07-07 "langsamere Vibes"): the ceiling
        // drops 100 -> 78 so the pad can never race; the floor still admits a deep
        // resting pulse (46).
        case .selfObservation:    return 46...78
        // Drift sits in the same calm band — a shade slower-centred than meditation
        // so the pad floats; the ceiling stays low so nothing hurries.
        case .drift:              return 48...74
        // Contemplation is the slowest, deepest ambient window — a still, grounded
        // pad; the lowest ceiling of the three.
        case .contemplation:      return 44...66
        }
    }

    /// The BPM a fresh take starts at, inside `tempoRange`.
    public var defaultTempo: Double {
        switch self {
        case .dubTechno:          return 124
        case .acidTechno:         return 134
        case .deepHouse:          return 122
        case .deepDrone:          return 48
        case .ambientPulse:       return 85
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
        case .drift:              return 60
        case .contemplation:      return 52
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
        // The swung house shuffle — the most of any OFFERED genre (next is vaporwave at
        // 0.15). NOT the most of any genre: jazz 0.34, rocknroll 0.28, rocksteady 0.22,
        // klezmer 0.20 and ska 0.18 all swing harder, and `MusicStyleSwingTests`
        // asserts jazz is the maximum. The unscoped claim stood here for one commit —
        // raising house to defend it would have reddened that test.
        case .deepHouse:          return 0.16
        case .acidTechno:         return 0.0    // machine-straight; a 303 line does not swing
        case .eighties:           return 0.06
        case .synthwave, .earlySynth, .futuristic, .sciFi, .psytrance,
             .esotericMeditation, .classical, .punk, .rock, .heavyMetal,
             .doom, .selfObservation, .drift, .contemplation,
             .deepDrone, .ambientPulse:
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
        // Every lead-bearing genre is now spread across the SIX approved warm patches as
        // evenly as the roster allows — guarded in `MusicStyleLeadTests` against the
        // DERIVED ceiling `ceil(leadBearing / warmPatches)`, not against a magic 3.
        // ⚠️ It WAS a magic 3, and #254 proved why that was wrong: its batch 1 took the
        // lead-bearing count from 17 to 19, and 6 patches × 3 = 18 makes "no more than
        // three" arithmetically IMPOSSIBLE — the test would have gone red on any
        // assignment whatsoever, which is a broken test rather than a broken design. The
        // derived form yields exactly 3 at 17 genres (so nothing was loosened) and 4 from
        // 19 on, and it forbids the thing the guard is actually for: a pile-up on one patch
        // while others sit nearly empty. Batch 2 then added `ambientPulse` (non-sustained,
        // so lead-bearing) → 20, and `deepDrone` (sustained, so NOT counted). At 20 the
        // ceiling is still 4 and the roster sits exactly on it (Soft Keys 4, Warm Strings
        // 4, the rest 3): ZERO HEADROOM. The next lead-bearing genre put on either of those
        // two names fails the guard, so pick one of the 3s. While every
        // lead stays inside the warm set — no shrill "Bright Lead"/"Glass Bell"/"Vapor
        // Lead" and no plastic real-instrument emulation ever returns. Character now
        // reads distinctly per genre (a plucky rock'n'roll vs a reedy rock vs Rhodes
        // jazz) without any bright/harsh reintroduction. Exact per-genre timbre is
        // device-tunable; the INVARIANT is: warm-set only + spread.
        switch self {
        case .dubTechno:          return "Pluck"         // sustained — unused
        // #254: both are lead-BEARING (not sustained), so both count against the spread
        // ceiling above even though no lead sounds today (#255). "Deep Sub" for acid is
        // both the honest spread choice (it left "Pluck" at 4 with 5 patches under-used)
        // and the musical one — a squelching low sequence, not a plucked string.
        case .acidTechno:         return "Deep Sub"      // no lead exists at all (#255)
        case .deepDrone:          return "Deep Sub"      // sustained — unused
        // #254 batch 2: ambientPulse is NOT sustained, so it IS lead-bearing and DOES count
        // against the spread ceiling above. "Warm Strings" stood at 3 of a ceiling of 4.
        case .ambientPulse:       return "Warm Strings"
        case .deepHouse:          return "Soft Keys"     // Rhodes-ish keys; no lead today (#255)
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
        case .drift:              return "Warm Strings"  // sustained — unused
        case .contemplation:      return "Choir Vox"     // sustained — unused
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
        case .acidTechno:                             return (1.15, 0.90, 0.88)  // bass-led
        case .deepHouse:                              return (1.06, 1.02, 0.90)  // chord-led
        case .ska, .rocksteady, .disco:               return (1.10, 0.96, 0.90)
        case .synthwave, .eighties, .vaporwave, .earlySynth:
                                                      return (1.00, 0.94, 0.90)
        case .futuristic, .sciFi, .psytrance:         return (1.00, 0.92, 0.88)
        case .classical, .jazz, .klezmer, .oriental:  return (1.00, 1.00, 0.90)
        case .punk, .rock, .rocknroll, .heavyMetal, .doom:
                                                      return (1.10, 0.92, 0.90)
        case .esotericMeditation, .selfObservation, .drift, .contemplation,
             .deepDrone, .ambientPulse:
                                                      return (0.95, 1.05, 0.85)
        }
    }

    /// The dark/bright, genre-appropriate scale a take defaults to.
    public var scale: Scale {
        switch self {
        case .dubTechno:          return .dorian
        case .acidTechno:         return .phrygian   // the ♭2 is the acid bite
        case .deepHouse:          return .minor
        // #254 batch 2 — the only two pentatonic genres in the roster. No semitone anywhere,
        // so nothing in either can create tension; every other genre is a 7-note mode.
        case .deepDrone:          return .pentatonicMinor
        case .ambientPulse:       return .pentatonicMajor
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
        case .drift:              return .dorian
        case .contemplation:      return .mixolydian
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
            // NO auto-lead (founder 2026-07-21: "Psytrance bis Rocksteady werden
            // sehr stressig wegen den Melodien. Melodien sollen die Leute selbst
            // machen") — same PURE FLÄCHE pattern already applied to the calmer
            // genres, extended to the whole remaining melodic roster. The lead
            // VOICE/timbre (leadPatchName) is unchanged — a user still plays their
            // own melody on it.
            return HarmonicProfile(progression: [0, 4, 5, 3], chordTones: [0, 2, 4],
                                   padOctave: 4, leadOctave: 5, arpeggiated: true, leadDensity: 0.0)
        case .disco:
            return HarmonicProfile(progression: [0, 3, 4], chordTones: [0, 2, 4, 6],
                                   padOctave: 4, leadOctave: 5, arpeggiated: false, leadDensity: 0.0)
        case .synthwave:
            return HarmonicProfile(progression: [0, 5, 3, 4], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 5, arpeggiated: true, leadDensity: 0.0)
        case .earlySynth:
            return HarmonicProfile(progression: [0, 0], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 4, arpeggiated: true, leadDensity: 0.0)
        case .futuristic:
            return HarmonicProfile(progression: [0, 1], chordTones: [0, 2, 4],
                                   padOctave: 4, leadOctave: 6, arpeggiated: false, leadDensity: 0.0)
        case .sciFi:
            // PURE FLÄCHE (founder 2026-07-09: "reine Wellen-Töne stechen raus …
            // besser wenn die komplett weg sind — nur chillige mystische Flächen"):
            // NO lead, sustained. Character = phrygian i→♭II drift in a low
            // register — the eerie deep-space slide, held, never a tune.
            return HarmonicProfile(progression: [0, 1], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false,
                                   leadDensity: 0.0, sustained: true)
        case .psytrance:
            // NO auto-lead (founder 2026-07-21, see .eighties above).
            return HarmonicProfile(progression: [0], chordTones: [0, 2, 4],
                                   padOctave: 2, leadOctave: 4, arpeggiated: true, leadDensity: 0.0)
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
            // NO auto-lead (founder 2026-07-21, see .eighties above).
            return HarmonicProfile(progression: [0, 3, 4, 0], chordTones: [0, 2, 4],
                                   padOctave: 4, leadOctave: 5, arpeggiated: false, leadDensity: 0.0)
        case .jazz:
            return HarmonicProfile(progression: [0, 3, 5, 1], chordTones: [0, 2, 4, 6],
                                   padOctave: 4, leadOctave: 5, arpeggiated: false, leadDensity: 0.0)
        case .klezmer:
            return HarmonicProfile(progression: [0, 3, 4], chordTones: [0, 2, 4],
                                   padOctave: 4, leadOctave: 5, arpeggiated: false, leadDensity: 0.0)
        case .oriental:
            return HarmonicProfile(progression: [0, 1], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false, leadDensity: 0.0)
        case .punk:
            // Rockakkorde (founder 2026-07-11): a real POWER CHORD = root + fifth +
            // octave root ([0,4,7]), the chunky rock/punk voicing, not a bare dyad.
            // NO auto-lead (founder 2026-07-21, see .eighties above).
            return HarmonicProfile(progression: [0, 3, 4], chordTones: [0, 4, 7],
                                   padOctave: 3, leadOctave: 4, arpeggiated: false, leadDensity: 0.0)
        case .rocknroll:
            return HarmonicProfile(progression: [0, 3, 4], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false, leadDensity: 0.0)
        case .rock:
            // Rockakkorde (founder 2026-07-11): full power chord (root + fifth + octave).
            return HarmonicProfile(progression: [0, 5, 3, 4], chordTones: [0, 4, 7],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false, leadDensity: 0.0)
        case .ska:
            return HarmonicProfile(progression: [0, 3, 4], chordTones: [0, 2, 4],
                                   padOctave: 4, leadOctave: 5, arpeggiated: true, leadDensity: 0.0)
        case .rocksteady:
            return HarmonicProfile(progression: [0, 5, 3, 4], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 4, arpeggiated: false, leadDensity: 0.0)
        case .heavyMetal:
            // Rockakkorde (founder 2026-07-11): low, dark power chord (root+fifth+octave)
            // in phrygian — the metal chug.
            return HarmonicProfile(progression: [0, 1, 0], chordTones: [0, 4, 7],
                                   padOctave: 2, leadOctave: 4, arpeggiated: false, leadDensity: 0.0)
        case .doom:
            // Rockakkorde (founder 2026-07-11): crushing downtuned power chord.
            return HarmonicProfile(progression: [0], chordTones: [0, 4, 7],
                                   padOctave: 2, leadOctave: 3, arpeggiated: false, leadDensity: 0.0)
        case .acidTechno:
            // #254 batch 1 — THE SEQUENCE, not a pad. `arpeggiated: true` is the whole point: a
            // 303 line is a rising figure, so the chord is broken into one, and PLAIN TRIADS
            // (not 7ths) keep it raw where deepHouse below is lush. Low register, two roots
            // only (i → v) so the relentlessness is the character. NOT sustained — it stabs.
            return HarmonicProfile(progression: [0, 4], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 5, arpeggiated: true,
                                   leadDensity: 0.0)
        case .deepHouse:
            // #254 batch 1 — the opposite pole to acidTechno on every audible axis: HELD lush
            // minor 7ths (not an arpeggio, not a triad) one octave HIGHER, over three roots so
            // the harmony actually travels. NOT sustained — the offbeat skank articulation is
            // what makes it house, and `sustained: true` would suppress that (it also kills the
            // walking bass and the inner pulse — see `HarmonicProfile.sustained`).
            //
            // ⚠️ THE PROGRESSION IS i → VII → VI, NOT the i → VI → iv this first shipped as. That
            // draft was note-for-note `selfObservation`'s progression AND chord tones AND scale —
            // the flagship calm Fläche — leaving only articulation, register and tempo to tell the
            // two apart. The distinctness sweep would still have passed it, and that is exactly
            // the #81/#125 defect the founder has reported twice ("plötzlich klingt alles gleich"):
            // a sweep that passes is not the same as two genres a listener can tell apart. The
            // descending i–VII–VI vamp is also the more house-authentic figure.
            return HarmonicProfile(progression: [0, 6, 5], chordTones: [0, 2, 4, 6],
                                   padOctave: 4, leadOctave: 5, arpeggiated: false,
                                   leadDensity: 0.0)
        case .deepDrone:
            // #254 batch 2 — the quartal drone. `[0, 3, 6]` on the FIVE-note pentatonicMinor
            // resolves through `MusicalKey.degree`'s octave wrap to root + fifth + minor tenth
            // (intervals [0,3,5,7,10]: degree 0 → +0, degree 3 → +7, degree 6 → +3 +12 = +15).
            // Deliberately NOT a triad or a 7th — those are what all six existing calm genres are.
            // padOctave 2 puts the root at MIDI 36, the same floor psytrance/metal/doom already
            // use, and the >1-octave spread keeps it open instead of muddy.
            // ONE frozen root, sustained: this is the stillest genre in the product.
            return HarmonicProfile(progression: [0], chordTones: [0, 3, 6],
                                   padOctave: 2, leadOctave: 4, arpeggiated: false,
                                   leadDensity: 0.0, sustained: true)
        case .ambientPulse:
            // #254 batch 2 — the calm family's ONLY moving genre. `[0, 2, 4]` on pentatonicMajor
            // ([0,2,4,7,9]) is root + major third + major sixth: an open 6th colour, not the triad
            // those same degrees would give on a 7-note mode. Two roots (degree 3 = +7, a fifth)
            // so it travels once per section instead of holding.
            // NOT sustained — see the case doc: that flag would delete the sequence.
            return HarmonicProfile(progression: [0, 3], chordTones: [0, 2, 4],
                                   padOctave: 4, leadOctave: 5, arpeggiated: true,
                                   leadDensity: 0.0)
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
        case .drift:
            // G2 contemplative Fläche (founder 2026-07-24 "Ambient-Meditation-drift-
            // contemplation"). A gentle dorian i → v drift (the raised-6th mode reads
            // hopeful-yet-unresolved — neither the dark minor of self-observation nor
            // the bright lydian of deep-ambient), a lush open 7th voicing, held one
            // octave ABOVE the other two drum-free Flächen so it floats airier. One
            // chord HELD per bar (stillness preserved) + NO lead — the held chord
            // advances with the bio-cadenced evolve like the sibling Flächen. Distinct
            // scale·progression·register from meditation/self-observation (guarded by
            // testSustainedFlächenStayDistinct + testEveryGenreHasADistinctMusicalIdentity).
            return HarmonicProfile(progression: [0, 4], chordTones: [0, 2, 4, 6],
                                   padOctave: 4, leadOctave: 5, arpeggiated: false,
                                   leadDensity: 0.0, sustained: true)
        case .contemplation:
            // G2 grounded Fläche (founder 2026-07-24, same ask). A low mixolydian
            // i → ♭VII rock (the flat-7 gives an open, unresolved, contemplative
            // suspension — distinct from drift's dorian and the siblings' minor/
            // lydian), a plain open triad (purer/simpler than drift's lush 7th) held
            // LOW (padOctave 3) so it sits grounded rather than airy. One chord HELD
            // per bar (stillness) + NO lead — the held chord advances with the
            // bio-cadenced evolve like every sibling Fläche. Its scale·progression·
            // register fingerprint is unique among the drum-free Flächen.
            return HarmonicProfile(progression: [0, 6], chordTones: [0, 2, 4],
                                   padOctave: 3, leadOctave: 5, arpeggiated: false,
                                   leadDensity: 0.0, sustained: true)
        }
    }

    /// The transport a fresh take of this style defaults to: meditation follows
    /// the heart (sync-free); everything else locks to a BPM for DAW handoff.
    public var defaultMode: ComposerMode {
        switch self {
        // #254 batch 2: both ambient additions MUST be listed here. This switch ends in
        // `default: .studioLocked`, so omitting them would have silently given two breath-paced
        // genres a locked grid tempo — the kind of wrong default a compiler cannot catch.
        case .selfObservation, .esotericMeditation, .drift, .contemplation,
             .deepDrone, .ambientPulse:              return .flowFree
        default:                                     return .studioLocked
        }
    }
}
