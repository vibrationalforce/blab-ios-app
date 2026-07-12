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

// Error surface: `EchoelAIError` lives in Core/EchoelLanguageModel.swift —
// the EXISTING provider-agnostic language layer (discovered red-gate lesson
// 2026-07-12: this module already had the enum; one error type app-wide,
// `refused` == the ADR's guardrail rejection). This file adds no error type.

/// The planner abstraction. Implementations must be safe to call from any
/// task (Sendable); availability is async because the system may need to
/// consult model state.
public protocol BrainBackend: Sendable {
    /// True only when this backend can actually answer on THIS device now.
    var isAvailable: Bool { get async }
    /// One prompt → one response. Throws `EchoelAIError`.
    func respond(to prompt: String) async throws -> String
}
