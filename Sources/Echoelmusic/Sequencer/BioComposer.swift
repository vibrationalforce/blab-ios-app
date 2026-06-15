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
        public var seed: UInt64

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
            seed: UInt64 = 0x5EED
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
            self.seed = seed
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

    /// Tempo a take should run at: clamped into the style's window in Studio mode,
    /// heart-following in Flow.
    public static func tempo(for input: Input) -> Double {
        switch input.mode {
        case .studioLocked:
            let r = input.style.tempoRange
            return min(max(input.lockedTempo, r.lowerBound), r.upperBound)
        case .flowFree:
            return min(max(Double(input.heartRateBPM), 40), 160)
        }
    }

    /// Generate music from a bio snapshot, in the requested genre.
    public static func compose(_ input: Input) -> BioComposition {
        var rng = SeededRNG(seed: input.seed)

        // ── Physiological → musical state (autonomic-balance model) ───────────
        // The body is read as an autonomic state, not four loose dials:
        //   • coherence (`calm`) = HRV resonance near 0.1 Hz → an ordered,
        //     parasympathetic state. High ⇒ space, repetition, consonance.
        //   • hrvNormalized (`vagal`) = vagal tone (RMSSD-derived). High ⇒ relaxed;
        //     LOW ⇒ sympathetic ("fight/flight") load, which lifts musical energy.
        //   • heart rate (`energy`) = cardiac drive → rhythmic energy + tempo.
        // `arousal` (sympathetic activation) rises with a fast heart AND low HRV —
        // the textbook stress signature (↑HR, ↓HRV) — so the take gets busier/denser
        // when the body is activated and opens up when it settles. Previously
        // hrvNormalized was collected but never reached the composition; this threads
        // it in so the music genuinely tracks autonomic balance, not just heart rate.
        let calm    = clamp01(input.coherence)
        let vagal   = clamp01(input.hrvNormalized)
        let energy  = clamp01((input.heartRateBPM - 50) / 70)   // 50…120 bpm → 0…1
        let arousal = clamp01(0.55 * energy + 0.45 * (1 - vagal))
        let busy    = clamp01(0.6 * arousal + 0.4 * (1 - calm))

        let notes: [Note]
        let drumSteps: [[Bool]]
        let drumAccents: [[Bool]]

        switch input.style {
        case .dubTechno:
            notes = dubMelody(key: input.key, busy: busy,
                              breathDepth: input.breathDepth, rng: &rng)
            (drumSteps, drumAccents) = dubBeat(energy: energy, rng: &rng)
        case .trap:
            notes = trapMelody(key: input.key, busy: busy, calm: calm,
                               breathPhase: input.breathPhase,
                               breathDepth: input.breathDepth, rng: &rng)
            (drumSteps, drumAccents) = trapBeat(energy: energy, calm: calm, rng: &rng)
        case .selfObservation:
            notes = ambientMelody(key: input.key, calm: calm, busy: busy,
                                  breathPhase: input.breathPhase,
                                  breathDepth: input.breathDepth, rng: &rng)
            (drumSteps, drumAccents) = (emptyGrid(), emptyGrid())
        default:
            // The non-beat harmonic genres: pads/chords/arps + an optional lead,
            // the starting material for a professional production. No drums.
            notes = composeHarmonic(key: input.key, profile: input.style.harmonicProfile,
                                    calm: calm, busy: busy,
                                    breathPhase: input.breathPhase,
                                    breathDepth: input.breathDepth, rng: &rng)
            (drumSteps, drumAccents) = (emptyGrid(), emptyGrid())
        }

        return BioComposition(
            notes: notes,
            drumSteps: drumSteps,
            drumAccents: drumAccents,
            suggestedTempo: tempo(for: input)
        )
    }

    private static func emptyGrid() -> [[Bool]] {
        Array(repeating: Array(repeating: false, count: stepCount), count: trackCount)
    }

    // MARK: - Dub Techno (deep dub chords · tape echo · sub-bass)

    /// Steady 4/4 kick, offbeat ticks, a deep sub on 1 & 3, a soft backbeat and a
    /// little seeded perc. Hypnotic and spacious — the genre's signature.
    private static func dubBeat(energy: Float, rng: inout SeededRNG)
        -> (steps: [[Bool]], accents: [[Bool]]) {
        var steps = emptyGrid()
        var accents = emptyGrid()

        // 4-on-the-floor kick — the dub pulse.
        for s in stride(from: 0, to: stepCount, by: 4) { steps[Track.kick][s] = true }
        accents[Track.kick][0] = true
        accents[Track.kick][8] = true

        // Offbeat closed-hat tick (the "tss" between the kicks).
        for s in [2, 6, 10, 14] { steps[Track.closedHat][s] = true }

        // Offbeat open-hat skank once there's drive.
        if energy > 0.35 { steps[Track.openHat][6] = true; steps[Track.openHat][14] = true }

        // Soft backbeat clap on beat 4 (and 2 when energetic).
        steps[Track.clap][12] = true
        accents[Track.clap][12] = true
        if energy > 0.5 { steps[Track.clap][4] = true }

        // Deep dub sub on the 1 and the 3.
        steps[Track.bass][0] = true
        steps[Track.bass][8] = true

        // A little seeded perc for movement — taste, not noise.
        if rng.unit() < 0.6 {
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

        for s in positions([2, 6])  { addChord(rootDegree: 0, at: s) }   // i  (tonic)
        for s in positions([10, 14]) { addChord(rootDegree: 3, at: s) }  // IV (subdominant)
        return notes
    }

    // MARK: - Trap (booming 808 sub-bass · crisp hats · dark melody)

    /// Syncopated 808 kick, half-time snare/clap on beat 3, rolling 16th hats and
    /// the open-hat lift into the loop. The 808 sub mirrors the kick.
    private static func trapBeat(energy: Float, calm: Float, rng: inout SeededRNG)
        -> (steps: [[Bool]], accents: [[Bool]]) {
        var steps = emptyGrid()
        var accents = emptyGrid()

        // 808 kick: syncopated, half-time feel. The Bass track doubles it (the 808).
        var kickHits = [0, 6, 10]
        if energy > 0.5 { kickHits.append(3) }
        if rng.unit() < 0.5 { kickHits.append(11) }
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

        // Sparse seeded perc.
        if rng.unit() < 0.5 {
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
                              lengthSteps: 6, velocity: subVel))
        }

        // Sparse dark bell lead up top (octave 5), harmonic-minor tension.
        let leadOctave = 5
        let noteCount = 3 + Int((busy * 3).rounded())   // 3…6
        let inhaleBias: Float = breathPhase < 0.5 ? 0.65 : 0.35
        var degree = 0
        var lastStart = -1
        for i in 0..<noteCount {
            let start = i * stepCount / noteCount
            let startStep = min(stepCount - 1, max(start, lastStart + 1))
            lastStart = startStep

            let pitch = key.degree(degree, octave: leadOctave)
            let length = max(1, min(calm > 0.5 ? 3 : 2, stepCount - startStep))
            let velocity = clamp01(0.5 + 0.3 * breathDepth)
            notes.append(Note(id: nextUUID(&rng), pitch: pitch, startStep: startStep,
                              lengthSteps: length, velocity: velocity))

            let dir = rng.unit() < inhaleBias ? 1 : -1
            let leap = 1 + Int(rng.unit() * 2)
            degree = min(14, max(-7, degree + dir * leap))
        }
        return notes
    }

    // MARK: - Self-Observation (ambient, no drums)

    /// A gentle, breath-paced contour for meditation. Calmer coherence → longer,
    /// more stepwise notes; the breath sets the rise/fall.
    private static func ambientMelody(key: MusicalKey, calm: Float, busy: Float,
                                      breathPhase: Float, breathDepth: Float,
                                      rng: inout SeededRNG) -> [Note] {
        // Density follows the autonomic state (`busy` already folds in heart rate,
        // vagal tone/HRV and coherence) — so in meditation the line thins as the
        // body settles and fills out under sympathetic load. clamp01 keeps 2…8.
        let density = clamp01(busy)
        let noteCount = 2 + Int((density * 6).rounded())       // 2…8
        let inhaleBias: Float = breathPhase < 0.5 ? 0.7 : 0.3
        let octave = 4

        var notes: [Note] = []
        var degree = 0
        var lastStart = -1
        for i in 0..<noteCount {
            let start = i * stepCount / noteCount
            let startStep = min(stepCount - 1, max(start, lastStart + 1))
            lastStart = startStep

            let pitch = key.degree(degree, octave: octave)
            let gap = Float(stepCount) / Float(noteCount)
            let lenF = gap * (0.5 + 0.5 * calm)
            let length = max(1, min(Int(lenF.rounded()), stepCount - startStep))

            let accent: Float = (startStep % 8 == 0) ? 0.15 : 0
            let velocity = clamp01(0.55 + 0.3 * breathDepth + accent)

            notes.append(Note(id: nextUUID(&rng), pitch: pitch, startStep: startStep,
                              lengthSteps: length, velocity: velocity))

            let dir = rng.unit() < inhaleBias ? 1 : -1
            let leap = calm > 0.5 ? 1 : 1 + Int(rng.unit() * 2)
            degree = min(14, max(-7, degree + dir * leap))
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

    private static func composeHarmonic(key: MusicalKey, profile: HarmonicProfile,
                                        calm: Float, busy: Float,
                                        breathPhase: Float, breathDepth: Float,
                                        rng: inout SeededRNG) -> [Note] {
        var notes: [Note] = []
        let prog = profile.progression.isEmpty ? [0] : profile.progression
        // Guard chord tones symmetrically with the progression (a public
        // HarmonicProfile could be built with empty tones → div-by-zero in the arp).
        let tones = profile.chordTones.isEmpty ? [0, 2, 4] : profile.chordTones
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

            // 1) Bass foundation — a sustained root an octave below the pad. Gives
            //    every chord a defined low end so the loop reads full and produced,
            //    never thin or floating. Slightly stronger so it grounds the harmony.
            let bassOct = max(0, profile.padOctave - 1)
            notes.append(Note(id: nextUUID(&rng),
                              pitch: key.degree(rootDegree, octave: bassOct),
                              startStep: secStart, lengthSteps: len, velocity: hVel(bassVelocity, &rng)))

            // 2) Pad — the full chord (root/3rd/5th/7th as the profile defines),
            //    voice-led into the previous chord's register, then sustained for
            //    the section or gently arpeggiated.
            var basePitches: [Int] = []
            for tone in tones { basePitches.append(key.degree(rootDegree + tone, octave: profile.padOctave)) }
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
                let arpStep = busy > 0.5 ? 1 : 2
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
        }

        // 3) Lead melody — ALWAYS consonant: every note is a chord tone of the
        //    chord sounding at that step, so it can never clash (no weird/aimless
        //    intervals). Density, contour and rhythm are animated by the body —
        //    inhale lifts the line, a busier signal adds notes — so every take
        //    surprises while staying musical. (Replaces the old free-wandering
        //    scale-degree lead that could drift out of the harmony.)
        if profile.leadDensity > 0 {
            let count = max(2, Int((profile.leadDensity * (4 + busy * 4)).rounded()))
            var lastStart = -1
            var toneIdx = breathPhase < 0.5 ? 0 : 1   // inhale low → exhale higher
            for i in 0..<count {
                let start = i * stepCount / count
                let startStep = min(stepCount - 1, max(start, lastStart + 1))
                lastStart = startStep
                let section = min(prog.count - 1, startStep / sectionLen)
                let chordRoot = prog[section]
                let chordTone = tones[((toneIdx % tones.count) + tones.count) % tones.count]
                let pitch = key.degree(chordRoot + chordTone, octave: profile.leadOctave)
                let length = max(1, min(calm > 0.5 ? 3 : 2, stepCount - startStep))
                let velocity = hVel(0.46 + 0.30 * breathDepth, &rng)
                notes.append(Note(id: nextUUID(&rng), pitch: pitch, startStep: startStep,
                                  lengthSteps: length, velocity: velocity))
                // Small, singable steps through the chord; inhale biases upward.
                let up = rng.unit() < (breathPhase < 0.5 ? 0.62 : 0.40)
                toneIdx += up ? 1 : -1
            }
        }
        return notes
    }
}
