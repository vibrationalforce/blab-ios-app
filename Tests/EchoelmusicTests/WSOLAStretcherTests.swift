// WSOLAStretcherTests.swift
// Echoel — Stretch Slice 2 (Beats-Executor): the pure, offline WSOLA core.
// Textbook Verhelst–Roelands: fixed synthesis hop, rate-scaled analysis hop,
// waveform-similarity search (±tolerance) against the natural continuation,
// Hann overlap-add. Time changes, PITCH stays — the property naive resampling
// cannot deliver. Pure Float-buffer math; runs on the macOS SwiftPM CI.

import XCTest
@testable import Echoelmusic

final class WSOLAStretcherTests: XCTestCase {

    private let sampleRate = 48_000.0

    private func sine(hz: Double, seconds: Double) -> [Float] {
        let n = Int(seconds * sampleRate)
        return (0..<n).map { Float(sin(2.0 * .pi * hz * Double($0) / sampleRate)) }
    }

    /// Estimate the dominant frequency by counting sign changes (a sine's
    /// zero-crossing rate = 2·f). Robust enough to separate 440 from 220/880.
    private func zeroCrossingHz(_ x: [Float]) -> Double {
        guard x.count > 1 else { return 0 }
        var crossings = 0
        for i in 1..<x.count where (x[i - 1] < 0) != (x[i] < 0) { crossings += 1 }
        return Double(crossings) / 2.0 / (Double(x.count) / sampleRate)
    }

    // MARK: - Guards / degenerate input

    func testDegenerateInputs_failQuiet() {
        let s = WSOLAStretcher()
        XCTAssertTrue(s.stretch([], rate: 0.5).isEmpty)
        // Shorter than one analysis frame: passthrough copy, no crash.
        let tiny: [Float] = [0.1, -0.2, 0.3]
        XCTAssertEqual(s.stretch(tiny, rate: 0.5), tiny)
        // Non-finite / non-positive rates: passthrough (fail quiet, NaN law).
        let x = sine(hz: 220, seconds: 0.1)
        XCTAssertEqual(s.stretch(x, rate: 0), x)
        XCTAssertEqual(s.stretch(x, rate: .nan), x)
        XCTAssertEqual(s.stretch(x, rate: -1), x)
    }

    func testRateOne_isPassthrough() {
        let x = sine(hz: 330, seconds: 0.2)
        XCTAssertEqual(WSOLAStretcher().stretch(x, rate: 1.0), x,
                       "rate 1 must be bit-transparent, like StretchPlan's clean identity")
    }

    // MARK: - Duration law (rate = playback speed; output ≈ input / rate)

    func testDuration_scalesInverselyWithRate() {
        let x = sine(hz: 440, seconds: 1.0)
        let s = WSOLAStretcher()
        let slow = s.stretch(x, rate: 0.5)     // half speed → ~double length
        let fast = s.stretch(x, rate: 2.0)     // double speed → ~half length
        XCTAssertEqual(Double(slow.count), Double(x.count) / 0.5,
                       accuracy: Double(x.count) * 0.08)
        XCTAssertEqual(Double(fast.count), Double(x.count) / 2.0,
                       accuracy: Double(x.count) * 0.08)
    }

    // MARK: - The point of WSOLA: pitch survives the time change

    func testPitchPreserved_atHalfAndDoubleSpeed() {
        let x = sine(hz: 440, seconds: 1.0)
        let s = WSOLAStretcher()
        for rate in [0.5, 2.0] {
            let y = s.stretch(x, rate: Float(rate))
            let hz = zeroCrossingHz(y)
            XCTAssertEqual(hz, 440, accuracy: 25,
                           "rate \(rate): pitch must hold near 440 Hz (naive resample would give \(440 * rate))")
        }
    }

    func testHeadReachesFullLevel_kickAttackSurvives() {
        // DSP-review M1: without window-sum normalization the first half-frame
        // fades in over ~5 ms — a kick at sample 0 loses its attack. A constant
        // signal must come out at full level well inside the first half-frame.
        let x = [Float](repeating: 0.5, count: 48_000)
        let y = WSOLAStretcher().stretch(x, rate: 0.5)
        XCTAssertEqual(y[64], 0.5, accuracy: 0.05,
                       "sample 64 sits deep in the old fade-in region — must be full level")
        XCTAssertEqual(y[y.count / 2], 0.5, accuracy: 0.05, "steady state stays unit gain")
    }

    func testTail_hasNoZeroGap_atSlowRates() {
        // DSP-review L1: for rate < 1 the nominal position could pass the last
        // valid frame start and the old break left hard zeros in the allocated
        // tail. Clamped search: the end of a stretched loop keeps sounding.
        let x = sine(hz: 440, seconds: 1.0)
        let y = WSOLAStretcher().stretch(x, rate: 0.5)
        let tail = Array(y.suffix(512))
        XCTAssertGreaterThan(tail.map { abs($0) }.max() ?? 0, 0.3,
                             "allocated tail must carry signal, not silence")
    }

    // MARK: - Multichannel coherence (timeline-executor prep: mono-downmix search)

    func testMultichannel_renderIsLinear_scaledChannelStaysScaled() {
        // LINEARITY check (dsp-review: NOT a shared-search guard — normalized
        // cross-correlation is scale-invariant, so R = 0.5·L yields identical
        // offsets even under independent searches; the discriminating guard is
        // the superposition test below): render() must be linear per channel,
        // so an exactly scaled channel stays exactly scaled through the stretch.
        let left = sine(hz: 440, seconds: 0.5)
        let right = left.map { $0 * 0.5 }
        let out = WSOLAStretcher().stretchMultichannel([left, right], rate: 0.5)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].count, out[1].count, "channel lengths must match")
        for i in stride(from: 0, to: out[0].count, by: 7) {
            XCTAssertEqual(out[1][i], out[0][i] * 0.5, accuracy: 1e-4,
                           "sample \(i): offsets must be shared across channels")
        }
        // And the stretch itself still happened (duration law).
        XCTAssertEqual(Double(out[0].count), Double(left.count) / 0.5,
                       accuracy: Double(left.count) * 0.08)
    }

    func testMultichannel_offsetsAreShared_superposition() {
        // THE shared-offset guard (dsp-review MEDIUM): with two DIFFERENT-content
        // channels, independent searches would pick different offsets (a click
        // train snaps to click spacing, a sine to its period) and the identity
        // below fails hard. With ONE shared search, render() linearity makes
        // sum-of-channels == stretch-of-the-downmix by construction.
        let a = sine(hz: 440, seconds: 0.5)
        let clicks: [Float] = (0..<a.count).map { $0 % 4800 == 0 ? 1 : 0 }
        let out = WSOLAStretcher().stretchMultichannel([a, clicks], rate: 0.5)
        let mixRef = WSOLAStretcher().stretch(zip(a, clicks).map { ($0 + $1) * 0.5 }, rate: 0.5)
        XCTAssertEqual(out[0].count, mixRef.count)
        for i in stride(from: 0, to: mixRef.count, by: 7) {
            XCTAssertEqual((out[0][i] + out[1][i]) * 0.5, mixRef[i], accuracy: 1e-3,
                           "shared-offset law: sum of channels == stretch of the downmix")
        }
    }

    func testMultichannel_degenerateInputs_failQuiet() {
        let s = WSOLAStretcher()
        XCTAssertTrue(s.stretchMultichannel([], rate: 0.5).isEmpty)
        // Mismatched channel lengths: passthrough unchanged (fail quiet).
        let a: [Float] = sine(hz: 220, seconds: 0.2)
        let b: [Float] = Array(a.dropLast(100))
        let out = s.stretchMultichannel([a, b], rate: 0.5)
        XCTAssertEqual(out[0], a)
        XCTAssertEqual(out[1], b)
        // Mono input behaves exactly like stretch().
        XCTAssertEqual(s.stretchMultichannel([a], rate: 2.0)[0], s.stretch(a, rate: 2.0))
    }

    func testOutputLevel_isSane_noWindowingGapsOrDoubling() {
        // Hann 50% overlap-add is constant-gain; the similarity search must not
        // tear that apart: RMS of the stretched sine stays near the input RMS
        // (a dropped/doubled overlap would show up as a big level shift).
        let x = sine(hz: 440, seconds: 1.0)
        let y = WSOLAStretcher().stretch(x, rate: 0.5)
        func rms(_ v: [Float]) -> Double {
            guard !v.isEmpty else { return 0 }
            return (v.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(v.count)).squareRoot()
        }
        XCTAssertEqual(rms(y), rms(x), accuracy: rms(x) * 0.25)
        // And every sample stays finite/in a sane band.
        XCTAssertTrue(y.allSatisfy { $0.isFinite && abs($0) <= 1.5 })
    }
}
