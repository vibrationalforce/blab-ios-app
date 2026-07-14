// VBAPPannerTests.swift
// Pure tests for the 2D VBAP gain solver. No engine → every platform (Foundation-only).
// Verifies: on-speaker snap, equal-power midpoint, energy sum-of-squares ≈ 1, the ±180
// wrap bracket, single/empty degenerate rings, and the standalone `normalized` helper.

import XCTest
@testable import Echoelmusic

final class VBAPPannerTests: XCTestCase {

    private let tol = 1e-9
    private let looseTol = 1e-6

    // Ring helper: real speakers at the given azimuths, channels 1…n.
    private func ring(_ azimuths: [Double]) -> [Loudspeaker] {
        azimuths.enumerated().map { idx, az in
            Loudspeaker(azimuth: az, channel: idx + 1)
        }
    }

    private func sumOfSquares(_ gains: [Int: Double]) -> Double {
        gains.values.reduce(0) { $0 + $1 * $1 }
    }

    // MARK: - On-speaker

    func testSourceOnSpeaker_gainOneThereZeroElsewhere() {
        let speakers = ring([90, 0, -90, 180])   // L, front, R, back
        let g = VBAPPanner.gains(sourceAzimuthDeg: 0, speakers: speakers)
        // Channel 2 sits at azimuth 0.
        XCTAssertEqual(g[2] ?? 0, 1.0, accuracy: tol)
        for (ch, v) in g where ch != 2 {
            XCTAssertEqual(v, 0.0, accuracy: tol, "channel \(ch) should be silent")
        }
        XCTAssertEqual(sumOfSquares(g), 1.0, accuracy: tol)
    }

    // MARK: - Equal-power midpoint

    func testSourceMidwayBetweenTwo_equalPower0707() {
        // Two speakers at ±45, source dead centre (0°).
        let speakers = ring([45, -45])
        let g = VBAPPanner.gains(sourceAzimuthDeg: 0, speakers: speakers)
        XCTAssertEqual(g[1] ?? 0, 0.7071067811865476, accuracy: looseTol)
        XCTAssertEqual(g[2] ?? 0, 0.7071067811865476, accuracy: looseTol)
        XCTAssertEqual(sumOfSquares(g), 1.0, accuracy: looseTol)
    }

    func testSourceMidway_offsetPair_stillEqualPower() {
        // Symmetric midpoint of an off-centre pair: 30 and 90 → midpoint 60.
        let speakers = ring([30, 90])
        let g = VBAPPanner.gains(sourceAzimuthDeg: 60, speakers: speakers)
        XCTAssertEqual(g[1] ?? 0, g[2] ?? 0, accuracy: looseTol)
        XCTAssertEqual(sumOfSquares(g), 1.0, accuracy: looseTol)
    }

    // MARK: - Energy conservation over arbitrary angles

    func testEnergySumOfSquares_arbitraryAngles() {
        let speakers = ring([90, 30, -30, -90, 150, -150])  // hexagon-ish ring
        for az in stride(from: -179.0, through: 180.0, by: 7.3) {
            let g = VBAPPanner.gains(sourceAzimuthDeg: az, speakers: speakers)
            XCTAssertEqual(sumOfSquares(g), 1.0, accuracy: looseTol,
                           "energy not conserved at azimuth \(az)")
            for (ch, v) in g {
                XCTAssertGreaterThanOrEqual(v, -tol, "negative gain on channel \(ch) at \(az)")
                XCTAssertLessThanOrEqual(v, 1.0 + looseTol, "gain > 1 on channel \(ch) at \(az)")
            }
            // At most two channels active.
            let active = g.filter { $0.value > looseTol }
            XCTAssertLessThanOrEqual(active.count, 2, "more than two active speakers at \(az)")
        }
    }

    // MARK: - Wrap across ±180

    func testWrapBracket_sourceAt170_between160AndMinus170() {
        // Speaker 1 at 160, speaker 2 at -170 (≡ +190). The gap 160 → 190 (CCW) is 30°;
        // source at 170 sits inside it, so BOTH these speakers should be active, not the
        // ones far around the front.
        let speakers = ring([160, -170, 0, 90, -90])
        let g = VBAPPanner.gains(sourceAzimuthDeg: 170, speakers: speakers)
        XCTAssertGreaterThan(g[1] ?? 0, 0.0, "160° speaker must be active")
        XCTAssertGreaterThan(g[2] ?? 0, 0.0, "-170° speaker must be active")
        // Everyone else silent.
        for ch in [3, 4, 5] {
            XCTAssertEqual(g[ch] ?? 0, 0.0, accuracy: looseTol, "channel \(ch) should be silent")
        }
        XCTAssertEqual(sumOfSquares(g), 1.0, accuracy: looseTol)
    }

    func testWrap_sourceExactlyAtBackBoundary() {
        // Source at 180 with speakers straddling the seam.
        let speakers = ring([160, -160, 0])
        let g = VBAPPanner.gains(sourceAzimuthDeg: 180, speakers: speakers)
        // 160 and -160 (≡200) bracket 180; front (0) silent.
        XCTAssertGreaterThan(g[1] ?? 0, 0.0)
        XCTAssertGreaterThan(g[2] ?? 0, 0.0)
        XCTAssertEqual(g[3] ?? 0, 0.0, accuracy: looseTol)
        XCTAssertEqual(sumOfSquares(g), 1.0, accuracy: looseTol)
        // Symmetric about the seam → equal power.
        XCTAssertEqual(g[1] ?? 0, g[2] ?? 0, accuracy: looseTol)
    }

    func testWrapEquivalentAzimuths_190equals_minus170() {
        let speakers = ring([160, -170, 0])
        let a = VBAPPanner.gains(sourceAzimuthDeg: 170, speakers: speakers)
        let b = VBAPPanner.gains(sourceAzimuthDeg: 170 - 360, speakers: speakers)  // -190 ≡ 170
        XCTAssertEqual(a[1] ?? 0, b[1] ?? 0, accuracy: looseTol)
        XCTAssertEqual(a[2] ?? 0, b[2] ?? 0, accuracy: looseTol)
    }

    // MARK: - Degenerate rings

    func testSingleSpeaker_gainOne() {
        let g = VBAPPanner.gains(sourceAzimuthDeg: 42, speakers: ring([90]))
        XCTAssertEqual(g, [1: 1.0])
    }

    func testEmpty_returnsEmpty() {
        XCTAssertTrue(VBAPPanner.gains(sourceAzimuthDeg: 12, speakers: []).isEmpty)
    }

    func testImaginarySpeakersExcluded() {
        // One real speaker + one imaginary floor → treated as single-speaker ring.
        let speakers = [
            Loudspeaker(azimuth: 30, channel: 1),
            Loudspeaker(azimuth: 0, elevation: -90, isImaginary: true, channel: 99)
        ]
        let g = VBAPPanner.gains(sourceAzimuthDeg: 0, speakers: speakers)
        XCTAssertEqual(g, [1: 1.0])
        XCTAssertNil(g[99], "imaginary speaker must never receive a gain")
    }

    func testCoincidentSpeakers_noCrashNearestWins() {
        // Two speakers at the same azimuth (det≈0) plus a third to complete a ring.
        let speakers = ring([0, 0, 180])
        let g = VBAPPanner.gains(sourceAzimuthDeg: 5, speakers: speakers)
        // Must produce a finite, energy-1 (or on-speaker) result without dividing by zero.
        XCTAssertFalse(g.isEmpty)
        for v in g.values { XCTAssertFalse(v.isNaN); XCTAssertFalse(v.isInfinite) }
    }

    // MARK: - Channel identity

    func testGainsKeyedByLoudspeakerChannel_notIndex() {
        // Channels deliberately not 1…n and out of azimuth order.
        let speakers = [
            Loudspeaker(azimuth: -45, channel: 7),
            Loudspeaker(azimuth: 45, channel: 3)
        ]
        let g = VBAPPanner.gains(sourceAzimuthDeg: 0, speakers: speakers)
        XCTAssertEqual(g[3] ?? 0, 0.7071067811865476, accuracy: looseTol)
        XCTAssertEqual(g[7] ?? 0, 0.7071067811865476, accuracy: looseTol)
    }

    // MARK: - wrapDeg

    func testWrapDeg_intervalIsHalfOpen() {
        XCTAssertEqual(VBAPPanner.wrapDeg(180), 180, accuracy: tol)
        XCTAssertEqual(VBAPPanner.wrapDeg(-180), 180, accuracy: tol)   // -180 maps to +180
        XCTAssertEqual(VBAPPanner.wrapDeg(190), -170, accuracy: tol)
        XCTAssertEqual(VBAPPanner.wrapDeg(-190), 170, accuracy: tol)
        XCTAssertEqual(VBAPPanner.wrapDeg(360), 0, accuracy: tol)
        XCTAssertEqual(VBAPPanner.wrapDeg(720 + 45), 45, accuracy: tol)
        XCTAssertEqual(VBAPPanner.wrapDeg(-45), -45, accuracy: tol)
    }

    // MARK: - normalized helper

    func testNormalized_makesSumOfSquaresOne() {
        let n = VBAPPanner.normalized([1: 3.0, 2: 4.0])   // 3² + 4² = 25 → /5
        XCTAssertEqual(n[1] ?? 0, 0.6, accuracy: tol)
        XCTAssertEqual(n[2] ?? 0, 0.8, accuracy: tol)
        XCTAssertEqual(sumOfSquares(n), 1.0, accuracy: tol)
    }

    func testNormalized_zeroMapUnchanged() {
        XCTAssertEqual(VBAPPanner.normalized([1: 0.0, 2: 0.0]), [1: 0.0, 2: 0.0])
    }

    func testNormalized_emptyMapUnchanged() {
        XCTAssertTrue(VBAPPanner.normalized([:]).isEmpty)
    }

    func testNormalized_preservesRatios() {
        let n = VBAPPanner.normalized([5: 1.0, 6: 1.0])
        XCTAssertEqual(n[5] ?? 0, n[6] ?? 0, accuracy: tol)
        XCTAssertEqual(sumOfSquares(n), 1.0, accuracy: tol)
    }
}
