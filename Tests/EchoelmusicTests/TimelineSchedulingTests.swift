// TimelineSchedulingTests.swift
// Echoel — pure region-playback logic (reorg P2). No audio: verifies which region
// is active at a tick and WHEN the playhead crosses into a new one (the onset that
// (re)loads a lane's clip). These lock the contract the P3 audio wiring rides on.

import XCTest
@testable import Echoelmusic

final class TimelineSchedulingTests: XCTestCase {

    typealias S = TimelineScheduling

    // Two fixed lane IDs so regions can target them deterministically.
    private let laneA = UUID()
    private let laneB = UUID()

    private func region(_ lane: UUID, start: Int, length: Int) -> TimelineRegion {
        TimelineRegion(laneID: lane, clipID: UUID(), startTick: start, lengthTicks: length)
    }

    private func doc(lanes: [TimelineLane], _ regions: [TimelineRegion]) -> TimelineDocument {
        TimelineDocument(lanes: lanes, regions: regions)
    }

    private func midiLane(_ id: UUID, bio: Bool = false) -> TimelineLane {
        TimelineLane(id: id, name: "MIDI", kind: .midi, isBio: bio)
    }
    private func audioLane(_ id: UUID) -> TimelineLane {
        TimelineLane(id: id, name: "Audio", kind: .audio)
    }

    // MARK: - activeRegion

    func testActiveRegion_insideSpan() {
        let r = region(laneA, start: 0, length: 1920)
        let d = doc(lanes: [midiLane(laneA)], [r])
        XCTAssertEqual(S.activeRegion(in: d, laneID: laneA, at: 960)?.id, r.id)
    }

    func testActiveRegion_startInclusive_endExclusive() {
        let r = region(laneA, start: 100, length: 200)   // [100, 300)
        let d = doc(lanes: [midiLane(laneA)], [r])
        XCTAssertEqual(S.activeRegion(in: d, laneID: laneA, at: 100)?.id, r.id, "start is inclusive")
        XCTAssertNil(S.activeRegion(in: d, laneID: laneA, at: 300), "end is exclusive")
        XCTAssertEqual(S.activeRegion(in: d, laneID: laneA, at: 299)?.id, r.id)
        XCTAssertNil(S.activeRegion(in: d, laneID: laneA, at: 99))
    }

    func testActiveRegion_gapReturnsNil() {
        let d = doc(lanes: [midiLane(laneA)],
                    [region(laneA, start: 0, length: 100), region(laneA, start: 500, length: 100)])
        XCTAssertNil(S.activeRegion(in: d, laneID: laneA, at: 300))
    }

    func testActiveRegion_ignoresOtherLanes() {
        let rB = region(laneB, start: 0, length: 1920)
        let d = doc(lanes: [midiLane(laneA), audioLane(laneB)], [rB])
        XCTAssertNil(S.activeRegion(in: d, laneID: laneA, at: 500), "lane A has no region here")
        XCTAssertEqual(S.activeRegion(in: d, laneID: laneB, at: 500)?.id, rB.id)
    }

    func testActiveRegion_overlap_latestStartWins() {
        let under = region(laneA, start: 0, length: 2000)      // [0, 2000)
        let over  = region(laneA, start: 500, length: 1000)    // [500, 1500) placed on top
        let d = doc(lanes: [midiLane(laneA)], [under, over])
        XCTAssertEqual(S.activeRegion(in: d, laneID: laneA, at: 800)?.id, over.id, "top-most wins in overlap")
        XCTAssertEqual(S.activeRegion(in: d, laneID: laneA, at: 1800)?.id, under.id, "outside the overlap → the underlying region")
    }

    /// Overlap where the two regions share the SAME startTick — a clip dropped on
    /// top of another at the same bar boundary (common with grid snap). The
    /// contract (activeRegion doc) is "the most-recently placed / top-most wins".
    /// Regions are appended in placement order (newest LAST), so the tie must break
    /// toward the later array element — NOT `max(by: startTick)`, which keeps the
    /// FIRST (oldest) maximal element and would play the stale clip.
    func testActiveRegion_sameStartTick_mostRecentlyPlacedWins() {
        let older = region(laneA, start: 1920, length: 1920)   // [1920, 3840) placed first
        let newer = region(laneA, start: 1920, length: 960)    // [1920, 2880) dropped on top
        let d = doc(lanes: [midiLane(laneA)], [older, newer])
        XCTAssertEqual(S.activeRegion(in: d, laneID: laneA, at: 2000)?.id, newer.id,
                       "on a startTick tie the most-recently-placed region wins")
        // A tick only the older region covers still resolves to the older one.
        XCTAssertEqual(S.activeRegion(in: d, laneID: laneA, at: 3000)?.id, older.id)
    }

    /// The tie-break is purely about ARRAY POSITION (= placement order): among
    /// equal-start containing regions, the LATER array element wins, regardless of
    /// span length. Names are placement-ordered to avoid implying length matters.
    func testActiveRegion_sameStartTick_laterArrayElementWinsTie() {
        let placedFirst  = region(laneA, start: 480, length: 480)   // earlier in array
        let placedSecond = region(laneA, start: 480, length: 960)   // later → wins the tie
        let d = doc(lanes: [midiLane(laneA)], [placedFirst, placedSecond])
        XCTAssertEqual(S.activeRegion(in: d, laneID: laneA, at: 600)?.id, placedSecond.id,
                       "later array element wins the equal-start tie")
    }

    /// Three-way equal-start tie: the LAST-placed of three overlapping same-start
    /// regions wins (proves the comparator generalizes past a 2-way tie).
    func testActiveRegion_sameStartTick_threeWayTie_lastPlacedWins() {
        let a = region(laneA, start: 960, length: 480)
        let b = region(laneA, start: 960, length: 720)
        let c = region(laneA, start: 960, length: 1200)   // placed last → wins
        let d = doc(lanes: [midiLane(laneA)], [a, b, c])
        XCTAssertEqual(S.activeRegion(in: d, laneID: laneA, at: 1000)?.id, c.id,
                       "the last-placed of three equal-start regions wins")
    }

    // MARK: - laneEvent (onset detection)

    func testLaneEvent_unchanged_withinSameRegion() {
        let r = region(laneA, start: 0, length: 1920)
        let d = doc(lanes: [midiLane(laneA)], [r])
        XCTAssertEqual(S.laneEvent(in: d, laneID: laneA, fromTick: 120, toTick: 240), .unchanged)
    }

    func testLaneEvent_unchanged_gapToGap() {
        let d = doc(lanes: [midiLane(laneA)], [region(laneA, start: 2000, length: 100)])
        XCTAssertEqual(S.laneEvent(in: d, laneID: laneA, fromTick: 0, toTick: 120), .unchanged)
    }

    func testLaneEvent_loadOnEnteringRegion() {
        let r = region(laneA, start: 240, length: 480)
        let d = doc(lanes: [midiLane(laneA)], [r])
        XCTAssertEqual(S.laneEvent(in: d, laneID: laneA, fromTick: 120, toTick: 240), .load(r))
    }

    func testLaneEvent_clearOnLeavingToGap() {
        let r = region(laneA, start: 0, length: 240)   // [0, 240)
        let d = doc(lanes: [midiLane(laneA)], [r])
        XCTAssertEqual(S.laneEvent(in: d, laneID: laneA, fromTick: 120, toTick: 240), .clear)
    }

    func testLaneEvent_switchBetweenAdjacentRegions() {
        let a = region(laneA, start: 0, length: 1920)       // [0, 1920)
        let b = region(laneA, start: 1920, length: 1920)    // [1920, 3840)
        let d = doc(lanes: [midiLane(laneA)], [a, b])
        XCTAssertEqual(S.laneEvent(in: d, laneID: laneA, fromTick: 1800, toTick: 1920), .load(b))
    }

    func testLaneEvent_loopWrap_reloadsFirstRegion() {
        let a = region(laneA, start: 0, length: 1920)
        let b = region(laneA, start: 1920, length: 1920)
        let d = doc(lanes: [midiLane(laneA)], [a, b])
        // Playhead wraps from the end of B back to the top → active region changes B→A.
        XCTAssertEqual(S.laneEvent(in: d, laneID: laneA, fromTick: 3800, toTick: 0), .load(a))
    }

    // MARK: - roll / audio lane selection

    func testRollLaneID_firstNonBioMidi() {
        let bio = UUID(); let midi = UUID()
        let d = doc(lanes: [midiLane(bio, bio: true), midiLane(midi), audioLane(laneB)], [])
        XCTAssertEqual(d.rollLaneID, midi, "skips the bio lane, picks the first real MIDI lane")
    }

    func testRollLaneID_nilWhenNoMidi() {
        let d = doc(lanes: [audioLane(laneB)], [])
        XCTAssertNil(d.rollLaneID)
    }

    func testAudioLaneIDs_inOrder_excludesMidiAndBio() {
        let a1 = UUID(); let a2 = UUID()
        let d = doc(lanes: [midiLane(laneA), audioLane(a1), midiLane(UUID(), bio: true), audioLane(a2)], [])
        XCTAssertEqual(d.audioLaneIDs, [a1, a2])
    }
}
