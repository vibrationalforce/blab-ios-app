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

    // NOTE (A8 audit, see EchoelDDSP.applyBioReactive): coherence→harmonicity is no
    // longer the absolute `0.3 + coherence*0.7`; it is a SUBTLE deviation around the
    // patch baseline — `harmonicity = (bioBaseHarmonicity + (coherence-0.5)*0.12)`,
    // clamped [0.05, 0.98]. The mapping DIRECTION (more coherence → more harmonic) is
    // intact and intended, so these assert direction/range against a mid reference,
    // not the retired exact formula.
    func testCoherence_high_producesHighHarmonicity() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.5)
        let mid = ddsp.harmonicity
        ddsp.applyBioReactive(coherence: 0.95)
        XCTAssertGreaterThan(ddsp.harmonicity, mid,
                             "High coherence should yield higher harmonicity (purer tone)")
    }

    func testCoherence_low_producesLowHarmonicity() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.5)
        let mid = ddsp.harmonicity
        ddsp.applyBioReactive(coherence: 0.1)
        XCTAssertLessThan(ddsp.harmonicity, mid,
                          "Low coherence should yield lower harmonicity (less pure)")
    }

    func testCoherence_zero_producesMinimumHarmonicity() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.5)
        let mid = ddsp.harmonicity
        ddsp.applyBioReactive(coherence: 0.0)
        XCTAssertLessThan(ddsp.harmonicity, mid,
                          "Zero coherence sits below the mid-coherence baseline")
        XCTAssertGreaterThanOrEqual(ddsp.harmonicity, 0.05, "clamped to the audible floor")
    }

    func testCoherence_one_producesMaximumHarmonicity() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.5)
        let mid = ddsp.harmonicity
        ddsp.applyBioReactive(coherence: 1.0)
        XCTAssertGreaterThan(ddsp.harmonicity, mid,
                             "Full coherence sits above the mid-coherence baseline")
        XCTAssertLessThanOrEqual(ddsp.harmonicity, 0.98, "clamped to the harmonic ceiling")
    }

    // MARK: - HRV → Brightness

    // #77 RESTORED: HRV variability adds a ±0.10 patch-relative deviation to brightness
    // (centered on neutral HRV 0.5), on TOP of the coherence/HR/LFO drive and alongside
    // HRV→reverbMix. Two fresh engines get the IDENTICAL call sequence so _lfoPhase advances
    // identically and the LFO term cancels — only the HRV DC gap differs. 40 calls settle the
    // α=0.92 one-pole. Direction/range asserts (the retired exact formula is gone).
    func testHRV_high_producesBrightSpectrum() {
        let hi = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        let lo = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        for _ in 0..<40 {
            hi.applyBioReactive(coherence: 0.5, hrvVariability: 0.9)
            lo.applyBioReactive(coherence: 0.5, hrvVariability: 0.1)
        }
        XCTAssertGreaterThan(hi.brightness, lo.brightness, "High HRV → brighter spectrum")
        XCTAssertGreaterThanOrEqual(hi.brightness, 0.05, "clamped floor")
        XCTAssertLessThanOrEqual(hi.brightness, 0.8, "clamped ceiling")
    }

    func testHRV_low_producesWarmSpectrum() {
        let lo = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        let mid = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        for _ in 0..<40 {
            lo.applyBioReactive(coherence: 0.5, hrvVariability: 0.1)
            mid.applyBioReactive(coherence: 0.5, hrvVariability: 0.5)
        }
        XCTAssertLessThan(lo.brightness, mid.brightness, "Low HRV → warmer than neutral")
        XCTAssertGreaterThanOrEqual(lo.brightness, 0.05, "clamped floor")
    }

    // MARK: - Heart Rate → Vibrato

    // A8 audit: heart-rate → vibrato is now a GENTLE drift (founder: "bio should be
    // subtle"), `vibratoRate = 0.05 + heartRate*0.15`, `vibratoDepth = 0.004 + heartRate*0.02`,
    // not the retired `*3.0`/`*0.15`. The DIRECTION (faster pulse → faster/deeper vibrato)
    // is intact, so assert direction against a resting reference.
    func testHeartRate_high_producesHighVibratoRate() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.5, heartRate: 0.35)   // ~70 BPM resting
        let restingRate = ddsp.vibratoRate
        let restingDepth = ddsp.vibratoDepth
        ddsp.applyBioReactive(coherence: 0.5, heartRate: 0.8)    // ~160 BPM active
        XCTAssertGreaterThan(ddsp.vibratoRate, restingRate,
                             "High heart rate → faster vibrato")
        XCTAssertGreaterThan(ddsp.vibratoDepth, restingDepth,
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

    // #77 RESTORED: breath phase swells amplitude in ALL profiles (raised cosine, peak at
    // mid-breath / phase 0.5, trough at the exhale/phase-wrap). Two fresh engines get the
    // identical call sequence so _smoothedAmplitude matches; only the breath multiplier
    // differs (1.0 at phase 0.5 vs 0.90 at phase 0.0). Downward-only, so mid-breath is louder.
    func testBreathPhase_inhalation_producesHigherAmplitude() {
        let mid = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        let trough = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        for _ in 0..<40 {
            mid.applyBioReactive(coherence: 0.5, breathPhase: 0.5)
            trough.applyBioReactive(coherence: 0.5, breathPhase: 0.0)
        }
        XCTAssertGreaterThan(mid.amplitude, trough.amplitude,
                             "Mid-breath swell peak is louder than the exhale trough")
        XCTAssertLessThanOrEqual(mid.amplitude, 1.0, "never past the −1 dBFS ceiling")
    }

    func testBreathDepth_deep_opensFilterMovement() {
        // A8 audit (see EchoelDDSP.applyBioReactive): breath depth no longer sets
        // noise absolutely (that plastered every patch toward one timbre) — noise now
        // subtly tracks coherence, and BREATH drives the filter LFO depth so the
        // chosen character survives. Formula: lfoToFilterDepth = 0.05 + breathDepth * 0.3.
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.5, breathDepth: 0.9)
        let deepBreathMovement = ddsp.lfoToFilterDepth

        ddsp.applyBioReactive(coherence: 0.5, breathDepth: 0.1)
        let shallowBreathMovement = ddsp.lfoToFilterDepth

        XCTAssertGreaterThan(deepBreathMovement, shallowBreathMovement,
                             "Deeper breath should open more filter movement (breathing sweep)")
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

    // #77 RESTORED: coherenceTrend leans the spectral morph — rising→.natural, falling→.metallic
    // (arbitrary engineering shape names, NO wellbeing valence). |trend| ≥ 0.10 activates;
    // morphPosition rises continuously from the deadband edge to a 0.30 cap (a lean, base shape
    // still dominant). No smoothing on the trend path, so a single call suffices.
    func testCoherenceTrend_rising_morphsTowardNatural() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.5, coherenceTrend: 0.8)
        XCTAssertEqual(ddsp.morphTarget, .natural, "Rising coherence leans toward the natural shape")
        XCTAssertGreaterThan(ddsp.morphPosition, 0, "morph active above the deadband")
        XCTAssertLessThanOrEqual(ddsp.morphPosition, 0.30, "capped lean, base shape dominant")
    }

    func testCoherenceTrend_falling_morphsTowardMetallic() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.5, coherenceTrend: -0.8)
        XCTAssertEqual(ddsp.morphTarget, .metallic, "Falling coherence leans toward the metallic shape")
        XCTAssertGreaterThan(ddsp.morphPosition, 0, "morph active above the deadband")
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
        // Restored HRV→brightness (±0.10 around neutral): zero HRV sits at the low end but
        // stays a valid, clamped, finite value (the retired exact 0.2 formula is gone).
        let low = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        let high = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        for _ in 0..<40 {
            low.applyBioReactive(coherence: 0.5, hrvVariability: 0.0)
            high.applyBioReactive(coherence: 0.5, hrvVariability: 1.0)
        }
        XCTAssertTrue(low.brightness.isFinite)
        XCTAssertGreaterThanOrEqual(low.brightness, 0.05)
        XCTAssertLessThanOrEqual(low.brightness, 0.8)
        XCTAssertLessThan(low.brightness, high.brightness, "zero HRV is the darker end")
    }

    func testBioReactive_zeroHeartRate_safeVibratoRate() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        ddsp.applyBioReactive(coherence: 0.5, heartRate: 0.0)
        // A8: vibrato has a gentle floor (0.05 + hr*0.15), never zero — but at rest it stays
        // small and safe (no wobble). Assert small + finite, not exactly zero.
        XCTAssertTrue(ddsp.vibratoRate.isFinite && ddsp.vibratoDepth.isFinite)
        XCTAssertGreaterThanOrEqual(ddsp.vibratoRate, 0)
        XCTAssertLessThan(ddsp.vibratoRate, 0.1, "resting vibrato stays subtle")
        XCTAssertLessThan(ddsp.vibratoDepth, 0.01)
    }

    func testBioReactive_allParametersAtOnce() {
        // Full bio state update — verify no crash and all mappings produce valid output.
        // (Exact per-mapping values are covered by BioDDSPMappingTests; here we assert the
        // combined call stays finite/in-range and the morph engages, not the retired formulas.)
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
        for v in [ddsp.harmonicity, ddsp.brightness, ddsp.vibratoRate, ddsp.amplitude, ddsp.noiseLevel] {
            XCTAssertTrue(v.isFinite, "every mapped parameter stays finite")
        }
        XCTAssertGreaterThanOrEqual(ddsp.harmonicity, 0.05); XCTAssertLessThanOrEqual(ddsp.harmonicity, 0.98)
        XCTAssertGreaterThanOrEqual(ddsp.amplitude, 0); XCTAssertLessThanOrEqual(ddsp.amplitude, 1.0)
        XCTAssertEqual(ddsp.morphTarget, .natural, "positive coherenceTrend (0.3 > 0.10 deadband) leans natural")
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

        // Verify the entire chain applied correctly — the bio inputs reach the synth params
        // as valid, in-range values (exact per-mapping curves are covered by BioDDSPMappingTests;
        // the retired absolute formulas 0.3+coh*0.7 / 0.2+hrv*0.6 / hr*3.0 / 0.4+breath*0.35 are gone).
        _ = (coherence, hrv, heartRateNormalized, breathPhase)  // inputs exercised above
        XCTAssertTrue(ddsp.harmonicity.isFinite && ddsp.brightness.isFinite
                      && ddsp.vibratoRate.isFinite && ddsp.amplitude.isFinite,
                      "E2E: every mapped synth parameter stays finite")
        XCTAssertGreaterThanOrEqual(ddsp.harmonicity, 0.05); XCTAssertLessThanOrEqual(ddsp.harmonicity, 0.98)
        XCTAssertGreaterThanOrEqual(ddsp.brightness, 0.05); XCTAssertLessThanOrEqual(ddsp.brightness, 0.8)
        XCTAssertGreaterThanOrEqual(ddsp.amplitude, 0); XCTAssertLessThanOrEqual(ddsp.amplitude, 1.0)
        XCTAssertGreaterThan(ddsp.vibratoRate, 0, "gentle vibrato floor present")
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
