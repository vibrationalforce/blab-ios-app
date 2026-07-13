//
//  BioPhaser.swift
//  Echoelmusic — Sync (EchoelLux L3)
//
//  An MA3-style PHASER over a fixture group: each fixture gets a fanned phase OFFSET
//  across the group while the BASE phase is driven by the body — breath phase directly,
//  or a heart phase integrated from heart rate. The per-fixture output is a unit
//  luminance that feeds the dimmer, so this is the flash-safety HOT PATH:
//
//    1. the base ADVANCE rate is clamped to WCAG-safe ≤3 Hz (FlashGuard.safeFrequency),
//       so even a 200 bpm heart can't drive the phase faster than three cycles/second, and
//    2. every per-fixture per-tick luminance step is slew-limited (FlashGuard.limitedLuminance),
//       so a fast base can only ever produce a low-amplitude wobble, never a full strobe.
//
//  Pure + deterministic (no RNG, no wall clock — `dt` is passed in), value-type state,
//  mirrors BioSpaceMap: a nil frame HOLDS the last output (a stalled bio stream freezes
//  the look, it does not snap to black), the first frame lands directly (no origin to
//  ramp from), NaN/inf are sanitized. NOTHING consumes this yet — Release bit-identical.
//

import Foundation

/// What drives the phaser's base phase.
public enum BioPhaserSource: String, Codable, CaseIterable, Sendable {
    /// Base phase = the frame's breath phase (already 0…1, slow — never a flash risk).
    case breath
    /// Base phase = ∫ (heartRateBPM/60)·dt, wrapped to [0,1), advance-clamped to ≤3 Hz.
    case heart
}

/// Deterministic bio→phaser state machine with per-fixture luminance slew limiting.
public struct BioPhaser: Sendable {

    /// Maximum luminance change per SECOND for the per-fixture slew — the rate bound is
    /// deliberately per-second, NOT per-tick, so it is invariant to poll rate. A WCAG
    /// flash needs a ≥0.10 luminance swing, so a full up-down PAIR traverses ≥0.20;
    /// capping the velocity at 0.5/s makes a pair take ≥0.4 s → ≤2.5 pairs/s, safely under
    /// the 3 Hz ceiling for ANY poll rate. (A per-TICK cap would let a fast poll sneak
    /// extra flashes through — and the breath source has no frequency clamp of its own —
    /// so the rate guarantee has to live here.)
    public static let maxLuminancePerSecond: Double = 0.5

    public var source: BioPhaserSource
    /// Number of fixtures in the fan.
    public var count: Int
    /// How far the phase fans across the group, 0…1 (1 = a full cycle spread over the rig).
    public var spread: Float

    /// Accumulated heart phase, [0,1). Exposed read-only for tests/telemetry.
    public private(set) var heartPhase: Float = 0
    /// Last slewed per-fixture output; nil until the first frame (no origin to ramp from).
    private var lastOutputs: [Float]?

    public init(source: BioPhaserSource = .breath, count: Int = 1, spread: Float = 1) {
        self.source = source
        self.count = Swift.max(0, count)
        self.spread = spread.isFinite ? Swift.min(Swift.max(spread, 0), 1) : 1
    }

    /// Advance one poll tick, returning one unit luminance [0,1] per fixture. `frame`
    /// nil holds the last output (a stalled body freezes the look). Deterministic.
    public mutating func step(frame: BioSampleFrame?, dt: Double) -> [Float] {
        let n = Swift.max(0, count)
        guard n > 0 else { return [] }
        guard let frame else { return lastOutputs ?? [Float](repeating: 0, count: n) }

        let safeDt = Float((dt.isFinite && dt > 0) ? Swift.min(dt, 1.0) : 0.1)

        // Base phase [0,1).
        let base: Float
        switch source {
        case .breath:
            base = Self.sanitized01(frame.breathPhase, fallback: 0)
        case .heart:
            let bpm = frame.heartRateBPM.isFinite ? Swift.max(0, frame.heartRateBPM) : 0
            // Clamp the phase ADVANCE frequency to ≤3 Hz BEFORE integrating — the first
            // flash-safety guarantee (a 200 bpm heart advances at 3 Hz, not 3.33 Hz).
            let phaseHz = Float(FlashGuard.safeFrequency(Double(bpm) / 60.0))
            heartPhase = Self.wrap01(heartPhase + phaseHz * safeDt)
            base = heartPhase
        }

        // Per-tick cap derived from the per-SECOND velocity, so the flash-rate bound holds
        // at any poll rate (this is what makes the breath source — which has no frequency
        // clamp — flash-safe too, not just heart).
        let maxStep = Self.maxLuminancePerSecond * Double(safeDt)
        let offsets = Self.phaseOffsets(count: n, spread: spread)
        var out = [Float](repeating: 0, count: n)
        let prev = lastOutputs
        for i in 0..<n {
            let raw = Self.value(bioPhase: base, offset: offsets[i])
            if let prev, i < prev.count {
                // Second flash-safety guarantee: slew-limit every per-fixture step so a
                // fast base can never strobe a fixture — it can only wobble slowly.
                out[i] = Float(FlashGuard.limitedLuminance(from: Double(prev[i]), to: Double(raw),
                                                           maxDelta: maxStep))
            } else {
                out[i] = raw    // first frame lands directly (mirrors BioSpaceMap)
            }
        }
        lastOutputs = out
        return out
    }

    /// Forget the slew + phase state (source/preset change hard-cut).
    public mutating func reset() { lastOutputs = nil; heartPhase = 0 }

    // MARK: - Pure formulas (exposed for tests)

    /// Even phase fan across the group: fixture i sits at `spread · i / count` of a cycle.
    /// Edge cases: 0 fixtures → empty; 1 fixture → [0] (nothing to fan).
    public static func phaseOffsets(count: Int, spread: Float) -> [Float] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [0] }
        let s = spread.isFinite ? Swift.min(Swift.max(spread, 0), 1) : 1
        return (0..<count).map { s * Float($0) / Float(count) }
    }

    /// Unit luminance for a phase + offset: `0.5 + 0.5·sin(2π(phase+offset))`.
    public static func value(bioPhase: Float, offset: Float) -> Float {
        0.5 + 0.5 * sin(2 * Float.pi * (bioPhase + offset))
    }

    // MARK: - Helpers

    static func sanitized01(_ v: Float, fallback: Float) -> Float {
        v.isFinite ? Swift.min(Swift.max(v, 0), 1) : fallback
    }

    static func wrap01(_ v: Float) -> Float {
        guard v.isFinite else { return 0 }
        let f = v.truncatingRemainder(dividingBy: 1)
        return f < 0 ? f + 1 : f
    }
}
