// StepTickMath.swift
// Echoel — ULTRASYNC slice 2: the tick source a LIVE touch needs (founder 2026-07-28,
// "damit das Touch Instrument immer perfekt im timing ist auch microtime").
//
// WHAT WAS MISSING. `TouchQuantizer` (slice 1) decides what to do with a touch AT a
// 480-PPQ tick. Nothing in the touch path knew that tick. The transport's `position`
// is the only musical clock reachable there, and it moves once per SIXTEENTH — 120
// ticks at 480 PPQ. Fed straight into the quantizer, every touch inside a step would
// read as landing exactly ON that step: offset 0, correction never fires, the feature
// is a no-op. A quantizer needs to know HOW FAR PAST the last grid point the finger
// landed, which is sub-step information the step counter does not carry.
//
// SO THIS INTERPOLATES: last step boundary (a wall-clock stamp) + elapsed seconds +
// tempo → the tick under the finger. Straight-line, constant-tempo, exactly the map
// `RecordAnchor.tick(afterSeconds:)` already uses for recording — but anchored to a
// STEP rather than to a take, because a live player has no take.
//
// THE CLAMP IS THE WHOLE SAFETY STORY. A step stamp can be late: the sequencer's
// timer jitters, the app is backgrounded, a step is missed under load. Without a
// bound, "elapsed" then keeps growing and the interpolation walks into steps that
// have not happened, quantizing a touch against a bar the player is not in — silently,
// with no way for the caller to tell. Held inside its own step, the worst a stale
// stamp can produce is "late in this step", which the quantizer already handles as
// an ordinary late note.
//
// Pure value math — Foundation only, no clock read of its own (`now` is always handed
// in), so every boundary here is unit-tested on CI without an audio or UI stack. The
// same law as `RollFitMath`, `AutomationCanvasMath` and `TouchQuantizer` itself.

import Foundation

/// Turns a step-quantized transport position plus elapsed wall-clock time into a
/// song-absolute 480-PPQ tick.
public enum StepTickMath {

    /// Ticks per sixteenth step. Deliberately NOT a new constant: `TimelineTime` already
    /// owns this number, and a second definition here would be a second source of truth
    /// for the one value the grid, the exporter and this interpolation all have to agree
    /// on. `StepTickMathTests` pins it against `Transport.stepsPerBeat` so the two cannot
    /// drift apart unnoticed.
    public static var ticksPerStep: Int { TimelineTime.ticksPerTransportStep }

    /// The song-absolute tick for a touch that landed `secondsSinceStep` after the
    /// boundary of step `absoluteStep`.
    ///
    /// - Parameters:
    ///   - absoluteStep: steps since play started (`bar * 16 + step`). Negative reads
    ///     as 0 — a position before the start is not a musical location.
    ///   - secondsSinceStep: elapsed since that step boundary. Non-finite, negative or
    ///     over-long values collapse to the step boundary or its last tick (see above).
    ///   - bpm: musical tempo, held constant across the one step being interpolated.
    ///     Non-finite or non-positive returns the step boundary itself.
    /// - Returns: the tick under the finger, always within `[stepTick, stepTick + ticksPerStep - 1]`.
    public static func tick(absoluteStep: Int, secondsSinceStep: Double, bpm: Double) -> Int {
        // Clamped at BOTH ends before the multiply: negative is not a musical location,
        // and an absurd step count would overflow the multiplication into a trap. Neither
        // is reachable from a running transport — they are reachable from a corrupt
        // restore or a future caller, and a trap here would kill the app on a touch.
        let step = Swift.min(Swift.max(0, absoluteStep), Int.max / Swift.max(1, ticksPerStep))
        let base = step * ticksPerStep
        guard bpm.isFinite, bpm > 0,
              secondsSinceStep.isFinite, secondsSinceStep > 0 else { return base }

        let ticksPerSecond = Double(TimelineTime.ticksPerQuarter) * bpm / 60.0
        let raw = (secondsSinceStep * ticksPerSecond).rounded()
        // Bound BEFORE the Int conversion, not after: `raw` is unbounded (a stale stamp
        // or an absurd tempo makes it astronomically large) and converting that to Int
        // first would trap. `Swift.min` on the Double is total.
        let within = Swift.min(Double(ticksPerStep - 1), raw)
        return base + Int(within)
    }
}
