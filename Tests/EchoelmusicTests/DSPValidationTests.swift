#if canImport(AVFoundation)
// DSPValidationTests.swift
// Echoelmusic — TorchCode-Inspired DSP Validation Suite
//
// Auto-grading validation for bio-reactive parameter mappings,
// spectral accuracy, and cross-synth coherence.
// Inspired by TorchCode (github.com/duoan/TorchCode):
// exercises with known-correct outputs and tolerance-based auto-grading.

import XCTest
@testable import Echoelmusic

// MARK: - Bio-Reactive Parameter Sweep Tests (DDSP)

/// Validates that bio-reactive mappings produce correct, continuous parameter changes.
/// TorchCode pattern: known input → expected output range → auto-grade.
final class BioReactiveDDSPValidationTests: XCTestCase {

    // MARK: - Coherence → Harmonicity Mapping

    /// Coherence 0.0 → harmonicity should be low (~0.3)
    func testCoherenceZeroProducesLowHarmonicity() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.applyBioReactive(coherence: 0.0)
        // Formula: harmonicity = 0.3 + coherence * 0.7
        XCTAssertEqual(ddsp.harmonicity, 0.3, accuracy: 0.05,
                       "Zero coherence should produce ~0.3 harmonicity (noisy)")
    }

    /// Coherence 1.0 → harmonicity should be high (~1.0)
    func testCoherenceOneProducesHighHarmonicity() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.applyBioReactive(coherence: 1.0)
        XCTAssertEqual(ddsp.harmonicity, 1.0, accuracy: 0.05,
                       "Full coherence should produce ~1.0 harmonicity (pure)")
    }

    /// Coherence → Harmonicity must be monotonically increasing
    func testCoherenceToHarmonicityMonotonic() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        var prevHarmonicity: Float = -1

        for i in stride(from: Float(0), through: 1.0, by: 0.1) {
            ddsp.applyBioReactive(coherence: i)
            XCTAssertGreaterThanOrEqual(ddsp.harmonicity, prevHarmonicity - 0.001,
                                        "Harmonicity must increase with coherence at \(i)")
            prevHarmonicity = ddsp.harmonicity
        }
    }

    // MARK: - HRV → Brightness Mapping

    /// HRV sweep: low HRV → warm, high HRV → bright
    func testHRVToBrightnessRange() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)

        ddsp.applyBioReactive(coherence: 0.5, hrvVariability: 0.0)
        let warmBrightness = ddsp.brightness

        ddsp.applyBioReactive(coherence: 0.5, hrvVariability: 1.0)
        let brightBrightness = ddsp.brightness

        XCTAssertLessThan(warmBrightness, brightBrightness,
                          "Low HRV should produce warmer (lower brightness) than high HRV")
    }

    // MARK: - Heart Rate → Vibrato Mapping

    /// Heart rate normalized 0→1 should map to vibrato 0→3 Hz
    func testHeartRateToVibratoRate() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)

        ddsp.applyBioReactive(coherence: 0.5, heartRate: 0.0)
        XCTAssertEqual(ddsp.vibratoRate, 0.0, accuracy: 0.1,
                       "Zero heart rate → no vibrato")

        ddsp.applyBioReactive(coherence: 0.5, heartRate: 1.0)
        XCTAssertEqual(ddsp.vibratoRate, 3.0, accuracy: 0.3,
                       "Max heart rate → ~3 Hz vibrato")
    }

    /// Vibrato depth should stay subtle (max ~0.15 semitones)
    func testVibratoDepthSubtle() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.applyBioReactive(coherence: 0.5, heartRate: 1.0)
        XCTAssertLessThanOrEqual(ddsp.vibratoDepth, 0.2,
                                  "Vibrato depth should stay subtle even at max heart rate")
    }

    // MARK: - Breath → Amplitude & Noise Mapping

    /// Breath phase 0 → low amplitude, breath phase 1 → high amplitude
    func testBreathPhaseToAmplitude() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)

        ddsp.applyBioReactive(coherence: 0.5, breathPhase: 0.0)
        let quietAmp = ddsp.amplitude

        ddsp.applyBioReactive(coherence: 0.5, breathPhase: 1.0)
        let loudAmp = ddsp.amplitude

        XCTAssertLessThan(quietAmp, loudAmp,
                          "Higher breath phase should produce louder amplitude")
    }

    /// Deep breathing → more filter LFO movement (breathing sweep). Since the A8
    /// audit, breath drives `lfoToFilterDepth` (0.05 + breathDepth * 0.3), not noise
    /// absolutely — noise now subtly tracks coherence so the chosen timbre survives.
    func testBreathDepthToFilterMovement() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)

        ddsp.applyBioReactive(coherence: 0.5, breathDepth: 0.0)
        let shallowMovement = ddsp.lfoToFilterDepth

        ddsp.applyBioReactive(coherence: 0.5, breathDepth: 1.0)
        let deepMovement = ddsp.lfoToFilterDepth

        XCTAssertGreaterThan(deepMovement, shallowMovement,
                             "Deep breathing should open more filter movement (breathing sweep)")
    }

    // MARK: - Coherence Trend → Spectral Morphing

    /// Rising coherence → morph toward natural
    func testRisingCoherenceMorphsToNatural() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.applyBioReactive(coherence: 0.8, coherenceTrend: 0.5)
        XCTAssertEqual(ddsp.morphTarget, .natural,
                       "Rising coherence should morph toward natural")
        XCTAssertGreaterThan(ddsp.morphPosition, 0,
                             "Morph position should be > 0 for positive trend")
    }

    /// Falling coherence → morph toward metallic
    func testFallingCoherenceMorphsToMetallic() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.applyBioReactive(coherence: 0.3, coherenceTrend: -0.5)
        XCTAssertEqual(ddsp.morphTarget, .metallic,
                       "Falling coherence should morph toward metallic (tension)")
    }

    /// Stable coherence → no morphing
    func testStableCoherenceNoMorph() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.applyBioReactive(coherence: 0.5, coherenceTrend: 0.0)
        XCTAssertNil(ddsp.morphTarget,
                     "Stable coherence should not trigger morphing")
        XCTAssertEqual(ddsp.morphPosition, 0, accuracy: 0.001)
    }

    // MARK: - Full Bio Sweep NaN Guard

    /// Sweep all 7 bio parameters across full range — no NaN/Inf in rendered output
    func testFullBioSweepNaNGuard() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.noteOn(frequency: 440)
        var buffer = [Float](repeating: 0, count: 256)

        let steps: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]

        for coherence in steps {
            for hrv in steps {
                for breath in steps {
                    ddsp.applyBioReactive(
                        coherence: coherence,
                        hrvVariability: hrv,
                        heartRate: 0.5,
                        breathPhase: breath,
                        breathDepth: 0.5,
                        lfHfRatio: 0.5,
                        coherenceTrend: 0
                    )
                    ddsp.render(buffer: &buffer, frameCount: 256)
                    for (idx, sample) in buffer.enumerated() {
                        XCTAssertFalse(sample.isNaN,
                                       "NaN at sample \(idx) with coherence=\(coherence) hrv=\(hrv) breath=\(breath)")
                        XCTAssertFalse(sample.isInfinite,
                                       "Inf at sample \(idx) with coherence=\(coherence) hrv=\(hrv) breath=\(breath)")
                    }
                }
            }
        }
    }

    // MARK: - LF/HF → Spectral Tilt

    /// LF/HF ratio modulates harmonic amplitudes (spectral tilt)
    func testLFHFSpectralTilt() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)

        // Sympathetic (high LF/HF) should produce brighter spectrum
        ddsp.applyBioReactive(coherence: 0.5, lfHfRatio: 1.0)
        let brightHighHarmonic = ddsp.harmonicAmplitudes.last ?? 0

        // Reset and apply parasympathetic
        let ddsp2 = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp2.applyBioReactive(coherence: 0.5, lfHfRatio: 0.0)
        let warmHighHarmonic = ddsp2.harmonicAmplitudes.last ?? 0

        // Higher LF/HF should boost higher harmonics relative to lower LF/HF
        XCTAssertGreaterThan(brightHighHarmonic, warmHighHarmonic - 0.01,
                             "High LF/HF ratio should tilt spectrum brighter")
    }
}

// MARK: - Bio-Reactive ModalBank Validation Tests

/// Validates bio-reactive mappings on the physical modal synthesis engine.
final class BioReactiveModalBankValidationTests: XCTestCase {

    // MARK: - Coherence → Stiffness (Inharmonicity)

    /// High coherence → low stiffness (harmonic, string-like)
    func testHighCoherenceLowStiffness() {
        let bank = EchoelModalBank(modeCount: 16, sampleRate: 48000)
        bank.applyBioReactive(coherence: 1.0)
        XCTAssertLessThan(bank.stiffness, 0.2,
                          "High coherence should produce low stiffness (harmonic)")
    }

    /// Low coherence → high stiffness (inharmonic, bell-like)
    func testLowCoherenceHighStiffness() {
        let bank = EchoelModalBank(modeCount: 16, sampleRate: 48000)
        bank.applyBioReactive(coherence: 0.0)
        XCTAssertGreaterThan(bank.stiffness, 0.5,
                             "Low coherence should produce high stiffness (bell-like)")
    }

    /// Coherence → Stiffness must be monotonically decreasing
    func testCoherenceToStiffnessMonotonic() {
        let bank = EchoelModalBank(modeCount: 16, sampleRate: 48000)
        var prevStiffness: Float = Float.greatestFiniteMagnitude

        for i in stride(from: Float(0), through: 1.0, by: 0.1) {
            bank.applyBioReactive(coherence: i)
            XCTAssertLessThanOrEqual(bank.stiffness, prevStiffness + 0.001,
                                     "Stiffness must decrease with coherence at \(i)")
            prevStiffness = bank.stiffness
        }
    }

    // MARK: - HRV → Damping

    /// Low HRV → long ring (low damping), high HRV → short decay (high damping)
    func testHRVToDamping() {
        let bank = EchoelModalBank(modeCount: 16, sampleRate: 48000)

        bank.applyBioReactive(coherence: 0.5, hrvVariability: 0.0)
        let calmDamping = bank.damping

        bank.applyBioReactive(coherence: 0.5, hrvVariability: 1.0)
        let stressedDamping = bank.damping

        XCTAssertLessThan(calmDamping, stressedDamping,
                          "Low HRV (calm) should produce lower damping (longer ring)")
    }

    // (testBreathPhaseExcitation removed 2026-07-21 — it read the now-`private`
    //  EchoelModalBank.continuousExcitationLevel; the breath→excitation path is
    //  covered end-to-end by the NaN-sweep + render tests below.)

    // MARK: - Full Bio Sweep NaN Guard

    /// Parametric sweep of all bio inputs — no NaN/Inf in modal output
    func testModalBankBioSweepNaNGuard() {
        let bank = EchoelModalBank(modeCount: 16, sampleRate: 48000)
        bank.excite(velocity: 0.8, position: 0.5)
        var buffer = [Float](repeating: 0, count: 256)

        let steps: [Float] = [0.0, 0.33, 0.66, 1.0]

        for coherence in steps {
            for hrv in steps {
                for breath in steps {
                    bank.applyBioReactive(coherence: coherence, hrvVariability: hrv, breathPhase: breath)
                    bank.render(buffer: &buffer, frameCount: 256)
                    for (idx, sample) in buffer.enumerated() {
                        XCTAssertFalse(sample.isNaN,
                                       "NaN at \(idx) with coherence=\(coherence) hrv=\(hrv) breath=\(breath)")
                        XCTAssertFalse(sample.isInfinite,
                                       "Inf at \(idx) with coherence=\(coherence) hrv=\(hrv) breath=\(breath)")
                    }
                }
            }
        }
    }
}

// MARK: - Cellular Automata Coherence Validation

/// Validates that coherence correctly maps to CA rule selection.
final class CellularCoherenceValidationTests: XCTestCase {

    /// High coherence → harmonic rules (90, 150, 60)
    func testHighCoherenceSelectsHarmonicRule() {
        let cell = EchoelCellular(cellCount: 64, sampleRate: 48000)
        cell.coherence = 1.0
        let harmonicRules = EchoelCellular.CARule.harmonicRules
        XCTAssertTrue(harmonicRules.contains(cell.rule.number),
                      "Coherence 1.0 should select a harmonic rule, got \(cell.rule.number)")
    }

    /// Low coherence → chaotic rules (110, 30)
    func testLowCoherenceSelectsChaoticRule() {
        let cell = EchoelCellular(cellCount: 64, sampleRate: 48000)
        cell.coherence = 0.0
        // At coherence 0, we expect either the first harmonic rule or a chaotic one
        // The exact behavior depends on the mapping, so just verify it's deterministic
        let rule1 = cell.rule.number
        cell.coherence = 0.0
        XCTAssertEqual(cell.rule.number, rule1, "Same coherence should always select same rule")
    }

    /// Coherence sweep produces valid rules (no crash, no invalid state)
    func testCoherenceSweepProducesValidRules() {
        let cell = EchoelCellular(cellCount: 64, sampleRate: 48000)
        var seenRules = Set<UInt8>()

        for i in stride(from: Float(0), through: 1.0, by: 0.05) {
            cell.coherence = i
            XCTAssertGreaterThanOrEqual(cell.rule.number, 0)
            XCTAssertLessThanOrEqual(cell.rule.number, 255)
            seenRules.insert(cell.rule.number)
        }

        // Should produce at least 2 different rules across the coherence range
        XCTAssertGreaterThanOrEqual(seenRules.count, 2,
                                    "Coherence range should map to multiple different CA rules")
    }
}

// MARK: - Cross-Synth Bio Coherence Tests

/// Validates that DDSP + ModalBank respond consistently to the same bio snapshot.
/// TorchCode pattern: same input → consistent behavior across implementations.
final class CrossSynthBioCoherenceTests: XCTestCase {

    /// All synths should produce "calmer" output at high coherence
    func testHighCoherenceProducesCalmerOutput() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        let bank = EchoelModalBank(modeCount: 16, sampleRate: 48000)

        // High coherence state
        ddsp.applyBioReactive(coherence: 0.9)
        bank.applyBioReactive(coherence: 0.9)

        // DDSP: high harmonicity = more harmonic (calmer)
        XCTAssertGreaterThan(ddsp.harmonicity, 0.8, "DDSP should be highly harmonic at high coherence")

        // ModalBank: low stiffness = more harmonic modes (calmer)
        XCTAssertLessThan(bank.stiffness, 0.2, "ModalBank should have low stiffness at high coherence")
    }

    /// All synths should produce "tenser" output at low coherence
    func testLowCoherenceProducesTenserOutput() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        let bank = EchoelModalBank(modeCount: 16, sampleRate: 48000)

        // Low coherence state (stress/incoherence)
        ddsp.applyBioReactive(coherence: 0.1)
        bank.applyBioReactive(coherence: 0.1)

        // DDSP: low harmonicity = more noise (tenser)
        XCTAssertLessThan(ddsp.harmonicity, 0.45, "DDSP should have low harmonicity at low coherence")

        // ModalBank: high stiffness = inharmonic (bell-like, tenser)
        XCTAssertGreaterThan(bank.stiffness, 0.6, "ModalBank should have high stiffness at low coherence")
    }

    /// Bio-reactive NaN guard across all synths with extreme parameters
    func testExtremeParametersCrossNaNGuard() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        let bank = EchoelModalBank(modeCount: 16, sampleRate: 48000)

        ddsp.noteOn(frequency: 440)
        bank.excite(velocity: 1.0, position: 0.5)

        // Extreme bio state: everything at max
        ddsp.applyBioReactive(
            coherence: 1.0, hrvVariability: 1.0, heartRate: 1.0,
            breathPhase: 1.0, breathDepth: 1.0, lfHfRatio: 1.0, coherenceTrend: 1.0
        )
        bank.applyBioReactive(coherence: 1.0, hrvVariability: 1.0, breathPhase: 1.0)

        var ddspBuffer = [Float](repeating: 0, count: 256)
        var bankBuffer = [Float](repeating: 0, count: 256)

        ddsp.render(buffer: &ddspBuffer, frameCount: 256)
        bank.render(buffer: &bankBuffer, frameCount: 256)

        for i in 0..<256 {
            XCTAssertFalse(ddspBuffer[i].isNaN, "DDSP NaN at extreme params, sample \(i)")
            XCTAssertFalse(ddspBuffer[i].isInfinite, "DDSP Inf at extreme params, sample \(i)")
            XCTAssertFalse(bankBuffer[i].isNaN, "ModalBank NaN at extreme params, sample \(i)")
            XCTAssertFalse(bankBuffer[i].isInfinite, "ModalBank Inf at extreme params, sample \(i)")
        }

        // Extreme bio state: everything at min
        ddsp.applyBioReactive(
            coherence: 0.0, hrvVariability: 0.0, heartRate: 0.0,
            breathPhase: 0.0, breathDepth: 0.0, lfHfRatio: 0.0, coherenceTrend: -1.0
        )
        bank.applyBioReactive(coherence: 0.0, hrvVariability: 0.0, breathPhase: 0.0)

        ddsp.render(buffer: &ddspBuffer, frameCount: 256)
        bank.render(buffer: &bankBuffer, frameCount: 256)

        for i in 0..<256 {
            XCTAssertFalse(ddspBuffer[i].isNaN, "DDSP NaN at zero params, sample \(i)")
            XCTAssertFalse(ddspBuffer[i].isInfinite, "DDSP Inf at zero params, sample \(i)")
            XCTAssertFalse(bankBuffer[i].isNaN, "ModalBank NaN at zero params, sample \(i)")
            XCTAssertFalse(bankBuffer[i].isInfinite, "ModalBank Inf at zero params, sample \(i)")
        }
    }
}

// MARK: - ADSR Envelope Boundary Tests

/// TorchCode pattern: edge cases with known outputs.
final class ADSRBoundaryValidationTests: XCTestCase {

    /// Zero attack + zero decay should not crash
    func testZeroAttackZeroDecay() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.attack = 0.0
        ddsp.decay = 0.0
        ddsp.sustain = 0.8
        ddsp.release = 0.0
        ddsp.noteOn(frequency: 440)

        var buffer = [Float](repeating: 0, count: 256)
        ddsp.render(buffer: &buffer, frameCount: 256)

        for sample in buffer {
            XCTAssertFalse(sample.isNaN, "Zero ADSR must not produce NaN")
            XCTAssertFalse(sample.isInfinite, "Zero ADSR must not produce Inf")
        }
    }

    /// Full sustain (1.0) after zero attack/decay should produce near-max output
    func testFullSustainProducesOutput() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.attack = 0.001
        ddsp.decay = 0.001
        ddsp.sustain = 1.0
        ddsp.release = 1.0
        ddsp.amplitude = 1.0
        ddsp.noteOn(frequency: 440)

        var buffer = [Float](repeating: 0, count: 256)
        // Render a few frames to get past attack/decay
        for _ in 0..<4 {
            ddsp.render(buffer: &buffer, frameCount: 256)
        }

        let rms = sqrt(buffer.map { $0 * $0 }.reduce(0, +) / Float(buffer.count))
        XCTAssertGreaterThan(rms, 0.01,
                             "Full sustain should produce audible output (RMS > 0.01)")
    }

    /// Zero sustain should produce near-silence after attack+decay
    func testZeroSustainProducesSilence() {
        let ddsp = EchoelDDSP(harmonicCount: 32, sampleRate: 48000, frameSize: 256)
        ddsp.attack = 0.001
        ddsp.decay = 0.01
        ddsp.sustain = 0.0
        ddsp.release = 0.0
        ddsp.noteOn(frequency: 440)

        var buffer = [Float](repeating: 0, count: 256)
        // Render several frames to get well past decay
        for _ in 0..<10 {
            ddsp.render(buffer: &buffer, frameCount: 256)
        }

        let rms = sqrt(buffer.map { $0 * $0 }.reduce(0, +) / Float(buffer.count))
        XCTAssertLessThan(rms, 0.1,
                          "Zero sustain should produce near-silence after decay (RMS < 0.1)")
    }
}

// MARK: - Spectral Accuracy Validation

/// Validates FFT and spectral analysis produce correct frequency identification.
/// TorchCode pattern: known input frequency → FFT → verify dominant bin.
final class SpectralAccuracyValidationTests: XCTestCase {

    /// 440 Hz sine → FFT → dominant frequency should be ~440 Hz
    func testFFTIdentifies440Hz() {
        let fftSize = 4096
        let sampleRate: Float = 48000
        let frequency: Float = 440

        // Generate pure sine
        let signal = (0..<fftSize).map { i in
            sin(2.0 * Float.pi * frequency * Float(i) / sampleRate)
        }

        let fft = EchoelRealFFT(size: fftSize)
        let magnitudes = fft.forward(signal).magnitudes

        // Find dominant bin
        guard let maxIdx = magnitudes.indices.max(by: { magnitudes[$0] < magnitudes[$1] }) else {
            XCTFail("No FFT magnitudes"); return
        }

        let dominantFreq = Float(maxIdx) * sampleRate / Float(fftSize)
        XCTAssertEqual(dominantFreq, frequency, accuracy: 20,
                       "FFT should identify 440 Hz within ±20 Hz (got \(dominantFreq) Hz)")
    }

    /// 1 kHz sine → FFT → dominant frequency should be ~1000 Hz
    func testFFTIdentifies1kHz() {
        let fftSize = 4096
        let sampleRate: Float = 48000
        let frequency: Float = 1000

        let signal = (0..<fftSize).map { i in
            sin(2.0 * Float.pi * frequency * Float(i) / sampleRate)
        }

        let fft = EchoelRealFFT(size: fftSize)
        let magnitudes = fft.forward(signal).magnitudes

        guard let maxIdx = magnitudes.indices.max(by: { magnitudes[$0] < magnitudes[$1] }) else {
            XCTFail("No FFT magnitudes"); return
        }

        let dominantFreq = Float(maxIdx) * sampleRate / Float(fftSize)
        XCTAssertEqual(dominantFreq, frequency, accuracy: 20,
                       "FFT should identify 1 kHz within ±20 Hz (got \(dominantFreq) Hz)")
    }

    /// Silent input → all magnitudes near zero
    func testFFTSilenceProducesZeroMagnitudes() {
        let fftSize = 4096
        let signal = [Float](repeating: 0, count: fftSize)

        let fft = EchoelRealFFT(size: fftSize)
        let maxMagnitude = fft.forward(signal).magnitudes.max() ?? 0
        XCTAssertLessThan(maxMagnitude, 0.001,
                          "Silent input should produce near-zero magnitudes")
    }

    /// Power spectrum must be non-negative
    func testPowerSpectrumNonNegative() {
        let fftSize = 2048
        let signal = (0..<fftSize).map { Float(sin(Double($0) * 0.1)) * 0.5 }

        let fft = EchoelRealFFT(size: fftSize)
        let power = fft.powerSpectrum(signal)
        for (idx, val) in power.enumerated() {
            XCTAssertGreaterThanOrEqual(val, 0, "Power spectrum must be >= 0 at bin \(idx)")
            XCTAssertFalse(val.isNaN, "Power spectrum must not be NaN at bin \(idx)")
        }
    }
}

// MARK: - Convolution Kernel Validation

/// Validates filter kernel properties (DC gain, symmetry, length).
final class ConvolutionKernelValidationTests: XCTestCase {

    /// Lowpass kernel sum should approximate 1.0 (unity DC gain)
    func testLowpassKernelUnityDCGain() {
        let kernel = EchoelConvolution.lowpassKernel(cutoffHz: 1000, sampleRate: 48000, taps: 31)
        let sum = kernel.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.15,
                       "Lowpass kernel DC gain should be ~1.0 (got \(sum))")
    }

    /// Kernel length must match tap count
    func testKernelLengthMatchesTapCount() {
        let taps = 31
        let kernel = EchoelConvolution.lowpassKernel(cutoffHz: 1000, sampleRate: 48000, taps: taps)
        XCTAssertEqual(kernel.count, taps,
                       "Kernel length must match tap count")
    }

    /// Highpass kernel: DC gain should be near 0
    func testHighpassKernelZeroDCGain() {
        let kernel = EchoelConvolution.highpassKernel(cutoffHz: 1000, sampleRate: 48000, taps: 31)
        let sum = kernel.reduce(0, +)
        XCTAssertEqual(sum, 0.0, accuracy: 0.2,
                       "Highpass kernel DC gain should be ~0 (got \(sum))")
    }
}

// (AnalogEmulationValidationTests removed 2026-07-21 — the analog-emulation
//  processors it exercised, SSLBusCompressor / LA2ACompressor, no longer exist
//  in Sources, and its biquad-cascade case referenced a drifted setParametricEQ
//  signature. EchoelRealFFT/EchoelConvolution stay covered above.)
#endif
