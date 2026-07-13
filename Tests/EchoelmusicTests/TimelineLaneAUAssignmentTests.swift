// TimelineLaneAUAssignmentTests.swift
// AUv3-structure block U3 — a timeline track carries its plugin assignment:
// an optional instrument (for a MIDI lane) and an ordered FX chain, each a pure
// Codable AUPluginRef whose identity matches the parameter registry's au-prefix
// (so a lane knows which registered params are "its" plugin's). Legacy documents
// decode with no assignment; the assignment is the DATA the founder's "sichtbare
// Instrument/FX-Belegung pro Spur" surfaces. (Engine routing to per-lane voices
// waits for multi-roll; this is the honest persisted model + display foundation.)

import XCTest
import Foundation
@testable import Echoelmusic

final class AUPluginRefTests: XCTestCase {

    private func osType(_ s: String) -> UInt32 {
        var r: UInt32 = 0
        for b in s.utf8.prefix(4) { r = (r << 8) | UInt32(b) }
        return r
    }

    func testIdentity_matchesParameterRegistryPrefix() {
        let ref = AUPluginRef(name: "Bass", manufacturerName: "Echoel",
                              componentType: osType("aumu"), componentSubType: osType("bass"),
                              componentManufacturer: osType("Echl"), isInstrument: true)
        // The plugin identity is the param keyPath prefix: a lane's instrument and
        // its params (au.Echl.bass.<addr>) share one plugin id.
        XCTAssertEqual(ref.id, "au.Echl.bass")
        XCTAssertEqual(ref.id, AUParameterMapping.pluginPrefix(
            manufacturer: osType("Echl"), subType: osType("bass")))
    }

    func testCodable_roundTrip() throws {
        let ref = AUPluginRef(name: "Reverb X", manufacturerName: "Acme",
                              componentType: osType("aufx"), componentSubType: osType("rvb1"),
                              componentManufacturer: osType("Acme"), isInstrument: false)
        let back = try JSONDecoder().decode(AUPluginRef.self,
                                            from: JSONEncoder().encode(ref))
        XCTAssertEqual(back, ref)
    }
}

final class TimelineLaneAUAssignmentTests: XCTestCase {

    private func osType(_ s: String) -> UInt32 {
        var r: UInt32 = 0
        for b in s.utf8.prefix(4) { r = (r << 8) | UInt32(b) }
        return r
    }

    private func ref(_ name: String, instrument: Bool) -> AUPluginRef {
        AUPluginRef(name: name, manufacturerName: "Echoel",
                    componentType: osType(instrument ? "aumu" : "aufx"),
                    componentSubType: osType("sub1"), componentManufacturer: osType("Echl"),
                    isInstrument: instrument)
    }

    func testDefaultLane_hasNoAssignment() {
        let lane = TimelineLane(name: "Lead", kind: .midi)
        XCTAssertNil(lane.instrument)
        XCTAssertTrue(lane.effects.isEmpty)
    }

    func testLegacyLaneJSON_decodesWithNoAssignment() throws {
        // A lane saved before the assignment fields (no instrument/effects keys),
        // including pre-mixer docs (no level/pan) — must load lossless.
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Old","kind":"midi"}
        """.data(using: .utf8) ?? Data()
        let lane = try JSONDecoder().decode(TimelineLane.self, from: legacy)
        XCTAssertNil(lane.instrument)
        XCTAssertTrue(lane.effects.isEmpty)
        XCTAssertEqual(lane.level, 1, accuracy: 1e-6)   // pre-existing mixer defaults still hold
    }

    func testAssignment_roundTripsThroughJSON() throws {
        var lane = TimelineLane(name: "Synth", kind: .midi)
        lane.instrument = ref("Echoel Synth", instrument: true)
        lane.effects = [ref("Reverb", instrument: false), ref("Delay", instrument: false)]
        let back = try JSONDecoder().decode(TimelineLane.self,
                                            from: JSONEncoder().encode(lane))
        XCTAssertEqual(back.instrument, lane.instrument)
        XCTAssertEqual(back.effects, lane.effects)
        // Mixer + identity survive alongside the new fields.
        XCTAssertEqual(back.id, lane.id)
        XCTAssertEqual(back.level, lane.level, accuracy: 1e-6)
    }

    func testInstrumentInitParam() {
        let inst = ref("Piano", instrument: true)
        let lane = TimelineLane(name: "Keys", kind: .midi, instrument: inst)
        XCTAssertEqual(lane.instrument, inst)
    }
}
