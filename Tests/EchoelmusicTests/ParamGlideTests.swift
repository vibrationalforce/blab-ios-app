// ParamGlideTests.swift
// The one-pole parameter glide that lets the FX chain stop stepping its parameters
// at control rate (#138). Pure arithmetic → Linux-verifiable, no audio, no device.

import XCTest
@testable import Echoelmusic

final class ParamGlideTests: XCTestCase {

    /// Step for a fixed wall-clock duration at a given rate.
    private func glide(from start: Float, to target: Float,
                       seconds: Float, rateHz: Float, tau: Float) -> Float {
        var g = ParamGlide(start)
        let c = ParamGlide.coefficient(tauSeconds: tau, stepRateHz: rateHz)
        for _ in 0..<Int((seconds * rateHz).rounded()) {
            g.advance(toward: target, coefficient: c)
        }
        return g.value
    }

    func testGlide_isRateBased_blockRateMatchesSampleRate() {
        // The law: slews are rate-based. The intended caller is BLOCK-rate (~188 Hz for
        // a 256-frame buffer at 48 kHz) because gliding the filter per SAMPLE would
        // reintroduce the per-sample `tanf` that stage deliberately removed. So the same
        // glide must land in the same place at either rate, or the sound would depend on
        // the buffer size the host happens to hand us.
        let perBlock  = glide(from: 200, to: 8000, seconds: 0.05, rateHz: 187.5, tau: 0.02)
        let perSample = glide(from: 200, to: 8000, seconds: 0.05, rateHz: 48000, tau: 0.02)
        XCTAssertEqual(perBlock, perSample, accuracy: 30, "8000 Hz span — 30 Hz is 0.4 %")
    }

    func testGlide_settlesExactly_soDownstreamRecomputesStop() {
        // A one-pole never arrives on its own, and a cutoff that never stops changing
        // keeps EchoelSVFilter's didSet recomputing `tanf` every block for the rest of
        // the session. Settling is what ends that.
        var g = ParamGlide(200)
        let c = ParamGlide.coefficient(tauSeconds: 0.02, stepRateHz: 187.5)
        for _ in 0..<200 { g.advance(toward: 8000, coefficient: c) }
        XCTAssertEqual(g.value, 8000, "exactly, not asymptotically close")
    }

    func testGlide_neverOvershoots_inEitherDirection() {
        var up = ParamGlide(0)
        up.advance(toward: 1, coefficient: 1)
        XCTAssertLessThanOrEqual(up.value, 1)
        var down = ParamGlide(1)
        down.advance(toward: 0, coefficient: 1)
        XCTAssertGreaterThanOrEqual(down.value, 0)
    }

    func testGlide_movesTowardTheTargetOnTheFirstStep_notInstantly() {
        // The whole point: one control-rate write must become a ramp, not a step.
        var g = ParamGlide(200)
        let c = ParamGlide.coefficient(tauSeconds: 0.02, stepRateHz: 187.5)
        g.advance(toward: 8000, coefficient: c)
        XCTAssertGreaterThan(g.value, 200, "it moved")
        XCTAssertLessThan(g.value, 3000, "but nowhere near arriving — that is the declick")
    }

    func testCoefficient_degradesToInstantOnNonsenseTiming() {
        // A zero/negative/non-finite tau or rate means "no glide", not a divide-by-zero
        // or a NaN coefficient that would poison a recursive filter downstream.
        for c in [ParamGlide.coefficient(tauSeconds: 0, stepRateHz: 187.5),
                  ParamGlide.coefficient(tauSeconds: -1, stepRateHz: 187.5),
                  ParamGlide.coefficient(tauSeconds: .nan, stepRateHz: 187.5),
                  ParamGlide.coefficient(tauSeconds: 0.02, stepRateHz: 0),
                  ParamGlide.coefficient(tauSeconds: 0.02, stepRateHz: .infinity)] {
            XCTAssertTrue(c.isFinite)
            XCTAssertTrue((0...1).contains(c))
        }
        XCTAssertEqual(ParamGlide.coefficient(tauSeconds: 0, stepRateHz: 187.5), 1)
    }

    func testGlide_nonFiniteTargetIsIgnored_notPropagated() {
        // This value feeds a recursive filter, where a single NaN is permanent. Holding
        // the last good value is the only safe answer.
        var g = ParamGlide(2000)
        g.advance(toward: .nan, coefficient: 0.5)
        XCTAssertEqual(g.value, 2000)
        g.advance(toward: .infinity, coefficient: 0.5)
        XCTAssertEqual(g.value, 2000)
        g.snap(to: .nan)
        XCTAssertEqual(g.value, 2000)
        XCTAssertEqual(ParamGlide(.nan).value, 0, "a non-finite seed cannot start it poisoned either")
    }

    func testSnap_bypassesTheGlideEntirely() {
        var g = ParamGlide(200)
        g.snap(to: 8000)
        XCTAssertEqual(g.value, 8000, "loading a document must not sweep the filter up")
    }

    func testGlide_largeAndSmallRangedParametersBothSettle() {
        // Cutoff lives in Hz up to 18 000; the mixes live in 0…1. A purely absolute
        // epsilon would never be reached in Float at the top of the Hz range, and a
        // purely relative one would never settle at a target of 0.
        var hz = ParamGlide(80)
        var mix = ParamGlide(1)
        let c = ParamGlide.coefficient(tauSeconds: 0.02, stepRateHz: 187.5)
        for _ in 0..<400 {
            hz.advance(toward: 18000, coefficient: c)
            mix.advance(toward: 0, coefficient: c)
        }
        XCTAssertEqual(hz.value, 18000)
        XCTAssertEqual(mix.value, 0)
    }
}
