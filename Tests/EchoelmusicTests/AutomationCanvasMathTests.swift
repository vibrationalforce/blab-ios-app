// AutomationCanvasMathTests.swift
// Echoel — geometry + touch laws of the drawable automation canvas (A3).

import XCTest
import Foundation
@testable import Echoelmusic

final class AutomationCanvasMathTests: XCTestCase {

    // MARK: Coordinate mapping

    func testXTickRoundTrip_andClamping() {
        let w = 320.0
        XCTAssertEqual(AutomationCanvasMath.x(forTick: 0, width: w), 0)
        XCTAssertEqual(AutomationCanvasMath.x(forTick: AutomationCanvasMath.barTicks, width: w), w)
        XCTAssertEqual(AutomationCanvasMath.tick(forX: w / 2, width: w),
                       AutomationCanvasMath.barTicks / 2)
        XCTAssertEqual(AutomationCanvasMath.tick(forX: -50, width: w), 0, "clamps left")
        XCTAssertEqual(AutomationCanvasMath.tick(forX: w * 2, width: w),
                       AutomationCanvasMath.barTicks, "clamps right")
        XCTAssertEqual(AutomationCanvasMath.tick(forX: .nan, width: w), 0, "guards NaN")
    }

    func testYValueMapping_topIsHigh() {
        let h = 200.0
        XCTAssertEqual(AutomationCanvasMath.y(forValue: 1, height: h), 0, "value 1 at the top")
        XCTAssertEqual(AutomationCanvasMath.y(forValue: 0, height: h), h)
        XCTAssertEqual(AutomationCanvasMath.value(forY: 0, height: h), 1)
        XCTAssertEqual(AutomationCanvasMath.value(forY: h * 2, height: h), 0, "clamps below")
    }

    func testSnappedTick_landsOn16thGrid() {
        XCTAssertEqual(AutomationCanvasMath.snappedTick(0), 0)
        XCTAssertEqual(AutomationCanvasMath.snappedTick(61), 120, "rounds up past half step")
        XCTAssertEqual(AutomationCanvasMath.snappedTick(59), 0, "rounds down before half step")
        XCTAssertEqual(AutomationCanvasMath.snappedTick(99_999),
                       AutomationCanvasMath.barTicks, "clamps into the bar")
    }

    // MARK: Hit-testing

    private func lanePoints() -> [AutomationPoint] {
        [AutomationPoint(tick: 0, value: 0.2),
         AutomationPoint(tick: 960, value: 0.8),
         AutomationPoint(tick: 1920, value: 0.5)]
    }

    func testNearestPoint_findsTheClosest() {
        let pts = lanePoints()
        let w = 384.0, h = 100.0   // 960 ticks → x=192
        let hit = AutomationCanvasMath.nearestPoint(toX: 190, y: 22, points: pts,
                                                    width: w, height: h)
        XCTAssertEqual(hit?.id, pts[1].id)
        XCTAssertNotNil(hit); XCTAssertLessThan(hit!.distance, 4)
        XCTAssertNil(AutomationCanvasMath.nearestPoint(toX: 0, y: 0, points: [],
                                                       width: w, height: h))
    }

    func testSegmentLeftPoint_betweenTwoPoints_elseNil() {
        let pts = lanePoints()
        let w = 384.0
        // x=100 → tick 500: between point 0 (tick 0) and point 1 (tick 960).
        XCTAssertEqual(AutomationCanvasMath.segmentLeftPoint(atX: 100, points: pts, width: w)?.id,
                       pts[0].id)
        // x exactly on a point is NOT inside a segment (strict betweenness).
        XCTAssertEqual(AutomationCanvasMath.segmentLeftPoint(atX: 192, points: pts, width: w)?.id,
                       nil)
        // Single point → no segment.
        XCTAssertNil(AutomationCanvasMath.segmentLeftPoint(atX: 100, points: [pts[0]], width: w))
    }

    func testSegmentLeftPoint_worksOnUnsortedInput() {
        let pts = lanePoints().reversed()
        let hit = AutomationCanvasMath.segmentLeftPoint(atX: 100, points: Array(pts), width: 384)
        XCTAssertEqual(hit?.tick, 0)
    }

    // MARK: Bend law

    func testBentCurvature_upDragBulgesUp_bothDirections() {
        // Rising segment: up-drag → negative curvature (ease-out bulges up).
        let rising = AutomationCanvasMath.bentCurvature(start: 0, dragUpPoints: 60,
                                                        risingSegment: true)
        XCTAssertEqual(rising, -0.5, accuracy: 1e-9)
        // Falling segment: the same up-drag needs positive curvature.
        let falling = AutomationCanvasMath.bentCurvature(start: 0, dragUpPoints: 60,
                                                         risingSegment: false)
        XCTAssertEqual(falling, 0.5, accuracy: 1e-9)
        // And the shaped midpoint really moves toward the top in both cases:
        // rising 0→1 with c=−0.5: mid > 0.5; falling 1→0 with c=+0.5: value at
        // mid = 1 − shaped(0.5) > 0.5.
        XCTAssertGreaterThan(AutomationLane.shapedFraction(0.5, curvature: rising), 0.5)
        XCTAssertLessThan(AutomationLane.shapedFraction(0.5, curvature: falling), 0.5)
    }

    func testBentCurvature_clampsAndAccumulatesFromStart() {
        XCTAssertEqual(AutomationCanvasMath.bentCurvature(start: -0.8, dragUpPoints: 240,
                                                          risingSegment: true), -1)
        XCTAssertEqual(AutomationCanvasMath.bentCurvature(start: 0.25, dragUpPoints: -30,
                                                          risingSegment: true),
                       0.5, accuracy: 1e-9, "down-drag on rising segment adds positive bend")
        XCTAssertEqual(AutomationCanvasMath.bentCurvature(start: 0.3, dragUpPoints: .nan,
                                                          risingSegment: true), 0.3)
    }
}
