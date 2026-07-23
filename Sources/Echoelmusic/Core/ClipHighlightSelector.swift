//
//  ClipHighlightSelector.swift
//  Echoelmusic — Core
//
//  EchoelPublish slice 1 — the algorithmic heart of vision law #1 ("every session
//  spits out a shareable 15-second clip"): given a session's energy timeline, pick the
//  most ALIVE fixed-length window to become that clip. Today the recorder simply grabs
//  the LAST N seconds of the master mix (RetroCapture ring); that is often not the best
//  moment. This chooses the window with the most integrated liveliness instead.
//
//  PURE + deterministic + Foundation-only. It runs POST-HOC (after a recording, on the
//  main thread) — NOT on the audio render thread — so an allocation (the defensive sort)
//  is fine here. The caller supplies whatever liveliness signal it has (audio RMS and/or
//  bio intensity, already normalized); this file is signal-agnostic. WIRING — what feeds
//  the samples, and how the returned window drives the recorder/export — is a separate
//  slice (named target: VisualRecorder's window choice) and is intentionally NOT done here.
//
//  No Core/Sequencer coupling, no external dependency, no health claim.
//

import Foundation

/// Selects the best fixed-length window of a recorded session for the shareable clip.
public enum ClipHighlightSelector {

    /// One liveliness reading on the session timeline.
    public struct Sample: Equatable {
        /// Seconds from session start. Ascending is expected but not required — the
        /// selector sorts defensively.
        public let time: Double
        /// Liveliness at `time` (e.g. audio RMS + bio intensity, normalized ≥ 0). A
        /// non-finite or negative value is treated as 0 so a garbage spike can never win.
        public let energy: Float
        public init(time: Double, energy: Float) {
            self.time = time
            self.energy = energy
        }
    }

    /// A chosen clip window — the continuous span `[start, end]` in seconds from session
    /// start (a recorder captures a continuous span, so the boundary instant is immaterial).
    /// `end` is always ≤ the session's last sample time (the window never references audio
    /// beyond the recording).
    public struct Window: Equatable {
        public let start: Double
        public let end: Double
        public init(start: Double, end: Double) {
            self.start = start
            self.end = end
        }
        public var duration: Double { end - start }
    }

    /// The most-alive `length`-second window of `samples`.
    ///
    /// - Returns: `nil` when `samples` is empty. When the whole session is shorter than
    ///   `length` (or `length` is non-positive), returns the entire session span so the
    ///   caller still gets a usable clip. Otherwise returns the `length`-second window
    ///   maximizing the summed liveliness; ties resolve to the EARLIEST such window
    ///   (deterministic).
    /// - Parameters:
    ///   - samples: liveliness timeline (any order; sorted internally).
    ///   - length: desired clip length in seconds (default 15 — the vision's clip length).
    public static func bestWindow(samples: [Sample], length: Double = 15) -> Window? {
        // Drop samples with a non-finite timestamp (a bad clock reading) BEFORE any time
        // arithmetic — a NaN time would poison min/max/span (NaN comparisons are all false).
        // Consistent with the energy sanitization below. Sorting here is post-hoc/main-thread,
        // so the allocation is fine; first/last then give the span with no extra passes.
        let sorted = samples.filter { $0.time.isFinite }.sorted { $0.time < $1.time }
        guard let firstTime = sorted.first?.time, let lastTime = sorted.last?.time else { return nil }

        // Degenerate / short session: the whole span IS the clip.
        guard length > 0, lastTime - firstTime > length else {
            return Window(start: firstTime, end: lastTime)
        }

        // Two-pointer sliding window: for each sample as the window's right edge, keep the
        // left edge no further back than `length`, tracking the max running liveliness. This
        // is O(n) and provably finds the global max-sum `length`-window (every optimal window
        // can be slid so its samples all fall inside a two-pointer window ending at a sample).
        func clean(_ e: Float) -> Float { (e.isFinite && e > 0) ? e : 0 }

        var bestScore = -Float.greatestFiniteMagnitude
        var bestStart = firstTime
        var lo = 0
        var running: Float = 0

        for hi in sorted.indices {
            running += clean(sorted[hi].energy)
            while sorted[hi].time - sorted[lo].time > length {
                running -= clean(sorted[lo].energy)
                lo += 1
            }
            if running > bestScore {           // strict `>` ⇒ ties keep the EARLIEST window
                bestScore = running
                bestStart = sorted[lo].time
            }
        }

        // Keep the window fully inside the recording. With non-uniform spacing the winning
        // left-anchor sample can sit later than `lastTime - length`, which would push `end`
        // past the session end (referencing audio that was never recorded). Pulling `start`
        // back to at most `lastTime - length` keeps the full `length` and ends ≤ lastTime;
        // `start` stays ≥ firstTime because `lastTime - length > firstTime` in this branch.
        let clampedStart = Swift.min(bestStart, lastTime - length)
        return Window(start: clampedStart, end: clampedStart + length)
    }
}
