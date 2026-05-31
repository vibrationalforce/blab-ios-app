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

    /// Natural input range of the raw field, used for [0..1] normalization.
    public var range: ClosedRange<Float> {
        switch self {
        case .heartRate:   return 40...200
        case .breathRate:  return 4...30
        case .hrv, .breathPhase, .coherence, .motion: return 0...1
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
    /// Invert the response (1 - value) before depth is applied.
    public var invert: Bool
    /// Whether this route currently contributes output.
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        source: ModSource,
        destination: ModDestination,
        mode: ModMode = .live,
        depth: Float = 1.0,
        invert: Bool = false,
        enabled: Bool = true
    ) {
        self.id = id
        self.source = source
        self.destination = destination
        self.mode = mode
        self.depth = depth
        self.invert = invert
        self.enabled = enabled
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

        let shaped = route.invert ? (1 - base) : base
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
