// EchoelFXTests.swift
// Echoelmusic — real-time FX suite (delay foundation).
//
// Covers EchoelDelayLine (fractional ring buffer) and EchoelDelay
// (digital / tape / ping-pong). Pure-DSP, no AVFoundation dependency.

import XCTest
@testable import Echoelmusic

final class EchoelDelayLineTests: XCTestCase {

    func testIntegerDelayReadsExactSample() {
        let dl = EchoelDelayLine(maxDelaySeconds: 0.01, sampleRate: 48000)
        dl.write(1.0)
        XCTAssertEqual(dl.read(delaySamples: 1), 1.0, accuracy: 1e-6)
        dl.write(0.0)
        XCTAssertEqual(dl.read(delaySamples: 1), 0.0, accuracy: 1e-6) // most recent
        XCTAssertEqual(dl.read(delaySamples: 2), 1.0, accuracy: 1e-6) // two ago
    }

    func testLinearInterpolationMidpoint() {
        let dl = EchoelDelayLine(maxDelaySeconds: 0.01, sampleRate: 48000)
        dl.write(0.0)   // older
        dl.write(1.0)   // newest
        // delay 1.5 sits halfway between newest (1.0) and previous (0.0)
        XCTAssertEqual(dl.read(delaySamples: 1.5), 0.5, accuracy: 1e-5)
    }

    func testReadClampsAndNeverCrashes() {
        let dl = EchoelDelayLine(maxDelaySeconds: 0.01, sampleRate: 48000)
        dl.write(0.7)
        // Out-of-range reads are clamped, not crashing.
        XCTAssertTrue(dl.read(delaySamples: -50).isFinite)
        XCTAssertTrue(dl.read(delaySamples: 1_000_000).isFinite)
    }

    func testAllpassReadIsFiniteAndStable() {
        let dl = EchoelDelayLine(maxDelaySeconds: 0.02, sampleRate: 48000)
        for i in 0..<2000 {
            dl.write(sinf(Float(i) * 0.05))
            let v = dl.readAllpass(delaySamples: 100.3)
            XCTAssertTrue(v.isFinite)
            XCTAssertLessThan(abs(v), 4.0)
        }
    }

    func testResetClears() {
        let dl = EchoelDelayLine(maxDelaySeconds: 0.01, sampleRate: 48000)
        dl.write(1.0); dl.write(1.0); dl.write(1.0)
        dl.reset()
        XCTAssertEqual(dl.read(delaySamples: 1), 0.0, accuracy: 1e-6)
        XCTAssertEqual(dl.read(delaySamples: 5), 0.0, accuracy: 1e-6)
    }
}

final class EchoelDelayTests: XCTestCase {

    private let sr: Float = 48000

    func testDryPassthroughWhenMixZero() {
        let d = EchoelDelay(sampleRate: sr)
        d.mix = 0; d.feedback = 0.5
        for i in 0..<256 {
            let x = sinf(Float(i) * 0.1)
            let (l, r) = d.processStereo(x, x)
            XCTAssertEqual(l, x, accuracy: 1e-5)
            XCTAssertEqual(r, x, accuracy: 1e-5)
        }
    }

    func testImpulseProducesEchoAtDelayTime() {
        let d = EchoelDelay(sampleRate: sr)
        d.mode = .digital; d.mix = 1.0; d.feedback = 0.0
        d.timeSeconds = 0.01 // 480 samples
        d.reset() // snap the ~40ms time-glide to the set tap (fresh line starts at 0.375s)

        var peakIdx = -1
        var peakVal: Float = 0
        for i in 0..<700 {
            let input: Float = (i == 0) ? 1.0 : 0.0
            let (l, _) = d.processStereo(input, input)
            if abs(l) > peakVal { peakVal = abs(l); peakIdx = i }
        }
        XCTAssertEqual(peakVal, 1.0, accuracy: 0.05)
        XCTAssertLessThanOrEqual(abs(peakIdx - 480), 2)
    }

    func testFeedbackProducesDecayingEchoes() {
        let d = EchoelDelay(sampleRate: sr)
        d.mode = .digital; d.mix = 1.0; d.feedback = 0.5; d.tone = 1.0
        d.timeSeconds = 0.01 // 480 samples
        d.reset() // snap the ~40ms time-glide to the set tap (fresh line starts at 0.375s)

        var out = [Float](repeating: 0, count: 1600)
        for i in 0..<out.count {
            let input: Float = (i == 0) ? 1.0 : 0.0
            out[i] = d.processStereo(input, input).0
        }
        let echo1 = peak(in: out, around: 480, window: 30)
        let echo2 = peak(in: out, around: 960, window: 30)
        XCTAssertGreaterThan(echo1, 0.3)
        XCTAssertGreaterThan(echo2, 0.05)
        XCTAssertLessThan(echo2, echo1) // each repeat is quieter
    }

    /// Changing `timeSeconds` mid-stream must GLIDE the read tap, not jump it —
    /// a jump is the sample-to-sample discontinuity the founder hears as
    /// "Knistern beim Umschalten" when a preset/character lands a new delay time.
    func testTimeChangeMidStreamGlidesWithoutDiscontinuity() {
        let d = EchoelDelay(sampleRate: sr)
        d.mode = .digital; d.mix = 1.0; d.feedback = 0.0
        d.timeSeconds = 0.01                       // 480 samples

        // 60 Hz sine (period 800 samples — NOT commensurate with either tap, so
        // a 480→960-sample tap jump lands mid-phase and the discontinuity is
        // large); the glide keeps the diff near the sine's own slope
        // (~0.008/sample, ×~1.25 max repitch rate).
        let omega = 2.0 * Float.pi * 60.0 / sr
        var prev: Float = 0
        var maxDiff: Float = 0
        for i in 0..<19_200 {
            if i == 9600 { d.timeSeconds = 0.02 }  // the switch
            let x = sinf(Float(i) * omega)
            let (l, _) = d.processStereo(x, x)
            if i > 960 { maxDiff = Swift.max(maxDiff, abs(l - prev)) } // skip fill-in
            prev = l
        }
        XCTAssertLessThan(maxDiff, 0.05, "delay-time switch must repitch smoothly, not click")
    }

    func testHighFeedbackStaysBounded() {
        let d = EchoelDelay(sampleRate: sr)
        d.mode = .tape; d.mix = 0.5; d.feedback = 0.95
        d.drive = 0.8; d.wow = 0.5; d.tone = 0.7
        d.timeSeconds = 0.02

        for i in 0..<100_000 {
            let input: Float = (i == 0) ? 1.0 : 0.0
            let (l, r) = d.processStereo(input, input)
            XCTAssertTrue(l.isFinite && r.isFinite)
            XCTAssertLessThan(abs(l), 4.0)
            XCTAssertLessThan(abs(r), 4.0)
        }
    }

    func testPingPongCrossesChannels() {
        let d = EchoelDelay(sampleRate: sr)
        d.mode = .pingPong; d.mix = 1.0; d.feedback = 0.6; d.tone = 1.0
        d.timeSeconds = 0.01 // 480 samples
        d.reset() // snap the ~40ms time-glide to the set tap (fresh line starts at 0.375s)

        var outL = [Float](repeating: 0, count: 1600)
        var outR = [Float](repeating: 0, count: 1600)
        for i in 0..<outL.count {
            let input: Float = (i == 0) ? 1.0 : 0.0
            let (l, r) = d.processStereo(input, 0.0) // hit LEFT only
            outL[i] = l; outR[i] = r
        }
        // First echo on the left, second bounces to the right.
        XCTAssertGreaterThan(energy(outL, 400, 600), energy(outR, 400, 600))
        XCTAssertGreaterThan(energy(outR, 900, 1100), energy(outL, 900, 1100))
    }

    func testModeEnumIsComplete() {
        XCTAssertEqual(EchoelDelay.Mode.allCases.count, 3)
    }

    // MARK: - Helpers

    private func peak(in buf: [Float], around center: Int, window: Int) -> Float {
        var p: Float = 0
        let lo = Swift.max(0, center - window)
        let hi = Swift.min(buf.count, center + window)
        for i in lo..<hi { p = Swift.max(p, abs(buf[i])) }
        return p
    }

    private func energy(_ buf: [Float], _ lo: Int, _ hi: Int) -> Float {
        var s: Float = 0
        let a = Swift.max(0, lo), b = Swift.min(buf.count, hi)
        for i in a..<b { s += abs(buf[i]) }
        return s
    }
}
