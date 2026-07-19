// PolySynthVoiceAutomatableTests.swift
// L2/L4 S2b: pins the single-source-of-truth automatable base table shared by the
// global router binding (bindAutomatable) and the per-track dispatch (applyAutomatable),
// so the two paths can never drift.

import XCTest
@testable import Echoelmusic

@MainActor
final class PolySynthVoiceAutomatableTests: XCTestCase {

    func testAutomatableBases_areTheExpectedSix() {
        XCTAssertEqual(Set(PolySynthVoice.automatableBases), Set([
            "ddsp.warmth.drive", "ddsp.env.attack", "ddsp.env.decay",
            "ddsp.env.sustain", "ddsp.env.release", "ddsp.amp.level"
        ]))
    }

    func testApplyAutomatable_trueForEveryAutomatableBase() {
        let voice = PolySynthVoice(maxVoices: 6)
        for base in PolySynthVoice.automatableBases {
            XCTAssertTrue(voice.applyAutomatable(base: base, real: 0.5),
                          "\(base) should be automatable on the voice")
        }
    }

    func testApplyAutomatable_falseForUnknownOrBioContestedBase() {
        let voice = PolySynthVoice(maxVoices: 6)
        // Unknown + a deliberately-excluded bio-contested param → no-op, never a
        // wrong-parameter write.
        XCTAssertFalse(voice.applyAutomatable(base: "ddsp.nonexistent", real: 0.5))
        XCTAssertFalse(voice.applyAutomatable(base: "ddsp.filter.cutoff", real: 0.5))
        XCTAssertFalse(voice.applyAutomatable(base: "", real: 0.5))
    }

    func testBindAutomatable_bindsExactlyTheAutomatableBases() {
        let voice = PolySynthVoice(maxVoices: 6)
        let router = ParameterApplyRouter(registry: EchoelParameterRegistry())
        voice.bindAutomatable(into: router)
        // The global router binding and the per-track dispatch draw from the same
        // table, so the bound set must equal automatableBases exactly.
        XCTAssertEqual(router.boundKeyPaths, Set(PolySynthVoice.automatableBases))
    }
}
