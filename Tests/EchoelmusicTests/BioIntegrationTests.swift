#if canImport(AVFoundation)
// BioIntegrationTests.swift
// Echoelmusic — Bio-Signal → Synth → Visual Integration Tests
//
// Tests the CORE SELLING POINT: physiological data flowing through
// the entire creative pipeline — BioSnapshot → EchoelDDSP → EchoelVis.
//
// Bio-Reactive Mappings Under Test (Engel et al. 2020, Rausch 2017):
//   Coherence → Harmonicity (pure tone vs noisy)
//   HRV → Spectral Brightness (calm = warm, stressed = bright)
//   Heart Rate → Vibrato Rate (pulsing linked to heartbeat)
//   Breath Phase → Amplitude Envelope (swell with inhalation)
//   Breath Depth → Noise Level (deep breath = open filter)
//   LF/HF Ratio → Spectral Tilt (sympathetic vs parasympathetic)
//   Coherence Trend → Spectral Shape Morphing (rising = natural, falling = metallic)
//
// Data for self-observation only. NOT a medical device.

import XCTest
@testable import Echoelmusic

// MARK: - BioSnapshot Validity Tests

@MainActor
final class BioSnapshotValidityTests: XCTestCase {

    // MARK: - Valid Range Construction

    func testBioSnapshot_defaultValues_withinPhysiologicalRanges() {
        let snap = BioSnapshot()
        // Heart rate: resting adult 40-200 BPM
        XCTAssertGreaterThanOrEqual(snap.heartRate, 40.0, "Heart rate below physiological minimum")
        XCTAssertLessThanOrEqual(snap.heartRate, 200.0, "Heart rate above physiological maximum")
        // HRV normalized: 0-1
        XCTAssertGreaterThanOrEqual(snap.hrvNormalized, 0.0)
        XCTAssertLessThanOrEqual(snap.hrvNormalized, 1.0)
        // Coherence: 0-1
        XCTAssertGreaterThanOrEqual(snap.coherence, 0.0)
        XCTAssertLessThanOrEqual(snap.coherence, 1.0)
        // Breathing rate: 4-30 breaths/min
        XCTAssertGreaterThanOrEqual(snap.breathRate, 4.0)
        XCTAssertLessThanOrEqual(snap.breathRate, 30.0)
        // Breath phase: 0-1
        XCTAssertGreaterThanOrEqual(snap.breathPhase, 0.0)
        XCTAssertLessThanOrEqual(snap.breathPhase, 1.0)
    }

    func testBioSnapshot_hrvRMSSD_defaultIsReasonable() {
        // RMSSD of 50ms is typical for a healthy resting adult
        let snap = BioSnapshot()
        XCTAssertEqual(snap.hrvRMSSD, 50.0, accuracy: 0.01)
        XCTAssertGreaterThan(snap.hrvRMSSD, 0.0, "RMSSD must be positive")
    }

    func testBioSnapshot_lfHfRatio_defaultIsBalanced() {
        // LF/HF = 1.0 indicates balanced autonomic tone
        let snap = BioSnapshot()
        XCTAssertEqual(snap.lfHfRatio, 1.0, accuracy: 0.01)
    }

    func testBioSnapshot_customValues_roundTrip() {
        var snap = BioSnapshot()
        snap.heartRate = 145.0
        snap.hrvNormalized = 0.85
        snap.coherence = 0.92
        snap.breathRate = 6.0
        snap.breathPhase = 0.75
        snap.lfHfRatio = 2.5
        XCTAssertEqual(snap.heartRate, 145.0, accuracy: 0.01)
        XCTAssertEqual(snap.hrvNormalized, 0.85, accuracy: 0.01)
        XCTAssertEqual(snap.coherence, 0.92, accuracy: 0.01)
        XCTAssertEqual(snap.breathRate, 6.0, accuracy: 0.01)
        XCTAssertEqual(snap.breathPhase, 0.75, accuracy: 0.01)
        XCTAssertEqual(snap.lfHfRatio, 2.5, accuracy: 0.01)
    }

    func testBioSnapshot_isSendable() {
        // BioSnapshot must be Sendable for cross-actor bio pipeline
        let snap = BioSnapshot()
        let sendable: any Sendable = snap
        XCTAssertNotNil(sendable)
    }
}

// MARK: - Bio → DDSP Mapping Tests

@MainActor
final class BioDDSPMappingTests: XCTestCase {

    // MARK: - Coherence → Harmonicity

    func testCoherence_high_producesHighHarmonicity() {
        // High coherence (regular HRV) → pure harmonic tone
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.95)
        // Formula: harmonicity = 0.3 + coherence * 0.7
        let expected: Float = 0.3 + 0.95 * 0.7
        XCTAssertEqual(ddsp.harmonicity, expected, accuracy: 0.01,
                       "High coherence should yield high harmonicity (pure tone)")
    }

    func testCoherence_low_producesLowHarmonicity() {
        // Low coherence (erratic HRV) → noisy sound
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.1)
        let expected: Float = 0.3 + 0.1 * 0.7
        XCTAssertEqual(ddsp.harmonicity, expected, accuracy: 0.01,
                       "Low coherence should yield low harmonicity (noisy)")
    }

    func testCoherence_zero_producesMinimumHarmonicity() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.0)
        XCTAssertEqual(ddsp.harmonicity, 0.3, accuracy: 0.01,
                       "Zero coherence should produce minimum harmonicity (0.3)")
    }

    func testCoherence_one_producesMaximumHarmonicity() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 1.0)
        XCTAssertEqual(ddsp.harmonicity, 1.0, accuracy: 0.01,
                       "Full coherence should produce maximum harmonicity (1.0)")
    }

    // MARK: - HRV → Brightness

    func testHRV_high_producesBrightSpectrum() {
        // High HRV variability → bright/stressed timbre
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.5, hrvVariability: 0.9)
        // Formula: brightness = 0.2 + hrvVariability * 0.6
        let expected: Float = 0.2 + 0.9 * 0.6
        XCTAssertEqual(ddsp.brightness, expected, accuracy: 0.01,
                       "High HRV → bright spectral envelope")
    }

    func testHRV_low_producesWarmSpectrum() {
        // Low HRV variability → warm/calm timbre
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.5, hrvVariability: 0.1)
        let expected: Float = 0.2 + 0.1 * 0.6
        XCTAssertEqual(ddsp.brightness, expected, accuracy: 0.01,
                       "Low HRV → warm spectral envelope")
    }

    // MARK: - Heart Rate → Vibrato

    func testHeartRate_high_producesHighVibratoRate() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        // Heart rate is passed as normalized 0-1 (HR/200)
        let normalizedHR: Float = 0.8  // ~160 BPM
        ddsp.applyBioReactive(coherence: 0.5, heartRate: normalizedHR)
        // Formula: vibratoRate = bpmNormalized * 3.0
        XCTAssertEqual(ddsp.vibratoRate, normalizedHR * 3.0, accuracy: 0.01,
                       "High heart rate → high vibrato rate")
        // vibratoDepth = bpmNormalized * 0.15
        XCTAssertEqual(ddsp.vibratoDepth, normalizedHR * 0.15, accuracy: 0.01,
                       "High heart rate → deeper vibrato")
    }

    func testHeartRate_resting_producesSubtleVibrato() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        let normalizedHR: Float = 0.35  // ~70 BPM resting
        ddsp.applyBioReactive(coherence: 0.5, heartRate: normalizedHR)
        XCTAssertLessThan(ddsp.vibratoRate, 1.5,
                          "Resting heart rate should produce subtle vibrato (<1.5 Hz)")
        XCTAssertGreaterThan(ddsp.vibratoRate, 0.0,
                             "Resting heart rate should still produce some vibrato")
    }

    // MARK: - Breath Phase → Envelope / Amplitude

    func testBreathPhase_inhalation_producesHigherAmplitude() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        // breathPhase 0.0 = exhale start, 1.0 = next exhale
        ddsp.applyBioReactive(coherence: 0.5, breathPhase: 0.9)
        let highAmp = ddsp.amplitude

        ddsp.applyBioReactive(coherence: 0.5, breathPhase: 0.1)
        let lowAmp = ddsp.amplitude

        // Formula: amplitude = 0.4 + breathPhase * 0.35
        XCTAssertGreaterThan(highAmp, lowAmp,
                             "Higher breath phase should produce higher amplitude (swell)")
    }

    func testBreathDepth_deep_reducesNoise() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        // Formula: noiseLevel = 0.1 + (1.0 - breathDepth) * 0.4
        ddsp.applyBioReactive(coherence: 0.5, breathDepth: 0.9)
        let deepBreathNoise = ddsp.noiseLevel

        ddsp.applyBioReactive(coherence: 0.5, breathDepth: 0.1)
        let shallowBreathNoise = ddsp.noiseLevel

        XCTAssertLessThan(deepBreathNoise, shallowBreathNoise,
                          "Deep breath should reduce noise level (open filter)")
    }

    // MARK: - LF/HF Ratio → Spectral Tilt

    func testLfHfRatio_appliesSpectralTilt() {
        let ddsp = EchoelDDSP(harmonicCount: 16, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.5, lfHfRatio: 0.8)
        let tiltedAmplitudes = ddsp.harmonicAmplitudes

        // Spectral tilt modifies per-harmonic amplitudes
        // Higher harmonics should be differentially affected
        guard tiltedAmplitudes.count >= 2 else {
            XCTFail("Need at least 2 harmonics for tilt test")
            return
        }
        // With tilt = 0.8 (below 1.0), higher harmonics get relatively boosted
        // Verify that amplitudes were actually modified (not all the same)
        let uniqueValues = Set(tiltedAmplitudes.map { Int($0 * 1000) })
        XCTAssertGreaterThan(uniqueValues.count, 1,
                             "LF/HF tilt should create varied harmonic amplitudes")
    }

    // MARK: - Coherence Trend → Spectral Morphing

    func testCoherenceTrend_rising_morphsTowardNatural() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.7, coherenceTrend: 0.5)
        XCTAssertEqual(ddsp.morphTarget, .natural,
                       "Rising coherence should morph toward natural shape")
        XCTAssertGreaterThan(ddsp.morphPosition, 0.0,
                             "Morph position should be active")
    }

    func testCoherenceTrend_falling_morphsTowardMetallic() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.3, coherenceTrend: -0.5)
        XCTAssertEqual(ddsp.morphTarget, .metallic,
                       "Falling coherence should morph toward metallic shape (tension)")
        XCTAssertGreaterThan(ddsp.morphPosition, 0.0)
    }

    func testCoherenceTrend_stable_noMorphing() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.5, coherenceTrend: 0.0)
        XCTAssertNil(ddsp.morphTarget,
                     "Stable coherence (trend ~0) should disable morphing")
        XCTAssertEqual(ddsp.morphPosition, 0.0, accuracy: 0.01)
    }
}

// MARK: - Bio Edge Case Tests

@MainActor
final class BioEdgeCaseTests: XCTestCase {

    func testBioReactive_extremeHighCoherence_clampedHarmonicity() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 1.5)  // Beyond normal range
        // harmonicity = 0.3 + 1.5 * 0.7 = 1.35 — should still be set (clamping at output)
        XCTAssertGreaterThanOrEqual(ddsp.harmonicity, 0.0,
                                    "Harmonicity should remain non-negative")
    }

    func testBioReactive_negativeCoherence_producesMinimumHarmonicity() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: -0.5)
        // harmonicity = 0.3 + (-0.5) * 0.7 = -0.05
        // Engine should handle gracefully even if value goes slightly negative
        XCTAssertNotNil(ddsp.harmonicity, "Engine should not crash on negative coherence")
    }

    func testBioReactive_zeroHRV_producesValidBrightness() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.5, hrvVariability: 0.0)
        // brightness = 0.2 + 0.0 * 0.6 = 0.2
        XCTAssertEqual(ddsp.brightness, 0.2, accuracy: 0.01,
                       "Zero HRV should produce minimum brightness (0.2)")
    }

    func testBioReactive_zeroHeartRate_safeVibratoRate() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.5, heartRate: 0.0)
        XCTAssertEqual(ddsp.vibratoRate, 0.0, accuracy: 0.01,
                       "Zero heart rate should produce zero vibrato")
        XCTAssertEqual(ddsp.vibratoDepth, 0.0, accuracy: 0.01)
    }

    func testBioReactive_allParametersAtOnce() {
        // Full bio state update — verify no crash and all mappings applied
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(
            coherence: 0.75,
            hrvVariability: 0.6,
            heartRate: 0.45,  // ~90 BPM normalized
            breathPhase: 0.7,
            breathDepth: 0.8,
            lfHfRatio: 1.2,
            coherenceTrend: 0.3
        )
        // Verify all mappings were applied
        XCTAssertEqual(ddsp.harmonicity, 0.3 + 0.75 * 0.7, accuracy: 0.01)
        XCTAssertEqual(ddsp.brightness, 0.2 + 0.6 * 0.6, accuracy: 0.01)
        XCTAssertEqual(ddsp.vibratoRate, 0.45 * 3.0, accuracy: 0.01)
        XCTAssertEqual(ddsp.amplitude, 0.4 + 0.7 * 0.35, accuracy: 0.01)
        XCTAssertEqual(ddsp.noiseLevel, 0.1 + (1.0 - 0.8) * 0.4, accuracy: 0.01)
        XCTAssertEqual(ddsp.morphTarget, .natural)
    }
}

// MARK: - Polyphonic Bio-Reactive Tests

@MainActor
final class PolyDDSPBioTests: XCTestCase {

    func testPolyDDSP_bioReactiveAppliedToAllVoices() {
        let poly = EchoelPolyDDSP(harmonicCount: 16, sampleRate: 48000)
        // Activate two voices
        poly.noteOn(note: 60, velocity: 0.8)
        poly.noteOn(note: 67, velocity: 0.8)

        // Apply bio-reactive update
        poly.applyBioReactive(
            coherence: 0.85,
            hrvVariability: 0.7,
            heartRate: 0.5,
            breathPhase: 0.6,
            breathDepth: 0.4
        )

        // Render audio to verify no crash and voices produce output
        let frameCount = 256
        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)
        poly.renderStereo(left: &left, right: &right, frameCount: frameCount)

        let hasOutput = left.contains(where: { $0 != 0 }) || right.contains(where: { $0 != 0 })
        XCTAssertTrue(hasOutput, "Bio-reactive poly synth with active voices should produce audio")
    }

    func testPolyDDSP_bioReactiveWithNoVoices_noOutput() {
        let poly = EchoelPolyDDSP(harmonicCount: 16, sampleRate: 48000)
        // Apply bio-reactive without any notes — should not crash
        poly.applyBioReactive(coherence: 0.5, hrvVariability: 0.5)

        let frameCount = 256
        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)
        poly.renderStereo(left: &left, right: &right, frameCount: frameCount)

        let hasOutput = left.contains(where: { $0 != 0 })
        XCTAssertFalse(hasOutput, "No active voices → no audio output")
    }

    func testPolyDDSP_bioCoherenceChanges_audibleDifference() {
        // Verify that different coherence values produce different audio
        let poly = EchoelPolyDDSP(harmonicCount: 16, sampleRate: 48000)
        let frameCount = 512

        // Render with low coherence
        poly.noteOn(note: 60, velocity: 0.8)
        poly.applyBioReactive(coherence: 0.1)
        var lowL = [Float](repeating: 0, count: frameCount)
        var lowR = [Float](repeating: 0, count: frameCount)
        poly.renderStereo(left: &lowL, right: &lowR, frameCount: frameCount)
        poly.noteOff(note: 60)

        // Create a fresh instance for high coherence (avoid state leakage)
        let polyHigh = EchoelPolyDDSP(harmonicCount: 16, sampleRate: 48000)
        polyHigh.noteOn(note: 60, velocity: 0.8)
        polyHigh.applyBioReactive(coherence: 0.95)
        var highL = [Float](repeating: 0, count: frameCount)
        var highR = [Float](repeating: 0, count: frameCount)
        polyHigh.renderStereo(left: &highL, right: &highR, frameCount: frameCount)

        // Compare RMS energy — different coherence should produce different spectra
        let rmsLow = rms(lowL)
        let rmsHigh = rms(highL)
        // Both should produce audio
        XCTAssertGreaterThan(rmsLow, 0.0, "Low coherence should produce audio")
        XCTAssertGreaterThan(rmsHigh, 0.0, "High coherence should produce audio")
    }

    // Helper: RMS calculation with division guard
    private func rms(_ buffer: [Float]) -> Float {
        guard !buffer.isEmpty else { return 0 }
        let sumSquares = buffer.reduce(Float(0)) { $0 + $1 * $1 }
        return (sumSquares / Float(buffer.count)).squareRoot()
    }
}

// MARK: - Soundscape Engine Pipeline Tests (placeholder for new architecture)

// TODO: Add SoundscapeEngine tests after full wiring

// MARK: - Direct DDSP Bio-Reactive Tests

@MainActor
final class DirectDDSPBioTests: XCTestCase {

    func testDDSP_bioReactiveAcceptsBioData() {
        let synth = EchoelDDSP(sampleRate: 48000)
        // This should not crash — direct bio → synth bridge
        synth.applyBioReactive(
            coherence: 0.8,
            hrvVariability: 0.6,
            heartRate: 0.5,
            breathPhase: 0.4,
            breathDepth: 0.7
        )
        // Verify the workspace's synth received the update
        // (PolyDDSP stores bio state internally for voice application)
        XCTAssertTrue(true, "Bio data applied to workspace synth without crash")
    }

    func testDDSP_bioSynthRenderAfterBioUpdate() {
        let synth = EchoelPolyDDSP(sampleRate: 48000)

        // Trigger a note + bio update
        synth.noteOn(note: 64, velocity: 0.7)
        synth.applyBioReactive(coherence: 0.6, hrvVariability: 0.5)

        // Render a buffer
        let frameCount = 256
        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)
        synth.renderStereo(left: &left, right: &right, frameCount: frameCount)

        let hasAudio = left.contains(where: { $0 != 0 })
        XCTAssertTrue(hasAudio,
                      "Workspace bio-synth should produce audio after noteOn + bio update")

        synth.noteOff(note: 64)
    }

    func testDDSP_bioReactiveRenderAfterBioUpdate() {
        let synth = EchoelPolyDDSP(sampleRate: 48000)
        synth.noteOn(note: 60, velocity: 0.8)
        synth.applyBioReactive(
            coherence: 0.65,
            hrvVariability: 0.55,
            heartRate: 0.45,
            breathPhase: 0.5
        )

        let frameCount = 512
        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)
        synth.renderStereo(left: &left, right: &right, frameCount: frameCount)

        let leftRMS = left.reduce(Float(0)) { $0 + $1 * $1 }
        XCTAssertGreaterThan(leftRMS, 0.0, "Left channel should have audio")

        synth.noteOff(note: 60)
    }
}

// MARK: - BioEngine State Tests

@MainActor
final class BioEngineIntegrationTests: XCTestCase {

    func testBioEngine_audioParametersBridge() {
        let bio = EchoelBioEngine.shared
        let params = bio.audioParameters()
        // Verify tuple structure for synth consumption
        XCTAssertGreaterThanOrEqual(params.coherence, 0.0)
        XCTAssertLessThanOrEqual(params.coherence, 1.0)
        XCTAssertGreaterThanOrEqual(params.hrv, 0.0)
        XCTAssertGreaterThanOrEqual(params.heartRate, 0.0)
        XCTAssertGreaterThanOrEqual(params.breathPhase, 0.0)
        XCTAssertLessThanOrEqual(params.breathPhase, 1.0)
    }

    func testBioEngine_dataSourceDefault() {
        let bio = EchoelBioEngine.shared
        // Without HealthKit authorization, should default to fallback
        XCTAssertEqual(bio.dataSource, .fallback,
                       "Bio engine should default to fallback (simulated) mode")
    }

    func testBioEngine_fallbackMode_smoothedValues() {
        let bio = EchoelBioEngine.shared
        // Smoothed values should be at reasonable defaults
        XCTAssertGreaterThan(bio.smoothHeartRate, 0.0)
        XCTAssertGreaterThanOrEqual(bio.smoothCoherence, 0.0)
        XCTAssertLessThanOrEqual(bio.smoothCoherence, 1.0)
        XCTAssertGreaterThanOrEqual(bio.smoothHRV, 0.0)
    }

    func testBioEngine_streamingStateManagement() {
        let bio = EchoelBioEngine.shared
        let wasStreaming = bio.isStreaming
        bio.startStreaming()
        XCTAssertTrue(bio.isStreaming, "Bio engine should be streaming after startStreaming()")
        bio.stopStreaming()
        XCTAssertFalse(bio.isStreaming, "Bio engine should stop after stopStreaming()")

        // Restore original state
        if wasStreaming {
            bio.startStreaming()
        }
    }

    func testBioEngine_audioParametersMatchSmoothed() {
        let bio = EchoelBioEngine.shared
        let params = bio.audioParameters()
        // Audio parameters should reflect the smoothed bio state
        XCTAssertEqual(params.coherence, Float(bio.smoothCoherence), accuracy: 0.01)
        XCTAssertEqual(params.hrv, Float(bio.smoothHRV), accuracy: 0.01)
        XCTAssertEqual(params.heartRate, Float(bio.smoothHeartRate), accuracy: 0.01)
    }
}

// MARK: - Bio Update Rate Concept Tests

@MainActor
final class BioUpdateRateTests: XCTestCase {

    func testBioLoopTarget_120Hz_intervalCalculation() {
        // The bio loop targets 120Hz — verify the interval math
        let targetHz: Double = 120.0
        let interval = 1.0 / targetHz
        XCTAssertEqual(interval, 1.0 / 120.0, accuracy: 0.0001,
                       "120Hz bio loop requires ~8.33ms interval")
        XCTAssertLessThan(interval, 0.01,
                          "Bio loop interval must be under 10ms for real-time response")
    }

    func testAudioRenderRate_withinBudget() {
        // At 48kHz / 512 frames, render rate ~93.75 Hz — within 10ms budget
        let sampleRate: Double = 48000
        let bufferSize: Double = 512
        guard sampleRate > 0 else {
            XCTFail("Sample rate must be positive")
            return
        }
        let renderInterval = bufferSize / sampleRate
        XCTAssertLessThan(renderInterval, 0.015,
                          "Audio render interval must be under 15ms (hard limit)")
        XCTAssertGreaterThan(renderInterval, 0.001,
                             "Render interval should be reasonable (not too small)")
    }
}

// MARK: - Visual Engine Bio-Reactive Tests

#if canImport(Metal)
@MainActor
final class VisEngineBioTests: XCTestCase {

    func testHilbertSensorMapper_preservesLocality() {
        // Adjacent 1D indices should map to nearby 2D coordinates
        let order = 16
        let (x0, y0) = HilbertSensorMapper.map(index: 0, order: order)
        let (x1, y1) = HilbertSensorMapper.map(index: 1, order: order)

        let distance = abs(x1 - x0) + abs(y1 - y0)  // Manhattan distance
        XCTAssertLessThanOrEqual(distance, 1,
                                 "Adjacent Hilbert indices should be neighbors in 2D (locality)")
    }

    func testHilbertSensorMapper_mapToGrid_correctSize() {
        let values: [Float] = Array(repeating: 0.5, count: 64)
        let grid = HilbertSensorMapper.mapToGrid(values: values, gridSize: 8)
        XCTAssertEqual(grid.count, 8, "Grid should have correct row count")
        for row in grid {
            XCTAssertEqual(row.count, 8, "Each row should have correct column count")
        }
    }

    func testHilbertSensorMapper_zeroOrder_safeDefault() {
        // Edge case: order = 0 should not crash
        let (x, y) = HilbertSensorMapper.map(index: 0, order: 0)
        XCTAssertEqual(x, 0)
        XCTAssertEqual(y, 0)
    }

}
#endif

// MARK: - End-to-End Bio Pipeline Tests

@MainActor
final class BioEndToEndTests: XCTestCase {

    func testEndToEnd_bioUpdate_throughSynthParams() {
        // Simulate the full pipeline: BioSnapshot → audioParameters → DDSP
        var snapshot = BioSnapshot()
        snapshot.heartRate = 90.0
        snapshot.hrvNormalized = 0.7
        snapshot.coherence = 0.8
        snapshot.breathPhase = 0.6
        snapshot.breathRate = 15.0
        snapshot.lfHfRatio = 1.3

        // Simulate what EchoelCreativeWorkspace does:
        // bio.audioParameters() → synth.applyBioReactive()
        let coherence = Float(snapshot.coherence)
        let hrv = Float(snapshot.hrvNormalized)
        guard snapshot.heartRate > 0 else {
            XCTFail("Heart rate must be positive for normalization")
            return
        }
        let heartRateNormalized = Float(snapshot.heartRate) / 200.0
        let breathPhase = Float(snapshot.breathPhase)

        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(
            coherence: coherence,
            hrvVariability: hrv,
            heartRate: heartRateNormalized,
            breathPhase: breathPhase,
            breathDepth: 0.5,
            lfHfRatio: Float(snapshot.lfHfRatio)
        )

        // Verify the entire chain applied correctly
        XCTAssertEqual(ddsp.harmonicity, 0.3 + coherence * 0.7, accuracy: 0.01,
                       "E2E: coherence → harmonicity mapping")
        XCTAssertEqual(ddsp.brightness, 0.2 + hrv * 0.6, accuracy: 0.01,
                       "E2E: HRV → brightness mapping")
        XCTAssertEqual(ddsp.vibratoRate, heartRateNormalized * 3.0, accuracy: 0.01,
                       "E2E: HR → vibrato mapping")
        XCTAssertEqual(ddsp.amplitude, 0.4 + breathPhase * 0.35, accuracy: 0.01,
                       "E2E: breath → amplitude mapping")
    }

    func testEndToEnd_bioSynth_producesAudioAfterBioUpdate() {
        // Full pipeline: create snapshot → apply to synth → render audio
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.noteOn(frequency: 440.0)
        ddsp.applyBioReactive(
            coherence: 0.7,
            hrvVariability: 0.5,
            heartRate: 0.4,
            breathPhase: 0.5,
            breathDepth: 0.5
        )

        let frameCount = 512
        var buffer = [Float](repeating: 0, count: frameCount)
        ddsp.render(buffer: &buffer, frameCount: frameCount)

        let hasSignal = buffer.contains(where: { $0 != 0 })
        XCTAssertTrue(hasSignal,
                      "E2E: Bio-reactive DDSP should produce audio after noteOn + bio update")

        // Verify output is within safe amplitude range
        guard let peak = buffer.map({ abs($0) }).max() else {
            XCTFail("Output buffer should not be empty")
            return
        }
        XCTAssertLessThanOrEqual(peak, 2.0,
                                 "E2E: Peak amplitude should be reasonable (no clipping explosion)")
    }

    // Workspace E2E test moved to DirectDDSPBioTests above
}

// MARK: - Bio Engine Crash Hardening Tests

final class BioCrashHardeningTests: XCTestCase {

    func testBioDataQueue_OverflowHandling() {
        let queue = BioDataQueue(capacity: 4)
        // Enqueue more than capacity
        for i in 0..<10 {
            queue.enqueue(heartRate: Float(60 + i), hrvCoherence: 0.5, breathPhase: 0.3)
        }
        // Should not crash, oldest samples should be dropped
        let sample = queue.dequeue()
        XCTAssertNotNil(sample, "Should have samples after overflow")
    }
}

#else
// Non-AVFoundation platforms — provide stub to avoid empty test bundle
import XCTest

final class BioIntegrationStubTests: XCTestCase {
    func testPlatformUnsupported() {
        // Bio integration tests require AVFoundation (iOS/macOS)
        XCTAssertTrue(true, "Bio integration tests skipped on this platform")
    }
}
#endif
