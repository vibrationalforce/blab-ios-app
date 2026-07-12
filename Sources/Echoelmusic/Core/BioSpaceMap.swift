//
//  BioSpaceMap.swift
//  Echoelmusic — Core
//
//  S3 of the Spatial Expansion (Layer 2 "BioSpace"): the pure mapping layer
//  from a live bio frame to a spatial-object TARGET (where in the room the
//  body places the sound). Three distinct presets, each a documented,
//  deterministic formula over existing BioSampleFrame fields — no RNG, no
//  wall clock, no allocation in the step path.
//
//  A slew limiter smooths every axis so an rPPG jitter or breath-phase wrap
//  never teleports the object: angles are limited in °/s (azimuth is
//  WRAP-AWARE — +180° and −180° are the same direction, so the shortest
//  angular path is taken across the seam), distance/gain in units/s.
//
//  Consumers (S5+, flag-gated): feed `step(frame:dt:)` from the existing
//  10 Hz bio poll, write the result into a SpatialScene object, render via
//  ADMOSCSender.send(scene:dialect:) or the future binaural path. NOTHING
//  consumes this yet — Release stays bit-identical (S0 guardrail).
//

import Foundation

/// Where the body currently places the sound — one object's spatial target.
public struct BioSpaceTarget: Sendable, Equatable {
    /// Degrees, -180…180 (ADM convention: 0 front, positive left).
    public var azimuth: Float
    /// Degrees, -90…90.
    public var elevation: Float
    /// Normalized 0…1.
    public var distance: Float
    /// Linear 0…1.
    public var gain: Float

    public init(azimuth: Float, elevation: Float, distance: Float, gain: Float) {
        self.azimuth   = azimuth.isFinite   ? min(max(azimuth, -180), 180) : 0
        self.elevation = elevation.isFinite ? min(max(elevation, -90), 90) : 0
        self.distance  = distance.isFinite  ? min(max(distance, 0), 1)     : 0.5
        self.gain      = gain.isFinite      ? min(max(gain, 0), 1)         : 0.5
    }

    /// The neutral resting place: front, ear height, mid-distance.
    public static let front = BioSpaceTarget(azimuth: 0, elevation: 0, distance: 0.5, gain: 0.7)
}

/// The three body→room mappings. Each reads DIFFERENT dominant fields so
/// switching presets is audibly a different choreography, not a re-tint.
public enum BioSpacePreset: String, Codable, CaseIterable, Sendable {
    /// Breath sweeps the object around the listener (the shipping ADM bio
    /// mapping, made explicit): breath phase → full azimuth circle,
    /// HRV lifts, coherence pulls close, motion brings it forward.
    case breathOrbit
    /// Coherence is altitude: rising coherence lifts the object toward the
    /// zenith and pulls it in — the "calm ascends" choreography.
    case coherenceRise
    /// The still center: the object rests in front; calm (HRV) draws it
    /// near, stillness (low motion) lets it settle and quieten gently.
    case calmCenter

    public var displayName: String {
        switch self {
        case .breathOrbit:   return "Breath Orbit"
        case .coherenceRise: return "Coherence Rise"
        case .calmCenter:    return "Calm Center"
        }
    }
}

/// Deterministic bio→space state machine with per-axis slew limiting.
public struct BioSpaceMap: Sendable {

    public var preset: BioSpacePreset
    /// Angular slew limit (azimuth + elevation), degrees per second.
    public var maxDegreesPerSecond: Float
    /// Distance/gain slew limit, units per second.
    public var maxUnitsPerSecond: Float

    /// Current (slewed) output; nil until the first voiced frame arrives.
    private var current: BioSpaceTarget?

    public init(preset: BioSpacePreset = .breathOrbit,
                maxDegreesPerSecond: Float = 90,
                maxUnitsPerSecond: Float = 1.0) {
        self.preset = preset
        self.maxDegreesPerSecond = (maxDegreesPerSecond.isFinite && maxDegreesPerSecond > 0)
            ? maxDegreesPerSecond : 90
        self.maxUnitsPerSecond = (maxUnitsPerSecond.isFinite && maxUnitsPerSecond > 0)
            ? maxUnitsPerSecond : 1.0
    }

    /// Advance one poll tick. `frame` nil (no bio) holds the last position —
    /// the object stays where the body left it rather than snapping home.
    /// The FIRST frame jumps directly to its target (there is no meaningful
    /// origin to slew from), every later frame is slew-limited.
    public mutating func step(frame: BioSampleFrame?, dt: Double) -> BioSpaceTarget {
        let safeDt = Float((dt.isFinite && dt > 0) ? min(dt, 1.0) : 0.1)
        guard let frame else { return current ?? .front }
        let target = Self.target(for: frame, preset: preset)
        guard let from = current else {
            current = target
            return target
        }
        let maxAngle = maxDegreesPerSecond * safeDt
        let maxUnit  = maxUnitsPerSecond * safeDt
        let next = BioSpaceTarget(
            azimuth:   Self.slewAngleWrapped(from: from.azimuth, to: target.azimuth, maxStep: maxAngle),
            elevation: Self.slewLinear(from: from.elevation, to: target.elevation, maxStep: maxAngle),
            distance:  Self.slewLinear(from: from.distance, to: target.distance, maxStep: maxUnit),
            gain:      Self.slewLinear(from: from.gain, to: target.gain, maxStep: maxUnit))
        current = next
        return next
    }

    /// Forget the slew state (source change / preset switch hard-cut).
    public mutating func reset() { current = nil }

    // MARK: - Pure preset formulas (exposed for tests)

    public static func target(for f: BioSampleFrame, preset: BioSpacePreset) -> BioSpaceTarget {
        let breath = sanitized(f.breathPhase, fallback: 0.5)
        let hrv = sanitized(f.hrvNormalized, fallback: 0.5)
        let coherence = sanitized(f.coherence, fallback: 0.5)
        let motion = sanitized(f.motionEnergy, fallback: 0)
        switch preset {
        case .breathOrbit:
            return BioSpaceTarget(
                azimuth: (breath * 2 - 1) * 180,
                elevation: hrv * 30,
                distance: 1 - coherence * 0.7,
                gain: 0.4 + motion * 0.6)
        case .coherenceRise:
            return BioSpaceTarget(
                azimuth: (hrv * 2 - 1) * 45,
                elevation: coherence * 90 - 10,
                distance: 1 - coherence,
                gain: 0.5 + coherence * 0.5)
        case .calmCenter:
            return BioSpaceTarget(
                azimuth: 0,
                elevation: 0,
                distance: 1 - hrv * 0.8,
                gain: 0.5 + (1 - motion) * 0.3)
        }
    }

    // MARK: - Slew primitives (exposed for tests)

    /// Linear move toward the target, at most `maxStep` per call.
    static func slewLinear(from: Float, to: Float, maxStep: Float) -> Float {
        let delta = to - from
        if abs(delta) <= maxStep { return to }
        return from + (delta > 0 ? maxStep : -maxStep)
    }

    /// Wrap-aware angular move: takes the SHORTEST path across the ±180°
    /// seam (+170° → −170° travels 20° through the back, not 340° through
    /// the front), result re-wrapped into −180…180.
    static func slewAngleWrapped(from: Float, to: Float, maxStep: Float) -> Float {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        let step = abs(delta) <= maxStep ? delta : (delta > 0 ? maxStep : -maxStep)
        var next = (from + step).truncatingRemainder(dividingBy: 360)
        if next > 180 { next -= 360 }
        if next < -180 { next += 360 }
        return next
    }

    private static func sanitized(_ v: Float, fallback: Float) -> Float {
        v.isFinite ? min(max(v, 0), 1) : fallback
    }
}
