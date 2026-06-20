//
//  BreathPacer.swift
//  Echoelmusic — Bio
//
//  A resonance-breathing guide: the single best-evidenced HRV intervention
//  (slow paced breathing at ~6 breaths/min / ~0.1 Hz raises respiratory sinus
//  arrhythmia, baroreflex gain, and vagally-mediated HRV — Lehrer & Gevirtz).
//  This is the active half of the coherence loop that HRVCoherence measures.
//
//  SAFETY (this guide must never be able to harm):
//    • Never FORCES a rate: it only suggests; the user breathes voluntarily.
//    • Pace is bounded to a safe, evidence-based window and EASED, never jerked
//      (`maxRateSlewPerSec`), so a rate change can't make anyone gasp.
//    • NO breath-holds are ever instructed (only "in" / "out").
//    • Slow floor at `minRate` so it cannot push dangerously slow.
//    • `contraindications` ships with the model for the UI to show BEFORE a
//      session (asthma/COPD, panic/anxiety, cardiac, pregnancy — coordinate
//      with a provider). This is self-observation, not therapy or diagnosis.
//
//  Pure, deterministic advance (no timers inside): the host ticks `tick(_:)`
//  from its existing loop. Phase convention is the pacer's own (documented on
//  `phase`); breath curve is a smooth raised-cosine, never a hard sawtooth.
//

import Foundation
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class BreathPacer {

    // MARK: Safe bounds (breaths per minute)
    // `nonisolated` so pure, non-MainActor models (e.g. ResonanceFinder) can read
    // these immutable bounds without crossing actor isolation.

    /// Slow floor — resonance-search protocols stay at/above this; we do not
    /// push below it so the guide can never drive an unsafely slow pace.
    public nonisolated static let minRate = 5.0
    public nonisolated static let maxRate = 12.0
    /// ~0.1 Hz — the canonical resonance / coherence pace.
    public nonisolated static let defaultRate = 6.0
    /// Max pace change per second — easing so a rate change is never abrupt.
    public nonisolated static let maxRateSlewPerSec = 0.5

    // MARK: State

    public private(set) var isRunning = false

    /// Desired pace (breaths/min). Always clamped into [minRate, maxRate].
    public var targetRate: Double = BreathPacer.defaultRate {
        didSet {
            let c = Swift.min(Self.maxRate, Swift.max(Self.minRate, targetRate))
            if c != targetRate { targetRate = c }   // single re-clamp (no didSet recursion)
        }
    }

    /// Fraction of each breath spent inhaling (rest is exhale). Exhale is kept
    /// longer than inhale by default — the vagal-emphasis pattern. Bounded so a
    /// segment can never collapse to zero.
    public var inhaleFraction: Double = 0.4 {
        didSet {
            let c = Swift.min(0.6, Swift.max(0.3, inhaleFraction))
            if c != inhaleFraction { inhaleFraction = c }
        }
    }

    /// The pace actually applied right now — eases toward `targetRate`.
    public private(set) var effectiveRate = BreathPacer.defaultRate

    /// Cycle phase [0,1): 0 = exhale start. Exhale spans [0, 1−inhaleFraction),
    /// inhale spans [1−inhaleFraction, 1).
    public private(set) var phase = 0.0

    /// Guidance amplitude [0,1] for the visual: 1 = lungs full (inhale peak),
    /// 0 = empty (exhale end). Smooth raised-cosine, no hard edges.
    public private(set) var guidance = 0.0

    /// What to show the user now. Only "Breathe in" / "Breathe out" — never a hold.
    public private(set) var instruction = "Breathe out"

    public init() {}

    // MARK: Transport (user-initiated; never auto-starts)

    public func start() {
        isRunning = true
    }

    public func stop() {
        isRunning = false
    }

    public func reset() {
        phase = 0
        effectiveRate = targetRate
        recompute()
    }

    /// Advance the guide by `dt` seconds. No-op while stopped. Pure given state.
    public func tick(_ dt: Double) {
        guard isRunning, dt > 0, dt.isFinite else { return }

        // Ease the applied rate toward the target (never jerks the user).
        let maxStep = Self.maxRateSlewPerSec * dt
        let delta = targetRate - effectiveRate
        if abs(delta) <= maxStep {
            effectiveRate = targetRate
        } else {
            effectiveRate += (delta > 0 ? maxStep : -maxStep)
        }

        // Advance phase by rate (cycles/sec = breaths-per-min / 60).
        phase += dt * effectiveRate / 60.0
        phase -= floor(phase)   // wrap into [0,1)
        recompute()
    }

    // MARK: Curve

    private func recompute() {
        guidance = Self.guidance(phase: phase, inhaleFraction: inhaleFraction)
        instruction = (phase >= 1.0 - inhaleFraction) ? "Breathe in" : "Breathe out"
    }

    /// Pure breath curve: raised-cosine over each segment. Exhale (first part of
    /// the cycle) eases 1→0; inhale (last `inhaleFraction`) eases 0→1.
    public static func guidance(phase: Double, inhaleFraction: Double) -> Double {
        let p = phase - floor(phase)
        let inh = Swift.min(0.6, Swift.max(0.3, inhaleFraction))
        let exhaleSpan = 1.0 - inh
        if p < exhaleSpan {
            let u = exhaleSpan > 0 ? p / exhaleSpan : 0           // 0→1 across exhale
            return 0.5 * (1.0 + cos(Double.pi * u))               // 1→0
        } else {
            let v = inh > 0 ? (p - exhaleSpan) / inh : 0          // 0→1 across inhale
            return 0.5 * (1.0 - cos(Double.pi * v))               // 0→1
        }
    }

    // MARK: Safety copy (shown by the UI before a session)

    /// Plain, non-medical cautions. Shown BEFORE paced breathing — the guide is
    /// for self-observation, not therapy. No diagnostic or therapeutic claims.
    public static let contraindications: [String] = [
        "Breathe gently — never strain or hold your breath.",
        "Stop if you feel dizzy or short of breath.",
        "If you have asthma/COPD, a heart condition, a panic/anxiety disorder, "
            + "or are pregnant, check with a healthcare provider first.",
        "This is for self-observation, not medical diagnosis or treatment."
    ]
}
