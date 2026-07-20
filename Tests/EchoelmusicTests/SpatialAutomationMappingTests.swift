// SpatialAutomationMappingTests.swift
// Pure tests for the bridge that turns an Immersive-Stage puck gesture into
// replayable automation and back: SpatialPosition ↔ normalized [0…1] dimensions,
// multi-lane sampling at a tick, and the base fallback for untouched dimensions.
// No engine → runs on every platform (Linux included).

import XCTest
@testable import Echoelmusic

final class SpatialAutomationMappingTests: XCTestCase {

    // MARK: normalized() maps ranges to [0…1]

    func testNormalized_frontOrigin_isMidAzimuthMidElevation() {
        // azimuth 0 → 0.5, elevation 0 → 0.5, distance 1 → 1.
        let n = SpatialAutomationMapping.normalized(
            SpatialPosition(azimuth: 0, elevation: 0, distance: 1))
        XCTAssertEqual(n[SpatialAutomationMapping.azimuthKey] ?? -1, 0.5, accuracy: 1e-6)
        XCTAssertEqual(n[SpatialAutomationMapping.elevationKey] ?? -1, 0.5, accuracy: 1e-6)
        XCTAssertEqual(n[SpatialAutomationMapping.distanceKey] ?? -1, 1.0, accuracy: 1e-6)
    }

    func testNormalized_extremes_mapToZeroAndOne() {
        let low = SpatialAutomationMapping.normalized(
            SpatialPosition(azimuth: -180, elevation: -90, distance: 0))
        XCTAssertEqual(low[SpatialAutomationMapping.azimuthKey] ?? -1, 0.0, accuracy: 1e-6)
        XCTAssertEqual(low[SpatialAutomationMapping.elevationKey] ?? -1, 0.0, accuracy: 1e-6)
        XCTAssertEqual(low[SpatialAutomationMapping.distanceKey] ?? -1, 0.0, accuracy: 1e-6)

        let high = SpatialAutomationMapping.normalized(
            SpatialPosition(azimuth: 180, elevation: 90, distance: 1))
        XCTAssertEqual(high[SpatialAutomationMapping.azimuthKey] ?? -1, 1.0, accuracy: 1e-6)
        XCTAssertEqual(high[SpatialAutomationMapping.elevationKey] ?? -1, 1.0, accuracy: 1e-6)
        XCTAssertEqual(high[SpatialAutomationMapping.distanceKey] ?? -1, 1.0, accuracy: 1e-6)
    }

    // MARK: denormalize round-trips losslessly

    func testRoundTrip_arbitraryPosition_isLossless() {
        let original = SpatialPosition(azimuth: -63, elevation: 27, distance: 0.42)
        let n = SpatialAutomationMapping.normalized(original)
        let az = SpatialAutomationMapping.azimuth(fromNormalized: n[SpatialAutomationMapping.azimuthKey]!)
        let el = SpatialAutomationMapping.elevation(fromNormalized: n[SpatialAutomationMapping.elevationKey]!)
        let di = SpatialAutomationMapping.distance(fromNormalized: n[SpatialAutomationMapping.distanceKey]!)
        XCTAssertEqual(az, original.azimuth, accuracy: 1e-3)
        XCTAssertEqual(el, original.elevation, accuracy: 1e-3)
        XCTAssertEqual(di, original.distance, accuracy: 1e-4)
    }

    // MARK: record a gesture then replay it at a tick

    func testRecordThenReplay_samplesTheRecordedPosition() {
        var rec = SpatialAutomationMapping.recorder(anchorTick: 0, minTickInterval: 1)
        let start = SpatialPosition(azimuth: -90, elevation: 0, distance: 0.2)
        let end = SpatialPosition(azimuth: 90, elevation: 0, distance: 1.0)
        rec.capture(SpatialAutomationMapping.normalized(start), atTick: 0)
        rec.capture(SpatialAutomationMapping.normalized(end), atTick: 100)

        let lanes = rec.lanes()
        XCTAssertEqual(lanes.count, 3, "azimuth + elevation + distance lanes")

        // At the anchor: the start position.
        let atStart = SpatialAutomationMapping.position(atTick: 0, from: lanes)
        XCTAssertEqual(atStart.azimuth, -90, accuracy: 1e-2)
        XCTAssertEqual(atStart.distance, 0.2, accuracy: 1e-3)

        // At the end tick: the end position.
        let atEnd = SpatialAutomationMapping.position(atTick: 100, from: lanes)
        XCTAssertEqual(atEnd.azimuth, 90, accuracy: 1e-2)
        XCTAssertEqual(atEnd.distance, 1.0, accuracy: 1e-3)

        // Midpoint: linear interpolation → azimuth 0, distance 0.6.
        let mid = SpatialAutomationMapping.position(atTick: 50, from: lanes)
        XCTAssertEqual(mid.azimuth, 0, accuracy: 1.0)
        XCTAssertEqual(mid.distance, 0.6, accuracy: 1e-2)
    }

    // MARK: an untouched dimension keeps the base

    func testMissingLane_keepsBaseValue() {
        // A 2D gesture: azimuth + distance only, elevation lane absent.
        var rec = AutomationGestureRecorder(
            parameters: [SpatialAutomationMapping.azimuthKey, SpatialAutomationMapping.distanceKey],
            anchorTick: 0, minTickInterval: 1)
        rec.capture([SpatialAutomationMapping.azimuthKey: 0.75,
                     SpatialAutomationMapping.distanceKey: 0.5], atTick: 0)
        let lanes = rec.lanes()
        XCTAssertEqual(lanes.count, 2)

        let base = SpatialPosition(azimuth: 0, elevation: 45, distance: 0)
        let p = SpatialAutomationMapping.position(atTick: 0, from: lanes, base: base)
        XCTAssertEqual(p.elevation, 45, accuracy: 1e-3, "no elevation lane → base height preserved")
        XCTAssertEqual(p.azimuth, 90, accuracy: 1e-2, "0.75 → 90°")
        XCTAssertEqual(p.distance, 0.5, accuracy: 1e-3)
    }

    // MARK: empty lane set → the base position

    func testNoLanes_returnsBase() {
        let base = SpatialPosition(azimuth: -30, elevation: 10, distance: 0.7)
        let p = SpatialAutomationMapping.position(atTick: 42, from: [], base: base)
        XCTAssertEqual(p, base)
    }
}
