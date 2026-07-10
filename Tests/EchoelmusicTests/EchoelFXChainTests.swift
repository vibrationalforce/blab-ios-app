// EchoelFXChainTests.swift
// Echoelmusic — FX chain composition layer.

import XCTest
@testable import Echoelmusic

final class EchoelFXChainTests: XCTestCase {

    private let sr: Float = 48000

    func testFullBypassIsExactPassthrough() {
        let fx = EchoelFXChain(sampleRate: sr)
        // Disable every stage, including the default-on saturation + limiter.
        fx.saturationEnabled = false
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
        fx.saturationEnabled = false; fx.limiterEnabled = false // all stages off
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

    func testSaturationAddsHarmonicBodyAndStaysBounded() {
        let fx = EchoelFXChain(sampleRate: sr)
        // Isolate saturation: every other stage off.
        fx.chorusEnabled = false; fx.flangerEnabled = false; fx.phaserEnabled = false
        fx.tremoloEnabled = false; fx.delayEnabled = false; fx.compressorEnabled = false
        fx.limiterEnabled = false
        fx.saturationEnabled = true
        fx.saturationDrive = 0.6

        var changed = false
        for i in 0..<2048 {
            let x = 0.8 * sinf(Float(i) * 0.07)
            let (l, r) = fx.processStereo(x, x)
            XCTAssertTrue(l.isFinite && r.isFinite)
            XCTAssertLessThanOrEqual(abs(l), 1.0)   // soft-clipped, never above unity
            if abs(l - x) > 1e-4 { changed = true }  // it actually shapes the tone
            XCTAssertEqual(l, r, accuracy: 1e-6)      // symmetric L/R
        }
        XCTAssertTrue(changed, "saturation should reshape the signal, not pass it through")
    }

    func testSaturationOfSilenceIsSilence() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.limiterEnabled = false
        fx.saturationEnabled = true
        let (l, r) = fx.processStereo(0, 0)
        XCTAssertEqual(l, 0, accuracy: 1e-6)
        XCTAssertEqual(r, 0, accuracy: 1e-6)
    }

    // MARK: - Switch declick (founder: "knistert beim Umschalten von Dingen")

    /// A stage disabled while holding audio freezes its delay lines; re-enabling
    /// it (preset/genre/character switch) must NOT burst that stale audio out.
    func testReEnableAfterStaleState_delay_emitsNoBurst() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.limiterEnabled = false; fx.saturationEnabled = false; fx.chorusEnabled = false
        fx.delayEnabled = true
        fx.delay.mix = 1.0; fx.delay.feedback = 0.7; fx.delay.timeSeconds = 0.01
        for i in 0..<4800 {                       // fill the line with loud audio
            let x = 0.9 * sinf(Float(i) * 0.2)
            _ = fx.processStereo(x, x)
        }
        fx.delayEnabled = false                   // freeze (bypassed = no state advance)
        fx.delayEnabled = true                    // the "Umschalten"
        for _ in 0..<4800 {                       // silence in → silence out, no stale burst
            let (l, r) = fx.processStereo(0, 0)
            XCTAssertEqual(l, 0, accuracy: 1e-4)
            XCTAssertEqual(r, 0, accuracy: 1e-4)
        }
    }

    func testReEnableAfterStaleState_reverb_emitsNoBurst() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.limiterEnabled = false; fx.saturationEnabled = false; fx.chorusEnabled = false
        fx.reverbEnabled = true
        fx.reverb.mix = 1.0
        for i in 0..<9600 {
            let x = 0.9 * sinf(Float(i) * 0.2)
            _ = fx.processStereo(x, x)
        }
        fx.reverbEnabled = false
        fx.reverbEnabled = true
        for _ in 0..<9600 {
            let (l, r) = fx.processStereo(0, 0)
            XCTAssertEqual(l, 0, accuracy: 1e-3)
            XCTAssertEqual(r, 0, accuracy: 1e-3)
        }
    }

    /// Re-assigning an ALREADY-enabled flag (presets write every flag every
    /// time) must not reset — a live delay tail survives a same-value write.
    func testReassignSameEnabledValue_keepsLiveTail() {
        let fx = EchoelFXChain(sampleRate: sr)
        fx.limiterEnabled = false; fx.saturationEnabled = false; fx.chorusEnabled = false
        fx.delayEnabled = true
        fx.delay.mix = 1.0; fx.delay.feedback = 0.0; fx.delay.timeSeconds = 0.005 // 240 smp
        _ = fx.processStereo(1.0, 1.0)            // impulse into the line
        fx.delayEnabled = true                    // same-value write (preset apply pattern)
        var laterPeak: Float = 0
        for _ in 0..<512 {
            let (l, _) = fx.processStereo(0, 0)
            laterPeak = Swift.max(laterPeak, abs(l))
        }
        XCTAssertGreaterThan(laterPeak, 0.5, "same-value enable write must not clear the tail")
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
