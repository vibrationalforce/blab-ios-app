// BioComposer.swift
// Echoel — the generative core: biodata → an in-key melody + a suggested tempo.
// "Sounds, melody, rhythm and tempo are computed from the biodata." This kernel
// is the melody+tempo half (rhythm follows in a sibling step). It is PURE and
// SEEDED — same inputs + seed produce the same music — so it is fully unit-tested
// without any clock or audio, and a performer can reproduce a take.
//
// Musical mappings (deliberately musical, not random noise):
//   heart rate  → tempo (and rhythmic energy)
//   coherence   → calm: fewer, longer, stepwise notes (high) vs busier leaps (low)
//   breath phase→ melodic direction (inhale rises, exhale falls)
//   breath depth→ velocity
// Every pitch is produced via MusicalKey.degree(...), so output is always in key.

import Foundation

/// Transport intent for a generated take.
public enum ComposerMode: String, Codable, Sendable {
    case studioLocked   // fixed BPM (e.g. 75) for DAW handoff
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
    /// 8 tracks × 16 steps drum grid (kick/snare/hat seeded from the heartbeat).
    /// All-false in Flow mode, which stays ambient (melody only).
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

    public struct Input: Sendable {
        public var heartRateBPM: Float
        public var hrvNormalized: Float     // 0…1
        public var coherence: Float         // 0…1
        public var breathPhase: Float       // 0…1 (0 = inhale start)
        public var breathDepth: Float       // 0…1
        public var key: MusicalKey
        public var mode: ComposerMode
        public var lockedTempo: Double      // used when mode == .studioLocked
        public var seed: UInt64

        public init(
            heartRateBPM: Float = 70,
            hrvNormalized: Float = 0.5,
            coherence: Float = 0.5,
            breathPhase: Float = 0,
            breathDepth: Float = 0.5,
            key: MusicalKey = MusicalKey(root: 0, scale: .minor),
            mode: ComposerMode = .studioLocked,
            lockedTempo: Double = 75,
            seed: UInt64 = 0x5EED
        ) {
            self.heartRateBPM = heartRateBPM
            self.hrvNormalized = hrvNormalized
            self.coherence = coherence
            self.breathPhase = breathPhase
            self.breathDepth = breathDepth
            self.key = key
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

    /// Tempo a take should run at: fixed in Studio mode, heart-following in Flow.
    public static func tempo(for input: Input) -> Double {
        switch input.mode {
        case .studioLocked:
            return min(max(input.lockedTempo, 30), 300)
        case .flowFree:
            return min(max(Double(input.heartRateBPM), 40), 160)
        }
    }

    /// Generate an in-key melody + suggested tempo from a bio snapshot.
    public static func compose(_ input: Input) -> BioComposition {
        var rng = SeededRNG(seed: input.seed)

        let calm = clamp01(input.coherence)
        let energy = clamp01((input.heartRateBPM - 50) / 70)   // 50…120 bpm → 0…1
        let density = 0.5 * (1 - calm) + 0.5 * energy          // 0…1
        let noteCount = 2 + Int((density * 6).rounded())       // 2…8

        // Inhale (phase < 0.5) biases the line upward; exhale downward.
        let inhaleBias: Float = input.breathPhase < 0.5 ? 0.7 : 0.3
        let octave = 4

        var notes: [Note] = []
        var degree = 0
        var lastStart = -1
        for i in 0..<noteCount {
            let start = i * Self.stepCount / noteCount
            // Guarantee strictly increasing, in-bar positions.
            let startStep = min(Self.stepCount - 1, max(start, lastStart + 1))
            lastStart = startStep

            let pitch = input.key.degree(degree, octave: octave)

            // Calmer → longer, more legato; busier → shorter.
            let gap = Float(Self.stepCount) / Float(noteCount)
            let lenF = gap * (0.5 + 0.5 * calm)
            let length = max(1, min(Int(lenF.rounded()), Self.stepCount - startStep))

            // Velocity from breath depth, accent on the downbeat.
            let accent: Float = (startStep % 8 == 0) ? 0.15 : 0
            let velocity = clamp01(0.55 + 0.3 * input.breathDepth + accent)

            let id = Self.nextUUID(&rng)
            notes.append(Note(id: id, pitch: pitch, startStep: startStep,
                              lengthSteps: length, velocity: velocity))

            // Advance the contour: direction from breath, step size from calm.
            let dir = rng.unit() < inhaleBias ? 1 : -1
            let leap = calm > 0.5 ? 1 : 1 + Int(rng.unit() * 2)   // 1 (calm) … 1–2 (busy)
            degree = min(14, max(-7, degree + dir * leap))
        }

        // Rhythm: a heartbeat-seeded beat in Studio mode; Flow stays ambient.
        let (drumSteps, drumAccents) = input.mode == .studioLocked
            ? composeRhythm(calm: calm, energy: energy, rng: &rng)
            : (Self.emptyGrid(), Self.emptyGrid())

        return BioComposition(
            notes: notes,
            drumSteps: drumSteps,
            drumAccents: drumAccents,
            suggestedTempo: tempo(for: input)
        )
    }

    public static let trackCount = 8

    private static func emptyGrid() -> [[Bool]] {
        Array(repeating: Array(repeating: false, count: stepCount), count: trackCount)
    }

    /// Heartbeat → beat. Track 0 = kick (the pulse), 1 = snare (backbeat),
    /// 2 = hi-hat (subdivision density from energy/calm). Deterministic from the
    /// shared RNG; a little seeded syncopation when energetic.
    private static func composeRhythm(
        calm: Float, energy: Float, rng: inout SeededRNG
    ) -> (steps: [[Bool]], accents: [[Bool]]) {
        var steps = emptyGrid()
        var accents = emptyGrid()

        // Kick: 2-on-the-bar when calm, 4-on-the-floor when energetic.
        if energy > 0.55 {
            for s in [0, 4, 8, 12] { steps[0][s] = true }
        } else {
            for s in [0, 8] { steps[0][s] = true }
        }
        accents[0][0] = true   // downbeat accent

        // Snare backbeat on 2 and 4 once there's some energy.
        if energy > 0.3 {
            steps[1][4] = true; steps[1][12] = true
            accents[1][4] = true; accents[1][12] = true
        }

        // Hi-hat subdivision: calm → quarters, busy → 8ths/16ths.
        let drive = min(max(0.5 * energy + 0.5 * (1 - calm), 0), 1)
        let hatEvery = drive > 0.66 ? 1 : (drive > 0.33 ? 2 : 4)
        var s = 0
        while s < stepCount {
            steps[2][s] = true
            s += hatEvery
        }

        // Seeded syncopated kick when energetic (taste, not noise).
        if energy > 0.55, rng.unit() < 0.5 {
            steps[0][14] = true
        }

        return (steps, accents)
    }
}
