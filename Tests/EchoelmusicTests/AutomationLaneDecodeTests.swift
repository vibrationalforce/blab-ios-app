// AutomationLaneDecodeTests.swift
// Echoel — data-loss guard for the automation persistence path (Ultraarchitecture
// REIHENFOLGE Tier A1). A single renamed/removed field on AutomationPoint or
// AutomationLane must degrade ONE field (or drop ONE keyframe), never throw — because
// AutomationLane decodes inside TimelineDocument, whose element error rethrows and
// makes AppGroupStore.load return nil, vaporizing the whole timeline document (the
// user's entire song). These tests lock the defensive-decode law on that path.

import XCTest
@testable import Echoelmusic

final class AutomationLaneDecodeTests: XCTestCase {

    private func decodePoint(_ json: String) throws -> AutomationPoint {
        try JSONDecoder().decode(AutomationPoint.self, from: Data(json.utf8))
    }
    private func decodeLane(_ json: String) throws -> AutomationLane {
        try JSONDecoder().decode(AutomationLane.self, from: Data(json.utf8))
    }

    // MARK: AutomationPoint — a missing/renamed field degrades, never throws

    func testPoint_missingValueField_defaultsToZero_doesNotThrow() throws {
        // `value` renamed away (old field gone). Must decode, not throw.
        let p = try decodePoint(#"{"id":"00000000-0000-0000-0000-000000000001","tick":480,"curve":"linear"}"#)
        XCTAssertEqual(p.value, 0)
        XCTAssertEqual(p.tick, 480)
    }

    func testPoint_missingId_getsFreshUUID_doesNotThrow() throws {
        let p = try decodePoint(#"{"tick":240,"value":0.5,"curve":"hold"}"#)
        // A fresh UUID is assigned (non-crash); the value survives.
        XCTAssertEqual(p.value, 0.5)
        XCTAssertEqual(p.curve, .hold)
    }

    func testPoint_missingCurve_defaultsToLinear() throws {
        let p = try decodePoint(#"{"id":"00000000-0000-0000-0000-000000000002","tick":0,"value":0.25}"#)
        XCTAssertEqual(p.curve, .linear)
        XCTAssertEqual(p.value, 0.25)
    }

    // MARK: AutomationLane — identity fields defended + element isolation

    func testLane_missingParameter_survives_doesNotThrow() throws {
        let lane = try decodeLane(#"{"id":"00000000-0000-0000-0000-000000000010","points":[]}"#)
        XCTAssertEqual(lane.parameter, "")
        XCTAssertTrue(lane.isEmpty)
    }

    func testLane_missingPointsKey_becomesEmpty() throws {
        let lane = try decodeLane(#"{"id":"00000000-0000-0000-0000-000000000011","parameter":"filter.cutoff"}"#)
        XCTAssertEqual(lane.parameter, "filter.cutoff")
        XCTAssertTrue(lane.isEmpty)
    }

    func testLane_oneCorruptKeyframe_isDropped_restSurvive() throws {
        // The middle element is garbage (a string, not a point object). It must be
        // dropped, the two valid keyframes kept — NOT the whole lane thrown away.
        let json = #"""
        {"id":"00000000-0000-0000-0000-000000000012","parameter":"mix.level",
         "points":[
            {"id":"00000000-0000-0000-0000-0000000000a1","tick":0,"value":0.1,"curve":"linear","curvature":0},
            "totally-not-a-keyframe",
            {"id":"00000000-0000-0000-0000-0000000000a2","tick":960,"value":0.9,"curve":"linear","curvature":0}
         ]}
        """#
        let lane = try decodeLane(json)
        XCTAssertEqual(lane.points.count, 2, "corrupt keyframe dropped, valid ones kept")
        XCTAssertEqual(lane.points.first?.value, 0.1)
        XCTAssertEqual(lane.points.last?.value, 0.9)
    }

    func testLane_pointsDecodeSortedAscending() throws {
        let json = #"""
        {"id":"00000000-0000-0000-0000-000000000013","parameter":"p",
         "points":[
            {"id":"00000000-0000-0000-0000-0000000000b2","tick":960,"value":0.9,"curve":"linear","curvature":0},
            {"id":"00000000-0000-0000-0000-0000000000b1","tick":0,"value":0.1,"curve":"linear","curvature":0}
         ]}
        """#
        let lane = try decodeLane(json)
        XCTAssertEqual(lane.points.map { $0.tick }, [0, 960], "kept sorted after decode")
    }

    // MARK: Round-trip stays lossless for well-formed data (no regression)

    func testLane_roundTrip_isLossless() throws {
        var lane = AutomationLane(parameter: "filter.cutoff")
        lane.addPoint(tick: 0, value: 0.2, curve: .linear, curvature: 0.5)
        lane.addPoint(tick: 480, value: 0.8, curve: .hold, curvature: 0)
        let data = try JSONEncoder().encode(lane)
        let round = try JSONDecoder().decode(AutomationLane.self, from: data)
        XCTAssertEqual(round, lane, "well-formed encode→decode is bit-identical")
    }
}
