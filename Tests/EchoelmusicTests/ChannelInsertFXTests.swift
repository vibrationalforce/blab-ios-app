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
