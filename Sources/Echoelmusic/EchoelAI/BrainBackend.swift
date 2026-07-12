// BrainBackend.swift
// Echoel — EchoelAI N3 (ADR scratchpads/ECHOELAI_ADR_2026-07-12.md): the
// backend abstraction every EchoelAI feature talks to. Tier 1 is Apple's
// Foundation Models framework (FoundationModelsBrain.swift); Tier 2 (MLX
// fallback) implements this same protocol later. Tier 3 does not exist:
// realtime biosignal modulation NEVER goes through a language model — the
// planner configures control-plane mappings, EngineBus + DSP do the work.
//
// No UI entry, no session persistence, no instructions prose in this cycle —
// a compiling skeleton behind FeatureFlags.echoelAI (default OFF).

import Foundation

/// Errors the brain surface can produce. Deliberately small and stable —
/// tool code and UI switch over THESE, never over backend-specific errors.
public enum EchoelAIError: Error, Equatable, Sendable {
    /// No capable model on this device/OS (or the feature flag is off).
    case unavailable
    /// The system model's safety layer rejected the prompt or response.
    case guardrailRejected
    /// A tool invocation failed (tool name in the payload).
    case toolFailed(String)
    /// Anything else, with a diagnostic description.
    case unknown(String)
}

/// The planner abstraction. Implementations must be safe to call from any
/// task (Sendable); availability is async because the system may need to
/// consult model state.
public protocol BrainBackend: Sendable {
    /// True only when this backend can actually answer on THIS device now.
    var isAvailable: Bool { get async }
    /// One prompt → one response. Throws `EchoelAIError`.
    func respond(to prompt: String) async throws -> String
}
