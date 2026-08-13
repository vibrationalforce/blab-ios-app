// PolySynthVoiceAutomatableTests.swift
// L2/L4 S2b: pins the single-source-of-truth automatable base table shared by the
// global router binding (bindAutomatable) and the per-track dispatch (applyAutomatable),
// so the two paths can never drift.

import XCTest
@testable import Echoelmusic

@MainActor
final class PolySynthVoiceAutomatableTests: XCTestCase {

    /// ⛔ THIS CASE WAS STALE BY FOUR BEFORE #564 TOUCHED IT, and the staleness is a fact about
    /// the SUITE, not about this list: `Tests/EchoelmusicTests` is compiled by no gate (#208), so
    /// #557 (two anchors), #558 (the vibrato pair) and #564 (brightness) each grew
    /// `automatableBases` without the compiler or a run ever contradicting the "expected six"
    /// written here. It is corrected rather than deleted because the exact-set shape is the point
    /// — `bindAutomatable` and `applyAutomatable` both read this table, so a silent addition
    /// reaches both paths. The BLOCKING guards are `TheAutomatableSetHasOneWriterTests` and
    /// `TheAutomatableSetIsWhatMovesAudioTests`; those decide whether a base may be here at all.
    func testAutomatableBases_areTheExpectedEleven() {
        XCTAssertEqual(Set(PolySynthVoice.automatableBases), Set([
            "ddsp.warmth.drive", "ddsp.env.attack", "ddsp.env.decay",
            "ddsp.env.sustain", "ddsp.env.release", "ddsp.amp.level",
            "ddsp.osc.harmonicity", "ddsp.osc.noiseLevel",
            "ddsp.mod.vibratoDepth", "ddsp.mod.vibratoRate",
            "ddsp.osc.brightness"
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
