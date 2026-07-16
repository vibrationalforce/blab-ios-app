// VideoAudioPairingTests.swift
// Echoelmusic — Sequencer tests
//
// Pure coverage for where a video's extracted-audio clip lands so it stays locked to
// the video region (same span + start), which audio lane it picks, and slot-room.

import XCTest
@testable import Echoelmusic

final class VideoAudioPairingTests: XCTestCase {

    // MARK: - Lane choice

    func testPlan_withExistingAudioLane_landsOnFirst() {
        let a = UUID(), b = UUID()
        let plan = VideoAudioPairing.plan(videoStartTick: 0, videoLengthTicks: 3840,
                                          existingAudioLaneIDs: [a, b])
        XCTAssertEqual(plan.lane, .existing(a))   // document order — first wins
    }

    func testPlan_noAudioLane_requestsCreateNew() {
        let plan = VideoAudioPairing.plan(videoStartTick: 0, videoLengthTicks: 3840,
                                          existingAudioLaneIDs: [])
        XCTAssertEqual(plan.lane, .createNew)
    }

    // MARK: - Locked to the video region

    func testPlan_inheritsVideoStartAndSpan() {
        let plan = VideoAudioPairing.plan(videoStartTick: 1920, videoLengthTicks: 7680,
                                          existingAudioLaneIDs: [UUID()])
        XCTAssertEqual(plan.startTick, 1920)      // aligned to the video region
        XCTAssertEqual(plan.lengthTicks, 7680)    // same musical span — no drift
    }

    func testPlan_negativeStart_clampsToZero() {
        let plan = VideoAudioPairing.plan(videoStartTick: -100, videoLengthTicks: 1920,
                                          existingAudioLaneIDs: [UUID()])
        XCTAssertEqual(plan.startTick, 0)
    }

    func testPlan_zeroOrTinyLength_floorsAtOneBar() {
        let plan = VideoAudioPairing.plan(videoStartTick: 0, videoLengthTicks: 0,
                                          existingAudioLaneIDs: [UUID()])
        XCTAssertEqual(plan.lengthTicks, TimelineTime.ticksPerBar) // never a zero-length clip
    }

    // MARK: - Offset / gain passthrough + guards

    func testPlan_offsetAndGain_passThrough() {
        let plan = VideoAudioPairing.plan(videoStartTick: 0, videoLengthTicks: 1920,
                                          existingAudioLaneIDs: [UUID()],
                                          contentOffsetSeconds: 2.5, gain: 0.8)
        XCTAssertEqual(plan.contentOffsetSeconds, 2.5, accuracy: 1e-9)
        XCTAssertEqual(plan.gain, 0.8, accuracy: 1e-6)
    }

    func testPlan_nonFiniteOffsetOrGain_sanitized() {
        let plan = VideoAudioPairing.plan(videoStartTick: 0, videoLengthTicks: 1920,
                                          existingAudioLaneIDs: [UUID()],
                                          contentOffsetSeconds: .nan, gain: .infinity)
        XCTAssertEqual(plan.contentOffsetSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(plan.gain, 1, accuracy: 1e-6)
    }

    func testPlan_negativeOffset_clampsToZero() {
        let plan = VideoAudioPairing.plan(videoStartTick: 0, videoLengthTicks: 1920,
                                          existingAudioLaneIDs: [UUID()],
                                          contentOffsetSeconds: -3)
        XCTAssertEqual(plan.contentOffsetSeconds, 0, accuracy: 1e-9)
    }

    // MARK: - Slot room (video + audio both consume a clip slot)

    func testHasRoom_needsTwoFreeSlots() {
        XCTAssertEqual(VideoAudioPairing.requiredFreeSlots, 2)
        XCTAssertTrue(VideoAudioPairing.hasRoom(freeSlotCount: 2))
        XCTAssertTrue(VideoAudioPairing.hasRoom(freeSlotCount: 5))
        XCTAssertFalse(VideoAudioPairing.hasRoom(freeSlotCount: 1))
        XCTAssertFalse(VideoAudioPairing.hasRoom(freeSlotCount: 0))
    }
}
