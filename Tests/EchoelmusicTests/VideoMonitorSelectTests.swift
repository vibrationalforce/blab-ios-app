// VideoMonitorSelectTests.swift
// The Video Monitor's pure "which picture" selector (founder 2026-07-15: the header
// film button opens a floating video monitor). One window shows ONE picture: the
// FIRST unmuted video lane with an active region at the playhead wins; muted lanes
// and gaps are skipped; the playback outcome comes from the tested VideoRegionSync.
// Reference: TimelineTime.seconds(fromTicks: 480, bpm: 120) = 0.5 s.

import XCTest
@testable import Echoelmusic

final class VideoMonitorSelectTests: XCTestCase {

    private func videoLane(name: String, muted: Bool = false) -> TimelineLane {
        TimelineLane(name: name, kind: .video, isMuted: muted)
    }

    private func region(_ lane: TimelineLane, clipID: UUID = UUID(),
                        start: Int = 0, length: Int = 1920,
                        offset: Double = 0) -> TimelineRegion {
        TimelineRegion(laneID: lane.id, clipID: clipID, startTick: start,
                       lengthTicks: length, contentOffsetSeconds: offset)
    }

    func testActiveRegion_playsAtTrimPlusElapsed() {
        let lane = videoLane(name: "Video 1")
        let clip = UUID()
        let doc = TimelineDocument(lanes: [lane],
                                   regions: [region(lane, clipID: clip, offset: 2.0)])
        let picked = VideoMonitorSelect.active(in: doc, atTick: 480, bpm: 120,
                                               nativeDuration: { _ in 3600 })
        XCTAssertEqual(picked?.clipID, clip)
        // 480 ticks = 0.5 s @120 + trim-in 2.0 → source 2.5, running.
        XCTAssertEqual(picked?.playback, .play(sourceSeconds: 2.5))
    }

    func testGap_returnsNil() {
        let lane = videoLane(name: "Video 1")
        let doc = TimelineDocument(lanes: [lane], regions: [region(lane)])
        XCTAssertNil(VideoMonitorSelect.active(in: doc, atTick: 5000, bpm: 120,
                                               nativeDuration: { _ in 3600 }),
                     "past the region → nothing to show")
    }

    func testMutedFirstLane_secondLaneWins() {
        let muted = videoLane(name: "Video 1", muted: true)
        let live = videoLane(name: "Video 2")
        let liveClip = UUID()
        let doc = TimelineDocument(lanes: [muted, live],
                                   regions: [region(muted), region(live, clipID: liveClip)])
        let picked = VideoMonitorSelect.active(in: doc, atTick: 480, bpm: 120,
                                               nativeDuration: { _ in 3600 })
        XCTAssertEqual(picked?.clipID, liveClip, "a muted lane never reaches the monitor")
    }

    func testFirstLaneGap_fallsThroughToSecondLane() {
        let first = videoLane(name: "Video 1")
        let second = videoLane(name: "Video 2")
        let secondClip = UUID()
        // First lane's region ends at tick 480; second spans the playhead.
        let doc = TimelineDocument(
            lanes: [first, second],
            regions: [region(first, start: 0, length: 480),
                      region(second, clipID: secondClip, start: 0, length: 1920)])
        let picked = VideoMonitorSelect.active(in: doc, atTick: 960, bpm: 120,
                                               nativeDuration: { _ in 3600 })
        XCTAssertEqual(picked?.clipID, secondClip, "lane order decides; gaps fall through")
    }

    func testUnknownDuration_holdsFrameAtTrimIn() {
        // A STILL image (or a pre-duration-persist import) has no native duration →
        // VideoRegionSync holds a single frame at the trim-in; the monitor shows it held.
        let lane = videoLane(name: "Video 1")
        let doc = TimelineDocument(lanes: [lane], regions: [region(lane, offset: 1.5)])
        let picked = VideoMonitorSelect.active(in: doc, atTick: 480, bpm: 120,
                                               nativeDuration: { _ in 0 })
        XCTAssertEqual(picked?.playback, .exhausted(sourceSeconds: 1.5))
    }

    func testNoVideoLanes_returnsNil() {
        let midi = TimelineLane(name: "MIDI 1", kind: .midi)
        let doc = TimelineDocument(lanes: [midi], regions: [])
        XCTAssertNil(VideoMonitorSelect.active(in: doc, atTick: 0, bpm: 120,
                                               nativeDuration: { _ in 0 }))
    }
}
