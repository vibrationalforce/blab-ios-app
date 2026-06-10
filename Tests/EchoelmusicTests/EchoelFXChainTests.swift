// EchoelFXChainTests.swift
// Echoelmusic — FX chain composition layer.

import XCTest
@testable import Echoelmusic

final class EchoelFXChainTests: XCTestCase {

    private let sr: Float = 48000

    func testFullBypassIsExactPassthrough() {
        let fx = EchoelFXChain(sampleRate: sr)
        // Disable every stage, including the default-on limiter.
        fx.chorusEnabled = false; fx.flangerEnabled = false; fx.phaserEnabled = false
        fx.tremoloEnabled = false; fx.delayEnabled = false; fx.compressorEnabled = false
        fx.limiterEnabled = false
        for i in 0..<512 {
            let x = sinf(Float(i) * 0.13)
            let (l, r) = fx.processStereo(x, x)
            XCTAssertEqual(l, x, accuracy: 1e-6)
            XCTAssertEqual(r, x, accuracy: 1e-6)
        }
    }

    func testDefaultLimiterCatchesLoudPeaks() {
        let fx = EchoelFXChain(sampleRate: sr) // limiter on by default
        let ceiling = powf(10.0, fx.limiter.ceilingDb / 20.0)
        var maxOut: Float = 0
        for i in 0..<4000 {
            let x = 2.0 * sinf(Float(i) * 0.1)
            let (l, r) = fx.processStereo(x, x)
            maxOut = Swift.max(maxOut, Swift.max(abs(l), abs(r)))
        }
        XCTAssertLessThanOrEqual(maxOut, ceiling * 1.001)
    }

    func testAllStagesEnabledStaysBounded() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.chorusEnabled = true; fx.flangerEnabled = true; fx.phaserEnabled = true
        fx.tremoloEnabled = true; fx.delayEnabled = true; fx.compressorEnabled = true
        fx.limiterEnabled = true
        fx.delay.feedback = 0.6; fx.flanger.feedback = 0.7; fx.phaser.feedback = 0.6
        let ceiling = powf(10.0, fx.limiter.ceilingDb / 20.0)
        for i in 0..<48_000 {
            let x = 0.8 * sinf(Float(i) * 0.05)
            let (l, r) = fx.processStereo(x, x)
            XCTAssertTrue(l.isFinite && r.isFinite)
            // Limiter is last, so the chain output respects the ceiling.
            XCTAssertLessThanOrEqual(abs(l), ceiling * 1.01)
            XCTAssertLessThanOrEqual(abs(r), ceiling * 1.01)
        }
    }

    func testProcessBufferMonoBypassIsPassthrough() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.limiterEnabled = false // all stages off
        var buf = (0..<256).map { sinf(Float($0) * 0.11) }
        let original = buf
        fx.processBufferMono(&buf, frameCount: buf.count)
        for i in 0..<buf.count {
            XCTAssertEqual(buf[i], original[i], accuracy: 1e-6)
        }
    }

    func testProcessBufferMonoDelayProducesTail() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.delayEnabled = true; fx.limiterEnabled = false
        fx.delay.mix = 1.0; fx.delay.feedback = 0.0; fx.delay.timeSeconds = 0.005 // 240 samples
        var buf = [Float](repeating: 0, count: 512)
        buf[0] = 1.0
        fx.processBufferMono(&buf, frameCount: buf.count)
        // The dry input was 1 only at index 0; a wet echo must appear later.
        var laterPeak: Float = 0
        for i in 100..<buf.count { laterPeak = Swift.max(laterPeak, abs(buf[i])) }
        XCTAssertGreaterThan(laterPeak, 0.5)
    }

    func testResetClearsDelayTail() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.delayEnabled = true; fx.limiterEnabled = false
        fx.delay.mix = 1.0; fx.delay.feedback = 0.7; fx.delay.timeSeconds = 0.01
        _ = fx.processStereo(1.0, 1.0)
        for _ in 0..<2000 { _ = fx.processStereo(0, 0) }
        fx.reset()
        // After reset the delay memory is clear → silence in, silence out.
        let (l, r) = fx.processStereo(0, 0)
        XCTAssertEqual(l, 0, accuracy: 1e-6)
        XCTAssertEqual(r, 0, accuracy: 1e-6)
    }
}
