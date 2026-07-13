// TrackInstrumentTests.swift
// Echoel — built-in track instruments (EchoelDrums/Break/Sampler/Synth/Bass/Bio)
// and each track's derived record source. Pure value model → runs on every
// platform (no engine, no audio, no SwiftUI).

import XCTest
@testable import Echoelmusic

final class TrackInstrumentTests: XCTestCase {

    // MARK: - Instrument identity

    func testAllInstrumentsHaveDistinctBrandNames() {
        let names = TrackInstrument.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, TrackInstrument.allCases.count, "names must be unique")
        XCTAssertTrue(names.contains("EchoelDrums"))
        XCTAssertTrue(names.contains("EchoelBreak"))
        XCTAssertTrue(names.contains("EchoelSampler"))
    }

    func testEveryBuiltinInstrumentIsAMidiVoice() {
        for inst in TrackInstrument.allCases {
            XCTAssertEqual(inst.clipKind, .midi, "\(inst) should carry a MIDI lane")
        }
    }

    func testInstrumentRecordSource_bioVsMidi() {
        XCTAssertEqual(TrackInstrument.bioVoice.recordSource, .bio)
        XCTAssertEqual(TrackInstrument.drums.recordSource, .midiInput)
        XCTAssertEqual(TrackInstrument.polySynth.recordSource, .midiInput)
    }

    func testRawValuesAreStableForPersistence() {
        // Raw values persist with the document — guard against silent renames.
        XCTAssertEqual(TrackInstrument.drums.rawValue, "drums")
        XCTAssertEqual(TrackInstrument.breakLoop.rawValue, "breakLoop")
        XCTAssertEqual(TrackInstrument.sampler.rawValue, "sampler")
        XCTAssertEqual(TrackInstrument.polySynth.rawValue, "polySynth")
        XCTAssertEqual(TrackInstrument.subBass.rawValue, "subBass")
        XCTAssertEqual(TrackInstrument.bioVoice.rawValue, "bioVoice")
    }

    // MARK: - RecordSource

    func testRecordSource_canRecordExceptNone() {
        for s in RecordSource.allCases where s != .none {
            XCTAssertTrue(s.canRecord, "\(s) should be armable")
        }
        XCTAssertFalse(RecordSource.none.canRecord)
    }

    // MARK: - Lane-derived record source (founder's per-track routing)

    func testLaneRecordSource_byKind() {
        XCTAssertEqual(TimelineLane(name: "MIDI 1", kind: .midi).recordSource, .midiInput)
        XCTAssertEqual(TimelineLane(name: "Audio 1", kind: .audio).recordSource, .audioInput)
        XCTAssertEqual(TimelineLane(name: "Video 1", kind: .video).recordSource, .videoCapture)
        XCTAssertEqual(TimelineLane(name: "Visual", kind: .visual).recordSource, .none)
    }

    func testLaneRecordSource_bioLaneAlwaysBio() {
        let bio = TimelineLane(name: "Bio", kind: .midi, isBio: true)
        XCTAssertEqual(bio.recordSource, .bio)
    }

    func testLaneRecordSource_instrumentOverridesKind() {
        let drums = TimelineLane(name: "EchoelDrums", kind: .midi, builtinInstrument: .drums)
        XCTAssertEqual(drums.recordSource, .midiInput)
        let bioInst = TimelineLane(name: "Bio Instrument", kind: .midi, builtinInstrument: .bioVoice)
        XCTAssertEqual(bioInst.recordSource, .bio)
    }

    // MARK: - Backward-compatible decode (pre-instrument docs)

    func testLegacyLaneDecodes_withoutInstrumentOrArmKeys() throws {
        let legacy = #"{"id":"\#(UUID().uuidString)","name":"Old","kind":"midi"}"#
        let lane = try JSONDecoder().decode(TimelineLane.self, from: Data(legacy.utf8))
        XCTAssertNil(lane.builtinInstrument)
        XCTAssertFalse(lane.isArmed)
        XCTAssertEqual(lane.recordSource, .midiInput)
    }

    func testLaneRoundTrips_withInstrumentAndArm() throws {
        let lane = TimelineLane(name: "EchoelSampler", kind: .midi,
                                builtinInstrument: .sampler, isArmed: true)
        let data = try JSONEncoder().encode(lane)
        let back = try JSONDecoder().decode(TimelineLane.self, from: data)
        XCTAssertEqual(back.builtinInstrument, .sampler)
        XCTAssertTrue(back.isArmed)
    }
}
