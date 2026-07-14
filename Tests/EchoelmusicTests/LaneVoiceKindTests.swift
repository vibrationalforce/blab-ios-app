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
        XCTAssertEqual(TrackInstrument.drums.voiceKind, .drums)
        XCTAssertEqual(TrackInstrument.sampler.voiceKind, .sampler)
        XCTAssertEqual(TrackInstrument.subBass.voiceKind, .subBass)
        XCTAssertEqual(TrackInstrument.bioVoice.voiceKind, .bioVoice)
    }

    func testBreakLoopResolvesToDrums() {
        // Break has no dedicated voice class — it rides the drum kit (documented default).
        XCTAssertEqual(TrackInstrument.breakLoop.voiceKind, .drums)
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
