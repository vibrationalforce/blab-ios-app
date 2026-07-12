// NoteOperators.swift
// Echoel — per-note play operators ("Ableton 20" track A1, founder 2026-07-12:
// "Ableton von Funktionen nicht nur einholen sondern abhängen"). Bitwig-class
// note operators — Chance, Repeats with a velocity ramp, and Occurrence
// (every-Nth-loop) — which Ableton Live 12 does NOT have (Live only offers
// Note Chance + velocity ranges). They make a looped pattern breathe: the same
// bar never has to play identically twice, yet everything stays DETERMINISTIC
// (seeded, reproducible — same seed + loop index → same take, so a performance
// can be re-rendered bit-identically and unit-tested).
//
// Pure value type (Foundation only). Evaluation happens at SCHEDULING time on
// the sequencer clock (main actor), never in the audio render path.

import Foundation

/// One concrete hit produced by evaluating a note's operators for one loop pass.
public struct NoteHit: Equatable, Sendable {
    /// Tick offset from the note's own `startTick` (0 for the first hit).
    public var offsetTicks: Int
    /// Hit length in ticks (≥1).
    public var lengthTicks: Int
    /// Final velocity [0…1] after the repeat ramp.
    public var velocity: Float

    public init(offsetTicks: Int, lengthTicks: Int, velocity: Float) {
        self.offsetTicks = max(0, offsetTicks)
        self.lengthTicks = max(1, lengthTicks)
        self.velocity = min(max(velocity, 0), 1)
    }
}

/// Per-note operators: whether and how a note plays on each pass of the loop.
/// The default instance is a transparent no-op (note plays plainly every loop),
/// so `Note.operators == nil` and `.init()` behave identically.
public struct NoteOperators: Codable, Sendable, Equatable {

    /// Probability [0…1] that the note plays on a given loop pass (1 = always).
    /// Deterministic: the dice roll is seeded per (seed, note, loopIndex).
    public var chance: Double
    /// Number of evenly-spaced hits within the note's length (1 = no ratchet).
    public var repeats: Int
    /// Velocity ramp across the repeats, −1…1: the LAST hit's velocity is
    /// `velocity × (1 + ramp)` (clamped), intermediate hits interpolate
    /// linearly. 0 = flat, +1 = crescendo to double, −1 = decrescendo to zero.
    public var repeatRamp: Double
    /// Play only every Nth loop pass (1 = every loop). With `occurrencePhase`
    /// this is Bitwig's Occurrence: plays when
    /// `loopIndex % occurrencePeriod == occurrencePhase`.
    public var occurrencePeriod: Int
    /// Which pass inside the period plays, 0…period−1.
    public var occurrencePhase: Int

    public static let repeatsRange = 1...32
    public static let periodRange = 1...64

    public init(chance: Double = 1, repeats: Int = 1, repeatRamp: Double = 0,
                occurrencePeriod: Int = 1, occurrencePhase: Int = 0) {
        self.chance = Self.clampUnit(chance, fallback: 1)
        self.repeats = Self.clampInt(repeats, to: Self.repeatsRange)
        self.repeatRamp = Self.clampRamp(repeatRamp)
        self.occurrencePeriod = Self.clampInt(occurrencePeriod, to: Self.periodRange)
        self.occurrencePhase = min(max(0, occurrencePhase), self.occurrencePeriod - 1)
    }

    /// True when this instance changes nothing (the note plays plainly).
    public var isDefault: Bool {
        chance >= 1 && repeats == 1 && repeatRamp == 0 && occurrencePeriod == 1
    }

    // MARK: Evaluation (pure, deterministic)

    /// The hits this note produces on loop pass `loopIndex` (0-based), or `[]`
    /// when the occurrence/chance gates keep it silent this pass. Offsets are
    /// relative to the note's `startTick`. Same inputs → same output, always.
    public func hits(for note: Note, loopIndex: Int, seed: UInt64) -> [NoteHit] {
        let loop = max(0, loopIndex)
        // Occurrence gate: only the matching pass inside the period plays.
        guard loop % occurrencePeriod == occurrencePhase else { return [] }
        // Chance gate: a deterministic per-(note, loop) dice roll.
        if chance < 1 {
            var rng = SeededRNG(seed: seed
                ^ Self.fold(note.id)
                ^ (UInt64(loop) &* 0xD1B54A32D192ED03))
            guard Double(rng.unit()) < chance else { return [] }
        }
        // Repeats: n evenly-spaced hits, velocity ramped towards ×(1 + ramp).
        let n = repeats
        guard n > 1 else {
            return [NoteHit(offsetTicks: 0, lengthTicks: note.lengthTicks,
                            velocity: note.velocity)]
        }
        let hitLength = max(1, note.lengthTicks / n)
        return (0..<n).map { k in
            let f = Double(k) / Double(n - 1)                    // 0 → 1 across hits
            let scale = 1 + repeatRamp * f
            return NoteHit(offsetTicks: k * hitLength,
                           lengthTicks: hitLength,
                           velocity: Float(Double(note.velocity) * scale))
        }
    }

    // MARK: Helpers

    /// Stable 64-bit fold of a UUID — `Hasher` is process-random, so it must
    /// NOT be used here (the take would change on every launch).
    static func fold(_ id: UUID) -> UInt64 {
        let b = id.uuid
        let hi = UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40
            | UInt64(b.3) << 32 | UInt64(b.4) << 24 | UInt64(b.5) << 16
            | UInt64(b.6) << 8 | UInt64(b.7)
        let lo = UInt64(b.8) << 56 | UInt64(b.9) << 48 | UInt64(b.10) << 40
            | UInt64(b.11) << 32 | UInt64(b.12) << 24 | UInt64(b.13) << 16
            | UInt64(b.14) << 8 | UInt64(b.15)
        return hi ^ (lo &* 0x9E3779B97F4A7C15)
    }

    static func clampUnit(_ v: Double, fallback: Double) -> Double {
        guard v.isFinite else { return fallback }
        return min(1, max(0, v))
    }

    static func clampRamp(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(1, max(-1, v))
    }

    static func clampInt(_ v: Int, to range: ClosedRange<Int>) -> Int {
        min(max(v, range.lowerBound), range.upperBound)
    }

    // MARK: Codable (tolerant: absent fields → defaults, values re-clamped)

    private enum CodingKeys: String, CodingKey {
        case chance, repeats, repeatRamp, occurrencePeriod, occurrencePhase
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            chance: try c.decodeIfPresent(Double.self, forKey: .chance) ?? 1,
            repeats: try c.decodeIfPresent(Int.self, forKey: .repeats) ?? 1,
            repeatRamp: try c.decodeIfPresent(Double.self, forKey: .repeatRamp) ?? 0,
            occurrencePeriod: try c.decodeIfPresent(Int.self, forKey: .occurrencePeriod) ?? 1,
            occurrencePhase: try c.decodeIfPresent(Int.self, forKey: .occurrencePhase) ?? 0)
    }
}
