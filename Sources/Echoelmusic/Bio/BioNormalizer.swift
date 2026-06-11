//
//  BioNormalizer.swift
//  Echoelmusic — Bio
//
//  Science-grounded normalization of noisy, non-stationary biosignals into a
//  stable, musician-playable [0..1] control value. This is the implementation
//  of the mapping research (scratchpads/RESEARCH_BIO_UX_2026-06-11.md, §A1/§A2):
//
//    raw → [accept-gate] → rolling z-score (σ-floor) → tanh squash → EMA
//
//  Why this stack (cited in the research file):
//    • Bio baselines drift, so a fixed min/max mis-scales over time and a single
//      outlier crushes the range. A ROLLING z-score adapts to the moving baseline.
//    • A σ-floor stops division-by-near-zero from turning quiet signals into jumps.
//    • tanh squashes z (in std units) into a bounded, outlier-robust [0..1] with a
//      neutral 0.5 centre — no clipping, gentle saturation at the extremes.
//    • An EMA after the squash trades a little latency for jitter-free, expressive
//      control (the slew/low-pass trade-off). Use a long τ for slow signals
//      (coherence/HRV ≈ 0.5–2 s) and a short τ for fast ones (breath ≈ 100 ms).
//    • The accept-gate freezes the baseline and HOLDS the last value when the
//      signal is untrustworthy (e.g. motion corrupts PPG → gate HRV off).
//
//  Pure value type. No allocation in steady state (the window is sized once at
//  init), no locks, no I/O — safe to evaluate on the control plane. Accumulators
//  are Double to avoid Float cancellation over long windows; output is Float.
//

import Foundation

// MARK: - Response curve

/// Monotonic [0..1] → [0..1] shaping applied AFTER normalization. Endpoints
/// (0 and 1) are preserved by every curve. Perceptual scaling lives here:
/// pitch-like targets want `.logarithmic` emphasis on low values, loudness-like
/// targets want `.exponential`. (Research §A2: linear-on-Hz/amplitude is
/// perceptually wrong; choose the curve per destination.)
public enum ResponseCurve: String, Codable, Sendable, CaseIterable {
    case linear
    case exponential   // x²  — expands the top, compresses the bottom
    case logarithmic   // √x  — expands the bottom, compresses the top
    case sCurve        // smoothstep 3x²−2x³ — soft ends, steep middle

    /// Applies the curve to `x`, clamping the input to [0..1] first.
    public func apply(_ x: Float) -> Float {
        let c = BioNormalizer.clamp01(x)
        switch self {
        case .linear:      return c
        case .exponential: return c * c
        case .logarithmic: return c.squareRoot()
        case .sCurve:      return c * c * (3 - 2 * c)
        }
    }
}

// MARK: - Rolling window statistics

/// Fixed-capacity ring buffer maintaining a running mean and sample standard
/// deviation. Accumulates in Double; `push` is O(1) and allocation-free once
/// constructed.
public struct RollingStats: Sendable {

    public let capacity: Int
    private var buffer: [Double]
    private var head: Int = 0
    private var filled: Int = 0
    private var sum: Double = 0
    private var sumSq: Double = 0

    public init(capacity: Int) {
        self.capacity = Swift.max(1, capacity)
        self.buffer = [Double](repeating: 0, count: self.capacity)
    }

    /// Number of valid samples currently in the window (≤ capacity).
    public var count: Int { filled }

    /// Mean of the current window, or 0 when empty.
    public var mean: Double { filled > 0 ? sum / Double(filled) : 0 }

    /// Sample standard deviation (n−1). 0 when fewer than two samples or flat.
    public var std: Double {
        guard filled >= 2 else { return 0 }
        let n = Double(filled)
        let variance = (sumSq - sum * sum / n) / (n - 1)
        return variance > 0 ? variance.squareRoot() : 0
    }

    /// Pushes a new sample, evicting the oldest once full.
    public mutating func push(_ x: Double) {
        if filled == capacity {
            let old = buffer[head]
            sum -= old
            sumSq -= old * old
        } else {
            filled += 1
        }
        buffer[head] = x
        sum += x
        sumSq += x * x
        head = (head + 1) % capacity
    }
}

// MARK: - BioNormalizer

/// Turns a raw biosignal stream into a smoothed, baseline-relative [0..1].
public struct BioNormalizer: Sendable {

    /// Rolling-window length in samples. At a 10 Hz control rate, 300 ≈ 30 s,
    /// 600 ≈ 60 s, 1200 ≈ 120 s (research recommends 30–120 s).
    public let windowSamples: Int
    /// Lower bound on the std used in the z-score, in the signal's own units.
    /// Prevents tiny noise from being amplified into full-range jumps.
    public let sigmaFloor: Float
    /// Steepness of the tanh squash, in 1/σ. ~1.0 maps ±2σ to ≈[0.08, 0.92].
    public let squashGain: Float
    /// EMA coefficient in (0, 1]. 1 = no smoothing. Derive from a time constant
    /// with `BioNormalizer.alpha(tauSeconds:dtSeconds:)`.
    public let emaAlpha: Float

    private var stats: RollingStats
    private var smoothed: Float?

    public init(
        windowSamples: Int = 600,
        sigmaFloor: Float = 1e-3,
        squashGain: Float = 1.0,
        emaAlpha: Float = 0.3
    ) {
        self.windowSamples = Swift.max(1, windowSamples)
        self.sigmaFloor = Swift.max(1e-9, sigmaFloor)
        self.squashGain = squashGain
        self.emaAlpha = Self.clamp01(emaAlpha)
        self.stats = RollingStats(capacity: self.windowSamples)
    }

    /// Normalizes one sample to [0..1].
    ///
    /// - Parameters:
    ///   - raw: the raw signal value (any unit/scale).
    ///   - accept: when `false`, the sample is treated as untrustworthy — the
    ///     baseline is NOT updated and the previous output is held (the
    ///     motion/confidence gate). Defaults to `true`.
    /// - Returns: a smoothed value in [0..1]; a neutral `0.5` until the window
    ///   holds at least two samples (no spurious modulation at startup).
    public mutating func normalize(_ raw: Float, accept: Bool = true) -> Float {
        // Gate: hold the last value, leave the baseline untouched.
        guard accept else {
            let held = smoothed ?? 0.5
            smoothed = held
            return held
        }

        stats.push(Double(raw))

        // Warm-up: not enough data for a meaningful std yet.
        guard stats.count >= 2 else {
            smoothed = 0.5
            return 0.5
        }

        let sigma = Swift.max(Float(stats.std), sigmaFloor)
        let z = (raw - Float(stats.mean)) / sigma
        let squashed = 0.5 * (Self.tanhf(z * squashGain) + 1)

        let prev = smoothed ?? squashed
        let out = Self.clamp01(emaAlpha * squashed + (1 - emaAlpha) * prev)
        smoothed = out
        return out
    }

    /// Current held output without advancing state (0.5 before warm-up).
    public var value: Float { smoothed ?? 0.5 }

    /// Resets the rolling window and smoothing state.
    public mutating func reset() {
        stats = RollingStats(capacity: windowSamples)
        smoothed = nil
    }

    // MARK: Helpers

    /// One-pole EMA coefficient for a target time constant `tau` at sample
    /// spacing `dt` (both seconds): `alpha = dt / (tau + dt)`. `tau == 0` → 1
    /// (no smoothing); larger `tau` → smaller alpha → slower response.
    public static func alpha(tauSeconds tau: Float, dtSeconds dt: Float) -> Float {
        let d = Swift.max(0, dt)
        let t = Swift.max(0, tau)
        let denom = t + d
        guard denom > 0 else { return 1 }
        return clamp01(d / denom)
    }

    public static func clamp01(_ v: Float) -> Float {
        if v.isNaN { return 0 }
        return Swift.min(1, Swift.max(0, v))
    }

    /// Float hyperbolic tangent via Double `tanh` (avoids shadowing the global
    /// `log`/`tanhf` C symbols and stays portable across platforms).
    static func tanhf(_ x: Float) -> Float {
        Float(Foundation.tanh(Double(x)))
    }
}
