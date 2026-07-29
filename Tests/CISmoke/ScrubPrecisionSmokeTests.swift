// ScrubPrecisionSmokeTests.swift
// Echoel — the one parameter control stays usable at both ends (founder 2026-07-29
// "besser funktionieren"), in the BLOCKING bundle.
//
// WHY THIS EARNS A GATE. `EchoelValueField` is the ONE control for every numeric parameter
// in the app — synth, FX, mix, bio, mood. A regression in how its drag travels is not one
// screen behaving oddly; it is every screen at once, and it is the kind of thing that reads
// as "the app feels wrong" long before anyone can name it. The thresholds below are the
// entire design surface, so they are pinned here rather than left to be re-tuned by feel.
//
// The failure this file exists to prevent is specific: a scale of 0 at any input. That would
// make a slow finger move nothing at all, which reads as a dead control — the exact opposite
// of the ask that produced this code.

import XCTest
@testable import Echoelmusic

final class ScrubPrecisionSmokeTests: XCTestCase {

    /// A fast sweep must cost nothing. This is the behaviour that existed before precision
    /// was added, and it has to survive unchanged, or the fix trades one complaint for
    /// another.
    func testAFastDragKeepsFullTravel() {
        XCTAssertEqual(ScrubPrecision.scale(speedPointsPerSecond: ScrubPrecision.fullSpeed), 1,
                       accuracy: 1e-9)
        XCTAssertEqual(ScrubPrecision.scale(speedPointsPerSecond: 5_000), 1, accuracy: 1e-9)
    }

    /// A slow finger buys precision — but never silence.
    func testASlowDragIsFineButNeverDead() {
        XCTAssertEqual(ScrubPrecision.scale(speedPointsPerSecond: 0),
                       ScrubPrecision.fineScale, accuracy: 1e-9)
        XCTAssertEqual(ScrubPrecision.scale(speedPointsPerSecond: ScrubPrecision.fineSpeed),
                       ScrubPrecision.fineScale, accuracy: 1e-9)
        XCTAssertGreaterThan(ScrubPrecision.fineScale, 0,
                             "a zero-travel control reads as broken, not as precise")
    }

    /// THE ONE THAT CANNOT BE CHECKED BY EYE: the response must be monotonic and bounded
    /// across the whole domain. A dip or a spike anywhere in the blend would feel like the
    /// control sticking, and no single-point assertion would find it.
    func testTheResponseRisesSmoothlyAndStaysInRangeEverywhere() {
        var previous = ScrubPrecision.scale(speedPointsPerSecond: 0)
        for step in 0...400 {
            let speed = Double(step) * 5          // 0 … 2000 pt/s
            let scale = ScrubPrecision.scale(speedPointsPerSecond: speed)
            XCTAssertTrue(scale.isFinite, "speed \(speed) produced a non-finite travel scale")
            XCTAssertGreaterThanOrEqual(scale, ScrubPrecision.fineScale, "speed \(speed)")
            XCTAssertLessThanOrEqual(scale, 1, "speed \(speed) would overshoot the range")
            XCTAssertGreaterThanOrEqual(scale, previous - 1e-12,
                                        "speed \(speed) travels LESS than a slower finger")
            previous = scale
        }
    }

    /// An unusable measurement means "no opinion", not "go slow". Speed comes from dividing
    /// by the gesture's time delta, and two events stamped in the same instant divide by
    /// zero — a timing artefact of the event stream, not something the user did. Slowing the
    /// control down for it would be punishing the wrong party.
    func testAnUnusableSpeedMeasurementFallsBackToFullTravel() {
        XCTAssertEqual(ScrubPrecision.scale(speedPointsPerSecond: .infinity), 1, accuracy: 1e-9)
        XCTAssertEqual(ScrubPrecision.scale(speedPointsPerSecond: .nan), 1, accuracy: 1e-9)
    }

    /// Speed reaches the function as a magnitude, but the guard order decides what a negative
    /// value would do, and "silently full travel" would be a surprise. Pinned so the answer
    /// is a decision rather than an accident of how the branches happen to be written.
    func testANegativeSpeedIsTreatedAsSlowNotAsFast() {
        XCTAssertEqual(ScrubPrecision.scale(speedPointsPerSecond: -500),
                       ScrubPrecision.fineScale, accuracy: 1e-9)
    }

    /// The thresholds must stay ordered, or the blend divides by zero or inverts.
    func testTheThresholdsAreOrdered() {
        XCTAssertLessThan(ScrubPrecision.fineSpeed, ScrubPrecision.fullSpeed)
        XCTAssertLessThan(ScrubPrecision.fineScale, 1)
    }
}
