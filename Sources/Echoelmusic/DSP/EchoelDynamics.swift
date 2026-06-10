import Foundation

/// Dynamics processors — audio-thread safe (no allocation or locks in the hot
/// loop). Stereo detection is channel-linked (uses the louder channel) so the
/// stereo image is preserved while gain is applied equally to both sides.
///
/// References: Giannoulis, Massberg & Reiss, "Digital Dynamic Range Compressor
/// Design — A Tutorial and Analysis" (JAES 2012); Zölzer, "DAFX".

// MARK: - Compressor

public final class EchoelCompressor: @unchecked Sendable {

    /// Threshold in dBFS (below this, no compression).
    public var thresholdDb: Float = -18
    /// Compression ratio [1, 20] (1 = no compression).
    public var ratio: Float = 3.0
    /// Attack time in milliseconds.
    public var attackMs: Float = 10 { didSet { recalc() } }
    /// Release time in milliseconds.
    public var releaseMs: Float = 120 { didSet { recalc() } }
    /// Soft-knee width in dB.
    public var kneeDb: Float = 6
    /// Make-up gain in dB.
    public var makeupDb: Float = 0

    private let sr: Float
    private var attackCoeff: Float = 0
    private var releaseCoeff: Float = 0
    private var grState: Float = 0   // current gain reduction in dB (≤ 0)

    public init(sampleRate: Float = 48000) {
        self.sr = sampleRate
        recalc()
    }

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        let peak = Swift.max(abs(inL), abs(inR))
        let inDb = 20.0 * log10f(Swift.max(peak, 1e-7))

        // Static gain-computer with quadratic soft knee.
        let r = Swift.max(1.0, ratio)
        let slope = (1.0 / r) - 1.0
        let over = inDb - thresholdDb
        let halfKnee = Swift.max(0.0001, kneeDb) * 0.5
        let target: Float
        if over <= -halfKnee {
            target = 0
        } else if over >= halfKnee {
            target = slope * over
        } else {
            let x = over + halfKnee
            target = slope * (x * x) / (4.0 * halfKnee)
        }

        // Ballistics: fast toward more reduction (attack), slow toward less (release).
        if target < grState {
            grState += (target - grState) * attackCoeff
        } else {
            grState += (target - grState) * releaseCoeff
        }

        let gainLin = powf(10.0, (grState + makeupDb) / 20.0)
        return (inL * gainLin, inR * gainLin)
    }

    /// Current gain reduction in dB (≤ 0), for metering.
    public var gainReductionDb: Float { grState }

    public func reset() { grState = 0 }

    private func recalc() {
        attackCoeff = coeff(forMs: attackMs)
        releaseCoeff = coeff(forMs: releaseMs)
    }

    @inline(__always)
    private func coeff(forMs ms: Float) -> Float {
        let t = Swift.max(0.01, ms) * 0.001 * sr
        return 1.0 - expf(-1.0 / t)
    }
}

// MARK: - Limiter (brick-wall)

/// Brick-wall limiter with a hard guarantee: output magnitude never exceeds the
/// ceiling. Gain reduction is applied instantly (zero attack) and recovers with
/// a smooth release, so transients are caught while sustained material breathes.
public final class EchoelLimiter: @unchecked Sendable {

    /// Output ceiling in dBFS.
    public var ceilingDb: Float = -0.3
    /// Release time in milliseconds.
    public var releaseMs: Float = 60 { didSet { recalc() } }

    private let sr: Float
    private var releaseCoeff: Float = 0
    private var gain: Float = 1.0    // ≤ 1

    public init(sampleRate: Float = 48000) {
        self.sr = sampleRate
        recalc()
    }

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        let ceiling = powf(10.0, ceilingDb / 20.0)
        let peak = Swift.max(abs(inL), abs(inR))

        // Release: drift gain back toward unity.
        var g = gain + (1.0 - gain) * releaseCoeff

        // Instant attack: clamp so the (linked) peak cannot exceed the ceiling.
        if peak * g > ceiling {
            g = ceiling / peak
        }
        gain = g
        return (inL * g, inR * g)
    }

    /// Current gain reduction in dB (≤ 0), for metering.
    public var gainReductionDb: Float { 20.0 * log10f(Swift.max(gain, 1e-7)) }

    public func reset() { gain = 1.0 }

    private func recalc() {
        let t = Swift.max(0.01, releaseMs) * 0.001 * sr
        releaseCoeff = 1.0 - expf(-1.0 / t)
    }
}
