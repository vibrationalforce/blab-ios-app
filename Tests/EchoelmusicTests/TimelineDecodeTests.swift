// TimelineDecodeTests.swift
// Echoel — data-loss guard for the timeline document (Ultraarchitecture REIHENFOLGE
// Tier A1, part 2). TimelineLane (id/name/kind) and TimelineRegion (id/laneID/clipID/
// startTick/lengthTicks) previously used bare `try c.decode` for their IDENTITY fields.
// A single renamed/removed identity field threw → the [TimelineLane]/[TimelineRegion]
// array decode threw → TimelineDocument.init rethrew → AppGroupStore.load returned nil →
// the user's WHOLE song was lost. These tests lock the defensive-decode law on those
// fields and prove the document survives a degraded element.

import XCTest
@testable import Echoelmusic

final class TimelineDecodeTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: TimelineLane — identity fields degrade, never throw

    func testLane_missingName_defaultsEmpty_doesNotThrow() throws {
        let lane = try decode(TimelineLane.self,
            #"{"id":"00000000-0000-0000-0000-000000000001","kind":"midi"}"#)
        XCTAssertEqual(lane.name, "")
        XCTAssertEqual(lane.kind, .midi)
    }

    func testLane_missingKind_defaultsMidi_doesNotThrow() throws {
        let lane = try decode(TimelineLane.self,
            #"{"id":"00000000-0000-0000-0000-000000000002","name":"Drums"}"#)
        XCTAssertEqual(lane.kind, .midi)
        XCTAssertEqual(lane.name, "Drums")
    }

    func testLane_missingId_getsFreshUUID_doesNotThrow() throws {
        let lane = try decode(TimelineLane.self, #"{"name":"Bass","kind":"audio"}"#)
        XCTAssertEqual(lane.name, "Bass")
        XCTAssertEqual(lane.kind, .audio)
    }

    // MARK: TimelineRegion — identity fields degrade, never throw

    func testRegion_missingStartTick_defaultsZero_doesNotThrow() throws {
        let r = try decode(TimelineRegion.self, #"""
        {"id":"00000000-0000-0000-0000-0000000000a1",
         "laneID":"00000000-0000-0000-0000-0000000000b1",
         "clipID":"00000000-0000-0000-0000-0000000000c1","lengthTicks":480}
        """#)
        XCTAssertEqual(r.startTick, 0)
        XCTAssertEqual(r.lengthTicks, 480)
    }

    func testRegion_missingLengthTicks_defaultsOne_doesNotThrow() throws {
        let r = try decode(TimelineRegion.self, #"""
        {"id":"00000000-0000-0000-0000-0000000000a2",
         "laneID":"00000000-0000-0000-0000-0000000000b2",
         "clipID":"00000000-0000-0000-0000-0000000000c2","startTick":240}
        """#)
        XCTAssertEqual(r.lengthTicks, 1, "min-clamped to a non-zero length")
        XCTAssertEqual(r.startTick, 240)
    }

    func testRegion_missingLaneID_survives_doesNotThrow() throws {
        // laneID renamed away → a fresh (orphan) UUID, but the region — and thus the
        // whole document — survives instead of throwing.
        let r = try decode(TimelineRegion.self, #"""
        {"id":"00000000-0000-0000-0000-0000000000a3",
         "clipID":"00000000-0000-0000-0000-0000000000c3","startTick":0,"lengthTicks":96}
        """#)
        XCTAssertEqual(r.lengthTicks, 96)
    }

    // MARK: Document survives a degraded element (the blast-radius proof)

    func testDocument_laneMissingName_documentSurvives() throws {
        let doc = try decode(TimelineDocument.self, #"""
        {"lanes":[{"id":"00000000-0000-0000-0000-000000000010","kind":"audio"}],
         "regions":[],"automation":[]}
        """#)
        XCTAssertEqual(doc.lanes.count, 1, "degraded lane kept, document not vaporized")
        XCTAssertEqual(doc.lanes.first?.name, "")
        XCTAssertEqual(doc.lanes.first?.kind, .audio)
    }

    func testDocument_regionMissingStartTick_documentSurvives() throws {
        let doc = try decode(TimelineDocument.self, #"""
        {"lanes":[],
         "regions":[{"id":"00000000-0000-0000-0000-000000000020",
                     "laneID":"00000000-0000-0000-0000-000000000021",
                     "clipID":"00000000-0000-0000-0000-000000000022","lengthTicks":240}],
         "automation":[]}
        """#)
        XCTAssertEqual(doc.regions.count, 1, "degraded region kept, document not vaporized")
        XCTAssertEqual(doc.regions.first?.startTick, 0)
    }

    // MARK: Well-formed round-trip stays lossless (no regression)

    func testLane_roundTrip_isLossless() throws {
        let lane = TimelineLane(name: "Lead", kind: .midi, level: 0.8, pan: -0.3,
                                transposeSemitones: 7, octaveDouble: 1)
        let round = try JSONDecoder().decode(TimelineLane.self,
                                             from: try JSONEncoder().encode(lane))
        XCTAssertEqual(round, lane)
    }

    func testRegion_roundTrip_isLossless() throws {
        let r = TimelineRegion(laneID: UUID(), clipID: UUID(), startTick: 480,
                               lengthTicks: 960, contentOffsetSeconds: 1.5,
                               gain: 0.7, warpEnabled: true, stretchMode: .clean)
        let round = try JSONDecoder().decode(TimelineRegion.self,
                                             from: try JSONEncoder().encode(r))
        XCTAssertEqual(round, r)
    }

    // MARK: Document array element-isolation (A1.3) — a non-decodable element is dropped

    func testDocument_corruptLaneElement_isDropped_restSurvive() throws {
        // Middle element is a non-object (a string) — even the field-level defensive
        // decoder can't absorb it, so it must be DROPPED, not vaporize the document.
        let doc = try decode(TimelineDocument.self, #"""
        {"lanes":[
            {"id":"00000000-0000-0000-0000-000000000030","name":"A","kind":"midi"},
            "not-a-lane",
            {"id":"00000000-0000-0000-0000-000000000031","name":"B","kind":"audio"}
         ],"regions":[],"automation":[]}
        """#)
        XCTAssertEqual(doc.lanes.count, 2, "corrupt lane dropped, valid ones kept")
        XCTAssertEqual(doc.lanes.map { $0.name }, ["A", "B"], "order preserved")
    }

    func testDocument_corruptRegionElement_isDropped_restSurvive() throws {
        let doc = try decode(TimelineDocument.self, #"""
        {"lanes":[],"regions":[
            {"id":"00000000-0000-0000-0000-000000000040","laneID":"00000000-0000-0000-0000-000000000041","clipID":"00000000-0000-0000-0000-000000000042","startTick":0,"lengthTicks":96},
            42
         ],"automation":[]}
        """#)
        XCTAssertEqual(doc.regions.count, 1, "corrupt region element dropped")
        XCTAssertEqual(doc.regions.first?.lengthTicks, 96)
    }

    func testDocument_corruptAutomationElement_isDropped_restSurvive() throws {
        let doc = try decode(TimelineDocument.self, #"""
        {"lanes":[],"regions":[],"automation":[
            {"id":"00000000-0000-0000-0000-000000000050","parameter":"filter.cutoff","points":[]},
            "garbage"
         ]}
        """#)
        XCTAssertEqual(doc.automation.count, 1, "corrupt automation lane dropped")
        XCTAssertEqual(doc.automation.first?.parameter, "filter.cutoff")
    }

    func testDocument_allValid_roundTripPreservesOrderAndContent() throws {
        var a = AutomationLane(parameter: "mix.level")
        a.addPoint(tick: 0, value: 0.3)
        let doc = TimelineDocument(
            lanes: [TimelineLane(name: "One", kind: .midi),
                    TimelineLane(name: "Two", kind: .audio)],
            regions: [TimelineRegion(laneID: UUID(), clipID: UUID(),
                                     startTick: 0, lengthTicks: 480)],
            automation: [a])
        let round = try JSONDecoder().decode(TimelineDocument.self,
                                             from: try JSONEncoder().encode(doc))
        XCTAssertEqual(round, doc, "well-formed document round-trips losslessly, order kept")
    }
}
