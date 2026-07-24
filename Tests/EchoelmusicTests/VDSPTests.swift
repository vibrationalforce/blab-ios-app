#if canImport(AVFoundation)
// VDSPTests.swift
// Echoelmusic — Phase 3 Test Coverage: vDSP & Advanced Synthesis
//
// Tests for EchoelVDSPKit (FFT, Convolution, Biquad, Decimator, SpectralAnalyzer),
// EchoelModalBank, and EchoelCellular.

import XCTest
@testable import Echoelmusic

// MARK: - EchoelRealFFT Tests

final class EchoelRealFFTTests: XCTestCase {

    func testInit() {
        let fft = EchoelRealFFT(size: 1024)
        XCTAssertEqual(fft.size, 1024)
    }

    func testDefaultInit() {
        let fft = EchoelRealFFT()
        XCTAssertEqual(fft.size, 2048)
    }

    func testWindowTypeCases() {
        let cases = EchoelRealFFT.WindowType.allCases
        XCTAssertTrue(cases.contains(.hann))
        XCTAssertTrue(cases.contains(.blackman))
        XCTAssertTrue(cases.contains(.hamming))
        XCTAssertTrue(cases.contains(.kaiser))
        XCTAssertTrue(cases.contains(.flatTop))
    }

    func testForwardTransform() {
        let fft = EchoelRealFFT(size: 256, window: .hann)
        let input = (0..<256).map { sin(Float($0) * 2 * .pi * 10 / 256) }
        let (magnitudes, phases) = fft.forward(input)
        XCTAssertGreaterThan(magnitudes.count, 0)
        XCTAssertGreaterThan(phases.count, 0)
        // No NaN
        for mag in magnitudes {
            XCTAssertFalse(mag.isNaN)
            XCTAssertFalse(mag.isInfinite)
        }
    }

    func testPowerSpectrum() {
        let fft = EchoelRealFFT(size: 256)
        let input = [Float](repeating: 0.5, count: 256)
        let power = fft.powerSpectrum(input)
        XCTAssertGreaterThan(power.count, 0)
        for val in power {
            XCTAssertGreaterThanOrEqual(val, 0)
        }
    }

    func testFrequencyForBin() {
        let fft = EchoelRealFFT(size: 1024)
        let freq = fft.frequencyForBin(10, sampleRate: 48000)
        // bin 10 at 1024 FFT, 48kHz → 10 * 48000/1024 ≈ 468.75
        XCTAssertEqual(freq, 468.75, accuracy: 1.0)
    }

    func testUpdateWindow() {
        let fft = EchoelRealFFT(size: 512, window: .hann)
        fft.updateWindow(.blackman)
        // Should not crash, verify by running transform
        let input = [Float](repeating: 0.3, count: 512)
        let (mags, _) = fft.forward(input)
        XCTAssertGreaterThan(mags.count, 0)
    }

    func testSilentInput() {
        let fft = EchoelRealFFT(size: 256)
        let input = [Float](repeating: 0, count: 256)
        let (mags, _) = fft.forward(input)
        // All magnitudes should be ~0
        for mag in mags {
            XCTAssertEqual(mag, 0, accuracy: 0.001)
        }
    }
}

// MARK: - EchoelComplexDFT Tests

final class EchoelComplexDFTTests: XCTestCase {

    func testInit() {
        let dft = EchoelComplexDFT(size: 64)
        XCTAssertEqual(dft.size, 64)
    }

    func testForwardTransform() {
        let dft = EchoelComplexDFT(size: 64)
        let real = [Float](repeating: 1.0, count: 64)
        let imag = [Float](repeating: 0.0, count: 64)
        let result = dft.forward(real: real, imag: imag)
        XCTAssertEqual(result.real.count, 64)
        XCTAssertEqual(result.imag.count, 64)
        // DC component should be sum of inputs = 64
        XCTAssertEqual(result.real[0], 64.0, accuracy: 0.1)
    }

    func testZeroInput() {
        let dft = EchoelComplexDFT(size: 32)
        let zero = [Float](repeating: 0, count: 32)
        let result = dft.forward(real: zero, imag: zero)
        for val in result.real {
            XCTAssertEqual(val, 0, accuracy: 0.001)
        }
    }
}

// MARK: - EchoelConvolution Tests

final class EchoelConvolutionTests: XCTestCase {

    func testInit() {
        let kernel: [Float] = [0.25, 0.5, 0.25]
        let conv = EchoelConvolution(kernel: kernel)
        XCTAssertNotNil(conv)
    }

    func testProcessOutput() {
        let kernel: [Float] = [1.0]
        let conv = EchoelConvolution(kernel: kernel)
        let input: [Float] = [0.1, 0.2, 0.3, 0.4]
        let output = conv.process(input)
        XCTAssertGreaterThan(output.count, 0)
    }

    func testLowpassKernel() {
        let kernel = EchoelConvolution.lowpassKernel(cutoffHz: 1000, sampleRate: 48000, taps: 31)
        XCTAssertEqual(kernel.count, 31)
        // Kernel should sum to ~1 (unity gain at DC)
        let sum = kernel.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.1)
    }

    func testHighpassKernel() {
        let kernel = EchoelConvolution.highpassKernel(cutoffHz: 1000, sampleRate: 48000, taps: 31)
        XCTAssertEqual(kernel.count, 31)
    }

    func testBandpassKernel() {
        let kernel = EchoelConvolution.bandpassKernel(lowHz: 500, highHz: 2000, sampleRate: 48000, taps: 31)
        XCTAssertEqual(kernel.count, 31)
    }

    func testSetKernel() {
        let conv = EchoelConvolution(kernel: [1.0])
        conv.setKernel([0.5, 0.5])
        let input: [Float] = [1.0, 0.0, 0.0, 0.0]
        let output = conv.process(input)
        XCTAssertGreaterThan(output.count, 0)
    }
}

// MARK: - EchoelBiquadCascade Tests

final class EchoelBiquadCascadeTests: XCTestCase {

    func testInit() {
        let cascade = EchoelBiquadCascade(sectionCount: 4)
        XCTAssertEqual(cascade.sectionCount, 4)
    }

    func testDefaultInit() {
        let cascade = EchoelBiquadCascade()
        XCTAssertEqual(cascade.sectionCount, 4)
    }

    func testProcess() {
        let cascade = EchoelBiquadCascade(sectionCount: 2)
        cascade.setLowpass(section: 0, frequency: 1000, q: 0.707, sampleRate: 48000)
        let input: [Float] = Array(repeating: 0.5, count: 256)
        let output = cascade.process(input)
        XCTAssertEqual(output.count, 256)
        for sample in output {
            XCTAssertFalse(sample.isNaN)
            XCTAssertFalse(sample.isInfinite)
        }
    }

    func testParametricEQ() {
        let cascade = EchoelBiquadCascade(sectionCount: 4)
        cascade.setParametricEQ(section: 0, frequency: 1000, gain: 6.0, q: 1.0, sampleRate: 48000)
        let input: [Float] = (0..<256).map { sin(Float($0) * 2 * .pi * 1000 / 48000) }
        let output = cascade.process(input)
        XCTAssertEqual(output.count, input.count)
    }

    func testHighpass() {
        let cascade = EchoelBiquadCascade(sectionCount: 1)
        cascade.setHighpass(section: 0, frequency: 200, q: 0.707, sampleRate: 48000)
        let input: [Float] = Array(repeating: 0.3, count: 128)
        let output = cascade.process(input)
        XCTAssertEqual(output.count, 128)
    }

    func testOutOfRangeSection_isNoOp_neverTraps() {
        // The setters guard `section < sectionCount` AND (now) `section >= 0`. A
        // negative section would make `idx = section * 5` a negative subscript into
        // `coefficients` → out-of-bounds trap. Reaching the end of this test IS the
        // assertion (a trap would crash the run). A valid band must still apply after.
        let cascade = EchoelBiquadCascade(sectionCount: 2)
        for bad in [-1, -100, 2, 5, Int.min / 5] {
            cascade.setParametricEQ(section: bad, frequency: 1000, gain: 3, q: 1, sampleRate: 48000)
            cascade.setLowpass(section: bad, frequency: 1000, q: 0.707, sampleRate: 48000)
            cascade.setHighpass(section: bad, frequency: 200, q: 0.707, sampleRate: 48000)
        }
        // A valid section still works and produces finite output.
        cascade.setLowpass(section: 0, frequency: 1000, q: 0.707, sampleRate: 48000)
        let output = cascade.process(Array(repeating: 0.4, count: 128))
        XCTAssertEqual(output.count, 128)
        for s in output { XCTAssertFalse(s.isNaN); XCTAssertFalse(s.isInfinite) }
    }

    func testReset() {
        let cascade = EchoelBiquadCascade()
        cascade.setLowpass(section: 0, frequency: 500, q: 0.7, sampleRate: 48000)
        let input: [Float] = [1.0, 0.0, 0.0, 0.0]
        _ = cascade.process(input)
        cascade.reset()
        // After reset, processing should start fresh
        let output = cascade.process(input)
        XCTAssertEqual(output.count, input.count)
    }
}

// MARK: - EchoelDecimator Tests

final class EchoelDecimatorTests: XCTestCase {

    func testInit() {
        let decimator = EchoelDecimator(factor: 2)
        XCTAssertEqual(decimator.factor, 2)
    }

    func testProcess() {
        let decimator = EchoelDecimator(factor: 2)
        let input = [Float](repeating: 0.5, count: 100)
        let output = decimator.process(input)
        // Output should be roughly half the length
        XCTAssertEqual(output.count, 50)
    }

    func testDecimationFactor4() {
        let decimator = EchoelDecimator(factor: 4)
        let input = [Float](repeating: 1.0, count: 200)
        let output = decimator.process(input)
        XCTAssertEqual(output.count, 50)
    }

    func testNoNaN() {
        let decimator = EchoelDecimator(factor: 2)
        let input = (0..<128).map { sin(Float($0) * 0.1) }
        let output = decimator.process(input)
        for sample in output {
            XCTAssertFalse(sample.isNaN)
            XCTAssertFalse(sample.isInfinite)
        }
    }
}

// MARK: - EchoelSpectralAnalyzer Tests

final class EchoelSpectralAnalyzerTests: XCTestCase {

    func testInit() {
        let analyzer = EchoelSpectralAnalyzer(size: 1024, sampleRate: 48000)
        XCTAssertEqual(analyzer.sampleRate, 48000)
    }

    func testBandPower() {
        let analyzer = EchoelSpectralAnalyzer(size: 1024, sampleRate: 48000)
        // Generate 1kHz sine wave
        let input = (0..<1024).map { sin(Float($0) * 2 * .pi * 1000 / 48000) }
        let power = analyzer.bandPower(input, band: 900...1100)
        XCTAssertGreaterThan(power, 0)
    }

    func testDominantFrequency() {
        let analyzer = EchoelSpectralAnalyzer(size: 2048, sampleRate: 48000)
        // Generate 440Hz sine wave
        let input = (0..<2048).map { sin(Float($0) * 2 * .pi * 440 / 48000) }
        let dominant = analyzer.dominantFrequency(input, band: 200...800)
        XCTAssertEqual(dominant, 440, accuracy: 50) // Reasonable FFT bin resolution
    }

    func testSpectralCentroid() {
        let analyzer = EchoelSpectralAnalyzer(size: 1024, sampleRate: 48000)
        let input = (0..<1024).map { sin(Float($0) * 2 * .pi * 1000 / 48000) }
        let centroid = analyzer.spectralCentroid(input)
        XCTAssertGreaterThan(centroid, 0)
        XCTAssertFalse(centroid.isNaN)
    }

    func testSilentInputCentroid() {
        let analyzer = EchoelSpectralAnalyzer(size: 512, sampleRate: 48000)
        let input = [Float](repeating: 0, count: 512)
        let centroid = analyzer.spectralCentroid(input)
        // Should handle zero input gracefully
        XCTAssertFalse(centroid.isNaN)
    }
}

// MARK: - EchoelModalBank Tests

final class EchoelModalBankTests: XCTestCase {

    func testInit() {
        let bank = EchoelModalBank(modeCount: 32, sampleRate: 48000)
        XCTAssertEqual(bank.modeCount, 32)
        XCTAssertEqual(bank.sampleRate, 48000)
    }

    func testDefaultInit() {
        let bank = EchoelModalBank()
        XCTAssertEqual(bank.modeCount, 64)
        XCTAssertEqual(bank.sampleRate, 48000)
        XCTAssertEqual(bank.frequency, 220.0)
        XCTAssertEqual(bank.amplitude, 0.8, accuracy: 0.01)
    }

    func testMaterialPresetCases() {
        let cases = EchoelModalBank.MaterialPreset.allCases
        XCTAssertEqual(cases.count, 8)
        XCTAssertTrue(cases.contains(.bell))
        XCTAssertTrue(cases.contains(.plate))
        XCTAssertTrue(cases.contains(.bar))
        XCTAssertTrue(cases.contains(.string))
        XCTAssertTrue(cases.contains(.glass))
        XCTAssertTrue(cases.contains(.drum))
        XCTAssertTrue(cases.contains(.gong))
        XCTAssertTrue(cases.contains(.custom))
    }

    func testExcitationTypeCases() {
        let cases = EchoelModalBank.ExcitationType.allCases
        XCTAssertEqual(cases.count, 3)
        XCTAssertTrue(cases.contains(.impulse))
        XCTAssertTrue(cases.contains(.continuous))
        XCTAssertTrue(cases.contains(.noise))
    }

    func testExcite() {
        let bank = EchoelModalBank(modeCount: 16)
        bank.excite(velocity: 0.8, position: 0.3)
        XCTAssertTrue(bank.isActive())
    }

    func testNoteOnOff() {
        let bank = EchoelModalBank(modeCount: 16)
        bank.noteOn(frequency: 440, velocity: 0.9)
        XCTAssertTrue(bank.isActive())
        bank.noteOff()
        // After noteOff, bank may still be active during release tail — that's valid
        // Render enough frames to exhaust release, then verify silence
        var buffer = [Float](repeating: 0, count: 4096)
        for _ in 0..<10 {
            bank.render(buffer: &buffer, frameCount: 4096)
        }
        // After 40960 samples of release, bank should be inactive
        XCTAssertFalse(bank.isActive(), "Bank should be inactive after extended release")
    }

    func testRender() {
        let bank = EchoelModalBank(modeCount: 16, sampleRate: 48000, frameSize: 256)
        bank.noteOn(frequency: 440, velocity: 0.8)
        var buffer = [Float](repeating: 0, count: 256)
        bank.render(buffer: &buffer, frameCount: 256)
        // Should have non-zero output after excitation
        let hasNonZero = buffer.contains { $0 != 0 }
        XCTAssertTrue(hasNonZero)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN)
            XCTAssertFalse(sample.isInfinite)
        }
    }

    func testRenderSilentBeforeExcite() {
        let bank = EchoelModalBank(modeCount: 16)
        var buffer = [Float](repeating: 0, count: 128)
        bank.render(buffer: &buffer, frameCount: 128)
        for sample in buffer {
            XCTAssertEqual(sample, 0, accuracy: 0.001)
        }
    }

    func testMaterialPresetSwitch() {
        let bank = EchoelModalBank()
        for material in EchoelModalBank.MaterialPreset.allCases where material != .custom {
            bank.material = material
            XCTAssertEqual(bank.material, material)
        }
    }

    func testBioReactive() {
        let bank = EchoelModalBank(modeCount: 16)
        bank.noteOn(frequency: 440, velocity: 0.8)
        bank.applyBioReactive(coherence: 0.8, hrvVariability: 0.5, breathPhase: 0.3)
        var buffer = [Float](repeating: 0, count: 128)
        bank.render(buffer: &buffer, frameCount: 128)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN)
        }
    }

    func testMorphMaterials() {
        let bank = EchoelModalBank(modeCount: 16, sampleRate: 48000, frameSize: 64)
        bank.morphMaterials(from: .bell, to: .plate, blend: 0.5)
        bank.noteOn(frequency: 440, velocity: 0.8)
        var buffer = [Float](repeating: 0, count: 64)
        bank.render(buffer: &buffer, frameCount: 64)
        // Verify morphed output produces sound and no NaN/Inf
        let hasNonZero = buffer.contains { $0 != 0 }
        XCTAssertTrue(hasNonZero, "Morphed material should produce non-zero output")
        for sample in buffer {
            XCTAssertFalse(sample.isNaN, "Morphed output must not contain NaN")
            XCTAssertFalse(sample.isInfinite, "Morphed output must not contain Inf")
        }
    }

    func testSpectralEnvelope() {
        let bank = EchoelModalBank(modeCount: 16)
        let envelope = bank.getSpectralEnvelope()
        XCTAssertEqual(envelope.count, 16)
    }

    func testModeFrequencies() {
        let bank = EchoelModalBank(modeCount: 16)
        let freqs = bank.getModeFrequencies()
        XCTAssertEqual(freqs.count, 16)
    }

    func testReset() {
        let bank = EchoelModalBank(modeCount: 16)
        bank.noteOn(frequency: 440, velocity: 1.0)
        bank.reset()
        XCTAssertFalse(bank.isActive())
    }

    func testDamping() {
        let bank = EchoelModalBank(modeCount: 16)
        bank.damping = 0.9
        XCTAssertEqual(bank.damping, 0.9, accuracy: 0.01)
    }

    func testStiffness() {
        let bank = EchoelModalBank(modeCount: 16)
        bank.stiffness = 0.5
        XCTAssertEqual(bank.stiffness, 0.5, accuracy: 0.01)
    }
}

// MARK: - EchoelCellular Tests

final class EchoelCellularTests: XCTestCase {

    func testInit() {
        let cellular = EchoelCellular(cellCount: 128, sampleRate: 48000)
        XCTAssertNotNil(cellular)
    }

    func testDefaultInit() {
        let cellular = EchoelCellular()
        XCTAssertEqual(cellular.frequency, 220.0)
    }

    func testSynthModeCases() {
        let cases = EchoelCellular.SynthMode.allCases
        XCTAssertEqual(cases.count, 4)
        XCTAssertTrue(cases.contains(.wavetable))
        XCTAssertTrue(cases.contains(.additive))
        XCTAssertTrue(cases.contains(.fm))
        XCTAssertTrue(cases.contains(.spectral2D))
    }

    func testSeedPatternCases() {
        let cases = EchoelCellular.SeedPattern.allCases
        XCTAssertEqual(cases.count, 5)
        XCTAssertTrue(cases.contains(.singleCenter))
        XCTAssertTrue(cases.contains(.random))
        XCTAssertTrue(cases.contains(.alternating))
        XCTAssertTrue(cases.contains(.pulse))
        XCTAssertTrue(cases.contains(.gradient))
    }

    func testCARule() {
        let rule = EchoelCellular.CARule(110)
        XCTAssertEqual(rule.number, 110)
    }

    func testCARuleEvaluate() {
        let rule = EchoelCellular.CARule(110)
        // Rule 110: binary 01101110
        // pattern 111=0, 110=1, 101=1, 100=0, 011=1, 010=1, 001=1, 000=0
        let result = rule.evaluate(left: 1, center: 1, right: 0)
        XCTAssertEqual(result, 1) // pattern 110 → 1
    }

    func testCARulePresets() {
        XCTAssertEqual(EchoelCellular.CARule.rule30.number, 30)
        XCTAssertEqual(EchoelCellular.CARule.rule90.number, 90)
        XCTAssertEqual(EchoelCellular.CARule.rule110.number, 110)
        XCTAssertEqual(EchoelCellular.CARule.rule150.number, 150)
    }

    func testHarmonicRules() {
        let rules = EchoelCellular.CARule.harmonicRules
        XCTAssertGreaterThan(rules.count, 0)
    }

    func testSeedPatterns() {
        let cellular = EchoelCellular(cellCount: 64)
        for pattern in EchoelCellular.SeedPattern.allCases {
            cellular.seed(pattern)
            let states = cellular.getCellStates()
            XCTAssertEqual(states.count, 64)
        }
    }

    func testRender() {
        let cellular = EchoelCellular(cellCount: 64, sampleRate: 48000)
        cellular.seed(.singleCenter)
        var buffer = [Float](repeating: 0, count: 256)
        cellular.render(buffer: &buffer, frameCount: 256)
        XCTAssertEqual(buffer.count, 256)
        for sample in buffer {
            XCTAssertFalse(sample.isNaN)
            XCTAssertFalse(sample.isInfinite)
        }
    }

    func testAllSynthModes() {
        let cellular = EchoelCellular(cellCount: 32, sampleRate: 48000)
        cellular.seed(.random)
        for mode in EchoelCellular.SynthMode.allCases {
            cellular.synthMode = mode
            var buffer = [Float](repeating: 0, count: 128)
            cellular.render(buffer: &buffer, frameCount: 128)
            for sample in buffer {
                XCTAssertFalse(sample.isNaN, "NaN in \(mode)")
                XCTAssertFalse(sample.isInfinite, "Inf in \(mode)")
            }
        }
    }

    func testGetGrid2D() {
        let cellular = EchoelCellular(cellCount: 32)
        cellular.seed(.singleCenter)
        let grid = cellular.getGrid2D()
        XCTAssertGreaterThan(grid.count, 0)
    }

    func testGetRuleNumber() {
        let cellular = EchoelCellular()
        cellular.rule = .rule110
        XCTAssertEqual(cellular.getRuleNumber(), 110)
    }

    func testBioReactiveCoherence() {
        let cellular = EchoelCellular(cellCount: 32)
        cellular.bioReactiveEnabled = true
        cellular.coherence = 0.8
        XCTAssertEqual(cellular.coherence, 0.8, accuracy: 0.01)
    }

    func testReset() {
        let cellular = EchoelCellular(cellCount: 32)
        cellular.seed(.random)
        cellular.reset()
        let states = cellular.getCellStates()
        // reset() re-seeds to .singleCenter: exactly one live cell at the center
        // (index cellCount/2), every other cell zero.
        for (i, state) in states.enumerated() {
            XCTAssertEqual(state, i == 32 / 2 ? 1 : 0, accuracy: 0.001)
        }
    }
}
#endif
