// EchoelModFXTests.swift
// Echoelmusic — modulation FX (chorus / flanger / phaser / tremolo).

import XCTest
@testable import Echoelmusic

final class EchoelModFXTests: XCTestCase {

    private let sr: Float = 48000

    // MARK: - Chorus

    func testChorusDryPassthroughWhenMixZero() {
        let fx = EchoelChorus(sampleRate: sr)
        fx.mix = 0
        for i in 0..<256 {
            let x = sinf(Float(i) * 0.1)
            let (l, r) = fx.processStereo(x, x)
            XCTAssertEqual(l, x, accuracy: 1e-5)
            XCTAssertEqual(r, x, accuracy: 1e-5)
        }
    }

    func testChorusIsBoundedAndAltersSignal() {
        let fx = EchoelChorus(sampleRate: sr)
        fx.mix = 1.0; fx.depth = 0.8; fx.rate = 1.5
        var diff: Float = 0
        for i in 0..<4000 {
            let x = sinf(Float(i) * 0.07)
            let (l, _) = fx.processStereo(x, x)
            XCTAssertTrue(l.isFinite)
            XCTAssertLessThan(abs(l), 2.0)
            if i > 1000 { diff += abs(l - x) }
        }
        XCTAssertGreaterThan(diff, 1.0) // wet path actually changed the signal
    }

    // MARK: - Flanger

    func testFlangerStableAtHighFeedback() {
        let fx = EchoelFlanger(sampleRate: sr)
        fx.mix = 0.6; fx.feedback = 0.9; fx.depth = 1.0
        for i in 0..<60_000 {
            let x: Float = (i == 0) ? 1.0 : 0.0
            let (l, r) = fx.processStereo(x, x)
            XCTAssertTrue(l.isFinite && r.isFinite)
            XCTAssertLessThan(abs(l), 8.0)
            XCTAssertLessThan(abs(r), 8.0)
        }
    }

    func testFlangerNegativeFeedbackIsClamped() {
        let fx = EchoelFlanger(sampleRate: sr)
        fx.mix = 0.5; fx.feedback = -5.0 // out of range → clamped internally
        for i in 0..<2000 {
            let x = sinf(Float(i) * 0.05)
            let (l, _) = fx.processStereo(x, x)
            XCTAssertTrue(l.isFinite)
        }
    }

    // MARK: - Phaser

    func testPhaserPreservesMagnitudeForStaticAllpass() {
        // depth 0 + feedback 0 → fixed allpass cascade, which is unity-magnitude.
        let fx = EchoelPhaser(sampleRate: sr)
        fx.mix = 1.0; fx.depth = 0.0; fx.feedback = 0.0
        var inSum: Float = 0
        var outSum: Float = 0
        for i in 0..<6000 {
            let x = sinf(2 * Float.pi * 440 * Float(i) / sr)
            let (l, _) = fx.processStereo(x, x)
            if i >= 5000 { inSum += x * x; outSum += l * l }
        }
        let inRMS = sqrtf(inSum / 1000)
        let outRMS = sqrtf(outSum / 1000)
        XCTAssertEqual(outRMS, inRMS, accuracy: 0.08)
    }

    func testPhaserBoundedWithFeedback() {
        // Impulse excitation: a stable feedback allpass comb (loop gain < 1)
        // must decay, not run away. Avoids resonance-driven steady-state gain.
        let fx = EchoelPhaser(sampleRate: sr)
        fx.mix = 1.0; fx.depth = 0.9; fx.feedback = 0.9; fx.rate = 0.5
        for i in 0..<20_000 {
            let x: Float = (i == 0) ? 1.0 : 0.0
            let (l, r) = fx.processStereo(x, x)
            XCTAssertTrue(l.isFinite && r.isFinite)
            XCTAssertLessThan(abs(l), 8.0)
            XCTAssertLessThan(abs(r), 8.0)
        }
    }

    // MARK: - Tremolo

    func testTremoloDepthZeroIsTransparent() {
        let fx = EchoelTremolo(sampleRate: sr)
        fx.depth = 0
        for i in 0..<512 {
            let x = sinf(Float(i) * 0.2)
            let (l, r) = fx.processStereo(x, x)
            XCTAssertEqual(l, x, accuracy: 1e-6)
            XCTAssertEqual(r, x, accuracy: 1e-6)
        }
    }

    func testTremoloModulatesAmplitude() {
        let fx = EchoelTremolo(sampleRate: sr)
        fx.depth = 1.0; fx.rate = 6.0
        var minGain: Float = .greatestFiniteMagnitude
        var maxGain: Float = 0
        // Drive a DC signal so output == instantaneous gain.
        for _ in 0..<20_000 {
            let (l, _) = fx.processStereo(1.0, 1.0)
            minGain = Swift.min(minGain, l)
            maxGain = Swift.max(maxGain, l)
        }
        XCTAssertLessThan(minGain, 0.2)      // dips toward silence
        XCTAssertGreaterThan(maxGain, 0.95)  // peaks near unity
    }

    func testTremoloAutoPanIsAntiPhase() {
        let fx = EchoelTremolo(sampleRate: sr)
        fx.depth = 1.0; fx.rate = 6.0; fx.stereoPan = true
        var maxSpread: Float = 0
        for _ in 0..<20_000 {
            let (l, r) = fx.processStereo(1.0, 1.0)
            maxSpread = Swift.max(maxSpread, abs(l - r))
        }
        XCTAssertGreaterThan(maxSpread, 0.8) // channels swing in opposition
    }
}
