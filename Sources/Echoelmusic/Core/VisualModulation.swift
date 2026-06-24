//
//  VisualModulation.swift
//  Echoelmusic — bio-reactive IMMERSIVE-VISUAL modulation core.
//
//  The Echoel thesis applied to light: the body (and free LFOs) continuously sculpt
//  the immersive visual — coherence morphing one look into another, the breath
//  swelling the spread, the heartbeat brightening the field. This is the PURE,
//  deterministic core (routes + the value mapping). It is applied NON-DESTRUCTIVELY:
//  the user's set values stay the BASE, and `apply` returns the modulated values to
//  hand to MetalBioView each refresh — so manual edits and bio-modulation never fight.
//
//  Mirrors `FXModulation` exactly (same route/depth/polarity/curve vocabulary) and
//  REUSES `FXModCarrier` + `ModSource` so "what coherence/breath/HR mean" has one
//  definition app-wide. Value types only — no audio-thread work, Linux-testable.
//

import Foundation

/// A modulatable immersive-visual parameter. Each carries the natural range used to
/// scale a normalized [0..1] modulation signal into a real parameter offset, plus a
/// label. Ranges match the live visual controls (and `MetalBioView`'s clamps).
public enum VisualModTarget: String, Codable, Sendable, CaseIterable, Identifiable {
    case intensity
    case detail
    case motion
    case spread
    case hue
    case saturation
    case blend

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .intensity:  return "Intensity"
        case .detail:     return "Detail"
        case .motion:     return "Motion"
        case .spread:     return "Spread"
        case .hue:        return "Hue"
        case .saturation: return "Saturation"
        case .blend:      return "Blend (Mix)"
        }
    }

    /// Natural range — the modulation offset is scaled by its span and the result is
    /// clamped here, matching the EchoelValueField ranges + the renderer's clamps.
    public var range: ClosedRange<Float> {
        switch self {
        case .intensity:  return 0...1.5
        case .detail:     return 8...90
        case .motion:     return 0...1.5
        case .spread:     return 0.5...1.5
        case .hue:        return 0...1
        case .saturation: return 0...2
        case .blend:      return 0...1
        }
    }
}

/// One carrier → visual-target modulation, with depth and polarity. Codable so a whole
/// "bio light scene" can persist with a performance patch.
public struct VisualModRoute: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var carrier: FXModCarrier        // reused: .bio(ModSource) or .lfo
    public var target: VisualModTarget
    /// Output amount [0..1] — the fraction of the target's range the modulation can
    /// move it by (bipolar: ±depth·span/2 around base; unipolar: 0…+depth·span).
    public var depth: Float
    /// Bipolar swings both sides of the user's base value; unipolar only adds.
    public var bipolar: Bool
    /// LFO rate in Hz (used when `carrier == .lfo`).
    public var lfoRateHz: Float
    /// Response shaping applied to the [0..1] carrier signal before depth/polarity.
    public var curve: ResponseCurve
    public var enabled: Bool

    public init(id: UUID = UUID(), carrier: FXModCarrier, target: VisualModTarget,
                depth: Float = 0.5, bipolar: Bool = false, lfoRateHz: Float = 0.2,
                curve: ResponseCurve = .linear, enabled: Bool = true) {
        self.id = id
        self.carrier = carrier
        self.target = target
        self.depth = FXModulation.clamp01(depth)
        self.bipolar = bipolar
        self.lfoRateHz = Swift.max(0.01, lfoRateHz)
        self.curve = curve
        self.enabled = enabled
    }
}

/// The seven live visual parameters, as a value type — the BASE the user sets and the
/// modulated result `apply` returns. Mirrors what `MetalBioView` consumes.
public struct VisualParams: Sendable, Equatable {
    public var intensity: Float
    public var detail: Float
    public var motion: Float
    public var spread: Float
    public var hue: Float
    public var saturation: Float
    public var blend: Float

    public init(intensity: Float, detail: Float, motion: Float, spread: Float,
                hue: Float, saturation: Float, blend: Float) {
        self.intensity = intensity
        self.detail = detail
        self.motion = motion
        self.spread = spread
        self.hue = hue
        self.saturation = saturation
        self.blend = blend
    }

    /// Read the value for one target.
    public func value(for t: VisualModTarget) -> Float {
        switch t {
        case .intensity:  return intensity
        case .detail:     return detail
        case .motion:     return motion
        case .spread:     return spread
        case .hue:        return hue
        case .saturation: return saturation
        case .blend:      return blend
        }
    }

    /// Write the value for one target.
    public mutating func set(_ t: VisualModTarget, _ v: Float) {
        switch t {
        case .intensity:  intensity = v
        case .detail:     detail = v
        case .motion:     motion = v
        case .spread:     spread = v
        case .hue:        hue = v
        case .saturation: saturation = v
        case .blend:      blend = v
        }
    }
}

/// Pure mapping helpers — the deterministic heart of the feature (mirror FXModulation).
public enum VisualModulation {

    /// The signed offset a single route contributes to `target` for a normalized
    /// carrier `signal` in [0..1]. Summed across routes on one target before one clamp.
    public static func offset(target: VisualModTarget, signal: Float,
                              depth: Float, bipolar: Bool) -> Float {
        let span = target.range.upperBound - target.range.lowerBound
        let s = FXModulation.clamp01(signal)
        let d = FXModulation.clamp01(depth)
        let o: Float = bipolar ? (s * 2 - 1) * d * span * 0.5 : s * d * span
        return o.isFinite ? o : 0
    }

    /// Combine a base value with summed route offsets, clamped to the target range.
    /// Hue WRAPS (it is a turn on the colour wheel) rather than clamping.
    public static func combine(base: Float, target: VisualModTarget, offset: Float) -> Float {
        let v = base + offset
        guard v.isFinite else { return base }
        if target == .hue { return v - floor(v) }      // wrap into [0,1)
        let r = target.range
        return Swift.min(Swift.max(v, r.lowerBound), r.upperBound)
    }

    /// Apply all `routes` to `base`, reading body channels from `bio` (nil → bio routes
    /// contribute nothing) and LFOs from `lfoTime` (seconds). Returns the modulated
    /// parameters to hand to the renderer. Pure: same inputs → same output.
    public static func apply(routes: [VisualModRoute], base: VisualParams,
                             bio: BioSampleFrame?, lfoTime: Float) -> VisualParams {
        guard routes.contains(where: { $0.enabled }) else { return base }
        var out = base
        for target in VisualModTarget.allCases {
            var sum: Float = 0
            var touched = false
            for route in routes where route.enabled && route.target == target {
                let raw: Float
                switch route.carrier {
                case .bio(let source):
                    guard let bio else { continue }
                    raw = source.normalizedValue(from: bio)
                case .lfo:
                    let phase = (lfoTime * route.lfoRateHz).truncatingRemainder(dividingBy: 1)
                    raw = FXModulation.lfoUnipolar(phase: phase)
                }
                sum += offset(target: target, signal: route.curve.apply(raw),
                              depth: route.depth, bipolar: route.bipolar)
                touched = true
            }
            if touched {
                out.set(target, combine(base: base.value(for: target), target: target, offset: sum))
            }
        }
        return out
    }
}
