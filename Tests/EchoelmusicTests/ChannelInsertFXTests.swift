// ChannelInsertFXTests.swift
// Echoelmusic — per-channel insert effect (biquad + drive) DSP core.

import XCTest
@testable import Echoelmusic

final class ChannelInsertFXTests: XCTestCase {

    private func rms(_ xs: [Float]) -> Float {
        guard !xs.isEmpty else { return 0 }
        let s = xs.reduce(0) { $0 + $1 * $1 }
        return (s / Float(xs.count)).squareRoot()
    }

    /// A short sine at `hz` through the fx; returns output RMS.
    private func runSine(_ fx0: ChannelInsertFX, hz: Float, sr: Float = 48_000, n: Int = 4096) -> Float {
        var fx = fx0
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let x = sinf(2 * .pi * hz * Float(i) / sr)
            out[i] = fx.process(x)
        }
        // Skip the filter warm-up.
        return rms(Array(out[(n/2)...]))
    }

    func testOff_isUnityPassthrough() {
        var fx = ChannelInsertFX(type: .off)
        for v: Float in [-0.9, -0.3, 0, 0.25, 0.7, 1.0] {
            XCTAssertEqual(fx.process(v), v, accuracy: 1e-6, "off = clean passthrough")
        }
    }

    func testANonFiniteInputCannotLatchTheFilterIntoPermanentSilence() {
        // A biquad is a recursive accumulator, so one bad sample stays in the state
        // forever unless it is cleared. The old denormal test could not clear it:
        // every comparison against NaN is false, and ±inf fails both bounds. This
        // is the permanent-silence class this repo has shipped twice. (⛔ It used to bite
        // hardest on `DrumSynthVoice`, which never called reset() and had no idle
        // detector; that voice was deleted with #167, founder 2026-07-27. The remaining
        // owners `PolySynthVoice`/`SubBassVoice` reset only on an off→on FX transition,
        // so a latched filter still survives everything short of toggling the effect.)
        for poison: Float in [.nan, .infinity, -.infinity] {
            var fx = ChannelInsertFX(type: .lowPass, cutoffHz: 800, resonance: 0.707, drive: 0)
            // Warm up on real audio, then poison it.
            for i in 0..<64 { _ = fx.process(sinf(Float(i) * 0.1)) }
            let poisoned = fx.process(poison)
            XCTAssertEqual(poisoned, 0, "a non-finite input must leave silence, not \(poisoned)")

            // It must then come back on its own — the whole point.
            var out = [Float](repeating: 0, count: 4096)
            for i in 0..<out.count { out[i] = fx.process(sinf(2 * .pi * 100 * Float(i) / 48_000)) }
            for v in out { XCTAssertTrue(v.isFinite, "state stayed poisoned after \(poison)") }
            XCTAssertGreaterThan(rms(Array(out[2048...])), 0.3,
                                 "filter never recovered after \(poison) — still silent")
        }
    }

    func testTheInputHistoryIsClearedToo_notJustTheOutputState() {
        // Zeroing only y1/y2 would leave the poison in x1/x2 and re-infect the next
        // two samples through the feed-forward path (`b1*x1 + b2*x2`).
        //
        // Asserting `isFinite` here does NOT catch that, which is the trap: under a
        // y-only fix, sample n+1 computes b1·NaN, re-enters the fault branch, and
        // comes out as 0 — finite, and silently wrong. So this asserts the VALUE.
        //
        // A correctly healed filter is state-identical to a fresh one, so a virgin
        // instance is the exact expectation. Under a y-only fix the first two
        // samples would be 0.0, 0.0 instead of the real impulse response, and this
        // fails.
        var fx = ChannelInsertFX(type: .lowPass, cutoffHz: 800, resonance: 0.707, drive: 0)
        for i in 0..<64 { _ = fx.process(sinf(Float(i) * 0.1)) }
        _ = fx.process(.nan)
        let next = (0..<3).map { _ in fx.process(0.5) }

        var fresh = ChannelInsertFX(type: .lowPass, cutoffHz: 800, resonance: 0.707, drive: 0)
        let expected = (0..<3).map { _ in fresh.process(0.5) }

        XCTAssertEqual(next, expected,
                       "the filter must resume from a fully cleared state, not replay "
                       + "zeroed samples out of a poisoned input history")
        XCTAssertGreaterThan(expected[0], 0, "fixture check: a fresh filter's first sample is non-zero")
    }

    func testLowPass_attenuatesHighsMoreThanLows() {
        let fx = ChannelInsertFX(type: .lowPass, cutoffHz: 500, resonance: 0.707, drive: 0)
        let low = runSine(fx, hz: 100)
        let high = runSine(fx, hz: 6000)
        XCTAssertGreaterThan(low, high * 3, "a 500 Hz LP must pass 100 Hz far more than 6 kHz")
        XCTAssertGreaterThan(low, 0.3, "passband roughly preserved")
    }

    func testHighPass_attenuatesLowsMoreThanHighs() {
        let fx = ChannelInsertFX(type: .highPass, cutoffHz: 2000, resonance: 0.707, drive: 0)
        let low = runSine(fx, hz: 100)
        let high = runSine(fx, hz: 8000)
        XCTAssertGreaterThan(high, low * 3, "a 2 kHz HP must pass 8 kHz far more than 100 Hz")
    }

    func testStability_boundedOutputOnLoudInput() {
        var fx = ChannelInsertFX(type: .lowPass, cutoffHz: 800, resonance: 8, drive: 0)
        var maxAbs: Float = 0
        for i in 0..<8000 {
            let x: Float = (i % 2 == 0) ? 1 : -1   // worst-case alternating
            let y = fx.process(x)
            XCTAssertTrue(y.isFinite, "filter must never produce NaN/Inf")
            maxAbs = Swift.max(maxAbs, abs(y))
        }
        XCTAssertLessThan(maxAbs, 50, "high-Q biquad stays bounded")
    }

    func testDrive_addsSaturationButStaysBounded() {
        var fx = ChannelInsertFX(type: .off, drive: 1)
        // A hot input should be soft-clipped toward ±1 by the tanh saturator.
        let y = fx.process(5.0)
        // tanhf saturates: a very hot input reaches ±1 exactly in Float32
        // (tanhf(25) rounds to 1.0f), so the bound is inclusive.
        XCTAssertLessThanOrEqual(abs(y), 1.0, "drive soft-clips a hot sample")
        XCTAssertGreaterThan(y, 0.5, "still passes most of the level")
    }

    func testReset_clearsState() {
        var fx = ChannelInsertFX(type: .lowPass, cutoffHz: 300, resonance: 4, drive: 0)
        for _ in 0..<100 { _ = fx.process(1.0) }
        fx.reset()
        // After reset, the first output of a zero input must be exactly 0 (no tail).
        XCTAssertEqual(fx.process(0), 0, accuracy: 1e-7)
    }

    func testSampleRateChangeRecomputes() {
        var fx = ChannelInsertFX(type: .lowPass, cutoffHz: 1000)
        fx.setSampleRate(44_100)
        XCTAssertEqual(fx.sampleRate, 44_100)
        // Still stable + finite at the new rate.
        for _ in 0..<1000 { XCTAssertTrue(fx.process(0.5).isFinite) }
    }
}
