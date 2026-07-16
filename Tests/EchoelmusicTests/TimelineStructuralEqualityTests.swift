// TimelineStructuralEqualityTests.swift
// CLIP-3 (ultrascan CRITICAL→HIGH): the playing TimelineRegionPlayer must pull
// STRUCTURE edits (region move/trim/split/delete/add, lane add/remove/reorder,
// automation) into the live session — but mixer-only edits (mute/solo/level/pan)
// must keep flowing through the cheap per-step mergeMixer WITHOUT triggering a
// relocate (which flushes voices / re-primes = an audible chase). This pure
// predicate is the gate between the two paths.

import XCTest
@testable import Echoelmusic

final class TimelineStructuralEqualityTests: XCTestCase {

    private func doc() -> TimelineDocument {
        let lane = TimelineLane(name: "Synth", kind: .midi, builtinInstrument: .polySynth)
        let clip = UUID()
        var d = TimelineDocument(lanes: [lane])
        d.regions = [TimelineRegion(laneID: lane.id, clipID: clip,
                                    startTick: 0, lengthTicks: 1920)]
        return d
    }

    func testIdenticalDocuments_areStructurallyEqual() {
        let d = doc()
        XCTAssertTrue(TimelineDocument.structurallyEqual(d, d))
    }

    func testMixerOnlyEdits_areStructurallyEqual() {
        // The exact fields mergeMixer flows per step — none may trigger a relocate.
        let a = doc()
        var b = a
        b.lanes[0].isMuted = true
        b.lanes[0].isSoloed = true
        b.lanes[0].level = 0.3
        b.lanes[0].pan = -0.5
        XCTAssertTrue(TimelineDocument.structurallyEqual(a, b))
    }

    func testRenameAndArm_areNotStructural() {
        // Neither changes what SOUNDS at a tick — no relocate (no voice re-attack).
        let a = doc()
        var b = a
        b.lanes[0].name = "Renamed"
        b.lanes[0].isArmed = true
        XCTAssertTrue(TimelineDocument.structurallyEqual(a, b))
    }

    func testRegionMove_isStructural() {
        let a = doc()
        var b = a
        b.regions[0].startTick += TimelineTime.ticksPerBar   // drag 1 bar later
        XCTAssertFalse(TimelineDocument.structurallyEqual(a, b))
    }

    func testRegionTrimAndDelete_areStructural() {
        let a = doc()
        var trimmed = a
        trimmed.regions[0].lengthTicks -= TimelineTime.ticksPerBar / 2
        XCTAssertFalse(TimelineDocument.structurallyEqual(a, trimmed))
        var deleted = a
        deleted.regions.removeAll()
        XCTAssertFalse(TimelineDocument.structurallyEqual(a, deleted))
    }

    func testLaneAddRemoveReorder_areStructural() {
        let a = doc()
        var added = a
        added.lanes.append(TimelineLane(name: "Lead", kind: .midi,
                                        builtinInstrument: .polySynth))
        XCTAssertFalse(TimelineDocument.structurallyEqual(a, added),
                       "a new lane shifts pump ranks — must relocate")
        var two = added
        two.lanes.reverse()
        XCTAssertFalse(TimelineDocument.structurallyEqual(added, two),
                       "lane ORDER is rank order — reorder must relocate")
    }

    func testAutomationEdit_isStructural() {
        let a = doc()
        var b = a
        b.automation = [AutomationLane(parameter: "seq.tempo",
                                       points: [AutomationPoint(tick: 0, value: 0.5)])]
        XCTAssertFalse(TimelineDocument.structurallyEqual(a, b))
    }

    func testMixedEdit_mixerPlusStructural_isStructural() {
        // A level drag bundled with a region move must still relocate.
        let a = doc()
        var b = a
        b.lanes[0].level = 0.4
        b.regions[0].startTick += 480
        XCTAssertFalse(TimelineDocument.structurallyEqual(a, b))
    }
}
