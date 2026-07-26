// LaneVoiceKindTests.swift
// Pure tests for the instrument→voice-class map (B10). No engine → every platform.

import XCTest
@testable import Echoelmusic

final class LaneVoiceKindTests: XCTestCase {

    func testEveryInstrumentMapsToAVoiceKind() {
        // Total map — no instrument is left without a concrete voice class.
        for inst in TrackInstrument.allCases {
            _ = inst.voiceKind   // exhaustive switch; compiles + never traps
        }
    }

    func testDirectMappings() {
        XCTAssertEqual(TrackInstrument.polySynth.voiceKind, .poly)
        XCTAssertEqual(TrackInstrument.sampler.voiceKind, .sampler)
        XCTAssertEqual(TrackInstrument.subBass.voiceKind, .subBass)
        XCTAssertEqual(TrackInstrument.bioVoice.voiceKind, .bioVoice)
    }

    func testFormerDrumAliasesResolveToPoly() {
        // NO DRUMS (founder 2026-07-26: "es soll keine Drums geben. Auch nicht im Mixer.").
        // Both former drum aliases resolve to `.poly`, so a project persisted BEFORE this
        // build comes back audible as a melodic voice instead of binding to a kit that no
        // longer exists in the graph. This is the DATA half of the removal — the UI half
        // cannot create either instrument any more, but old documents can still contain one.
        XCTAssertEqual(TrackInstrument.drums.voiceKind, .poly)
        XCTAssertEqual(TrackInstrument.breakLoop.voiceKind, .poly)
        for inst in TrackInstrument.allCases {
            XCTAssertNotEqual(inst.voiceKind, .drums,
                              "\(inst) still resolves to a drum kit — no instrument may")
        }
    }

    func testRawValuesStableForPersistence() {
        XCTAssertEqual(LaneVoiceKind.poly.rawValue, "poly")
        XCTAssertEqual(LaneVoiceKind.drums.rawValue, "drums")
        XCTAssertEqual(LaneVoiceKind.sampler.rawValue, "sampler")
        XCTAssertEqual(LaneVoiceKind.subBass.rawValue, "subBass")
        XCTAssertEqual(LaneVoiceKind.bioVoice.rawValue, "bioVoice")
    }

    func testDisplayNamesUnique() {
        let names = LaneVoiceKind.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, LaneVoiceKind.allCases.count)
    }
}
