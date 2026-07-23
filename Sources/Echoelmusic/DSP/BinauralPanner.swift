// BinauralPanner.swift
// Echoel — the spatial-placement core (the "where in the room" dimension), as a
// PURE, deterministic, unit-tested value type (no Accelerate, no AVFoundation, so
// it builds + tests everywhere). It turns ONE position — the SAME
// azimuth/elevation/distance convention Echoel already sends over ADM-OSC
// (ADMOSCSender) — into the three classic binaural cues:
//
//   • ILD (interaural level difference) → per-ear gain via equal-power panning,
//     softened toward centre as the source rises overhead (elevation).
//   • ITD (interaural time difference) → a small inter-ear delay in seconds, from
//     the Woodworth spherical-head model (head radius a, speed of sound c).
//   • Distance → a gain attenuation AND an "air" high-cut (far sources lose highs),
//     the standard distance-modelling pair.
//
// SCOPE: this is the math core only. It is NOT yet in the live render path —
// wiring it (or AVAudioEnvironmentNode / PHASE for true HRTF) into the master
// graph is a later, audio-thread-reviewed + device-verified slice. Building the
// cue model first keeps the founder-approved live sound untouched while the
// binaural placement is validated, and keeps Echoel's spatial output consistent
// across formats: ADM-OSC objects and on-device binaural follow the SAME angle
// convention — positive azimuth = LEFT (CCW). This file lives in DSP/ (compiled in
// isolation for the AUv3), so it cannot import `SpatialPosition`; it mirrors that
// convention by hand and a unit test pins the sign so the two never drift.

import Foundation

/// The three binaural cues for one source position. Pure value type.
public struct BinauralCues: Equatable, Sendable {
    /// Left-ear linear gain, 0…1 (already includes distance attenuation).
    public var leftGain: Float
    /// Right-ear linear gain, 0…1 (already includes distance attenuation).
    public var rightGain: Float
    /// Interaural time difference in seconds. Positive = sound reaches the LEFT
    /// ear first (source on the left); the RIGHT ear is delayed by this amount.
    public var itdSeconds: Float
    /// First-order "air" high-cut in Hz applied to far sources (closer → brighter,
    /// farther → duller). Full bandwidth when close.
    public var airHighCutHz: Float

    public init(leftGain: Float, rightGain: Float, itdSeconds: Float, airHighCutHz: Float) {
        self.leftGain = leftGain
        self.rightGain = rightGain
        self.itdSeconds = itdSeconds
        self.airHighCutHz = airHighCutHz
    }
}

public enum BinauralPanner {

    /// Spherical head radius (m) — average adult ~8.75 cm.
    public static let headRadius: Float = 0.0875
    /// Speed of sound in air (m/s) at room temperature.
    public static let speedOfSound: Float = 343

    /// Map a source position to binaural cues.
    /// - Parameters:
    ///   - azimuthDegrees: −180…+180, 0 = front, positive = left, negative = right
    ///     (the ADM / house convention — the same one `SpatialPosition` documents and
    ///     `ADMOSCSender` sends; breath drives it via the bio convenience below).
    ///   - elevationDegrees: −90…+90, 0 = ear level, positive = above.
    ///   - distanceNorm: 0…1, 0 = at the head, 1 = far (ADM-OSC distance).
    public static func cues(azimuthDegrees: Float,
                            elevationDegrees: Float,
                            distanceNorm: Float) -> BinauralCues {
        let az = clamp(azimuthDegrees, -180, 180) * .pi / 180        // radians
        let el = clamp(elevationDegrees, -90, 90) * .pi / 180
        let dist = clamp(distanceNorm, 0, 1)

        // ILD via equal-power pan. `pan` is right-positive (−1 full left … +1 full
        // right). The house/ADM convention is positive azimuth = LEFT (see
        // SpatialPosition), so azimuth maps in with a SIGN FLIP: +az (left) → pan < 0
        // (louder left ear). The horizontal component (cos elevation) shrinks the L/R
        // imbalance as the source rises overhead, where both ears hear it about equally.
        let pan = -sinf(az) * cosf(el)
        let theta = (pan + 1) * 0.5 * (.pi / 2)                      // 0…π/2
        var left = cosf(theta)
        var right = sinf(theta)

        // Distance attenuation: gentle inverse law, never zero, ≤ 1 at the head.
        let atten = 1 / (1 + 2.5 * dist)
        left *= atten
        right *= atten

        // ITD (Woodworth spherical-head): t = (a/c)(θ + sin θ) for the lateral angle.
        // `pan` is right-positive, so a LEFT source (pan < 0) makes the LEFT ear lead →
        // POSITIVE `itdSeconds` per the struct contract; a RIGHT source (pan > 0) delays
        // the left ear → negative. Elevation folds the lateral angle toward 0 (overhead
        // → no ITD; itdMag is 0 at centre, so the sign branch is a no-op there).
        let lateral = asinf(clamp(pan, -1, 1))                       // −π/2…π/2
        let itdMag = (headRadius / speedOfSound) * (fabsf(lateral) + sinf(fabsf(lateral)))
        let itd = (pan < 0 ? 1 : -1) * itdMag

        // Air high-cut: full band when close, rolling down with distance. 18 kHz
        // near → ~3.5 kHz far (audible "behind glass" damping for far objects).
        let airHighCut = 18_000 - 14_500 * dist

        return BinauralCues(leftGain: left, rightGain: right,
                            itdSeconds: itd, airHighCutHz: airHighCut)
    }

    /// Convenience: drive the panner straight from a bio frame using the exact same
    /// azimuth/elevation/distance mapping `ADMOSCSender` uses, so on-device binaural
    /// and the ADM-OSC object move together. Breath → azimuth, HRV → elevation,
    /// coherence → distance (coherent pulls close).
    public static func cues(breathPhase: Float, hrvNormalized: Float, coherence: Float) -> BinauralCues {
        let azimuth = (clamp(breathPhase, 0, 1) * 2 - 1) * 180
        let elevation = clamp(hrvNormalized, 0, 1) * 60
        let distance = 1 - clamp(coherence, 0, 1)
        return cues(azimuthDegrees: azimuth, elevationDegrees: elevation, distanceNorm: distance)
    }

    private static func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        Swift.min(Swift.max(v, lo), hi)
    }
}
