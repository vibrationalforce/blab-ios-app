// HRVCoherenceTests.swift
// Echoelmusic — frequency-domain HRV (the real coherence metric).
//
// The "calibration sine" tests are the proof of physical correctness: feed an
// RR tachogram that oscillates at a KNOWN frequency and assert the spectral
// peak lands in the right band — exactly like a test tone through a measurement
// chain. If these pass, the band math is trustworthy regardless of method.

import XCTest
@testable import Echoelmusic

final class HRVCoherenceTests: XCTestCase {

    /// Build an RR tachogram (ms) whose interval length oscillates at `freqHz`
    /// around `baseMs`, sampled at each beat's completion time, for `seconds`.
    private func sineTachogram(freqHz: Double, baseMs: Double = 850,
                               ampMs: Double = 60, seconds: Double = 90) -> [Double] {
        var rr = [Double]()
        var clock = 0.0
        while clock < seconds {
            let v = baseMs + ampMs * sin(2.0 * Double.pi * freqHz * clock)
            rr.append(v)
            clock += v / 1000.0
        }
        return rr
    }

    // MARK: Calibration — 0.1 Hz (resonance / LF) must peak in LF.

    func testCalibration_lombScargle_point1Hz_peaksInLF() {
        let rr = sineTachogram(freqHz: 0.1)
        let r = HRVCoherence.compute(rrMs: rr, method: .lombScargle)
        XCTAssertTrue(r.valid)
        XCTAssertEqual(Double(r.peakFrequencyHz), 0.1, accuracy: 0.02)
        XCTAssertGreaterThan(r.coherence, 0.4)            // power concentrated
        XCTAssertGreaterThan(r.lfPower, r.hfPower)         // LF dominates
    }

    func testCalibration_welch_point1Hz_peaksInLF() {
        let rr = sineTachogram(freqHz: 0.1)
        let r = HRVCoherence.compute(rrMs: rr, method: .welch)
        XCTAssertTrue(r.valid)
        XCTAssertEqual(Double(r.peakFrequencyHz), 0.1, accuracy: 0.02)
        XCTAssertGreaterThan(r.lfPower, r.hfPower)
    }

    // MARK: Calibration — 0.25 Hz (respiratory / HF) must peak in HF.

    func testCalibration_point25Hz_peaksInHF() {
        let rr = sineTachogram(freqHz: 0.25)
        let r = HRVCoherence.compute(rrMs: rr, method: .lombScargle)
        XCTAssertTrue(r.valid)
        XCTAssertEqual(Double(r.peakFrequencyHz), 0.25, accuracy: 0.03)
        XCTAssertGreaterThan(r.hfPower, r.lfPower)         // HF dominates
        XCTAssertLessThan(r.lfHfRatio, 1.0)
    }

    // MARK: Degenerate inputs.

    func testConstantRR_isInvalidOrZeroCoherence() {
        let rr = [Double](repeating: 850, count: 60)   // no variability → no spectrum
        let r = HRVCoherence.compute(rrMs: rr, method: .lombScargle)
        // Detrended signal is all-zero → total power 0 → invalid.
        XCTAssertFalse(r.valid)
    }

    func testTooFewIntervals_isInvalid() {
        let rr = [Double](repeating: 850, count: 4)
        XCTAssertFalse(HRVCoherence.compute(rrMs: rr, method: .welch).valid)
        XCTAssertFalse(HRVCoherence.compute(rrMs: rr, blend: 1.0).valid)
    }

    func testNonFiniteAndOutOfRange_rejected() {
        var rr = sineTachogram(freqHz: 0.1)
        rr.append(.nan)
        rr.append(99999)   // impossible RR
        rr.append(10)      // impossible RR
        let r = HRVCoherence.compute(rrMs: rr, method: .lombScargle)
        XCTAssertTrue(r.valid)                              // survives, junk dropped
        XCTAssertEqual(Double(r.peakFrequencyHz), 0.1, accuracy: 0.02)
    }

    // MARK: Blend fader.

    func testBlend_endpointsMatchPureMethods() {
        let rr = sineTachogram(freqHz: 0.1)
        let welch = HRVCoherence.compute(rrMs: rr, method: .welch)
        let lomb = HRVCoherence.compute(rrMs: rr, method: .lombScargle)
        let atZero = HRVCoherence.compute(rrMs: rr, blend: 0.0)
        let atOne = HRVCoherence.compute(rrMs: rr, blend: 1.0)
        XCTAssertEqual(atZero.coherence, welch.coherence, accuracy: 1e-5)
        XCTAssertEqual(atOne.coherence, lomb.coherence, accuracy: 1e-5)
    }

    func testBlend_midpointIsBetween() {
        let rr = sineTachogram(freqHz: 0.1)
        let welch = HRVCoherence.compute(rrMs: rr, method: .welch).coherence
        let lomb = HRVCoherence.compute(rrMs: rr, method: .lombScargle).coherence
        let mid = HRVCoherence.compute(rrMs: rr, blend: 0.5).coherence
        let lo = min(welch, lomb), hi = max(welch, lomb)
        XCTAssertGreaterThanOrEqual(mid, lo - 1e-5)
        XCTAssertLessThanOrEqual(mid, hi + 1e-5)
    }

    // MARK: "School" layer — always some info, never empty, never medical.

    func testReading_alwaysCarriesExplanation() {
        let valid = HRVCoherence.compute(rrMs: sineTachogram(freqHz: 0.1), blend: 1.0)
        XCTAssertFalse(valid.headline.isEmpty)
        XCTAssertFalse(valid.lesson.isEmpty)
        let invalid = CoherenceReading.invalid
        XCTAssertFalse(invalid.headline.isEmpty)
        XCTAssertFalse(invalid.lesson.isEmpty)
    }
}
