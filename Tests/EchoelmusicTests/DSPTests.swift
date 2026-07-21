#if canImport(AVFoundation)
// DSPTests.swift
// Echoelmusic — Phase 2 Test Coverage: DSP Engine Tests
//
// Tests for EchoelDDSP + EchoelPolyDDSP render/bio-reactive paths and crash-hardening.
// (Analog-emulation + CrossfadeCurve/CrossfadeRegion suites removed 2026-07-21 —
//  those subsystems no longer exist in Sources.)

import XCTest
@testable import Echoelmusic

// MARK: - EchoelDDSP Tests

final class EchoelDDSPTests: XCTestCase {

    func testInitialization() {
        let ddsp = EchoelDDSP(harmonicCount: 32, noiseBandCount: 33, sampleRate: 48000, frameSize: 256)
        XCTAssertEqual(ddsp.harmonicCount, 32)
        XCTAssertEqual(ddsp.noiseBandCount, 33)
        XCTAssertEqual(ddsp.sampleRate, 48000)
        XCTAssertEqual(ddsp.frameSize, 256)
    }

    func testDefaultParameters() {
        let ddsp = EchoelDDSP()
        XCTAssertEqual(ddsp.harmonicCount, 64)
        XCTAssertEqual(ddsp.frequency, 220.0)
        XCTAssertEqual(ddsp.harmonicLevel, 0.8, accuracy: 0.01)
        XCTAssertEqual(ddsp.harmonicity, 0.7, accuracy: 0.01)
        XCTAssertEqual(ddsp.noiseLevel, 0.3, accuracy: 0.01)
        XCTAssertEqual(ddsp.amplitude, 0.8, accuracy: 0.01)
    }

    func testHarmonicAmplitudesCount() {
        let ddsp = EchoelDDSP(harmonicCount: 16)
        XCTAssertEqual(ddsp.harmonicAmplitudes.count, 16)
    }

    func testNoiseMagnitudesCount() {
        let ddsp = EchoelDDSP(noiseBandCount: 33)
        XCTAssertEqual(ddsp.noiseMagnitudes.count, 33)
    }

    func testNoiseColorCases() {
        let cases = EchoelDDSP.NoiseColor.allCases
        XCTAssertEqual(cases.count, 5)
        XCTAssertTrue(cases.contains(.white))
        XCTAssertTrue(cases.contains(.pink))
        XCTAssertTrue(cases.contains(.brown))
        XCTAssertTrue(cases.contains(.blue))
        XCTAssertTrue(cases.contains(.violet))
    }

    func testSpectralShapeCases() {
        let cases = EchoelDDSP.SpectralShape.allCases
        XCTAssertEqual(cases.count, 8)
        XCTAssertTrue(cases.contains(.natural))
        XCTAssertTrue(cases.contains(.bright))
        XCTAssertTrue(cases.contains(.dark))
        XCTAssertTrue(cases.contains(.formant))
        XCTAssertTrue(cases.contains(.metallic))
        XCTAssertTrue(cases.contains(.hollow))
        XCTAssertTrue(cases.contains(.bell))
        XCTAssertTrue(cases.contains(.flat))
    }

    func testEnvelopeCurveCases() {
        let cases = EchoelDDSP.EnvelopeCurve.allCases
        XCTAssertEqual(cases.count, 3)
        XCTAssertTrue(cases.contains(.linear))
        XCTAssertTrue(cases.contains(.exponential))
        XCTAssertTrue(cases.contains(.logarithmic))
    }

    func testFrequencyRange() {
        let ddsp = EchoelDDSP()
        ddsp.frequency = 440.0
        XCTAssertEqual(ddsp.frequency, 440.0)

        ddsp.frequency = 20.0
        XCTAssertEqual(ddsp.frequency, 20.0)

        ddsp.frequency = 20000.0
        XCTAssertEqual(ddsp.frequency, 20000.0)
    }

    func testADSRParameters() {
        let ddsp = EchoelDDSP()
        ddsp.attack = 0.05
        ddsp.decay = 0.2
        ddsp.sustain = 0.6
        ddsp.release = 0.5

        XCTAssertEqual(ddsp.attack, 0.05, accuracy: 0.001)
        XCTAssertEqual(ddsp.decay, 0.2, accuracy: 0.001)
        XCTAssertEqual(ddsp.sustain, 0.6, accuracy: 0.001)
        XCTAssertEqual(ddsp.release, 0.5, accuracy: 0.001)
    }

    func testVibratoParameters() {
        let ddsp = EchoelDDSP()
        ddsp.vibratoRate = 5.5
        ddsp.vibratoDepth = 0.3

        XCTAssertEqual(ddsp.vibratoRate, 5.5, accuracy: 0.01)
        XCTAssertEqual(ddsp.vibratoDepth, 0.3, accuracy: 0.01)
    }

    func testSpectralMorphing() {
        let ddsp = EchoelDDSP()
        XCTAssertNil(ddsp.morphTarget)
        XCTAssertEqual(ddsp.morphPosition, 0)

        ddsp.morphTarget = .metallic
        ddsp.morphPosition = 0.5
        XCTAssertEqual(ddsp.morphTarget, .metallic)
        XCTAssertEqual(ddsp.morphPosition, 0.5, accuracy: 0.01)
    }

    func testTimbreTransfer() {
        let ddsp = EchoelDDSP()
        XCTAssertNil(ddsp.timbreProfile)
        XCTAssertEqual(ddsp.timbreBlend, 0)

        let profile: [Float] = Array(repeating: 0.5, count: 64)
        ddsp.timbreProfile = profile
        ddsp.timbreBlend = 0.7
        XCTAssertNotNil(ddsp.timbreProfile)
        XCTAssertEqual(ddsp.timbreBlend, 0.7, accuracy: 0.01)
    }

    func testReverbParameters() {
        let ddsp = EchoelDDSP()
        XCTAssertEqual(ddsp.reverbMix, 0.0, accuracy: 0.001)
        ddsp.reverbMix = 0.4
        ddsp.reverbDecay = 2.5
        XCTAssertEqual(ddsp.reverbMix, 0.4, accuracy: 0.01)
        XCTAssertEqual(ddsp.reverbDecay, 2.5, accuracy: 0.01)
    }
}

// MARK: - EchoelDDSP Render Tests

final class EchoelDDSPRenderTests: XCTestCase {

    func testRenderProducesOutput() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.noteOn(frequency: 440)
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        let hasNonZero = buffer.contains { $0 != 0 }
        XCTAssertTrue(hasNonZero, "DDSP should produce non-zero output after noteOn")
    }

    func testRenderNaNGuard() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.noteOn(frequency: 440)
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN, "DDSP render must not produce NaN")
            XCTAssertFalse(sample.isInfinite, "DDSP render must not produce Inf")
        }
    }

    func testRenderStereo() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 128)
        ddsp.noteOn(frequency: 440)
        var buffer = [Float](repeating: 0, count: 256) // 128 frames * 2 channels
        ddsp.render(buffer: &buffer, frameCount: 128, stereo: true)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN)
            XCTAssertFalse(sample.isInfinite)
        }
    }

    func testRenderZeroFrameCount() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.noteOn(frequency: 440)
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 0)
        // Buffer should remain all zeros
        for sample in buffer {
            XCTAssertEqual(sample, 0)
        }
    }

    func testRenderExtremeFrequency() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.noteOn(frequency: 22000) // Near Nyquist
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN, "High frequency must not produce NaN")
            XCTAssertFalse(sample.isInfinite, "High frequency must not produce Inf")
        }
    }

    func testRenderSilenceBeforeNoteOn() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        for sample in buffer {
            XCTAssertEqual(sample, 0, accuracy: 0.001, "Should be silent before noteOn")
        }
    }

    func testAllSpectralShapesRender() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 128)
        for shape in EchoelDDSP.SpectralShape.allCases {
            ddsp.spectralShape = shape
            ddsp.noteOn(frequency: 440)
            var buffer = [Float](repeating: 0, count: 128)
            ddsp.render(buffer: &buffer, frameCount: 128)
            for sample in buffer {
                XCTAssertFalse(sample.isNaN, "NaN with shape \(shape)")
                XCTAssertFalse(sample.isInfinite, "Inf with shape \(shape)")
            }
        }
    }
}

// MARK: - EchoelPolyDDSP Render Tests

final class EchoelPolyDDSPRenderTests: XCTestCase {

    func testRenderStereoOutput() {
        let poly = EchoelPolyDDSP(maxVoices: 4, sampleRate: 48000)
        poly.noteOn(note: 60, velocity: 0.8)
        var left = [Float](repeating: 0, count: 256)
        var right = [Float](repeating: 0, count: 256)
        poly.renderStereo(left: &left, right: &right, frameCount: 256)
        let hasOutput = left.contains { $0 != 0 } || right.contains { $0 != 0 }
        XCTAssertTrue(hasOutput, "PolyDDSP should produce output after noteOn")
    }

    func testRenderNaNGuard() {
        let poly = EchoelPolyDDSP(maxVoices: 4, sampleRate: 48000)
        poly.noteOn(note: 60, velocity: 0.8)
        var left = [Float](repeating: 0, count: 256)
        var right = [Float](repeating: 0, count: 256)
        poly.renderStereo(left: &left, right: &right, frameCount: 256)
        for i in 0..<256 {
            XCTAssertFalse(left[i].isNaN, "Left NaN at \(i)")
            XCTAssertFalse(right[i].isNaN, "Right NaN at \(i)")
            XCTAssertFalse(left[i].isInfinite, "Left Inf at \(i)")
            XCTAssertFalse(right[i].isInfinite, "Right Inf at \(i)")
        }
    }

    func testVoiceStealing() {
        let poly = EchoelPolyDDSP(maxVoices: 2, sampleRate: 48000, frameSize: 128)
        // Exceed max voices
        poly.noteOn(note: 60, velocity: 0.8)
        poly.noteOn(note: 64, velocity: 0.8)
        poly.noteOn(note: 67, velocity: 0.8) // Should steal a voice
        XCTAssertLessThanOrEqual(poly.activeVoiceCount, 2, "Should not exceed maxVoices")
        var left = [Float](repeating: 0, count: 128)
        var right = [Float](repeating: 0, count: 128)
        poly.renderStereo(left: &left, right: &right, frameCount: 128)
        for i in 0..<128 {
            XCTAssertFalse(left[i].isNaN, "Voice stealing must not produce NaN")
        }
    }

    func testAllNotesOff() {
        let poly = EchoelPolyDDSP(maxVoices: 4, sampleRate: 48000, frameSize: 128)
        poly.noteOn(note: 60, velocity: 0.8)
        poly.noteOn(note: 64, velocity: 0.8)
        poly.allNotesOff()
        XCTAssertEqual(poly.activeVoiceCount, 0, "All voices should be off")
    }

    func testUnisonOffSpawnsOneVoice() {
        let poly = EchoelPolyDDSP(maxVoices: 6, sampleRate: 48000, frameSize: 128)
        poly.setUnison(count: 1, detuneCents: 12)   // count 1 = off regardless of detune
        poly.noteOn(note: 60, velocity: 0.8)
        XCTAssertEqual(poly.activeVoiceCount, 1, "Unison off → one voice per note")
    }

    func testUnisonStacksDetunedVoices() {
        let poly = EchoelPolyDDSP(maxVoices: 6, sampleRate: 48000, frameSize: 128)
        poly.setUnison(count: 3, detuneCents: 14)
        poly.noteOn(note: 60, velocity: 0.8)
        XCTAssertEqual(poly.activeVoiceCount, 3, "Unison 3 → three voices for one note")
        // A single noteOff releases the whole stack (they share the note tag).
        poly.noteOff(note: 60)
        XCTAssertEqual(poly.activeVoiceCount, 0, "noteOff releases the entire unison stack")
    }

    func testUnisonClampedToMax() {
        let poly = EchoelPolyDDSP(maxVoices: 8, sampleRate: 48000, frameSize: 128)
        poly.setUnison(count: 99, detuneCents: 999)
        poly.noteOn(note: 60, velocity: 0.8)
        XCTAssertEqual(poly.activeVoiceCount, EchoelPolyDDSP.maxUnison,
                       "Unison count clamps to maxUnison")
    }

    func testUnisonRenderIsFinite() {
        let poly = EchoelPolyDDSP(maxVoices: 6, sampleRate: 48000, frameSize: 128)
        poly.setUnison(count: 3, detuneCents: 20)
        poly.noteOn(note: 57, velocity: 1.0)
        var left = [Float](repeating: 0, count: 128)
        var right = [Float](repeating: 0, count: 128)
        poly.renderStereo(left: &left, right: &right, frameCount: 128)
        for i in 0..<128 {
            XCTAssertTrue(left[i].isFinite && right[i].isFinite, "Unison render finite at \(i)")
        }
    }
}
// MARK: - DSP Crash Hardening Tests

final class DSPCrashHardeningTests: XCTestCase {

    // MARK: - EchoelDDSP Edge Cases

    func testDDSP_ZeroFrequency() {
        let ddsp = EchoelDDSP()
        ddsp.frequency = 0.0
        // Should not crash or produce NaN
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN, "Zero frequency should not produce NaN")
            XCTAssertFalse(sample.isInfinite, "Zero frequency should not produce Inf")
        }
    }

    func testDDSP_ExtremeFrequency() {
        let ddsp = EchoelDDSP()
        ddsp.frequency = 22050.0 // Nyquist
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN, "Nyquist frequency should not produce NaN")
        }
    }

    func testDDSP_ZeroAmplitude() {
        let ddsp = EchoelDDSP()
        ddsp.amplitude = 0.0
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        // All samples should be zero or near-zero
        let maxAbs = buffer.map { abs($0) }.max() ?? 0
        XCTAssertLessThan(maxAbs, 0.001, "Zero amplitude should produce silence")
    }

    func testDDSP_ZeroFrameCount() {
        let ddsp = EchoelDDSP()
        var buffer = [Float](repeating: 0, count: 0)
        // Must not crash or grow the buffer with an empty render.
        ddsp.render(buffer: &buffer, frameCount: 0)
        XCTAssertEqual(buffer.count, 0, "empty render must leave the buffer empty")
    }

    func testDDSP_SingleFrame() {
        let ddsp = EchoelDDSP()
        var buffer = [Float](repeating: 0, count: 1)
        ddsp.render(buffer: &buffer, frameCount: 1)
        XCTAssertFalse(buffer[0].isNaN, "Single frame should not produce NaN")
    }

    func testDDSP_BioReactiveWithZeroCoherence() {
        let ddsp = EchoelDDSP()
        ddsp.applyBioReactive(coherence: 0.0, hrvVariability: 0.0, heartRate: 0.0, breathPhase: 0.0, breathDepth: 0.0)
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN, "Zero bio values should not produce NaN")
        }
    }

    func testDDSP_BioReactiveWithExtremeValues() {
        let ddsp = EchoelDDSP()
        ddsp.applyBioReactive(coherence: 1.0, hrvVariability: 1.0, heartRate: 200.0, breathPhase: 1.0, breathDepth: 1.0)
        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN, "Extreme bio values should not produce NaN")
            XCTAssertFalse(sample.isInfinite, "Extreme bio values should not produce Inf")
        }
    }
}
#endif
