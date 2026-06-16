// EchoelReverbTests.swift
// Echoelmusic — Freeverb-style algorithmic reverb.

import XCTest
@testable import Echoelmusic

final class EchoelReverbTests: XCTestCase {

    private let sr: Float = 48000

    func testReverbMixZeroIsPassthrough() {
        let fx = EchoelReverb(sampleRate: sr)
        fx.mix = 0
        for i in 0..<512 {
            let x = sinf(Float(i) * 0.13)
            let (l, r) = fx.processStereo(x, x)
            XCTAssertEqual(l, x, accuracy: 1e-6)
            XCTAssertEqual(r, x, accuracy: 1e-6)
        }
    }

    func testReverbBoundedAndStableOnImpulse() {
        let fx = EchoelReverb(sampleRate: sr)
        fx.mix = 1.0; fx.roomSize = 0.95; fx.damping = 0.2
        for i in 0..<200_000 {
            let x: Float = (i == 0) ? 1.0 : 0.0
            let (l, r) = fx.processStereo(x, x)
            XCTAssertTrue(l.isFinite && r.isFinite)
            XCTAssertLessThan(abs(l), 4.0)
            XCTAssertLessThan(abs(r), 4.0)
        }
    }

    func testReverbProducesDecayingTailAfterInputStops() {
        let fx = EchoelReverb(sampleRate: sr)
        fx.mix = 0.6; fx.roomSize = 0.85; fx.damping = 0.4
        // Excite for a short burst.
        for i in 0..<2_000 {
            _ = fx.processStereo(sinf(Float(i) * 0.2), sinf(Float(i) * 0.2))
        }
        // Then feed silence and confirm a non-trivial tail rings out.
        var tailEnergy: Float = 0
        for _ in 0..<4_000 {
            let (l, r) = fx.processStereo(0, 0)
            tailEnergy += l * l + r * r
        }
        XCTAssertGreaterThan(tailEnergy, 0.01) // reverb tail persists past the input
    }

    func testReverbAltersSignalWhenWet() {
        let fx = EchoelReverb(sampleRate: sr)
        fx.mix = 1.0; fx.roomSize = 0.8
        var diff: Float = 0
        for i in 0..<8_000 {
            let x = sinf(Float(i) * 0.05)
            let (l, _) = fx.processStereo(x, x)
            XCTAssertTrue(l.isFinite)
            if i > 2_000 { diff += abs(l - x) }
        }
        XCTAssertGreaterThan(diff, 1.0) // wet output is audibly different from dry
    }

    func testReverbResetClearsTail() {
        let fx = EchoelReverb(sampleRate: sr)
        fx.mix = 0.8; fx.roomSize = 0.9
        for i in 0..<4_000 {
            _ = fx.processStereo(sinf(Float(i) * 0.2), sinf(Float(i) * 0.2))
        }
        fx.reset()
        // Immediately after reset the first silent sample must be silent.
        let (l, r) = fx.processStereo(0, 0)
        XCTAssertEqual(l, 0, accuracy: 1e-6)
        XCTAssertEqual(r, 0, accuracy: 1e-6)
    }
}
