// ImmersiveStageMathTests.swift
// Pure geometry of the Immersive Stage puck placement. Convention: azimuth 0 = front
// (top of disc), +90 = left (screen-left), distance 0…1 = normalized radius.

import XCTest
@testable import Echoelmusic

final class ImmersiveStageMathTests: XCTestCase {

    private let center = (x: 100.0, y: 100.0)
    private let radius = 80.0

    // MARK: point(azimuth:distance:)

    func testFrontAtRimIsTopCentre() {
        let p = ImmersiveStageMath.point(azimuthDeg: 0, distance: 1, center: center, radius: radius)
        XCTAssertEqual(p.x, 100, accuracy: 0.001)   // centred horizontally
        XCTAssertEqual(p.y, 20, accuracy: 0.001)    // up = centre.y − radius
    }

    func testLeftAtRimIsScreenLeft() {
        let p = ImmersiveStageMath.point(azimuthDeg: 90, distance: 1, center: center, radius: radius)
        XCTAssertEqual(p.x, 20, accuracy: 0.001)    // left = centre.x − radius
        XCTAssertEqual(p.y, 100, accuracy: 0.001)
    }

    func testRightAtRimIsScreenRight() {
        let p = ImmersiveStageMath.point(azimuthDeg: -90, distance: 1, center: center, radius: radius)
        XCTAssertEqual(p.x, 180, accuracy: 0.001)   // right = centre.x + radius
        XCTAssertEqual(p.y, 100, accuracy: 0.001)
    }

    func testBackAtRimIsBottomCentre() {
        let p = ImmersiveStageMath.point(azimuthDeg: 180, distance: 1, center: center, radius: radius)
        XCTAssertEqual(p.x, 100, accuracy: 0.001)
        XCTAssertEqual(p.y, 180, accuracy: 0.001)   // back = centre.y + radius
    }

    func testCentreDistanceZeroSitsOnCentre() {
        let p = ImmersiveStageMath.point(azimuthDeg: 45, distance: 0, center: center, radius: radius)
        XCTAssertEqual(p.x, 100, accuracy: 0.001)
        XCTAssertEqual(p.y, 100, accuracy: 0.001)
    }

    func testDistanceClampsToRim() {
        let p = ImmersiveStageMath.point(azimuthDeg: 0, distance: 5, center: center, radius: radius)
        XCTAssertEqual(p.y, 20, accuracy: 0.001)    // clamped to distance 1
    }

    // MARK: azimuthDistance(forPoint:) — inverse

    func testInverseTopIsFront() {
        let r = ImmersiveStageMath.azimuthDistance(forPoint: (x: 100, y: 20), center: center, radius: radius)
        XCTAssertEqual(r.azimuthDeg, 0, accuracy: 0.001)
        XCTAssertEqual(r.distance, 1, accuracy: 0.001)
    }

    func testInverseLeftIsPlus90() {
        let r = ImmersiveStageMath.azimuthDistance(forPoint: (x: 20, y: 100), center: center, radius: radius)
        XCTAssertEqual(r.azimuthDeg, 90, accuracy: 0.001)
        XCTAssertEqual(r.distance, 1, accuracy: 0.001)
    }

    func testInverseRightIsMinus90() {
        let r = ImmersiveStageMath.azimuthDistance(forPoint: (x: 180, y: 100), center: center, radius: radius)
        XCTAssertEqual(r.azimuthDeg, -90, accuracy: 0.001)
    }

    func testInverseBeyondRimClampsDistance() {
        let r = ImmersiveStageMath.azimuthDistance(forPoint: (x: 100, y: -200), center: center, radius: radius)
        XCTAssertEqual(r.distance, 1, accuracy: 0.001)   // clamped
        XCTAssertEqual(r.azimuthDeg, 0, accuracy: 0.001) // still front
    }

    func testInverseCentreKeepsFront() {
        let r = ImmersiveStageMath.azimuthDistance(forPoint: center, center: center, radius: radius)
        XCTAssertEqual(r.azimuthDeg, 0, accuracy: 0.001)
        XCTAssertEqual(r.distance, 0, accuracy: 0.001)
    }

    // MARK: round-trip

    func testRoundTripPreservesAzimuthAndDistance() {
        for az in stride(from: -150.0, through: 150.0, by: 30.0) {
            for dist in [0.2, 0.5, 0.9] {
                let p = ImmersiveStageMath.point(azimuthDeg: az, distance: dist, center: center, radius: radius)
                let back = ImmersiveStageMath.azimuthDistance(forPoint: p, center: center, radius: radius)
                XCTAssertEqual(back.azimuthDeg, az, accuracy: 0.01, "az \(az)")
                XCTAssertEqual(back.distance, dist, accuracy: 0.01, "dist \(dist)")
            }
        }
    }
}
