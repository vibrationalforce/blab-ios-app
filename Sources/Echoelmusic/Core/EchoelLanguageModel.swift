//
//  EchoelLanguageModel.swift
//  Echoelmusic — Core (EchoelAI infrastructure)
//
//  The provider-agnostic language layer. The whole app talks to ONE interface,
//  never a concrete backend, so inference providers swap by configuration
//  (deterministic ⟷ Apple Foundation Models on-device ⟷ explicit opt-in cloud) —
//  the "hybrid-first, modular provider" rule, with a strict ON-DEVICE DEFAULT.
//
//  This file is pure Foundation: the protocol, a guaranteed deterministic
//  fallback, a token-budget guard for the on-device context window, and the
//  router. The Apple Foundation Models adapter conforms to this protocol in a
//  separate, availability-guarded file (next cycle). No external dependency.
//
//  Design facts baked in (Apple Foundation Models, iOS 26): the on-device session
//  window is 4096 tokens (input + output). We budget conservatively and trim
//  grounding (Direct Document Injection RAG) first, never the user's prompt.
//

import Foundation

/// Errors surfaced by a language provider or an EchoelAI tool. ONE error
/// surface app-wide (the night-ADR's `guardrailRejected` maps to `refused` —
/// the system safety layer refused prompt or response). Equatable so tool
/// code and tests can switch on it.
public enum EchoelAIError: Error, Sendable, Equatable {
    case unavailable
    case contextOverflow
    case refused
    /// A tool invocation failed (payload names the tool/keyPath) — the
    /// planner receives a correctable message, never a silent no-op.
    case toolFailed(String)
    /// Anything else, with a diagnostic description.
    case unknown(String)
}

/// Provider-agnostic, OpenAI-compatible-style language interface. Implementations
/// must respect the on-device token budget and must never require the network
/// unless they are an explicit opt-in cloud provider.
public protocol EchoelLanguageModel: Sendable {
    /// Whether this provider can serve a request right now.
    var isAvailable: Bool { get }
    /// Respond to `prompt`, optionally grounded in caller-supplied `grounding`
    /// text (Direct Document Injection — the model reasons over OUR facts, not
    /// its unaided recall, which a ~3B model gets wrong).
    func respond(to prompt: String, grounding: String?) async throws -> String
}

/// On-device context budgeting. Apple Foundation Models exposes a 4096-token
/// session window; we leave room for the response and trim grounding to fit.
public enum PromptBudget {
    public static let sessionTokens = 4096
    public static let reservedForResponse = 512

    /// Cheap, dependency-free token estimate (~4 characters per token).
    public static func estimateTokens(_ text: String) -> Int { (text.count + 3) / 4 }

    /// Fit prompt + grounding into the budget. The prompt is preserved; grounding
    /// is trimmed (head-first) to whatever room remains.
    public static func fit(prompt: String, grounding: String?) -> (prompt: String, grounding: String?) {
        guard var g = grounding, !g.isEmpty else { return (prompt, grounding) }
        let budget = sessionTokens - reservedForResponse
        let allowedForGrounding = max(0, budget - estimateTokens(prompt))
        if estimateTokens(g) > allowedForGrounding {
            g = String(g.prefix(max(0, allowedForGrounding * 4)))
        }
        return (prompt, g.isEmpty ? nil : g)
    }
}

/// Always-available, fully deterministic fallback — no model, no network. It
/// returns the grounded fact verbatim when given one (so EVERY device, including
/// pre-Apple-Intelligence hardware, gets a useful, private, free answer and the
/// LLM layer stays purely additive — never a blank screen).
public struct DeterministicLanguageModel: EchoelLanguageModel {
    public init() {}
    public var isAvailable: Bool { true }
    public func respond(to prompt: String, grounding: String?) async throws -> String {
        if let g = grounding, !g.isEmpty { return g }   // grounded copy wins — zero hallucination
        return prompt
    }
}

/// Picks the best available provider by configuration + availability, always
/// falling back to the deterministic provider. App default = `.onDevice`
/// (never cloud unless the user explicitly opts in).
public struct EchoelAIRouter: Sendable {
    public enum Mode: Sendable, Equatable { case deterministic, onDevice, cloudOptIn }

    public var mode: Mode
    private let onDevice: (any EchoelLanguageModel)?
    private let cloud: (any EchoelLanguageModel)?
    private let fallback: any EchoelLanguageModel

    public init(mode: Mode = .onDevice,
                onDevice: (any EchoelLanguageModel)? = nil,
                cloud: (any EchoelLanguageModel)? = nil,
                fallback: any EchoelLanguageModel = DeterministicLanguageModel()) {
        self.mode = mode
        self.onDevice = onDevice
        self.cloud = cloud
        self.fallback = fallback
    }

    /// The provider chosen for the current mode, if it is available.
    private var preferred: (any EchoelLanguageModel)? {
        switch mode {
        case .deterministic: return nil
        case .onDevice:      return (onDevice?.isAvailable == true) ? onDevice : nil
        case .cloudOptIn:    return (cloud?.isAvailable == true) ? cloud : nil
        }
    }

    /// Respond with budgeting + guaranteed fallback. Never throws — a degraded
    /// deterministic answer is always returned.
    public func respond(to prompt: String, grounding: String? = nil) async -> String {
        let (p, g) = PromptBudget.fit(prompt: prompt, grounding: grounding)
        if let model = preferred, let out = try? await model.respond(to: p, grounding: g) {
            return out
        }
        return (try? await fallback.respond(to: p, grounding: g)) ?? (g ?? p)
    }
}
