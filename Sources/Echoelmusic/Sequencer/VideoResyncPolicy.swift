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
    /// lock. Always in `0.97...1.03` (±3%). `1.0` would be no change (never emitted —
    /// `hold` covers the deadband instead).
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
    /// Rate change per second of drift, before clamping. Chosen so the nudge band is
    /// meaningful: drift just past the ~0.033 s deadband produces a small proportional
    /// nudge, and drift approaching the 0.25 s hard-seek threshold saturates the ±3%
    /// clamp (e.g. |drift| 0.06 s → 0.03 delta → clamp onset; |drift| 0.20 s → clamped).
    private static let rateGainPerSecond: Double = 0.5

    /// Decide how the video lane should correct this tick.
    ///
    /// `drift = observedSeconds - expectedSourceSeconds`. Negative means the picture is
    /// AHEAD of the audio (slow it down); positive means BEHIND (speed it up).
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

        // Proportional nudge. drift = observed - expected:
        //   drift > 0 → player AHEAD of the audio → slow down (rate < 1).
        //   drift < 0 → player BEHIND the audio → speed up (rate > 1).
        let rawRate = 1.0 - drift * rateGainPerSecond
        let clamped = Float(min(max(rawRate, Double(minRate)), Double(maxRate)))
        return .nudgeRate(clamped)
    }
}
