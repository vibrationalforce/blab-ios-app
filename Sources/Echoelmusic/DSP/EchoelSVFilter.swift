import Foundation

/// Topology-Preserving-Transform (TPT) State Variable Filter — zero-delay-feedback
/// form. Provides lowpass, highpass, bandpass and notch from the same two integrators.
/// Zero allocation, no branching in the inner loop — safe for the audio render thread.
///
/// Reference: Vadim Zavalishin, "The Art of VA Filter Design" (§4.4, the 2-pole SVF);
/// the trapezoidal-integration form popularised by Andrew Simper (Cytomic).
///
/// ── WHY NOT CHAMBERLIN ────────────────────────────────────────────────────────
/// This was a Chamberlin SVF (Musical Applications of Microprocessors, 1985) until
/// the cutoff lid became audible. That topology uses forward Euler integrators, and
/// its stability boundary is roughly `cutoff ≤ SR/6`; above it the two integrators
/// accumulate energy and self-oscillate into a high-pitched whine. The previous fix
/// for that whine was to CLAMP the normalized cutoff at 1/6 — correct as a safety
/// measure, and fatal as a musical one: at 48 kHz every cutoff above 8 kHz collapsed
/// onto the same filter, so the top ~1.2 octaves of the advertised 20 Hz…18 kHz range
/// did nothing. Every patch was quietly lidded, which is most of "the synth sounds
/// dull no matter what I do".
///
/// TPT replaces the Euler integrators with trapezoidal ones and solves the resulting
/// zero-delay feedback loop algebraically. It is unconditionally stable for any
/// `g > 0` and any positive damping, so the cutoff needs no musical clamp at all —
/// only a guard at Nyquist itself, where the `tan()` prewarp genuinely diverges.
public final class EchoelSVFilter: @unchecked Sendable {

    // MARK: - Filter Mode

    public enum Mode: String, CaseIterable, Sendable {
        case lowpass
        case highpass
        case bandpass
        case notch
    }

    // MARK: - Parameters

    /// Filter cutoff frequency in Hz. Musically unbounded — the only limit is Nyquist.
    public var cutoff: Float = 2000.0 {
        // The equality guard is not micro-optimization. `EchoelDDSP` assigns this INSIDE
        // its per-sample render loop, and `didSet` fires on every assignment regardless
        // of value — so without it the `tanf` below runs 48 000×/s per voice. The
        // smoothed cutoff converges to a fixed Float on a held note, so in steady state
        // this elides the recompute entirely.
        didSet { if cutoff != oldValue { updateCoefficients() } }
    }

    /// Resonance [0-1] (0.7 = musical, 0.95 = near self-oscillation)
    public var resonance: Float = 0.3 {      // Gentle — no harsh peaking
        didSet { if resonance != oldValue { updateCoefficients() } }
    }

    /// Active filter mode
    public var mode: Mode = .lowpass

    // MARK: - Internal State

    /// ── WHY ONLY `g` AND `k` ARE STORED ──────────────────────────────────────────
    /// These two are written from the control thread (`SynthPatch.apply`,
    /// `EchoelFXChain.setFilter`, `FXBioModulator` at ~30 Hz) and read on the audio
    /// thread, with no synchronisation. That race is old, but the TPT rewrite made it
    /// DANGEROUS in a way the Chamberlin form was not, so the storage layout is now
    /// load-bearing.
    ///
    /// The old `(f, q)` were INDEPENDENT: every torn combination of an old and a new
    /// value was still a valid, stable filter, because stability depended only on each
    /// value's own range. The solved coefficients `a1 = 1/(1 + g(g+k))`, `a2 = g·a1`,
    /// `a3 = g·a2` are mutually DERIVED, so a torn set — new `a1` beside stale `a2`,
    /// which a preemption between two stores makes reachable — is not a filter at all.
    /// Its state matrix can reach a spectral radius near 1.4, i.e. +3 dB per sample:
    /// milliseconds to full scale, and the FX path has no non-finite sweep before the
    /// hardware buffer.
    ///
    /// So the solve moved INTO `process`. `g` and `k` are independent again, each an
    /// aligned 32-bit store (atomic on ARM64), and any torn pair is a consistent filter
    /// — tear-tolerance by construction rather than by a narrower window. The cost is
    /// one divide per sample, which is far below what the removed per-sample `tanf` was.
    private var sampleRate: Float
    private var g: Float = 0      // tan(π·fc/SR) — prewarped integrator gain
    private var k: Float = 1      // Damping (2ζ = 1/Q); same role the Chamberlin `q` had
    private var ic1eq: Float = 0  // Integrator 1 state (bandpass path)
    private var ic2eq: Float = 0  // Integrator 2 state (lowpass path)

    // MARK: - Init

    public init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 48000
        updateCoefficients()
    }

    // MARK: - Coefficient Update

    private func updateCoefficients() {
        // Prewarp so the DIGITAL corner lands on the requested frequency (bilinear
        // transform frequency warping). `tan` diverges at Nyquist, so the normalized
        // cutoff is capped just below it — 0.49 rather than 0.5 keeps `g` finite
        // without touching any frequency a user or the bio path can ask for (the
        // parameter registry tops out at 18 kHz, i.e. 0.375 of a 48 kHz rate).
        // A NaN request falls back to a benign 1 kHz rather than propagating into the
        // coefficients. The LOW end gets a floor rather than reaching 0: at g = 0 the
        // integrator state updates collapse to `ic = ic`, so the state does not close —
        // it FREEZES at whatever charge it last held, and at normal magnitude, so the
        // denormal flush never clears it. Lowpass then emits that stuck DC forever, and
        // highpass/notch pass the input plus a stuck offset (a 0 Hz highpass SHOULD be
        // unity — it is the frozen offset riding on it that is wrong). The old
        // Chamberlin form had the same defect. A floor of
        // 1e-5 normalized is ~0.5 Hz at 48 kHz — two decades below the 20 Hz the
        // parameter registry allows, so no musical setting is affected, but the state
        // now decays with a ~0.3 s time constant instead of hanging.
        let requested = cutoff.isFinite ? max(0, cutoff) : 1000
        let normalized = min(max(requested / sampleRate, 1e-5), 0.49)
        g = tanf(Float.pi * normalized)

        // Damping. Kept as `1 - resonance` so the control feel is unchanged from the
        // Chamberlin implementation this replaces: `k` sits in exactly the same place
        // in the highpass expression. The 0.05 floor stops the resonant peak running
        // away into ringing; 0.95 stays expressive without screaming.
        let clampedRes = max(0.01, min(resonance.isFinite ? resonance : 0.3, 0.95))
        k = 1.0 - clampedRes
    }

    // MARK: - Process

    /// Process a single sample through the filter. Audio-thread safe.
    @inline(__always)
    public func process(_ input: Float) -> Float {
        // Read each shared field ONCE into a local, then solve. Re-reading `g` or `k`
        // mid-sample could mix two generations within a single sample's arithmetic;
        // one read each keeps the sample internally consistent.
        let g = self.g
        let k = self.k

        // Solve the zero-delay feedback loop. `1 + g·(g + k)` is strictly positive for
        // g, k > 0, so this division cannot blow up — that is the unconditional-
        // stability guarantee, and it holds for ANY (g, k) pair, which is exactly why
        // solving here rather than caching three derived fields is race-safe.
        let a1 = 1.0 / (1.0 + g * (g + k))
        let a2 = g * a1
        let a3 = g * a2

        let v0 = input
        let v3 = v0 - ic2eq
        let v1 = a1 * ic1eq + a2 * v3
        let v2 = ic2eq + a2 * ic1eq + a3 * v3
        ic1eq = flush(2.0 * v1 - ic1eq)
        ic2eq = flush(2.0 * v2 - ic2eq)

        // All four responses fall out of the same two integrator outputs.
        switch mode {
        case .lowpass:  return v2
        case .bandpass: return v1
        case .highpass: return v0 - k * v1 - v2
        case .notch:    return v0 - k * v1          // == highpass + lowpass
        }
    }

    /// Keep the recursive state numerically healthy. Two failure modes, one guard:
    ///
    /// 1. **Non-finite poisoning — the real reason this exists.** A single NaN reaching
    ///    a recursive accumulator stays there forever; this codebase has shipped
    ///    permanent-silence bugs from exactly that twice. Resetting lets the filter heal
    ///    on the next sample instead of needing the voice torn down. Note ONE poisoned
    ///    sample still escapes to the output before the state resets — deliberate, since
    ///    checking the input first would cost a branch on every sample to fix a case
    ///    that should not occur.
    /// 2. **Denormals** — a secondary benefit, not the justification. A decaying tail
    ///    approaches zero asymptotically and can linger in the denormal range for
    ///    thousands of samples. That is a genuine CPU cliff on x86/SSE; on the ARM64
    ///    ship target NEON flushes denormals and Apple cores handle scalar subnormals
    ///    in hardware, so the win here is small. `1e-25` matches `EchoelDDSP`'s
    ///    existing threshold.
    ///
    /// The two conditions are not redundant: `abs(x) > 1e-25` is already false for NaN
    /// (every comparison against NaN is), so `isFinite` is load-bearing ONLY for ±∞.
    /// Do not "simplify" it away.
    @inline(__always)
    private func flush(_ x: Float) -> Float {
        (x.isFinite && abs(x) > 1e-25) ? x : 0
    }

    /// Process a buffer of samples in-place.
    ///
    /// The caller must own `buffer` UNIQUELY: a second live reference turns the
    /// in-place write into a copy-on-write heap allocation on the audio thread (the
    /// failure class task #94 closed for `RenderScratch`). Every current caller passes
    /// a solely-owned scratch buffer.
    public func processBuffer(_ buffer: inout [Float], frameCount: Int) {
        let n = min(frameCount, buffer.count)
        for i in 0..<n {
            buffer[i] = process(buffer[i])
        }
    }

    /// Reset filter state (call when changing notes to avoid clicks)
    public func reset() {
        ic1eq = 0
        ic2eq = 0
    }
}
