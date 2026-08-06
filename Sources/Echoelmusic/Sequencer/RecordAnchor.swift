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

    /// The armed, CAPTURABLE lanes in `doc`, in document (lane) order. A lane is a
    /// target only when it is `isArmed` AND its source is `captureImplemented`
    /// (CLIP-2: an armed mic/video lane used to count as a target, which enabled
    /// the global Record button and ran a take that silently committed nothing —
    /// TakeRecorder has no audio/video recorder yet, task #13). A pure visual
    /// lane (`.none`) is never a target even if armed. Deterministic — the
    /// result order follows `doc.lanes`.
    public static func targets(in doc: TimelineDocument) -> [(laneID: UUID, source: RecordSource)] {
        doc.lanes.compactMap { lane in
            guard lane.isArmed else { return nil }
            let source = lane.recordSource
            guard source.captureImplemented else { return nil }
            return (laneID: lane.id, source: source)
        }
    }

    /// Every ARMED lane whose source is `.audioInput`, in document order. Used
    /// internally by the (flag-gated) audio-capture wiring — task #13,
    /// PLAN_AUDIO_LANE_RECORDING_2026-07-21.md — to find a lane that requested a
    /// mic take, independent of `captureImplemented`/`targets` (which stay the
    /// honest, user-facing "will this actually run a take" gate for the Record
    /// button; this helper does not change that promise). Today's recorder
    /// captures a single mic stream, so a caller consults only the first result —
    /// any further armed audio lanes are silently not captured (a documented
    /// single-lane limit, not a bug).
    public static func armedAudioLaneIDs(in doc: TimelineDocument) -> [UUID] {
        doc.lanes.filter { $0.isArmed && $0.recordSource == .audioInput }.map(\.id)
    }
}

/// Normalize a live bio reading into a flash-safe, UI-friendly 0…1 control value
/// for the bio automation lane (pure — no engine, no clock). Blends a heart-rate
/// term and a breath-rate term against calm-to-active physiological ranges and
/// clamps hard to 0…1 so downstream mapping can never over-drive.
///
/// ⛔ THE BREATH FLOOR WAS 6.0 AND THAT WAS THE ONE RATE THE APP ITSELF ASKS FOR (#433).
/// `BreathPacer.defaultRate` is EXACTLY 6.0 and the pacer's whole range is 5…12 — so a user
/// following Echoel's own resonance guide sat on the floor and the breath term read exactly 0,
/// while the coached band's slow half (5…6) had no travel at all. A floor that swallows the
/// paced target is not a calm reference, it is a blind spot at the one place the product aims.
///
/// ⭐ WHY 3.0 AND WHY IT IS A LITERAL. It is the low bound of `BioSampleFrame
/// .plausibleBreathRate` — the set of rates that can arrive here at all — so every admitted
/// slow breath now spends depth instead of pinning. It stays a LITERAL rather than a reference
/// because this is an AROUSAL window, not a validity test: the two happen to agree today, and
/// the day the gate widens is a day someone should decide about arousal on purpose, not inherit
/// it. `Tests/CISmoke/TheArousalFloorSitsBelowThePacedBreathTests` chains it to
/// `BreathPacer.minRate` so the floor can never climb back above a paced rate unnoticed.
///
/// ⚠️ THE TOP IS DELIBERATELY NARROWER THAN THE GATE and is NOT moved. 24/min is an active
/// ceiling; the gate admits 40. Widening it to 40 would cost every realistic rate a flat ~43 %
/// of its travel (the ratio 21/37 is the same at every rate) to buy resolution for panting —
/// the same asymmetry, and the same refusal, as `ModSource.breathRate.range` (#429).
///
/// ⭐ AN UNMEASURED BREATH IS NO LONGER BLENDED IN AS CALM. `EngineBus.usableBio()` gates on
/// FRESHNESS only, not on `hasMeasuredBreath`, so a BLE-strap frame arrives here with
/// `breathRate: 0` — and a fabricated 0 used to halve the arousal value, indistinguishable from
/// a genuinely very slow breather. This is exactly the argument #215 used to stop sending
/// `/bio/motion`. When there is no breath measurement the heart term stands alone.
///
/// ⚠️ THIS PATH IS DORMANT TODAY and the fix is worth making BECAUSE of that, not in spite of
/// it. `RecordController.onStep` opens with `guard armed else { return }`, `arm()` has zero
/// callers in `Sources/`, and task #204 records RecordController as doorless. A review report
/// called this "the shipped capture path"; it is not. Repairing arithmetic while nothing rides
/// on it is free — the same repair after a door exists would need a device listen.
///
/// - Parameters:
///   - bpm: heart rate in beats per minute (typical resting ~50, active ~120).
///   - breathRate: breaths per minute — a MEASUREMENT, or anything outside
///     `BioSampleFrame.plausibleBreathRate` (0 included) to say "no breath reading".
/// - Returns: a value clamped to 0…1 (0 = calm floor, 1 = active ceiling).
public func bioNormalized(bpm: Double, breathRate: Double) -> Float {
    // Calm → active reference windows. Below the floor reads 0, above the top reads 1.
    let hrFloor = 50.0, hrTop = 120.0
    let brFloor = 3.0, brTop = 24.0

    let hr = normalize01(bpm, floor: hrFloor, top: hrTop)

    // No breath measurement → the heart term alone, never a fabricated calm.
    guard measuresBreath(breathRate) else { return Float(clamp01(hr)) }
    let br = normalize01(breathRate, floor: brFloor, top: brTop)

    // Equal blend of the two arousal terms; already in 0…1, clamp for safety.
    let blended = (hr + br) * 0.5
    return Float(clamp01(blended))
}

// MARK: - Private math helpers (pure)

/// Is this a breath READING at all? Reuses the repo's single answer to that question
/// (`BioSampleFrame.plausibleBreathRate`, the same set `hasMeasuredBreath` tests) rather than
/// minting a second definition of "plausible" — that duplication is the #416 defect. Non-finite
/// is never a measurement.
private func measuresBreath(_ rate: Double) -> Bool {
    guard rate.isFinite else { return false }
    return BioSampleFrame.plausibleBreathRate.contains(Float(rate))
}

private func normalize01(_ value: Double, floor: Double, top: Double) -> Double {
    guard top > floor else { return 0 }
    return clamp01((value - floor) / (top - floor))
}

private func clamp01(_ value: Double) -> Double {
    if value.isNaN { return 0 }
    return Swift.max(0, Swift.min(1, value))
}
