// PitchTracker.swift
// Echoel — fine fundamental-frequency detection (YIN) for "hear the tuning".
//
// The mic's FFT peak (~43 Hz/bin at 1024 pt) is far too coarse to tell A4=432 from
// 440 (8 Hz). YIN (de Cheveigné & Kawahara, 2002) estimates the period directly from
// the signal with sub-sample (parabolic) refinement, giving cents-accurate pitch from
// voice/instrument — exactly what TuningDetector needs to recover the Kammerton.
//
// Pure value math (no AVFoundation/Accelerate) so it is fully unit-tested on every
// platform with synthetic tones. The audio tap passes a Float window in; this returns
// the fundamental in Hz (or nil when the window is unvoiced/aperiodic).

import Foundation

public enum PitchTracker {

    /// Detect the fundamental of `samples` (mono, −1…1) at `sampleRate`.
    /// - threshold: YIN aperiodicity gate (0.10–0.15 typical; lower = stricter).
    /// - Returns: frequency in Hz within [minHz, maxHz], or nil if unvoiced.
    public static func detect(_ samples: [Float], sampleRate: Double,
                              minHz: Double = 50, maxHz: Double = 2000,
                              threshold: Double = 0.12) -> Double? {
        let n = samples.count
        guard sampleRate > 0, maxHz > minHz, minHz > 0 else { return nil }
        // Need at least two periods of the lowest detectable pitch in the window.
        let tauMax = Swift.min(n - 1, Int(sampleRate / minHz))
        let tauMin = Swift.max(2, Int(sampleRate / maxHz))
        guard tauMax > tauMin, n >= tauMax * 2 else { return nil }

        // Reject silence (cheap energy gate).
        var energy = 0.0
        for s in samples { energy += Double(s) * Double(s) }
        guard energy / Double(n) > 1e-7 else { return nil }

        // 1) Difference function d(τ), canonical from τ=1 so the cumulative-mean
        //    normalisation (and thus the 0.12 threshold) is calibrated as in YIN.
        var d = [Double](repeating: 0, count: tauMax + 1)
        for tau in 1...tauMax {
            var sum = 0.0
            var i = 0
            let limit = n - tau
            while i < limit {
                let diff = Double(samples[i]) - Double(samples[i + tau])
                sum += diff * diff
                i += 1
            }
            d[tau] = sum
        }

        // 2) Cumulative mean normalised difference d'(τ) = d(τ) / [(1/τ) Σ_{1..τ} d(j)].
        var dPrime = [Double](repeating: 1, count: tauMax + 1)
        var running = 0.0
        for tau in 1...tauMax {
            running += d[tau]
            dPrime[tau] = running > 0 ? d[tau] * Double(tau) / running : 1
        }

        // 3) Absolute threshold: first τ dipping below `threshold` at a local minimum;
        //    fall back to the global minimum of d' if none crosses.
        var tauEstimate = -1
        var tau = tauMin + 1
        while tau < tauMax {
            if dPrime[tau] < threshold {
                while tau + 1 <= tauMax && dPrime[tau + 1] < dPrime[tau] { tau += 1 }
                tauEstimate = tau
                break
            }
            tau += 1
        }
        if tauEstimate == -1 {
            var best = tauMin, bestVal = dPrime[tauMin]
            for t in tauMin...tauMax where dPrime[t] < bestVal { bestVal = dPrime[t]; best = t }
            // Only trust the global min if it's reasonably periodic.
            guard bestVal < 0.5 else { return nil }
            tauEstimate = best
        }

        // 4) Parabolic interpolation around tauEstimate for sub-sample precision.
        let t = tauEstimate
        var refined = Double(t)
        if t > tauMin && t < tauMax {
            let x0 = dPrime[t - 1], x1 = dPrime[t], x2 = dPrime[t + 1]
            let denom = (x0 + x2 - 2 * x1)
            if abs(denom) > 1e-12 { refined = Double(t) + 0.5 * (x0 - x2) / denom }
        }
        guard refined > 0 else { return nil }

        let f0 = sampleRate / refined
        guard f0 >= minHz, f0 <= maxHz, f0.isFinite else { return nil }
        return f0
    }
}
