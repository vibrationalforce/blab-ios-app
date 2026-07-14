// AutomationGestureRecorderTests.swift
// Pure tests for the multi-dimensional automation gesture recorder — records N
// named parameter dimensions at once (Touch surface: object X/Y/Z, focus, FX),
// mirroring BioAutomationRecorder's anchor-gate + per-parameter decimation +
// [0...1] clamp, and emitting one clip-relative AutomationLane per parameter.
// No engine → runs on every platform.

import XCTest
@testable import Echoelmusic

final class AutomationGestureRecorderTests: XCTestCase {

    // MARK: Two parameters captured together → two lanes

    func testTwoParametersCapturedTogether_yieldTwoLanes() {
        var r = AutomationGestureRecorder(parameters: ["obj.x", "obj.y"], minTickInterval: 60)
        r.capture(["obj.x": 0.2, "obj.y": 0.8], atTick: 0)
        r.capture(["obj.x": 0.4, "obj.y": 0.6], atTick: 60)
        let lanes = r.lanes()
        XCTAssertEqual(lanes.count, 2)
        XCTAssertEqual(lanes.map(\.parameter), ["obj.x", "obj.y"])   // declared order
        let x = lanes[0]
        let y = lanes[1]
        XCTAssertEqual(x.points.map(\.tick), [0, 60])
        XCTAssertEqual(x.points.map(\.value), [0.2, 0.4])
        XCTAssertEqual(y.points.map(\.tick), [0, 60])
        XCTAssertEqual(y.points.map(\.value), [0.8, 0.6])
        XCTAssertTrue(r.hasContent)
    }

    // MARK: A five-dimensional gesture (X, Y, Z, focus, FX) at once

    func testFiveDimensionalGesture_producesFiveSynchronizedLanes() {
        let dims = ["obj.x", "obj.y", "obj.z", "focus", "fx.mix"]
        var r = AutomationGestureRecorder(parameters: dims, minTickInterval: 60)
        r.capture(["obj.x": 0.1, "obj.y": 0.2, "obj.z": 0.3, "focus": 0.4, "fx.mix": 0.5], atTick: 0)
        r.capture(["obj.x": 0.6, "obj.y": 0.7, "obj.z": 0.8, "focus": 0.9, "fx.mix": 1.0], atTick: 120)
        let lanes = r.lanes()
        XCTAssertEqual(lanes.map(\.parameter), dims)
        for lane in lanes {
            XCTAssertEqual(lane.points.map(\.tick), [0, 120])
        }
        XCTAssertEqual(r.pointCount, 10)
    }

    // MARK: Decimation is per-parameter

    func testDecimation_dropsSamplesCloserThanInterval_perParameter() {
        var r = AutomationGestureRecorder(parameters: ["a", "b"], minTickInterval: 120)
        r.capture(["a": 0.1, "b": 0.1], atTick: 0)     // both kept (first)
        r.capture(["a": 0.2, "b": 0.2], atTick: 60)    // < 120 → both dropped
        r.capture(["a": 0.3, "b": 0.3], atTick: 119)   // < 120 → both dropped
        r.capture(["a": 0.4, "b": 0.4], atTick: 120)   // == interval → both kept
        r.capture(["a": 0.5, "b": 0.5], atTick: 130)   // < 240 → both dropped
        r.capture(["a": 0.6, "b": 0.6], atTick: 240)   // kept
        let lanes = r.lanes()
        for lane in lanes {
            XCTAssertEqual(lane.points.map(\.tick), [0, 120, 240])
            XCTAssertEqual(lane.points.map(\.value), [0.1, 0.4, 0.6])
        }
    }

    func testDecimation_cursorsAreIndependentPerParameter() {
        // "a" and "b" arrive on different ticks — each decimates on its OWN cadence.
        var r = AutomationGestureRecorder(parameters: ["a", "b"], minTickInterval: 100)
        r.capture(["a": 0.1], atTick: 0)               // a kept
        r.capture(["b": 0.1], atTick: 50)              // b kept (b's first, a untouched)
        r.capture(["a": 0.2], atTick: 90)              // a: 90 < 0+100 → dropped
        r.capture(["b": 0.2], atTick: 140)             // b: 140 < 50+100=150 → dropped
        r.capture(["a": 0.3], atTick: 100)             // a: 100 >= 100 → kept
        r.capture(["b": 0.3], atTick: 150)             // b: 150 >= 150 → kept
        let lanes = Dictionary(uniqueKeysWithValues: r.lanes().map { ($0.parameter, $0) })
        XCTAssertEqual(lanes["a"]?.points.map(\.tick), [0, 100])
        XCTAssertEqual(lanes["b"]?.points.map(\.tick), [50, 150])   // clip-relative to anchor 0 (b's own ticks)
        XCTAssertEqual(lanes["b"]?.points.map(\.value), [0.1, 0.3])
    }

    // MARK: Clamp

    func testValues_areClampedToUnitRange() {
        var r = AutomationGestureRecorder(parameters: ["x", "y", "z"], minTickInterval: 120)
        r.capture(["x": 1.5, "y": -0.5, "z": .nan], atTick: 0)
        let lanes = Dictionary(uniqueKeysWithValues: r.lanes().map { ($0.parameter, $0) })
        XCTAssertEqual(lanes["x"]?.points.map(\.value), [1.0])   // 1.5 → 1
        XCTAssertEqual(lanes["y"]?.points.map(\.value), [0.0])   // -0.5 → 0
        XCTAssertEqual(lanes["z"]?.points.map(\.value), [0.0])   // NaN → 0
    }

    // MARK: Empty parameters dropped from lanes()

    func testParameterWithNoValues_isDroppedFromLanes() {
        var r = AutomationGestureRecorder(parameters: ["used", "unused"], minTickInterval: 60)
        r.capture(["used": 0.5], atTick: 0)
        let lanes = r.lanes()
        XCTAssertEqual(lanes.count, 1)
        XCTAssertEqual(lanes.first?.parameter, "used")
        XCTAssertEqual(r.pointCount(for: "unused"), 0)
    }

    func testParameterNeverCaptured_yieldsNoLane() {
        // Declared but never fed → no lane at all (not a flat/empty one).
        var r = AutomationGestureRecorder(parameters: ["a", "b", "c"], minTickInterval: 60)
        r.capture(["a": 0.3, "c": 0.7], atTick: 0)
        XCTAssertEqual(r.lanes().map(\.parameter), ["a", "c"])   // "b" absent, order preserved
    }

    func testUnknownKeyInValues_isIgnored() {
        var r = AutomationGestureRecorder(parameters: ["a"], minTickInterval: 60)
        r.capture(["a": 0.5, "stranger": 0.9], atTick: 0)
        XCTAssertEqual(r.lanes().map(\.parameter), ["a"])
        XCTAssertEqual(r.pointCount, 1)
    }

    // MARK: Anchor makes ticks clip-relative

    func testAnchor_makesEmittedTicksClipRelative() {
        var r = AutomationGestureRecorder(parameters: ["x"], anchorTick: 1000, minTickInterval: 120)
        r.capture(["x": 0.2], atTick: 1000)    // relative 0
        r.capture(["x": 0.6], atTick: 1240)    // relative 240
        let lane = r.lanes().first
        XCTAssertEqual(lane?.points.map(\.tick), [0, 240])
        // Replays like any automation from clip tick 0.
        XCTAssertEqual(lane?.value(atTick: 0), 0.2)
        XCTAssertEqual(lane?.value(atTick: 240), 0.6)
    }

    func testCaptureBeforeAnchor_isIgnored() {
        var r = AutomationGestureRecorder(parameters: ["x"], anchorTick: 1000, minTickInterval: 60)
        r.capture(["x": 0.5], atTick: 500)     // before anchor
        r.capture(["x": 0.6], atTick: 999)     // before anchor
        XCTAssertFalse(r.hasContent)
        XCTAssertTrue(r.lanes().isEmpty)
    }

    // MARK: hasContent / empty recorder

    func testEmptyRecorder_hasNoContentAndNoLanes() {
        let r = AutomationGestureRecorder(parameters: ["a", "b"])
        XCTAssertFalse(r.hasContent)
        XCTAssertTrue(r.lanes().isEmpty)
        XCTAssertEqual(r.pointCount, 0)
    }

    func testDefaultMinTickInterval_isSixty() {
        var r = AutomationGestureRecorder(parameters: ["x"])   // default 60
        r.capture(["x": 0.1], atTick: 0)       // kept
        r.capture(["x": 0.2], atTick: 59)      // < 60 → dropped
        r.capture(["x": 0.3], atTick: 60)      // == 60 → kept
        XCTAssertEqual(r.lanes().first?.points.map(\.tick), [0, 60])
    }
}
