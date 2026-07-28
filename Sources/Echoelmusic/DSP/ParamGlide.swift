//
//  ParamGlide.swift
//  Echoelmusic — one-pole parameter glide for the audio path.
//
//  Control-rate writes are steps. The FX chain's parameters are written by a 30 Hz
//  driver off a bio carrier that itself only updates at ~10 Hz, and no `EchoelFXChain`
//  stage smooths its own parameters — so a body-driven filter sweep is a staircase, and
//  on a resonant filter each step is an audible edge rather than a sweep.
//
//  `EchoelDelay` already solved this for one parameter, inline: it keeps `timeSeconds`
//  as the control-plane TARGET and glides a separate `timeSmoothed` toward it in the
//  render loop, "so a preset/character switch slides the read tap instead of jumping it
//  — a jump is a click". This is that idiom extracted, so the rest of the chain can use
//  it without each stage reinventing the coefficient.
//
//  Audio-thread safe by construction: a value type holding a single Float, pure
//  arithmetic, no allocation, no locks, no access to shared mutable state.
//

import Foundation

/// A value that glides toward a target with a one-pole response.
///
/// The distinction that makes this usable across the chain: `value` is what the AUDIO
/// should hear, and it is deliberately NOT where the control plane reads its state from.
/// Whoever owns the parameter keeps the target as the authoritative number — so a preset
/// save, a UI readout, or a modulation driver capturing a base all see the value the user
/// set, never a number caught mid-glide.
public struct ParamGlide: Sendable, Equatable {

    /// The current audible value.
    public private(set) var value: Float

    public init(_ initial: Float = 0) {
        value = initial.isFinite ? initial : 0
    }

    /// The time constant for a parameter driven by the BODY (the bio carriers, which
    /// land a new value about every 100 ms).
    ///
    /// Chosen by measurement, not taste. A smaller τ still removes the discontinuity —
    /// the integrator kick, the click — but leaves the staircase: at τ = 0.02 the
    /// one-pole corner sits at 8 Hz, right on top of a 10 Hz step train, so the ripple
    /// comes down only ~4 dB and a body-driven sweep still reads as ten events a second.
    /// At τ = 0.05 the corner is 3.2 Hz, the ripple is ~10 dB down, and — the part that
    /// actually matters — the glide is still moving when the next value arrives (86 %
    /// of the way there at 100 ms), so consecutive steps overlap into one contour
    /// instead of ten separate ramps. The cost is 50 ms of lag on a body gesture, which
    /// is imperceptible and three orders below the 4–5 s Watch HR latency this platform
    /// already lives with. Sits just above the house precedent — `EchoelDelay` uses 40 ms
    /// for its read tap.
    ///
    /// Honest limit: this is DECLICKING plus a softened contour. At any τ the staircase
    /// only truly disappears when the carrier itself runs at block rate.
    public static let bioTau: Float = 0.05

    /// One-pole coefficient for a `tauSeconds` time constant when `advance` is called
    /// `stepRateHz` times a second.
    ///
    /// Rate-based, per the project law, and EXACTLY so rather than approximately:
    /// `v_n = T + (v₀−T)·(1−c)^n = T + (v₀−T)·e^(−t/τ)`, in which the step count and the
    /// rate survive only as elapsed time. So the same glide takes the same wall-clock
    /// time whether it is stepped once per sample or once per audio block.
    ///
    /// That is what lets the intended caller be BLOCK-rate. Per-sample gliding of a
    /// cutoff is NOT forbidden — `EchoelDDSP` does exactly that today, inside its render
    /// loop, and `EchoelSVFilter`'s equality guard exists to make it cheap. But `tanf`
    /// still runs on every sample for which the glide is moving: ~3000 samples per glide
    /// at 48 kHz versus ~10 calls at block rate, for no audible difference, because the
    /// filter's integrators cannot resolve cutoff motion within a block anyway.
    ///
    /// Pass the rate derived from the ACTUAL block (`sampleRate / frameCount`), never an
    /// assumed one: render blocks are variable, so a coefficient cached against an
    /// assumed 256 frames would make the glide's duration scale with whatever buffer the
    /// host hands us — reintroducing at the call site the very rate-dependence this
    /// formula removes.
    ///
    /// A non-positive or non-finite tau or rate yields 1 — "instant", i.e. no glide.
    public static func coefficient(tauSeconds: Float, stepRateHz: Float) -> Float {
        guard tauSeconds.isFinite, tauSeconds > 0,
              stepRateHz.isFinite, stepRateHz > 0 else { return 1 }
        let c = 1 - expf(-1 / (tauSeconds * stepRateHz))
        guard c.isFinite else { return 1 }
        return Swift.min(Swift.max(c, 0), 1)
    }

    /// Step once toward `target`.
    ///
    /// `epsilon` buys EXACTNESS and a bounded settle time — not CPU. Be precise about
    /// that, because the tempting justification is wrong: a Float32 one-pole does stop
    /// on its own (the increment falls below half an ULP and rounds away), and once the
    /// value stops changing, a downstream `didSet` equality guard stops firing too. What
    /// it actually prevents is the glide STALLING a hair short of its target and staying
    /// there — with an absolute-only threshold, a cutoff heading for 18 000 Hz settles
    /// nowhere near it, because an absolute 1e-4 is unreachable at that magnitude (one
    /// ULP there is ~0.002). Hence the relative term, which is live for cutoff-scale
    /// values and dead for every 0…1 parameter, where the absolute floor takes over —
    /// including a target of exactly 0, where a purely relative rule would never settle.
    ///
    /// Usable up to about τ = 2 s at block rate. Beyond that the per-step increment
    /// itself falls under half an ULP at cutoff magnitudes and the glide stalls sub-Hz
    /// short — harmless, but it will not reach the target exactly.
    ///
    /// A non-finite target is ignored (hold the last good value) rather than propagated.
    /// Precisely: the ONE consumer today is `EchoelFXChain`'s tone filter, and that filter
    /// substitutes 1 kHz for a non-finite cutoff of its own accord — so this guard is not
    /// what stands between a NaN and permanent silence there, as an earlier version of
    /// this line claimed. What it buys is that the parameter keeps a MEANINGFUL value
    /// instead of a substitute one, and that a future consumer without such a substitute
    /// (a delay read tap, an oscillator frequency, anything feeding recursive state where
    /// a NaN does not decay out) inherits the guard rather than needing its own.
    public mutating func advance(toward target: Float, coefficient: Float,
                                 epsilon: Float = 1e-4) {
        guard target.isFinite else { return }
        let c = coefficient.isFinite ? Swift.min(Swift.max(coefficient, 0), 1) : 1
        // `Swift.max(.nan, x)` returns NaN — argument order decides, per the house rule —
        // and a NaN threshold makes every `<=` false, so the glide would never settle.
        let eps = (epsilon.isFinite && epsilon > 0) ? epsilon : 1e-4
        let settleAt = Swift.max(Swift.abs(target) * 1e-5, eps)
        if Swift.abs(target - value) <= settleAt {
            value = target
            return
        }
        let next = value + c * (target - value)
        value = next.isFinite ? next : target
    }

    /// Jump straight to `target`, no glide. For the moments where a glide would be
    /// WRONG rather than merely fast: loading a document, a `reset()` on an empty
    /// signal path, or the first value after a stage is enabled — there is nothing to
    /// glide from, and gliding up from a stale value is itself the artifact.
    public mutating func snap(to target: Float) {
        guard target.isFinite else { return }
        value = target
    }
}
