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
        didSet { updateCoefficients() }
    }

    /// Resonance [0-1] (0.7 = musical, 0.95 = near self-oscillation)
    public var resonance: Float = 0.3 {      // Gentle — no harsh peaking
        didSet { updateCoefficients() }
    }

    /// Active filter mode
    public var mode: Mode = .lowpass

    // MARK: - Internal State

    private var sampleRate: Float
    private var g: Float = 0      // tan(π·fc/SR) — prewarped integrator gain
    private var k: Float = 1      // Damping (2ζ = 1/Q); same role the Chamberlin `q` had
    private var a1: Float = 0     // Solved feedback coefficients (see updateCoefficients)
    private var a2: Float = 0
    private var a3: Float = 0
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
        // coefficients. Zero and negatives are NOT a fallback case: `g = 0` starves both
        // integrators, i.e. a fully-closed filter, which is what a 0 Hz cutoff meant
        // before this rewrite and what any preset carrying one still expects.
        let requested = cutoff.isFinite ? max(0, cutoff) : 1000
        let normalized = min(requested / sampleRate, 0.49)
        g = tanf(Float.pi * normalized)

        // Damping. Kept as `1 - resonance` so the control feel is unchanged from the
        // Chamberlin implementation this replaces: `k` sits in exactly the same place
        // in the highpass expression. The 0.05 floor stops the resonant peak running
        // away into ringing; 0.95 stays expressive without screaming.
        let clampedRes = max(0.01, min(resonance.isFinite ? resonance : 0.3, 0.95))
        k = 1.0 - clampedRes

        // Solve the zero-delay feedback loop once per parameter change rather than
        // per sample. `1 + g·(g + k)` is strictly positive for g, k > 0, so this
        // division cannot blow up — that is the unconditional-stability guarantee.
        a1 = 1.0 / (1.0 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    }

    // MARK: - Process

    /// Process a single sample through the filter. Audio-thread safe.
    @inline(__always)
    public func process(_ input: Float) -> Float {
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
    /// 1. **Denormals.** A decaying IIR tail approaches zero asymptotically and can
    ///    spend thousands of samples in the denormal range, where every operation
    ///    traps into microcode. On a per-voice filter that is a CPU cliff exactly
    ///    during release tails, when the most voices are alive. Flushing to true zero
    ///    ~500 dB below full scale costs nothing audible.
    /// 2. **Non-finite poisoning.** A single NaN reaching a recursive accumulator
    ///    stays there forever — this codebase has shipped permanent-silence bugs from
    ///    that twice. Resetting the state lets the filter recover on its own instead
    ///    of needing the voice torn down.
    @inline(__always)
    private func flush(_ x: Float) -> Float {
        (x.isFinite && abs(x) > 1e-25) ? x : 0
    }

    /// Process a buffer of samples in-place
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
