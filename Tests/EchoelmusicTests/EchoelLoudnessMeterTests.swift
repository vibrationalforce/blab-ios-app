// EchoelLoudnessMeterTests.swift
// Echoelmusic — BS.1770 K-weighted loudness meter.
//
// Assertions are calibration-robust (relative laws), since exact absolute LUFS
// depends on the offset/coefficients and cannot be locally compiled here.

import XCTest
@testable import Echoelmusic

final class EchoelLoudnessMeterTests: XCTestCase {

    private let sr: Float = 48000

    private func sine(_ freq: Float, _ amp: Float, _ count: Int) -> [Float] {
        (0..<count).map { amp * sinf(2 * Float.pi * freq * Float($0) / sr) }
    }

    func testSilenceReadsFloor() {
        let m = EchoelLoudnessMeter(sampleRate: sr)
        m.process([Float](repeating: 0, count: 24000), frameCount: 24000)
        XCTAssertEqual(m.momentaryLUFS, EchoelLoudnessMeter.floorLUFS, accuracy: 0.01)
        XCTAssertEqual(m.shortTermLUFS, EchoelLoudnessMeter.floorLUFS, accuracy: 0.01)
    }

    func testDoublingAmplitudeAddsSixLU() {
        let quiet = EchoelLoudnessMeter(sampleRate: sr)
        let loud = EchoelLoudnessMeter(sampleRate: sr)
        let n = 48000 // 1 s — fills the 400 ms momentary window
        quiet.process(sine(1000, 0.25, n), frameCount: n)
        loud.process(sine(1000, 0.50, n), frameCount: n)
        let delta = loud.momentaryLUFS - quiet.momentaryLUFS
        XCTAssertEqual(delta, 6.02, accuracy: 0.4) // 10*log10(4)
    }

    func testKWeightingAttenuatesLowFrequencies() {
        let mid = EchoelLoudnessMeter(sampleRate: sr)
        let low = EchoelLoudnessMeter(sampleRate: sr)
        let n = 48000
        mid.process(sine(1000, 0.5, n), frameCount: n)
        low.process(sine(30, 0.5, n), frameCount: n)
        // The RLB high-pass should make 30 Hz read clearly quieter than 1 kHz.
        XCTAssertGreaterThan(mid.momentaryLUFS, low.momentaryLUFS + 2.0)
    }

    func testMomentaryInPlausibleRange() {
        let m = EchoelLoudnessMeter(sampleRate: sr)
        let n = 48000
        m.process(sine(1000, 1.0, n), frameCount: n)
        XCTAssertGreaterThan(m.momentaryLUFS, -12)
        XCTAssertLessThan(m.momentaryLUFS, 2)
    }

    func testStereoIsLouderThanMonoSameAmplitude() {
        // Two equal channels sum to +3 LU vs one channel at the same amplitude.
        let mono = EchoelLoudnessMeter(sampleRate: sr)
        let stereo = EchoelLoudnessMeter(sampleRate: sr)
        let n = 48000
        let s = sine(1000, 0.5, n)
        mono.process(s, frameCount: n)
        stereo.processStereo(left: s, right: s, frameCount: n)
        XCTAssertEqual(stereo.momentaryLUFS - mono.momentaryLUFS, 3.01, accuracy: 0.4)
    }

    func testPointerOverloadMatchesArrayPath() {
        let n = 48000
        let l = sine(1000, 0.5, n)
        let r = sine(1000, 0.35, n)
        let mArray = EchoelLoudnessMeter(sampleRate: sr)
        mArray.processStereo(left: l, right: r, frameCount: n)
        let mPtr = EchoelLoudnessMeter(sampleRate: sr)
        l.withUnsafeBufferPointer { lp in
            r.withUnsafeBufferPointer { rp in
                guard let lb = lp.baseAddress, let rb = rp.baseAddress else { return XCTFail("no base") }
                mPtr.processStereo(left: lb, right: rb, frameCount: n)
            }
        }
        XCTAssertEqual(mPtr.momentaryLUFS, mArray.momentaryLUFS, accuracy: 0.05)
        XCTAssertEqual(mPtr.shortTermLUFS, mArray.shortTermLUFS, accuracy: 0.05)
    }

    func testResetReturnsToFloor() {
        let m = EchoelLoudnessMeter(sampleRate: sr)
        m.process(sine(1000, 0.5, 24000), frameCount: 24000)
        m.reset()
        XCTAssertEqual(m.momentaryLUFS, EchoelLoudnessMeter.floorLUFS, accuracy: 0.01)
    }

    // MARK: - Integrated / LRA (EBU R128)

    /// Feed a steady tone in 100 ms chunks so the gating clocks fire repeatedly.
    private func feedSteady(_ m: EchoelLoudnessMeter, seconds: Int, amp: Float = 0.5) {
        let chunk = Int(0.1 * sr)
        let tone = sine(1000, amp, chunk)
        for _ in 0..<(seconds * 10) { m.process(tone, frameCount: chunk) }
    }

    func testIntegrated_steadyTone_approxMomentary() {
        let m = EchoelLoudnessMeter(sampleRate: sr)
        feedSteady(m, seconds: 6)
        XCTAssertGreaterThan(m.integratedLUFS, EchoelLoudnessMeter.floorLUFS + 1)
        // Integrated (gated mean of 400 ms blocks) ≈ momentary for a steady tone.
        XCTAssertEqual(m.integratedLUFS, m.momentaryLUFS, accuracy: 1.0)
    }

    func testLRA_steadyTone_isSmall() {
        let m = EchoelLoudnessMeter(sampleRate: sr)
        feedSteady(m, seconds: 8)
        XCTAssertGreaterThanOrEqual(m.loudnessRange, 0)
        XCTAssertLessThan(m.loudnessRange, 1.0) // no dynamics → ~0 LU
    }

    func testReset_clearsIntegratedAndLRA() {
        let m = EchoelLoudnessMeter(sampleRate: sr)
        feedSteady(m, seconds: 6)
        m.reset()
        XCTAssertEqual(m.integratedLUFS, EchoelLoudnessMeter.floorLUFS, accuracy: 0.01)
        XCTAssertEqual(m.loudnessRange, 0, accuracy: 0.01)
    }

    func testIntegrated_silence_staysAtFloor() {
        let m = EchoelLoudnessMeter(sampleRate: sr)
        let silence = [Float](repeating: 0, count: Int(0.1 * sr))
        for _ in 0..<60 { m.process(silence, frameCount: silence.count) }
        XCTAssertEqual(m.integratedLUFS, EchoelLoudnessMeter.floorLUFS, accuracy: 0.01)
        XCTAssertEqual(m.loudnessRange, 0, accuracy: 0.01)
    }
}
