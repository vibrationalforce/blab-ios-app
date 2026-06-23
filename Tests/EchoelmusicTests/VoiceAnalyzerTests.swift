// VoiceAnalyzerTests.swift
// Echoel — the voice analyser must recover pitch from a tone, read loudness on a
// perceptual dB scale, order brightness by spectral content, and refuse to "voice"
// silence or broadband noise. Pure → runs on every platform (the trustworthy INPUT
// half of the audiovisual vocoder).

import XCTest
@testable import Echoelmusic

final class VoiceAnalyzerTests: XCTestCase {

    private let sr = 48000.0
    private let analyzer = VoiceAnalyzer()

    /// `seconds` of a sine at `hz`, amplitude `amp`, optional white noise.
    private func sine(hz: Double, amp: Float = 0.5, seconds: Double = 0.05,
                      noise: Float = 0) -> [Float] {
        let n = Int(sr * seconds)
        var rng = SystemRandomNumberGenerator()
        return (0..<n).map { i in
            let t = Double(i) / sr
            var v = amp * Float(sin(2 * Double.pi * hz * t))
            if noise > 0 { v += Float.random(in: -noise...noise, using: &rng) }
            return v
        }
    }

    // MARK: - Pitch

    func testPitch_220Hz_isVoicedAndAccurate() {
        let f = analyzer.analyze(sine(hz: 220), sampleRate: sr)
        XCTAssertTrue(f.voiced)
        XCTAssertEqual(f.pitchHz, 220, accuracy: 5)
        // 220 Hz ≈ A3 = MIDI 57.
        XCTAssertEqual(f.midiNote ?? -1, 57, accuracy: 0.5)
    }

    func testPitch_440Hz_mapsToA4() {
        let f = analyzer.analyze(sine(hz: 440), sampleRate: sr)
        XCTAssertEqual(f.pitchHz, 440, accuracy: 6)
        XCTAssertEqual(f.midiNote ?? -1, 69, accuracy: 0.5)   // A4
        XCTAssertEqual(f.pitchClass, 9)                        // A
    }

    func testPitch_survivesNoise() {
        let f = analyzer.analyze(sine(hz: 196, noise: 0.15), sampleRate: sr)
        XCTAssertTrue(f.voiced)
        XCTAssertEqual(f.pitchHz, 196, accuracy: 8)            // ~G3
    }

    func testPitch_neverReportsBelowFloor() {
        // The analyser must never report an F0 below its band floor, whatever the
        // input (a sub-band tone may alias, but the reported Hz stays ≥ minF0).
        let f = analyzer.analyze(sine(hz: 40), sampleRate: sr)
        if f.voiced { XCTAssertGreaterThanOrEqual(f.pitchHz, 70) }
    }

    // MARK: - Voicing gate

    func testSilence_isUnvoicedAndSilent() {
        let f = analyzer.analyze([Float](repeating: 0, count: 2048), sampleRate: sr)
        XCTAssertFalse(f.voiced)
        XCTAssertEqual(f.energy, 0, accuracy: 1e-9)
        XCTAssertTrue(f.isSilent)
        XCTAssertNil(f.midiNote)
    }

    func testWhiteNoise_isNotStronglyVoiced() {
        var rng = SystemRandomNumberGenerator()
        let noise = (0..<2048).map { _ in Float.random(in: -0.5...0.5, using: &rng) }
        let f = analyzer.analyze(noise, sampleRate: sr)
        // Broadband noise must not masquerade as a clear pitch...
        XCTAssertFalse(f.voiced, "white noise should fail the periodicity gate")
        // ...and reads bright (high zero-crossing rate).
        XCTAssertGreaterThan(f.brightness, 0.5)
    }

    func testTooShort_isSilent() {
        let f = analyzer.analyze([0.1, -0.1, 0.1], sampleRate: sr)
        XCTAssertFalse(f.voiced)
    }

    // MARK: - Loudness (perceptual dB map)

    func testEnergy01_dBMapping() {
        XCTAssertEqual(analyzer.energy01(pow(10, -10.0 / 20)), 1.0, accuracy: 0.01) // ceil
        XCTAssertEqual(analyzer.energy01(pow(10, -50.0 / 20)), 0.0, accuracy: 0.01) // floor
        XCTAssertEqual(analyzer.energy01(pow(10, -30.0 / 20)), 0.5, accuracy: 0.01) // mid
        XCTAssertEqual(analyzer.energy01(0), 0)
    }

    func testEnergy_louderSine_readsHotter() {
        let quiet = analyzer.analyze(sine(hz: 220, amp: 0.05), sampleRate: sr)
        let loud = analyzer.analyze(sine(hz: 220, amp: 0.5), sampleRate: sr)
        XCTAssertGreaterThan(loud.energy, quiet.energy)
    }

    // MARK: - Brightness ordering

    func testBrightness_highToneBrighterThanLow() {
        let low = analyzer.analyze(sine(hz: 150), sampleRate: sr)
        let high = analyzer.analyze(sine(hz: 2000), sampleRate: sr)
        XCTAssertGreaterThan(high.brightness, low.brightness)
        XCTAssertGreaterThanOrEqual(low.brightness, 0)
        XCTAssertLessThanOrEqual(high.brightness, 1)
    }

    // MARK: - Mapping integration (voice → audiovisual)

    func testFeedsVocoderMapping() {
        let f = analyzer.analyze(sine(hz: 261.63), sampleRate: sr)   // ~C4
        let m = VocoderMapping.from(voice: f)
        XCTAssertNotNil(m.carrierMidi)
        XCTAssertEqual(m.carrierMidi ?? -1, 60, accuracy: 1)         // C4 = MIDI 60
        XCTAssertGreaterThan(m.level, 0)
    }
}
