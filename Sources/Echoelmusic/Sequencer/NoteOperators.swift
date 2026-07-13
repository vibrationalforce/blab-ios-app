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

/// One note's EXPRESSION for a loop pass (A5 bio-per-note): how the body shapes
/// this note's dynamics this time round. `velocityScale` multiplies the note-on
/// amplitude (the only dimension wired today); `timingOffsetTicks` and
/// `brightness` are tested model outputs reserved for the sub-tick clock (W2) and
/// a future per-note filter input. The identity (`.init()`) touches nothing:
/// scale 1, no shift, `brightness == nil` (leave the filter alone).
public struct NoteExpression: Equatable, Sendable {
    public var velocityScale: Float
    public var timingOffsetTicks: Int
    public var brightness: Float?

    public init(velocityScale: Float = 1, timingOffsetTicks: Int = 0, brightness: Float? = nil) {
        self.velocityScale = velocityScale
        self.timingOffsetTicks = timingOffsetTicks
        self.brightness = brightness
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

    /// A5 bio-per-note EXPRESSION depths (all default 0 = transparent). Coherence +
    /// breath deterministically shape the note's dynamics each loop pass; the depth is
    /// how far the body is allowed to move that dimension. `velocityDepth` (−1…1) is
    /// wired (note-on amplitude); `timingDepth` (−1…1) and `filterDepth` (0…1) are
    /// tested model outputs, not yet wired (see `expression(for:…)`).
    public var velocityDepth: Double
    public var timingDepth: Double
    public var filterDepth: Double

    public static let repeatsRange = 1...32
    public static let periodRange = 1...64

    /// Distinct salt for the expression jitter so it is DE-CORRELATED from the chance
    /// roll (which uses `0xD1B54A32D192ED03`); otherwise a whole gated chord would
    /// swell/thin as one unit instead of each note breathing on its own.
    static let expressionSalt: UInt64 = 0x94D049BB133111EB
    /// Micro-timing jitter window in ticks (± this), small so it humanizes, not drags.
    static let maxTimingTicks = 12
    static let velScaleMin: Float = 0.1     // expression never fully mutes (that is chance's job)
    static let velScaleMax: Float = 2.0

    public init(chance: Double = 1, repeats: Int = 1, repeatRamp: Double = 0,
                occurrencePeriod: Int = 1, occurrencePhase: Int = 0,
                velocityDepth: Double = 0, timingDepth: Double = 0, filterDepth: Double = 0) {
        self.chance = Self.clampUnit(chance, fallback: 1)
        self.repeats = Self.clampInt(repeats, to: Self.repeatsRange)
        self.repeatRamp = Self.clampRamp(repeatRamp)
        self.occurrencePeriod = Self.clampInt(occurrencePeriod, to: Self.periodRange)
        self.occurrencePhase = min(max(0, occurrencePhase), self.occurrencePeriod - 1)
        self.velocityDepth = Self.clampRamp(velocityDepth)      // −1…1
        self.timingDepth = Self.clampRamp(timingDepth)          // −1…1
        self.filterDepth = Self.clampUnit(filterDepth, fallback: 0)  // 0…1
    }

    /// True when this instance changes nothing (the note plays plainly).
    public var isDefault: Bool {
        chance >= 1 && repeats == 1 && repeatRamp == 0 && occurrencePeriod == 1
            && velocityDepth == 0 && timingDepth == 0 && filterDepth == 0
    }

    // MARK: Evaluation (pure, deterministic — bio bends the dice, never the die)

    /// The chance actually rolled when the body is present (A4 Bio-Operators —
    /// the position nobody in the field occupies: physiology as a per-note
    /// operator). Coherence 0.5 is NEUTRAL (returns `chance` unchanged); high
    /// coherence lifts the odds (the pattern fills out as the player settles),
    /// low coherence thins it. Bends ONLY a chance the user set strictly
    /// between 0 and 1: 0 stays silent (muted is muted), 1 stays certain
    /// (plain and occurrence-only notes never flicker), nil bio → identity.
    public func bioBentChance(coherence: Double?) -> Double {
        guard let c = coherence, c.isFinite, chance > 0, chance < 1 else { return chance }
        let bend = (min(1, max(0, c)) - 0.5)          // −0.5 … +0.5
        return min(1, max(0, chance + bend))
    }

    /// A5 per-note EXPRESSION: how coherence + breath shape THIS note's dynamics on
    /// loop pass `loopIndex`. Mirrors `bioBentChance` exactly — coherence 0.5 is
    /// NEUTRAL, no body (both `coherence` and `breath` nil) OR all depths 0 → identity
    /// — so legacy/plain notes are byte-identical and a settled body simply lets the
    /// pattern breathe. Velocity is a SMOOTH deterministic function of the body (no
    /// jitter → neutral bio returns exactly the un-bent centre, parity with the chance
    /// roll); the small seeded per-note jitter rides on the (still-unwired) micro-timing
    /// so a whole chord doesn't move as one block. Fully reproducible (SeededRNG +
    /// UUID-fold, never `Hasher`), clamped, and safe for a noisy/absent body.
    public func expression(for note: Note, loopIndex: Int, seed: UInt64,
                           coherence: Double?, breath: Double?) -> NoteExpression {
        // No body present at all → pure identity (mirrors the bioBentChance nil-guard).
        guard coherence != nil || breath != nil else { return NoteExpression() }

        // Coherence 0.5 = neutral (delta 0); breath is a raised hump, 0 at the cycle
        // ends and 1 at mid-cycle (sin, matching the trigger's breathSwell convention).
        // A nil or non-finite field contributes nothing (safe for a noisy/absent body).
        let cohDelta: Double = {
            guard let c = coherence, c.isFinite else { return 0 }
            return min(1, max(0, c)) - 0.5              // −0.5 … +0.5
        }()
        let breathHump: Double = {
            guard let b = breath, b.isFinite else { return 0 }
            return sin(min(1, max(0, b)) * .pi)         // 0 … 1, hump
        }()
        let bodyBend = cohDelta + 0.5 * breathHump      // −0.5 … +1.0

        // Velocity (WIRED): smooth, jitter-free → neutral body = exact centre 1.
        let velScale: Float = velocityDepth == 0
            ? 1
            : min(Self.velScaleMax, max(Self.velScaleMin, Float(1 + velocityDepth * bodyBend)))

        // Micro-timing (MODEL-ONLY, unwired): a small seeded jitter, de-correlated from
        // the chance roll via a distinct salt so each note breathes independently.
        var timing = 0
        if timingDepth != 0 {
            var rng = SeededRNG(seed: seed
                ^ Self.fold(note.id)
                ^ (UInt64(max(0, loopIndex)) &* Self.expressionSalt))
            let jitter = (Double(rng.unit()) - 0.5) * 2      // −1 … 1
            timing = Int((timingDepth * jitter * Double(Self.maxTimingTicks)).rounded())
        }

        // Brightness (MODEL-ONLY, unwired): nil unless the filter depth is engaged.
        let bright: Float? = filterDepth == 0
            ? nil
            : min(1, max(0, Float(0.5 + filterDepth * bodyBend)))

        return NoteExpression(velocityScale: velScale, timingOffsetTicks: timing, brightness: bright)
    }

    /// The hits this note produces on loop pass `loopIndex` (0-based), or `[]`
    /// when the occurrence/chance gates keep it silent this pass. Offsets are
    /// relative to the note's `startTick`. Without `coherence` the take is
    /// fully deterministic (same inputs → same output, always); with a live
    /// body the dice THRESHOLD moves with coherence while the roll itself
    /// stays seeded — replaying with the same recorded coherence reproduces
    /// the take exactly.
    public func hits(for note: Note, loopIndex: Int, seed: UInt64,
                     coherence: Double? = nil) -> [NoteHit] {
        let loop = max(0, loopIndex)
        // Occurrence gate: only the matching pass inside the period plays.
        guard loop % occurrencePeriod == occurrencePhase else { return [] }
        // Chance gate: a deterministic per-(note, loop) dice roll against a
        // (possibly bio-bent) threshold.
        if chance < 1 {
            var rng = SeededRNG(seed: seed
                ^ Self.fold(note.id)
                ^ (UInt64(loop) &* 0xD1B54A32D192ED03))
            guard Double(rng.unit()) < bioBentChance(coherence: coherence) else { return [] }
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
        case velocityDepth, timingDepth, filterDepth
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            chance: try c.decodeIfPresent(Double.self, forKey: .chance) ?? 1,
            repeats: try c.decodeIfPresent(Int.self, forKey: .repeats) ?? 1,
            repeatRamp: try c.decodeIfPresent(Double.self, forKey: .repeatRamp) ?? 0,
            occurrencePeriod: try c.decodeIfPresent(Int.self, forKey: .occurrencePeriod) ?? 1,
            occurrencePhase: try c.decodeIfPresent(Int.self, forKey: .occurrencePhase) ?? 0,
            velocityDepth: try c.decodeIfPresent(Double.self, forKey: .velocityDepth) ?? 0,
            timingDepth: try c.decodeIfPresent(Double.self, forKey: .timingDepth) ?? 0,
            filterDepth: try c.decodeIfPresent(Double.self, forKey: .filterDepth) ?? 0)
    }

    /// Custom encoder that preserves BYTE-IDENTITY for pre-A5 operators: the original
    /// five fields are written in the same order the synthesized encoder used, and each
    /// expression depth is emitted ONLY when non-zero. So a chance/repeat/occurrence
    /// operator serializes exactly as before (old builds keep ignoring absent keys),
    /// and the new fields cost nothing until a note actually uses expression.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(chance, forKey: .chance)
        try c.encode(repeats, forKey: .repeats)
        try c.encode(repeatRamp, forKey: .repeatRamp)
        try c.encode(occurrencePeriod, forKey: .occurrencePeriod)
        try c.encode(occurrencePhase, forKey: .occurrencePhase)
        if velocityDepth != 0 { try c.encode(velocityDepth, forKey: .velocityDepth) }
        if timingDepth != 0 { try c.encode(timingDepth, forKey: .timingDepth) }
        if filterDepth != 0 { try c.encode(filterDepth, forKey: .filterDepth) }
    }
}
