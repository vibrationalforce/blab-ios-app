// VideoExportPlanTests.swift
// Echoel — Sequencer tests for the pure video export planner.

import XCTest
@testable import Echoelmusic

final class VideoExportPlanTests: XCTestCase {

    // Fixed UUIDs — deterministic, no UUID() in test logic.
    private let laneA = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let laneB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    private let laneMidi = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
    private let clip1 = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
    private let clip2 = UUID(uuidString: "00000000-0000-0000-0000-000000000222")!
    private let clip3 = UUID(uuidString: "00000000-0000-0000-0000-000000000333")!

    private let bpm = 120.0

    // MARK: - Empty

    func testInstructions_emptyDocument_returnsEmpty() {
        XCTAssertEqual(VideoExportPlan.instructions(document: TimelineDocument(), bpm: bpm), [])
    }

    func testInstructions_noRegions_returnsEmpty() {
        let doc = TimelineDocument(lanes: [TimelineLane(id: laneA, name: "V", kind: .video)],
                                   regions: [])
        XCTAssertEqual(VideoExportPlan.instructions(document: doc, bpm: bpm), [])
    }

    // MARK: - Time ranges

    func testInstructions_timeRanges_ticksToSecondsAtBPM() {
        // 1920 ticks = 1 bar = 4 quarters; at 120 BPM one quarter = 0.5 s → 2.0 s span.
        let region = TimelineRegion(id: UUID(), laneID: laneA, clipID: clip1,
                                    startTick: TimelineTime.ticksPerBar,      // 1920 → 2.0s
                                    lengthTicks: TimelineTime.ticksPerBar,    // 1920 → 2.0s span
                                    contentOffsetSeconds: 1.5)
        let doc = TimelineDocument(lanes: [TimelineLane(id: laneA, name: "V", kind: .video)],
                                   regions: [region])

        let out = VideoExportPlan.instructions(document: doc, bpm: bpm)
        XCTAssertEqual(out.count, 1)
        let i = out[0]
        XCTAssertEqual(i.laneID, laneA)
        XCTAssertEqual(i.clipID, clip1)
        XCTAssertEqual(i.timelineStartSeconds, 2.0, accuracy: 1e-9)
        XCTAssertEqual(i.timelineDurationSeconds, 2.0, accuracy: 1e-9)
        XCTAssertEqual(i.sourceStartSeconds, 1.5, accuracy: 1e-9)      // = contentOffsetSeconds
        XCTAssertEqual(i.sourceDurationSeconds, 2.0, accuracy: 1e-9)   // real-time: == timeline span
        XCTAssertEqual(i.zIndex, 0)
        XCTAssertEqual(i.opacity, 1)
    }

    func testInstructions_negativeContentOffset_clampedToZero() {
        // TimelineRegion clamps contentOffsetSeconds to ≥ 0 at construction; verify the
        // instruction reflects a non-negative source start.
        let region = TimelineRegion(id: UUID(), laneID: laneA, clipID: clip1,
                                    startTick: 0, lengthTicks: 480,
                                    contentOffsetSeconds: -5)
        let doc = TimelineDocument(lanes: [TimelineLane(id: laneA, name: "V", kind: .video)],
                                   regions: [region])
        let out = VideoExportPlan.instructions(document: doc, bpm: bpm)
        XCTAssertEqual(out.count, 1)
        XCTAssertGreaterThanOrEqual(out[0].sourceStartSeconds, 0)
    }

    // MARK: - Z-order across multi-lane overlaps

    func testInstructions_zOrder_byLaneOrder_deterministic() {
        // Two video lanes with overlapping regions at the same tick. Lane order in the
        // document must fix the z-order (A = 0, B = 1) regardless of region contents.
        let rA = TimelineRegion(id: UUID(), laneID: laneA, clipID: clip1,
                                startTick: 0, lengthTicks: 960)
        let rB = TimelineRegion(id: UUID(), laneID: laneB, clipID: clip2,
                                startTick: 0, lengthTicks: 960)
        let doc = TimelineDocument(
            lanes: [TimelineLane(id: laneA, name: "A", kind: .video),
                    TimelineLane(id: laneB, name: "B", kind: .video)],
            regions: [rB, rA])   // deliberately out of lane order in the array

        let out = VideoExportPlan.instructions(document: doc, bpm: bpm)
        XCTAssertEqual(out.count, 2)
        // z ordered, first entry is lane A (z 0), second is lane B (z 1).
        XCTAssertEqual(out[0].laneID, laneA)
        XCTAssertEqual(out[0].zIndex, 0)
        XCTAssertEqual(out[1].laneID, laneB)
        XCTAssertEqual(out[1].zIndex, 1)

        // Deterministic: a second run yields identical output.
        XCTAssertEqual(VideoExportPlan.instructions(document: doc, bpm: bpm), out)
    }

    func testInstructions_withinLane_orderedByStartTick() {
        let late = TimelineRegion(id: UUID(), laneID: laneA, clipID: clip2,
                                  startTick: 1920, lengthTicks: 480)
        let early = TimelineRegion(id: UUID(), laneID: laneA, clipID: clip1,
                                   startTick: 0, lengthTicks: 480)
        let doc = TimelineDocument(lanes: [TimelineLane(id: laneA, name: "A", kind: .video)],
                                   regions: [late, early])
        let out = VideoExportPlan.instructions(document: doc, bpm: bpm)
        XCTAssertEqual(out.map(\.clipID), [clip1, clip2])   // early first
        XCTAssertEqual(out.map(\.zIndex), [0, 0])           // same lane → same z
    }

    // MARK: - Lane filtering

    func testInstructions_nonVideoLanes_excluded() {
        let vid = TimelineRegion(id: UUID(), laneID: laneA, clipID: clip1,
                                 startTick: 0, lengthTicks: 480)
        let midi = TimelineRegion(id: UUID(), laneID: laneMidi, clipID: clip3,
                                  startTick: 0, lengthTicks: 480)
        let doc = TimelineDocument(
            lanes: [TimelineLane(id: laneMidi, name: "M", kind: .midi),
                    TimelineLane(id: laneA, name: "V", kind: .video)],
            regions: [vid, midi])
        let out = VideoExportPlan.instructions(document: doc, bpm: bpm)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].clipID, clip1)
        XCTAssertEqual(out[0].laneID, laneA)
        // The MIDI lane preceding the video lane must NOT consume a z-index — the video
        // lane is the first VIDEO lane, so z 0.
        XCTAssertEqual(out[0].zIndex, 0)
    }

    func testInstructions_bioVideoLane_excluded() {
        // A lane can carry kind .video but be a bio lane; it must be excluded.
        let region = TimelineRegion(id: UUID(), laneID: laneA, clipID: clip1,
                                    startTick: 0, lengthTicks: 480)
        let doc = TimelineDocument(
            lanes: [TimelineLane(id: laneA, name: "Bio", kind: .video, isBio: true)],
            regions: [region])
        XCTAssertEqual(VideoExportPlan.instructions(document: doc, bpm: bpm), [])
    }

    // MARK: - Guards

    func testInstructions_zeroBPM_returnsEmpty() {
        let region = TimelineRegion(id: UUID(), laneID: laneA, clipID: clip1,
                                    startTick: 0, lengthTicks: 480)
        let doc = TimelineDocument(lanes: [TimelineLane(id: laneA, name: "V", kind: .video)],
                                   regions: [region])
        XCTAssertEqual(VideoExportPlan.instructions(document: doc, bpm: 0), [])
    }

    func testInstructions_negativeBPM_returnsEmpty() {
        let region = TimelineRegion(id: UUID(), laneID: laneA, clipID: clip1,
                                    startTick: 0, lengthTicks: 480)
        let doc = TimelineDocument(lanes: [TimelineLane(id: laneA, name: "V", kind: .video)],
                                   regions: [region])
        XCTAssertEqual(VideoExportPlan.instructions(document: doc, bpm: -60), [])
    }

    func testInstructions_emptyVideoLaneBetweenTwo_stableZIndex() {
        // Lane A (video, has region), lane B (video, empty), lane C (video, has region).
        // C must be z 2 — an empty video lane still advances the stack.
        let laneC = UUID(uuidString: "00000000-0000-0000-0000-0000000000D4")!
        let rA = TimelineRegion(id: UUID(), laneID: laneA, clipID: clip1,
                                startTick: 0, lengthTicks: 480)
        let rC = TimelineRegion(id: UUID(), laneID: laneC, clipID: clip2,
                                startTick: 0, lengthTicks: 480)
        let doc = TimelineDocument(
            lanes: [TimelineLane(id: laneA, name: "A", kind: .video),
                    TimelineLane(id: laneB, name: "B", kind: .video),
                    TimelineLane(id: laneC, name: "C", kind: .video)],
            regions: [rA, rC])
        let out = VideoExportPlan.instructions(document: doc, bpm: bpm)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].zIndex, 0)   // lane A
        XCTAssertEqual(out[1].zIndex, 2)   // lane C (B consumed z 1 despite being empty)
    }
}
