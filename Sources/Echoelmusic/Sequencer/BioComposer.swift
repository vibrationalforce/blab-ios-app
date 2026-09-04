// BioComposer.swift
// Echoel — the generative core: biodata → music, in one of two curated genres
// (Dub Techno / Trap) or a sync-free ambient mode for self-observation. There is
// NO generic beat-maker: every take sounds like its genre because the patterns
// are hand-shaped after the reference artists, and the biodata only animates the
// detail inside that frame.
//
// The kernel is PURE and SEEDED — same inputs + seed produce the same music — so
// it is fully unit-tested without any clock or audio, and a performer can
// reproduce a take.
//
// Bio mappings (deliberately musical, not random noise):
//   heart rate  → tempo (clamped into the style's BPM window) + rhythmic energy
//   coherence   → calm: more space, fewer hits (high) vs busier, denser (low)
//   breath phase→ melodic direction in the ambient mode (inhale rises, exhale falls)
//   breath depth→ velocity
// Every pitch is produced via MusicalKey.degree(...), so output is always in key.

import Foundation

/// Transport intent for a generated take.
public enum ComposerMode: String, Codable, Sendable {
    case studioLocked   // fixed BPM (e.g. 124 dub, 140 trap) for DAW handoff
    case flowFree       // tempo follows the heart, for meditation

    /// The user-facing Flow/Loop switch (M1). The two modes are a presentation of
    /// ONE truth — the tempo lock: **Loop** = a fixed BPM for production/DAW handoff
    /// (`studioLocked`), **Flow** = the tempo follows the body, for meditation
    /// (`flowFree`). Deriving the mode from the lock keeps the composer's transport
    /// intent, the saved project mode and the tempo-lock UI from ever disagreeing
    /// (before M1 the live path was hardcoded `.flowFree` regardless of the lock).
    public init(locked: Bool) {
        self = locked ? .studioLocked : .flowFree
    }
}

/// How the groove layer behaves (founder 2026-07-06C: "Beat soll ausschaltbar
/// sein und tendenziell eher schamanisch ur-rhythmisch"). Orthogonal to the
/// genre — the melody/pads always follow the chosen style; this only selects
/// the DRUM layer: `off` = pure Flächen, `pulse` = the shamanic ur-rhythm
/// (`BioComposer.shamanicBeat`, the DEFAULT), `genre` = the style's own
/// archetypal groove.
public enum BeatMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case off, pulse, genre
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .off:   return "Off"
        case .pulse: return "Pulse"
        case .genre: return "Genre"
        }
    }
}

/// A small, fast, fully-deterministic RNG (SplitMix64) so compositions are
/// reproducible from a seed. Pure value type.
public struct SeededRNG: Sendable {
    public private(set) var state: UInt64
    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform Float in [0, 1).
    public mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}

/// Continuous "mood"/character controls that shape the composition independently of
/// genre — they blend with each other and with the body. All 0…1. Neutral defaults
/// keep existing behaviour. (See `composeHarmonic`/`ambientMelody` for the mapping.)
public struct MoodProfile: Sendable, Equatable, Codable {
    public var liveliness: Float   // 0 sparse/still … 1 busy/active (density)
    public var darkness: Float     // 0 bright/high register … 1 dark/low register
    public var tension: Float      // 0 friendly/consonant … 1 scary/dissonant
    public var romance: Float      // 0 plain triads … 1 lush 7th-chord warmth
    public var weird: Float        // 0 predictable steps … 1 odd leaps + chromaticism
    public var virtuosity: Float   // 0 plain line … 1 grace runs + octave climaxes
    public var syncopation: Float  // 0 on-the-beat … 1 pushed off-beat placement
    public var humanize: Float     // 0 machine-exact velocity … 1 loose/expressive

    public init(liveliness: Float = 0.5, darkness: Float = 0.5, tension: Float = 0.0,
                romance: Float = 0.3, weird: Float = 0.0,
                virtuosity: Float = 0.3, syncopation: Float = 0.15, humanize: Float = 0.25) {
        self.liveliness = liveliness
        self.darkness = darkness
        self.tension = tension
        self.romance = romance
        self.weird = weird
        self.virtuosity = virtuosity
        self.syncopation = syncopation
        self.humanize = humanize
    }
}

public struct BioComposition: Equatable, Sendable {
    public var notes: [Note]
    /// 8 tracks × 16 steps drum grid, shaped to the genre. All-false in the
    /// ambient self-observation style (melody only).
    public var drumSteps: [[Bool]]
    public var drumAccents: [[Bool]]
    public var suggestedTempo: Double

    public init(notes: [Note], drumSteps: [[Bool]], drumAccents: [[Bool]], suggestedTempo: Double) {
        self.notes = notes
        self.drumSteps = drumSteps
        self.drumAccents = drumAccents
        self.suggestedTempo = suggestedTempo
    }

    /// Whether the take carries any drum hits.
    public var hasDrums: Bool { drumSteps.contains { $0.contains(true) } }
}

public enum BioComposer {

    public static let stepCount = 16   // one bar loop, matches PatternEngine/PianoRoll
    public static let trackCount = 8

    /// Drum-grid track indices — must match `BeatPlayer.trackNames`.
    private enum Track {
        static let kick = 0, snare = 1, closedHat = 2, openHat = 3
        static let clap = 4, perc = 5, bass = 6, leadFX = 7
    }

    public struct Input: Sendable {
        public var heartRateBPM: Float
        public var hrvNormalized: Float     // 0…1
        public var coherence: Float         // 0…1
        public var breathPhase: Float       // 0…1 (0 = inhale start)
        public var breathDepth: Float       // 0…1
        public var key: MusicalKey
        public var style: MusicStyle
        public var mode: ComposerMode
        public var lockedTempo: Double      // used when mode == .studioLocked
        public var mood: MoodProfile
        public var seed: UInt64
        /// Optional SKELETON seed for cohesion. The structural skeleton — chord
        /// progression, register, note density, and WHERE ornaments / octave-lifts /
        /// syncopation land — is drawn from this stream; the melodic DETAIL (which
        /// pitches, fine velocity) is drawn from `seed`. Pass a body-stable value here
        /// and an evolving value in `seed` so consecutive takes feel like the SAME
        /// piece evolving (homogeneous), not a new random piece each time. `nil`
        /// (default) makes the skeleton share `seed` — original behaviour.
        public var structureSeed: UInt64?
        /// Position in the genre's chord progression this take starts on — the "where
        /// are we in the journey" cursor (founder 2026-07-11: "es soll ja weitergehen
        /// und sich mit dem Herzschlag weiterentwickeln"). A SUSTAINED Fläche holds ONE
        /// chord per bar (stillness preserved), but WHICH chord = `progression[phase]`,
        /// so advancing the phase per bar (multi-bar loop) and per evolve (over time,
        /// bio-cadenced) makes the pad TRAVEL through its progression instead of
        /// freezing on one chord. Melodic genres rotate their progression start by it
        /// too. 0 (default) = the progression's first chord — original behaviour.
        public var progressionPhase: Int
        /// H1 voice-leading switch (PLAN_HARMONY_CORE.md): `true` routes the pad's
        /// chord-to-chord movement through `VoiceLeader.resolve` (real inversions,
        /// common tones held) instead of the whole-chord octave shift. Deliberately
        /// a BOOL, not a spec struct, for Slice 1: strictness/spread are derived
        /// from the BIO fields already on this Input (see `compose` — coherence →
        /// strictness, breath depth → spread), so the caller flips one switch and
        /// the body does the rest. `false` (default) keeps today's path
        /// byte-identical (Golden law — pinned in BioComposerVoiceLeadingTests).
        public var voiceLeading: Bool
        /// H3 HRV-humanize switch (PLAN_HARMONY_CORE.md): `true` adds a FINAL
        /// velocity micro-variability stage drawn from the player's REAL heart
        /// rate variability — jitter amplitude = hrvNormalized · ±12% (see
        /// `hrvHumanize`), so a variable heart loosens the take and a rigid one
        /// leaves it machine-tight ("the body humanizes its own pattern"). KEIN
        /// Zufalls-Humanize: deterministic per seed + note index, hrv 0 ⇒ exactly
        /// zero jitter. Distinct from `mood.humanize` (the stylistic feel dial,
        /// untouched) — this stage is ADDITIVE and opt-in. `false` (default)
        /// keeps today's path byte-identical (pinned in BioComposerHumanizeTests).
        public var humanize: Bool
        /// H2 chord-journey switch (PLAN_HARMONY_CORE.md): `true` replaces the
        /// legacy progression logic (profile rotation / weird splice /
        /// turnaround) with a `ChordSuggest` journey — harmonic-function
        /// ranking (T→S→D circulation, cadence resolution) smoothed by the
        /// VoiceLeader distance, with the body's COHERENCE selecting how deep
        /// into the ranking each step reaches (settled → the expected
        /// consonant continuation, unsettled → borrowings/tension). Like H1 a
        /// plain BOOL: coherence + the skeleton seed are read from the fields
        /// already on this Input (see `chordSuggestControl`). `false` (default)
        /// keeps today's path byte-identical (pinned in ChordSuggestTests).
        public var suggestJourney: Bool
        /// #253 A3 — WHICH RHYTHM THE BASS WALKS IN (founder 2026-07-30: *"Alle Soundrubriken von
        /// Pads, Bass bis arp etc. brauchen noch verschiedene Rhythmus Regler … interessante,
        /// treibende, hypnotische, dynamische etc."*).
        ///
        /// **`nil` (default) = the genre's own bass rhythm, byte-identical** — the same Golden law
        /// `voiceLeading` / `humanize` / `suggestJourney` above are held to, and here it is not
        /// hygiene but the whole design. The founder CURATED these genres twice (#81, #125:
        /// "erst eine individuelle Variation und dann klingt plötzlich alles gleich"), so a rhythm
        /// character that applied itself by default would flatten Disco, Doom and Dub Techno onto
        /// one bassline — the exact failure those two tasks fixed. This is an OVERRIDE a player
        /// reaches for, never a new baseline.
        ///
        /// A `Character` and NOT a full `RoleRhythm.Params`, deliberately: the bass already gets its
        /// rate, its level and its length from the BODY (`busy`/`calm` → the walking gap, the
        /// section velocity). Four more dials would be four more ways to contradict the
        /// biofeedback. The character chooses the SHAPE; the body keeps the scale.
        ///
        /// ⚠️ It only reaches the WALKING bass. A sustained profile's held root and trap's
        /// quarter-note 808 pedal are the genre's foundation, not a groove — see `appendBass`.
        /// ⭐ #983: on a genre with a `BassGrammar` (`MusicStyle.bassGrammar`) a set character
        /// REPLACES the genre's figure with the walking path, so the Picker keeps meaning "shape
        /// the bass my way" there too; `nil` plays the genre's own figure.
        public var bassRhythm: RoleRhythm.Character?

        /// #253 A4 — the PAD's rhythm character, or `nil` for the genre's own articulation.
        ///
        /// Same Golden law as `bassRhythm` and for the same curated-genre reason: `nil` produces a
        /// byte-identical take. Where the bass override reaches only the walking line, this one
        /// reaches EVERY non-arpeggiated pad path — the `.sustained` heartbeat Fläche, the
        /// skank/stab/comp chop grids and the single held chord — because all three are the same
        /// thing to a listener: when the chord re-articulates.
        ///
        /// ⚠️ THE RATE STAYS THE GENRE'S. The density handed to `RoleRhythm` is COUNTED from the path
        /// this override is about to replace — `chordOnsets` on the three chord paths, and the arp's
        /// own `arpStep` grid on an arpeggiated profile. Two sources, not one: an arp genre's
        /// articulation value describes a chord grid it never plays, so counting `chordOnsets` there
        /// would hand over a rate the ear never heard. (The first version of this doc said "counted
        /// from what `chordOnsets` would have played" full stop — i.e. it documented the bug the same
        /// commit fixed, in the one place a CALLER reads.) Either way an even-spread character sounds
        /// roughly the same number of chords and only their placement, length and level change.
        ///
        /// ⚠️ IT DOES NOT TOUCH AN ARPEGGIATED PROFILE'S PITCH ORDER, only when its notes land: an
        /// arpeggio is a pitch figure and re-voicing it is `ArpFigure`'s business, not a rhythm's.
        ///
        /// ⚠️ AND IT DOES NOT REACH THE INNER PULSE. That layer is `.harmony` too by this repo's own
        /// definition, and it keeps re-articulating chord tones an octave up on its fixed 8th/quarter
        /// grid. So on a busy non-sustained genre, choosing `sparse` thins the PAD to one chord per
        /// section while the pulse keeps its own rate — the row governs when the CHORD speaks, not
        /// every harmonic event in the take. Bringing the pulse under the same character is a
        /// separate decision (it is the layer that keeps a take moving) and deliberately not made here.
        public var padRhythm: RoleRhythm.Character?

        /// The PERSON's habitual dynamic position, −1 … +1 (#403 Slice 3b). `0` = no
        /// fingerprint learned yet, and `bassLift(for: 0)` is the pre-#403 constant `0.14` —
        /// so a never-measured performer renders bit-identically to before this field existed.
        ///
        /// Supplied by `PerformerSignature.dynamicTilt`. It sets the take's LOW-END WEIGHT
        /// (how far the bass is lifted over the pad), not its level — see `composeHarmonic`'s
        /// velocity site for why the level version was erased by the loudness servo.
        ///
        /// ⛔ For one commit this doc said "`StudioCalculator.tilted` returns its input
        /// unchanged for a zero tilt", which was true of the Slice 3 implementation and stopped
        /// being true when 3b dropped that call. Naming the mechanism rather than the guarantee
        /// is what made it rot; the guarantee is stated above and the mechanism is one hop away.
        public var signatureDynamicTilt: Double = 0

        /// The pad's chord SHAPE (#581), the three dials `roleRhythmOnsets` used to hard-code.
        /// See `RoleRhythm.Params` for the measured semantics of each, and
        /// `StudioDefaultKeys.padGate/padAccent/padEvolve` for the persisted rows above them.
        ///
        /// ⚠️ THE DEFAULTS HERE ARE THE OLD LITERALS (0.8 / 0.4 / 0.2) AND THAT IS LOAD-BEARING
        /// IN A WAY THE CALL SITE'S IS NOT. `roleRhythmOnsets` takes these as REQUIRED arguments
        /// on purpose (#431) — but `Input` is constructed in dozens of tests, and defaulting
        /// there is what keeps every one of those takes byte-identical to before this field
        /// existed. The difference is deliberate: the engine boundary should force the caller to
        /// choose, the value object should not force a hundred test fixtures to.
        ///
        /// ⚠️ THEY REACH NOTHING WHILE `padRhythm == nil`. `composeHarmonic` only calls
        /// `roleRhythmOnsets` inside `if let character = padRhythm`, so with the Picker on
        /// "Genre" these three are carried and never read — which is why the rows that write
        /// them are DISABLED in that state rather than merely ineffective.
        public var padGate: Float = 0.8
        public var padAccent: Float = 0.4
        public var padEvolve: Float = 0.2

        public init(
            heartRateBPM: Float = 70,
            hrvNormalized: Float = 0.5,
            coherence: Float = 0.5,
            breathPhase: Float = 0,
            breathDepth: Float = 0.5,
            key: MusicalKey = MusicalKey(root: 0, scale: .dorian),
            style: MusicStyle = .dubTechno,
            mode: ComposerMode = .studioLocked,
            lockedTempo: Double = 124,
            mood: MoodProfile = MoodProfile(),
            seed: UInt64 = 0x5EED,
            structureSeed: UInt64? = nil,
            progressionPhase: Int = 0,
            voiceLeading: Bool = false,
            humanize: Bool = false,
            suggestJourney: Bool = false,
            bassRhythm: RoleRhythm.Character? = nil,
            padRhythm: RoleRhythm.Character? = nil,
            signatureDynamicTilt: Double = 0,
            padGate: Float = 0.8,
            padAccent: Float = 0.4,
            padEvolve: Float = 0.2
        ) {
            self.heartRateBPM = heartRateBPM
            self.hrvNormalized = hrvNormalized
            self.coherence = coherence
            self.breathPhase = breathPhase
            self.breathDepth = breathDepth
            self.key = key
            self.style = style
            self.mode = mode
            self.lockedTempo = lockedTempo
            self.mood = mood
            self.seed = seed
            self.structureSeed = structureSeed
            self.progressionPhase = progressionPhase
            self.voiceLeading = voiceLeading
            self.humanize = humanize
            self.suggestJourney = suggestJourney
            self.bassRhythm = bassRhythm
            self.padRhythm = padRhythm
            self.signatureDynamicTilt = signatureDynamicTilt
            self.padGate = padGate
            self.padAccent = padAccent
            self.padEvolve = padEvolve
        }
    }

    /// Resolved per-take voice-leading controls (H1). Built in `compose` from the
    /// Input's bio fields when `input.voiceLeading` is on; `nil` = legacy octave
    /// shift. Internal so the mapping law is unit-testable.
    struct VoiceLeadControl: Sendable {
        var strictness: Float
        var spread: Float
        var seed: UInt64
    }

    /// H1 bio → voice-leading mapping (tested law, BioComposerVoiceLeadingTests):
    ///   strictness = 0.6 + 0.4·clamp01(coherence) — a settled body voice-leads at
    ///     the strict cost optimum; low coherence relaxes toward the seeded freer
    ///     pick, never below 0.6 (the leading always stays recognizably smooth).
    ///   spread = clamp01(breathDepth) — deep breathing opens the voicing
    ///     (close ↔ open ambitus), shallow breathing keeps it close.
    ///   seed = structureSeed ?? seed — the SKELETON stream, so the chosen
    ///     inversions are part of the stable structure across evolving takes.
    /// Only fields Input really carries are used (coherence, breathDepth).
    static func voiceLeadControl(for input: Input) -> VoiceLeadControl? {
        guard input.voiceLeading else { return nil }
        return VoiceLeadControl(strictness: 0.6 + 0.4 * clamp01(input.coherence),
                                spread: clamp01(input.breathDepth),
                                seed: input.structureSeed ?? input.seed)
    }

    /// Resolved per-take chord-journey controls (H2). Built in `compose` from
    /// the Input when `input.suggestJourney` is on; `nil` = the legacy
    /// progression logic (rotation / weird splice / turnaround), byte-identical.
    struct ChordSuggestControl: Sendable {
        var coherence: Float
        var seed: UInt64
    }

    /// H2 bio → journey mapping (tested law, ChordSuggestTests):
    ///   coherence = clamp01(input.coherence) — drives the selection depth
    ///     (high → the expected consonant top pick, low → deeper/tenser
    ///     candidates incl. the curated borrowings; the window law itself lives
    ///     in `ChordSuggest.selectionWindow`).
    ///   seed = structureSeed ?? seed — the SKELETON stream (the chord journey
    ///     IS structure, stable across evolving takes). ChordSuggest salts it
    ///     internally; no draws are consumed from either compose RNG stream.
    static func chordSuggestControl(for input: Input) -> ChordSuggestControl? {
        guard input.suggestJourney else { return nil }
        return ChordSuggestControl(coherence: clamp01(input.coherence),
                                   seed: input.structureSeed ?? input.seed)
    }

    /// H2: the journey repeats after this many chords — `progressionPhase` is
    /// wrapped into it, so per-bar/per-evolve advances travel an 8-chord arc
    /// before looping (the legacy path loops after `progression.count`).
    static let chordJourneyLoopLength = 8

    /// Even a fully aroused body keeps this share of the genre's own progression.
    static let genreAnchorFloor: Float = 0.34
    /// Coherence at which the genre's progression is anchored in FULL — the same
    /// threshold at which the beat turns "spacious".
    static let genreAnchorFullBy: Float = 0.7

    /// How many of a take's `n` section roots are locked to the genre's OWN authored
    /// progression instead of the shared, coherence-selected chord journey.
    ///
    /// The crossfade (founder 2026-07-22: *"bei den Genres kommt erst eine individuelle
    /// Variation und dann klingt plötzlich alles gleich"*): calm ⇒ k→n ⇒ the root motion
    /// IS the genre signature; aroused ⇒ k→the floor ⇒ the genre's first roots stay
    /// anchored while the rest of the journey explores. Pure function of coherence — no
    /// RNG draw, so every downstream draw keeps its order (determinism law).
    ///
    /// ⛔ THE `max(1, …)` IS THE WHOLE POINT, and it was missing until 2026-07-29.
    /// The expression used to be `min(n, Int((Float(n) * anchor).rounded()))`. For
    /// **n == 1** that rounds `1 × 0.34` to **0** — nothing anchored, the single root
    /// taken wholesale from the shared journey — for every body below coherence 0.35.
    /// FOUR profiles have n == 1: `.selfObservation` (the SHIPPED DEFAULT) and
    /// `.stillMeditation` (both sustained with a >2-chord progression → one section
    /// per take), plus `.psytrance` and `.doom` (one-chord progressions). Camera rPPG reports
    /// coherence 0 until beats accrue and HealthKit never measures it at all, so this is
    /// not an edge case — it is the FIRST MINUTES OF EVERY SESSION on the default genre,
    /// which is exactly where a listener forms their judgement, and exactly the founder's
    /// complaint. The old comment block admitted the gap in a parenthetical ("k≥1 for
    /// n≥2") rather than closing it; documenting a hole is not choosing it.
    ///
    /// The clamp is a no-op for n ≥ 2 (`2 × 0.34 = 0.68` already rounds to 1), so this
    /// changes the sound of those four profiles only — and only below coherence 0.35.
    ///
    /// `sections` is a progression length (≤ 4 across the whole roster), so the `Int(_:)`
    /// below cannot overflow; the guard covers the one degenerate value that IS worth a
    /// contract (`0` ⇒ nothing to anchor, which the caller's `if k > 0` relies on).
    static func genreAnchorCount(sections n: Int, coherence: Float) -> Int {
        guard n > 0 else { return 0 }
        // `clamp01` would pass NaN straight through (`max(NaN, 0)` returns NaN — see the
        // argument-order law in CLAUDE.md), and a NaN anchor makes `Int(_:)` trap.
        let coh = coherence.isFinite ? Swift.min(Swift.max(coherence, 0), 1) : 0
        let anchor = Swift.max(genreAnchorFloor, Swift.min(1, coh / genreAnchorFullBy))
        return Swift.min(n, Swift.max(1, Int((Float(n) * anchor).rounded())))
    }

    private static func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }

    /// A deterministic UUID drawn from the RNG, so a whole composition — note
    /// identities included — is reproducible from its seed.
    private static func nextUUID(_ rng: inout SeededRNG) -> UUID {
        let hi = rng.next()
        let lo = rng.next()
        func byte(_ v: UInt64, _ i: Int) -> UInt8 { UInt8((v >> (UInt64(i) * 8)) & 0xFF) }
        return UUID(uuid: (
            byte(hi, 7), byte(hi, 6), byte(hi, 5), byte(hi, 4),
            byte(hi, 3), byte(hi, 2), byte(hi, 1), byte(hi, 0),
            byte(lo, 7), byte(lo, 6), byte(lo, 5), byte(lo, 4),
            byte(lo, 3), byte(lo, 2), byte(lo, 1), byte(lo, 0)
        ))
    }

    /// Resonance pulse band: 72 BPM = 6 breaths/min × 12, i.e. an integer pulse over
    /// the 0.1 Hz resonance breath clock (the parasympathetic entrainment target).
    static let resonancePulseBPM = 72.0

    /// Tempo a take should run at: clamped into the style's window in Studio mode;
    /// in Flow it follows the heart but is pulled toward the resonance band as
    /// coherence rises (two-clock entrainment — the groove settles WITH the body
    /// instead of merely mirroring it). At zero coherence Flow follows the heart
    /// exactly; at full coherence it converges to ~72 BPM. Pure + testable.
    public static func tempo(for input: Input) -> Double {
        switch input.mode {
        case .studioLocked:
            let r = input.style.tempoRange
            return min(max(input.lockedTempo, r.lowerBound), r.upperBound)
        case .flowFree:
            let hr = Double(input.heartRateBPM)
            let calm = Double(clamp01(input.coherence))
            let pulled = hr * (1 - calm) + Self.resonancePulseBPM * calm
            return min(max(pulled, 40), 160)
        }
    }

    /// The body read as an autonomic state (not four loose dials), the validated
    /// bio→music spine. Pure + deterministic so it can be unit-tested directly.
    ///   • coherence (`calm`) = HRV resonance near 0.1 Hz → ordered, parasympathetic.
    ///     High ⇒ space, repetition, consonance.
    ///   • hrvNormalized (`vagal`) = vagal tone (RMSSD). High ⇒ relaxed; LOW ⇒
    ///     sympathetic ("fight/flight") load, which lifts musical energy.
    ///   • heart rate (`energy`) = cardiac drive → rhythmic energy + tempo.
    /// `arousal` (sympathetic activation) rises with a fast heart AND low HRV — the
    /// textbook stress signature (↑HR, ↓HRV). `busy` (density) then rises with arousal
    /// and falls with coherence.
    ///
    /// COHERENCE-CONVERGENCE SERVO (science brief, Phase 1): as coherence rises the
    /// music should not just be a touch sparser — it should CONVERGE toward calm
    /// (sparser, settled) as the body's reward for self-regulation. So coherence
    /// enters `busy` both additively (1−calm) AND as a multiplicative settle
    /// (1 − 0.35·calm): at low coherence the factor is ~1 (unchanged); at high
    /// coherence the take is decisively sparser. Monotonic in every input, clamped.
    static func musicalState(coherence: Float, hrvNormalized: Float, heartRateBPM: Double)
        -> (calm: Float, vagal: Float, energy: Float, arousal: Float, busy: Float) {
        let calm    = clamp01(coherence)
        let vagal   = clamp01(hrvNormalized)
        let energy  = clamp01(Float((heartRateBPM - 50) / 70))   // 50…120 bpm → 0…1
        let arousal = clamp01(0.55 * energy + 0.45 * (1 - vagal))
        let settle  = 1 - 0.35 * calm                            // coherence converges
        let busy    = clamp01((0.6 * arousal + 0.4 * (1 - calm)) * settle)
        return (calm, vagal, energy, arousal, busy)
    }

    /// Consonance convergence: scale a mood's tension down as coherence rises so a
    /// settled body yields a more consonant melody (fewer out-of-chord bends). At
    /// zero coherence tension is unchanged; at full coherence it drops to 40%.
    static func effectiveTension(_ moodTension: Float, coherence: Float) -> Float {
        clamp01(moodTension) * (1 - 0.6 * clamp01(coherence))
    }

    /// Depth of the bar-internal dynamic SHAPE (metric accent + swell) applied to every
    /// take. The device clip measured LRA 1.7 LU (dynamically dead — a flat 1-bar loop);
    /// this gives the loop real phrasing so it breathes. Kept musical (peak-to-peak ~±30%),
    /// not a pump. Tunable; 0 restores the old flat behaviour.
    static let dynamicDepth: Float = 0.6

    /// How far the performer fingerprint may move the bass's lift over the pad, either way
    /// (#403 Slice 3b). The un-tilted lift is `0.14`, so the reachable band is 0.07…0.21.
    ///
    /// ⚠️ WHY THIS SIZE, stated as a number so it can be argued with rather than found inline.
    /// At a typical pad velocity of ~0.46 the two extremes put the bass at 0.53 and 0.67. Under
    /// the `v^0.5` law that is `20·log₁₀(√(0.67/0.53))` ≈ **1.0 dB of bass weight relative to
    /// the pad** — audible as a different mix, nowhere near enough to unbalance one.
    ///
    /// ⛔ AND `v^0.5` IS NOT A PROPERTY OF `EchoelDDSP`, WHICH IS WHAT THE FIRST VERSION OF
    /// THIS LINE SAID. `spawnVoice` scales `amplitude` by `pow(v, expo)` with `expo = 1 …
    /// 1.5`; the 0.5 comes from `velocityGain`'s `expo * velocityCurve` (`velocityCurve` =
    /// 0.5), and that only governs the level when bio modulation is armed — which the app does
    /// at play, on an ambient patch whose `expo` is exactly 1. So ≈1.0 dB is right for the
    /// SHIPPED path and is the CONSERVATIVE end: with bio off the law is `v^1` (≈2.0 dB), and
    /// on the percussive genre patches it is 1.2…1.5 dB. Naming the condition matters because
    /// the number is the whole argument for the size.
    ///
    /// ⚠️ AND IT IS THE BASS LINE, NOT "THE LOW END". The felt sub an octave below
    /// (`SubBassVoice`) takes `noteOn(pitch:velocity:)` and DISCARDS the velocity by design —
    /// its level is `subGain × mixLevel`, performer-independent. So the sub band does not move
    /// at all; what moves is the composed bass line at `padOctave − 1`, against a fixed-level
    /// sub. Calling this "low-end weight" overstates which band actually shifts.
    ///
    /// ⚠️ THE HONEST LIMIT, AND IT IS THE ONE THAT DECIDES THE DEVICE LISTEN: on the shipped
    /// default genre a take is ONE sustained section, so `appendBass` writes exactly ONE bass
    /// note. The per-note humanisation on it is `hVel` ±0.05 plus `hrvHumanize` (default-on in
    /// the app, depth 0.12) up to ±0.036 — combined ±0.086 against a systematic ±0.07. With no
    /// second note there is no within-take averaging, so a SINGLE take is noise-dominated for
    /// all but near-opposite fingerprints; the fingerprint is a BIAS across takes, not a
    /// per-take guarantee. (Two takes from the same seed differ by exactly 0.14 because the
    /// tilt consumes no RNG — but #403 Slice 1 salts the seed per performer, so in the
    /// founder's actual scenario the jitter differs too.) A dimension that moves EVERY note
    /// — register, Slice 4 — carries a fingerprint better than one that moves one note.
    ///
    /// ⚠️ AND IT IS SYMMETRIC BY CONSTRUCTION, which the tilted-velocity form was not.
    /// `StudioCalculator.tilted` moves a fraction of the headroom to the NEAR bound, so when
    /// the anchor itself moves with the body the two directions get different authority — at
    /// high coherence the old pad-velocity form was 4:1 lopsided, i.e. the better a performer
    /// did at the one thing this instrument asks of them, the more one half of their
    /// fingerprint disappeared. The anchor here is a constant, so plain ± arithmetic is both
    /// simpler and fairer, and `tilted` would be ceremony.
    static let bassLiftRange: Double = 0.07

    /// The bass's lift over the pad for this performer. `0.14` when nothing was ever measured,
    /// which is the value this line carried before #403 — so an unlearned performer renders
    /// bit-identically.
    ///
    /// Higher habitual HRV lifts the bass LESS (see the convention note at the call site), so
    /// the tilt is subtracted. Clamped at both ends: `dynamicTilt` is already −1…1 by
    /// construction, and a non-finite tilt must not become a non-finite velocity.
    ///
    /// ⛔ It does NOT make the velocity site NaN-proof, which the first version implied by
    /// calling it "the line that would put a bad value into the audio". `clamp01` is
    /// `min(max(x, 0), 1)`, and by the argument-order law in CLAUDE.md that passes NaN
    /// straight through — so a non-finite `breathDepth` still yields a NaN `bassVelocity`,
    /// exactly as it did before #403. Not reachable via `makeComposerInput` (it sanitises
    /// first) and pre-existing, but the sentence claimed a completeness this line does not
    /// have, on a file whose whole subject is claims that outrun their code.
    static func bassLift(for tilt: Double) -> Float {
        let t = tilt.isFinite ? tilt.clamped(to: -1...1) : 0
        return Float(0.14 - t * Self.bassLiftRange)
    }

    /// Trap's low end, when the body is aroused, drives a quarter-note root PEDAL (a
    /// moving 808 — the genre's signature) instead of the single held root, so beats 2 & 4
    /// stop dropping out (founder-diagnosed "die Viertel fehlen" on the Trap 132 lock). A
    /// CALM body keeps the held root, and it is SCOPED TO TRAP ONLY — dub and the
    /// meditative Flächen stay held whatever the body does. Tunable; `false` restores the
    /// pre-B8 single held root everywhere.
    static let quarterAnchorBass = true

    /// Velocity multiplier (~[1−depth/2, 1+depth/2]) for a note starting at `step`: a metric
    /// accent (downbeat > 8th > 16th, the natural musical hierarchy) blended with a gentle
    /// raised-cosine swell across the bar (0→1→0). Pure + deterministic → unit-tested.
    static func barDynamic(step: Int, stepCount: Int, depth: Float) -> Float {
        guard stepCount > 1 else { return 1 }
        let s = ((step % stepCount) + stepCount) % stepCount
        let pos = Float(s) / Float(stepCount)                     // 0..<1 across the bar
        // THE ONE (bar downbeat, s==0) is the strongest metric event; the other beats
        // follow, then 8ths, then 16ths. Founder ("die Eins zu erkennen"): the old curve
        // gave every quarter metric=1 AND the raised-cosine swell TROUGHED at s=0, so the
        // bar's energy peaked mid-bar and the "one" was the weakest downbeat — the exact
        // reason the one was hard to hear. Now a downbeat term lifts s==0 above the swell.
        let metric: Float
        if s == 0            { metric = 1.0 }                     // THE ONE
        else if s % 4 == 0   { metric = 0.72 }                    // other beats (2·3·4)
        else if s % 2 == 0   { metric = 0.5 }                     // 8ths
        else                 { metric = 0.32 }                    // 16ths
        let swell = 0.5 - 0.5 * cos(2 * Float.pi * pos)           // 0 → 1 → 0 bar breath
        // Founder 2026-07-13 ("man findet die Eins nicht"): push the downbeat anchor to
        // its safe ceiling so beat 1 sits at (near) full velocity while mid-bar notes fall
        // back — the strongest metric cue a beat-free Fläche can carry (a soft pad has no
        // transient, so velocity is the only lever here; kept ≤1 so the ±depth/2 bound holds).
        let downbeat: Float = (s == 0) ? 0.44 : 0                 // anchor the one over the swell trough
        let shape = 0.55 * metric + 0.25 * swell + downbeat       // 0…1, the one wins
        return 1 + clamp01(depth) * (shape - 0.5)                 // centred ~1, span ≤ ±depth/2
    }

    /// Shape a take's dynamics over the bar so the WHOLE texture (pads, bass, lead) rises
    /// and relaxes together instead of sitting at a flat velocity — the phrasing a looping
    /// bar otherwise lacks (LRA 1.7 → lifeless). Applied to all genres uniformly. Pure,
    /// deterministic; velocity clamped to a musical [0.05, 1]. depth 0 → unchanged.
    static func shapeBarDynamics(_ notes: [Note], depth: Float, stepCount: Int) -> [Note] {
        guard clamp01(depth) > 0, stepCount > 1 else { return notes }
        return notes.map { note in
            var n = note
            // NaN-safe `clamped(to:)`: this multiplies by a bio-derived factor, so ONE
            // non-finite bio value used to write a NaN velocity straight into the take
            // (`min(max(x, 0.05), 1)` passes NaN through — CLAUDE.md's argument-order
            // law). NaN now lands on this window's floor: the quietest audible note.
            n.velocity = (note.velocity * barDynamic(step: note.startStep,
                                                     stepCount: stepCount, depth: depth))
                .clamped(to: 0.05...1)
            return n
        }
    }

    /// Subtle, SEEDED per-note velocity variation so repeated notes don't read
    /// machine-gun identical — the `humanize` mood, now applied to the LIVE take and
    /// not only at MIDI export (audit: live notes were perfectly uniform → lifeless).
    /// Timing is left to the sequencer/grid; only velocity breathes. Deterministic
    /// (same seed → same feel), velocity kept in a musical [0.05, 1] window.
    static func humanizeVelocity(_ notes: [Note], amount: Float, seed: UInt64) -> [Note] {
        let amt = clamp01(amount)
        guard amt > 0 else { return notes }
        let span = amt * 0.18                        // up to ±18% at full humanize
        return notes.enumerated().map { idx, note in
            var rng = SeededRNG(seed: seed &+ (UInt64(bitPattern: Int64(idx + 1)) &* 0x9E3779B97F4A7C15))
            let v = rng.unit() * 2 - 1               // -1…1
            var n = note
            n.velocity = (note.velocity * (1 + v * span)).clamped(to: 0.05...1)  // NaN-safe
            return n
        }
    }

    /// H3 (PLAN_HARMONY_CORE.md): maximum HRV-humanize velocity depth — at full
    /// vagal tone (hrvNormalized 1) a note's velocity may swing up to ±12%.
    /// Tested law (BioComposerHumanizeTests): jitter amplitude = hrv · this depth,
    /// so hrv 0 ⇒ EXACTLY zero jitter. Kept small — micro-variability, not swing.
    static let hrvHumanizeDepth: Float = 0.12

    /// Seed salt for the H3 stream ("HRVHUMNZ" in ASCII): XOR-derived from the
    /// take seed WITHOUT consuming either RNG stream (H1 wiring discipline), and
    /// decorrelated from `humanizeVelocity`'s per-note streams (which mix the
    /// raw seed) so the two stages never share a jitter sequence.
    static let hrvHumanizeSeedSalt: UInt64 = 0x4852_5648_554D_4E5A

    /// H3 HRV-HUMANIZE — the body humanizes its own pattern. A FINAL, opt-in
    /// per-note velocity micro-variability stage whose AMPLITUDE is the player's
    /// real heart rate variability: span = hrvNormalized · `hrvHumanizeDepth`.
    /// A variable heart (high RMSSD → high hrvNormalized) loosens the take like a
    /// relaxed player; a rigid heart leaves it machine-tight. NOT random-humanize:
    /// deterministic per (seed, note index) via the same golden-ratio per-note
    /// SeededRNG derivation as `humanizeVelocity` (own salted stream, no draws
    /// consumed from the compose streams), and hrv 0 returns the notes UNTOUCHED.
    /// Velocity clamped to the musical [0.05, 1] window; pitch/timing/role are
    /// never touched (Slice 1 is velocity-only — the live trigger clock is
    /// step-quantized, see `PianoRollModel.trigger`, so tick offsets would be
    /// inaudible in-app; a timing slice waits for the sub-step clock). Pure.
    static func hrvHumanize(_ notes: [Note], hrvNormalized: Float, seed: UInt64) -> [Note] {
        let span = clamp01(hrvNormalized) * hrvHumanizeDepth
        guard span > 0 else { return notes }         // hrv 0 ⇒ exactly zero jitter
        let salted = seed ^ hrvHumanizeSeedSalt
        return notes.enumerated().map { idx, note in
            var rng = SeededRNG(seed: salted &+ (UInt64(bitPattern: Int64(idx + 1)) &* 0x9E3779B97F4A7C15))
            let v = rng.unit() * 2 - 1               // -1…1
            var n = note
            n.velocity = (note.velocity * (1 + v * span)).clamped(to: 0.05...1)  // NaN-safe
            return n
        }
    }

    /// MOTIF CONTOUR (Cycle 3, "singt statt noodelt"). Per-note scale-step deltas
    /// for a melodic line that STATES a short seeded cell, then RESTATES it as a
    /// varied answer (statement→answer / call-and-response), and RESOLVES back toward
    /// its centre so the phrase settles instead of drifting — the structure that
    /// makes a line sing instead of wander. The caller still maps the running index
    /// onto chord tones, so output stays perfectly in key. Pure + deterministic.
    ///   • `directionBias` (0…1, from breath): >0.5 leans the cell upward (inhale).
    ///   • `weird` (0…1, mood): widens intervals (1 → 2–3 steps) and loosens the
    ///     restatement (more likely to invert the contour for the answer).
    static func motifDeltas(count: Int, directionBias: Float, weird: Float,
                            rng: inout SeededRNG) -> [Int] {
        guard count > 0 else { return [] }
        let w = clamp01(weird)
        let bias = clamp01(directionBias)
        // 1) A short motivic cell (2–4 steps). Stepwise by default; weird widens.
        let cellLen = 2 + Int(rng.unit() * 2.999)              // 2…4
        var cell: [Int] = []
        for _ in 0..<cellLen {
            let up = rng.unit() < (0.30 + 0.45 * bias)         // breath leans direction
            let wide = rng.unit() < w
            let mag = wide ? 2 + Int(rng.unit() * 1.999) : 1   // 2–3 only when weird
            cell.append((up ? 1 : -1) * mag)
        }
        // 2) State the cell (first half), then restate it (second half) — inverted
        //    some of the time so the answer echoes the question in a recognizable
        //    shape. The cell index RESTARTS at the answer so it's a clean restatement.
        let invertAnswer = rng.unit() < (0.5 + 0.3 * w)
        let half = Swift.max(1, count / 2)
        var deltas: [Int] = []
        while deltas.count < count {
            let inAnswer = deltas.count >= half
            let idx = inAnswer ? (deltas.count - half) : deltas.count
            let base = cell[idx % cell.count]
            deltas.append(inAnswer && invertAnswer ? -base : base)
        }
        // 3) Resolve: the final step opposes the accumulated direction so the phrase
        //    settles toward its centre rather than climbing/falling off the end.
        if count >= 2 {
            let net = deltas[0..<(count - 1)].reduce(0, +)
            if net > 0 { deltas[count - 1] = -1 } else if net < 0 { deltas[count - 1] = 1 }
        }
        return deltas
    }

    /// Snap a scale-degree offset onto the nearest chord tone of the sounding
    /// chord, in scale-degree space and across octaves. `tones` are chord-tone
    /// offsets (e.g. `[0, 2, 4]` triad, `[0, 4, 7]` power chord) that may span
    /// more than one octave; each is imaged to the octave nearest `deg` and the
    /// closest wins. This is what lets a stepwise (singing) lead re-anchor to the
    /// harmony on strong beats — chord tones on the beat, passing tones between —
    /// so the line outlines the chord instead of drifting out of it. Pure.
    static func nearestChordDegree(_ deg: Int, tones: [Int], degreesPerOctave n: Int) -> Int {
        guard !tones.isEmpty, n > 0 else { return deg }
        var best = deg
        var bestDist = Int.max
        for t in tones {
            let k = Int((Double(deg - t) / Double(n)).rounded())   // octave image nearest deg
            let cand = t + k * n
            let dist = abs(cand - deg)
            if dist < bestDist { bestDist = dist; best = cand }
        }
        return best
    }

    /// Generate music from a bio snapshot, in the requested genre.
    /// How much to thin the FAST melodic layers (lead note count, arp/pulse subdivision)
    /// for a given PLAYBACK tempo, so a take keeps a good vibe instead of turning hectic as
    /// BPM rises (founder 2026-07-11: "auf 75 ok, auf 132 zu hektisch … je nach bpm adaptiv
    /// die Spielart anpassen um immer einen guten Vibe zu kreieren"). Perceived busyness ≈
    /// notes × tempo; to hold roughly-constant notes-per-SECOND above a comfortable baseline
    /// we thin density as tempo climbs. At/below the baseline the take is UNCHANGED (1.0) —
    /// a slow groove stays as full as it was (the founder's good-at-75 case). Softened power
    /// curve + a floor so it thins without gutting the line. Does NOT touch the pad's
    /// heartbeat re-articulation (that's the body's own movement, driven by arousal, not
    /// tempo). Pure → unit-testable.
    /// ⭐ #418 — WHERE THE LIVELINESS KNOB LANDS. `MoodProfile.liveliness` documents itself as
    /// "0 sparse/still … 1 busy/active (density)" and `MoodProfile`'s own doc points here, at
    /// `composeHarmonic`, for the mapping. That mapping did not exist on any shipped path: every
    /// read of the field sat in the callerless `ambientMelody` or inside `if profile.leadDensity
    /// > 0`, and all 33 offered genres set `leadDensity: 0.0` (pinned by `LeadRoleAbsenceTests`).
    /// Three writers — the Mood panel knob, the mood-pad drag, `WeatherMood.blend` — and no
    /// reachable reader. Fifteen shipped mood presets carry values spread from 0.05 to 0.92 and
    /// all fifteen behaved identically, which is the founder's "die Kompositionen klingen gleich"
    /// at its own source.
    ///
    /// It moves the THRESHOLD, not the steps. The two live density decisions (`arpStep`,
    /// `pulseGap`) each choose between two fixed values by comparing `busy` against a literal;
    /// this shifts that literal. The knob can therefore only pick the other of the two values the
    /// genre ALREADY ships — it can never invent a third.
    ///
    /// ⛔ "THE TWO" IS A #418 SENTENCE AND #419 MADE IT INCOMPLETE — kept as written because it is
    /// still exactly true of the MELODIC path this block describes, but a reader must not take it
    /// as the full inventory of what the knob reaches. Both of those decisions sit behind
    /// `!profile.sustained`, so eight of the sixteen offered genres — `.selfObservation`, the
    /// shipped default, among them — saw nothing. #419 added three more comparisons on the
    /// `.sustained` path (the `heartbeatActive` arousal gate and `heartbeatOnsets`' two stride
    /// steps) through this same function with a smaller `stillnessThresholdSpan`. Five
    /// comparisons, one shape, two spans. The count in this paragraph is the melodic half only.
    ///
    /// ⛔ THAT BOUND IS ABOUT THE GRID, NOT THE TAKE, and the first version of this comment said
    /// "no knob position can produce a texture the genre could not previously make" — too strong,
    /// caught in the #418 Nachlese. Doubling the arp onsets in section 0 shifts every later RNG
    /// draw (`nextUUID` twice per note, `hVel` once), and the beat is drawn AFTER the melody, so
    /// velocity detail and drum placement land somewhere this seed could not previously reach.
    /// The claim that survives: no knob position changes WHICH grid values a genre can use.
    ///
    /// ⚠️ 0.5 IS BIT-IDENTICAL, and that is load-bearing rather than tidy: it is `MoodProfile`'s
    /// init default, so anyone who never touches the knob gets exactly today's take. `centred` is
    /// zero there and `base - span * 0` is `base` exactly in Float — not "close enough".
    ///
    /// ⛔ AND THE NON-FINITE PATH WAS WRONG IN BOTH THE CODE AND THE COMMENT ABOVE IT. The first
    /// version called `clamp01` and claimed "`min(max(x, 0), 1)` with NaN first returns 0 (the
    /// argument-order rule CLAUDE.md records)". That is the rule INVERTED: `max(0, NaN)` returns
    /// 0, `max(NaN, 0)` returns NaN — and `clamp01` writes the value first, so a NaN went
    /// straight through into the threshold. The `genreAnchorCount` guard eighty lines above
    /// spells this out for the same helper; a brand-new comment cited the law backwards anyway.
    /// A non-finite value now reads as the NEUTRAL 0.5, not as 0: a bad weather sample must not
    /// silently sparsify a take, and 0.5 lands on exactly today's threshold.
    /// - Parameter span: how far full knob travel may move `base`. Defaults to the melodic
    ///   `livelinessThresholdSpan`; the `.sustained` stillness ladder passes the smaller
    ///   `stillnessThresholdSpan` for the reason written at that constant. One function, so
    ///   "lively lowers the bar, 0.5 is exactly today" means the same thing everywhere it is used.
    nonisolated static func densityThreshold(base: Float, liveliness: Float,
                                             span: Float = BioComposer.livelinessThresholdSpan)
        -> Float {
        let safe = liveliness.isFinite ? liveliness : 0.5     // NaN/±inf ⇒ today's threshold
        let centred = safe.clamped(to: 0...1) - 0.5           // −0.5 … +0.5
        return base - span * centred                          // lively ⇒ lower bar
    }

    /// Full knob travel = ±0.15 on the `busy` axis. Chosen so both thresholds (0.6 and 0.7) stay
    /// strictly inside 0…1 across the whole range — outside it one branch becomes unreachable and
    /// the knob would delete half a genre instead of biasing it. Whether ±0.15 is the musically
    /// right amount is a listening call; this is the one line to change for it.
    nonisolated static let livelinessThresholdSpan: Float = 0.3

    /// ⭐ #419 — THE SAME KNOB, A DELIBERATELY SMALLER TRAVEL, ON THE `.sustained` PATH.
    /// #418 wired Liveliness to the two melodic density decisions (`arpStep`, `pulseGap`) and
    /// BOTH sit behind `!profile.sustained`. Eight of the sixteen offered genres are Flächen —
    /// including `.selfObservation`, the genre a first-run user hears — so for exactly those the
    /// knob still did nothing. On a Fläche the movement lives in `heartbeatOnsets`: the arousal
    /// gate that decides held-vs-pulsing, and the two stride steps above it. Those three
    /// literals are what this span moves.
    ///
    /// ⚠️ WHY 0.2 AND NOT 0.3, and this is a founder doctrine rather than a taste: on the melodic
    /// path the knob decides how DENSELY an already-moving texture is filled; here it decides
    /// whether the Fläche moves AT ALL. The 2026-07-09 "Flächen still" call is what the founder
    /// liked about the meditative genres, and `heartbeatOnsets`' own doc states it as
    /// "calm = still, active = alive". So the knob may bring the onset of movement FORWARD and
    /// must never abolish the hold: at the fully-live extreme the gate is still `busy >= 0.4`,
    /// which a resting body does not reach (a settled take runs `busy` well under 0.35 — the
    /// `pulseInput` fixture in `LivelinessReachesTheDensityDecisionTests` had to push HR to 110
    /// to clear 0.55). At the fully-still extreme the gate is 0.6, so an aroused body can still
    /// move the pad — the knob biases, it does not veto.
    ///
    /// Whether 0.2 is the musically right amount is a listening call, exactly like its melodic
    /// twin; this is the one line to change for it.
    nonisolated static let stillnessThresholdSpan: Float = 0.2

    nonisolated static func tempoDensityScale(bpm: Double) -> Float {
        let baseline = 84.0
        guard bpm > baseline else { return 1.0 }          // slow stays full (75 is good)
        let scale = Float(pow(baseline / bpm, 0.85))       // thin as tempo climbs
        return Swift.max(scale, 0.5)                        // never thinner than half
    }

    public static func compose(_ input: Input) -> BioComposition {
        var rng = SeededRNG(seed: input.seed)
        // Skeleton RNG: structural choices (progression, register, ornament/lift/
        // syncopation placement, density) are drawn from here so they stay stable
        // while `rng` evolves the melodic detail. Defaults to the detail seed → the
        // original single-stream behaviour when no structureSeed is supplied.
        var structureRNG = SeededRNG(seed: input.structureSeed ?? input.seed)

        // ── Physiological → musical state (autonomic-balance + coherence servo) ──
        let (calm, _, energy, _, busy) = musicalState(
            coherence: input.coherence,
            hrvNormalized: input.hrvNormalized,
            heartRateBPM: Double(input.heartRateBPM))

        // CONSONANCE CONVERGENCE (servo): as coherence rises the melody should stray
        // LESS from chord tones — high coherence → more consonant/settled (the reward
        // for self-regulation; science brief: reduce tension depth, converge to
        // consonance). Scale the mood's tension down by coherence before it reaches
        // the melody generators; every other mood dimension is untouched.
        var effMood = input.mood
        effMood.tension = effectiveTension(input.mood.tension, coherence: input.coherence)

        // Tempo-adaptive Spielart (founder 2026-07-11): the fast melodic layers thin as the
        // PLAYBACK tempo rises so a fast take doesn't turn hectic. Resolved once (the clamped
        // tempo the loop actually runs at) and reused for `suggestedTempo`.
        let playTempo = tempo(for: input)
        let densityScale = tempoDensityScale(bpm: playTempo)

        // H1 voice-leading (opt-in): the bio→control mapping lives here in the
        // composer, not on the caller — see `voiceLeadControl`. nil = legacy path.
        let voiceLead = voiceLeadControl(for: input)

        // H2 chord journey (opt-in): coherence + skeleton seed for ChordSuggest —
        // see `chordSuggestControl`. nil = the legacy progression logic.
        let suggest = chordSuggestControl(for: input)

        let notes: [Note]
        let drumSteps: [[Bool]]
        let drumAccents: [[Bool]]

        switch input.style {
        case .dubTechno, .trap:
            // PURE FLÄCHEN (founder 2026-07-09: "die Melodie in den Genres war zu
            // laut und zu unnatürlich … reine Wellen-Töne stechen raus … besser
            // wenn die komplett weg sind — nur chillige mystische Flächen"). The
            // bespoke dubMelody/trapMelody lines (offbeat stabs / the exposed
            // dark-bell lead) are RETIRED from the flow: both genres now voice
            // their sustained, lead-free harmonicProfile through composeHarmonic —
            // held pad + held bass root, bar-exact for tight WAV loops. Only the
            // SIGNATURE beats stay hand-built. dubMelody/trapMelody remain defined
            // below (unused, reversible).
            notes = composeHarmonic(key: input.key, profile: input.style.harmonicProfile,
                                    calm: calm, busy: busy,
                                    breathPhase: input.breathPhase,
                                    breathDepth: input.breathDepth, mood: effMood,
                                    progressionPhase: input.progressionPhase,
                                    dynamicTilt: input.signatureDynamicTilt,
                                    densityScale: densityScale,
                                    quarterAnchor: input.style == .trap,
                                    articulation: input.style.chordArticulation,
                                    voiceLead: voiceLead,
                                    suggest: suggest,
                                    bassRhythm: input.bassRhythm,
                                    padRhythm: input.padRhythm,
                                    bassGrammar: input.style.bassGrammar,
                                    padGate: input.padGate, padAccent: input.padAccent,
                                    padEvolve: input.padEvolve,
                                    rng: &rng, structureRNG: &structureRNG)
            if input.style == .dubTechno {
                (drumSteps, drumAccents) = dubBeat(energy: energy, calm: calm, rng: &rng)
            } else {
                (drumSteps, drumAccents) = trapBeat(energy: energy, calm: calm, rng: &rng)
            }
        // .selfObservation is NO LONGER intercepted here (founder 2026-07-07: "in der
        // Hauptmelodie sehr laute quakige Töne … es soll sich mehr in den weichen
        // Trance-Pad-Ambient einfügen"). It used to route to `ambientMelody`, a BARE
        // monophonic .lead line with NO pad under it — a thin, exposed, formant-y tune,
        // exactly the loud "quakig" melody. Its harmonicProfile has ALWAYS been a lush
        // sustained drone (leadDensity 0), IDENTICAL to stillMeditation (the pad the
        // founder likes) — but that profile was never reached. Falling through to the
        // `default:` composeHarmonic path finally plays that drone Fläche. `ambientMelody`
        // stays defined below (unused, reversible) in case a gentle melodic mode returns.
        default:
            // The harmonic genres: pads/chords/arps + an optional lead — PLUS the
            // genre's groove skeleton (audit B5: every beat-driven genre now carries
            // its defining rhythm; classical/meditation stay drum-free by design).
            // Beat is drawn AFTER the melody so existing seeds reproduce their notes.
            notes = composeHarmonic(key: input.key, profile: input.style.harmonicProfile,
                                    calm: calm, busy: busy,
                                    breathPhase: input.breathPhase,
                                    breathDepth: input.breathDepth, mood: effMood,
                                    progressionPhase: input.progressionPhase,
                                    dynamicTilt: input.signatureDynamicTilt,
                                    densityScale: densityScale,
                                    articulation: input.style.chordArticulation,
                                    voiceLead: voiceLead,
                                    suggest: suggest,
                                    bassRhythm: input.bassRhythm,
                                    padRhythm: input.padRhythm,
                                    bassGrammar: input.style.bassGrammar,
                                    padGate: input.padGate, padAccent: input.padAccent,
                                    padEvolve: input.padEvolve,
                                    rng: &rng, structureRNG: &structureRNG)
            switch input.style.beatArchetype {
            case .fourOnFloor:
                (drumSteps, drumAccents) = fourOnFloorBeat(energy: energy, calm: calm,
                                                           flavor: input.style.beatFlavor, rng: &rng)
            case .backbeat:
                (drumSteps, drumAccents) = backbeatBeat(energy: energy, calm: calm,
                                                        flavor: input.style.beatFlavor, rng: &rng)
            case .offbeat:
                (drumSteps, drumAccents) = offbeatBeat(energy: energy, calm: calm,
                                                       flavor: input.style.beatFlavor, rng: &rng)
            case .halfTime:
                (drumSteps, drumAccents) = halfTimeBeat(energy: energy, calm: calm,
                                                        flavor: input.style.beatFlavor, rng: &rng)
            case .none, .signature:
                (drumSteps, drumAccents) = (emptyGrid(), emptyGrid())
            }
        }

        // Shape the bar's dynamics (metric accent + swell) so the whole texture breathes,
        // THEN add the seeded humanize jitter on top — flat loops read as unprofessional.
        let shaped = humanizeVelocity(
            shapeBarDynamics(notes, depth: Self.dynamicDepth, stepCount: stepCount),
            amount: input.mood.humanize, seed: input.seed)
        return BioComposition(
            // H3 (opt-in): the body's OWN heart rate variability as the final
            // micro-variability stage — off (default) is byte-identical to `shaped`.
            notes: input.humanize
                ? hrvHumanize(shaped, hrvNormalized: input.hrvNormalized, seed: input.seed)
                : shaped,
            drumSteps: drumSteps,
            drumAccents: drumAccents,
            suggestedTempo: playTempo
        )
    }

    private static func emptyGrid() -> [[Bool]] {
        Array(repeating: Array(repeating: false, count: stepCount), count: trackCount)
    }

    /// No drums at all — BeatMode.off (pure Flächen). Public so the studio can
    /// silence the groove layer without reaching the private emptyGrid.
    public static func silentBeat() -> (steps: [[Bool]], accents: [[Bool]]) {
        (emptyGrid(), emptyGrid())
    }

    /// The shamanic ur-rhythm (BeatMode.pulse — founder 2026-07-06C: "tendenziell
    /// eher schamanisch ur-rhythmisch"): ONE deep drum walking a steady, hypnotic
    /// quarter pulse with the cardiac lub-dub as its cell — the drum literally
    /// walks like a heart. Same bio grammar as the genre beats: `energy` (heart
    /// drive) adds the soft echo hits, a spacious (high-coherence) body strips
    /// every extra down to the bare pulse — and every rng draw happens
    /// UNCONDITIONALLY so a spacious take is a strict subset of the same seed.
    public static func shamanicBeat(seed: UInt64, energy: Float, calm: Float)
        -> (steps: [[Bool]], accents: [[Bool]]) {
        var rng = SeededRNG(seed: seed)
        var steps = emptyGrid()
        var accents = emptyGrid()
        let spacious = calm > 0.7

        // The steady frame-drum quarters — the monotone, trance-inducing base.
        for s in stride(from: 0, to: stepCount, by: 4) { steps[Track.kick][s] = true }
        accents[Track.kick][0] = true    // the bar breathes: 1 calls…
        accents[Track.kick][8] = true    // …3 answers

        // The cardiac "dub": a soft echo one 16th-pair after beats 1 and 3
        // (lub-DUB … lub-DUB). Earned by body drive, dropped when spacious.
        let pDub = rng.unit()
        if energy > 0.3 && !spacious {
            steps[Track.kick][2] = true
            if pDub < 0.6 { steps[Track.kick][10] = true }
        }

        // A rare low perc turn at the bar's end — the drummer's variation,
        // never a fill. Gone when the body is spacious.
        let pTurn = rng.unit()
        if !spacious && pTurn < 0.35 { steps[Track.perc][14] = true }

        return (steps, accents)
    }

    // MARK: - Archetype beats (audit B5 — the genre grooves for the harmonic genres)
    //
    // Same bio-reactive grammar as dubBeat/trapBeat: `energy` (heart drive) adds
    // movement, high coherence (`calm` > 0.7, "spacious") strips the seeded extras
    // so a settled body earns a settled groove — and every rng draw happens
    // UNCONDITIONALLY so a spacious take is a strict subset of the same seed.

    /// Kick on every beat, offbeat hats, backbeat clap — disco/synth-pop/psy drive.
    /// `flavor` (task #79 Slice A) is a purely declarative per-genre overlay: it never
    /// draws from `rng`, so the seeded melody + the pOpen/pPerc draws below stay
    /// byte-identical to before — the same genre+seed+bio always reproduces, while
    /// two DIFFERENT four-on-floor genres now diverge in hats/perc/kick. The archetype
    /// core (kick on every beat + backbeat clap on 2 & 4) is applied first and is never
    /// removed by the overlay.
    private static func fourOnFloorBeat(energy: Float, calm: Float,
                                        flavor: MusicStyle.GenreFlavor = .neutral,
                                        rng: inout SeededRNG)
        -> (steps: [[Bool]], accents: [[Bool]]) {
        var steps = emptyGrid()
        var accents = emptyGrid()
        let spacious = calm > 0.7

        for s in stride(from: 0, to: stepCount, by: 4) { steps[Track.kick][s] = true }
        accents[Track.kick][0] = true
        accents[Track.kick][8] = true

        // Backbeat clap on 2 & 4 — the dancefloor snap.
        steps[Track.clap][4] = true
        steps[Track.clap][12] = true
        accents[Track.clap][12] = true

        // Offbeat closed hats (the disco "&"), 16th fill only with real drive.
        for s in [2, 6, 10, 14] { steps[Track.closedHat][s] = true }
        if energy > 0.55 && !spacious {
            for s in stride(from: 0, to: stepCount, by: 2) { steps[Track.closedHat][s] = true }
        }

        // Open-hat lift into the loop + a seeded perc push.
        let pOpen = rng.unit()
        if energy > 0.35 && !spacious && pOpen < 0.7 { steps[Track.openHat][14] = true }
        let pPerc = rng.unit()
        if !spacious && pPerc < 0.5 { steps[Track.perc][pPerc < 0.25 ? 7 : 15] = true }

        // --- Per-genre flavor overlay (task #79) — RNG-free; perc ghost is bio-independent, closed hats are bio-reactive (applyHatRate) ---
        // Genre-signature perc ghost + optional kick push (shared, RNG-free — the
        // archetype-independent half of the flavor overlay, see applyFlavorGhost).
        // NOTE: the closed-hat row is now owned entirely by applyHatRate (task #82);
        // the base + energy hats above stand only for the `.inherit` fallback.
        applyFlavorGhost(&steps, flavor: flavor)
        applyHatRate(&steps, rate: flavor.hatRate, energy: energy, spacious: spacious)

        return (steps, accents)
    }

    /// The archetype-INDEPENDENT half of a genre flavor overlay (task #79): a single
    /// genre-unique perc ghost — what guarantees two genres in the SAME archetype
    /// never share bit-identical `drumSteps` — plus an optional syncopated kick push
    /// into the "1" (step 14, an EXTRA hit only). Draws NO rng, so the seeded draws
    /// upstream stay byte-identical and the take is deterministic. Both writes are
    /// additive and bounds-checked; `.neutral` (percGhostStep -1, no push) is a no-op.
    private static func applyFlavorGhost(_ steps: inout [[Bool]], flavor: MusicStyle.GenreFlavor) {
        if steps[Track.perc].indices.contains(flavor.percGhostStep) {
            steps[Track.perc][flavor.percGhostStep] = true
        }
        if flavor.kickPushEnabled { steps[Track.kick][14] = true }
        // A second genre-signature kick step (task #79 follow-up): an EXTRA hit that
        // survives the calm strip, distinct per genre so same-archetype genres diverge
        // on the kick too. Bounds-guarded; -1 (default) is a no-op. RNG-free.
        if steps[Track.kick].indices.contains(flavor.kickCell) {
            steps[Track.kick][flavor.kickCell] = true
        }
    }

    /// Set the closed-hat row to the genre's calm-surviving signature texture
    /// (task #79 follow-up, founder 2026-07-22; owns the closed-hat row entirely
    /// since task #82). For a non-`.inherit` `hatRate` this REPLACES the hats with a
    /// genre-defining CALM base pattern that reads distinctly even when the body is
    /// calm and the seeded ornaments have stripped, then adds an ADDITIVE energy
    /// overlay (bio-reactivity: a driving body densifies the hats one step further
    /// WITHIN the genre's character). RNG-free — the seeded melody/perc draws stay
    /// byte-identical — and energy is a deterministic function of the bio snapshot,
    /// so the take reproduces exactly per seed. The overlay is purely additive, so the
    /// settled hits are a subset of the aroused hits. `.inherit` is a no-op (the
    /// archetype's own base + energy hats stand as the fallback).
    private static func applyHatRate(_ steps: inout [[Bool]], rate: MusicStyle.HatRate,
                                     energy: Float, spacious: Bool) {
        guard rate != .inherit else { return }
        let ch = Track.closedHat
        for s in steps[ch].indices { steps[ch][s] = false }   // clear, then set the signature
        // The genre's CALM base texture — always present, so a settled body still reads
        // as THIS genre (the founder-2026-07-22 fix).
        switch rate {
        case .inherit:  break                                             // unreachable (guarded)
        case .offbeat:  for s in [2, 6, 10, 14] where steps[ch].indices.contains(s) { steps[ch][s] = true }
        case .driving:  for s in stride(from: 0, to: stepCount, by: 2) { steps[ch][s] = true }
        case .sixteenth: for s in 0..<stepCount { steps[ch][s] = true }
        case .quarter:  for s in stride(from: 0, to: stepCount, by: 4) { steps[ch][s] = true }
        case .sparse:   for s in [0, 8] where steps[ch].indices.contains(s) { steps[ch][s] = true }
        }
        // ENERGY overlay (bio-reactivity restored — north-star "the music changes with the
        // body"; dsp-review follow-up to the calm-only Slice 2): as the body DRIVES (and is
        // not settled), densify the hats ONE step further WITHIN the genre's character, so a
        // genre stays relatively lighter/busier than its neighbours at BOTH calm and aroused.
        // Purely ADDITIVE → settled hits ⊆ aroused hits (subset invariant holds). Energy is a
        // deterministic function of the bio snapshot, so the take still reproduces per seed.
        guard energy > 0.5 && !spacious else { return }
        switch rate {
        case .inherit, .sixteenth: break                                          // already maximal / n/a
        case .sparse:   for s in [4, 12] where steps[ch].indices.contains(s) { steps[ch][s] = true }  // → quarter pulse
        case .quarter:  for s in [2, 6, 10, 14] where steps[ch].indices.contains(s) { steps[ch][s] = true } // → 8ths
        case .offbeat:  for s in [0, 8] where steps[ch].indices.contains(s) { steps[ch][s] = true }   // fuller offbeat
        case .driving:  for s in 0..<stepCount { steps[ch][s] = true }            // → rolling 16ths
        }
    }

    /// Kick 1 (+3), snare 2 & 4, driving 8th hats — rock/punk/metal backbone.
    /// `flavor` (task #79 Slice B) is the same purely declarative, RNG-free per-genre
    /// overlay used by `fourOnFloorBeat`: it never draws `rng`, so the seeded pKick/
    /// pOpen draws stay byte-identical and the take reproduces exactly, while two
    /// DIFFERENT backbeat genres now diverge (hats/perc/kick). The archetype core
    /// (snare on 2 & 4, kick anchors) is placed first and never removed by the overlay.
    private static func backbeatBeat(energy: Float, calm: Float,
                                     flavor: MusicStyle.GenreFlavor = .neutral,
                                     rng: inout SeededRNG)
        -> (steps: [[Bool]], accents: [[Bool]]) {
        var steps = emptyGrid()
        var accents = emptyGrid()
        let spacious = calm > 0.7

        steps[Track.kick][0] = true
        steps[Track.kick][8] = true
        accents[Track.kick][0] = true
        if energy > 0.45 { steps[Track.kick][10] = true }   // the push into beat 4
        let pKick = rng.unit()
        if !spacious && pKick < 0.4 { steps[Track.kick][6] = true }

        // THE backbeat: snare on 2 & 4, always accented.
        steps[Track.snare][4] = true
        steps[Track.snare][12] = true
        accents[Track.snare][4] = true
        accents[Track.snare][12] = true

        // Driving 8th closed hats; open hat crash-lift only when really moving.
        for s in stride(from: 0, to: stepCount, by: 2) { steps[Track.closedHat][s] = true }
        let pOpen = rng.unit()
        if energy > 0.6 && !spacious && pOpen < 0.6 { steps[Track.openHat][14] = true }

        // --- Per-genre flavor overlay (task #79 Slice B) — RNG-free; perc ghost is bio-independent, closed hats are bio-reactive (applyHatRate) ---
        // NOTE: the closed-hat row is now owned entirely by applyHatRate (task #82);
        // the base + energy hats above stand only for the `.inherit` fallback.
        applyFlavorGhost(&steps, flavor: flavor)
        applyHatRate(&steps, rate: flavor.hatRate, energy: energy, spacious: spacious)

        return (steps, accents)
    }

    /// Kick anchor on 1 & 3, skank stabs on every offbeat — ska/rocksteady/klezmer.
    /// `flavor` (task #79 Slice C) is the same RNG-free per-genre overlay: the skank
    /// perc (2/6/10/14) is the archetype signature and stays; each genre's ghost is
    /// placed on a FREE perc slot (see beatFlavor), so two offbeat genres diverge
    /// without ever touching the skank. Determinism preserved (no rng draw here).
    private static func offbeatBeat(energy: Float, calm: Float,
                                    flavor: MusicStyle.GenreFlavor = .neutral,
                                    rng: inout SeededRNG)
        -> (steps: [[Bool]], accents: [[Bool]]) {
        var steps = emptyGrid()
        var accents = emptyGrid()
        let spacious = calm > 0.7

        steps[Track.kick][0] = true
        steps[Track.kick][8] = true
        accents[Track.kick][0] = true

        // The skank: percussive stabs on the offbeats carry the genre.
        for s in [2, 6, 10, 14] {
            steps[Track.perc][s] = true
            accents[Track.perc][s] = true
        }

        // Soft snare on 3 (one-drop lean); quarter-note hats keep time underneath.
        steps[Track.snare][8] = true
        for s in stride(from: 0, to: stepCount, by: 4) { steps[Track.closedHat][s] = true }

        // Energy doubles the skank with closed hats; a seeded clap answers on 4.
        if energy > 0.5 && !spacious {
            for s in [2, 6, 10, 14] { steps[Track.closedHat][s] = true }
        }
        let pClap = rng.unit()
        if !spacious && pClap < 0.4 { steps[Track.clap][12] = true }

        // --- Per-genre flavor overlay (task #79 Slice C) — RNG-free; perc ghost is bio-independent, closed hats are bio-reactive (applyHatRate) ---
        // NOTE: the closed-hat row is now owned entirely by applyHatRate (task #82);
        // the base + energy hats above stand only for the `.inherit` fallback.
        applyFlavorGhost(&steps, flavor: flavor)
        applyHatRate(&steps, rate: flavor.hatRate, energy: energy, spacious: spacious)

        return (steps, accents)
    }

    /// Sparse kick, big snare on 3, air between the hits — doom/vaporwave/sci-fi.
    /// `flavor` (task #79 Slice C) is the same RNG-free per-genre overlay: the perc
    /// track is free in this archetype, so each genre's ghost step is collision-free
    /// by construction and the three half-time genres diverge without touching the
    /// snare-on-3 lean. Determinism preserved (the overlay draws no rng).
    private static func halfTimeBeat(energy: Float, calm: Float,
                                     flavor: MusicStyle.GenreFlavor = .neutral,
                                     rng: inout SeededRNG)
        -> (steps: [[Bool]], accents: [[Bool]]) {
        var steps = emptyGrid()
        var accents = emptyGrid()
        let spacious = calm > 0.7

        steps[Track.kick][0] = true
        accents[Track.kick][0] = true
        let pKick = rng.unit()
        if energy > 0.4 && pKick < 0.6 { steps[Track.kick][7] = true }   // the drag hit

        // Half-time snare on beat 3 — the whole genre leans on this one hit.
        steps[Track.snare][8] = true
        accents[Track.snare][8] = true

        // Quarter hats for pulse; 8ths only when the body drives, never when settled.
        for s in stride(from: 0, to: stepCount, by: 4) { steps[Track.closedHat][s] = true }
        if energy > 0.6 && !spacious {
            for s in stride(from: 0, to: stepCount, by: 2) { steps[Track.closedHat][s] = true }
        }
        let pOpen = rng.unit()
        if !spacious && pOpen < 0.35 { steps[Track.openHat][15] = true } // tail lift

        // --- Per-genre flavor overlay (task #79 Slice C) — RNG-free; perc ghost is bio-independent, closed hats are bio-reactive (applyHatRate) ---
        // NOTE: the closed-hat row is now owned entirely by applyHatRate (task #82);
        // the base + energy hats above stand only for the `.inherit` fallback.
        applyFlavorGhost(&steps, flavor: flavor)
        applyHatRate(&steps, rate: flavor.hatRate, energy: energy, spacious: spacious)

        return (steps, accents)
    }

    // MARK: - Dub Techno (deep dub chords · tape echo · sub-bass)

    /// Steady 4/4 kick, offbeat ticks, a deep sub on 1 & 3, a soft backbeat and a
    /// little seeded perc. Hypnotic and spacious — the genre's signature.
    private static func dubBeat(energy: Float, calm: Float, rng: inout SeededRNG)
        -> (steps: [[Bool]], accents: [[Bool]]) {
        var steps = emptyGrid()
        var accents = emptyGrid()
        // High coherence settles the groove too (rhythmic analog of the density
        // servo): the backbone stays, the "extra movement" is suppressed.
        let spacious = calm > 0.7

        // 4-on-the-floor kick — the dub pulse.
        for s in stride(from: 0, to: stepCount, by: 4) { steps[Track.kick][s] = true }
        accents[Track.kick][0] = true
        accents[Track.kick][8] = true

        // Offbeat closed-hat tick (the "tss" between the kicks).
        for s in [2, 6, 10, 14] { steps[Track.closedHat][s] = true }

        // Offbeat open-hat skank once there's drive (eased off when the body settles).
        if energy > 0.35 && !spacious { steps[Track.openHat][6] = true; steps[Track.openHat][14] = true }

        // Soft backbeat clap on beat 4 (and 2 when energetic, unless settled).
        steps[Track.clap][12] = true
        accents[Track.clap][12] = true
        if energy > 0.5 && !spacious { steps[Track.clap][4] = true }

        // Deep dub sub on the 1 and the 3.
        steps[Track.bass][0] = true
        steps[Track.bass][8] = true

        // A little seeded perc for movement — taste, not noise; dropped when settled.
        // (Draw the rng unconditionally so a settled take is a strict subset.)
        let pPerc = rng.unit()
        if !spacious && pPerc < 0.6 {
            steps[Track.perc][rng.unit() < 0.5 ? 7 : 11] = true
        }

        return (steps, accents)
    }

    /// Dub chord stabs: a i→IV triad move on the offbeats, soft and spacious.
    /// Drenched in delay by the patch — here we place the harmony.
    private static func dubMelody(key: MusicalKey, busy: Float,
                                  breathDepth: Float, rng: inout SeededRNG) -> [Note] {
        var notes: [Note] = []
        let octave = 4
        let velocity = clamp01(0.42 + 0.22 * breathDepth)

        // Busy → stab on both offbeats of each half; calm → just the later one.
        func positions(_ pair: [Int]) -> [Int] { busy > 0.5 ? pair : [pair[1]] }

        func addChord(rootDegree: Int, at step: Int) {
            let length = max(1, min(busy > 0.5 ? 2 : 3, stepCount - step))
            for interval in [0, 2, 4] {     // root · third · fifth = an in-key triad
                let pitch = key.degree(rootDegree + interval, octave: octave)
                notes.append(Note(id: nextUUID(&rng), pitch: pitch, startStep: step,
                                  lengthSteps: length, velocity: velocity))
            }
        }

        // The first half anchors on the tonic; the second half moves to a seeded
        // in-key chord (IV / VI / v / VII) so it isn't forever the same i→IV stab.
        let secondDegrees = [3, 5, 4, 6]
        let second = secondDegrees[Int(rng.next() % UInt64(secondDegrees.count))]
        for s in positions([2, 6])  { addChord(rootDegree: 0, at: s) }        // i (tonic)
        for s in positions([10, 14]) { addChord(rootDegree: second, at: s) }  // seeded move

        // Sustained root bass (octave 2, role .bass) mirroring the trap sub — dub's whole
        // identity is a deep sub under spacious chord stabs. Without this the generative path
        // played dub with NO low end (the offbeat triads live at octave 4, all .harmony; the
        // dub sub only existed on the SILENCED drum grid). Follows the harmony: tonic under
        // the first half, the seeded `second` degree under the move. .bass also drives the
        // octave-doubling subBass voice and the firmer dub bass mix level.
        let subVel = clamp01(0.6 + 0.2 * breathDepth)
        notes.append(Note(id: nextUUID(&rng), pitch: key.degree(0, octave: 2),
                          startStep: 0, lengthSteps: 8, velocity: subVel, role: .bass))
        notes.append(Note(id: nextUUID(&rng), pitch: key.degree(second, octave: 2),
                          startStep: 8, lengthSteps: 8, velocity: subVel, role: .bass))
        return notes
    }

    // MARK: - Trap (booming 808 sub-bass · crisp hats · dark melody)

    /// Syncopated 808 kick, half-time snare/clap on beat 3, rolling 16th hats and
    /// the open-hat lift into the loop. The 808 sub mirrors the kick.
    private static func trapBeat(energy: Float, calm: Float, rng: inout SeededRNG)
        -> (steps: [[Bool]], accents: [[Bool]]) {
        var steps = emptyGrid()
        var accents = emptyGrid()

        // High coherence settles the groove (drops the seeded extras; backbone stays).
        let spacious = calm > 0.7

        // 808 kick: syncopated, half-time feel. The Bass track doubles it (the 808).
        var kickHits = [0, 6, 10]
        if energy > 0.5 { kickHits.append(3) }
        let pKick = rng.unit()                  // drawn unconditionally (subset on settle)
        if !spacious && pKick < 0.5 { kickHits.append(11) }
        for s in kickHits {
            steps[Track.kick][s] = true
            steps[Track.bass][s] = true
        }
        accents[Track.kick][0] = true

        // Snare + clap on beat 3 (step 8) — the half-time backbeat.
        steps[Track.snare][8] = true
        steps[Track.clap][8] = true
        accents[Track.snare][8] = true
        accents[Track.clap][8] = true

        // Rolling 16th hats across the whole bar.
        for s in 0..<stepCount { steps[Track.closedHat][s] = true }
        accents[Track.closedHat][7] = true
        accents[Track.closedHat][15] = true

        // Hat roll + open-hat lift into the loop, busier when energetic.
        if energy > 0.6 {
            accents[Track.closedHat][14] = true
            steps[Track.openHat][15] = true
        } else {
            steps[Track.openHat][15] = true
        }

        // Sparse seeded perc — dropped when the body is settled (subset on settle).
        let pPerc = rng.unit()
        if !spacious && pPerc < 0.5 {
            steps[Track.perc][rng.unit() < 0.5 ? 5 : 13] = true
        }

        return (steps, accents)
    }

    /// A dark, sparse bell lead up top plus a low 808 root line — both exportable
    /// as MIDI so the body's melody lands in Ableton / FL Studio with pitch.
    private static func trapMelody(key: MusicalKey, busy: Float, calm: Float,
                                   breathPhase: Float, breathDepth: Float,
                                   rng: inout SeededRNG) -> [Note] {
        var notes: [Note] = []

        // Low 808 root line on the downbeats (octave 2), long + gliding.
        let subVel = clamp01(0.7 + 0.2 * breathDepth)
        for s in [0, 8] {
            let pitch = key.degree(0, octave: 2)
            notes.append(Note(id: nextUUID(&rng), pitch: pitch, startStep: s,
                              lengthSteps: 6, velocity: subVel, role: .bass))
        }

        // Sparse dark bell lead up top (octave 5), harmonic-minor tension.
        let leadOctave = 5
        let noteCount = 3 + Int((busy * 3).rounded())   // 3…6
        let inhaleBias: Float = breathPhase < 0.5 ? 0.65 : 0.35
        // Seeded opening degree (was always 0) so the dark bell line doesn't open on
        // the same note every take.
        var degree = Int(rng.next() % 3)
        // Motif contour (Cycle 3) so the bell line states + answers a shape instead
        // of wandering; small weird keeps the dark, slightly-unpredictable character.
        let leadDeltas = Self.motifDeltas(count: noteCount,
                                          directionBias: inhaleBias,
                                          weird: 0.2, rng: &rng)
        var lastStart = -1
        for i in 0..<noteCount {
            let start = i * stepCount / noteCount
            let startStep = min(stepCount - 1, max(start, lastStart + 1))
            lastStart = startStep

            let pitch = key.degree(degree, octave: leadOctave)
            let length = max(1, min(calm > 0.5 ? 3 : 2, stepCount - startStep))
            // Phrase arc + downbeat accent for dynamics (not a flat velocity).
            let pos = noteCount > 1 ? Float(i) / Float(noteCount - 1) : 0
            let arc = clamp01(1 - abs(pos - 0.6) * 1.4)
            let metric: Float = (startStep % 4 == 0) ? 0.1 : 0
            let velocity = clamp01(0.42 + 0.3 * breathDepth + 0.16 * arc + metric)
            notes.append(Note(id: nextUUID(&rng), pitch: pitch, startStep: startStep,
                              lengthSteps: length, velocity: velocity, role: .lead))

            degree = min(14, max(-7, degree + leadDeltas[i]))
        }
        return notes
    }

    // MARK: - Self-Observation (ambient, no drums)

    /// A gentle, breath-paced contour for meditation. Calmer coherence → longer,
    /// more stepwise notes; the breath sets the rise/fall.
    private static func ambientMelody(key: MusicalKey, calm: Float, busy: Float,
                                      breathPhase: Float, breathDepth: Float,
                                      mood: MoodProfile, rng: inout SeededRNG) -> [Note] {
        // Density follows the autonomic state (`busy` already folds in heart rate,
        // vagal tone/HRV and coherence), scaled by the user's liveliness. clamp01
        // keeps the count in range. Darkness drops the line an octave.
        let density = clamp01(busy * (0.6 + 0.8 * clamp01(mood.liveliness)))
        let noteCount = 2 + Int((density * 6).rounded())       // 2…8
        let inhaleBias: Float = breathPhase < 0.5 ? 0.7 : 0.3
        let octave = 4 + (mood.darkness > 0.6 ? -1 : 0)

        var notes: [Note] = []
        // Seeded opening degree (was always 0) so the breath line doesn't always
        // start on the tonic — gentle variety without breaking the calm character.
        var degree = Int(rng.next() % 3)
        // Motif contour (Cycle 3): a gentle stated+answered shape that resolves; a
        // calm body keeps it stepwise (weird 0), an unsettled one loosens it slightly.
        let leadDeltas = Self.motifDeltas(count: noteCount,
                                          directionBias: inhaleBias,
                                          weird: calm > 0.5 ? 0 : 0.15, rng: &rng)
        var lastStart = -1
        for i in 0..<noteCount {
            let start = i * stepCount / noteCount
            let startStep = min(stepCount - 1, max(start, lastStart + 1))
            lastStart = startStep

            let pitch = key.degree(degree, octave: octave)
            let gap = Float(stepCount) / Float(noteCount)
            let lenF = gap * (0.5 + 0.5 * calm)
            let length = max(1, min(Int(lenF.rounded()), stepCount - startStep))

            // Gentle phrase arc on top of the downbeat accent for breathing dynamics.
            let pos = noteCount > 1 ? Float(i) / Float(noteCount - 1) : 0
            let arc = clamp01(1 - abs(pos - 0.5) * 1.2)
            let accent: Float = (startStep % 8 == 0) ? 0.15 : 0
            let velocity = clamp01(0.5 + 0.28 * breathDepth + 0.12 * arc + accent)

            notes.append(Note(id: nextUUID(&rng), pitch: pitch, startStep: startStep,
                              lengthSteps: length, velocity: velocity, role: .lead))

            degree = min(14, max(-7, degree + leadDeltas[i]))
        }
        return notes
    }

    // MARK: - Harmonic genres (pads · chords · arps · leads — no drums)

    /// The starting material for a professional production: a chord progression
    /// voiced as a sustained pad or a rising arpeggio, plus an optional lead line.
    /// All in-key, all inside the bar, exportable as MIDI. Genre character comes
    /// from the `HarmonicProfile`; the body animates density and velocity.
    /// Humanize a velocity by ±5% so repeated notes/chords breathe instead of
    /// sounding mechanically identical. Deterministic given the seed.
    private static func hVel(_ v: Float, _ rng: inout SeededRNG) -> Float {
        clamp01(v + (rng.unit() - 0.5) * 0.10)
    }

    /// Metric-accent multiplier for a chord chop at a bar-aligned step — the basic metrical
    /// hierarchy (downbeat strongest, then beat 3, then the other beats, weak positions
    /// softest). It makes the genre-articulated chops (skank/stab/comp, task 2026-07-22) read
    /// as INTENTIONAL rather than mechanical — uniform-volume chops sound robotic/amateur
    /// ("unprofessionell"). Subtle range (0.86…1.0) so it shapes dynamics without gutting the
    /// weak-beat chops; the random `hVel` humanisation rides on top. Pure/deterministic; a
    /// universal music principle, not genre-specific taste.
    static func metricAccent(step: Int) -> Float {
        let phase = ((step % 16) + 16) % 16
        if phase == 0 { return 1.0 }        // downbeat
        if phase == 8 { return 0.95 }       // beat 3
        if phase % 4 == 0 { return 0.92 }   // beats 2 & 4
        return 0.86                          // offbeats / weak positions
    }

    /// Build a MOVING bass line for one chord section instead of a single held
    /// root. The section downbeat is always the chord root (the foundation); on
    /// takes with drive it subdivides into root/fifth hits and walks a passing
    /// tone up to the NEXT chord's root at the section end — a real bass line,
    /// like a player, not a drone. Calm or short sections keep one sustained root
    /// so spacious genres stay spacious. All tones resolve through
    /// `MusicalKey.degree` → always in key. `role: .bass` so the sub follows it.
    /// Deterministic given the seed.
    ///
    /// ⭐ #983: a genre with a `BassGrammar` (`MusicStyle.bassGrammar`, today deepHouse /
    /// techHouse / minimalTechno / deepTech) takes NONE of the paths described above or below — it plays
    /// its authored figure and returns, unless the user's Bass-rhythm Picker is set. Under a
    /// grammar the downbeat is NOT always the chord root (house leaves it free). Everything in
    /// this doc from here on describes the `grammar == nil` genres, unchanged.
    ///
    /// ⚠️ THE WALKING PATH IS NOT REACHED BY MOST TAKES, and `rhythm:` only reaches it — so any
    /// claim about what a rhythm character does is conditional on all THREE parts of the guard
    /// below: `!sustained` (the genre is not a Fläche), `motion > 0.32` (`busy · 0.7 +
    /// (1 − calm) · 0.4`, so a SETTLED body fails it on every genre) and `len >= 4` (a five-chord
    /// progression over 16 steps gives sections of 3). Saying only "sustained genres hold a root"
    /// — which is what this doc used to say — reads as "every other genre walks", and a reader
    /// would then take a resting-body take that ignores the Picker for a broken binding.
    private static func appendBass(into notes: inout [Note], key: MusicalKey,
                                   rootDegree: Int, nextRoot: Int, octave: Int,
                                   secStart: Int, len: Int, busy: Float, calm: Float,
                                   velocity: Float, sustained: Bool,
                                   quarterAnchor: Bool = false,
                                   alterations: [Int] = [],
                                   // NOT defaulted, deliberately: the bug this parameter fixes was
                                   // "the rotation index was always 0", and a default of 0 would let
                                   // a future second call site reproduce it by omission, with
                                   // nothing in the diff to see. One caller — the cost is nil.
                                   sectionIndex: Int,
                                   rhythm: RoleRhythm.Character? = nil,
                                   // #983: the genre's authored figure. NOT defaulted — see
                                   // `composeHarmonic`'s parameter of the same name. One caller.
                                   grammar: BassGrammar?,
                                   // #419: the trap 808 pedal shares `heartbeatActive` with the pad
                                   // — that sharing is the whole point of hoisting the gate, and the
                                   // doc there says "identical across the low end and the pad". If
                                   // only the pad passed the knob that sentence would become false.
                                   liveliness: Float,
                                   rng: inout SeededRNG) {
        // H2: semitone alteration of a chord tone (root / fifth) when the
        // section's chord is a borrowed suggestion. Empty (legacy: always) ⇒ 0.
        func alt(_ tone: Int) -> Int {
            ChordSuggest.alteration(forToneOffset: tone,
                                    degreesPerOctave: key.degreesPerOctave,
                                    in: alterations)
        }
        // #983 GENRE BASS GRAMMAR — the genre's OWN figure, and it comes before every body gate
        // below on purpose: like `.skank` on the pad, the house offbeat / tech 8ths / minimal
        // held root ARE the genre at a resting body too. The body keeps the LEVEL (the section
        // `velocity` already carries breath depth and the low-end tilt; `hVel` humanises), the
        // genre keeps the PLACE. Precedence, stated in `BassGrammar.swift`: a user's Bass-rhythm
        // Picker choice (`rhythm != nil`) wins and takes the walking path exactly as before —
        // the person named a character, the genre only offered one. `grammar == nil` (every
        // genre without a figure) falls through to the unchanged code below, byte-identical:
        // no RNG is touched on this line for those genres, so the #253 A3 Golden law holds.
        //
        // The figure is authored on the 16-step BAR and cut by the section: a hit plays if its
        // phase falls inside `[secStart, secStart + len)` — a 3-chord progression (5/5/6-step
        // sections) simply gets the hits that land in each section. A section that catches no
        // hit stays SILENT in the bass. That is deliberate and it is the first time this
        // function lets a section start on air: the old "the section downbeat IS the chord
        // root" contract does not hold under a grammar (the house "&" needs the 1 free), and the
        // felt sub — which used to inherit the pad's lowest note in that hole — is coupled to
        // the `.bass` role in the same slice so the hole is a hole (`PianoRollModel`).
        if let grammar, rhythm == nil {
            let secEndLocal = secStart + len
            for hit in grammar.hits {
                // Absolute step in this section with the hit's bar phase (the composer's take
                // is one bar, so at most one step per section can match).
                var step = secStart
                while step < secEndLocal {
                    if ((step % 16) + 16) % 16 == hit.phase { break }
                    step += 1
                }
                guard step < secEndLocal else { continue }
                let noteLen = max(1, min(hit.length, secEndLocal - step))
                let degree = hit.fifth ? rootDegree + 4 : rootDegree
                let alteration = hit.fifth ? alt(4) : alt(0)
                notes.append(Note(id: nextUUID(&rng),
                                  pitch: key.degree(degree, octave: octave) + alteration,
                                  startStep: step, lengthSteps: noteLen,
                                  velocity: hVel(clamp01(velocity * hit.level), &rng),
                                  role: .bass))
            }
            return
        }
        // TRAP quarter-note 808 pedal (B8): a sustained trap profile whose body is aroused
        // drives the chord root on the quarter grid — one pitch class, downbeat accented —
        // so beats 2 & 4 no longer drop out. Calm trap (and every non-trap caller, which
        // never sets quarterAnchor) falls through to the held-root path below, RNG-identical.
        if quarterAnchor, sustained, Self.quarterAnchorBass,
           Self.heartbeatActive(energy: busy, secLen: len, liveliness: liveliness) {
            let gap = 4                                        // quarter grid
            let secEndLocal = secStart + len
            var s = secStart
            while s < secEndLocal {
                let noteLen = max(1, min(gap, secEndLocal - s))
                // Accent the SECTION downbeat (relative, so it holds even if a mood
                // splice makes sections an odd length); off-quarters sit back.
                let vel = ((s - secStart) % 8 == 0) ? velocity : velocity * 0.7
                notes.append(Note(id: nextUUID(&rng),
                                  pitch: key.degree(rootDegree, octave: octave) + alt(0),
                                  startStep: s, lengthSteps: noteLen,
                                  velocity: hVel(vel, &rng), role: .bass))
                s += gap
            }
            return
        }
        let motion = clamp01(busy * 0.7 + (1 - calm) * 0.4)
        // A sustained drone (or a spacious / short section) keeps the grounding
        // single held root — no walking line, whatever the body is doing.
        guard !sustained, motion > 0.32, len >= 4 else {
            notes.append(Note(id: nextUUID(&rng),
                              pitch: key.degree(rootDegree, octave: octave) + alt(0),
                              startStep: secStart, lengthSteps: len,
                              velocity: hVel(velocity, &rng), role: .bass))
            return
        }
        let gap = (motion > 0.62 && len >= 8) ? 2 : 4      // 8ths when driving, else quarters
        let secEndLocal = secStart + len
        var hitStarts: [Int] = []
        // #253 A3: a chosen rhythm character re-shapes the walk. `nil` skips this whole block and
        // the even `gap` grid below runs byte-identically — the Golden law.
        //
        // The BODY still owns the rate: the density handed to `RoleRhythm` is derived from the very
        // same `motion`/`gap` decision the genre made (8ths → 0.5, quarters → 0.25 of a 16-step
        // bar), so an even-spread character sounds the SAME NUMBER of notes as today. That is what
        // keeps this an override of FEEL rather than a second tempo control fighting the
        // biofeedback — and it is also the reason the six characters do not all differ in the same
        // dimension, which is worth stating precisely because the first version of this comment
        // claimed the character "replaces WHICH steps the walk lands on" for all six:
        //   · `driving` and `dynamic` select the SAME cells at these densities (both are the plain
        //     even spread) and are told apart by note LENGTH (gate ×0.45 vs ×0.7) and by accent
        //     CONTOUR (hard-on-the-beat vs a moving wave).
        //   · `flowing` starts from that same even spread but is NOT identical to it: at the
        //     `evolve: 0.2` this call site passes, its per-cell coin flip adds or removes a cell
        //     with ~3.6 % probability each — a note more or a note less, which is the point of it.
        //     (An earlier version of this bullet listed `flowing` with the other two as "the SAME
        //     cells", contradicted by the very fallback note further down that says its flip can
        //     drop a cell even at density 1.)
        //   · `hypnotic` rotates the figure once per SECTION — see the rotation index below.
        //   · `syncopated` moves the walk off the beat (cells ≡ 2 mod 4 at the quarter grid).
        //   · `sparse` squares the density, so it thins the walk down towards the foundation note.
        // Three audible dimensions across six names; whether that is enough to hear as six
        // RHYTHMS is a device question and is filed as such (#253 listening items).
        //
        // ⛔ AND `push` IS NOT ONE OF THE DIMENSIONS **HERE** — the qualifier is new and load-bearing.
        // `RoleRhythm` computes `syncopated`'s late pull and `flowing`'s laid-back hair, and since
        // #253 A2b the ARP honours them (`FieldAutoPlay.arpTouches` carries `pushFraction`; the Field
        // view schedules the onset late). This consumer does not — and the blocker is PLAYBACK, not
        // this file's data model.
        //
        // ⚠️ THE FIRST VERSION OF THIS PARAGRAPH GOT THAT BACKWARDS and the review caught it. It said
        // `Note.startStep` "cannot carry 0.12 of a cell AT ALL", called it "a model limit", and
        // budgeted "persistence and export consequences". The model carries it fine: `Note.startTick`
        // is the source of truth at 120 ticks per 16th, `startStep` is a rounding accessor, `Note`
        // has a public tick-precise init for exactly this, `BreathArp` already writes a swing offset
        // into `startTick`, and `Note`'s `Codable` plus `MIDIFileExporter` are both tick-faithful.
        // 0.12 of a cell is 14 ticks — expressible, persistable, exportable, today.
        //
        // What is NOT: `PianoRollModel.trigger(_ step:)`, driven by `PatternEngine.onTick(step)`,
        // starts a note only where `startStep == step`. A pushed onset would therefore be silent
        // live and audible only in an exported file — the worst of the two. So writing a sub-step
        // `startTick` here would be a HALF feature, and the honest sequence is trigger granularity
        // first. Naming the wrong blocker mattered because it made a call-site change look like a
        // model + persistence + export epic, which is how a cheap slice stays unbuilt.
        //
        // Until then no copy anywhere may promise the BASS or PAD swings — the A7 review had to
        // strike that same promise out of two arp blurbs back when nothing honoured push at all.
        //
        // Counted on the composer's 16-step BAR and not on the section, using ABSOLUTE steps: the
        // characters that subdivide (`sparse`, `syncopated` read `beat = cells/4`) must land on real
        // quarters. Feeding them a section length would make "the beat" whatever the section
        // happens to be, and an 11-step mood splice would put their accents nowhere musical.
        var rhythmHits: [Int: RoleRhythm.Hit] = [:]
        if let character = rhythm {
            let cells = 16                                  // the composer's bar, in 16th cells
            let density: Float = gap == 2 ? 0.5 : 0.25
            // The three dials the bass has no row for are written out rather than inherited.
            // `Params(character:density:)` silently took gate 0.8 / accent 0.4 / evolve 0.2 — real
            // musical values arriving from the ARP's defaults, so a re-tune of the arp's feel would
            // have re-voiced every bassline with nothing in the diff to see. These are the same
            // three numbers, now owned here.
            let params = RoleRhythm.Params(character: character, density: density,
                                           gate: 0.8, accent: 0.4, evolve: 0.2)
            // ONE seed for the whole section, drawn once. Drawing per step would hand `RoleRhythm` a
            // different stream for every cell, which makes the two characters that consult the RNG
            // (`flowing`'s cell flips, `dynamic`'s level jitter) re-roll per call instead of being a
            // reproducible function of (bar, cell, seed) — the property this whole core is built on.
            let rhythmSeed = rng.next()
            // THE ROTATION INDEX, and getting it right took two attempts because both wrong answers
            // look correct in a diff.
            //   1. The first version passed `bar: step / 16`. Every step of a take is below
            //      `stepCount == 16`, so that was ALWAYS 0 — and `hypnotic`'s entire identity is its
            //      rotation, which at a frozen 0 reduces to the plain even spread, i.e. `driving`'s
            //      cells. The one character named after a slowly-turning figure was the only one
            //      that could not turn.
            //   2. Passing the plain section INDEX fixed that and walked into a subtler version of
            //      it. At `cells == 16` only `bar % 4` decides anything, and a 3-chord progression
            //      gives 5-step sections, so `secStart = 5·idx ≡ idx (mod 4)` — the rotation
            //      cancelled EXACTLY against the section's own start cell, every section fired on
            //      its own downbeat, and `hypnotic`'s placement came out identical to the genre's
            //      default grid. An override landing on the default grid is the #81/#125 defect
            //      wearing a new name, and a test asserting only "≠ driving" cannot see it.
            // So the rotation is measured FROM THE SECTION'S OWN DOWNBEAT: entry offset within the
            // section = `sectionIndex` cells, whatever cell of the bar the section happens to begin
            // on. `syncopated` and `sparse` read `position`, not `bar`, so their quarter alignment is
            // untouched; `dynamic`'s jitter and `flowing`'s flips only re-derive a different (still
            // reproducible) draw stream.
            let cellOfStart = ((secStart % cells) + cells) % cells
            let rotation = cellOfStart + sectionIndex
            for step in secStart..<secEndLocal {
                let cell = ((step % cells) + cells) % cells
                guard let beat = RoleRhythm.hit(bar: rotation, cell: cell, cellsPerBar: cells,
                                                params: params, seed: rhythmSeed) else { continue }
                rhythmHits[step] = beat
                hitStarts.append(step)
            }
            // THE FOUNDATION IS NOT NEGOTIABLE. This function's contract — stated in its own doc
            // and relied on by the sub — is that the section downbeat IS the chord root. Some
            // characters would drop it: `syncopated` skips every on-beat below density 0.85 by
            // design, so at the 0.25/0.5 densities above its bar would start on air and the low end
            // would lose its grounding. Prepending costs one note and keeps the walk's degree logic
            // (`j == 0` ⇒ root) intact.
            if rhythmHits[secStart] == nil {
                hitStarts.insert(secStart, at: 0)
                // …AND IT PLAYS IN CHARACTER. Probing at density 1 asks the character what it WOULD
                // play on this cell: `density` decides only `fires`, never the level, the length or
                // the push, so the Hit that comes back is exactly the one it would have produced had
                // the cell been selected. Without this the prepended note fell through to the
                // genre's own length and level, which on `sparse` — whose squared density fires
                // roughly ONE cell of a 16-step bar — left whole sections indistinguishable from no
                // override at all. (Only where the section starts ON a quarter, i.e. progressions of
                // 2 or 4 chords; a 3-chord genre starts sections at 5 and 10, `sparse` declines an
                // off-quarter cell whatever the density, and those two sections are unchanged by
                // this probe. Stated exactly, because "byte-identical on every section but the
                // first" was the earlier wording and it is not true of the take the tests use.)
                // The probe consumes no shared RNG: `hit` derives its own stream from `rhythmSeed`.
                var probe = params
                probe.density = 1
                if let foundation = RoleRhythm.hit(bar: rotation, cell: cellOfStart,
                                                   cellsPerBar: cells, params: probe,
                                                   seed: rhythmSeed) {
                    rhythmHits[secStart] = foundation
                }
                // The probe can legitimately come back nil, and every case is the character being
                // itself rather than a hole: `sparse` refuses any cell that is not a quarter whatever
                // the density, and `flowing`'s evolve can flip a cell out even at density 1. Then the
                // foundation keeps the genre's own shape — the right fallback, and the reason the
                // loop below still needs its non-rhythm branch.
                // ⚠️ ONE CORNER where the probe is not literally "what it would have played":
                // `flowing` at a cell the real density did NOT select but density 1 does, where the
                // flip then inverts the probe's answer — so the probe declines while a real call
                // would have fired. Harmless by construction: that is exactly the case in which the
                // cell already fired and no prepend happened.
                // ⚠️ AND ONE TRADE-OFF worth recording rather than discovering: on `syncopated` the
                // probe hands the foundation that character's ON-BEAT DUCK (accent strength 0.3),
                // so the grounding note lands ~1.5 dB UNDER the off-beat notes it grounds. That is
                // the inversion which IS `syncopated`, but it is the opposite of the reason the
                // prepend exists, and only a device listen can say whether the low end still reads
                // as grounded.
            }
        } else {
            var s = secStart
            while s < secEndLocal { hitStarts.append(s); s += gap }
        }
        for (j, start) in hitStarts.enumerated() {
            // Length: to the next hit (or the section end), scaled by the character's gate — the
            // same meaning gate has on the arp, a fraction of the space this note actually has.
            // At least one step, so a note is never a zero-length click (the #205/#176 law).
            let room = (j + 1 < hitStarts.count ? hitStarts[j + 1] : secEndLocal) - start
            let noteLen: Int
            if let beat = rhythmHits[start] {
                noteLen = max(1, min(room, Int((Float(room) * beat.gateFraction).rounded())))
            } else {
                // `room` and not `secEndLocal - start`. On the nil path the two are the same number
                // (the grid is even, so every hit but the last has exactly `gap` of room) — but a
                // prepended foundation note whose character-probe came back silent has a `room` of
                // ONE step, and the old form handed it a whole `gap` and overlapped the hit that
                // followed it. Byte-identical where the Golden law applies, correct where it did not.
                noteLen = max(1, min(room, gap))
            }
            let isDown = (j == 0)
            let isLast = (j == hitStarts.count - 1)
            let degree: Int
            let alteration: Int
            if isDown {
                degree = rootDegree                                  // foundation on the downbeat
                alteration = alt(0)
            } else if isLast, nextRoot != rootDegree, nextRoot > 0 {
                degree = nextRoot - 1                                // walk a step up into the next root
                alteration = 0                                       // diatonic passing tone
            } else {
                degree = (j % 2 == 1) ? rootDegree + 4 : rootDegree  // fifth / root alternation
                alteration = (j % 2 == 1) ? alt(4) : alt(0)
            }
            // The character shapes the CONTOUR, the composer keeps the LEVEL. `RoleRhythm.Hit`
            // velocities are absolute values around `RoleRhythm.neutralVelocity`, so dividing by
            // that turns the accent pattern into a multiplier and the section's own `velocity` —
            // which carries the genre's mix balance and the body's energy — still sets how loud the
            // bass sits. Using the Hit's absolute value instead would have thrown the composer's
            // level away and made every character equally loud.
            // The divisor is READ from `RoleRhythm` and not written as `0.72` here: it is a term of
            // that type's private velocity formula, and a copy of it in this file could not be
            // reached by a re-tune there — raising the base level would silently have made every
            // bassline quieter, with no diff in this file to explain it.
            var vel = isDown ? velocity : velocity * 0.82
            if let beat = rhythmHits[start] {
                vel = clamp01(velocity * (beat.velocity / RoleRhythm.neutralVelocity))
            }
            notes.append(Note(id: nextUUID(&rng),
                              pitch: key.degree(degree, octave: octave) + alteration,
                              startStep: start, lengthSteps: noteLen,
                              velocity: hVel(vel, &rng), role: .bass))
        }
    }

    /// Heartbeat-oriented rhythmic onsets for ONE held chord section (founder
    /// 2026-07-11: "Kompositionen müssen nicht statisch im Takt sein … interessante
    /// am Herzschlag orientierte Rhythmen, punktierte und Synkopen"). This resolves
    /// the tension with the 2026-07-09 "Flächen still" doctrine as **calm = still,
    /// active = alive** (the founder's own "je nach Biofeedback individuell"): the
    /// 2026-07-09 rejection was about the exposed harsh wave-LEAD timbre, not about
    /// movement — so movement returns in the PAD timbre, never a naked lead.
    ///
    /// BIO-SCALED: below the energy threshold it returns a SINGLE onset spanning the
    /// whole section — bit-identical to the old held Fläche, so the calm default the
    /// founder liked is fully preserved. As body energy rises the section breaks into
    /// a dotted (long-short) then tresillo (3-3-2, the lub-dub grouping) pattern of
    /// shorter re-articulations of the SAME chord. The step grid is the tempo grid,
    /// which is already heart-rate-derived upstream, so the onsets land on a
    /// heartbeat-referenced pulse. Deterministic (no RNG → the rhythm tracks the body,
    /// it doesn't jitter every re-seed) and always inside [secStart, secStart+secLen)
    /// so the loop stays bar-tight. Pure → unit-testable.
    /// The shared arousal gate: a held section only breaks into rhythmic life once the
    /// body is genuinely activated (`energy` = the composer's `busy` signal ≥ 0.5) AND
    /// the section is long enough to carry a pulse (≥ a quarter, 4 steps). BOTH the pad's
    /// heartbeat re-articulation (`heartbeatOnsets`) and trap's quarter-note 808 pedal
    /// (`appendBass`) read this ONE definition so "aroused enough to move" is identical
    /// across the low end and the pad. Pure → unit-tested.
    /// - Parameter liveliness: the mood's Liveliness knob (#419). Moves the arousal bar by
    ///   `stillnessThresholdSpan`; 0.5 — `MoodProfile`'s own default — is exactly the shipped
    ///   0.5 gate, in Float, not approximately. Defaulted ONLY so the pure-core tests that
    ///   predate the knob keep reading as "at the neutral setting"; both production callers pass
    ///   `mood.liveliness` explicitly and `LivelinessMovesTheStillnessGateTests` scans for that.
    ///   The default is the one risk here — a future third caller would silently get neutral —
    ///   which is what that scan exists to catch.
    static func heartbeatActive(energy: Float, secLen: Int, liveliness: Float = 0.5) -> Bool {
        secLen >= 4 && energy >= Self.densityThreshold(base: 0.5, liveliness: liveliness,
                                                       span: Self.stillnessThresholdSpan)
    }

    static func heartbeatOnsets(secStart: Int, secLen: Int,
                                energy: Float, syncopation: Float,
                                liveliness: Float = 0.5) -> [(start: Int, len: Int)] {
        // `energy` is the composer's own `busy` activity signal (0…~0.85). Below the
        // arousal gate the body is at rest or only neutrally engaged → ONE held onset (the
        // still Fläche, unchanged) so typical resting/meditative states keep the stillness
        // the founder liked. Rhythm only emerges once the body is genuinely activated.
        guard heartbeatActive(energy: energy, secLen: secLen, liveliness: liveliness) else {
            return [(secStart, secLen)]
        }
        // Syncopation nudges the body toward the more off-beat (tresillo) feel sooner.
        let e = clamp01(energy + clamp01(syncopation) * 0.15)
        // #419: the same knob that moved the gate above moves the two steps of the ladder, by the
        // same `stillnessThresholdSpan`, so "livelier" means ONE thing on this path — the movement
        // arrives sooner AND grows sooner — rather than a gate and a ladder that disagree.
        // Direction is the shared one: lively LOWERS the bar. At 0.5 both are the shipped literals.
        let dotted = Self.densityThreshold(base: 0.68, liveliness: liveliness,
                                           span: Self.stillnessThresholdSpan)
        let tresillo = Self.densityThreshold(base: 0.82, liveliness: liveliness,
                                             span: Self.stillnessThresholdSpan)
        let strides: [Int]
        if e < dotted {
            strides = [6, 4]              // dotted-quarter + quarter — a gentle dotted lilt
        } else if e < tresillo {
            strides = [3, 3, 2]           // tresillo — the classic heartbeat-like syncopation
        } else {
            strides = [3, 3, 2, 2, 3, 3]  // busier tresillo variant for a fully aroused body
        }
        var onsets: [(start: Int, len: Int)] = []
        let secEnd = secStart + secLen
        var s = secStart
        var i = 0
        while s < secEnd {
            let stride = strides[i % strides.count]
            onsets.append((s, Swift.min(stride, secEnd - s)))
            s += stride
            i += 1
        }
        // Deliberately NOT the displaced chop `chordOnsets` falls back to: the `.sustained`
        // genres are the calm-is-still Fläche, so a section with no pulse SHOULD hold.
        return onsets.isEmpty ? [(secStart, secLen)] : onsets
    }

    /// Genre-aware chord articulation for ONE held chord section — the audible rhythmic
    /// fingerprint per genre (2026-07-22: the 13 `sustained:true` genres all ran through
    /// ONE genre-blind heartbeat pattern, so going through the genres "everything sounded
    /// the same"; drums are muted and auto-leads off, so rhythm has to live on the chords).
    /// `.sustained` (meditative/ambient/classical/doom/dub/trap) delegates to
    /// `heartbeatOnsets` → BYTE-IDENTICAL calm-is-still Fläche, zero regression. The
    /// rhythmic articulations place SHORT (8th-length) chord chops on the genre's
    /// characteristic grid, ALWAYS present so the genre is recognisable even at rest
    /// ("erst individuell"), with the body's `energy` filling in busier subdivisions.
    /// Absolute-step phase → the pattern is bar-aligned regardless of section boundaries;
    /// hits are ≥ 2 steps apart so the 2-step chops never overlap. Deterministic (no RNG
    /// in placement; velocity uses the existing humaniser) → pure, unit-tested.
    /// - Parameter liveliness: the mood's Liveliness knob (#419). Reaches ONLY the `.sustained`
    ///   delegation below — the skank/stab/comp grids keep their own literals, deliberately: those
    ///   genres are not the ones the knob failed to reach (their movement runs through the melodic
    ///   `arpStep`/`pulseGap` decisions #418 already wired), and their grid IS the genre's
    ///   identity. All three production call sites still pass it, because passing the mood's own
    ///   value into a function that takes it is simply correct, and a site that passed it next to
    ///   a site that did not would be the more confusing arrangement.
    static func chordOnsets(secStart: Int, secLen: Int, energy: Float, syncopation: Float,
                            articulation: MusicStyle.ChordArticulation,
                            liveliness: Float = 0.5) -> [(start: Int, len: Int)] {
        guard secLen > 0 else { return [(secStart, Swift.max(0, secLen))] }
        if articulation == .sustained {
            return heartbeatOnsets(secStart: secStart, secLen: secLen,
                                   energy: energy, syncopation: syncopation,
                                   liveliness: liveliness)
        }
        // Syncopation nudges the busier subdivisions in a touch sooner (same feel knob as
        // heartbeatOnsets), so an edgy body fills the pattern earlier.
        let e = clamp01(energy + clamp01(syncopation) * 0.15)
        let secEnd = secStart + secLen
        var onsets: [(start: Int, len: Int)] = []
        for step in secStart..<secEnd {
            let phase = ((step % 16) + 16) % 16   // bar-aligned 16-step phase
            let hit: Bool
            switch articulation {
            case .skank:
                // Reggae/ska skank: chord chops on the OFFBEAT 8ths (2,6,10,14). Pure and
                // always on — the offbeat IS the genre, at rest or aroused.
                hit = (phase % 4 == 2)
            case .stab:
                // Disco/house stab: chord ON the beats (0,4,8,12). Body up → also the
                // offbeats → a driving 8th four-on-the-floor pulse.
                hit = (phase % 4 == 0) || (e >= 0.6 && phase % 2 == 0)
            case .comp:
                // Jazz/rock comp: the backbeat 2 & 4 (steps 4,12). Body up → add the
                // syncopated offbeat "and" for busier comping.
                hit = (phase % 8 == 4) || (e >= 0.62 && phase % 4 == 2)
            case .sustained:
                hit = false   // handled above
            }
            if hit { onsets.append((step, Swift.min(2, secEnd - step))) }
        }
        // A section that catches NO grid hit still has to SOUND — but it must not sound like
        // the `.sustained` branch. It used to return one onset spanning the whole section, i.e.
        // a held chord, which is the "everything sounds the same" bug this function exists to
        // fix. `.comp` hits absolute steps 4 and 12 only, and `composeHarmonic` cuts the bar
        // into (16 / prog.count)-step sections, so:
        //   jazz, rock (prog 4 → four 4-step sections): 0..<4 and 8..<12 caught nothing → pad
        //     starts {0,4,8,12}, BYTE-IDENTICAL to held classical. The worst case.
        //   punk, rocknroll, heavyMetal (prog 3 → 0..<5, 5..<10, 10..<16): the middle section
        //     caught nothing → one 5-step hold out of three.
        //   oriental (prog 2 → 0..<8, 8..<16): both sections contain a hit — never degenerate.
        // `.stab` cannot reach this branch at all (its grid is every 4th step, and the widest
        // section any shipping genre produces is 5). `.skank` CAN, but only once the user turns
        // the Weird knob up: `weird > 0` splices a chord in, and rocksteady at prog 5 gets
        // 3-step sections of which 3..<6 misses the 2/6/10/14 grid.
        //
        // So the fallback is a SHORT chop, displaced off the section downbeat and snapped to
        // the 8th grid — the same grid every real hit above sits on, so the fallback speaks the
        // function's own rhythmic vocabulary instead of inventing a 16th nobody else plays.
        // Off the downbeat because a section downbeat is `.stab`'s grid; snapped to the 8th
        // because sections are not always even (prog 3 gives odd `secStart`s).
        // For jazz/rock that puts the two missed sections on absolute 2 and 10 — the "and" of
        // beats 1 and 3, tied into the real chops on 4 and 12: a comping anticipation.
        // On the skank-with-Weird path the snapped step can land ON a beat, which is not
        // skank's own offbeat grid. Accepted rather than special-cased: it is one short chop in
        // a variant the user dialled in, and still more articulate than the hold it replaces.
        // Exactly ONE onset either way, so the RNG draw count downstream is unchanged.
        if onsets.isEmpty {
            var start = secStart + 1
            while start < secEnd && !start.isMultiple(of: 2) { start += 1 }
            // A 1- or 2-step section has no 8th-aligned room to move into; it holds, as before.
            if start >= secEnd { start = secStart }
            return [(start, Swift.min(2, secEnd - start))]
        }
        return onsets
    }

    /// #253 A4 — one chord section's onsets on a chosen `RoleRhythm.Character` instead of the
    /// genre's own articulation grid. Returns `(start, len, level)` where `level` is a MULTIPLIER on
    /// whatever velocity the caller had planned, never an absolute level: the composer keeps the
    /// genre's mix balance and the body's energy, the character only shapes the contour.
    ///
    /// `chordOnsets` is left completely untouched — it is the well-tested definition of what each
    /// genre plays, and this function is the alternative a player opts into, not a rewrite of it.
    /// The two share the caller's section boundaries and nothing else.
    ///
    /// - Parameters:
    ///   - density: fraction of a 16-cell bar that should sound. The CALLER derives it by counting
    ///     what `chordOnsets` returned for this same section, so an even-spread character keeps the
    ///     genre's rate — the reason this is a parameter and not computed here.
    ///   - sectionIndex: the chord section's index, used ONLY as `hypnotic`'s rotation. It is folded
    ///     against the section's own start cell for the reason `appendBass` states at length: at 16
    ///     cells only `bar % 4` matters, so a raw index cancels against a 5-step section's offset and
    ///     the rotation silently disappears.
    ///
    /// Pure and deterministic from `(seed, sectionIndex, cells)`. For any `secLen > 0` it returns at
    /// least one onset, starting ON `secStart` and never zero-length — a section must always SOUND,
    /// and the chord's downbeat is the harmonic foundation exactly as it is for the bass. For
    /// `secLen <= 0` it returns an EMPTY list (the guard below), which is what the caller's
    /// `if !padBeats.isEmpty` routes on. The first version of this line said "never returns an empty
    /// list", contradicted three lines later by its own guard and by the test that asserts it — and a
    /// reader who believed it would read that caller-side gate as dead code.
    static func roleRhythmOnsets(secStart: Int, secLen: Int, sectionIndex: Int,
                                 character: RoleRhythm.Character, density: Float,
                                 gate: Float, accent: Float, evolve: Float,
                                 seed: UInt64) -> [(start: Int, len: Int, level: Float)] {
        guard secLen > 0 else { return [] }
        let cells = 16
        let secEnd = secStart + secLen
        // ⭐ #581 — THE THREE DIALS NOW HAVE A UI, so they arrive as arguments instead of as
        // literals. The old comment here read *"The three dials no role UI exposes are written
        // out rather than inherited from `RoleRhythm.Params()`"*, and that sentence is what the
        // founder was reading the absence of: *"eine Sektion mit slidern der aus den Pad Sounds
        // rhythmische chords macht … Fehlt noch"* (2026-08-13).
        //
        // ⚠️ NO DEFAULT VALUES ON THESE THREE PARAMETERS, DELIBERATELY (#431/#440/#443). A
        // defaulted argument that no call site writes appears in no diff — the forgetful caller
        // compiles, the section silently does nothing, and the guard over the view stays green
        // because the view is fine. Required arguments make the compiler the reviewer.
        //
        // The reason the OLD comment gave still holds for the half it was about: these values
        // must not be inherited from `RoleRhythm.Params()`, because those defaults belong to the
        // ARP's feel and a re-tune there must not silently re-voice every pad. The pad's own
        // defaults now live in `StudioDefaultKeys.padGate/padAccent/padEvolve`, set to exactly
        // the literals this line used to carry, so nothing that existed before sounds different.
        let params = RoleRhythm.Params(character: character, density: clamp01(density),
                                       gate: gate, accent: accent, evolve: evolve)
        let cellOfStart = ((secStart % cells) + cells) % cells
        let rotation = cellOfStart + sectionIndex
        var byStart: [Int: RoleRhythm.Hit] = [:]
        var starts: [Int] = []
        for step in secStart..<secEnd {
            let cell = ((step % cells) + cells) % cells
            guard let beat = RoleRhythm.hit(bar: rotation, cell: cell, cellsPerBar: cells,
                                            params: params, seed: seed) else { continue }
            byStart[step] = beat
            starts.append(step)
        }
        // The section downbeat always sounds, and it sounds IN CHARACTER: probing at density 1 asks
        // the character what it would have played on that cell (density decides only WHICH cells
        // fire, never level/length/push). `sparse` off a quarter and `flowing` after an evolve flip
        // can still decline, and then the caller's own planned shape stands — level 1, full room.
        if byStart[secStart] == nil {
            starts.insert(secStart, at: 0)
            var probe = params
            probe.density = 1
            if let foundation = RoleRhythm.hit(bar: rotation, cell: cellOfStart, cellsPerBar: cells,
                                               params: probe, seed: seed) {
                byStart[secStart] = foundation
            }
        }
        var onsets: [(start: Int, len: Int, level: Float)] = []
        for (j, start) in starts.enumerated() {
            let room = (j + 1 < starts.count ? starts[j + 1] : secEnd) - start
            guard room > 0 else { continue }
            let beat = byStart[start]
            // Length measured against the room this onset actually has, so two chords can never
            // overlap into a mud smear — and `min(room, …)` is what makes that structural rather
            // than a hope (the bass shipped the `gap`-based version and it overlapped).
            //
            // ⛔ A SOLE ONSET FILLS ITS SECTION — no gate. A gate exists to leave AIR BETWEEN notes;
            // with nothing following it in the section, that air is not a rhythm, it is a hole. This
            // is not a nicety: `heartbeatOnsets` returns ONE onset spanning the whole section when
            // the body is calm ("calm = still", the Fläche the founder explicitly liked), and the
            // meditative drones collapse to a SINGLE 16-step section — so gating that one onset gave
            // `driving` a 6-step chord followed by ten steps of silence in a drone genre. The
            // character still shapes its LEVEL there, and shapes length again the moment the section
            // has more than one onset.
            let sole = starts.count == 1
            let len = sole
                ? room
                : max(1, min(room, Int((Float(room) * (beat?.gateFraction ?? 1)).rounded())))
            // A ratio around `neutralVelocity`, NOT clamped here: `dynamic`'s accent legitimately
            // goes above 1 (0.951 / 0.72 ≈ 1.32) and the caller clamps once it has applied its own
            // level. Clamping twice would flatten every accent that rises.
            let level = (beat?.velocity ?? RoleRhythm.neutralVelocity) / RoleRhythm.neutralVelocity
            onsets.append((start, len, level))
        }
        return onsets
    }

    /// Fold a lead pitch that has climbed into the piercing top octaves DOWN by whole
    /// octaves until it sits at/under `ceiling` (keeps the pitch class → always in key).
    /// Tames the "piepsig künstlich" high synth leads (founder 2026-07-11: "unangenehm
    /// bis piepsig künstlich") without a register plateau. Pure → unit-testable.
    static func tameLeadPitch(_ pitch: Int, ceiling: Int = 84) -> Int {
        var p = pitch
        while p > ceiling { p -= 12 }
        return Swift.max(0, p)
    }

    private static func composeHarmonic(key: MusicalKey, profile: HarmonicProfile,
                                        calm: Float, busy: Float,
                                        breathPhase: Float, breathDepth: Float,
                                        mood: MoodProfile, progressionPhase: Int,
                                        dynamicTilt: Double = 0,
                                        densityScale: Float = 1,
                                        quarterAnchor: Bool = false,
                                        articulation: MusicStyle.ChordArticulation = .sustained,
                                        voiceLead: VoiceLeadControl? = nil,
                                        suggest: ChordSuggestControl? = nil,
                                        bassRhythm: RoleRhythm.Character? = nil,
                                        padRhythm: RoleRhythm.Character? = nil,
                                        // #983 — the genre's own bass figure (`MusicStyle.bassGrammar`).
                                        // NO DEFAULT, for the same reason the pad dials below have
                                        // none (#431/#440/#443): a defaulted `nil` that no call site
                                        // writes would let a future caller silently lose every
                                        // house/tech/minimal bassline, with nothing in the diff.
                                        bassGrammar: BassGrammar?,
                                        // #581 — the pad's chord shape, threaded through to
                                        // `roleRhythmOnsets`. NO DEFAULTS, same reason as there
                                        // (#431/#440/#443): both call sites below must be forced
                                        // to pass the player's values, because a defaulted
                                        // argument nobody writes is invisible in a diff and the
                                        // section on screen would silently do nothing.
                                        padGate: Float, padAccent: Float, padEvolve: Float,
                                        rng: inout SeededRNG,
                                        structureRNG: inout SeededRNG) -> [Note] {
        var notes: [Note] = []
        let baseProg = profile.progression.isEmpty ? [0] : profile.progression
        var prog: [Int]
        // H2 (suggest != nil only): per-section semitone alterations of the
        // suggested chords, aligned with `prog`. A diatonic suggestion carries
        // [0,0,0]; a borrowing alters 1–2 triad tones. nil (legacy: always) ⇒
        // every alteration lookup below reads 0 — byte-identical arithmetic.
        var sectionAlterations: [[Int]]?
        if let sc = suggest {
            // H2 CHORD JOURNEY (PLAN_HARMONY_CORE.md): ChordSuggest replaces the
            // legacy progression choice. Section layout is preserved — the
            // sustained many-chord Flächen still hold ONE chord per bar, every
            // other profile keeps its section count — but WHICH chords come from
            // the function-ranked, coherence-selected journey. progressionPhase
            // stays the cursor: it walks an 8-chord arc (chordJourneyLoopLength)
            // instead of the profile's short loop. The journey runs on its own
            // salted skeleton stream — structureRNG is NOT consumed here, so the
            // legacy branches below stay untouched when suggest is nil.
            let n = (profile.sustained && baseProg.count > 2) ? 1 : Swift.max(1, baseProg.count)
            let loop = Self.chordJourneyLoopLength
            // Nominal ranking register: the pad's home octave ± the same whole-
            // octave window the voicing logic can reach. Reference only (the
            // smoothness term); actual voicing happens per section below.
            let anchor = key.degree(0, octave: profile.padOctave)
            let lo = Swift.max(0, Swift.min(115, anchor - 12))
            let hi = Swift.min(127, Swift.max(lo + 12, anchor + 16))
            let full = ChordSuggest.journey(length: loop + n, in: key,
                                            coherence: sc.coherence,
                                            register: lo...hi, seed: sc.seed)
            if full.count == loop + n {
                let start = ((progressionPhase % loop) + loop) % loop
                let chords = Array(full[start..<(start + n)])
                prog = chords.map(\.rootDegree)
                sectionAlterations = chords.map(\.alterations)
                // GENRE-IDENTITY CROSSFADE (founder 2026-07-22: "bei den Genres kommt
                // erst eine individuelle Variation und dann klingt plötzlich alles
                // gleich"). The coherence-selected journey is the AROUSED explorer;
                // as the body settles the harmony must converge to a CALM version of
                // THIS genre, not a generic functional cycle (which is exactly what a
                // high-coherence journey picks — the same expected T→S→D→T for every
                // genre in the same key/scale). Lock the first `k` of the `n` section
                // roots to the genre's OWN authored progression (phase-rotated,
                // diatonic), where `k` grows with coherence off a FLOOR: calm
                // (coherence→1) ⇒ k→n ⇒ the root motion IS the genre signature (Disco
                // stays Disco, Doom stays Doom); aroused (coherence→0) ⇒ k→ the floor
                // (≥1 for EVERY n≥1 since 2026-07-29 — it used to read "≥1 for n≥2",
                // which was an accurate description of a hole rather than a guarantee:
                // the one-section genres, Doom among them, got k=0 and stopped staying
                // Doom) ⇒ at least the genre's first root stays
                // anchored while the rest of the journey explores seeded/free. Pure
                // function of coherence + two
                // in-key degree arrays — NO rng/structureRNG draw, so every
                // downstream draw keeps its order (determinism law). Chord QUALITY
                // (profile.chordTones, e.g. jazz 7ths) is untouched below; only ROOT
                // MOTION is genre-anchored. Every substituted degree is a diatonic
                // scale degree ([0,0,0] alterations) → always resolves in key.
                // Anchor the genre's harmony as the body SETTLES, not only when fully
                // calm (founder 2026-07-22: "ich gehe durch die Genres und nach kurzer
                // Zeit klingt alles wie classic" — while browsing at MODERATE coherence
                // the shared journey still dominated, so genres converged). The law —
                // floor 0.34, full anchor by coherence 0.7, and the `max(1, …)` that
                // makes it hold for a ONE-section take too — lives in
                // `genreAnchorCount`, which is pinned in the blocking test bundle
                // (`Tests/CISmoke/GenreAnchorFloorTests.swift`). It was inline here and
                // silently returned 0 for n == 1, i.e. for the default genre.
                let k = Self.genreAnchorCount(sections: n, coherence: sc.coherence)
                if k > 0 {
                    let rotBase = ((progressionPhase % baseProg.count) + baseProg.count) % baseProg.count
                    for i in 0..<k {
                        prog[i] = baseProg[(rotBase + i) % baseProg.count]
                        sectionAlterations?[i] = [0, 0, 0]
                    }
                }
            } else {
                // Unreachable in practice (a non-empty scale always fills the
                // journey); fail safe to the profile's plain progression.
                prog = baseProg
                sectionAlterations = nil
            }
        } else if profile.sustained && baseProg.count > 2 {
            // MEDITATIVE FLÄCHE JOURNEY (founder 2026-07-11: "bleibt auf Flächen liegen
            // … soll weitergehen und sich mit dem Herzschlag weiterentwickeln"). The two
            // frozen single-chord drones (Self-Observation, Deep Ambient) now carry a
            // gentle multi-chord progression, and each BAR holds exactly ONE chord of it
            // — per-bar stillness (the meditative quality) is fully preserved — while
            // WHICH chord = `progression[phase]`. The Studio advances the phase per bar
            // (a multi-bar loop journeys through the chords) AND per evolve (the
            // bio-cadenced re-seed moves it onward over time), so the pad TRAVELS instead
            // of holding one chord forever. Deterministic + always in key (one degree →
            // MusicalKey.degree). The 2-chord Flächen (dub/trap/vaporwave/sci-fi) keep
            // their existing within-bar move below (they already breathe — "schon sehr
            // gut") and only pick up the phase rotation for extra evolve-to-evolve life.
            let i = ((progressionPhase % baseProg.count) + baseProg.count) % baseProg.count
            prog = [baseProg[i]]
        } else {
            // Seed-vary the harmony so a re-seed never replays the identical chord move
            // ("immer derselbe Tonwechsel"). The genre profile sets the vocabulary; the
            // seed rotates the progression (and `progressionPhase` advances that rotation
            // over evolves — inert at phase 0, so existing seeds are untouched) and, for
            // adventurous moods, borrows an in-key secondary chord (ii/V/vi) and adds a
            // turnaround so the loop resolves. Every degree still resolves through
            // MusicalKey.degree → always in key. The harmonic skeleton is drawn from
            // structureRNG so it stays STABLE across evolving takes — the "same song?" cue.
            prog = baseProg
            if prog.count > 1 {
                let rot = ((Int(structureRNG.next() % UInt64(prog.count)) + progressionPhase)
                           % prog.count + prog.count) % prog.count
                prog = Array((prog + prog)[rot..<rot + prog.count])
            }
            // Adventurous (weird) moods splice a borrowed secondary chord before the last
            // chord, so the phrase gets a fresh harmonic colour it didn't have before.
            if structureRNG.unit() < clamp01(mood.weird) * 0.6 {
                let candidates = [4, 5, 1].filter { !prog.contains($0) }   // V, vi, ii
                if !candidates.isEmpty {
                    let extra = candidates[Int(structureRNG.next() % UInt64(candidates.count))]
                    prog.insert(extra, at: max(0, prog.count - 1))
                }
            }
            // Turnaround cadence: on multi-chord takes, end on the dominant (V) some of
            // the time so the loop pulls back to the tonic at the wrap (V→i), instead of
            // always closing on the same chord. Seeded + tension-scaled so it varies.
            if prog.count > 1, prog.last != 4, structureRNG.unit() < 0.35 + 0.4 * clamp01(mood.tension) {
                prog[prog.count - 1] = 4
            }
        }
        // Guard chord tones symmetrically with the progression (a public
        // HarmonicProfile could be built with empty tones → div-by-zero in the arp).
        // Romance adds the 7th for lush chords; darkness drops the whole voicing an
        // octave. (Mood blends on top of the genre profile.)
        var tones = profile.chordTones.isEmpty ? [0, 2, 4] : profile.chordTones
        if mood.romance > 0.5, !tones.contains(6) { tones.append(6) }
        let octShift = mood.darkness > 0.6 ? -1 : 0
        let sectionLen = max(1, stepCount / prog.count)
        // ⭐ #403 SLICE 3b — THE PERSON SETS THE TAKE'S LOW-END WEIGHT, NOT ITS LEVEL.
        //
        // ⛔ SLICE 3 TILTED `padVelocity` ITSELF, AND THE REASON GIVEN FOR TAKING IT BACK WAS
        // ITSELF PART WRONG — both halves are recorded here because the next session will
        // plan from this block.
        //
        // The inventory behind Slice 3 claimed the section velocity was "the ONE continuous
        // body-driven quantity in the live composer, everything else is a threshold". ⛔ That
        // superlative is false. Live continuous body reads it missed: `voiceLeadControl`
        // (`strictness` from coherence, `spread` from breathDepth — consumed inside
        // `VoiceLeader`'s cost function, and the app passes `voiceLeading: true`),
        // `chordSuggestControl.coherence` (`suggestJourney: true`), and `effectiveTension`,
        // which is read as a continuous probability in this very function. The velocity may
        // still have been the best pick; it was not the only one, and the doc asserted the
        // stronger claim in two files. What the inventory genuinely got right is the DORMANT
        // half: `velBase` in the lead block and the three genre melody builders are continuous
        // too and have no callers — which is why "LIVE" is load-bearing and not pedantic.
        //
        // What the inventory did not look at is what happens after the composer:
        //
        //   1. It is overwhelmingly LEVEL. `spawnVoice` writes three velocity-derived values
        //      (`amplitude`, `velocityGain`, `noteVelocity`), and the first two are pure
        //      amplitude. ⛔ THE FIRST VERSION OF THIS LINE SAID "exactly ONE thing … no
        //      velocity→filter or velocity→spectrum path", AND THAT IS FALSE: `noteVelocity`
        //      feeds `brightBoost` (`EchoelDDSP`, the SVF cutoff term), and `filterEnvAmount`
        //      defaults to 1 and has NO setter anywhere in `Sources/` — so velocity moves the
        //      per-note brightness on every note of every patch. Over this slice's range that
        //      is ~5 % of cutoff, decaying in ~100 ms. Small, but not zero, and a servo cannot
        //      remove it. Two more paths (onset chiff, attack scale) are real and inert here,
        //      gated on `percussiveness`, which is 0 on a slow-attack pad.
        //   2. The loudness servo is ON by default (`StudioDefaultKeys.loudnessTarget` =
        //      `.streaming`, −14 LUFS) and its input meter is the PRE-chain tap, upstream of
        //      its own `gainNode` — open-loop feed-forward, fixed point `target − Lᵢₙ`.
        //      ⛔ AND THE FIRST VERSION SAID IT REMOVES A SOURCE OFFSET "ENTIRELY, NOT
        //      PARTLY", WHICH IS ALSO FALSE — `steadyGainDB` carries `deadZoneDB = 0.4` and
        //      HOLDS inside it. The arithmetic I never did: Slice 3's per-performer offset
        //      under the same `v^0.5` law was +0.32/−0.42 dB at coherence 0.5 (span 0.73 dB),
        //      so one whole side of it sat INSIDE the hold band. The honest verdict is not
        //      "erased" and not "survives" — it is INDETERMINATE, which is a worse property
        //      for a fingerprint than either.
        //   3. On the shipped default genre (`.selfObservation`, `leadDensity 0`) every
        //      sounding note derives from `padVelocity`, so the tilt was essentially all
        //      common-mode — the one class of signal that stage is built to move. (Not
        //      exactly 100 %: an ADDITIVE velocity delta is not a constant dB offset across
        //      notes, so ~0.08 dB of it was differential.)
        //
        // ⭐ SO THE SURVIVING ARGUMENT IS #2 AND #3 TOGETHER, AND IT IS ABOUT RELIABILITY, NOT
        // ERASURE: a sub-dB common-mode LEVEL offset lands in the servo's hold band, where
        // whether it reaches the listener depends on what the rest of the mix happens to be
        // doing. A fingerprint may not be a coin flip. BALANCE has no such stage: a RATIO is
        // untouched by a gain servo, by the static master trim, and by `AutoMixChain`'s EQ
        // (linear, no crossover, no multiband). That is the whole reason for 3b.
        //
        // `padVelocity` is therefore back to its pre-#403 expression, bit-identical for every
        // performer. The fingerprint moves the bass's lift OVER the pad instead: the same
        // section, played by a body that habitually sits low or high on variability, carries
        // more or less bottom. A loudness servo cannot take that back, because it does not
        // change how loud the take is — only what it is made of.
        //
        // ⚠️ THE DIRECTION IS A CONVENTION, NOT A FINDING. Higher habitual HRV → lighter
        // bottom (pad-forward, airier); lower → heavier. Nothing measures which way a body
        // "should" sound; the convention is fixed here so it is at least consistent, and it is
        // the founder's to reverse.
        let padVelocity = clamp01(0.34 + 0.22 * breathDepth)
        let bassVelocity = clamp01(padVelocity + Self.bassLift(for: dynamicTilt))

        // Voice-leading state: the average MIDI pitch of the previous pad voicing.
        // Each chord is shifted by whole octaves to sit closest to it — pitch
        // classes never change (so it stays perfectly in-key), but the chords
        // stop leaping in parallel and instead move smoothly, like a real player.
        var prevPadCenter: Float? = nil
        // H1 (voiceLead != nil only): the previous pad voicing's actual pitches,
        // so VoiceLeader can hold common tones and move single voices instead of
        // shifting the whole block. Call-local like prevPadCenter — continuity
        // lives within ONE compose() (across its sections); cross-bar journey
        // continuity is a follow-up slice.
        var prevPadVoicing: [Int] = []

        for (idx, rootDegree) in prog.enumerated() {
            let secStart = idx * sectionLen
            let secEnd = (idx == prog.count - 1) ? stepCount : min(stepCount, secStart + sectionLen)
            guard secEnd > secStart else { continue }
            let len = secEnd - secStart

            // H2: this section's chord alterations ([] = diatonic — always so
            // on the legacy path, where every lookup then adds 0).
            let secAlts: [Int]
            if let alts = sectionAlterations, idx < alts.count {
                secAlts = alts[idx]
            } else {
                secAlts = []
            }

            // 1) Bass foundation — a MOVING bass line an octave below the pad, not a
            //    single held root. The downbeat grounds the chord; on takes with drive
            //    it steps through root/fifth and walks up into the next chord's root, so
            //    the low end reads like a played bass instead of a drone. Calm/spacious
            //    takes keep the one sustained root (see appendBass). role: .bass → sub
            //    follows it; all tones stay in key.
            let bassOct = max(0, profile.padOctave - 1 + octShift)
            let nextRoot = prog[(idx + 1) % prog.count]
            appendBass(into: &notes, key: key, rootDegree: rootDegree, nextRoot: nextRoot,
                       octave: bassOct, secStart: secStart, len: len,
                       busy: busy, calm: calm, velocity: bassVelocity,
                       sustained: profile.sustained, quarterAnchor: quarterAnchor,
                       alterations: secAlts, sectionIndex: idx,
                       rhythm: bassRhythm, grammar: bassGrammar,
                       liveliness: mood.liveliness, rng: &rng)

            // 2) Pad — the full chord (root/3rd/5th/7th as the profile defines),
            //    voice-led into the previous chord's register, then sustained for
            //    the section or gently arpeggiated.
            var basePitches: [Int] = []
            for tone in tones {
                basePitches.append(key.degree(rootDegree + tone, octave: profile.padOctave + octShift)
                                   + ChordSuggest.alteration(forToneOffset: tone,
                                                             degreesPerOctave: key.degreesPerOctave,
                                                             in: secAlts))
            }
            let voiced: [Int]
            if let vl = voiceLead, !basePitches.isEmpty {
                // H1: real voice-leading (VoiceLeader.resolve) — inversions and
                // held common tones instead of the whole-block octave shift.
                // Order note (deliberate): resolve returns ASCENDING pitches.
                // basePitches are ascending scale degrees too (a block shift
                // preserves that), so the `voiced[t % count]` arp/pulse iteration
                // convention is normally unchanged — only the chosen inversion
                // differs (which is the point). Sole corner: romance > 0.5 on a
                // power-chord profile appends the 7th AFTER the octave ([0,4,7,6]),
                // where the legacy arp runs that unsorted order; the voice-led
                // branch always arpeggiates low→high. Accepted for the new branch.
                if prevPadVoicing.isEmpty {
                    // First chord: exactly what the legacy path plays (shift 0) —
                    // keeps the genre's opening voicing AND the voice count
                    // (power-chord octave doublings included) for every section.
                    voiced = basePitches
                } else {
                    // Register = the SAME window the legacy shift path can reach:
                    // the chord's root position ± one whole octave ({−12,0,+12}).
                    let lo = Swift.max(0, (basePitches.min() ?? 0) - 12)
                    let hi = Swift.min(127, (basePitches.max() ?? 0) + 12)
                    // Per-chord skeleton seed, derived WITHOUT consuming either
                    // RNG stream (same golden-ratio mix as humanizeVelocity) so
                    // progression/lead structure stays identical to the OFF path.
                    let chordSeed = vl.seed &+ (UInt64(bitPattern: Int64(idx + 1)) &* 0x9E3779B97F4A7C15)
                    voiced = VoiceLeader.resolve(from: prevPadVoicing, to: basePitches,
                                                 register: lo...hi,
                                                 strictness: vl.strictness,
                                                 spread: vl.spread,
                                                 seed: chordSeed)
                }
                prevPadVoicing = voiced
            } else {
                var shift = 0
                if let center = prevPadCenter, !basePitches.isEmpty {
                    let avg = Float(basePitches.reduce(0, +)) / Float(basePitches.count)
                    var best = Float.greatestFiniteMagnitude
                    for cand in [-12, 0, 12] {
                        let d = abs((avg + Float(cand)) - center)
                        if d < best { best = d; shift = cand }
                    }
                }
                voiced = basePitches.map { $0 + shift }
                if !voiced.isEmpty {
                    prevPadCenter = Float(voiced.reduce(0, +)) / Float(voiced.count)
                }
            }

            // #253 A4: ONE chosen character replaces the pad's onset grid on every path below.
            //
            // Computed here rather than inside the four branches because all four are the same
            // question to a listener — WHEN does the chord re-articulate — and because the four
            // together are the most ear-tuned code in this file: a `nil` that reaches none of them
            // is a Golden law that holds by construction instead of by four separate reviews.
            //
            // THE RATE IS COUNTED, NOT GUESSED — and it is counted from the path this override is
            // about to REPLACE, which is not the same source on all four:
            //   · arpeggiated → the arp's own `arpStep` grid. Asking `chordOnsets` here would be
            //     asking the wrong question: an arp genre's articulation value describes a chord
            //     grid it never plays. The two answers diverge by up to 2× (a calm body coarsens
            //     `arpStep` to 4 → arp rate 1 per 4-step section, while `.stab` still reports 2);
            //     they happen to AGREE at the body state the tests use, which is exactly why the
            //     bundle does not pin this choice — see the note in `PadRhythmOverrideTests`. The
            //     first version of this comment claimed "~3×"; that number was invented, and it is
            //     the number a future session would use to judge whether this ternary still earns
            //     its keep.
            //   · everything else → `chordOnsets`, which IS the definition of what the genre plays
            //     there. Pure and RNG-free, so asking it costs nothing.
            // #418: the 0.6 is the SPARSE/DENSE line, and the Mood panel's Liveliness knob now
            // shifts it (see `densityThreshold`). It still chooses between 2 and 4 — the knob
            // biases which of the genre's own two steps you land on, it never adds a third.
            let arpStep = (busy > Self.densityThreshold(base: 0.6, liveliness: mood.liveliness) ? 2 : 4)
                * (densityScale < 0.8 ? 2 : 1)
            var padBeats: [(start: Int, len: Int, level: Float)] = []
            if let character = padRhythm, !voiced.isEmpty {
                // ONE seed per section, drawn once — the `flowing`/`dynamic` reproducibility rule
                // `appendBass` states. Inside the `if let`, so the nil path touches no RNG and every
                // later note in the take keeps its identity.
                let padSeed = rng.next()
                let genreRate = profile.arpeggiated
                    ? (len + arpStep - 1) / max(1, arpStep)          // ceil: the arp's own onsets
                    // #419: the SAME liveliness the pad below uses. This is a count of the pad's
                    // onsets feeding `roleRhythmOnsets`' density — omitting it would leave the
                    // estimate describing a pad that is not the one being written.
                    : Self.chordOnsets(secStart: secStart, secLen: len, energy: busy,
                                       syncopation: mood.syncopation,
                                       articulation: articulation,
                                       liveliness: mood.liveliness).count
                padBeats = Self.roleRhythmOnsets(
                    secStart: secStart, secLen: len, sectionIndex: idx, character: character,
                    density: Float(max(1, genreRate)) / Float(max(1, len)),
                    gate: padGate, accent: padAccent, evolve: padEvolve,
                    seed: padSeed)
            }
            if !padBeats.isEmpty {
                if profile.arpeggiated {
                    // An arpeggiated profile keeps its PITCH figure (`voiced[t % count]`, the
                    // cycling that makes it an arp) and only changes WHEN the notes land. Playing
                    // the whole chord block here instead would have turned every arp genre into a
                    // pad — a timbral rewrite hiding inside a rhythm control.
                    for (t, beat) in padBeats.enumerated() {
                        notes.append(Note(id: nextUUID(&rng),
                                          pitch: voiced[t % voiced.count],
                                          startStep: beat.start, lengthSteps: beat.len,
                                          velocity: hVel(clamp01(padVelocity * beat.level), &rng)))
                    }
                } else {
                    // Every non-arp path — the sustained heartbeat Fläche, the skank/stab/comp chop
                    // and the single held chord — becomes the same thing: the full voicing on the
                    // character's grid. `metricAccent` is deliberately NOT applied on top: it is the
                    // genre grid's own accent shape and would fight the character's contour, which
                    // is the one thing a player picked this row to hear.
                    for pitch in voiced {
                        for beat in padBeats {
                            notes.append(Note(id: nextUUID(&rng), pitch: pitch,
                                              startStep: beat.start, lengthSteps: beat.len,
                                              velocity: hVel(clamp01(padVelocity * beat.level), &rng)))
                        }
                    }
                }
            } else if profile.arpeggiated {
                // SOFT TRANCE (founder 2026-07-07: "Ton-Dichte runter … ich will
                // angenehmen weichen Trance-Sound"). Arps were 16ths when busy, 8ths
                // when calm — a machine-gun, unnatural top layer. Halved to 8ths /
                // quarter-notes so the arp breathes instead of rattling.
                // Coarsen the arp at fast tempo (densityScale < 0.8 ⇔ >109 BPM) so it
                // breathes in quarters instead of rattling in 8ths — the anti-hectic move.
                // `arpStep` is hoisted above the A4 block (it is also that block's rate source);
                // the value and this branch's behaviour are unchanged.
                var s = secStart
                var t = 0
                while s < secEnd {
                    let length = max(1, min(arpStep, secEnd - s))
                    notes.append(Note(id: nextUUID(&rng),
                                      pitch: voiced[t % voiced.count],
                                      startStep: s, lengthSteps: length, velocity: hVel(padVelocity, &rng)))
                    s += arpStep
                    t += 1
                }
            } else if profile.sustained {
                // GENRE-ARTICULATED CHORDS (2026-07-22 fix for "going through the genres,
                // everything sounds the same"): the audible pad chords now carry each genre's
                // rhythmic fingerprint via `chordOnsets(articulation:)`. `.sustained` genres
                // (meditative/ambient/classical/doom/dub/trap) delegate to the unchanged
                // heartbeat Fläche — founder 2026-07-11 "nicht statisch im Takt … am Herzschlag
                // orientierte Rhythmen, punktierte und Synkopen"; calm body → one held onset,
                // active body → the SAME chord voicing on a dotted/tresillo pulse. The rhythmic
                // genres (skank/stab/comp) instead chop the SAME chord voicing on their own
                // characteristic grid, always present so the genre is recognisable even at rest
                // (drums are muted, so this is where genre rhythm lives). Same pitches (in-key),
                // pad timbre (no lead), all inside the bar; `busy` fills busier subdivisions.
                let onsets = Self.chordOnsets(secStart: secStart, secLen: len,
                                              energy: busy, syncopation: mood.syncopation,
                                              articulation: articulation,
                                              liveliness: mood.liveliness)
                for pitch in voiced {
                    for onset in onsets {
                        notes.append(Note(id: nextUUID(&rng), pitch: pitch,
                                          startStep: onset.start, lengthSteps: onset.len,
                                          velocity: hVel(padVelocity, &rng)))
                    }
                }
            } else if articulation != .sustained {
                // GENRE-ARTICULATED CHORDS for the non-arp, non-drone genres — THIS is where
                // the rhythmic genres actually live (disco/futuristic → stab; jazz/oriental/
                // rock/punk/rocknroll/heavyMetal → comp; klezmer/rocksteady → skank). They used
                // to fall through to the single held onset below, so going through them
                // "everything sounded the same" (drums muted, no lead → only harmony/timbre
                // differed). Now the SAME chord voicing is chopped on each genre's characteristic
                // grid; `busy` fills busier subdivisions. Same pitches (in-key), pad timbre.
                let onsets = Self.chordOnsets(secStart: secStart, secLen: len, energy: busy,
                                              syncopation: mood.syncopation, articulation: articulation,
                                              liveliness: mood.liveliness)
                for pitch in voiced {
                    for onset in onsets {
                        // Metric accent shapes the chops so the rhythm reads as intentional
                        // (downbeat > backbeat > offbeat), not a robotic uniform stutter.
                        notes.append(Note(id: nextUUID(&rng), pitch: pitch,
                                          startStep: onset.start, lengthSteps: onset.len,
                                          velocity: hVel(padVelocity * Self.metricAccent(step: onset.start), &rng)))
                    }
                }
            } else {
                // `.sustained` articulation on the non-arp path (classical, doom): keep the
                // single held onset — legato/held is these genres' identity. Byte-identical.
                for pitch in voiced {
                    notes.append(Note(id: nextUUID(&rng),
                                      pitch: pitch,
                                      startStep: secStart, lengthSteps: len, velocity: hVel(padVelocity, &rng)))
                }
            }

            // Inner PULSE layer ("more elements", founder ear-feedback: an instrumental
            // needs more than one surface). Under a SUSTAINED pad, add a quiet chord-tone
            // pulse on 8ths (16ths when the body is busy) so the texture keeps moving —
            // a take reads as bass · pad · PULSE · lead, an arrangement, not one static
            // Fläche. Arpeggiated genres already move, so skip them. Chord tones only →
            // always in key; sits at the pad's register, softer than the pad.
            // DRONE WHEN CALM (founder 2026-07-04 "könnte mehr Drone mäßig sein"): the
            // pulse is the busy/notey layer. As the body settles (coherence high) DROP it
            // so the texture becomes a sustained pad + bass + sparse lead — a drone. The
            // calmer you get, the more it becomes a drone (the meditative reward), and the
            // synth summing thins out too (fewer simultaneous onsets → less saturation).
            // As arousal returns the pulse comes back for movement.
            if !profile.arpeggiated, !profile.sustained, !voiced.isEmpty, calm <= 0.5 {
                // SOFT TRANCE (founder 2026-07-07): the pulse is the busy layer, so it
                // now only appears when the body is more aroused (calm ≤ 0.5, was
                // 0.6 → drops to a drone sooner) and it's HALVED to 8ths / quarters
                // (was 16ths / 8ths) and quieter, so even when present it just breathes.
                // Coarsen the pulse at fast tempo too (anti-hectic), same threshold as the arp.
                // #418: same shift as the arp, one line higher up the texture — 8ths busy, else
                // quarters, with the Liveliness knob moving where that line sits.
                let pulseGap = (busy > Self.densityThreshold(base: 0.7, liveliness: mood.liveliness) ? 2 : 4)
                    * (densityScale < 0.8 ? 2 : 1)
                let pulseVel = clamp01(padVelocity * 0.45)
                // Voice the pulse an OCTAVE ABOVE the pad (chord tones + 12, clamped ≤127) —
                // a comp/shimmer sits over the held chord like a real player, it doesn't
                // re-articulate the pad's exact fundamentals in the same register. Same-pitch
                // pulses piled mud in one band AND requested the pad's own MIDI pitches on the
                // shared 8-voice poly engine (voice-stealing → pad dropouts on dense 7ths).
                let pulsePitches = voiced.map { Swift.min(127, $0 + 12) }
                var ps = secStart
                var pt = 1                                             // offset so it doesn't just double the pad's downbeat
                while ps < secEnd {
                    let plen = Swift.max(1, Swift.min(pulseGap, secEnd - ps))
                    notes.append(Note(id: nextUUID(&rng),
                                      pitch: pulsePitches[pt % pulsePitches.count],
                                      startStep: ps, lengthSteps: plen, velocity: hVel(pulseVel, &rng)))
                    ps += pulseGap
                    pt += 1
                }
            }
        }

        // 3) Lead melody — ⛔ UNREACHABLE IN THE SHIPPING APP, READ THIS BEFORE PLANNING ANYTHING
        //    FROM THE PARAGRAPH BELOW. EVERY `MusicStyle` case carries (no count: it rots on
        //    every genre batch, the invariant does not)
        //    `leadDensity: 0.0` and nothing mutates it, so the `if` on the next line is never
        //    taken and NO `.lead`-role note is ever composed. The founder removed these melodies
        //    on 2026-07-09 ("die Melodie in den Genres war zu laut und zu unnatürlich … besser
        //    wenn die komplett weg sind — nur chillige mystische Flächen"), which is why
        //    `dubMelody`/`trapMelody`/`ambientMelody` also sit callerless further up this file.
        //    `LeadRoleAbsenceTests` (BLOCKING bundle) pins that and lists what wakes if it changes.
        //    KEPT, not deleted: everything below is the founder's own 2026-07-11/07-20 tuning of how
        //    a lead should sing, and it is the starting point if one ever returns. The cost of
        //    keeping it is this comment; the cost of deleting it is re-deriving the tuning.
        //    ⚠️ WHY A NEW GUARD WHEN THE FACT WAS ALREADY KNOWN — and the honest answer is NOT the
        //    one I gave first ("it was only a comment"). It was ASSERTED, in three places:
        //    `MusicStyleTests.swift` over `MusicStyle.allCases`, and `BioComposerTests.swift:122`
        //    / `:160` on composed output; `:360` states it in prose too. The reason none of them
        //    stopped #253 A5 from being built straight against the invariant is simply that the
        //    WHOLE `EchoelmusicTests` suite is non-blocking (#208) — `full-tests.yml` masks it with
        //    `continue-on-error` on both steps. So the fix was never "assert it", it was "assert it
        //    somewhere that can turn a merge red". That is `Tests/CISmoke`, and nothing else.
        //
        //    a SINGING line, not an arpeggio (founder 2026-07-20
        //    "sicherstellen dass keine Melodien Melodien sind"): the line moves
        //    STEPWISE through the scale (the motif deltas are scale steps → mostly
        //    2nds), and every metrically-STRONG note snaps to the nearest chord tone
        //    so it outlines the harmony — chord tones on the beat, passing / neighbour
        //    tones between. That is the missing middle ground between the old free
        //    scale-walk (drifted out of the chord → aimless) and the chord-tone-only
        //    walk (leapt a 3rd every note → an arpeggio, not a melody). Everything
        //    stays diatonic (scale degrees) so it can't clash, and the strong-beat
        //    anchor stops it drifting. Density, contour and rhythm are animated by the
        //    body — inhale lifts the line, a busier signal adds notes.
        if profile.leadDensity > 0 {
            // Liveliness scales how many lead notes; darkness drops the register.
            let lively = 0.6 + 0.8 * clamp01(mood.liveliness)
            // SPARSE, SINGING LEAD (founder 2026-07-07 "Ton-Dichte runter" → 2026-07-11
            // "die Genres klingen teilweise überladen"): the melody is a sparse line over
            // the pad, not a busy run. Density trimmed again (2 + busy·2.5 → 1.6 + busy·1.6)
            // so an aroused body no longer overloads the newly-opened energetic genres.
            // densityScale thins the line as the playback tempo rises (constant-ish
            // notes-per-second) so a fast take sings instead of machine-gunning; 1.0 at/below
            // the comfortable baseline leaves the count exactly as before.
            // Floor of 3 (was 2): a 2-note phrase is two strong beats with no room
            // for a passing tone between them → a bare chord-tone leap (an arpeggio,
            // the thing we're removing). Three notes guarantee at least one off-beat
            // passing tone, so even the sparsest take sings a step.
            let count = max(3, Int((profile.leadDensity * (1.6 + busy * 1.6) * lively * densityScale).rounded()))
            var lastStart = -1
            // Seed-vary the opening tone so the lead doesn't always begin on the same
            // pitch (a big part of "it's the same tune again"). Breath still biases
            // low on inhale / higher on exhale; the seed adds the individual offset.
            // `scaleDeg` is a scale-degree offset from the sounding chord's root — it
            // STARTS on a chord tone and then walks the scale stepwise (see below).
            let startToneIdx = (breathPhase < 0.5 ? 0 : 1)
                + Int(structureRNG.next() % UInt64(max(1, tones.count)))
            var scaleDeg = tones[((startToneIdx % tones.count) + tones.count) % tones.count]
            // Motif contour (Cycle 3): the line follows a seeded statement→answer
            // shape that resolves, instead of a random walk — so it sings. The deltas
            // are read as SCALE STEPS (a 2nd per unit), giving a stepwise melody.
            let leadDeltas = Self.motifDeltas(count: count,
                                              directionBias: breathPhase < 0.5 ? 0.72 : 0.30,
                                              weird: mood.weird, rng: &rng)
            for i in 0..<count {
                let start = i * stepCount / count
                var startStep = min(stepCount - 1, max(start, lastStart + 1))
                // Syncopation: push an on-beat note onto the following off-beat (still
                // inside the bar, after the previous note) for groove that isn't locked
                // to the downbeat. Scaled so 0 = dead-on-grid. Placement is structural
                // (stable groove across takes), so it draws from structureRNG.
                if startStep % 2 == 0, startStep + 1 < stepCount,
                   structureRNG.unit() < clamp01(mood.syncopation) * 0.6 {
                    startStep += 1
                }
                lastStart = startStep
                let section = min(prog.count - 1, startStep / sectionLen)
                let chordRoot = prog[section]
                // H2: the sounding chord's alterations follow the lead too, so a
                // borrowed suggestion never clashes with its own melody ([] = 0s).
                let leadAlts: [Int]
                if let alts = sectionAlterations, section < alts.count {
                    leadAlts = alts[section]
                } else {
                    leadAlts = []
                }
                // Anchor the harmony: the FIRST note, the LAST note (phrase
                // resolution) and every on-beat note snap to the nearest chord tone,
                // so the stepwise line outlines the chord and settles on it. Off-beat
                // notes keep the scale step (a passing / neighbour tone) that sings.
                let onStrongBeat = (startStep % 4 == 0) || i == 0 || i == count - 1
                if onStrongBeat {
                    scaleDeg = Self.nearestChordDegree(scaleDeg, tones: tones,
                                                       degreesPerOctave: key.degreesPerOctave)
                }
                let chordTone = scaleDeg
                let leadAlteration = ChordSuggest.alteration(forToneOffset: chordTone,
                                                             degreesPerOctave: key.degreesPerOctave,
                                                             in: leadAlts)
                var pitch = key.degree(chordRoot + chordTone, octave: profile.leadOctave + octShift) + leadAlteration
                // Tension (friendly→scary): occasionally bend a lead note a semitone
                // out of the chord for dissonance — scaled by tension so "friendly"
                // stays fully consonant.
                if mood.tension > 0, rng.unit() < clamp01(mood.tension) * 0.45 {
                    pitch += rng.unit() < 0.5 ? 1 : -1
                }
                // Phrasing: a phrase arc (swell to ~⅔, ease off) + a metric accent on
                // the beat give the line real dynamics instead of a flat velocity —
                // the first layer of "virtuosity". Articulation shortens busy notes.
                let pos = count > 1 ? Float(i) / Float(count - 1) : 0
                let arc = clamp01(1 - abs(pos - 0.66) * 1.4)        // 0…1 hump
                let metric: Float = (startStep % 4 == 0) ? 0.12 : 0
                let baseLen = calm > 0.5 ? 3 : 2
                let length = max(1, min(busy > 0.6 ? max(1, baseLen - 1) : baseLen,
                                        stepCount - startStep))
                // Humanize: extra expressive velocity spread on top of the baseline
                // jitter — 0 = tight/uniform, 1 = loose/played-by-hand.
                let velBase = 0.34 + 0.26 * breathDepth + 0.20 * arc + metric
                let velocity = clamp01(hVel(velBase, &rng) + (rng.unit() - 0.5) * clamp01(mood.humanize) * 0.3)
                // At the phrase peak a virtuosic/lively line leaps up an octave for a
                // register climax (same pitch class → still in key), resolving down
                // after — a tension/release arc instead of a flat tessitura.
                let liftP = (0.25 + 0.45 * clamp01(mood.virtuosity)) * (0.4 + 0.6 * clamp01(mood.liveliness))
                let lift = (arc > 0.7 && structureRNG.unit() < liftP) ? 12 : 0   // stable climaxes
                // Ornamentation: a virtuosic line splits a note into a quick grace
                // run — a neighbouring chord tone leading into the main note — for
                // virtuosic motion. Only when there's room (len ≥ 2) so nothing
                // overruns the bar. Both pitches are chord tones → always consonant.
                var mainStart = startStep
                var mainLen = length
                // Ornament PLACEMENT is structural (keeps the note count + rhythm
                // stable across takes); the grace pitch + velocity below stay on the
                // evolving rng so the detail still breathes.
                let ornamentP = clamp01(mood.liveliness) * 0.35 + busy * 0.15 + clamp01(mood.virtuosity) * 0.5
                if length >= 2, startStep + 1 < stepCount, structureRNG.unit() < ornamentP {
                    // A grace note is a neighbouring SCALE tone (a 2nd) leading into
                    // the main note — the classic ornament, still diatonic/in-key.
                    let gDeg = scaleDeg + (rng.unit() < 0.5 ? 1 : -1)
                    let gPitch = Self.tameLeadPitch(key.degree(chordRoot + gDeg, octave: profile.leadOctave + octShift)
                                                    + ChordSuggest.alteration(forToneOffset: gDeg,
                                                                              degreesPerOctave: key.degreesPerOctave,
                                                                              in: leadAlts)
                                                    + lift)
                    notes.append(Note(id: nextUUID(&rng), pitch: Swift.min(127, Swift.max(0, gPitch)),
                                      startStep: startStep, lengthSteps: 1,
                                      velocity: hVel(velocity * 0.7, &rng), role: .lead))
                    mainStart = startStep + 1
                    mainLen = max(1, length - 1)
                }
                notes.append(Note(id: nextUUID(&rng), pitch: Swift.min(127, Swift.max(0, Self.tameLeadPitch(pitch + lift))),
                                  startStep: mainStart, lengthSteps: mainLen, velocity: velocity, role: .lead))
                // Advance the singing line one motif step (a scale step) — the
                // statement→answer contour walks the scale; strong beats above
                // re-anchor it to a chord tone so it can't drift out of the harmony.
                scaleDeg += leadDeltas[i]
            }
        }
        return notes
    }
}
