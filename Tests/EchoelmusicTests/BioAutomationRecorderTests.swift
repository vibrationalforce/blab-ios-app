// BioAutomationRecorderTests.swift
// Pure tests for the per-track bio-record capture core (B18) — anchor gating,
// decimation, value clamping, lane build. No engine → runs on every platform.

import XCTest
@testable import Echoelmusic

final class BioAutomationRecorderTests: XCTestCase {

    private let step = TimelineTime.ticksPerTransportStep   // 120

    func testCaptureBeforeAnchor_isIgnored() {
        var r = BioAutomationRecorder(parameter: "bio.coherence", anchorTick: 1000)
        r.capture(value: 0.5, atTick: 500)     // before anchor
        r.capture(value: 0.6, atTick: 999)
        XCTAssertEqual(r.pointCount, 0)
        XCTAssertFalse(r.hasContent)
        XCTAssertTrue(r.lane().isEmpty)
    }

    func testFirstSampleAtOrAfterAnchor_isKept() {
        var r = BioAutomationRecorder(parameter: "bio.hr", anchorTick: 480)
        r.capture(value: 0.7, atTick: 480)
        XCTAssertEqual(r.pointCount, 1)
        XCTAssertTrue(r.hasContent)
    }

    func testDecimation_dropsSamplesCloserThanInterval() {
        var r = BioAutomationRecorder(parameter: "bio.hrv", anchorTick: 0, minTickInterval: step)
        r.capture(value: 0.1, atTick: 0)       // kept (first)
        r.capture(value: 0.2, atTick: 60)      // < 120 → dropped
        r.capture(value: 0.3, atTick: 119)     // < 120 → dropped
        r.capture(value: 0.4, atTick: 120)     // == interval → kept
        r.capture(value: 0.5, atTick: 130)     // < 240 → dropped
        r.capture(value: 0.6, atTick: 240)     // kept
        let pts = r.lane().points
        XCTAssertEqual(pts.map(\.tick), [0, 120, 240])
        XCTAssertEqual(pts.map(\.value), [0.1, 0.4, 0.6])
    }

    func testBackwardsOrEqualTick_isIgnored() {
        var r = BioAutomationRecorder(parameter: "bio.motion", anchorTick: 0, minTickInterval: 1)
        r.capture(value: 0.5, atTick: 200)     // kept
        r.capture(value: 0.9, atTick: 200)     // equal → within [last, last+1) → dropped
        r.capture(value: 0.9, atTick: 150)     // backwards → dropped
        XCTAssertEqual(r.lane().points.map(\.tick), [200])
    }

    func testValues_areClampedToUnitRange() {
        var r = BioAutomationRecorder(parameter: "bio.breath", anchorTick: 0, minTickInterval: step)
        r.capture(value: 1.5, atTick: 0)                       // → 1
        r.capture(value: -0.5, atTick: step)                   // → 0
        r.capture(value: .nan, atTick: step * 2)               // → 0
        XCTAssertEqual(r.lane().points.map(\.value), [1.0, 0.0, 0.0])
    }

    func testLane_carriesParameterAndSortedPoints() {
        var r = BioAutomationRecorder(parameter: "bio.coherence", anchorTick: 0, minTickInterval: step)
        r.capture(value: 0.2, atTick: 0)
        r.capture(value: 0.8, atTick: step * 3)
        let lane = r.lane()
        XCTAssertEqual(lane.parameter, "bio.coherence")
        XCTAssertEqual(lane.points.map(\.tick), [0, step * 3])
        // Replays like any automation.
        XCTAssertEqual(lane.value(atTick: 0), 0.2)
        XCTAssertEqual(lane.value(atTick: step * 3), 0.8)
    }

    func testEmptyRecorder_yieldsEmptyLane() {
        let r = BioAutomationRecorder(parameter: "bio.hr")
        XCTAssertTrue(r.lane().isEmpty)
        XCTAssertFalse(r.hasContent)
    }
}
