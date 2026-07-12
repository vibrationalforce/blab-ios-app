// FoundationModelsBrain.swift
// Echoel — EchoelAI N3, Tier 1: Apple Foundation Models (iOS 26+). The
// system's on-device ~3B model; no weights in our process, offline, private.
//
// Encapsulation law (ADR): every FoundationModels symbol lives behind
// `#if canImport(FoundationModels)` + `#available(iOS 26.0, *)` — the
// deployment floor stays iOS 18 and every target (app, AUv3, Linux CI)
// keeps building. On any other path `isAvailable` is false and `respond`
// throws `.unavailable`; nothing crashes, nothing links.
//
// Error mapping note: the exact `LanguageModelSession.GenerationError` case
// signatures are device-SDK territory we cannot compile against locally, so
// the mapping below goes through the error's description (guardrail →
// `.guardrailRejected`, rest → `.unknown`). Tighten to typed cases in the
// first device-verified cycle.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tier-1 backend over the system language model. Stateless (each call makes
/// a fresh session — session persistence is a later cycle), hence Sendable.
public struct FoundationModelsBrain: BrainBackend {

    public init() {}

    public var isAvailable: Bool {
        get async {
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                if case .available = SystemLanguageModel.default.availability {
                    return true
                }
            }
            #endif
            return false
        }
    }

    public func respond(to prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                throw EchoelAIError.unavailable
            }
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                return response.content
            } catch {
                let description = String(describing: error)
                if description.localizedCaseInsensitiveContains("guardrail") {
                    throw EchoelAIError.guardrailRejected
                }
                throw EchoelAIError.unknown(description)
            }
        }
        #endif
        throw EchoelAIError.unavailable
    }
}
