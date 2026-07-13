// RPPGConditioning.swift
// Echoel — pure rPPG signal-conditioning helpers.
//
// The device "no-lock" failure (log: finger=yes but pk=0 / bpm=0 / conf=0 for a whole
// session) is driven by a slow DC ramp that swamps the small cardiac AC, and by weak /
// motion windows the peak detector still self-agrees into a phantom rate. These pure
// helpers isolate the three conditioning steps that fix that, so they are unit-tested on
// every platform (Linux CI included) and can be reused by `CameraAnalyzer`:
//
//   1. `linearDetrend`      — kill the least-squares linear trend (the DC ramp) so the
//                             cardiac AC survives into the autocorrelation.
//   2. `perfusionIsMotion`  — discard a window ONLY when the pulsatile perfusion is weak
//                             AND the window is aperiodic (a strongly-periodic window is
//                             never thrown away, however weak).
//   3. `acfProminence`      — Hann-windowed normalized autocorrelation with a prominence
//                             score (peak minus the neighboring-lag floor) that separates
//                             a clean periodicity from a smooth trend.
//
// Pure Foundation value math only — no AVFoundation / Accelerate / SwiftUI. Deterministic.

import Foundation

/// Pure rPPG signal-conditioning helpers (see file header). Namespaced, stateless.
public enum RPPGConditioning {

    /// Small guard so a zero DC level can't divide-by-zero in the perfusion index.
    public static let epsilon: Float = 1e-6

    /// Perfusion index below which a window is considered to carry no real pulse.
    /// A resting fingertip pulse AC is a small fraction of the red DC, but not THIS small.
    public static let perfusionFloor: Float = 0.01

    /// Periodicity (autocorrelation strength, 0…1) below which a window is aperiodic.
    /// A window at or above this is treated as a real pulse regardless of perfusion.
    public static let periodicityFloor: Float = 0.3

    // MARK: - Linear detrend

    /// Remove the least-squares linear (slope + offset) trend from `samples`.
    ///
    /// The rPPG red channel drifts slowly (breathing, exposure settle) — that ramp is a
    /// large DC component that dominates the raw autocorrelation and hides the cardiac AC.
    /// Fitting `y ≈ a + b·i` by least squares and returning the residual `y − (a + b·i)`
    /// removes both the slope and the mean, leaving a ~zero-mean signal the pulse estimator
    /// can lock onto.
    ///
    /// - Parameter samples: the raw window (index `i` is the sample position).
    /// - Returns: the detrended residual, same length as the input. Returns the input
    ///   unchanged in length for `count < 2` (a 0- or 1-sample window has no trend to fit;
    ///   a single sample detrends to `0`). A pure straight line detrends to ~`0`.
    public static func linearDetrend(_ samples: [Float]) -> [Float] {
        let n = samples.count
        guard n >= 2 else {
            // 0 samples → []; 1 sample → its own least-squares line passes through it → 0.
            return n == 1 ? [0] : []
        }

        let nD = Double(n)
        var sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumXY = 0.0
        for i in 0..<n {
            let x = Double(i)
            let y = Double(samples[i])
            sumX += x
            sumY += y
            sumXX += x * x
            sumXY += x * y
        }

        // slope = (nΣxy − ΣxΣy) / (nΣx² − (Σx)²). Denominator > 0 for n ≥ 2 (distinct x),
        // guarded regardless so a degenerate case falls back to mean-removal.
        let denom = nD * sumXX - sumX * sumX
        guard denom != 0 else {
            let mean = sumY / nD
            return samples.map { Float(Double($0) - mean) }
        }
        let slope = (nD * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / nD

        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let fit = intercept + slope * Double(i)
            out[i] = Float(Double(samples[i]) - fit)
        }
        return out
    }

    // MARK: - Perfusion / motion gate

    /// Whether a window should be discarded as motion / no-signal.
    ///
    /// Perfusion index `PI = amplitude / max(dc, epsilon)` measures the pulsatile AC as a
    /// fraction of the DC level. A window is treated as motion (discard, return `true`)
    /// **only** when perfusion is low AND the window is aperiodic — a strongly-periodic
    /// window (high `autoStrength`) is NEVER discarded, even at low perfusion, because a
    /// clear periodicity is the real pulse the peak counter is missing.
    ///
    /// - Parameters:
    ///   - amplitude: peak-to-peak (or comparable) magnitude of the filtered pulse window.
    ///   - dc: the window's DC / baseline red level (`max(dc, epsilon)` guards divide-by-zero).
    ///   - autoStrength: autocorrelation periodicity, 0…1 (e.g. `PulsePeriodEstimator` strength).
    /// - Returns: `true` when the window is low-perfusion AND aperiodic (discard as motion).
    public static func perfusionIsMotion(amplitude: Float, dc: Float, autoStrength: Float) -> Bool {
        let perfusion = amplitude / Swift.max(dc, epsilon)
        let lowPerfusion = perfusion < perfusionFloor
        let aperiodic = autoStrength < periodicityFloor
        return lowPerfusion && aperiodic
    }

    // MARK: - Autocorrelation prominence

    /// Hann-windowed normalized autocorrelation with a prominence score over `[minLag, maxLag]`.
    ///
    /// The input is Hann-windowed (to suppress edge leakage), then the normalized
    /// autocorrelation `acf[lag] = Σ w[i]·w[i−lag] / Σ w[i]²` is evaluated for every lag in
    /// the range. `lag` is the argmax; `score` is that peak minus the mean of the other
    /// ("neighboring") lags in the band — a *prominence*, not a raw correlation. A smooth
    /// trend correlates highly at every lag, so its peak barely clears the band mean (low
    /// prominence); a genuine periodicity spikes at one lag while the rest of the band
    /// averages near zero (high prominence). O(n²), which is fine for the short windows used.
    ///
    /// - Parameters:
    ///   - samples: the window to analyze (detrend first for a clean cardiac peak).
    ///   - minLag: shortest lag to search (clamped to ≥ 1).
    ///   - maxLag: longest lag to search (clamped to ≤ count − 1).
    /// - Returns: `(lag, score)` — the argmax lag and its prominence. `(0, 0)` when the
    ///   window is too short, the lag range is empty, or the window is flat (zero energy).
    public static func acfProminence(_ samples: [Float],
                                     minLag: Int,
                                     maxLag: Int) -> (lag: Int, score: Float) {
        let n = samples.count
        guard n >= 4 else { return (0, 0) }

        let lo = Swift.max(1, minLag)
        let hi = Swift.min(n - 1, maxLag)
        guard hi >= lo else { return (0, 0) }

        // Hann window, applied in Double for stability.
        var w = [Double](repeating: 0, count: n)
        let denomN = Double(n - 1)
        for i in 0..<n {
            let hann = 0.5 - 0.5 * cos(2.0 * Double.pi * Double(i) / denomN)
            w[i] = hann * Double(samples[i])
        }

        var energy = 0.0
        for v in w { energy += v * v }
        guard energy > 1e-12 else { return (0, 0) }

        // Normalized autocorrelation over the lag band.
        var acf = [Double](repeating: 0, count: hi + 1)
        var bestLag = lo
        var bestVal = -Double.greatestFiniteMagnitude
        for lag in lo...hi {
            var c = 0.0
            var i = lag
            while i < n {
                c += w[i] * w[i - lag]
                i += 1
            }
            let v = c / energy
            acf[lag] = v
            if v > bestVal {
                bestVal = v
                bestLag = lag
            }
        }

        // Prominence: peak minus the mean of neighboring lags (band minus a small
        // exclusion zone around the peak). If nothing remains outside the exclusion the
        // floor is 0.
        let exclusion = 2
        var neighborSum = 0.0
        var neighborCount = 0
        for lag in lo...hi where abs(lag - bestLag) > exclusion {
            neighborSum += acf[lag]
            neighborCount += 1
        }
        let neighborMean = neighborCount > 0 ? neighborSum / Double(neighborCount) : 0
        let score = bestVal - neighborMean
        return (bestLag, Float(score))
    }
}
