//
//  SessionGuide.swift
//  Echoelmusic — Bio
//
//  The closed-loop GUIDE LAW of the bio-paced Session (warm-restart cycle 2).
//  Given how long the session has run and how the body is responding, it returns
//  the breathing pace (breaths per minute) the user is gently guided toward — the
//  expanding/contracting cue the tone and the flash-safe light follow.
//
//  The maneuver is the one that the evidence supports (deep research 2026-07-05):
//  ease the breath DOWN from the person's natural rate toward their personal
//  resonance frequency (~4.5–7/min), where heart and breath couple through the
//  baroreflex and short-term parasympathetic (calming) activity rises. It is a
//  GUIDE, not a metronome:
//   • it starts at the user's own measured pace, never a jarring jump;
//   • it eases with a smooth (smoothstep) descent over `descentSeconds`;
//   • it BACKS OFF when the body isn't following — low coherence holds the pace
//     closer to natural, so we never over-slow someone who can't keep up.
//
//  Pure value type + pure math: deterministic, unit-tested, no allocation, safe to
//  evaluate anywhere. Self-observation and self-regulation, NOT therapy or
//  diagnosis — Echoel guides the breath; the body does the rest.
//

import Foundation

public struct SessionGuide: Sendable, Equatable {

    /// Safe pace bounds (breaths/min). The floor matches EntrainmentEngine's resonance
    /// window; the ceiling caps the shown pace so a noisy breath estimate can't drive
    /// an absurdly fast cue.
    public static let paceFloor: Double = EntrainmentEngine.minBreathsPerMinute   // 4.5
    public static let paceCeiling: Double = 20.0
    /// The canonical resonance target when a personalized one isn't known yet.
    public static let defaultResonancePace: Double = 6.0
    /// Default time to ease from the natural start pace to the resonance target.
    public static let defaultDescentSeconds: Double = 180.0

    /// Where guidance begins — the user's own comfortable pace (clamped safe).
    public let startPace: Double
    /// The personal resonance target to ease toward (from ResonanceFinder if known,
    /// else the canonical 6/min), clamped into the resonance window.
    public let resonancePace: Double
    /// How long the eased descent takes, seconds (> 0).
    public let descentSeconds: Double

    /// Build a guide from the user's measured natural breathing rate and an optional
    /// personalized resonance pace. All inputs are clamped/guarded so the guide is
    /// always well-formed.
    public init(measuredBreathsPerMinute: Double,
                resonancePace: Double? = nil,
                descentSeconds: Double = SessionGuide.defaultDescentSeconds) {
        let start = SessionGuide.clampPace(measuredBreathsPerMinute,
                                           fallback: 12.0,
                                           lower: SessionGuide.paceFloor,
                                           upper: SessionGuide.paceCeiling)
        // Resonance target lives in the tighter evidence window [4.5, 7].
        let res = SessionGuide.clampPace(resonancePace ?? SessionGuide.defaultResonancePace,
                                         fallback: SessionGuide.defaultResonancePace,
                                         lower: EntrainmentEngine.minBreathsPerMinute,
                                         upper: EntrainmentEngine.maxBreathsPerMinute)
        // Never guide the user UP: if they already breathe slower than the target,
        // hold them where they are (the target becomes their current pace).
        self.startPace = Swift.max(start, res)
        self.resonancePace = res
        self.descentSeconds = (descentSeconds.isFinite && descentSeconds > 0)
            ? descentSeconds : SessionGuide.defaultDescentSeconds
    }

    /// The breaths-per-minute the user is guided toward at `elapsed` seconds into the
    /// session, given the current `coherence` (0…1) as the body's follow signal.
    /// Monotonic non-increasing in time (for fixed coherence); always within the safe
    /// window; eases in with a smoothstep so there is no jerk at t=0.
    public func targetBpm(atSeconds elapsed: Double, coherence: Double) -> Double {
        guard elapsed.isFinite, elapsed > 0 else { return startPace }
        let p = Swift.min(1, Swift.max(0, elapsed / descentSeconds))
        let eased = SessionGuide.smoothstep(p)                       // 0→1, flat ends
        // Follow signal: at coherence 0 apply only 40% of the descent (hold near
        // natural — don't rush an unsettled body); at 1 apply the full descent.
        let c = coherence.isFinite ? Swift.min(1, Swift.max(0, coherence)) : 0
        let responsiveness = 0.4 + 0.6 * c
        let descent = (startPace - resonancePace) * eased * responsiveness
        let pace = startPace - descent
        return SessionGuide.clampPace(pace, fallback: resonancePace,
                                      lower: resonancePace, upper: startPace)
    }

    /// The target as a frequency (Hz) — breath pace / 60. Always flash-safe (breath
    /// paces are far below any flicker concern), fed straight to EntrainmentEngine.plan.
    public func targetHz(atSeconds elapsed: Double, coherence: Double) -> Double {
        targetBpm(atSeconds: elapsed, coherence: coherence) / 60.0
    }

    // MARK: - Pure helpers

    /// Hermite smoothstep on [0,1] — 0 and 1 with zero slope at the ends (no jerk).
    public static func smoothstep(_ x: Double) -> Double {
        let t = Swift.min(1, Swift.max(0, x))
        return t * t * (3 - 2 * t)
    }

    static func clampPace(_ v: Double, fallback: Double, lower: Double, upper: Double) -> Double {
        guard v.isFinite else { return fallback }
        let lo = Swift.min(lower, upper)
        let hi = Swift.max(lower, upper)
        return Swift.min(hi, Swift.max(lo, v))
    }
}
