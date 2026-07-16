// VideoResyncPolicy.swift
// Echoelmusic — Sequencer
//
// PURE, device-free drift-correction policy for a video lane locked to the shared
// audio/transport clock. `VideoRegionSync` (see VideoRegionSync.swift) maps the
// playhead to an EXPECTED source time; the device-side player reports the frame it
// is ACTUALLY showing. This policy compares the two and decides how to close the gap
// so the picture stays glued to the sound:
//   - a big gap, or a region switch / media wrap → hard seek to the expected time,
//   - a sub-frame gap → hold (do nothing; a seek would only add judder),
//   - anything in between → nudge the playback rate proportional to the drift,
//     clamped to ±3% so the correction is inaudible/invisible.
//
// Deterministic and side-effect free — no AVFoundation, no clocks, no randomness.
// All timing inputs are seconds.

import Foundation

/// The correction a video lane should apply this tick to stay locked to the audio clock.
public enum VideoResyncAction: Equatable, Sendable {
    /// Drift is within one frame — do nothing (a seek here would add visible judder).
    case hold
    /// Multiply the player's nominal rate by this factor to slew the picture back into
    /// lock. Always in `0.97...1.03` (±3%). Ramps from ~1.0 at the deadband edge (a value
    /// arbitrarily close to — but effectively never exactly — 1.0, since only drift BEYOND
    /// the deadband is corrected); `player.rate = 1.0` would simply be a no-op anyway.
    case nudgeRate(Float)
    /// The gap is too large to slew away (or the region switched / media wrapped) —
    /// seek the player straight to `toSeconds` (the expected source time).
    case hardSeek(toSeconds: Double)
}

/// Pure policy that resolves the per-tick resync action for a locked video lane.
public enum VideoResyncPolicy {

    /// Gap (seconds) beyond which slewing can't catch up in time — hard-seek instead.
    public static let hardSeekThresholdSeconds: Double = 0.25
    /// Sub-frame deadband (≈ one frame at 30 fps). Within this, `hold`.
    public static let deadbandSeconds: Double = 0.033
    /// Slew clamp: the nudged rate stays within `[minRate, maxRate]` (±3%).
    public static let minRate: Float = 0.97
    public static let maxRate: Float = 1.03
    /// Rate change per second of drift BEYOND the deadband, before clamping. The nudge
    /// ramps from ZERO at the deadband edge (continuous with `hold`), so crossing the
    /// deadband no longer jumps the rate — the correction grows smoothly with the excess
    /// drift. |drift| ≈ 0.093 s reaches the ±3% clamp onset (0.06 excess × 0.5 = 0.03);
    /// |drift| approaching the 0.25 s hard-seek threshold is fully clamped.
    private static let rateGainPerSecond: Double = 0.5

    /// Decide how the video lane should correct this tick.
    ///
    /// `drift = observedSeconds - expectedSourceSeconds`. POSITIVE means the picture is
    /// AHEAD of the audio (slow it down, rate < 1); NEGATIVE means BEHIND (speed it up,
    /// rate > 1). (Matches the inline law below and the sign used throughout.)
    ///
    /// - Parameters:
    ///   - expectedSourceSeconds: source time the playhead maps to (from `VideoRegionSync`).
    ///   - observedSeconds: source time the player reports it is actually showing.
    ///   - dt: seconds since the last resolve (reserved for future rate integration; the
    ///     current proportional law does not divide by it, so any value — incl. 0 — is safe).
    ///   - regionSwitchedOrWrapped: true when the lane jumped regions or the media looped
    ///     this tick, so continuity is already broken and a hard seek is correct.
    /// - Returns: the `VideoResyncAction` to apply.
    public static func resolve(expectedSourceSeconds: Double,
                               observedSeconds: Double,
                               dt: Double,
                               regionSwitchedOrWrapped: Bool) -> VideoResyncAction {
        // Non-finite inputs → safest recovery is to re-anchor at the expected time.
        let expected = expectedSourceSeconds.isFinite ? expectedSourceSeconds : 0
        guard observedSeconds.isFinite else {
            return .hardSeek(toSeconds: expected)
        }

        let drift = observedSeconds - expected

        // Region change / loop wrap: continuity is broken → hard seek to expected.
        if regionSwitchedOrWrapped {
            return .hardSeek(toSeconds: expected)
        }

        let magnitude = abs(drift)

        // Too far to slew away in a reasonable window → hard seek.
        if magnitude > hardSeekThresholdSeconds {
            return .hardSeek(toSeconds: expected)
        }

        // Within one frame → leave it alone.
        if magnitude <= deadbandSeconds {
            return .hold
        }

        // Proportional nudge that RAMPS FROM ZERO at the deadband edge: only the drift
        // BEYOND the deadband is corrected, so the rate is continuous with `hold` at the
        // boundary. Without this, drift crossing the deadband jumped the rate from 1.0 to
        // a ~1.7% slew instantly, and at the ~8 Hz correction cadence the value oscillated
        // in and out of the deadband → visible rate shimmer/judder. drift = observed-expected:
        //   drift > 0 → player AHEAD of the audio → slow down (rate < 1).
        //   drift < 0 → player BEHIND the audio → speed up (rate > 1).
        let excess = magnitude - deadbandSeconds            // > 0 here (past the deadband)
        let signedExcess = drift > 0 ? excess : -excess
        let rawRate = 1.0 - signedExcess * rateGainPerSecond
        let clamped = Float(min(max(rawRate, Double(minRate)), Double(maxRate)))
        return .nudgeRate(clamped)
    }
}
