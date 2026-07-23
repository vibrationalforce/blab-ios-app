// BinauralPannerTests.swift
// Echoel — the binaural placement cue model (ILD/ITD/distance), pure + deterministic.

import XCTest
@testable import Echoelmusic

final class BinauralPannerTests: XCTestCase {

    func testCenter_balancedEqualPowerNoITD() {
        let c = BinauralPanner.cues(azimuthDegrees: 0, elevationDegrees: 0, distanceNorm: 0)
        XCTAssertEqual(c.leftGain, c.rightGain, accuracy: 1e-5, "front-centre is balanced")
        XCTAssertEqual(c.itdSeconds, 0, accuracy: 1e-6, "no ITD straight ahead")
        // Equal-power centre pan → both ears ≈ cos(45°) ≈ 0.707.
        XCTAssertEqual(c.leftGain, 0.7071, accuracy: 1e-3)
    }

    func testHardLeft_louderAndLeadsAtLeftEar() {
        // House/ADM convention: positive azimuth = LEFT. +90° is a hard-left source →
        // louder in the left ear, and the left ear leads (positive ITD per the struct).
        let c = BinauralPanner.cues(azimuthDegrees: 90, elevationDegrees: 0, distanceNorm: 0)
        XCTAssertGreaterThan(c.leftGain, c.rightGain, "source on the left is louder at the left ear")
        XCTAssertGreaterThan(c.itdSeconds, 0, "positive ITD = left ear leads (right ear delayed)")
        // Max ITD for the spherical-head model stays sub-millisecond and plausible.
        XCTAssertLessThan(c.itdSeconds, 0.001, "ITD is sub-millisecond")
        XCTAssertGreaterThan(c.itdSeconds, 0.0004, "near the ~0.66 ms max at 90°")
    }

    func testHardRight_louderAndLeadsAtRightEar() {
        // Negative azimuth = RIGHT → louder right ear, right ear leads (negative ITD).
        let c = BinauralPanner.cues(azimuthDegrees: -90, elevationDegrees: 0, distanceNorm: 0)
        XCTAssertGreaterThan(c.rightGain, c.leftGain, "source on the right is louder at the right ear")
        XCTAssertLessThan(c.itdSeconds, 0, "negative ITD = right ear leads (left ear delayed)")
    }

    func testHardRight_isMirrorOfHardLeft() {
        let left  = BinauralPanner.cues(azimuthDegrees: 90, elevationDegrees: 0, distanceNorm: 0)
        let right = BinauralPanner.cues(azimuthDegrees: -90, elevationDegrees: 0, distanceNorm: 0)
        XCTAssertEqual(right.leftGain, left.rightGain, accuracy: 1e-5, "left/right symmetry of gains")
        XCTAssertEqual(right.rightGain, left.leftGain, accuracy: 1e-5)
        XCTAssertEqual(right.itdSeconds, -left.itdSeconds, accuracy: 1e-7, "ITD sign mirrors")
    }

    func testOverhead_recentersTheImage() {
        let side = BinauralPanner.cues(azimuthDegrees: 90, elevationDegrees: 0, distanceNorm: 0)
        let over = BinauralPanner.cues(azimuthDegrees: 90, elevationDegrees: 90, distanceNorm: 0)
        let sideImbalance = abs(side.leftGain - side.rightGain)
        let overImbalance = abs(over.leftGain - over.rightGain)
        XCTAssertLessThan(overImbalance, sideImbalance, "overhead source is more centred")
        XCTAssertEqual(over.itdSeconds, 0, accuracy: 1e-6, "directly overhead → no lateral ITD")
    }

    func testDistance_attenuatesAndDampsHighs() {
        let near = BinauralPanner.cues(azimuthDegrees: 0, elevationDegrees: 0, distanceNorm: 0)
        let far  = BinauralPanner.cues(azimuthDegrees: 0, elevationDegrees: 0, distanceNorm: 1)
        XCTAssertLessThan(far.leftGain, near.leftGain, "far source is quieter")
        XCTAssertLessThan(far.airHighCutHz, near.airHighCutHz, "far source loses highs (air damping)")
        XCTAssertGreaterThan(far.airHighCutHz, 1000, "still musical, not fully muffled")
        XCTAssertGreaterThan(near.airHighCutHz, 15000, "close source keeps full bandwidth")
    }

    func testFiniteAndClampedOutOfRange() {
        let c = BinauralPanner.cues(azimuthDegrees: 999, elevationDegrees: -999, distanceNorm: 9)
        XCTAssertTrue(c.leftGain.isFinite && c.rightGain.isFinite)
        XCTAssertTrue(c.itdSeconds.isFinite && c.airHighCutHz.isFinite)
        XCTAssertLessThanOrEqual(c.leftGain, 1)
        XCTAssertGreaterThanOrEqual(c.leftGain, 0)
    }

    func testBioConvenienceMatchesADMConvention() {
        // High coherence → close (loud), low coherence → far (quiet): same direction
        // as ADMOSCSender's distance = 1 - coherence.
        let coherent = BinauralPanner.cues(breathPhase: 0.5, hrvNormalized: 0.5, coherence: 1)
        let scattered = BinauralPanner.cues(breathPhase: 0.5, hrvNormalized: 0.5, coherence: 0)
        let coherentLevel = coherent.leftGain + coherent.rightGain
        let scatteredLevel = scattered.leftGain + scattered.rightGain
        XCTAssertGreaterThan(coherentLevel, scatteredLevel, "coherence pulls the source close = louder")
    }
}
