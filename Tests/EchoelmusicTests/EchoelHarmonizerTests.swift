// EchoelHarmonizerTests.swift
// Echoelmusic — delay-line pitch-shift harmonizer.

import XCTest
@testable import Echoelmusic

final class EchoelHarmonizerTests: XCTestCase {

    private let sr: Float = 48000

    func testHarmonizerMixZeroIsDry() {
        let fx = EchoelHarmonizer(sampleRate: sr)
        fx.mix = 0
        for i in 0..<512 {
            let x = sinf(Float(i) * 0.11)
            let (l, r) = fx.processStereo(x, x)
            XCTAssertEqual(l, x, accuracy: 1e-6) // dry passes at full level, no harmony
            XCTAssertEqual(r, x, accuracy: 1e-6)
        }
    }

    func testHarmonizerBoundedAndAddsHarmony() {
        let fx = EchoelHarmonizer(sampleRate: sr)
        fx.mix = 0.7; fx.interval1 = 4; fx.interval2 = 7
        var diff: Float = 0
        for i in 0..<8_000 {
            let x = sinf(2 * Float.pi * 220 * Float(i) / sr)
            let (l, r) = fx.processStereo(x, x)
            XCTAssertTrue(l.isFinite && r.isFinite)
            XCTAssertLessThan(abs(l), 4.0)
            XCTAssertLessThan(abs(r), 4.0)
            if i > 2_000 { diff += abs(l - x) } // harmony voices added → differs from dry
        }
        XCTAssertGreaterThan(diff, 1.0)
    }

    func testHarmonizerSecondVoiceDisableChangesOutput() {
        let two = EchoelHarmonizer(sampleRate: sr)
        two.mix = 0.7; two.voice2Enabled = true
        let one = EchoelHarmonizer(sampleRate: sr)
        one.mix = 0.7; one.voice2Enabled = false
        var diff: Float = 0
        for i in 0..<6_000 {
            let x = sinf(2 * Float.pi * 196 * Float(i) / sr)
            let (l2, _) = two.processStereo(x, x)
            let (l1, _) = one.processStereo(x, x)
            XCTAssertTrue(l1.isFinite && l2.isFinite)
            if i > 2_000 { diff += abs(l2 - l1) }
        }
        XCTAssertGreaterThan(diff, 0.5) // the fifth voice measurably contributes
    }

    func testHarmonizerStableAtExtremeIntervals() {
        let fx = EchoelHarmonizer(sampleRate: sr)
        fx.mix = 1.0; fx.interval1 = 12; fx.interval2 = -12 // octave up + octave down
        for i in 0..<20_000 {
            let x = sinf(Float(i) * 0.07)
            let (l, r) = fx.processStereo(x, x)
            XCTAssertTrue(l.isFinite && r.isFinite)
            XCTAssertLessThan(abs(l), 4.0)
            XCTAssertLessThan(abs(r), 4.0)
        }
    }
}
