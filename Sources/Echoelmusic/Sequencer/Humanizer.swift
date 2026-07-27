// Humanizer.swift
// Echoel — "tight grid or humanized — the user decides." A tight take sits dead
// on the grid (quantized, mechanical); a humanized take gets subtle, musical
// timing and velocity variation so it breathes like a played performance.
//
// Pure value type (Foundation only). The jitter is SEEDED and per-index, so a
// humanized take is fully reproducible and unit-tested — same seed, same feel.
// Applied at MIDI export (where real ticks exist), not baked into the grid, so a
// user can switch between Tight and Humanized non-destructively.

import Foundation

/// Per-note timing + velocity variation. `tight` = no change (perfect grid).
public struct Humanizer: Sendable, Equatable {
    /// Maximum ± timing jitter in MIDI ticks (96 PPQ → 24 ticks per 16th).
    public var timingTicks: Int
    /// Maximum ± velocity variation as a fraction (0.12 = ±12%).
    public var velocityJitter: Float

    public init(timingTicks: Int, velocityJitter: Float) {
        self.timingTicks = max(0, timingTicks)
        self.velocityJitter = velocityJitter.clamped(to: 0...1)   // NaN-safe: NaN → no jitter
    }

    /// Dead on the grid — no humanization.
    public static let tight = Humanizer(timingTicks: 0, velocityJitter: 0)

    /// A natural, played feel: ±4 ticks (~21 ms at 120 BPM) and ±12% velocity.
    public static let humanized = Humanizer(timingTicks: 4, velocityJitter: 0.12)

    /// Whether any humanization is applied.
    public var isActive: Bool { timingTicks > 0 || velocityJitter > 0 }

    /// Deterministic jitter for the note/hit at `index`. Returns a timing delta in
    /// ticks (within ±timingTicks) and a velocity multiplier (within 1±jitter).
    /// Seeded per-index so the whole take is reproducible.
    public func jitter(index: Int, seed: UInt64) -> (tickDelta: Int, velocityScale: Float) {
        guard isActive else { return (0, 1) }
        // A distinct sub-stream per index keeps adjacent notes uncorrelated.
        var rng = SeededRNG(seed: seed &+ (UInt64(bitPattern: Int64(index)) &* 0x9E3779B97F4A7C15))
        let t = (rng.unit() * 2 - 1)   // -1…1
        let v = (rng.unit() * 2 - 1)   // -1…1
        let tickDelta = Int((t * Float(timingTicks)).rounded())
        let velocityScale = 1 + v * velocityJitter
        return (tickDelta, velocityScale)
    }
}
