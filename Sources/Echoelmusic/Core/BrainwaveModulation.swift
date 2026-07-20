//
//  BrainwaveModulation.swift
//  Echoelmusic — Core (pure, cross-platform)
//
//  Founder 2026-07-16 (Haffelder framing): EEG as a modulation SOURCE —
//  spectral BAND POWER plus interhemispheric COHERENCE, mapped to the same
//  normalized [0…1] currency every other bio driver speaks, ready to steer
//  DDSP (harmonicity, brightness, shape) once a sensor bridge lands.
//
//  This is the pure FOUNDATION half (like VocoderCore / BioModulationMap): it
//  owns the band model and the derived indices, with no sensor, no engine, no
//  @MainActor — so the maths is unit-tested on every platform (Linux included)
//  and can be wired to a real EEG stream or folded into `BioSampleFrame`/`ModSource`
//  in a later, device-gated cycle without re-deriving any coefficient.
//
//  Values are SELF-OBSERVATION signals for sound design, never a clinical readout
//  (Echoel's standing rule: data for self-observation, not medical diagnosis).
//  Relative power = a band's share of total spectral power; hemisphere coherence
//  = how similarly the two hemispheres' band distributions are shaped (cosine
//  similarity of their relative-power vectors). Every output is finite and
//  clamped to [0…1]; every division is guarded.
//

import Foundation

/// Absolute spectral power per canonical EEG band (e.g. µV², arbitrary but
/// consistent units — only ratios are used downstream). Non-finite or negative
/// input collapses to 0 on init, so a bad sample degrades instead of propagating.
public struct EEGBandPowers: Codable, Sendable, Equatable {

    public let delta: Float   // ~0.5–4 Hz
    public let theta: Float   // ~4–8 Hz
    public let alpha: Float   // ~8–13 Hz
    public let beta: Float    // ~13–30 Hz
    public let gamma: Float   // ~30–100 Hz

    public init(delta: Float = 0, theta: Float = 0, alpha: Float = 0,
                beta: Float = 0, gamma: Float = 0) {
        func clean(_ v: Float) -> Float { v.isFinite ? Swift.max(0, v) : 0 }
        self.delta = clean(delta)
        self.theta = clean(theta)
        self.alpha = clean(alpha)
        self.beta = clean(beta)
        self.gamma = clean(gamma)
    }

    /// Sum of all band powers (≥0, always finite).
    public var total: Float { delta + theta + alpha + beta + gamma }

    /// Power of one band by case.
    public func power(_ band: BrainwaveModulation.Band) -> Float {
        switch band {
        case .delta: return delta
        case .theta: return theta
        case .alpha: return alpha
        case .beta:  return beta
        case .gamma: return gamma
        }
    }
}

/// Pure EEG → normalized [0…1] modulation currency.
public enum BrainwaveModulation {

    /// Canonical EEG bands, low → high frequency.
    public enum Band: String, Codable, Sendable, CaseIterable {
        case delta, theta, alpha, beta, gamma
    }

    /// A band's share of total spectral power, 0…1. Silent spectrum (total 0) → 0.
    public static func relativePower(_ band: Band, in powers: EEGBandPowers) -> Float {
        let total = powers.total
        guard total > 0 else { return 0 }
        return clamp01(powers.power(band) / total)
    }

    /// Relaxation index — alpha vs. beta balance, `alpha / (alpha + beta)`, 0…1.
    /// High alpha over beta (calm, eyes-closed rest) → toward 1; beta-dominant
    /// (alert/engaged) → toward 0. No alpha+beta power → 0.5 (neutral).
    public static func relaxationIndex(_ powers: EEGBandPowers) -> Float {
        let denom = powers.alpha + powers.beta
        guard denom > 0 else { return 0.5 }
        return clamp01(powers.alpha / denom)
    }

    /// Arousal / engagement index — fast activity over slow, `(beta + gamma) /
    /// (theta + alpha + beta + gamma)`, 0…1. Delta (often movement/ocular
    /// artifact) is intentionally excluded. No qualifying power → 0.
    public static func arousalIndex(_ powers: EEGBandPowers) -> Float {
        let fast = powers.beta + powers.gamma
        let denom = powers.theta + powers.alpha + powers.beta + powers.gamma
        guard denom > 0 else { return 0 }
        return clamp01(fast / denom)
    }

    /// Meditative depth — theta share of the theta+alpha "slow-wave" band,
    /// `theta / (theta + alpha)`, 0…1. Deep relaxation/absorption raises theta.
    /// No theta+alpha power → 0.
    public static func meditativeIndex(_ powers: EEGBandPowers) -> Float {
        let denom = powers.theta + powers.alpha
        guard denom > 0 else { return 0 }
        return clamp01(powers.theta / denom)
    }

    /// Interhemispheric coherence — how similarly the two hemispheres' band
    /// distributions are SHAPED, as the cosine similarity of their band-power
    /// vectors, 0…1. (Cosine is scale-invariant, so absolute vs. relative power
    /// gives the same value — it compares SHAPE, not magnitude.) Identical
    /// distributions → 1 (high synchrony); orthogonal → 0.
    /// A silent hemisphere (no power) yields 0 (no defined direction to compare).
    public static func hemisphereCoherence(left: EEGBandPowers, right: EEGBandPowers) -> Float {
        let l = [left.delta, left.theta, left.alpha, left.beta, left.gamma]
        let r = [right.delta, right.theta, right.alpha, right.beta, right.gamma]
        var dot: Float = 0, nl: Float = 0, nr: Float = 0
        for i in 0..<l.count {
            dot += l[i] * r[i]
            nl += l[i] * l[i]
            nr += r[i] * r[i]
        }
        let denom = (nl * nr).squareRoot()
        guard denom > 0 else { return 0 }
        return clamp01(dot / denom)
    }

    // MARK: - Helpers

    static func clamp01(_ v: Float) -> Float {
        guard v.isFinite else { return 0 }
        return Swift.min(1, Swift.max(0, v))
    }
}
