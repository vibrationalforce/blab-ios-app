// EchoelParameterRegistry.swift
// Echoel — EchoelAI N2: the queryable parameter registry (ADR
// scratchpads/ECHOELAI_ADR_2026-07-12.md). Foundation of the later tool
// surface: an on-device planner never gets parameter DUMPS in its prompt —
// it queries THIS registry through a few generic tools (listParameters /
// searchParameters / setParameter). Today: internal engine parameters only
// (first real inventory = EchoelDDSP), read-only, no UI, no model.
//
// Identity law: a parameter's `keyPath` ("modul.sektion.parameter", e.g.
// "ddsp.filter.cutoff") is the STABLE persisted identity — never a numeric
// AU address, never a display name.
//
// LATER (AUv3 hosting cycle — design note, no code): external plugin
// parameters join this same registry by observing the host's
// `AUAudioUnit.parameterTree` via KVO (plugins REPLACE the tree at runtime,
// so the observation must re-enumerate on change), mapping each
// AUParameter's stable `keyPath` into a descriptor with a "au.<plugin>."
// prefix. Writes to those descriptors go through `setValue(_:originator:)`
// on the control plane — or, while the graph runs and the parameter carries
// flag_CanRamp, through a cached `scheduleParameterBlock`. The registry
// itself stays exactly this shape.

import Foundation

/// One adjustable engine parameter, described for query + typed writes.
/// Codable so tool transcripts / presets can carry descriptors verbatim.
public struct ParameterDescriptor: Codable, Sendable, Equatable, Identifiable {
    /// Stable identity, "modul.sektion.parameter" (see identity law above).
    public var keyPath: String
    public var displayName: String
    public var min: Float
    public var max: Float
    public var defaultValue: Float
    /// Physical unit for display ("Hz", "s"); empty = dimensionless 0–1 style.
    public var unit: String
    /// Optional labels for stepped/enum-like parameters (index = value).
    public var valueLabels: [String]?

    public var id: String { keyPath }

    public init(keyPath: String, displayName: String,
                min: Float, max: Float, defaultValue: Float,
                unit: String = "", valueLabels: [String]? = nil) {
        self.keyPath = keyPath
        self.displayName = displayName
        self.min = min
        self.max = max
        self.defaultValue = defaultValue
        self.unit = unit
        self.valueLabels = valueLabels
    }

    /// Map a normalized 0…1 tool value into the parameter's real range
    /// (clamped — a planner can never push a parameter out of bounds).
    public func denormalized(_ normalized: Float) -> Float {
        let t = Swift.max(0, Swift.min(1, normalized))
        return min + t * (max - min)
    }

    /// Inverse of `denormalized` (0 when the range is degenerate).
    public func normalized(_ value: Float) -> Float {
        guard max > min else { return 0 }
        return Swift.max(0, Swift.min(1, (value - min) / (max - min)))
    }
}

/// The queryable registry. Modules register their descriptors at startup;
/// tools (and later the AUv3 KVO bridge) only ever READ. @MainActor —
/// registration and queries are control-plane; nothing here is called from
/// audio code.
@MainActor
public final class EchoelParameterRegistry {

    /// keyPath → descriptor; insertion order preserved for stable `all()`.
    private var descriptors: [ParameterDescriptor] = []
    private var indexByKeyPath: [String: Int] = [:]

    public init() {}

    /// Register (or replace, by keyPath) a module's descriptors. Replacing
    /// keeps the original position so `all()` stays stable across re-inits.
    public func register(_ newDescriptors: [ParameterDescriptor]) {
        for d in newDescriptors {
            if let i = indexByKeyPath[d.keyPath] {
                descriptors[i] = d
            } else {
                indexByKeyPath[d.keyPath] = descriptors.count
                descriptors.append(d)
            }
        }
    }

    public func all() -> [ParameterDescriptor] { descriptors }

    public func descriptor(for keyPath: String) -> ParameterDescriptor? {
        indexByKeyPath[keyPath].map { descriptors[$0] }
    }

    /// Substring + token match over keyPath, displayName and unit — every
    /// whitespace-separated query token must match somewhere. Empty query
    /// returns everything (that IS listParameters).
    ///
    /// RANKING HOOK (deliberately not implemented today): the semantic
    /// vocabulary (Resources/echoelai-vocabulary.json) will later re-rank
    /// these hits — "dunkler" boosting cutoff/air/damping — via a scoring
    /// closure injected here. Keep the exact-match semantics as the base.
    public func search(query: String) -> [ParameterDescriptor] {
        let tokens = query.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return descriptors }
        return descriptors.filter { d in
            let haystack = "\(d.keyPath) \(d.displayName) \(d.unit)".lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }
}

// MARK: - First real inventory: EchoelDDSP (the bio-reactive synth core)

/// The DDSP voice's musically meaningful control-plane parameters, described
/// against the REAL ranges/defaults in DSP/EchoelDDSP.swift. This is data
/// about the engine, not a second source of truth for DSP behaviour — the
/// voice's own clamps still apply at the write site.
public enum DDSPParameterCatalog {
    public static let descriptors: [ParameterDescriptor] = [
        ParameterDescriptor(keyPath: "ddsp.osc.frequency", displayName: "Oscillator frequency",
                            min: 20, max: 2000, defaultValue: 110, unit: "Hz"),
        ParameterDescriptor(keyPath: "ddsp.osc.harmonicity", displayName: "Harmonicity",
                            min: 0, max: 1, defaultValue: 0.88),
        ParameterDescriptor(keyPath: "ddsp.osc.brightness", displayName: "Brightness",
                            min: 0, max: 1, defaultValue: 0.25),
        ParameterDescriptor(keyPath: "ddsp.osc.noiseLevel", displayName: "Noise level",
                            min: 0, max: 1, defaultValue: 0.01),
        ParameterDescriptor(keyPath: "ddsp.amp.level", displayName: "Amplitude",
                            min: 0, max: 1, defaultValue: 0.5),
        ParameterDescriptor(keyPath: "ddsp.env.attack", displayName: "Envelope attack",
                            min: 0.001, max: 10, defaultValue: 0.5, unit: "s"),
        ParameterDescriptor(keyPath: "ddsp.env.decay", displayName: "Envelope decay",
                            min: 0.001, max: 10, defaultValue: 0.5, unit: "s"),
        ParameterDescriptor(keyPath: "ddsp.env.sustain", displayName: "Envelope sustain",
                            min: 0, max: 1, defaultValue: 0.8),
        ParameterDescriptor(keyPath: "ddsp.env.release", displayName: "Envelope release",
                            min: 0.001, max: 10, defaultValue: 2.0, unit: "s"),
        ParameterDescriptor(keyPath: "ddsp.filter.cutoff", displayName: "Filter cutoff",
                            min: 20, max: 18_000, defaultValue: 220, unit: "Hz"),
        ParameterDescriptor(keyPath: "ddsp.fx.reverbMix", displayName: "Reverb mix",
                            min: 0, max: 1, defaultValue: 0.25),
        ParameterDescriptor(keyPath: "ddsp.fx.reverbDecay", displayName: "Reverb decay",
                            min: 0.1, max: 10, defaultValue: 2.0, unit: "s"),
        ParameterDescriptor(keyPath: "ddsp.mod.vibratoRate", displayName: "Vibrato rate",
                            min: 0, max: 12, defaultValue: 0, unit: "Hz"),
        ParameterDescriptor(keyPath: "ddsp.mod.vibratoDepth", displayName: "Vibrato depth",
                            min: 0, max: 1, defaultValue: 0),
        ParameterDescriptor(keyPath: "ddsp.warmth.drive", displayName: "Warmth drive",
                            min: 0, max: 1, defaultValue: 0),
    ]
}
