// AutomationCanvasMathSpanTests.swift
// Automation-in-track cycle 3 — the canvas geometry generalizes from the fixed
// 1-bar span to ANY span (clip length in C4, arrangement window in C5) via a
// `spanTicks` parameter. Default stays one bar, so every existing call site and
// the shipped 1-bar behaviour are bit-identical.

import XCTest
@testable import Echoelmusic

final class AutomationCanvasMathSpanTests: XCTestCase {

    private let fourBars = 4 * AutomationCanvasMath.barTicks

    // MARK: - Defaults unchanged (the shipped 1-bar canvas must not move)

    func testDefaultSpanIsOneBar() {
        XCTAssertEqual(AutomationCanvasMath.x(forTick: AutomationCanvasMath.barTicks,
                                              width: 320),
                       320, accuracy: 1e-9)
        XCTAssertEqual(AutomationCanvasMath.tick(forX: 160, width: 320),
                       AutomationCanvasMath.barTicks / 2)
    }

    // MARK: - x/tick over an arbitrary span

    func testXScalesToSpan() {
        // The 1-bar tick sits at 1/4 width when the span is 4 bars.
        XCTAssertEqual(AutomationCanvasMath.x(forTick: AutomationCanvasMath.barTicks,
                                              width: 400, spanTicks: fourBars),
                       100, accuracy: 1e-9)
        // End of span = full width; beyond clamps.
        XCTAssertEqual(AutomationCanvasMath.x(forTick: fourBars + 999,
                                              width: 400, spanTicks: fourBars),
                       400, accuracy: 1e-9)
    }

    func testTickInverseOverSpan() {
        XCTAssertEqual(AutomationCanvasMath.tick(forX: 100, width: 400, spanTicks: fourBars),
                       AutomationCanvasMath.barTicks)
        XCTAssertEqual(AutomationCanvasMath.tick(forX: 400, width: 400, spanTicks: fourBars),
                       fourBars)
        // Out-of-canvas clamps into the span, never negative / never past it.
        XCTAssertEqual(AutomationCanvasMath.tick(forX: -50, width: 400, spanTicks: fourBars), 0)
        XCTAssertEqual(AutomationCanvasMath.tick(forX: 999, width: 400, spanTicks: fourBars),
                       fourBars)
    }

    func testRoundTripTickXTick() {
        for tick in stride(from: 0, through: fourBars, by: AutomationCanvasMath.snapTicks) {
            let x = AutomationCanvasMath.x(forTick: tick, width: 800, spanTicks: fourBars)
            XCTAssertEqual(AutomationCanvasMath.tick(forX: x, width: 800, spanTicks: fourBars),
                           tick, "tick \(tick) must round-trip through x")
        }
    }

    // MARK: - Snap clamps into the span

    func testSnappedTickClampsToSpan() {
        let s = AutomationCanvasMath.snapTicks
        XCTAssertEqual(AutomationCanvasMath.snappedTick(fourBars - s / 4, spanTicks: fourBars),
                       fourBars)
        XCTAssertEqual(AutomationCanvasMath.snappedTick(fourBars + 5 * s, spanTicks: fourBars),
                       fourBars)
        XCTAssertEqual(AutomationCanvasMath.snappedTick(-30, spanTicks: fourBars), 0)
        // Default still clamps to one bar.
        XCTAssertEqual(AutomationCanvasMath.snappedTick(AutomationCanvasMath.barTicks * 3),
                       AutomationCanvasMath.barTicks)
    }

    // MARK: - Segment hit-testing over a span

    func testSegmentLeftPointOverSpan() {
        var lane = AutomationLane(parameter: "test")
        let a = lane.addPoint(tick: 0, value: 0)
        _ = lane.addPoint(tick: fourBars, value: 1)
        // Mid-canvas on a 4-bar span lies between the two points…
        let hit = AutomationCanvasMath.segmentLeftPoint(atX: 200, points: lane.points,
                                                        width: 400, spanTicks: fourBars)
        XCTAssertEqual(hit?.id, a.id)
        // …but with the DEFAULT 1-bar span the same x maps past the last 1-bar
        // tick of point a's segment only if a second point is inside the bar.
        let none = AutomationCanvasMath.segmentLeftPoint(
            atX: 200, points: [a], width: 400, spanTicks: fourBars)
        XCTAssertNil(none, "fewer than 2 points can never hit a segment")
    }

    // MARK: - Degenerate guards (never a crash, never NaN)

    func testDegenerateSpanAndWidthGuards() {
        XCTAssertEqual(AutomationCanvasMath.x(forTick: 100, width: 320, spanTicks: 0), 0)
        XCTAssertEqual(AutomationCanvasMath.tick(forX: 100, width: 320, spanTicks: -5), 0)
        XCTAssertEqual(AutomationCanvasMath.snappedTick(100, spanTicks: 0), 0)
        XCTAssertEqual(AutomationCanvasMath.x(forTick: 100, width: 0, spanTicks: fourBars), 0)
    }
}
