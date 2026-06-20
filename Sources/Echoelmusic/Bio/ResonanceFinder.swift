//
//  ResonanceFinder.swift
//  Echoelmusic — Bio
//
//  Personalized resonance-frequency assessment (Lehrer HRV-biofeedback protocol).
//  Pace the breath at several candidate rates, measure the HRV/coherence response
//  at each, and pick the rate that maximizes it = the user's resonance frequency —
//  the pace where heart and breath couple maximally through the baroreflex. This
//  is the science core of the resonance loop: the host orchestrates the per-stage
//  timing and feeds a response score for each rate; the peak math lives here, pure
//  and unit-tested. Bounded to the same safe window as BreathPacer (never below
//  its floor). Self-observation, not therapy or diagnosis.
//
//  Why personalize: the canonical ~6/min (0.1 Hz) is a population average; an
//  individual's resonance is typically 4.5–7/min and shifts the achievable HRV
//  meaningfully. Finding it is the single highest-leverage step of the loop.
//

import Foundation

/// One assessed breathing rate and the HRV/coherence response measured at it.
/// `score` is any monotonic "stronger coupling = higher" measure (e.g. RSA/HRV
/// amplitude or the HRVCoherence value), compared only relative to other samples.
public struct ResonanceSample: Equatable, Sendable {
    public let rate: Double      // breaths per minute
    public let score: Double     // measured response; higher = stronger coupling
    public init(rate: Double, score: Double) {
        self.rate = rate
        self.score = score
    }
}

public enum ResonanceFinder {

    /// Safe assessment window (breaths/min). The floor is shared with BreathPacer
    /// so the search can never suggest an unsafely slow pace.
    public static let minRate = BreathPacer.minRate          // 5.0
    public static let maxRate = 7.0
    public static let step = 0.5

    /// Candidate rates, high → low (7.0, 6.5, … 5.0): the usual clinical sweep
    /// starts a touch faster and settles slower.
    public static var candidateRates: [Double] {
        var rates: [Double] = []
        var r = maxRate
        while r >= minRate - 1e-9 {
            rates.append((r * 100).rounded() / 100)          // tidy 0.5 grid
            r -= step
        }
        return rates
    }

    /// Estimate the resonance rate from per-rate response scores. Returns the
    /// candidate with the strongest response, refined by parabolic interpolation
    /// when the peak is interior (sub-step resolution), clamped to the safe window.
    /// Returns nil when there is no finite sample to judge.
    public static func bestRate(from samples: [ResonanceSample]) -> Double? {
        let valid = samples.filter { $0.rate.isFinite && $0.score.isFinite }
        guard !valid.isEmpty else { return nil }

        // Sort by rate so neighbours are adjacent for interpolation.
        let sorted = valid.sorted { $0.rate < $1.rate }

        // Index of the strongest response.
        var peak = 0
        for i in 1..<sorted.count where sorted[i].score > sorted[peak].score { peak = i }
        let best = sorted[peak]

        // Refine only when the peak has neighbours on both sides.
        guard peak > 0, peak < sorted.count - 1 else { return clampRate(best.rate) }

        let y0 = sorted[peak - 1].score
        let y1 = best.score
        let y2 = sorted[peak + 1].score
        let denom = y0 - 2 * y1 + y2                          // ≤ 0 at a real maximum
        guard abs(denom) > 1e-12 else { return clampRate(best.rate) }

        // Vertex offset in units of sample spacing, then mapped to rate. Clamped
        // to ±1 step so a noisy triple can never extrapolate past the neighbours.
        var offset = 0.5 * (y0 - y2) / denom
        offset = Swift.min(1.0, Swift.max(-1.0, offset))
        let h = sorted[peak + 1].rate - best.rate            // local spacing (uniform grid)
        return clampRate(best.rate + offset * h)
    }

    private static func clampRate(_ r: Double) -> Double {
        Swift.min(maxRate, Swift.max(minRate, r))
    }
}
