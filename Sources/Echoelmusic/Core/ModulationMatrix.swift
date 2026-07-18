//
//  ModulationMatrix.swift
//  Echoelmusic — Core control-plane modulation routing
//
//  A freely-routable mapping layer: any biofeedback source can drive any
//  destination parameter. Each route is either
//
//    • LIVE   — the source modulates the destination continuously, or
//    • HOLD   — a value was captured and now stays on the destination,
//               either rigidly (drift = 0) or lightly modulated around
//               the captured value by the (still-moving) source.
//
//  This is the generalization the owner specified (2026-05-31):
//  "frei wählbar, welche Parameter von den Biofeedbackdaten moduliert
//   werden. Echtzeit gekoppelt, oder ein gefangener Wert bleibt starr
//   oder leicht moduliert auf dem Parameter."
//
//  v0 scope: pure, Codable value types + a deterministic evaluation
//  function. No audio/UI wiring yet — this is the tested skeleton other
//  cycles route into (synth params, sequencer, OSC out). All outputs are
//  normalized [0..1]; consumers scale to their own parameter range.
//
//  Pure value types only — safe to evaluate anywhere, including off the
//  audio thread by a control-plane subscriber.
//

import Foundation

// MARK: - Source

/// A biofeedback channel that can modulate a parameter. Each case maps to
/// one field of `BioSampleFrame` and carries the natural range used to
/// normalize that field into [0..1].
public enum ModSource: String, Codable, Sendable, CaseIterable {
    case heartRate
    case hrv
    case breathRate
    case breathPhase
    case coherence
    case motion
    // Additive facial-EXPRESSION sources (2026-07-18). Movement/expression used
    // as a CONTROL signal, NEVER an inferred emotion (see FaceExpressionMapping).
    // Appended at the END so existing rawValue/CaseIterable ordering and any
    // persisted routes decode unchanged.
    case faceSmile
    case faceBrow
    case faceJaw

    /// Human label for the "bind this parameter to the body" UI (the one shared
    /// source vocabulary — see BoundParameter / the modulation matrix).
    public var displayName: String {
        switch self {
        case .heartRate:   return "Heartbeat"
        case .hrv:         return "HRV"
        case .breathRate:  return "Breath rate"
        case .breathPhase: return "Breath"
        case .coherence:   return "Coherence"
        case .motion:      return "Motion"
        case .faceSmile:   return "Smile"
        case .faceBrow:    return "Brow"
        case .faceJaw:     return "Jaw"
        }
    }

    /// Natural input range of the raw field, used for [0..1] normalization.
    public var range: ClosedRange<Float> {
        switch self {
        case .heartRate:   return 40...200
        case .breathRate:  return 4...30
        case .hrv, .breathPhase, .coherence, .motion,
             .faceSmile, .faceBrow, .faceJaw: return 0...1
        }
    }

    /// The raw field value for this source from a bio frame.
    public func rawValue(from frame: BioSampleFrame) -> Float {
        switch self {
        case .heartRate:   return frame.heartRateBPM
        case .hrv:         return frame.hrvNormalized
        case .breathRate:  return frame.breathRate
        case .breathPhase: return frame.breathPhase
        case .coherence:   return frame.coherence
        case .motion:      return frame.motionEnergy
        case .faceSmile:   return frame.faceSmile
        case .faceBrow:    return frame.faceBrowRaise
        case .faceJaw:     return frame.faceJawOpen
        }
    }

    /// The source value normalized into [0..1] using `range`.
    public func normalizedValue(from frame: BioSampleFrame) -> Float {
        ModulationMatrix.normalize(rawValue(from: frame), in: range)
    }
}

// MARK: - Destination

/// An opaque, normalized destination parameter key, resolved by whatever
/// consumer owns the parameter (e.g. "synth.cutoff", "tempo", "voice.brightness",
/// "seq.track.0.gate"). Keeping it a string keeps the matrix decoupled from
/// any concrete parameter enum.
public struct ModDestination: Codable, Sendable, Hashable {
    public let key: String
    public init(_ key: String) { self.key = key }
}

// MARK: - Mode

/// How a route maps its source onto its destination.
public enum ModMode: Codable, Sendable, Equatable {
    /// Continuous real-time coupling: destination tracks the source.
    case live
    /// Latched: hold `value` ([0..1]). `drift` ([0..1]) is the amount of
    /// light bipolar modulation applied around the held value by the
    /// (still-moving) source — `drift == 0` is fully rigid.
    case hold(value: Float, drift: Float)
}

// MARK: - Route

/// One source → destination mapping with shaping.
public struct ModRoute: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var source: ModSource
    public var destination: ModDestination
    public var mode: ModMode
    /// Output amount, [0..1]. Scales the final normalized value.
    public var depth: Float
    /// Invert the response (1 - value) before the curve and depth are applied.
    public var invert: Bool
    /// Whether this route currently contributes output.
    public var enabled: Bool
    /// Response shaping applied to the [0..1] value (after invert, before
    /// depth) — pick `.logarithmic` for pitch-like targets, `.exponential`
    /// for loudness-like ones (research §A2). Defaults to `.linear` (identity)
    /// so existing routes and persisted data behave exactly as before.
    public var curve: ResponseCurve
    /// When true, this route only contributes when the bio frame's source is
    /// trustworthy for HRV (a BLE chest strap — `BioSource.providesTrustedHRV`).
    /// Set it on HRV-driven routes so they go silent on wrist/camera/Watch
    /// sources instead of modulating off an unreliable estimate (research §A1).
    /// Defaults to `false`: existing routes never gate.
    public var requiresTrustedSource: Bool
    /// One-pole smoothing time constant in seconds, applied by the stateful
    /// `ModulationEngine` to this route's output (NOT by the pure matrix). 0 =
    /// no smoothing (instant). Use ~0.1–0.3 s for fast targets (filter/bright),
    /// ~0.5–2 s for slow ones (coherence/HRV) to avoid zipper/jumps (research
    /// §A2). Defaults to `0`: existing routes are unsmoothed exactly as before.
    public var smoothingTau: Float

    /// Input SENSITIVITY window (AU2 — "Bio fühlt sich zu neutral an"): bio
    /// operating ranges are narrow (coherence typically lives in ~[0.3,0.6]), so
    /// a full-range destination driven by the raw value only moves a fraction and
    /// feels flat. The source's normalized value is remapped
    /// `[inputLow…inputHigh] → [0…1]` BEFORE invert/curve/depth, so a route can
    /// span its destination from the body's ACTUAL operating range. Defaults
    /// `inputLow=0, inputHigh=1` = identity (existing routes + persisted data
    /// behave EXACTLY as before). A non-positive width falls back to identity
    /// (never divides by zero). Both clamped into [0,1].
    /// NOTE (.hold mode): the window is applied to the FINAL base — including a
    /// latched/held value — so a value captured at e.g. 0.45 under a [0.3,0.6]
    /// window emits 0.5 (the destination always sees windowed output). This is
    /// intentional (the meter/param is consistent with `.live`); it means a held
    /// value is scaled, not reproduced literally.
    public var inputLow: Float
    public var inputHigh: Float

    public init(
        id: UUID = UUID(),
        source: ModSource,
        destination: ModDestination,
        mode: ModMode = .live,
        depth: Float = 1.0,
        invert: Bool = false,
        enabled: Bool = true,
        curve: ResponseCurve = .linear,
        requiresTrustedSource: Bool = false,
        smoothingTau: Float = 0,
        inputLow: Float = 0,
        inputHigh: Float = 1
    ) {
        self.id = id
        self.source = source
        self.destination = destination
        self.mode = mode
        self.depth = depth
        self.invert = invert
        self.enabled = enabled
        self.curve = curve
        self.requiresTrustedSource = requiresTrustedSource
        self.smoothingTau = Swift.max(0, smoothingTau)
        self.inputLow = ModulationMatrix.clamp01(inputLow)
        self.inputHigh = ModulationMatrix.clamp01(inputHigh)
    }

    /// Remap `v` through the sensitivity window `[inputLow, inputHigh] → [0,1]`.
    /// A non-positive width is identity (guards divide-by-zero); result clamped.
    /// With the identity window (0…1) this returns `clamp01(v)` unchanged — the
    /// golden-gate for every pre-AU2 route.
    func windowed(_ v: Float) -> Float {
        guard inputHigh > inputLow else { return ModulationMatrix.clamp01(v) }
        return ModulationMatrix.clamp01((v - inputLow) / (inputHigh - inputLow))
    }

    // Custom Codable so older persisted routes (missing newer keys) still
    // decode with safe defaults. encode(to:) stays synthesized.
    private enum CodingKeys: String, CodingKey {
        case id, source, destination, mode, depth, invert, enabled, curve, requiresTrustedSource, smoothingTau, inputLow, inputHigh
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        source = try c.decode(ModSource.self, forKey: .source)
        destination = try c.decode(ModDestination.self, forKey: .destination)
        mode = try c.decode(ModMode.self, forKey: .mode)
        depth = try c.decode(Float.self, forKey: .depth)
        invert = try c.decode(Bool.self, forKey: .invert)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        curve = try c.decodeIfPresent(ResponseCurve.self, forKey: .curve) ?? .linear
        requiresTrustedSource = try c.decodeIfPresent(Bool.self, forKey: .requiresTrustedSource) ?? false
        smoothingTau = try c.decodeIfPresent(Float.self, forKey: .smoothingTau) ?? 0
        inputLow = ModulationMatrix.clamp01(try c.decodeIfPresent(Float.self, forKey: .inputLow) ?? 0)
        inputHigh = ModulationMatrix.clamp01(try c.decodeIfPresent(Float.self, forKey: .inputHigh) ?? 1)
    }

    /// Returns a copy of this route latched to the source's current value
    /// from `frame`, with the given `drift` (0 = rigid). Implements the
    /// owner's "capture a value, then hold it" action.
    public func captured(from frame: BioSampleFrame, drift: Float = 0) -> ModRoute {
        var copy = self
        copy.mode = .hold(
            value: source.normalizedValue(from: frame),
            drift: ModulationMatrix.clamp01(drift)
        )
        return copy
    }
}

// MARK: - Matrix

/// An ordered collection of routes plus the pure evaluation logic.
public struct ModulationMatrix: Codable, Sendable, Equatable {

    public var routes: [ModRoute]

    public init(routes: [ModRoute] = []) {
        self.routes = routes
    }

    // MARK: Evaluation (pure)

    /// Normalized [0..1] output for one route given a bio frame.
    /// Disabled routes return 0. Deterministic and side-effect free.
    public static func output(for route: ModRoute, frame: BioSampleFrame) -> Float {
        guard route.enabled else { return 0 }
        // HRV-trust gate: a strap-only route stays silent on weak sources.
        if route.requiresTrustedSource && !frame.source.providesTrustedHRV { return 0 }

        let live = route.source.normalizedValue(from: frame)
        let base: Float
        switch route.mode {
        case .live:
            base = live
        case .hold(let held, let drift):
            // Bipolar light modulation around the held value:
            // (live - 0.5) maps [0..1] → [-0.5..0.5]; ×2 → [-1..1]; ×drift scales.
            base = clamp01(held + drift * (live - 0.5) * 2)
        }

        // AU2 sensitivity: expand the body's actual operating range to full
        // scale BEFORE invert/curve/depth (identity for pre-AU2 routes).
        let windowed = route.windowed(base)
        let inverted = route.invert ? (1 - windowed) : windowed
        let shaped = route.curve.apply(inverted)
        return clamp01(shaped * clamp01(route.depth))
    }

    /// Evaluates every route against `frame`, returning the summed,
    /// clamped [0..1] output per destination. Multiple routes onto the
    /// same destination are additive (then clamped).
    public func evaluate(_ frame: BioSampleFrame) -> [ModDestination: Float] {
        var result: [ModDestination: Float] = [:]
        for route in routes {
            let out = Self.output(for: route, frame: frame)
            guard out > 0 else { continue }
            result[route.destination, default: 0] = Self.clamp01((result[route.destination] ?? 0) + out)
        }
        return result
    }

    // MARK: Helpers

    /// Linear normalize `v` from `range` into [0..1]. Degenerate ranges → 0.
    public static func normalize(_ v: Float, in range: ClosedRange<Float>) -> Float {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return clamp01((v - range.lowerBound) / span)
    }

    public static func clamp01(_ v: Float) -> Float {
        if v.isNaN { return 0 }
        return Swift.min(1, Swift.max(0, v))
    }
}
