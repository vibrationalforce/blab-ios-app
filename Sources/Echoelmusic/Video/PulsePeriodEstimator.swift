// PulsePeriodEstimator.swift
// Echoel — robust pulse-rate estimate via normalized autocorrelation. The camera
// rPPG peak detector counts discrete local maxima; when the waveform is rounded
// or weak (common finger placements) it finds too few peaks and reports no BPM at
// all — even though a clear periodicity is present (device log: finger=yes, q≈0.58,
// bpm=0 for a whole session). Autocorrelation finds the dominant period directly
// from the signal shape, so it locks where peak-counting can't.
//
// Pure value math (no Accelerate dependency) so it is fully unit-tested on every
// platform and stays the trustworthy fallback in CameraAnalyzer.

import Foundation

public enum PulsePeriodEstimator {

    /// Dominant pulse rate via normalized autocorrelation over the heart-rate band.
    ///
    /// - Parameters:
    ///   - signal: band-passed samples (DC already removed upstream is fine; the
    ///     mean is removed here regardless).
    ///   - sampleRate: TRUE samples/second (derive from timestamps, don't assume).
    /// - Returns: `bpm` (within [minBPM, maxBPM]) and a 0…1 `strength`
    ///   (autocorrelation peak ÷ zero-lag energy = how periodic the window is),
    ///   or `nil` if the window is too short or flat.
    public static func dominantBPM(_ signal: [Float],
                                   sampleRate: Double,
                                   minBPM: Double = 40,
                                   maxBPM: Double = 200) -> (bpm: Double, strength: Double)? {
        let n = signal.count
        guard n >= 16, sampleRate > 1, minBPM > 0, maxBPM > minBPM else { return nil }

        // Mean-remove (so a residual DC offset can't dominate the correlation).
        var mean: Double = 0
        for v in signal { mean += Double(v) }
        mean /= Double(n)
        let x = signal.map { Double($0) - mean }

        var energy: Double = 0
        for v in x { energy += v * v }
        guard energy > 1e-9 else { return nil }

        // Lag range that maps to the allowed BPM band.
        let minLag = max(1, Int((60.0 / maxBPM) * sampleRate))
        let maxLag = min(n - 1, Int((60.0 / minBPM) * sampleRate))
        guard maxLag > minLag else { return nil }

        var corr = [Double](repeating: 0, count: maxLag + 1)
        var bestLag = -1
        var bestCorr = 0.0
        for lag in minLag...maxLag {
            var c = 0.0
            var i = lag
            while i < n { c += x[i] * x[i - lag]; i += 1 }
            corr[lag] = c
            if c > bestCorr { bestCorr = c; bestLag = lag }
        }
        guard bestLag > 0, bestCorr > 0 else { return nil }

        // Parabolic interpolation around the peak for sub-sample lag resolution
        // (at ~15 Hz one lag step is several BPM — interpolation matters).
        var lagF = Double(bestLag)
        if bestLag > minLag && bestLag < maxLag {
            let ym = corr[bestLag - 1], y0 = corr[bestLag], yp = corr[bestLag + 1]
            let denom = ym - 2 * y0 + yp
            if denom != 0 { lagF = Double(bestLag) + 0.5 * (ym - yp) / denom }
        }
        guard lagF > 0 else { return nil }

        let bpm = 60.0 * sampleRate / lagF
        guard bpm >= minBPM && bpm <= maxBPM else { return nil }
        let strength = max(0, min(1, bestCorr / energy))
        return (bpm, strength)
    }
}
