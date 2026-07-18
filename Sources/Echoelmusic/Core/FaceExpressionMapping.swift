//
//  FaceExpressionMapping.swift
//  Echoelmusic — Core control-plane (pure value type)
//
//  Smooths normalized facial-EXPRESSION coefficients (smile, browRaise,
//  jawOpen ∈ [0..1]) into stable modulation channels.
//
//  IMPORTANT — legal + product framing (EU AI Act):
//  These coefficients are treated strictly as EXPRESSION / MOVEMENT used as a
//  CONTROL signal for the instrument — never as inferred "emotion" or an
//  affective state. A raised brow moves a parameter; it is NOT read as a
//  feeling. Keep all copy here and downstream on "Ausdruck/Bewegung als
//  Steuerung", never "Emotion".
//
//  Source-agnostic: the raw coefficients may come from ARKit face blendShapes
//  OR (later) a Vision fallback — this type never imports ARKit/AVFoundation/
//  Vision. It is a pure, deterministic Foundation value type, safe to evaluate
//  anywhere on the control plane.
//
//  Smoothing is a rate-based one-pole EMA driven by wall-clock `dt` (seconds),
//  NOT a frame count — so the response is identical regardless of the producer's
//  frame rate. A neutral face (all zeros) keeps every channel at 0.
//

import Foundation

/// Smoothed, clamped facial-expression control channels.
///
/// All three channels are normalized to [0..1]. The struct carries its own
/// smoothed state; `updated(...)` returns the next state and is a pure function
/// of the current state, the raw targets, and `dt`.
public struct FaceExpressionMapping: Sendable, Equatable {

    /// Default one-pole time constant in seconds. At this τ the channel reaches
    /// ~63 % of a step within one τ. Small enough to feel responsive, large
    /// enough to reject per-frame jitter from the tracker.
    public static let defaultTimeConstant: Double = 0.15

    /// Smile expression as a control value, [0..1]. Not an emotion reading.
    public private(set) var smile: Float

    /// Brow-raise expression as a control value, [0..1]. Not an emotion reading.
    public private(set) var browRaise: Float

    /// Jaw-open expression as a control value, [0..1]. Not an emotion reading.
    public private(set) var jawOpen: Float

    /// One-pole EMA time constant in seconds (≥ 0). 0 = no smoothing (instant).
    public let timeConstant: Double

    public init(
        smile: Float = 0,
        browRaise: Float = 0,
        jawOpen: Float = 0,
        timeConstant: Double = FaceExpressionMapping.defaultTimeConstant
    ) {
        self.smile = Self.clamp01(smile)
        self.browRaise = Self.clamp01(browRaise)
        self.jawOpen = Self.clamp01(jawOpen)
        self.timeConstant = Swift.max(0, timeConstant)
    }

    /// Returns the next state after advancing `dt` seconds toward the given raw
    /// targets. Deterministic and side-effect free.
    ///
    /// - `dt <= 0` returns an unchanged copy (no time elapsed).
    /// - Raw targets are clamped to [0..1] before smoothing.
    /// - Convergence is monotonic toward each (constant) target.
    public func updated(
        rawSmile: Float,
        rawBrowRaise: Float,
        rawJawOpen: Float,
        dt: Double
    ) -> FaceExpressionMapping {
        let alpha = Self.alpha(dt: dt, tau: timeConstant)
        var copy = self
        copy.smile = Self.ema(current: smile, target: Self.clamp01(rawSmile), alpha: alpha)
        copy.browRaise = Self.ema(current: browRaise, target: Self.clamp01(rawBrowRaise), alpha: alpha)
        copy.jawOpen = Self.ema(current: jawOpen, target: Self.clamp01(rawJawOpen), alpha: alpha)
        return copy
    }

    // MARK: - Pure helpers

    /// One-pole smoothing coefficient for elapsed `dt` and time constant `tau`.
    /// `alpha = 1 - exp(-dt / tau)`, in [0..1]. `dt <= 0` → 0 (hold);
    /// `tau <= 0` → 1 (instant).
    static func alpha(dt: Double, tau: Double) -> Float {
        guard dt > 0 else { return 0 }
        guard tau > 0 else { return 1 }
        let a = 1 - exp(-dt / tau)
        if a.isNaN { return 0 }
        return Float(Swift.min(1, Swift.max(0, a)))
    }

    /// One EMA step: `current + alpha * (target - current)`, clamped to [0..1].
    static func ema(current: Float, target: Float, alpha: Float) -> Float {
        clamp01(current + alpha * (target - current))
    }

    static func clamp01(_ v: Float) -> Float {
        if v.isNaN { return 0 }
        return Swift.min(1, Swift.max(0, v))
    }

    // MARK: - ARKit blendShape → channel mapping (pure, ARKit-free)

    /// The ARKit `ARFaceAnchor.BlendShapeLocation` raw keys we read. Kept as plain
    /// strings so this Core type never imports ARKit — the device-side publisher
    /// builds a `[String: Float]` from the anchor and calls `rawChannels(from:)`.
    /// ARKit blendShape coefficients are already normalized to [0..1].
    public enum BlendShapeKey {
        public static let mouthSmileLeft = "mouthSmileLeft"
        public static let mouthSmileRight = "mouthSmileRight"
        public static let browInnerUp = "browInnerUp"
        public static let browOuterUpLeft = "browOuterUpLeft"
        public static let browOuterUpRight = "browOuterUpRight"
        public static let jawOpen = "jawOpen"
    }

    /// Reduces a bag of ARKit blendShape coefficients to the three EXPRESSION
    /// control channels. Pure, deterministic, ARKit-free — the raw feed for
    /// `updated(rawSmile:rawBrowRaise:rawJawOpen:dt:)`.
    ///
    /// - smile = mean(mouthSmileLeft, mouthSmileRight) — symmetric mouth corners.
    /// - browRaise = mean(browInnerUp, browOuterUpLeft, browOuterUpRight) — the
    ///   whole brow lifting, center + both outer edges.
    /// - jawOpen = jawOpen — the mouth opening directly.
    ///
    /// Missing keys count as `0` (that muscle simply not tracked / at rest); every
    /// output is clamped to [0..1]. A neutral / empty bag yields all zeros, so a
    /// lost face reads as "no expression", never a spike.
    public static func rawChannels(
        from blendShapes: [String: Float]
    ) -> (smile: Float, browRaise: Float, jawOpen: Float) {
        func value(_ key: String) -> Float { clamp01(blendShapes[key] ?? 0) }
        let smile = (value(BlendShapeKey.mouthSmileLeft)
                     + value(BlendShapeKey.mouthSmileRight)) / 2
        let brow = (value(BlendShapeKey.browInnerUp)
                    + value(BlendShapeKey.browOuterUpLeft)
                    + value(BlendShapeKey.browOuterUpRight)) / 3
        let jaw = value(BlendShapeKey.jawOpen)
        return (clamp01(smile), clamp01(brow), clamp01(jaw))
    }
}
