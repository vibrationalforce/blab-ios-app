// EchoelAIBrainTests.swift
// EchoelAI N3 — availability smoke test: on CI (Linux, simulators, runners
// without Apple Intelligence) the Tier-1 brain must report unavailable and
// fail CLEANLY (typed error, no crash). On a future device with the model
// present the test stays valid — it only asserts the unavailable path when
// the backend itself says so.

import XCTest
import Foundation
@testable import Echoelmusic

final class EchoelAIBrainTests: XCTestCase {

    func testFoundationModelsBrain_unavailablePath_isCleanAndTyped() async {
        let brain = FoundationModelsBrain()
        let available = await brain.isAvailable
        guard !available else {
            // Apple-Intelligence device: nothing to assert without network of
            // trust in CI — the unavailable contract is what this test guards.
            return
        }
        do {
            _ = try await brain.respond(to: "ping")
            XCTFail("respond must throw when the model is unavailable")
        } catch let error as EchoelAIError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("must throw EchoelAIError, got \(error)")
        }
    }

    func testFeatureFlag_echoelAI_defaultOff() {
        let defaults = UserDefaults(suiteName: "echoelai.test.\(UUID().uuidString)")!
        XCTAssertFalse(FeatureFlags.isOn(.echoelAI, defaults: defaults),
                       "absent key must read OFF — Release stays bit-identical")
        FeatureFlags.set(.echoelAI, true, defaults: defaults)
        XCTAssertTrue(FeatureFlags.isOn(.echoelAI, defaults: defaults))
    }

    func testEchoelAIError_equatable_forToolSwitching() {
        XCTAssertEqual(EchoelAIError.toolFailed("x"), .toolFailed("x"))
        XCTAssertNotEqual(EchoelAIError.toolFailed("x"), .toolFailed("y"))
        XCTAssertNotEqual(EchoelAIError.unavailable, .guardrailRejected)
    }
}
