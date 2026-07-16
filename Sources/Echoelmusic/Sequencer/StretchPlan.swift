// StretchPlan.swift
// Echoelmusic — Sequencer
//
// PURE resolver for the Echoel stretch engine: given a region's warp settings, chosen
// mode, and the project tempo, it decides the ONE stretch rate + whether pitch is held.
// This is the single source of truth every stretch consumer (audio clip, video sound,
// EchoelBreak, sampler) reads before configuring its executor node — so the tempo maths
// (via `TempoMatch`) and the character choice live in one testable place, not scattered.
//
// No AVFoundation, no clocks, no randomness — deterministic value logic.

import Foundation

public struct StretchPlan: Equatable, Sendable {
    /// The time-stretch rate to apply (1.0 = no change), clamped to `TempoMatch.rateRange`.
    public let rate: Double
    /// Whether the executor should preserve pitch (spectral/WSOLA) or let it move (tape).
    public let preservesPitch: Bool
    /// The mode actually rendered (chosen mode, or its `.clean` fallback if unimplemented).
    public let mode: StretchMode

    public init(rate: Double, preservesPitch: Bool, mode: StretchMode) {
        self.rate = rate
        self.preservesPitch = preservesPitch
        self.mode = mode
    }

    /// The identity plan — no tempo change, pitch held, Clean path. What every
    /// non-warping consumer (region audition, plain playback) passes.
    public static let unstretched = StretchPlan(rate: 1.0, preservesPitch: true, mode: .clean)

    /// Resolve the plan. `rate` is 1.0 (no stretch) whenever warp is off, the native
    /// tempo is unknown, or the project tempo is non-positive — identical to
    /// `AudioClipRegion.effectiveStretchRate`, so the two never diverge. The rendered
    /// `mode` is the chosen mode's `effectiveMode` (honest `.clean` fallback), and
    /// `preservesPitch` follows that rendered mode.
    public static func resolve(mode: StretchMode,
                               warpEnabled: Bool,
                               nativeBPM: Double,
                               projectBPM: Double) -> StretchPlan {
        let rendered = mode.effectiveMode
        let rate: Double
        if warpEnabled, nativeBPM > 0, projectBPM > 0 {
            rate = TempoMatch.stretchRate(nativeBPM: nativeBPM, masterBPM: projectBPM)
        } else {
            rate = 1.0
        }
        return StretchPlan(rate: rate, preservesPitch: rendered.preservesPitch, mode: rendered)
    }

    /// Pitch offset in CENTS that makes pitch ride the tempo — the tape/varispeed
    /// character rendered on a pitch-preserving spectral node (`AVAudioUnitTimePitch`):
    /// playing at `rate` naturally shifts pitch by `1200·log₂(rate)` cents, so setting the
    /// node's `pitch` to that value re-introduces exactly the tape pitch trajectory the
    /// spectral engine would otherwise cancel. Clean modes use 0 (pitch held). `rate ≤ 0`
    /// or `1.0` → 0 cents (no warp → clean and tape sound identical, by design).
    public static func tapePitchCents(forRate rate: Double) -> Double {
        guard rate > 0 else { return 0 }
        return 1200.0 * log2(rate)
    }
}
