// PitchTrackerTests.swift
// Echoel — YIN fine-pitch detection. Pure math on synthetic tones → runs on Linux.

import XCTest
import Foundation
@testable import Echoelmusic

final class PitchTrackerTests: XCTestCase {

    private let sr = 48_000.0

    private func sine(_ hz: Double, n: Int = 4096, harmonics: [Double] = []) -> [Float] {
        (0..<n).map { i in
            let t = Double(i) / sr
            var v = sin(2 * .pi * hz * t)
            for (k, amp) in harmonics.enumerated() {
                v += amp * sin(2 * .pi * hz * Double(k + 2) * t)
            }
            return Float(v)
        }
    }

    func testDetectsA440() throws {
        let f = try XCTUnwrap(PitchTracker.detect(sine(440), sampleRate: sr))
        XCTAssertEqual(f, 440, accuracy: 1.0)   // < ~4 cents
    }

    func testDetectsA432() throws {
        let f = try XCTUnwrap(PitchTracker.detect(sine(432), sampleRate: sr))
        XCTAssertEqual(f, 432, accuracy: 1.0)
    }

    func testDetectsA444() throws {
        let f = try XCTUnwrap(PitchTracker.detect(sine(444), sampleRate: sr))
        XCTAssertEqual(f, 444, accuracy: 1.0)
    }

    func testDetectsMiddleC() throws {
        let f = try XCTUnwrap(PitchTracker.detect(sine(261.63), sampleRate: sr))
        XCTAssertEqual(f, 261.63, accuracy: 1.5)
    }

    func testDetectsFundamentalWithHarmonics() throws {
        // Rich tone (fundamental + 2nd/3rd/4th partials) — YIN must lock the fundamental.
        let f = try XCTUnwrap(PitchTracker.detect(sine(220, harmonics: [0.5, 0.33, 0.25]), sampleRate: sr))
        XCTAssertEqual(f, 220, accuracy: 1.5)
    }

    func testSilenceReturnsNil() {
        XCTAssertNil(PitchTracker.detect([Float](repeating: 0, count: 4096), sampleRate: sr))
    }

    func testWhiteNoiseIsRejected() {
        var seed: UInt64 = 0x1234_5678
        let noise: [Float] = (0..<4096).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int32(truncatingIfNeeded: seed >> 33)) / Float(Int32.max)
        }
        // Aperiodic → either nil or, at worst, not a stable musical pitch. We require nil.
        XCTAssertNil(PitchTracker.detect(noise, sampleRate: sr, threshold: 0.10))
    }

    func testTooShortWindowReturnsNil() {
        XCTAssertNil(PitchTracker.detect(sine(440, n: 128), sampleRate: sr))
    }

    func testEndToEndPitchToTuning() throws {
        // The full chain: synth tones → PitchTracker → TuningDetector recovers key+A4.
        let cMajor = [261.63, 293.66, 329.63, 349.23, 392.0, 440.0, 493.88, 523.25]
        var detected: [Double] = []
        for hz in cMajor + cMajor {
            if let f = PitchTracker.detect(sine(hz), sampleRate: sr) { detected.append(f) }
        }
        let r = try XCTUnwrap(TuningDetector().analyze(frequencies: detected))
        XCTAssertEqual(r.keyRoot, 0)            // C
        XCTAssertFalse(r.isMinor)
        XCTAssertEqual(r.a4Hz, 440, accuracy: 1.0)
    }
}
