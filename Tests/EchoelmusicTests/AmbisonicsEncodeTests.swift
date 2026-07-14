// AmbisonicsEncodeTests.swift
// Pure tests for the ACN/SN3D Ambisonics encoder. Foundation-only → runs on every platform.
// Verifies: order-0 = [1] regardless of direction, coefficient count = (order+1)², W ≡ 1
// (SN3D), the cardinal-direction sign laws (LEFT → Y>0 & X≈0, FRONT → X>0 & Y≈0,
// UP → Z>0), order clamping, and a hand-computed full order-3 fixture.

import XCTest
@testable import Echoelmusic

final class AmbisonicsEncodeTests: XCTestCase {

    private let tol = 1e-9
    private let looseTol = 1e-6

    // MARK: - Order 0 (W only, constant)

    func testOrderZero_isSingleUnitCoefficient_regardlessOfDirection() {
        // W is direction-independent, so any az/elev must yield exactly [1].
        for az in stride(from: -180.0, through: 180.0, by: 45) {
            for el in stride(from: -90.0, through: 90.0, by: 30) {
                let c = AmbisonicsEncode.coefficients(azimuthDeg: az, elevationDeg: el, order: 0)
                XCTAssertEqual(c, [1.0], "order 0 must be [1] at az=\(az) el=\(el)")
            }
        }
    }

    // MARK: - Coefficient count = (order+1)²

    func testCoefficientCount_isOrderPlusOneSquared() {
        XCTAssertEqual(AmbisonicsEncode.coefficients(azimuthDeg: 33, elevationDeg: 12, order: 0).count, 1)
        XCTAssertEqual(AmbisonicsEncode.coefficients(azimuthDeg: 33, elevationDeg: 12, order: 1).count, 4)
        XCTAssertEqual(AmbisonicsEncode.coefficients(azimuthDeg: 33, elevationDeg: 12, order: 2).count, 9)
        XCTAssertEqual(AmbisonicsEncode.coefficients(azimuthDeg: 33, elevationDeg: 12, order: 3).count, 16)
        // Helper agrees with the array length.
        for o in 0...3 {
            XCTAssertEqual(AmbisonicsEncode.coefficientCount(order: o),
                           AmbisonicsEncode.coefficients(azimuthDeg: 10, elevationDeg: 5, order: o).count)
        }
    }

    // MARK: - Order clamping (0...3)

    func testOrderClamping_belowZeroAndAboveThree() {
        // Negative clamps to 0 → single W.
        XCTAssertEqual(AmbisonicsEncode.coefficients(azimuthDeg: 20, elevationDeg: 0, order: -5), [1.0])
        // Above 3 clamps to 3 → 16 coefficients.
        XCTAssertEqual(AmbisonicsEncode.coefficients(azimuthDeg: 20, elevationDeg: 0, order: 99).count, 16)
        XCTAssertEqual(AmbisonicsEncode.coefficientCount(order: 99), 16)
        XCTAssertEqual(AmbisonicsEncode.coefficientCount(order: -1), 1)
    }

    // MARK: - W ≡ 1.0 (SN3D) for any direction, any order

    func testW_isAlwaysOne_forEveryDirectionAndOrder() {
        for order in 0...3 {
            for az in stride(from: -180.0, through: 180.0, by: 30) {
                for el in stride(from: -90.0, through: 90.0, by: 30) {
                    let c = AmbisonicsEncode.coefficients(azimuthDeg: az, elevationDeg: el, order: order)
                    XCTAssertEqual(c[0], 1.0, accuracy: tol,
                                   "W must be 1.0 (SN3D) at order=\(order) az=\(az) el=\(el)")
                }
            }
        }
    }

    // MARK: - Cardinal direction sign laws (order 1: Y, Z, X)

    func testLeft_azimuthPlus90_givesYPositive_andXNearZero() {
        // Echoel convention: +90 = LEFT. Y = cosθ·sinφ = +1; X = cosθ·cosφ = 0.
        let c = AmbisonicsEncode.coefficients(azimuthDeg: 90, elevationDeg: 0, order: 1)
        XCTAssertGreaterThan(c[1], 0.0, "Y must be > 0 at the left")           // Y (ACN 1)
        XCTAssertEqual(c[1], 1.0, accuracy: looseTol)
        XCTAssertEqual(c[3], 0.0, accuracy: looseTol, "X (front-back) ≈ 0 at the sides")  // X (ACN 3)
        XCTAssertEqual(c[2], 0.0, accuracy: looseTol, "Z ≈ 0 at ear level")               // Z (ACN 2)
    }

    func testRight_azimuthMinus90_givesYNegative() {
        // -90 = RIGHT. Y = sin(-90) = -1.
        let c = AmbisonicsEncode.coefficients(azimuthDeg: -90, elevationDeg: 0, order: 1)
        XCTAssertLessThan(c[1], 0.0, "Y must be < 0 at the right")
        XCTAssertEqual(c[1], -1.0, accuracy: looseTol)
        XCTAssertEqual(c[3], 0.0, accuracy: looseTol)
    }

    func testFront_azimuthZero_givesXPositive_andYNearZero() {
        // FRONT: X = cos0 = +1; Y = sin0 = 0.
        let c = AmbisonicsEncode.coefficients(azimuthDeg: 0, elevationDeg: 0, order: 1)
        XCTAssertGreaterThan(c[3], 0.0, "X must be > 0 at the front")
        XCTAssertEqual(c[3], 1.0, accuracy: looseTol)
        XCTAssertEqual(c[1], 0.0, accuracy: looseTol, "Y (left-right) ≈ 0 at the front")
    }

    func testBack_azimuth180_givesXNegative() {
        let c = AmbisonicsEncode.coefficients(azimuthDeg: 180, elevationDeg: 0, order: 1)
        XCTAssertLessThan(c[3], 0.0, "X must be < 0 at the back")
        XCTAssertEqual(c[3], -1.0, accuracy: looseTol)
        XCTAssertEqual(c[1], 0.0, accuracy: looseTol)
    }

    func testUp_elevationPlus90_givesZPositive_andXYNearZero() {
        // UP: Z = sin90 = +1; horizontal projection cosθ = 0 → X,Y ≈ 0.
        let c = AmbisonicsEncode.coefficients(azimuthDeg: 0, elevationDeg: 90, order: 1)
        XCTAssertGreaterThan(c[2], 0.0, "Z must be > 0 overhead")
        XCTAssertEqual(c[2], 1.0, accuracy: looseTol)
        XCTAssertEqual(c[1], 0.0, accuracy: looseTol, "Y ≈ 0 overhead")
        XCTAssertEqual(c[3], 0.0, accuracy: looseTol, "X ≈ 0 overhead")
    }

    func testDown_elevationMinus90_givesZNegative() {
        let c = AmbisonicsEncode.coefficients(azimuthDeg: 0, elevationDeg: -90, order: 1)
        XCTAssertLessThan(c[2], 0.0, "Z must be < 0 below")
        XCTAssertEqual(c[2], -1.0, accuracy: looseTol)
    }

    // MARK: - Second-order hand fixtures

    func testOrderTwo_frontEarLevel_matchesHandComputed() {
        // az=0, el=0 → cₑ=1, sₑ=0, cos0=1, sin0=0, sin2φ=0, cos2φ=1.
        // ACN4 = (√3/2)·1·0 = 0; ACN5 = √3·0·1·0 = 0; ACN6 = (0-1)/2 = -0.5;
        // ACN7 = √3·0·1·1 = 0; ACN8 = (√3/2)·1·1 = √3/2.
        let c = AmbisonicsEncode.coefficients(azimuthDeg: 0, elevationDeg: 0, order: 2)
        XCTAssertEqual(c[4], 0.0, accuracy: looseTol)
        XCTAssertEqual(c[5], 0.0, accuracy: looseTol)
        XCTAssertEqual(c[6], -0.5, accuracy: looseTol)
        XCTAssertEqual(c[7], 0.0, accuracy: looseTol)
        XCTAssertEqual(c[8], 3.0.squareRoot() / 2, accuracy: looseTol)
    }

    func testOrderTwo_overhead_ZZmaxesOut() {
        // el=90 → sₑ=1, cₑ=0. ACN6 = (3·1 - 1)/2 = 1.0; all cₑ-bearing order-2 terms = 0.
        let c = AmbisonicsEncode.coefficients(azimuthDeg: 40, elevationDeg: 90, order: 2)
        XCTAssertEqual(c[6], 1.0, accuracy: looseTol, "l2m0 = 1.0 straight up")
        XCTAssertEqual(c[4], 0.0, accuracy: looseTol)
        XCTAssertEqual(c[5], 0.0, accuracy: looseTol)
        XCTAssertEqual(c[7], 0.0, accuracy: looseTol)
        XCTAssertEqual(c[8], 0.0, accuracy: looseTol)
    }

    // MARK: - Third-order full hand fixture (LEFT, ear level)

    func testOrderThree_left_matchesHandComputed() {
        // az=90, el=0 → cₑ=1, sₑ=0.
        // sin90=1, cos90=0, sin180=0, cos180=-1, sin270=-1, cos270=0.
        let c = AmbisonicsEncode.coefficients(azimuthDeg: 90, elevationDeg: 0, order: 3)
        // Order 0/1
        XCTAssertEqual(c[0], 1.0, accuracy: tol)                       // W
        XCTAssertEqual(c[1], 1.0, accuracy: looseTol)                  // Y = 1·sin90
        XCTAssertEqual(c[2], 0.0, accuracy: looseTol)                  // Z = 0
        XCTAssertEqual(c[3], 0.0, accuracy: looseTol)                  // X = 1·cos90
        // Order 2: sₑ=0 kills 5,6(part),7 ; ACN6=(0-1)/2=-0.5; ACN4=(√3/2)·sin180=0; ACN8=(√3/2)·cos180=-√3/2
        XCTAssertEqual(c[4], 0.0, accuracy: looseTol)
        XCTAssertEqual(c[5], 0.0, accuracy: looseTol)
        XCTAssertEqual(c[6], -0.5, accuracy: looseTol)
        XCTAssertEqual(c[7], 0.0, accuracy: looseTol)
        XCTAssertEqual(c[8], -(3.0.squareRoot() / 2), accuracy: looseTol)
        // Order 3: cₑ=1, sₑ=0.
        // ACN9  = √(5/8)·1·sin270 = -√(5/8)
        // ACN10 = √(15/4)·0·... = 0
        // ACN11 = √(3/8)·(0-1)·1·sin90 = -√(3/8)
        // ACN12 = (0-0)/2 = 0
        // ACN13 = √(3/8)·(0-1)·1·cos90 = 0
        // ACN14 = √(15/4)·0·... = 0
        // ACN15 = √(5/8)·1·cos270 = 0
        XCTAssertEqual(c[9], -(5.0 / 8.0).squareRoot(), accuracy: looseTol)
        XCTAssertEqual(c[10], 0.0, accuracy: looseTol)
        XCTAssertEqual(c[11], -(3.0 / 8.0).squareRoot(), accuracy: looseTol)
        XCTAssertEqual(c[12], 0.0, accuracy: looseTol)
        XCTAssertEqual(c[13], 0.0, accuracy: looseTol)
        XCTAssertEqual(c[14], 0.0, accuracy: looseTol)
        XCTAssertEqual(c[15], 0.0, accuracy: looseTol)
    }

    // MARK: - Lower orders are a prefix of higher orders (same direction)

    func testLowerOrder_isPrefixOfHigherOrder() {
        let az = 37.0, el = 21.0
        let o1 = AmbisonicsEncode.coefficients(azimuthDeg: az, elevationDeg: el, order: 1)
        let o3 = AmbisonicsEncode.coefficients(azimuthDeg: az, elevationDeg: el, order: 3)
        for i in 0..<o1.count {
            XCTAssertEqual(o1[i], o3[i], accuracy: tol,
                           "ACN \(i) must be identical across orders (nesting)")
        }
    }

    // MARK: - Energy / boundedness sanity

    func testEncodedGains_areFinite_andWithinUnitMagnitude() {
        // Every SN3D real SH is bounded by 1 in magnitude, so every coefficient ∈ [-1, 1].
        for az in stride(from: -180.0, through: 180.0, by: 15) {
            for el in stride(from: -90.0, through: 90.0, by: 15) {
                let c = AmbisonicsEncode.coefficients(azimuthDeg: az, elevationDeg: el, order: 3)
                for (i, v) in c.enumerated() {
                    XCTAssertTrue(v.isFinite, "coeff \(i) finite at az=\(az) el=\(el)")
                    XCTAssertLessThanOrEqual(abs(v), 1.0 + looseTol,
                                             "coeff \(i)=\(v) exceeds SN3D unit bound at az=\(az) el=\(el)")
                }
            }
        }
    }
}
