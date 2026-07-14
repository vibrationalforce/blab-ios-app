// MultiRollFanoutTests.swift
// Pure, Linux-CI coverage for the three Multi-Roll fan-out bug-fixes:
//   1. activeLoads — a secondary lane whose clip is active at the downbeat loads
//      (fixes the "clip at bar 1 stays silent" trap).
//   2. patch(forSlot:) — each slot resolves ITS lane's patch (per-lane timbre).
//   3. audible — mute / foreign-solo / 0-level silences a SECONDARY lane too.

import XCTest
@testable import Echoelmusic

final class MultiRollFanoutTests: XCTestCase {

    // Bio + roll(primary) + two secondary MIDI lanes. Returns (doc, laneIDs, clipIDs).
    private func makeDoc(
        secondaryPatches: [SynthPatch?] = [nil, nil],
        regionsAtZero: [Bool] = [true, true],
        mute: [Bool] = [false, false],
        solo: [Bool] = [false, false],
        level: [Float] = [1, 1]
    ) -> (TimelineDocument, roll: UUID, sec: [UUID], clips: [UUID]) {
        let bio = TimelineLane(name: "Bio", kind: .midi, isBio: true)
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let s1 = TimelineLane(name: "MIDI 2", kind: .midi, isMuted: mute[0], isSoloed: solo[0],
                              patch: secondaryPatches[0]); var s1v = s1; s1v.level = level[0]
        let s2 = TimelineLane(name: "MIDI 3", kind: .midi, isMuted: mute[1], isSoloed: solo[1],
                              patch: secondaryPatches[1]); var s2v = s2; s2v.level = level[1]
        let c1 = UUID(), c2 = UUID()
        var regions: [TimelineRegion] = []
        // roll region at 0 so the doc has regions; not part of the secondary set.
        regions.append(TimelineRegion(laneID: roll.id, clipID: UUID(), startTick: 0, lengthTicks: 1920))
        if regionsAtZero[0] { regions.append(TimelineRegion(laneID: s1v.id, clipID: c1, startTick: 0, lengthTicks: 1920)) }
        else { regions.append(TimelineRegion(laneID: s1v.id, clipID: c1, startTick: 1920, lengthTicks: 1920)) }
        if regionsAtZero[1] { regions.append(TimelineRegion(laneID: s2v.id, clipID: c2, startTick: 0, lengthTicks: 1920)) }
        else { regions.append(TimelineRegion(laneID: s2v.id, clipID: c2, startTick: 1920, lengthTicks: 1920)) }
        let doc = TimelineDocument(lanes: [bio, roll, s1v, s2v], regions: regions)
        return (doc, roll.id, [s1v.id, s2v.id], [c1, c2])
    }

    // MARK: - Bug 1: prime the secondaries active at the downbeat

    func testActiveLoads_secondaryRegionAtTickZero_loadsItsSlot() {
        let (doc, roll, sec, clips) = makeDoc()
        let loads = MultiRollFanout.activeLoads(in: doc, at: 0, rollLane: roll, capacity: 4)
        // Both secondaries have a region at 0 → both load, at rank 0 and rank 1 (roll excluded).
        XCTAssertEqual(loads.count, 2)
        XCTAssertEqual(loads[0].slot, 0)
        XCTAssertEqual(loads[0].laneID, sec[0])
        XCTAssertEqual(loads[0].clipID, clips[0])
        XCTAssertEqual(loads[1].slot, 1)
        XCTAssertEqual(loads[1].laneID, sec[1])
    }

    func testActiveLoads_secondaryRegionNotAtZero_isNotPrimed() {
        let (doc, roll, _, _) = makeDoc(regionsAtZero: [false, true])
        let loads = MultiRollFanout.activeLoads(in: doc, at: 0, rollLane: roll, capacity: 4)
        // Only the second secondary is active at 0; the first starts at bar 2.
        XCTAssertEqual(loads.count, 1)
        XCTAssertEqual(loads[0].slot, 1)   // rank is stable (position among secondaries), not compacted
    }

    func testActiveLoads_overflowBeyondCapacity_isDropped() {
        let (doc, roll, _, _) = makeDoc()
        let loads = MultiRollFanout.activeLoads(in: doc, at: 0, rollLane: roll, capacity: 1)
        // Capacity 1 → only rank 0 has a physical voice; rank 1 overflows (silenced).
        XCTAssertEqual(loads.count, 1)
        XCTAssertEqual(loads[0].slot, 0)
    }

    func testActiveLoads_zeroCapacity_isEmpty() {
        let (doc, roll, _, _) = makeDoc()
        XCTAssertTrue(MultiRollFanout.activeLoads(in: doc, at: 0, rollLane: roll, capacity: 0).isEmpty)
    }

    // MARK: - Bug 3: per-lane patch resolution

    func testPatchForSlot_resolvesEachLanesOwnPatch() throws {
        let p0 = try XCTUnwrap(SynthPatch.factory.first)
        let p1 = try XCTUnwrap(SynthPatch.factory.last)
        let (doc, roll, _, _) = makeDoc(secondaryPatches: [p0, p1])
        XCTAssertEqual(MultiRollFanout.patch(forSlot: 0, in: doc, rollLane: roll), p0)
        XCTAssertEqual(MultiRollFanout.patch(forSlot: 1, in: doc, rollLane: roll), p1)
    }

    func testPatchForSlot_nilLanePatch_returnsNil_forAppFallback() {
        let (doc, roll, _, _) = makeDoc(secondaryPatches: [nil, nil])
        XCTAssertNil(MultiRollFanout.patch(forSlot: 0, in: doc, rollLane: roll))
    }

    func testPatchForSlot_outOfRange_returnsNil() {
        let (doc, roll, _, _) = makeDoc()
        XCTAssertNil(MultiRollFanout.patch(forSlot: 9, in: doc, rollLane: roll))
    }

    func testActiveLoads_carriesLanePatch() throws {
        let p0 = try XCTUnwrap(SynthPatch.factory.first)
        let (doc, roll, _, _) = makeDoc(secondaryPatches: [p0, nil])
        let loads = MultiRollFanout.activeLoads(in: doc, at: 0, rollLane: roll, capacity: 4)
        XCTAssertEqual(loads[0].patch, p0)
        XCTAssertNil(loads[1].patch)
    }

    // MARK: - Bug 2: per-lane mute / solo / level gate on secondaries

    func testAudible_defaultLane_isAudible() {
        let (doc, _, sec, _) = makeDoc()
        XCTAssertTrue(MultiRollFanout.audible(doc, laneID: sec[0]))
    }

    func testAudible_mutedSecondary_isSilent() {
        let (doc, _, sec, _) = makeDoc(mute: [true, false])
        XCTAssertFalse(MultiRollFanout.audible(doc, laneID: sec[0]))
        XCTAssertTrue(MultiRollFanout.audible(doc, laneID: sec[1]))
    }

    func testAudible_foreignSolo_silencesUnsoloedSecondary() {
        let (doc, _, sec, _) = makeDoc(solo: [false, true])
        XCTAssertFalse(MultiRollFanout.audible(doc, laneID: sec[0]))   // another lane soloed
        XCTAssertTrue(MultiRollFanout.audible(doc, laneID: sec[1]))    // the soloed one plays
    }

    func testAudible_zeroLevelSecondary_isSilent() {
        let (doc, _, sec, _) = makeDoc(level: [0, 1])
        XCTAssertFalse(MultiRollFanout.audible(doc, laneID: sec[0]))
    }

    // MARK: - Slot → lane mapping stability

    func testLaneIDForSlot_mapsRankToSecondaryLaneExcludingRoll() {
        let (doc, roll, sec, _) = makeDoc()
        XCTAssertEqual(MultiRollFanout.laneID(forSlot: 0, in: doc, rollLane: roll), sec[0])
        XCTAssertEqual(MultiRollFanout.laneID(forSlot: 1, in: doc, rollLane: roll), sec[1])
        XCTAssertNil(MultiRollFanout.laneID(forSlot: 2, in: doc, rollLane: roll))
    }

    /// REGRESSION GUARD: the fan-out fires a slot's notes from `LaneVoiceRackPlan`
    /// (ranked by index in `LaneVoiceScheduling.plan(...).filter{ != roll }`) but
    /// resolves that slot's PATCH and MUTE from `MultiRollFanout.laneID(forSlot:)`.
    /// Those two orderings MUST be identical or a slot sounds with another lane's
    /// timbre / gets the wrong lane's mute. This binds them so a future reorder of
    /// `midiLaneIDs`, the filter site, or a `plan` drop-inactive optimization fails
    /// loudly instead of desyncing silently.
    func testSlotMapping_matchesLaneVoiceSchedulingPlanRankOrder() {
        let bio = TimelineLane(name: "Bio", kind: .midi, isBio: true)
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let a = TimelineLane(name: "MIDI 2", kind: .midi)
        let b = TimelineLane(name: "MIDI 3", kind: .midi)
        let c = TimelineLane(name: "MIDI 4", kind: .midi)
        let doc = TimelineDocument(lanes: [bio, roll, a, b, c], regions: [
            TimelineRegion(laneID: roll.id, clipID: UUID(), startTick: 0, lengthTicks: 1920),
            TimelineRegion(laneID: a.id, clipID: UUID(), startTick: 0, lengthTicks: 1920),
            TimelineRegion(laneID: b.id, clipID: UUID(), startTick: 0, lengthTicks: 1920),
            TimelineRegion(laneID: c.id, clipID: UUID(), startTick: 0, lengthTicks: 1920),
        ])
        var pool = LaneVoicePool(capacity: 4)
        let steps = LaneVoiceScheduling.plan(in: doc, fromTick: 0, toTick: 480, pool: &pool)
            .filter { $0.laneID != roll.id }
        XCTAssertEqual(steps.count, 3)   // three secondaries (roll excluded, bio not MIDI-playable)
        for (rank, step) in steps.enumerated() {
            XCTAssertEqual(MultiRollFanout.laneID(forSlot: rank, in: doc, rollLane: roll.id),
                           step.laneID,
                           "slot/rank \(rank): fan-out fires laneID \(step.laneID) but patch/mute resolves a different lane")
        }
    }
}
