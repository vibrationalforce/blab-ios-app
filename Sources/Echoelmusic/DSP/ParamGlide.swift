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
//  Audio-thread safe by construction: a value type of two Floats, pure arithmetic, no
//  allocation, no locks, no branches on shared state.
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

    /// One-pole coefficient for a `tauSeconds` time constant when `advance` is called
    /// `stepRateHz` times a second.
    ///
    /// Rate-based, per the project law: derived from elapsed time, so the same glide
    /// takes the same wall-clock time whether it is stepped once per sample or once per
    /// audio block. That matters here because the intended caller is BLOCK-rate — the
    /// filter recomputes a `tanf` whenever its cutoff changes, so gliding it per sample
    /// would reintroduce the per-sample transcendental that was deliberately removed
    /// from that stage. A 256-frame block at 48 kHz steps ~188 times a second, which is
    /// already ~19× finer than the 10 Hz carrier that causes the staircase.
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
    /// `epsilon` is not a rounding detail — it is what lets the glide FINISH. A one-pole
    /// approaches its target asymptotically and never arrives, and a parameter that never
    /// stops changing keeps every `didSet` downstream firing forever: on the state-variable
    /// filter that means recomputing `tanf` on every block for the rest of the session,
    /// long after the movement is inaudible. Snapping at the threshold ends it.
    ///
    /// A non-finite target is ignored (hold the last good value) rather than propagated —
    /// this feeds a recursive filter, where one NaN is permanent.
    public mutating func advance(toward target: Float, coefficient: Float,
                                 epsilon: Float = 1e-4) {
        guard target.isFinite else { return }
        let c = coefficient.isFinite ? Swift.min(Swift.max(coefficient, 0), 1) : 1
        // Relative for large-magnitude parameters (cutoff is in Hz, up to 18 000, where
        // an absolute 1e-4 would never be reached in Float), absolute for the 0…1 ones.
        let settleAt = Swift.max(epsilon, Swift.abs(target) * 1e-5)
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
