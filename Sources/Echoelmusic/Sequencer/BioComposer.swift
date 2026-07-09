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
public struct MoodProfile: Sendable, Equatable {
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
            structureSeed: UInt64? = nil
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
        }
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

    /// Velocity multiplier (~[1−depth/2, 1+depth/2]) for a note starting at `step`: a metric
    /// accent (downbeat > 8th > 16th, the natural musical hierarchy) blended with a gentle
    /// raised-cosine swell across the bar (0→1→0). Pure + deterministic → unit-tested.
    static func barDynamic(step: Int, stepCount: Int, depth: Float) -> Float {
        guard stepCount > 1 else { return 1 }
        let s = ((step % stepCount) + stepCount) % stepCount
        let pos = Float(s) / Float(stepCount)                     // 0..<1 across the bar
        let metric: Float = (s % 4 == 0) ? 1.0 : (s % 2 == 0 ? 0.6 : 0.32)
        let swell = 0.5 - 0.5 * cos(2 * Float.pi * pos)           // 0 → 1 → 0 hump
        let shape = 0.6 * metric + 0.4 * swell                    // 0…1
        return 1 + clamp01(depth) * (shape - 0.5)                 // centred ~1, span ±depth/2
    }

    /// Shape a take's dynamics over the bar so the WHOLE texture (pads, bass, lead) rises
    /// and relaxes together instead of sitting at a flat velocity — the phrasing a looping
    /// bar otherwise lacks (LRA 1.7 → lifeless). Applied to all genres uniformly. Pure,
    /// deterministic; velocity clamped to a musical [0.05, 1]. depth 0 → unchanged.
    static func shapeBarDynamics(_ notes: [Note], depth: Float, stepCount: Int) -> [Note] {
        guard clamp01(depth) > 0, stepCount > 1 else { return notes }
        return notes.map { note in
            var n = note
            n.velocity = min(max(note.velocity * barDynamic(step: note.startStep,
                                                            stepCount: stepCount, depth: depth), 0.05), 1)
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
            n.velocity = min(max(note.velocity * (1 + v * span), 0.05), 1)
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

    /// Generate music from a bio snapshot, in the requested genre.
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
        // sustained drone (leadDensity 0), IDENTICAL to esotericMeditation (the pad the
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
                                    rng: &rng, structureRNG: &structureRNG)
            switch input.style.beatArchetype {
            case .fourOnFloor:
                (drumSteps, drumAccents) = fourOnFloorBeat(energy: energy, calm: calm, rng: &rng)
            case .backbeat:
                (drumSteps, drumAccents) = backbeatBeat(energy: energy, calm: calm, rng: &rng)
            case .offbeat:
                (drumSteps, drumAccents) = offbeatBeat(energy: energy, calm: calm, rng: &rng)
            case .halfTime:
                (drumSteps, drumAccents) = halfTimeBeat(energy: energy, calm: calm, rng: &rng)
            case .none, .signature:
                (drumSteps, drumAccents) = (emptyGrid(), emptyGrid())
            }
        }

        return BioComposition(
            // Shape the bar's dynamics (metric accent + swell) so the whole texture breathes,
            // THEN add the seeded humanize jitter on top — flat loops read as unprofessional.
            notes: humanizeVelocity(
                shapeBarDynamics(notes, depth: Self.dynamicDepth, stepCount: stepCount),
                amount: input.mood.humanize, seed: input.seed),
            drumSteps: drumSteps,
            drumAccents: drumAccents,
            suggestedTempo: tempo(for: input)
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
    private static func fourOnFloorBeat(energy: Float, calm: Float, rng: inout SeededRNG)
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

        return (steps, accents)
    }

    /// Kick 1 (+3), snare 2 & 4, driving 8th hats — rock/punk/metal backbone.
    private static func backbeatBeat(energy: Float, calm: Float, rng: inout SeededRNG)
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

        return (steps, accents)
    }

    /// Kick anchor on 1 & 3, skank stabs on every offbeat — ska/rocksteady/klezmer.
    private static func offbeatBeat(energy: Float, calm: Float, rng: inout SeededRNG)
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

        return (steps, accents)
    }

    /// Sparse kick, big snare on 3, air between the hits — doom/vaporwave/sci-fi.
    private static func halfTimeBeat(energy: Float, calm: Float, rng: inout SeededRNG)
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

    /// Build a MOVING bass line for one chord section instead of a single held
    /// root. The section downbeat is always the chord root (the foundation); on
    /// takes with drive it subdivides into root/fifth hits and walks a passing
    /// tone up to the NEXT chord's root at the section end — a real bass line,
    /// like a player, not a drone. Calm or short sections keep one sustained root
    /// so spacious genres stay spacious. All tones resolve through
    /// `MusicalKey.degree` → always in key. `role: .bass` so the sub follows it.
    /// Deterministic given the seed.
    private static func appendBass(into notes: inout [Note], key: MusicalKey,
                                   rootDegree: Int, nextRoot: Int, octave: Int,
                                   secStart: Int, len: Int, busy: Float, calm: Float,
                                   velocity: Float, sustained: Bool, rng: inout SeededRNG) {
        let motion = clamp01(busy * 0.7 + (1 - calm) * 0.4)
        // A sustained drone (or a spacious / short section) keeps the grounding
        // single held root — no walking line, whatever the body is doing.
        guard !sustained, motion > 0.32, len >= 4 else {
            notes.append(Note(id: nextUUID(&rng),
                              pitch: key.degree(rootDegree, octave: octave),
                              startStep: secStart, lengthSteps: len,
                              velocity: hVel(velocity, &rng), role: .bass))
            return
        }
        let gap = (motion > 0.62 && len >= 8) ? 2 : 4      // 8ths when driving, else quarters
        let secEndLocal = secStart + len
        var hitStarts: [Int] = []
        var s = secStart
        while s < secEndLocal { hitStarts.append(s); s += gap }
        for (j, start) in hitStarts.enumerated() {
            let noteLen = max(1, min(gap, secEndLocal - start))
            let isDown = (j == 0)
            let isLast = (j == hitStarts.count - 1)
            let degree: Int
            if isDown {
                degree = rootDegree                                  // foundation on the downbeat
            } else if isLast, nextRoot != rootDegree, nextRoot > 0 {
                degree = nextRoot - 1                                // walk a step up into the next root
            } else {
                degree = (j % 2 == 1) ? rootDegree + 4 : rootDegree  // fifth / root alternation
            }
            let vel = isDown ? velocity : velocity * 0.82
            notes.append(Note(id: nextUUID(&rng),
                              pitch: key.degree(degree, octave: octave),
                              startStep: start, lengthSteps: noteLen,
                              velocity: hVel(vel, &rng), role: .bass))
        }
    }

    private static func composeHarmonic(key: MusicalKey, profile: HarmonicProfile,
                                        calm: Float, busy: Float,
                                        breathPhase: Float, breathDepth: Float,
                                        mood: MoodProfile, rng: inout SeededRNG,
                                        structureRNG: inout SeededRNG) -> [Note] {
        var notes: [Note] = []
        // Seed-vary the harmony so a re-seed never replays the identical chord move
        // ("immer derselbe Tonwechsel"). The genre profile sets the vocabulary; the
        // seed rotates the progression and, for adventurous moods, borrows an in-key
        // secondary chord (ii/V/vi) and adds a turnaround so the loop resolves. Every
        // degree still resolves through MusicalKey.degree → always perfectly in key.
        // The harmonic skeleton (progression rotation, borrowed chord, cadence) is
        // drawn from structureRNG so it stays STABLE across evolving takes — the
        // single biggest "same song?" cue. Only the melody on top evolves.
        var prog = profile.progression.isEmpty ? [0] : profile.progression
        if prog.count > 1 {
            let rot = Int(structureRNG.next() % UInt64(prog.count))
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
        // Guard chord tones symmetrically with the progression (a public
        // HarmonicProfile could be built with empty tones → div-by-zero in the arp).
        // Romance adds the 7th for lush chords; darkness drops the whole voicing an
        // octave. (Mood blends on top of the genre profile.)
        var tones = profile.chordTones.isEmpty ? [0, 2, 4] : profile.chordTones
        if mood.romance > 0.5, !tones.contains(6) { tones.append(6) }
        let octShift = mood.darkness > 0.6 ? -1 : 0
        let sectionLen = max(1, stepCount / prog.count)
        let padVelocity = clamp01(0.34 + 0.22 * breathDepth)
        let bassVelocity = clamp01(padVelocity + 0.14)

        // Voice-leading state: the average MIDI pitch of the previous pad voicing.
        // Each chord is shifted by whole octaves to sit closest to it — pitch
        // classes never change (so it stays perfectly in-key), but the chords
        // stop leaping in parallel and instead move smoothly, like a real player.
        var prevPadCenter: Float? = nil

        for (idx, rootDegree) in prog.enumerated() {
            let secStart = idx * sectionLen
            let secEnd = (idx == prog.count - 1) ? stepCount : min(stepCount, secStart + sectionLen)
            guard secEnd > secStart else { continue }
            let len = secEnd - secStart

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
                       sustained: profile.sustained, rng: &rng)

            // 2) Pad — the full chord (root/3rd/5th/7th as the profile defines),
            //    voice-led into the previous chord's register, then sustained for
            //    the section or gently arpeggiated.
            var basePitches: [Int] = []
            for tone in tones { basePitches.append(key.degree(rootDegree + tone, octave: profile.padOctave + octShift)) }
            var shift = 0
            if let center = prevPadCenter, !basePitches.isEmpty {
                let avg = Float(basePitches.reduce(0, +)) / Float(basePitches.count)
                var best = Float.greatestFiniteMagnitude
                for cand in [-12, 0, 12] {
                    let d = abs((avg + Float(cand)) - center)
                    if d < best { best = d; shift = cand }
                }
            }
            let voiced = basePitches.map { $0 + shift }
            if !voiced.isEmpty {
                prevPadCenter = Float(voiced.reduce(0, +)) / Float(voiced.count)
            }

            if profile.arpeggiated {
                // SOFT TRANCE (founder 2026-07-07: "Ton-Dichte runter … ich will
                // angenehmen weichen Trance-Sound"). Arps were 16ths when busy, 8ths
                // when calm — a machine-gun, unnatural top layer. Halved to 8ths /
                // quarter-notes so the arp breathes instead of rattling.
                let arpStep = busy > 0.6 ? 2 : 4
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
            } else {
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
                let pulseGap = busy > 0.7 ? 2 : 4                       // 8ths busy, else quarters
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

        // 3) Lead melody — ALWAYS consonant: every note is a chord tone of the
        //    chord sounding at that step, so it can never clash (no weird/aimless
        //    intervals). Density, contour and rhythm are animated by the body —
        //    inhale lifts the line, a busier signal adds notes — so every take
        //    surprises while staying musical. (Replaces the old free-wandering
        //    scale-degree lead that could drift out of the harmony.)
        if profile.leadDensity > 0 {
            // Liveliness scales how many lead notes; darkness drops the register.
            let lively = 0.6 + 0.8 * clamp01(mood.liveliness)
            // SOFT TRANCE (founder 2026-07-07: "Ton-Dichte runter"): fewer lead notes —
            // the melody is a sparse, singing line over the pad, not a busy run. Roughly
            // halved (was 4 + busy·4).
            let count = max(2, Int((profile.leadDensity * (2 + busy * 2.5) * lively).rounded()))
            var lastStart = -1
            // Seed-vary the opening tone so the lead doesn't always begin on the same
            // pitch (a big part of "it's the same tune again"). Breath still biases
            // low on inhale / higher on exhale; the seed adds the individual offset.
            var toneIdx = (breathPhase < 0.5 ? 0 : 1)
                + Int(structureRNG.next() % UInt64(max(1, tones.count)))
            // Motif contour (Cycle 3): the line follows a seeded statement→answer
            // shape that resolves, instead of a random walk — so it sings.
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
                let chordTone = tones[((toneIdx % tones.count) + tones.count) % tones.count]
                var pitch = key.degree(chordRoot + chordTone, octave: profile.leadOctave + octShift)
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
                    let gIdx = toneIdx + (rng.unit() < 0.5 ? 1 : -1)
                    let gTone = tones[((gIdx % tones.count) + tones.count) % tones.count]
                    let gPitch = key.degree(chordRoot + gTone, octave: profile.leadOctave + octShift) + lift
                    notes.append(Note(id: nextUUID(&rng), pitch: Swift.min(127, Swift.max(0, gPitch)),
                                      startStep: startStep, lengthSteps: 1,
                                      velocity: hVel(velocity * 0.7, &rng), role: .lead))
                    mainStart = startStep + 1
                    mainLen = max(1, length - 1)
                }
                notes.append(Note(id: nextUUID(&rng), pitch: Swift.min(127, Swift.max(0, pitch + lift)),
                                  startStep: mainStart, lengthSteps: mainLen, velocity: velocity, role: .lead))
                // Advance along the motif contour (statement→answer, resolving)
                // instead of a random walk — chord-tone-locked above, so still in key.
                toneIdx += leadDeltas[i]
            }
        }
        return notes
    }
}
