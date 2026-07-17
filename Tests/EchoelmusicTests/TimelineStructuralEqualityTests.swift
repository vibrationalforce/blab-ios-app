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

    func testTransposeDetuneEdits_areNotStructural() {
        // CLIP-3 review HIGH: transpose/detune are sink-applied voice fields (like
        // pan) that flow live through refreshMixer — a scrub during playback must
        // NEVER trigger a relocate storm (voice flush + audio-lane restart at ~8 Hz).
        let a = doc()
        var b = a
        b.lanes[0].transposeSemitones = -12
        b.lanes[0].detuneCents = 25
        XCTAssertTrue(TimelineDocument.structurallyEqual(a, b))
    }

    func testOctaveEdit_isNotStructural() {
        // The Oktaver direction is the third sink-applied pitch field (transpose/
        // detune twin) — it flows live through mergeMixer, never a relocate.
        let a = doc()
        var b = a
        b.lanes[0].octaveDouble = 1
        XCTAssertTrue(TimelineDocument.structurallyEqual(a, b))
    }

    func testSamplePathEdit_isStructural() {
        // The sampler lane's sample ref is CONTENT identity (like patch/
        // instrument): a different file sounds different at the same tick, so a
        // change must relocate — the prime path is what pushes the new sample
        // into the rack (slotSampleSink), mergeMixer never carries it.
        let a = doc()
        var b = a
        b.lanes[0].samplePath = "drum:Kick"
        XCTAssertFalse(TimelineDocument.structurallyEqual(a, b))
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
