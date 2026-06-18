// EchoelLanguageModelTests.swift
// Echoel — the modular provider layer: on-device default, deterministic fallback,
// strict token budgeting. Manual/grounded answers must always work, no network.

import XCTest
@testable import Echoelmusic

private struct MockModel: EchoelLanguageModel {
    let available: Bool
    let tag: String
    var isAvailable: Bool { available }
    func respond(to prompt: String, grounding: String?) async throws -> String {
        "\(tag):\(prompt)"
    }
}

final class EchoelLanguageModelTests: XCTestCase {

    // MARK: budget

    func testEstimateTokens() {
        XCTAssertEqual(PromptBudget.estimateTokens(""), 0)
        XCTAssertEqual(PromptBudget.estimateTokens("abcd"), 1)
        XCTAssertEqual(PromptBudget.estimateTokens(String(repeating: "x", count: 40)), 10)
    }

    func testFit_keepsShortInputs() {
        let (p, g) = PromptBudget.fit(prompt: "explain", grounding: "short fact")
        XCTAssertEqual(p, "explain")
        XCTAssertEqual(g, "short fact")
    }

    func testFit_trimsGroundingToBudget_preservesPrompt() {
        let prompt = "explain this"
        let huge = String(repeating: "g", count: 100_000)   // way over 4096-token window
        let (p, g) = PromptBudget.fit(prompt: prompt, grounding: huge)
        XCTAssertEqual(p, prompt, "prompt is never trimmed")
        XCTAssertNotNil(g)
        let total = PromptBudget.estimateTokens(p) + PromptBudget.estimateTokens(g ?? "")
        XCTAssertLessThanOrEqual(total, PromptBudget.sessionTokens - PromptBudget.reservedForResponse)
    }

    // MARK: deterministic fallback

    func testDeterministic_groundingWins() async throws {
        let m = DeterministicLanguageModel()
        XCTAssertTrue(m.isAvailable)
        let out = try await m.respond(to: "anything", grounding: "the fact")
        XCTAssertEqual(out, "the fact")
    }

    func testDeterministic_echoesPromptWhenNoGrounding() async throws {
        let out = try await DeterministicLanguageModel().respond(to: "hello", grounding: nil)
        XCTAssertEqual(out, "hello")
    }

    // MARK: router selection + fallback

    func testRouter_deterministicMode_ignoresOnDevice() async {
        let r = EchoelAIRouter(mode: .deterministic,
                               onDevice: MockModel(available: true, tag: "DEV"))
        let out = await r.respond(to: "p", grounding: "G")
        XCTAssertEqual(out, "G", "deterministic mode never calls the on-device model")
    }

    func testRouter_onDevice_usesModelWhenAvailable() async {
        let r = EchoelAIRouter(mode: .onDevice, onDevice: MockModel(available: true, tag: "DEV"))
        let out = await r.respond(to: "p", grounding: nil)
        XCTAssertEqual(out, "DEV:p")
    }

    func testRouter_onDevice_fallsBackWhenUnavailable() async {
        let r = EchoelAIRouter(mode: .onDevice, onDevice: MockModel(available: false, tag: "DEV"))
        let out = await r.respond(to: "p", grounding: "G")
        XCTAssertEqual(out, "G", "unavailable model → deterministic fallback (grounding wins)")
    }

    func testRouter_cloudOptIn_usesCloudWhenAvailable() async {
        let r = EchoelAIRouter(mode: .cloudOptIn,
                               cloud: MockModel(available: true, tag: "CLOUD"))
        let out = await r.respond(to: "p", grounding: nil)
        XCTAssertEqual(out, "CLOUD:p")
    }

    func testRouter_noProviders_stillAnswers() async {
        let r = EchoelAIRouter(mode: .onDevice)   // no onDevice provided
        let out = await r.respond(to: "p", grounding: nil)
        XCTAssertEqual(out, "p", "always returns a deterministic answer, never throws")
    }
}
