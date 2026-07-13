// VideoRegionTrim.swift
// Echoelmusic — Sequencer
//
// PURE trim/duration model for a video region — the video analog of AudioClipRegion's
// trim math, expressed against the 480-PPQ tick grid so a trim maps directly onto a
// TimelineRegion (contentOffsetSeconds = trim-in, lengthTicks = trimmed span @bpm).
// Foundation-only, fully unit-testable; the device-side VideoTrackEditor +
// AVAssetImageGenerator scrubber consume it.

import Foundation

/// In/out trim over a video file of known native duration.
public struct VideoRegionTrim: Codable, Sendable, Equatable {
    /// Full media length in seconds (> 0).
    public var nativeDurationSeconds: Double
    /// Trim-in point (seconds from file start), clamped to `[0, native)`.
    public var trimInSeconds: Double
    /// Trim-out point (seconds), always `> trimInSeconds`, clamped to `native`.
    public var trimOutSeconds: Double

    public init(nativeDurationSeconds: Double,
                trimInSeconds: Double = 0,
                trimOutSeconds: Double? = nil) {
        let dur = Swift.max(0.0001, nativeDurationSeconds.isFinite ? nativeDurationSeconds : 0.0001)
        self.nativeDurationSeconds = dur
        let tin = Swift.min(Swift.max(0, trimInSeconds.isFinite ? trimInSeconds : 0), dur - 0.0001)
        self.trimInSeconds = tin
        let rawOut = trimOutSeconds ?? dur
        let tout = rawOut.isFinite ? rawOut : dur
        self.trimOutSeconds = Swift.min(dur, Swift.max(tin + 0.0001, tout))
    }

    private enum CodingKeys: String, CodingKey {
        case nativeDurationSeconds, trimInSeconds, trimOutSeconds
    }

    /// Backward/forward-compatible decode — re-clamps through `init`, never fails.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            nativeDurationSeconds: (try? c.decode(Double.self, forKey: .nativeDurationSeconds)) ?? 1,
            trimInSeconds: (try? c.decode(Double.self, forKey: .trimInSeconds)) ?? 0,
            trimOutSeconds: try? c.decode(Double.self, forKey: .trimOutSeconds))
    }

    /// Trimmed length in seconds (always > 0).
    public var trimmedDurationSeconds: Double { trimOutSeconds - trimInSeconds }

    /// The timeline span (480-PPQ ticks) the trimmed region should occupy at `bpm`.
    /// Real-time video: 1 source-second = 1 transport-second at this tempo.
    public func lengthTicks(atBPM bpm: Double) -> Int {
        guard bpm > 0 else { return 1 }
        let ticks = trimmedDurationSeconds / (60.0 / bpm) * Double(TimelineTime.ticksPerQuarter)
        return Swift.max(1, Int(ticks.rounded()))
    }

    /// Snap a seconds position to the nearest whole frame at `fps` (frame-accurate
    /// handles). `fps <= 0` returns the input unchanged.
    public static func snap(_ seconds: Double, fps: Double) -> Double {
        guard fps > 0, seconds.isFinite else { return Swift.max(0, seconds) }
        let frame = (seconds * fps).rounded()
        return Swift.max(0, frame / fps)
    }

    /// Set trim-in (frame-snapped), keeping out > in.
    public mutating func setTrimIn(_ seconds: Double, fps: Double = 0) {
        let snapped = fps > 0 ? Self.snap(seconds, fps: fps) : seconds
        trimInSeconds = Swift.min(Swift.max(0, snapped), trimOutSeconds - 0.0001)
    }

    /// Set trim-out (frame-snapped), keeping out > in and ≤ native.
    public mutating func setTrimOut(_ seconds: Double, fps: Double = 0) {
        let snapped = fps > 0 ? Self.snap(seconds, fps: fps) : seconds
        trimOutSeconds = Swift.min(nativeDurationSeconds,
                                   Swift.max(trimInSeconds + 0.0001, snapped))
    }
}
