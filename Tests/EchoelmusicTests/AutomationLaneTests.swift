// AutomationLaneTests.swift
// Echoelmusic — time-based parameter automation (pure value type).

import XCTest
@testable import Echoelmusic

final class AutomationLaneTests: XCTestCase {

    func testEmptyLaneReturnsNil() {
        let lane = AutomationLane(parameter: "filter.cutoff")
        XCTAssertTrue(lane.isEmpty)
        XCTAssertNil(lane.value(atTick: 0))
        XCTAssertNil(lane.value(atTick: 1000))
    }

    func testHoldBeforeFirstAndAfterLast() {
        var lane = AutomationLane(parameter: "mix.level")
        lane.addPoint(tick: 480, value: 0.2)
        lane.addPoint(tick: 1440, value: 0.8)
        XCTAssertEqual(lane.value(atTick: 0), 0.2, "before first holds first value")
        XCTAssertEqual(lane.value(atTick: 480), 0.2)
        XCTAssertEqual(lane.value(atTick: 5000), 0.8, "after last holds last value")
    }

    func testLinearInterpolationMidpoint() {
        var lane = AutomationLane(parameter: "p")
        lane.addPoint(tick: 0, value: 0.0, curve: .linear)
        lane.addPoint(tick: 1000, value: 1.0)
        XCTAssertEqual(lane.value(atTick: 500) ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(lane.value(atTick: 250) ?? -1, 0.25, accuracy: 1e-9)
    }

    func testHoldCurveStepsAtNextPoint() {
        var lane = AutomationLane(parameter: "p")
        lane.addPoint(tick: 0, value: 0.0, curve: .hold)
        lane.addPoint(tick: 1000, value: 1.0)
        XCTAssertEqual(lane.value(atTick: 500), 0.0, "hold keeps the left value")
        XCTAssertEqual(lane.value(atTick: 999), 0.0)
        XCTAssertEqual(lane.value(atTick: 1000), 1.0, "steps at the next keyframe")
    }

    func testPointsStaySortedRegardlessOfInsertOrder() {
        var lane = AutomationLane(parameter: "p")
        lane.addPoint(tick: 2000, value: 1.0, curve: .linear)
        lane.addPoint(tick: 0, value: 0.0, curve: .linear)
        lane.addPoint(tick: 1000, value: 0.5, curve: .linear)
        XCTAssertEqual(lane.points.map(\.tick), [0, 1000, 2000])
        XCTAssertEqual(lane.value(atTick: 500) ?? -1, 0.25, accuracy: 1e-9)
    }

    func testValueAndTickClamping() {
        var lane = AutomationLane(parameter: "p")
        let p = lane.addPoint(tick: -50, value: 9, curve: .linear)
        XCTAssertEqual(p.tick, 0, "negative tick clamps to 0")
        XCTAssertEqual(p.value, 1, "value clamps to <= 1")
        lane.setValue(id: p.id, -3)
        XCTAssertEqual(lane.points.first?.value, 0, "value clamps to >= 0")
    }

    func testMoveAndRemove() {
        var lane = AutomationLane(parameter: "p")
        let a = lane.addPoint(tick: 0, value: 0.0)
        let b = lane.addPoint(tick: 500, value: 1.0)
        lane.movePoint(id: a.id, toTick: 1000)
        XCTAssertEqual(lane.points.map(\.tick), [500, 1000], "re-sorts after move")
        lane.removePoint(id: b.id)
        XCTAssertEqual(lane.points.count, 1)
        XCTAssertEqual(lane.points.first?.id, a.id)
    }

    func testCodableRoundTrip() throws {
        var lane = AutomationLane(parameter: "filter.cutoff")
        lane.addPoint(tick: 0, value: 0.1, curve: .hold)
        lane.addPoint(tick: 960, value: 0.9, curve: .linear)
        let data = try JSONEncoder().encode(lane)
        let decoded = try JSONDecoder().decode(AutomationLane.self, from: data)
        XCTAssertEqual(decoded, lane)
        XCTAssertEqual(decoded.value(atTick: 480) ?? -1,
                       lane.value(atTick: 480) ?? -2, accuracy: 1e-9)
    }
}
