// PulsePeriodEstimatorTests.swift
// Echoel — the autocorrelation pulse estimator must recover the correct BPM from
// a rounded/periodic signal where discrete peak-counting fails, at the real rPPG
// sample rate, and must refuse flat or random input (no false lock onto noise).

import XCTest
@testable import Echoelmusic

final class PulsePeriodEstimatorTests: XCTestCase {

    /// Build `seconds` of a sine at `hz` sampled at `rate`, with optional noise.
    private func sine(hz: Double, rate: Double, seconds: Double, noise: Float = 0) -> [Float] {
        let n = Int(rate * seconds)
        var out = [Float](); out.reserveCapacity(n)
        var rng = SystemRandomNumberGenerator()
        for i in 0..<n {
            let t = Double(i) / rate
            var v = Float(sin(2 * Double.pi * hz * t))
            if noise > 0 { v += Float.random(in: -noise...noise, using: &rng) }
            out.append(v)
        }
        return out
    }

    func test60BPM_atRPPGRate() {
        // 1.0 Hz = 60 BPM at the analyzer's 15 Hz rate.
        let s = sine(hz: 1.0, rate: 15, seconds: 10)
        let r = PulsePeriodEstimator.dominantBPM(s, sampleRate: 15)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.bpm, 60, accuracy: 3)
        XCTAssertGreaterThan(r!.strength, 0.5, "a clean sine is strongly periodic")
    }

    func test90BPM_withNoise() {
        // 1.5 Hz = 90 BPM, with noise — autocorrelation should still find it.
        let s = sine(hz: 1.5, rate: 15, seconds: 12, noise: 0.4)
        let r = PulsePeriodEstimator.dominantBPM(s, sampleRate: 15)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.bpm, 90, accuracy: 5)
    }

    func test50BPM_higherRate() {
        let s = sine(hz: 50.0 / 60.0, rate: 30, seconds: 10) // 50 BPM at 30 Hz
        let r = PulsePeriodEstimator.dominantBPM(s, sampleRate: 30)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.bpm, 50, accuracy: 3)
    }

    func testFlatSignal_returnsNil() {
        XCTAssertNil(PulsePeriodEstimator.dominantBPM([Float](repeating: 0.5, count: 150), sampleRate: 15))
    }

    func testTooShort_returnsNil() {
        XCTAssertNil(PulsePeriodEstimator.dominantBPM([0, 1, 0, -1, 0], sampleRate: 15))
    }

    func testRandomNoise_lowStrength() {
        var rng = SystemRandomNumberGenerator()
        let s = (0..<150).map { _ in Float.random(in: -1...1, using: &rng) }
        if let r = PulsePeriodEstimator.dominantBPM(s, sampleRate: 15) {
            XCTAssertLessThan(r.strength, 0.6, "white noise must not look strongly periodic")
        }
    }

    func testOutOfBandFrequency_excluded() {
        // 5 Hz = 300 BPM, above the 200 BPM ceiling → must not report it as the rate.
        let s = sine(hz: 5.0, rate: 30, seconds: 8)
        if let r = PulsePeriodEstimator.dominantBPM(s, sampleRate: 30) {
            XCTAssertLessThanOrEqual(r.bpm, 200)
            XCTAssertGreaterThanOrEqual(r.bpm, 40)
        }
    }
}
