// TimelineMultiLaneSchedulingTests.swift
// Multi-Roll cycle 2 — the PURE multi-lane fan-out of region scheduling: today
// TimelineScheduling.laneEvent() is called only for the single rollLaneID; the
// playback fan-out (a later, device-gated cycle) needs the per-lane events for ALL
// non-bio MIDI lanes at once. This is that pure list — no audio, no clock, no
// per-lane roll/voice yet. Deterministic → tested on every platform.

import XCTest
import Foundation
@testable import Echoelmusic

final class TimelineMultiLaneSchedulingTests: XCTestCase {

    private func midiLane(_ name: String) -> TimelineLane { TimelineLane(name: name, kind: .midi) }
    private func region(_ laneID: UUID, start: Int, len: Int) -> TimelineRegion {
        TimelineRegion(laneID: laneID, clipID: UUID(), startTick: start, lengthTicks: len)
    }

    func testMidiLaneIDs_excludesBioAndAudio_preservesOrder() {
        let a = midiLane("A"), b = midiLane("B")
        let audio = TimelineLane(name: "Aud", kind: .audio)
        let bio = TimelineLane(name: "Bio", kind: .midi, isBio: true)
        let doc = TimelineDocument(lanes: [a, audio, b, bio], regions: [])
        XCTAssertEqual(doc.midiLaneIDs, [a.id, b.id])   // audio + bio excluded, order kept
    }

    func testLaneEvents_perLane_loadAndUnchanged() {
        let a = midiLane("A"), b = midiLane("B")
        // Lane A: region [0,480). Lane B: region [480,960).
        let rA = region(a.id, start: 0, len: 480)
        let rB = region(b.id, start: 480, len: 480)
        let doc = TimelineDocument(lanes: [a, b], regions: [rA, rB])

        // Step crossing 0: A loads rA, B stays clear (empty→empty = unchanged).
        let atStart = TimelineScheduling.laneEvents(in: doc, fromTick: -1, toTick: 0)
        XCTAssertEqual(atStart, [
            .init(laneID: a.id, event: .load(rA)),
            .init(laneID: b.id, event: .unchanged)
        ])

        // Step crossing 480: A leaves rA into a gap (clear), B loads rB.
        let atMid = TimelineScheduling.laneEvents(in: doc, fromTick: 479, toTick: 480)
        XCTAssertEqual(atMid, [
            .init(laneID: a.id, event: .clear),
            .init(laneID: b.id, event: .load(rB))
        ])
    }

    func testLaneEvents_empty_whenNoMidiLanes() {
        let doc = TimelineDocument(lanes: [TimelineLane(name: "Aud", kind: .audio)], regions: [])
        XCTAssertTrue(TimelineScheduling.laneEvents(in: doc, fromTick: 0, toTick: 120).isEmpty)
    }
}
