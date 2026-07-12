// BioSpaceMapTests.swift
// Echoel — S3 of the spatial expansion: the body→room mapping must be
// deterministic per preset, audibly DISTINCT across presets, slew-limited on
// every axis (wrap-aware on azimuth), and NaN-proof — a bad rPPG frame may
// never teleport or vanish the spatial object.

import XCTest
@testable import Echoelmusic

final class BioSpaceMapTests: XCTestCase {

    private func frame(breath: Float = 0.5, hrv: Float = 0.5,
                       coherence: Float = 0.5, motion: Float = 0) -> BioSampleFrame {
        BioSampleFrame(timestamp: 1, heartRateBPM: 60, hrvNormalized: hrv,
                       breathRate: 6, breathPhase: breath, coherence: coherence,
                       motionEnergy: motion, source: .fallback)
    }

    // MARK: - Preset formulas

    func testBreathOrbitSweepsFullCircle() {
        let inhaleStart = BioSpaceMap.target(for: frame(breath: 0), preset: .breathOrbit)
        let mid = BioSpaceMap.target(for: frame(breath: 0.5), preset: .breathOrbit)
        let exhaleEnd = BioSpaceMap.target(for: frame(breath: 1), preset: .breathOrbit)
        XCTAssertEqual(inhaleStart.azimuth, -180)
        XCTAssertEqual(mid.azimuth, 0)
        XCTAssertEqual(exhaleEnd.azimuth, 180)
    }

    func testCoherenceRiseLiftsAndApproaches() {
        let scattered = BioSpaceMap.target(for: frame(coherence: 0), preset: .coherenceRise)
        let coherent = BioSpaceMap.target(for: frame(coherence: 1), preset: .coherenceRise)
        XCTAssertLessThan(scattered.elevation, coherent.elevation)
        XCTAssertGreaterThan(scattered.distance, coherent.distance)
        XCTAssertEqual(coherent.elevation, 80, accuracy: 1e-4)
        XCTAssertEqual(coherent.distance, 0, accuracy: 1e-4)
    }

    func testCalmCenterStaysFrontAndCalmPullsClose() {
        let tense = BioSpaceMap.target(for: frame(hrv: 0), preset: .calmCenter)
        let calm = BioSpaceMap.target(for: frame(hrv: 1), preset: .calmCenter)
        XCTAssertEqual(tense.azimuth, 0)
        XCTAssertEqual(calm.azimuth, 0)
        XCTAssertGreaterThan(tense.distance, calm.distance)
    }

    func testPresetsAreDistinctForTheSameBody() {
        let f = frame(breath: 0.25, hrv: 0.7, coherence: 0.8, motion: 0.3)
        let targets = BioSpacePreset.allCases.map { BioSpaceMap.target(for: f, preset: $0) }
        // Pairwise distinct — switching presets must be a different choreography.
        XCTAssertNotEqual(targets[0], targets[1])
        XCTAssertNotEqual(targets[1], targets[2])
        XCTAssertNotEqual(targets[0], targets[2])
    }

    func testGarbageFrameFieldsFallBackSafely() {
        let bad = BioSampleFrame(timestamp: 1, heartRateBPM: .nan, hrvNormalized: .infinity,
                                 breathRate: 6, breathPhase: .nan, coherence: -3,
                                 motionEnergy: 9, source: .fallback)
        for preset in BioSpacePreset.allCases {
            let t = BioSpaceMap.target(for: bad, preset: preset)
            XCTAssertTrue(t.azimuth.isFinite && t.elevation.isFinite
                          && t.distance.isFinite && t.gain.isFinite)
            XCTAssertTrue((-180...180).contains(t.azimuth))
            XCTAssertTrue((0...1).contains(t.distance))
            XCTAssertTrue((0...1).contains(t.gain))
        }
    }

    // MARK: - Slew limiting

    func testFirstFrameJumpsThenSlewLimits() {
        var map = BioSpaceMap(preset: .breathOrbit, maxDegreesPerSecond: 90)
        // First frame: direct jump (no origin to slew from).
        let first = map.step(frame: frame(breath: 0.5), dt: 0.1)   // azimuth 0
        XCTAssertEqual(first.azimuth, 0)
        // Target leaps to +90 (breath 0.75) — one 100 ms tick allows only 9°.
        let second = map.step(frame: frame(breath: 0.75), dt: 0.1)
        XCTAssertEqual(second.azimuth, 9, accuracy: 1e-3)
    }

    func testAzimuthSlewTakesShortestPathAcrossSeam() {
        // From +170° toward −170°: shortest path is 20° THROUGH the seam,
        // not 340° back through the front.
        let next = BioSpaceMap.slewAngleWrapped(from: 170, to: -170, maxStep: 8)
        XCTAssertEqual(next, 178, accuracy: 1e-4)
        // Crossing the seam wraps the value into range.
        let wrapped = BioSpaceMap.slewAngleWrapped(from: 178, to: -170, maxStep: 8)
        XCTAssertEqual(wrapped, -174, accuracy: 1e-4)
        // Within reach → lands exactly.
        XCTAssertEqual(BioSpaceMap.slewAngleWrapped(from: -174, to: -170, maxStep: 8),
                       -170, accuracy: 1e-4)
    }

    func testLinearSlewClampsPerTick() {
        XCTAssertEqual(BioSpaceMap.slewLinear(from: 0, to: 1, maxStep: 0.25), 0.25)
        XCTAssertEqual(BioSpaceMap.slewLinear(from: 1, to: 0, maxStep: 0.25), 0.75)
        XCTAssertEqual(BioSpaceMap.slewLinear(from: 0.9, to: 1, maxStep: 0.25), 1)
    }

    func testNilFrameHoldsPosition() {
        var map = BioSpaceMap(preset: .coherenceRise)
        let placed = map.step(frame: frame(coherence: 0.9), dt: 0.1)
        let held = map.step(frame: nil, dt: 0.1)
        XCTAssertEqual(held, placed, "no bio = the object stays where the body left it")
    }

    func testGarbageDtIsSafe() {
        var map = BioSpaceMap(preset: .breathOrbit)
        _ = map.step(frame: frame(breath: 0.5), dt: .nan)
        let t = map.step(frame: frame(breath: 1), dt: -5)
        XCTAssertTrue(t.azimuth.isFinite)
    }

    func testResetForgetsSlewState() {
        var map = BioSpaceMap(preset: .breathOrbit)
        _ = map.step(frame: frame(breath: 0), dt: 0.1)     // at -180
        map.reset()
        let t = map.step(frame: frame(breath: 1), dt: 0.001)
        XCTAssertEqual(t.azimuth, 180, "after reset the first frame jumps again")
    }
}
