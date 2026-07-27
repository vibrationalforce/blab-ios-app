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

/// Brick-wall limiter: for FINITE input, output magnitude never exceeds the ceiling, and
/// the gain that achieves that moves CONTINUOUSLY rather than jumping.
///
/// "For finite input" is not a hedge, it is the exact contract. A non-finite sample takes
/// the bypass in `processStereo` and is scaled by the current gain without any ceiling
/// enforcement — an `inf` in is an `inf` out. That is deliberate: this class is a gain
/// computer, and sanitizing samples belongs to `AudioOutputGuard`, which sweeps at the
/// source-node output — the stage immediately DOWNSTREAM of this whole FX chain
/// (`PolySynthVoice` runs `fxChain.processBuffer`, then `copySilencingNonFinite`). What IS
/// guaranteed for such a sample is that the limiter's own state survives it intact.
///
/// Also true and NOT a rounding-free absolute: the ceiling can be exceeded by up to ~2 ulp
/// (measured worst case 108 ppb over 900k fuzzed samples), because `fl(fl(ceiling/env)·peak)`
/// need not round down. Every assertion allows `ceiling * 1.001`, so nothing depends on the
/// stronger reading — but "never exceeds" means "never by more than one rounding step".
///
/// ⛔ WHY THE ATTACK EXISTS (founder 2026-07-27: "Es knistert. Wie CPU overload bei
/// Ableton oder so"). The previous version had zero attack:
///
///     if peak * g > ceiling { g = ceiling / peak }
///
/// Read what that does to the louder channel: its output becomes
/// `in * ceiling/|in| = sign(in) * ceiling` — EXACTLY the ceiling, every time it is
/// crossed. That is not "a limiter with a fast attack". It is algebraically a
/// **per-sample HARD CLIPPER**, and the waveform comes out flat-topped. Un-oversampled
/// at 48 kHz, hard clipping's high-order odd harmonics fold back below Nyquist as
/// INHARMONIC ALIASING — the gritty, digital, "CPU-overload" texture the founder
/// described, not the periodic click an earlier note of mine claimed.
///
/// It fired constantly, not rarely: the poly engine's makeup gain lags a chord attack by
/// ~250 ms, so every sparse→dense entry overshoots the ceiling already at velocity 0.47.
///
/// THE FIX, and why it is this one and not lookahead. Two stages, both required:
/// a PEAK-ENVELOPE detector (holds the peak between cycles) feeding a gain that moves
/// toward its target with a finite ATTACK. Sustained loud material is then SCALED
/// (waveform shape preserved) instead of flat-topped, and the aliasing goes with it. A
/// final per-sample guard keeps the ceiling absolute, so it can still engage on a
/// transient that rises faster than the attack — one brief clip instead of a continuous
/// one. Skipping the detector and running the ballistics off the raw sample does NOT
/// work; `processStereo` says why at the line that computes `env`.
///
/// A lookahead delay line would remove even that residue, but it would put this chain
/// ~1.3 ms behind `SubBassVoice`, which has no such chain — a real phase offset between
/// the bass and the felt layer, traded for a residue that only appears on isolated
/// transients. If the founder still hears grit after this, lookahead is the next step,
/// not a substitute for it.
public final class EchoelLimiter: @unchecked Sendable {

    /// Output ceiling in dBFS.
    public var ceilingDb: Float = -0.3 { didSet { recalc() } }
    /// Attack time in milliseconds — how fast the gain may FALL. Short enough to catch a
    /// note onset, long enough that the gain is a smooth signal rather than a step train.
    public var attackMs: Float = 0.5 { didSet { recalc() } }
    /// Release time in milliseconds.
    public var releaseMs: Float = 60 { didSet { recalc() } }

    private let sr: Float
    private var ceilingLin: Float = 1
    private var attackCoeff: Float = 0
    private var releaseCoeff: Float = 0
    private var env: Float = 0       // peak envelope, ≥ 0
    private var gain: Float = 1.0    // ≤ 1

    public init(sampleRate: Float = 48000) {
        self.sr = sampleRate
        recalc()
    }

    @inline(__always)
    public func processStereo(_ inL: Float, _ inR: Float) -> (Float, Float) {
        let peak = Swift.max(abs(inL), abs(inR))

        // A non-finite sample must not reach the detector. `inf` would pin `env` at
        // infinity permanently (`inf * decay == inf`), and NaN propagates through
        // `Swift.max`, so either one would silence the limiter for good — a state bug far
        // worse than the bad sample itself. Skip the whole state update and apply the gain
        // already held. Cleaning the SAMPLE up remains `AudioOutputGuard`'s job downstream;
        // this only guarantees the limiter survives one.
        guard peak.isFinite else { return (inL * gain, inR * gain) }

        // PEAK ENVELOPE — decays at the release rate, follows a rise instantly.
        //
        // This stage is not optional. If the detector reads the RAW sample it springs back
        // to a target of unity at every zero crossing (15.8% of samples on a 200 Hz sine at
        // 12 dB over), the slow release walks the gain up between peaks, and that ripple
        // re-engages the absolute guard below — the flat-topping this class exists to
        // remove comes back, periodically instead of continuously.
        //
        // Measured on that signal (bit-accurate simulation of these three variants, DSP
        // review 2026-07-27) — third harmonic, and the inharmonic floor above 1 kHz that IS
        // the audible "grit":
        //
        //     old (no ballistics at all)   H3 −31.2 dBc     floor −80.4 dB
        //     ballistics, RAW detector     H3 −37.9 dBc     floor −86.8 dB
        //     ballistics + this envelope   H3 −73.4 dBc     floor −90.7 dB
        //
        // So the envelope is worth 35 of the 42 dB. The ballistics alone buy ~7.
        // (Two earlier numbers here were mine and were wrong — "walks up ~0.04 per cycle"
        // is really 0.0097, and "a quarter of every cycle" is really 9.2%. They are replaced
        // by the measurements above rather than quietly deleted, because the conclusion
        // survived them and the next session should trust the measurement, not my estimate.)
        // `1 - releaseCoeff` is exactly `exp(-1/t)`, computed here rather than cached as a
        // field. One FSUB per sample, next to a division that already costs far more — and
        // in exchange `releaseCoeff` stays the SINGLE source of truth. A cached `envDecay`
        // would be a value DERIVED from `releaseCoeff` but stored separately, so a control
        // thread running `recalc()` could leave the render thread reading a new
        // `releaseCoeff` beside an old `envDecay` (arm64 gives no store ordering here).
        // Same lesson as `EchoelSVFilter` (see its file doc): do not create a pair that has
        // to stay consistent — remove the pairing instead.
        let decayed = env * (1 - releaseCoeff)
        env = peak > decayed ? peak : decayed

        // ⚠ THE INVARIANT THE CEILING GUARANTEE RESTS ON: `env >= peak`, established by the
        // line above. It is what makes the absolute guard at the bottom sufficient —
        // `target = ceiling/env` gives `peak * target <= ceiling` only because `env >= peak`.
        // If a later change makes this detector an RMS, or smooths its RISE, `env` can fall
        // below `peak` and that guard silently stops clamping. Do not weaken the rise.
        //
        // The gain the envelope WOULD need. `env <= ceiling` ⇒ 1, so quiet material has a
        // target of unity and the smoother simply releases toward it.
        let target = env > ceilingLin ? ceilingLin / env : 1

        // Asymmetric one-pole: fall fast (attack), recover slowly (release). Both are
        // one-poles rather than jumps, so `gain` is a continuous signal — which is the
        // whole point: a discontinuous gain multiplied into audio IS distortion.
        let coeff = target < gain ? attackCoeff : releaseCoeff
        var g = gain + (target - gain) * coeff

        // THE CEILING STAYS ABSOLUTE. The smoother may not have arrived yet on a fast
        // transient; this guard is what keeps the guarantee in the class doc true.
        //
        // On the sustained material that caused the report it engages on ~1.7% of samples
        // rather than 16.7%, and where it does the correction is under 0.01 dB — the
        // smoothed gain settles a hair ABOVE `ceiling/env`, not at or below it. (An earlier
        // version of this comment said "it no longer engages", stated as an absolute. It
        // was not one.)
        if peak * g > ceilingLin { g = target }
        gain = g
        return (inL * g, inR * g)
    }

    /// Current gain reduction in dB (≤ 0), for metering.
    public var gainReductionDb: Float { 20.0 * log10f(Swift.max(gain, 1e-7)) }

    public func reset() { gain = 1.0; env = 0 }

    private func recalc() {
        // Hoisted out of `processStereo`, where `powf(10, ceilingDb/20)` was recomputed
        // for a CONSTANT on every sample — ~200k needless transcendental calls per second
        // across the active chains.
        ceilingLin = powf(10.0, ceilingDb / 20.0)
        attackCoeff = Self.coeff(ms: attackMs, sr: sr)
        releaseCoeff = Self.coeff(ms: releaseMs, sr: sr)
    }

    @inline(__always)
    private static func coeff(ms: Float, sr: Float) -> Float {
        // Clamped at BOTH ends. The upper bound is the one that matters and was missing:
        // past ~700 s, `1 - expf(-1/t)` rounds to exactly 0 in Float, the coefficient dies,
        // and the limiter latches at whatever attenuation it happened to hold — permanent
        // silence, the exact failure mode "fail to resting, never to silence" exists to
        // forbid. No writer can reach that today (nothing sets attackMs/releaseMs), so this
        // is a guard against a future control, not a live bug. 10 s is far beyond any
        // musical release and still leaves the coefficient ~2e-6, comfortably normal.
        let t = Swift.min(Swift.max(0.01, ms), 10_000) * 0.001 * sr
        return 1.0 - expf(-1.0 / t)
    }
}
