// ParameterToolCore.swift
// Echoel — EchoelAI N4 (safe subset): the tool LOGIC behind listParameters /
// searchParameters / setParameter, model-free and directly testable (the
// night mandate's own test rule: call tool logic directly, mock the model).
//
// The FoundationModels `Tool`/@Generable conformances are DELIBERATELY not
// in this cycle: their exact macro/API signatures are device-SDK territory
// we cannot compile locally, and a wrong guess turns the Xcode gate red
// (night rule 7). When the first Apple-Intelligence device cycle runs, the
// wrappers are thin: Arguments{query} → ParameterToolCore.list(...),
// Arguments{keyPath, normalizedValue} → ParameterToolCore.set(...).
//
// Write-path law (ADR Tier 3): the model NEVER writes DSP state. `set`
// validates against the registry, clamps via the descriptor, and hands the
// REAL value to an injected control-plane apply closure — the caller decides
// what "apply" means (today: a MainActor voice setter; later: a typed
// EngineBus control message once that design lands against the real bus).

import Foundation

/// Result of a set-parameter tool call — Codable so a transcript can carry it.
public struct ParameterSetResult: Codable, Sendable, Equatable {
    public var keyPath: String
    /// The clamped REAL value that was applied (denormalized).
    public var appliedValue: Float
    public var unit: String
}

@MainActor
public enum ParameterToolCore {

    /// listParameters / searchParameters: empty query = full inventory.
    public static func list(registry: EchoelParameterRegistry,
                            query: String) -> [ParameterDescriptor] {
        registry.search(query: query)
    }

    /// setParameter: validate keyPath, clamp the normalized tool value into
    /// the descriptor's real range, apply on the control plane. Unknown
    /// keyPath throws `.toolFailed` with the offending path — the planner
    /// gets a correctable error instead of a silent no-op.
    public static func set(keyPath: String,
                           normalizedValue: Float,
                           registry: EchoelParameterRegistry,
                           apply: (ParameterDescriptor, Float) -> Void) throws -> ParameterSetResult {
        guard let descriptor = registry.descriptor(for: keyPath) else {
            throw EchoelAIError.toolFailed("unknown parameter keyPath: \(keyPath)")
        }
        let value = descriptor.denormalized(normalizedValue)
        apply(descriptor, value)
        return ParameterSetResult(keyPath: descriptor.keyPath,
                                  appliedValue: value,
                                  unit: descriptor.unit)
    }
}
