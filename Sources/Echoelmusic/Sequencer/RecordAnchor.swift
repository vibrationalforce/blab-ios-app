// RecordAnchor.swift
// Echoel — B17. A PURE recording time-map + capture plan.
//
// When a take starts, the transport is at some song-absolute tick and the audio
// clock is at some sample time. RecordAnchor pins those two together so any later
// sample time (or elapsed seconds) can be converted back to a song-absolute
// 480-PPQ content tick — the coordinate the timeline already uses (see
// `TimelineTime`). This is the deterministic math the per-source capture engine
// rides; it never touches AVFoundation, the audio thread, or wall-clock time.
//
// PURE value types only (Foundation). No Date()/random/UUID() in logic — the
// anchor is handed its start sample time + start tick by the caller.

import Foundation

/// A fixed point tying the audio sample clock to the musical (tick) clock at the
/// instant a recording take begins. All conversions are CONSTANT-TEMPO: `bpm`
/// does not change over the take, so `startTick + secondsToTicks(elapsed)` is an
/// exact linear map (no tempo automation — that is a later, higher-layer concern).
public struct RecordAnchor: Sendable, Equatable, Codable {
    /// The audio-render sample time captured at take start (frames since the
    /// engine's timeline origin). Later sample times are measured against this.
    public var startSampleTime: Int64
    /// The song-absolute 480-PPQ content tick the transport was at, at take start.
    public var startTick: Int
    /// Audio sample rate in Hz (e.g. 44100, 48000). Used to turn a sample delta
    /// into seconds. Must be > 0 for meaningful conversion.
    public var sampleRate: Double
    /// Musical tempo in beats per minute, held constant for the whole take.
    public var bpm: Double

    /// Create an anchor. All fields are supplied by the caller (deterministic —
    /// the anchor never reads a clock itself).
    public init(startSampleTime: Int64, startTick: Int, sampleRate: Double, bpm: Double) {
        self.startSampleTime = startSampleTime
        self.startTick = startTick
        self.sampleRate = sampleRate
        self.bpm = bpm
    }

    /// Seconds elapsed from the anchor to `sampleTime`. Guards a non-positive
    /// sample rate (returns 0). A sample time earlier than the anchor yields a
    /// negative value (honest — the caller decides whether that is valid).
    public func seconds(forSampleTime sampleTime: Int64) -> Double {
        guard sampleRate > 0 else { return 0 }
        let deltaFrames = Double(sampleTime - startSampleTime)
        return deltaFrames / sampleRate
    }

    /// The song-absolute content tick for a given audio sample time (constant
    /// tempo). Rounds to the nearest tick. Guards: a non-positive sample rate or
    /// tempo collapses the map to `startTick`.
    public func tick(forSampleTime sampleTime: Int64) -> Int {
        guard sampleRate > 0, bpm > 0 else { return startTick }
        return tick(afterSeconds: seconds(forSampleTime: sampleTime))
    }

    /// The song-absolute content tick `elapsed` seconds after take start
    /// (CONSTANT tempo). One quarter = `TimelineTime.ticksPerQuarter` ticks and
    /// lasts `60 / bpm` seconds, so ticks-per-second = ppq * bpm / 60. Rounds to
    /// the nearest tick; guards a non-positive tempo (returns `startTick`).
    public func tick(afterSeconds elapsed: Double) -> Int {
        guard bpm > 0 else { return startTick }
        let ticksPerSecond = Double(TimelineTime.ticksPerQuarter) * bpm / 60.0
        let delta = (elapsed * ticksPerSecond).rounded()
        return startTick + Int(delta)
    }
}

/// A pure planner: given a timeline document, which lanes will actually capture on
/// the next take, and what each one records. No side effects — the capture engine
/// consults this to wire its per-source recorders.
public enum RecordPlan {

    /// The armed, recordable lanes in `doc`, in document (lane) order. A lane is a
    /// target only when it is `isArmed` AND its `recordSource.canRecord` (a pure
    /// visual lane, `.none`, is never a target even if armed). Deterministic — the
    /// result order follows `doc.lanes`.
    public static func targets(in doc: TimelineDocument) -> [(laneID: UUID, source: RecordSource)] {
        doc.lanes.compactMap { lane in
            guard lane.isArmed else { return nil }
            let source = lane.recordSource
            guard source.canRecord else { return nil }
            return (laneID: lane.id, source: source)
        }
    }
}

/// Normalize a live bio reading into a flash-safe, UI-friendly 0…1 control value
/// for the bio automation lane (pure — no engine, no clock). Blends a heart-rate
/// term and a breath-rate term against calm-to-active physiological ranges and
/// clamps hard to 0…1 so downstream mapping can never over-drive.
///
/// - Parameters:
///   - bpm: heart rate in beats per minute (typical resting ~50, active ~120).
///   - breathRate: breaths per minute (typical resting ~6, active ~24).
/// - Returns: a value clamped to 0…1 (0 = calm floor, 1 = active ceiling).
public func bioNormalized(bpm: Double, breathRate: Double) -> Float {
    // Calm → active reference windows. Below the floor reads 0, above the top reads 1.
    let hrFloor = 50.0, hrTop = 120.0
    let brFloor = 6.0, brTop = 24.0

    let hr = normalize01(bpm, floor: hrFloor, top: hrTop)
    let br = normalize01(breathRate, floor: brFloor, top: brTop)

    // Equal blend of the two arousal terms; already in 0…1, clamp for safety.
    let blended = (hr + br) * 0.5
    return Float(clamp01(blended))
}

// MARK: - Private math helpers (pure)

private func normalize01(_ value: Double, floor: Double, top: Double) -> Double {
    guard top > floor else { return 0 }
    return clamp01((value - floor) / (top - floor))
}

private func clamp01(_ value: Double) -> Double {
    if value.isNaN { return 0 }
    return Swift.max(0, Swift.min(1, value))
}
