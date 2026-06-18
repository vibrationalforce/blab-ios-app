// VocoderCoreTests.swift
// Echoel — the pure voice→audiovisual mapping (flagship vocoder foundation).
// Sound + image + light derived from one signal, flash-safe by construction.

import XCTest
@testable import Echoelmusic

final class VocoderCoreTests: XCTestCase {

    private func bio(hr: Float) -> BioSampleFrame {
        BioSampleFrame(timestamp: 0, heartRateBPM: hr, hrvNormalized: 0.5,
                       breathRate: 6, breathPhase: 0.5, coherence: 0.5,
                       motionEnergy: 0, source: .fallback)
    }

    // MARK: VoiceFrame

    func testMidiNote_referencePitches() {
        XCTAssertEqual(VoiceFrame(pitchHz: 440, voiced: true, energy: 0.5, brightness: 0.5).midiNote!, 69, accuracy: 0.01)
        XCTAssertEqual(VoiceFrame(pitchHz: 880, voiced: true, energy: 0.5, brightness: 0.5).midiNote!, 81, accuracy: 0.01)
        XCTAssertNil(VoiceFrame(pitchHz: 0, voiced: false, energy: 0, brightness: 0).midiNote)
    }

    func testPitchClass() {
        XCTAssertEqual(VoiceFrame(pitchHz: 440, voiced: true, energy: 0.5, brightness: 0.5).pitchClass, 9) // A
        XCTAssertEqual(VoiceFrame(pitchHz: 261.63, voiced: true, energy: 0.5, brightness: 0.5).pitchClass, 0) // C
    }

    func testIsSilent() {
        XCTAssertTrue(VoiceFrame(pitchHz: 0, voiced: false, energy: 0.9, brightness: 0.5).isSilent)
        XCTAssertTrue(VoiceFrame(pitchHz: 200, voiced: true, energy: 0.0, brightness: 0.5).isSilent)
        XCTAssertFalse(VoiceFrame(pitchHz: 200, voiced: true, energy: 0.5, brightness: 0.5).isSilent)
    }

    // MARK: Mapping — sound

    func testVoiced_setsCarrierAndLevel() {
        let m = VocoderMapping.from(voice: VoiceFrame(pitchHz: 440, voiced: true, energy: 0.7, brightness: 0.5))
        XCTAssertEqual(m.carrierMidi, 69)
        XCTAssertEqual(m.level, 0.7, accuracy: 1e-9)
    }

    func testCarrier_clampedToMidiRange() {
        let m = VocoderMapping.from(voice: VoiceFrame(pitchHz: 20000, voiced: true, energy: 0.5, brightness: 0.5))
        XCTAssertLessThanOrEqual(m.carrierMidi ?? 0, 127)
        XCTAssertGreaterThanOrEqual(m.carrierMidi ?? 0, 0)
    }

    func testBrightness_drivesFormant() {
        XCTAssertEqual(VocoderMapping.from(voice: VoiceFrame(pitchHz: 200, voiced: true, energy: 0.5, brightness: 0)).formantShift, -1, accuracy: 1e-9)
        XCTAssertEqual(VocoderMapping.from(voice: VoiceFrame(pitchHz: 200, voiced: true, energy: 0.5, brightness: 1)).formantShift, 1, accuracy: 1e-9)
        XCTAssertEqual(VocoderMapping.from(voice: VoiceFrame(pitchHz: 200, voiced: true, energy: 0.5, brightness: 0.5)).formantShift, 0, accuracy: 1e-9)
    }

    // MARK: Mapping — visual + light

    func testHue_fromPitchClass_inRange() {
        for hz in [261.63, 293.66, 440.0, 493.88] {
            let m = VocoderMapping.from(voice: VoiceFrame(pitchHz: hz, voiced: true, energy: 0.5, brightness: 0.5))
            XCTAssertGreaterThanOrEqual(m.hue, 0)
            XCTAssertLessThan(m.hue, 1)
        }
    }

    func testRGB_inRange_andDarkWhenQuiet() {
        let loud = VocoderMapping.from(voice: VoiceFrame(pitchHz: 440, voiced: true, energy: 1.0, brightness: 0.5))
        for c in [loud.red, loud.green, loud.blue] { XCTAssertTrue(c >= 0 && c <= 1) }
        XCTAssertGreaterThan(max(loud.red, max(loud.green, loud.blue)), 0.5, "loud → bright light")
    }

    // MARK: Flash safety

    func testPulse_flashSafe_andFromBioNotVoice() {
        let m = VocoderMapping.from(voice: VoiceFrame(pitchHz: 440, voiced: true, energy: 1, brightness: 1),
                                    bio: bio(hr: 600))
        XCTAssertLessThanOrEqual(m.pulseHz, FlashGuard.maxFlashHz)
        XCTAssertGreaterThan(m.pulseHz, 0)
    }

    func testReduceMotion_freezesPulse() {
        let m = VocoderMapping.from(voice: VoiceFrame(pitchHz: 440, voiced: true, energy: 1, brightness: 1),
                                    bio: bio(hr: 120), reduceMotion: true)
        XCTAssertEqual(m.pulseHz, 0, accuracy: 1e-9)
    }

    // MARK: Silence

    func testSilent_isDarkAndUntoned_butKeepsHeartbeat() {
        let m = VocoderMapping.from(voice: .silent, bio: bio(hr: 60))
        XCTAssertNil(m.carrierMidi)
        XCTAssertEqual(m.level, 0, accuracy: 1e-9)
        XCTAssertEqual(m.red + m.green + m.blue, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(m.pulseHz, 0, "heartbeat pulse survives silence")
    }

    func testSilentNoBio_isFullyZero() {
        let m = VocoderMapping.from(voice: .silent)
        XCTAssertEqual(m.pulseHz, 0, accuracy: 1e-9)
        XCTAssertNil(m.carrierMidi)
    }
}
