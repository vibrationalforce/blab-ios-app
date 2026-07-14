// FloatingPointClampTests.swift
// Pure, Linux-CI coverage for the NaN-safe FloatingPoint.clamped(to:). This guards
// the bio → audio path: a NaN bio value must never survive a clamp and reach a
// synth parameter (where it would poison filter/oscillator state and silence the
// voice). Foundation-only — runs on Linux, not just the iOS build.

import XCTest
@testable import Echoelmusic

final class FloatingPointClampTests: XCTestCase {

    func testClamp_ordinaryValues_behaveLikeMinMax() {
        XCTAssertEqual((0.5 as Float).clamped(to: 0...1), 0.5)
        XCTAssertEqual((-3.0 as Float).clamped(to: 0...1), 0.0)   // below → lower
        XCTAssertEqual((9.0 as Float).clamped(to: 0...1), 1.0)    // above → upper
        XCTAssertEqual((0.0 as Float).clamped(to: 0...1), 0.0)    // on the bound
        XCTAssertEqual((1.0 as Float).clamped(to: 0...1), 1.0)
    }

    func testClamp_nan_mapsToLowerBound_notNaN() {
        // The whole point: NaN must NOT pass through (min/max let it).
        XCTAssertFalse(Float.nan.clamped(to: 0...1).isNaN)
        XCTAssertEqual(Float.nan.clamped(to: 0...1), 0.0)
        // A non-zero lower bound (e.g. a frequency floor) is honored.
        XCTAssertEqual(Float.nan.clamped(to: 20...20_000), 20)
        // Double too.
        XCTAssertEqual(Double.nan.clamped(to: -1.0 ... 1.0), -1.0)
    }

    func testClamp_infinities_stayFiniteInRange() {
        XCTAssertEqual(Float.infinity.clamped(to: 0...1), 1.0)
        XCTAssertEqual((-Float.infinity).clamped(to: 0...1), 0.0)
    }

    func testClamp_bipolarRange_nanGivesFiniteLowerBound() {
        // Bipolar params (pan, pitch mod): NaN → lowerBound is extreme but finite,
        // which is the safety guarantee (no NaN downstream), the exact goal here.
        let r: ClosedRange<Float> = -1...1
        XCTAssertTrue(Float.nan.clamped(to: r).isFinite)
        XCTAssertEqual(Float.nan.clamped(to: r), -1)
    }
}
