#if canImport(Accelerate)
// EchoelDDSPTests.swift
// Echoelmusic — Comprehensive tests for EchoelDDSP harmonic+noise synthesizer
//
// Tests initialization, enums, parameter defaults, spectral shapes,
// spectral morphing, timbre transfer, bio-reactive parameters, and reverb.

import XCTest
@testable import Echoelmusic

// MARK: - Initialization Tests

final class EchoelDDSPInitializationTests: XCTestCase {

    // MARK: - Default Initialization

    func testDefaultInit_harmonicCount() {
        let ddsp = EchoelDDSP()
        XCTAssertEqual(ddsp.harmonicCount, 64, "Default harmonicCount should be 64")
    }

    func testDefaultInit_noiseBandCount() {
        let ddsp = EchoelDDSP()
        XCTAssertEqual(ddsp.noiseBandCount, 65, "Default noiseBandCount should be 65")
    }

    func testDefaultInit_sampleRate() {
        let ddsp = EchoelDDSP()
        XCTAssertEqual(ddsp.sampleRate, 48000.0, "Default sampleRate should be 48000")
    }

    func testDefaultInit_frameSize() {
        let ddsp = EchoelDDSP()
        XCTAssertEqual(ddsp.frameSize, 192, "Default frameSize should be 192")
    }

    func testDefaultInit_allDefaultsAtOnce() {
        let ddsp = EchoelDDSP()
        XCTAssertEqual(ddsp.harmonicCount, 64)
        XCTAssertEqual(ddsp.noiseBandCount, 65)
        XCTAssertEqual(ddsp.sampleRate, 48000.0)
        XCTAssertEqual(ddsp.frameSize, 192)
    }

    // MARK: - Custom Initialization

    func testCustomInit_harmonicCount() {
        let ddsp = EchoelDDSP(harmonicCount: 32)
        XCTAssertEqual(ddsp.harmonicCount, 32)
    }

    func testCustomInit_noiseBandCount() {
        let ddsp = EchoelDDSP(noiseBandCount: 33)
        XCTAssertEqual(ddsp.noiseBandCount, 33)
    }

    func testCustomInit_sampleRate() {
        let ddsp = EchoelDDSP(sampleRate: 44100.0)
        XCTAssertEqual(ddsp.sampleRate, 44100.0)
    }

    func testCustomInit_frameSize() {
        let ddsp = EchoelDDSP(frameSize: 256)
        XCTAssertEqual(ddsp.frameSize, 256)
    }

    func testCustomInit_allParameters() {
        let ddsp = EchoelDDSP(
            harmonicCount: 128,
            noiseBandCount: 129,
            sampleRate: 96000.0,
            frameSize: 512
        )
        XCTAssertEqual(ddsp.harmonicCount, 128)
        XCTAssertEqual(ddsp.noiseBandCount, 129)
        XCTAssertEqual(ddsp.sampleRate, 96000.0)
        XCTAssertEqual(ddsp.frameSize, 512)
    }

    func testCustomInit_smallHarmonicCount() {
        let ddsp = EchoelDDSP(harmonicCount: 4)
        XCTAssertEqual(ddsp.harmonicCount, 4)
    }

    func testCustomInit_largeHarmonicCount() {
        let ddsp = EchoelDDSP(harmonicCount: 256)
        XCTAssertEqual(ddsp.harmonicCount, 256)
    }

    // MARK: - Array Size Matches Configuration

    func testHarmonicAmplitudes_sizeMatchesHarmonicCount_default() {
        let ddsp = EchoelDDSP()
        XCTAssertEqual(ddsp.harmonicAmplitudes.count, 64)
    }

    func testHarmonicAmplitudes_sizeMatchesHarmonicCount_custom() {
        let ddsp = EchoelDDSP(harmonicCount: 16)
        XCTAssertEqual(ddsp.harmonicAmplitudes.count, 16)
    }

    func testHarmonicAmplitudes_sizeMatchesHarmonicCount_large() {
        let ddsp = EchoelDDSP(harmonicCount: 128)
        XCTAssertEqual(ddsp.harmonicAmplitudes.count, 128)
    }

    func testNoiseMagnitudes_sizeMatchesNoiseBandCount_default() {
        let ddsp = EchoelDDSP()
        XCTAssertEqual(ddsp.noiseMagnitudes.count, 65)
    }

    func testNoiseMagnitudes_sizeMatchesNoiseBandCount_custom() {
        let ddsp = EchoelDDSP(noiseBandCount: 33)
        XCTAssertEqual(ddsp.noiseMagnitudes.count, 33)
    }

    func testNoiseMagnitudes_sizeMatchesNoiseBandCount_large() {
        let ddsp = EchoelDDSP(noiseBandCount: 257)
        XCTAssertEqual(ddsp.noiseMagnitudes.count, 257)
    }

    // MARK: - Minimum Value Clamping

    func testInit_harmonicCountClamped_zeroBecomesOne() {
        let ddsp = EchoelDDSP(harmonicCount: 0)
        XCTAssertEqual(ddsp.harmonicCount, 1, "harmonicCount should be clamped to minimum 1")
    }

    func testInit_harmonicCountClamped_negativeBecomesOne() {
        let ddsp = EchoelDDSP(harmonicCount: -5)
        XCTAssertEqual(ddsp.harmonicCount, 1, "Negative harmonicCount should be clamped to 1")
    }

    func testInit_noiseBandCountClamped_zeroBecomesOne() {
        let ddsp = EchoelDDSP(noiseBandCount: 0)
        XCTAssertEqual(ddsp.noiseBandCount, 1, "noiseBandCount should be clamped to minimum 1")
    }

    func testInit_noiseBandCountClamped_negativeBecomesOne() {
        let ddsp = EchoelDDSP(noiseBandCount: -10)
        XCTAssertEqual(ddsp.noiseBandCount, 1, "Negative noiseBandCount should be clamped to 1")
    }

    func testInit_sampleRateClamped_zeroBecomesOne() {
        let ddsp = EchoelDDSP(sampleRate: 0)
        XCTAssertEqual(ddsp.sampleRate, 1, "sampleRate should be clamped to minimum 1")
    }

    func testInit_sampleRateClamped_negativeBecomesOne() {
        let ddsp = EchoelDDSP(sampleRate: -44100)
        XCTAssertEqual(ddsp.sampleRate, 1, "Negative sampleRate should be clamped to 1")
    }

    func testInit_frameSizeClamped_zeroBecomesOne() {
        let ddsp = EchoelDDSP(frameSize: 0)
        XCTAssertEqual(ddsp.frameSize, 1, "frameSize should be clamped to minimum 1")
    }

    func testInit_frameSizeClamped_negativeBecomesOne() {
        let ddsp = EchoelDDSP(frameSize: -256)
        XCTAssertEqual(ddsp.frameSize, 1, "Negative frameSize should be clamped to 1")
    }

    func testInit_harmonicCountOne_isValid() {
        let ddsp = EchoelDDSP(harmonicCount: 1)
        XCTAssertEqual(ddsp.harmonicCount, 1)
        XCTAssertEqual(ddsp.harmonicAmplitudes.count, 1)
    }
}

// MARK: - NoiseColor Enum Tests

final class EchoelDDSPNoiseColorTests: XCTestCase {

    func testNoiseColor_allCasesCount() {
        let cases = EchoelDDSP.NoiseColor.allCases
        XCTAssertEqual(cases.count, 5, "NoiseColor should have exactly 5 cases")
    }

    func testNoiseColor_containsWhite() {
        XCTAssertTrue(EchoelDDSP.NoiseColor.allCases.contains(.white))
    }

    func testNoiseColor_containsPink() {
        XCTAssertTrue(EchoelDDSP.NoiseColor.allCases.contains(.pink))
    }

    func testNoiseColor_containsBrown() {
        XCTAssertTrue(EchoelDDSP.NoiseColor.allCases.contains(.brown))
    }

    func testNoiseColor_containsBlue() {
        XCTAssertTrue(EchoelDDSP.NoiseColor.allCases.contains(.blue))
    }

    func testNoiseColor_containsViolet() {
        XCTAssertTrue(EchoelDDSP.NoiseColor.allCases.contains(.violet))
    }

    func testNoiseColor_rawValue_white() {
        XCTAssertEqual(EchoelDDSP.NoiseColor.white.rawValue, "White")
    }

    func testNoiseColor_rawValue_pink() {
        XCTAssertEqual(EchoelDDSP.NoiseColor.pink.rawValue, "Pink")
    }

    func testNoiseColor_rawValue_brown() {
        XCTAssertEqual(EchoelDDSP.NoiseColor.brown.rawValue, "Brown")
    }

    func testNoiseColor_rawValue_blue() {
        XCTAssertEqual(EchoelDDSP.NoiseColor.blue.rawValue, "Blue")
    }

    func testNoiseColor_rawValue_violet() {
        XCTAssertEqual(EchoelDDSP.NoiseColor.violet.rawValue, "Violet")
    }

    func testNoiseColor_initFromRawValue_white() {
        let color = EchoelDDSP.NoiseColor(rawValue: "White")
        XCTAssertEqual(color, .white)
    }

    func testNoiseColor_initFromRawValue_pink() {
        let color = EchoelDDSP.NoiseColor(rawValue: "Pink")
        XCTAssertEqual(color, .pink)
    }

    func testNoiseColor_initFromRawValue_invalid() {
        let color = EchoelDDSP.NoiseColor(rawValue: "green")
        XCTAssertNil(color, "Invalid raw value should return nil")
    }

    func testNoiseColor_codableRoundTrip_white() throws {
        let original = EchoelDDSP.NoiseColor.white
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EchoelDDSP.NoiseColor.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testNoiseColor_codableRoundTrip_pink() throws {
        let original = EchoelDDSP.NoiseColor.pink
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EchoelDDSP.NoiseColor.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testNoiseColor_codableRoundTrip_brown() throws {
        let original = EchoelDDSP.NoiseColor.brown
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EchoelDDSP.NoiseColor.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testNoiseColor_codableRoundTrip_blue() throws {
        let original = EchoelDDSP.NoiseColor.blue
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EchoelDDSP.NoiseColor.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testNoiseColor_codableRoundTrip_violet() throws {
        let original = EchoelDDSP.NoiseColor.violet
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EchoelDDSP.NoiseColor.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testNoiseColor_codableRoundTrip_allCases() throws {
        for color in EchoelDDSP.NoiseColor.allCases {
            let data = try JSONEncoder().encode(color)
            let decoded = try JSONDecoder().decode(EchoelDDSP.NoiseColor.self, from: data)
            XCTAssertEqual(decoded, color, "Codable round-trip failed for \(color)")
        }
    }
}

// MARK: - SpectralShape Enum Tests

final class EchoelDDSPSpectralShapeTests: XCTestCase {

    func testSpectralShape_allCasesCount() {
        let cases = EchoelDDSP.SpectralShape.allCases
        XCTAssertEqual(cases.count, 8, "SpectralShape should have exactly 8 cases")
    }

    func testSpectralShape_containsNatural() {
        XCTAssertTrue(EchoelDDSP.SpectralShape.allCases.contains(.natural))
    }

    func testSpectralShape_containsBright() {
        XCTAssertTrue(EchoelDDSP.SpectralShape.allCases.contains(.bright))
    }

    func testSpectralShape_containsDark() {
        XCTAssertTrue(EchoelDDSP.SpectralShape.allCases.contains(.dark))
    }

    func testSpectralShape_containsFormant() {
        XCTAssertTrue(EchoelDDSP.SpectralShape.allCases.contains(.formant))
    }

    func testSpectralShape_containsMetallic() {
        XCTAssertTrue(EchoelDDSP.SpectralShape.allCases.contains(.metallic))
    }

    func testSpectralShape_containsHollow() {
        XCTAssertTrue(EchoelDDSP.SpectralShape.allCases.contains(.hollow))
    }

    func testSpectralShape_containsBell() {
        XCTAssertTrue(EchoelDDSP.SpectralShape.allCases.contains(.bell))
    }

    func testSpectralShape_containsFlat() {
        XCTAssertTrue(EchoelDDSP.SpectralShape.allCases.contains(.flat))
    }

    func testSpectralShape_rawValue_natural() {
        XCTAssertEqual(EchoelDDSP.SpectralShape.natural.rawValue, "Natural")
    }

    func testSpectralShape_rawValue_bright() {
        XCTAssertEqual(EchoelDDSP.SpectralShape.bright.rawValue, "Bright")
    }

    func testSpectralShape_rawValue_dark() {
        XCTAssertEqual(EchoelDDSP.SpectralShape.dark.rawValue, "Dark")
    }

    func testSpectralShape_rawValue_formant() {
        XCTAssertEqual(EchoelDDSP.SpectralShape.formant.rawValue, "Formant")
    }

    func testSpectralShape_rawValue_metallic() {
        XCTAssertEqual(EchoelDDSP.SpectralShape.metallic.rawValue, "Metallic")
    }

    func testSpectralShape_rawValue_hollow() {
        XCTAssertEqual(EchoelDDSP.SpectralShape.hollow.rawValue, "Hollow")
    }

    func testSpectralShape_rawValue_bell() {
        XCTAssertEqual(EchoelDDSP.SpectralShape.bell.rawValue, "Bell")
    }

    func testSpectralShape_rawValue_flat() {
        XCTAssertEqual(EchoelDDSP.SpectralShape.flat.rawValue, "Flat")
    }

    func testSpectralShape_initFromRawValue_natural() {
        let shape = EchoelDDSP.SpectralShape(rawValue: "Natural")
        XCTAssertEqual(shape, .natural)
    }

    func testSpectralShape_initFromRawValue_invalid() {
        let shape = EchoelDDSP.SpectralShape(rawValue: "invalid")
        XCTAssertNil(shape, "Invalid raw value should return nil")
    }

    func testSpectralShape_codableRoundTrip_allCases() throws {
        for shape in EchoelDDSP.SpectralShape.allCases {
            let data = try JSONEncoder().encode(shape)
            let decoded = try JSONDecoder().decode(EchoelDDSP.SpectralShape.self, from: data)
            XCTAssertEqual(decoded, shape, "Codable round-trip failed for \(shape)")
        }
    }

    func testSpectralShape_codableRoundTrip_natural() throws {
        let original = EchoelDDSP.SpectralShape.natural
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EchoelDDSP.SpectralShape.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testSpectralShape_codableRoundTrip_metallic() throws {
        let original = EchoelDDSP.SpectralShape.metallic
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EchoelDDSP.SpectralShape.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

// MARK: - EnvelopeCurve Enum Tests

final class EchoelDDSPEnvelopeCurveTests: XCTestCase {

    func testEnvelopeCurve_allCasesCount() {
        let cases = EchoelDDSP.EnvelopeCurve.allCases
        XCTAssertEqual(cases.count, 3, "EnvelopeCurve should have exactly 3 cases")
    }

    func testEnvelopeCurve_containsLinear() {
        XCTAssertTrue(EchoelDDSP.EnvelopeCurve.allCases.contains(.linear))
    }

    func testEnvelopeCurve_containsExponential() {
        XCTAssertTrue(EchoelDDSP.EnvelopeCurve.allCases.contains(.exponential))
    }

    func testEnvelopeCurve_containsLogarithmic() {
        XCTAssertTrue(EchoelDDSP.EnvelopeCurve.allCases.contains(.logarithmic))
    }

    func testEnvelopeCurve_rawValue_linear() {
        XCTAssertEqual(EchoelDDSP.EnvelopeCurve.linear.rawValue, "Linear")
    }

    func testEnvelopeCurve_rawValue_exponential() {
        XCTAssertEqual(EchoelDDSP.EnvelopeCurve.exponential.rawValue, "Exponential")
    }

    func testEnvelopeCurve_rawValue_logarithmic() {
        XCTAssertEqual(EchoelDDSP.EnvelopeCurve.logarithmic.rawValue, "Logarithmic")
    }

    func testEnvelopeCurve_initFromRawValue_linear() {
        let curve = EchoelDDSP.EnvelopeCurve(rawValue: "Linear")
        XCTAssertEqual(curve, .linear)
    }

    func testEnvelopeCurve_initFromRawValue_exponential() {
        let curve = EchoelDDSP.EnvelopeCurve(rawValue: "Exponential")
        XCTAssertEqual(curve, .exponential)
    }

    func testEnvelopeCurve_initFromRawValue_logarithmic() {
        let curve = EchoelDDSP.EnvelopeCurve(rawValue: "Logarithmic")
        XCTAssertEqual(curve, .logarithmic)
    }

    func testEnvelopeCurve_initFromRawValue_invalid() {
        let curve = EchoelDDSP.EnvelopeCurve(rawValue: "Cubic")
        XCTAssertNil(curve, "Invalid raw value should return nil")
    }
}

// MARK: - Parameter Default Tests

final class EchoelDDSPParameterDefaultTests: XCTestCase {

    private var ddsp: EchoelDDSP!

    override func setUp() {
        super.setUp()
        ddsp = EchoelDDSP()
    }

    override func tearDown() {
        ddsp = nil
        super.tearDown()
    }

    // MARK: - Harmonic Parameter Defaults

    func testDefault_frequency() {
        XCTAssertEqual(ddsp.frequency, 220.0, "Default frequency should be 220.0 Hz")
    }

    func testDefault_harmonicLevel() {
        XCTAssertEqual(ddsp.harmonicLevel, 0.8, accuracy: 0.001, "Default harmonicLevel should be 0.8")
    }

    func testDefault_harmonicity() {
        XCTAssertEqual(ddsp.harmonicity, 0.7, accuracy: 0.001, "Default harmonicity should be 0.7")
    }

    // MARK: - Noise Parameter Defaults

    func testDefault_noiseLevel() {
        XCTAssertEqual(ddsp.noiseLevel, 0.3, accuracy: 0.001, "Default noiseLevel should be 0.3")
    }

    // MARK: - Envelope Defaults

    func testDefault_amplitude() {
        XCTAssertEqual(ddsp.amplitude, 0.8, accuracy: 0.001, "Default amplitude should be 0.8")
    }

    func testDefault_attack() {
        XCTAssertEqual(ddsp.attack, 0.01, accuracy: 0.001, "Default attack should be 0.01")
    }

    func testDefault_decay() {
        XCTAssertEqual(ddsp.decay, 0.1, accuracy: 0.001, "Default decay should be 0.1")
    }

    func testDefault_sustain() {
        XCTAssertEqual(ddsp.sustain, 0.8, accuracy: 0.001, "Default sustain should be 0.8")
    }

    func testDefault_release() {
        XCTAssertEqual(ddsp.release, 0.3, accuracy: 0.001, "Default release should be 0.3")
    }

    func testDefault_envelopeCurve() {
        XCTAssertEqual(ddsp.envelopeCurve, .exponential, "Default envelopeCurve should be exponential")
    }

    // MARK: - Reverb Defaults

    func testDefault_reverbMix() {
        XCTAssertEqual(ddsp.reverbMix, 0.0, accuracy: 0.001, "Default reverbMix should be 0.0")
    }

    func testDefault_reverbDecay() {
        XCTAssertEqual(ddsp.reverbDecay, 1.5, accuracy: 0.001, "Default reverbDecay should be 1.5")
    }

    // MARK: - Spectral Control Defaults

    func testDefault_spectralShape() {
        XCTAssertEqual(ddsp.spectralShape, .natural, "Default spectralShape should be natural")
    }

    func testDefault_brightness() {
        XCTAssertEqual(ddsp.brightness, 0.5, accuracy: 0.001, "Default brightness should be 0.5")
    }

    // MARK: - Morphing Defaults

    func testDefault_morphTarget() {
        XCTAssertNil(ddsp.morphTarget, "Default morphTarget should be nil")
    }

    func testDefault_morphPosition() {
        XCTAssertEqual(ddsp.morphPosition, 0, accuracy: 0.001, "Default morphPosition should be 0")
    }

    // MARK: - Vibrato Defaults

    func testDefault_vibratoRate() {
        XCTAssertEqual(ddsp.vibratoRate, 0, accuracy: 0.001, "Default vibratoRate should be 0")
    }

    func testDefault_vibratoDepth() {
        XCTAssertEqual(ddsp.vibratoDepth, 0, accuracy: 0.001, "Default vibratoDepth should be 0")
    }

    // MARK: - Timbre Transfer Defaults

    func testDefault_timbreProfile() {
        XCTAssertNil(ddsp.timbreProfile, "Default timbreProfile should be nil")
    }

    func testDefault_timbreBlend() {
        XCTAssertEqual(ddsp.timbreBlend, 0, accuracy: 0.001, "Default timbreBlend should be 0")
    }

    // MARK: - Noise Color Default

    func testDefault_noiseColor() {
        XCTAssertEqual(ddsp.noiseColor, .pink, "Default noiseColor should be pink")
    }
}

// MARK: - Spectral Shape Control Tests

final class EchoelDDSPSpectralShapeControlTests: XCTestCase {

    private var ddsp: EchoelDDSP!

    override func setUp() {
        super.setUp()
        ddsp = EchoelDDSP()
    }

    override func tearDown() {
        ddsp = nil
        super.tearDown()
    }

    // MARK: - Setting Spectral Shape Updates Amplitudes

    func testSpectralShape_settingUpdatesHarmonicAmplitudes() {
        let before = ddsp.harmonicAmplitudes
        ddsp.spectralShape = .flat
        let after = ddsp.harmonicAmplitudes
        XCTAssertNotEqual(before, after, "Changing spectralShape should update harmonicAmplitudes")
    }

    func testSpectralShape_eachShapeProducesDifferentAmplitudes() {
        var amplitudeSets: [[Float]] = []
        for shape in EchoelDDSP.SpectralShape.allCases {
            ddsp.spectralShape = shape
            amplitudeSets.append(ddsp.harmonicAmplitudes)
        }
        // At minimum, natural and flat should differ
        let naturalIdx = EchoelDDSP.SpectralShape.allCases.firstIndex(of: .natural) ?? 0
        let flatIdx = EchoelDDSP.SpectralShape.allCases.firstIndex(of: .flat) ?? 7
        XCTAssertNotEqual(amplitudeSets[naturalIdx], amplitudeSets[flatIdx],
                          "Natural and flat shapes should produce different amplitude distributions")
    }

    // MARK: - Natural Shape: Amplitude Decreases

    func testNaturalShape_amplitudeDecreases() {
        ddsp.spectralShape = .natural
        let amps = ddsp.harmonicAmplitudes
        guard amps.count >= 4 else {
            XCTFail("Not enough harmonics for test")
            return
        }
        // First harmonic (fundamental) should be louder than later harmonics
        XCTAssertGreaterThan(amps[0], amps[3],
                             "Natural shape: fundamental should be louder than 4th harmonic")
    }

    func testNaturalShape_fundamentalIsLoudest() {
        ddsp.spectralShape = .natural
        let amps = ddsp.harmonicAmplitudes
        guard let maxAmp = amps.max(), amps.count > 0 else {
            XCTFail("Empty amplitudes")
            return
        }
        XCTAssertEqual(amps[0], maxAmp, accuracy: 0.001,
                       "Natural shape: fundamental should have the highest amplitude")
    }

    func testNaturalShape_monotonicDecreaseFirstEight() {
        ddsp.spectralShape = .natural
        let amps = ddsp.harmonicAmplitudes
        let count = min(8, amps.count)
        for i in 1..<count {
            XCTAssertLessThanOrEqual(amps[i], amps[i - 1] + 0.001,
                                     "Natural shape: amplitude should decrease or stay equal at harmonic \(i + 1)")
        }
    }

    // MARK: - Flat Shape: All Amplitudes Equal

    func testFlatShape_allAmplitudesEqual() {
        ddsp.spectralShape = .flat
        let amps = ddsp.harmonicAmplitudes
        guard let first = amps.first else {
            XCTFail("Empty amplitudes")
            return
        }
        for (index, amp) in amps.enumerated() {
            XCTAssertEqual(amp, first, accuracy: 0.001,
                           "Flat shape: all amplitudes should be equal, mismatch at index \(index)")
        }
    }

    func testFlatShape_amplitudesAreNormalized() {
        ddsp.spectralShape = .flat
        let amps = ddsp.harmonicAmplitudes
        guard let maxAmp = amps.max() else {
            XCTFail("Empty amplitudes")
            return
        }
        XCTAssertEqual(maxAmp, 1.0, accuracy: 0.01,
                       "Flat shape: max amplitude should be normalized to ~1.0")
    }

    // MARK: - Hollow Shape: Missing Even Harmonics

    func testHollowShape_evenHarmonicsAreZero() {
        ddsp.spectralShape = .hollow
        let amps = ddsp.harmonicAmplitudes
        // Even harmonics (index 1, 3, 5, ... = 2nd, 4th, 6th harmonic) should be 0
        let checkCount = min(10, amps.count)
        for i in 0..<checkCount where (i + 1) % 2 == 0 {
            XCTAssertEqual(amps[i], 0, accuracy: 0.001,
                           "Hollow shape: even harmonic \(i + 1) should be 0")
        }
    }

    func testHollowShape_oddHarmonicsNonZero() {
        ddsp.spectralShape = .hollow
        let amps = ddsp.harmonicAmplitudes
        // Odd harmonics (index 0, 2, 4 = 1st, 3rd, 5th harmonic) should be > 0
        let checkCount = min(5, amps.count)
        for i in stride(from: 0, to: checkCount, by: 2) {
            XCTAssertGreaterThan(amps[i], 0,
                                 "Hollow shape: odd harmonic \(i + 1) should be > 0")
        }
    }

    // MARK: - Metallic Shape: Enhanced Odd Harmonics

    func testMetallicShape_oddHarmonicsStronger() {
        ddsp.spectralShape = .metallic
        let amps = ddsp.harmonicAmplitudes
        guard amps.count >= 4 else {
            XCTFail("Not enough harmonics")
            return
        }
        // Odd harmonic (index 0, fundamental) should be much stronger than even (index 1, 2nd harmonic)
        XCTAssertGreaterThan(amps[0], amps[1],
                             "Metallic shape: odd harmonics should be stronger than even")
    }

    // MARK: - Brightness Affects Distribution

    func testBrightness_changingBrightnessAffectsAmplitudes() {
        ddsp.brightness = 0.0
        let darkAmps = ddsp.harmonicAmplitudes

        ddsp.brightness = 1.0
        let brightAmps = ddsp.harmonicAmplitudes

        XCTAssertNotEqual(darkAmps, brightAmps,
                          "Different brightness values should produce different amplitude distributions")
    }

    func testBrightness_higherBrightnessBoostsHighHarmonics() {
        ddsp.spectralShape = .natural
        ddsp.brightness = 0.0
        let darkHighHarmonic = ddsp.harmonicAmplitudes[min(15, ddsp.harmonicAmplitudes.count - 1)]

        ddsp.brightness = 1.0
        let brightHighHarmonic = ddsp.harmonicAmplitudes[min(15, ddsp.harmonicAmplitudes.count - 1)]

        XCTAssertGreaterThan(brightHighHarmonic, darkHighHarmonic,
                             "Higher brightness should boost higher harmonics relative to lower brightness")
    }

    func testBrightness_settingUpdatesAmplitudes() {
        let originalAmps = ddsp.harmonicAmplitudes
        ddsp.brightness = 0.9
        let newAmps = ddsp.harmonicAmplitudes
        XCTAssertNotEqual(originalAmps, newAmps,
                          "Setting brightness should trigger harmonic amplitude update")
    }

    // MARK: - Dark Shape: Steep Rolloff

    func testDarkShape_steepRolloff() {
        ddsp.spectralShape = .dark
        let amps = ddsp.harmonicAmplitudes
        guard amps.count >= 8 else {
            XCTFail("Not enough harmonics")
            return
        }
        // Dark shape should roll off more steeply than natural
        ddsp.spectralShape = .natural
        let naturalAmps = ddsp.harmonicAmplitudes

        ddsp.spectralShape = .dark
        let darkAmps = ddsp.harmonicAmplitudes

        // Higher harmonics should be relatively quieter in dark mode
        let highIdx = min(15, amps.count - 1)
        if naturalAmps[highIdx] > 0.001 {
            XCTAssertLessThan(darkAmps[highIdx], naturalAmps[highIdx],
                              "Dark shape should have steeper rolloff than natural at high harmonics")
        }
    }

    // MARK: - Amplitudes Are Normalized

    func testAllShapes_amplitudesAreNormalized() {
        for shape in EchoelDDSP.SpectralShape.allCases {
            ddsp.spectralShape = shape
            let amps = ddsp.harmonicAmplitudes
            guard let maxAmp = amps.max() else { continue }
            XCTAssertLessThanOrEqual(maxAmp, 1.01,
                                     "Shape \(shape): max amplitude should be normalized to <= 1.0")
            XCTAssertGreaterThanOrEqual(maxAmp, 0.0,
                                        "Shape \(shape): amplitudes should not be negative")
        }
    }

    func testAllShapes_noNegativeAmplitudes() {
        for shape in EchoelDDSP.SpectralShape.allCases {
            ddsp.spectralShape = shape
            for (index, amp) in ddsp.harmonicAmplitudes.enumerated() {
                XCTAssertGreaterThanOrEqual(amp, 0.0,
                                            "Shape \(shape): amplitude at index \(index) should not be negative")
            }
        }
    }

    func testAllShapes_noNaNAmplitudes() {
        for shape in EchoelDDSP.SpectralShape.allCases {
            ddsp.spectralShape = shape
            for (index, amp) in ddsp.harmonicAmplitudes.enumerated() {
                XCTAssertFalse(amp.isNaN,
                               "Shape \(shape): amplitude at index \(index) should not be NaN")
            }
        }
    }
}

// MARK: - Spectral Morphing Tests

final class EchoelDDSPSpectralMorphingTests: XCTestCase {

    private var ddsp: EchoelDDSP!

    override func setUp() {
        super.setUp()
        ddsp = EchoelDDSP()
    }

    override func tearDown() {
        ddsp = nil
        super.tearDown()
    }

    func testMorphTarget_nilByDefault() {
        XCTAssertNil(ddsp.morphTarget, "morphTarget should be nil by default")
    }

    func testMorphPosition_zeroByDefault() {
        XCTAssertEqual(ddsp.morphPosition, 0, accuracy: 0.001)
    }

    func testMorphing_settingTargetAndPositionBlendsShapes() {
        // Get pure natural shape
        ddsp.spectralShape = .natural
        ddsp.morphTarget = nil
        ddsp.morphPosition = 0
        let naturalAmps = ddsp.harmonicAmplitudes

        // Get pure flat shape
        ddsp.spectralShape = .flat
        ddsp.morphTarget = nil
        let flatAmps = ddsp.harmonicAmplitudes

        // Now set morphing: natural -> flat at 50%
        ddsp.spectralShape = .natural
        ddsp.morphTarget = .flat
        ddsp.morphPosition = 0.5
        // Trigger update by reassigning spectralShape (didSet fires update)
        ddsp.spectralShape = .natural
        let morphedAmps = ddsp.harmonicAmplitudes

        // Morphed should differ from both pure shapes
        let diffFromNatural = zip(morphedAmps, naturalAmps).map { abs($0 - $1) }.reduce(0, +)
        let diffFromFlat = zip(morphedAmps, flatAmps).map { abs($0 - $1) }.reduce(0, +)

        XCTAssertGreaterThan(diffFromNatural, 0.01,
                             "Morphed amplitudes should differ from pure natural")
        XCTAssertGreaterThan(diffFromFlat, 0.01,
                             "Morphed amplitudes should differ from pure flat")
    }

    func testMorphing_positionZero_pureSource() {
        ddsp.spectralShape = .natural
        ddsp.morphTarget = nil
        let pureNatural = ddsp.harmonicAmplitudes

        ddsp.morphTarget = .flat
        ddsp.morphPosition = 0
        // Re-trigger update
        ddsp.spectralShape = .natural
        let morphedAtZero = ddsp.harmonicAmplitudes

        // At position 0, morphed should equal pure source (natural)
        for i in 0..<min(pureNatural.count, morphedAtZero.count) {
            XCTAssertEqual(morphedAtZero[i], pureNatural[i], accuracy: 0.01,
                           "Morph position 0 should produce pure source at harmonic \(i)")
        }
    }

    func testMorphing_positionOne_pureTarget() {
        // Get pure flat shape amplitudes
        ddsp.spectralShape = .flat
        ddsp.morphTarget = nil
        let pureFlat = ddsp.harmonicAmplitudes

        // Now morph natural -> flat at position 1.0
        ddsp.spectralShape = .natural
        ddsp.morphTarget = .flat
        ddsp.morphPosition = 1.0
        // Re-trigger
        ddsp.spectralShape = .natural
        let morphedAtOne = ddsp.harmonicAmplitudes

        // At position 1, morphed should approximate pure target (flat)
        for i in 0..<min(pureFlat.count, morphedAtOne.count) {
            XCTAssertEqual(morphedAtOne[i], pureFlat[i], accuracy: 0.05,
                           "Morph position 1 should approximate pure target at harmonic \(i)")
        }
    }

    func testMorphing_progressiveBlend() {
        ddsp.spectralShape = .natural
        ddsp.morphTarget = .flat

        var previousDiffFromNatural: Float = 0

        ddsp.morphTarget = nil
        ddsp.spectralShape = .natural
        let naturalAmps = ddsp.harmonicAmplitudes

        ddsp.morphTarget = .flat
        for position in stride(from: Float(0.0), through: 1.0, by: 0.25) {
            ddsp.morphPosition = position
            ddsp.spectralShape = .natural  // trigger update
            let currentAmps = ddsp.harmonicAmplitudes
            let diff = zip(currentAmps, naturalAmps).map { abs($0 - $1) }.reduce(0, +)
            if position > 0 {
                XCTAssertGreaterThanOrEqual(diff, previousDiffFromNatural - 0.01,
                                            "Higher morph position should deviate more from source")
            }
            previousDiffFromNatural = diff
        }
    }

    func testMorphing_noTargetNoEffect() {
        ddsp.spectralShape = .natural
        ddsp.morphTarget = nil
        ddsp.morphPosition = 0.5
        let ampsWithoutTarget = ddsp.harmonicAmplitudes

        ddsp.morphPosition = 0
        let ampsNoMorph = ddsp.harmonicAmplitudes

        // Without a target, morphPosition should not affect anything
        for i in 0..<min(ampsWithoutTarget.count, ampsNoMorph.count) {
            XCTAssertEqual(ampsWithoutTarget[i], ampsNoMorph[i], accuracy: 0.001,
                           "Without morphTarget, morphPosition should have no effect at harmonic \(i)")
        }
    }

    func testMorphing_amplitudesRemainNormalized() {
        ddsp.spectralShape = .natural
        ddsp.morphTarget = .metallic
        ddsp.morphPosition = 0.5
        ddsp.spectralShape = .natural  // trigger
        let amps = ddsp.harmonicAmplitudes
        guard let maxAmp = amps.max() else {
            XCTFail("Empty amplitudes")
            return
        }
        XCTAssertLessThanOrEqual(maxAmp, 1.01, "Morphed amplitudes should be normalized")
    }
}

// MARK: - Timbre Transfer Tests

final class EchoelDDSPTimbreTransferTests: XCTestCase {

    private var ddsp: EchoelDDSP!

    override func setUp() {
        super.setUp()
        ddsp = EchoelDDSP()
    }

    override func tearDown() {
        ddsp = nil
        super.tearDown()
    }

    func testTimbreProfile_nilByDefault() {
        XCTAssertNil(ddsp.timbreProfile, "timbreProfile should be nil by default")
    }

    func testTimbreBlend_zeroByDefault() {
        XCTAssertEqual(ddsp.timbreBlend, 0, accuracy: 0.001)
    }

    func testTimbreTransfer_settingProfileAndBlendApplies() {
        // Get amplitudes without timbre
        ddsp.spectralShape = .natural
        let originalAmps = ddsp.harmonicAmplitudes

        // Create a custom timbre profile (e.g., strong even harmonics)
        var profile = [Float](repeating: 0, count: ddsp.harmonicCount)
        for i in 0..<profile.count where (i + 1) % 2 == 0 {
            profile[i] = 1.0
        }

        ddsp.timbreProfile = profile
        ddsp.timbreBlend = 0.5
        // Trigger update
        ddsp.spectralShape = .natural
        let blendedAmps = ddsp.harmonicAmplitudes

        let diff = zip(originalAmps, blendedAmps).map { abs($0 - $1) }.reduce(0, +)
        XCTAssertGreaterThan(diff, 0.01,
                             "Setting timbreProfile and timbreBlend > 0 should modify amplitudes")
    }

    func testTimbreTransfer_blendZero_noEffect() {
        ddsp.spectralShape = .natural
        let originalAmps = ddsp.harmonicAmplitudes

        var profile = [Float](repeating: 1.0, count: ddsp.harmonicCount)
        for i in 0..<profile.count { profile[i] = Float(i) / Float(profile.count) }

        ddsp.timbreProfile = profile
        ddsp.timbreBlend = 0
        ddsp.spectralShape = .natural  // trigger
        let blendedAmps = ddsp.harmonicAmplitudes

        // With blend at 0, should be identical to original (after normalization)
        for i in 0..<min(originalAmps.count, blendedAmps.count) {
            XCTAssertEqual(blendedAmps[i], originalAmps[i], accuracy: 0.01,
                           "timbreBlend 0 should leave amplitudes unchanged at harmonic \(i)")
        }
    }

    func testTimbreTransfer_blendOne_fullProfile() {
        // Create a distinctive profile
        var profile = [Float](repeating: 0, count: ddsp.harmonicCount)
        for i in 0..<profile.count {
            // Reverse amplitude: higher harmonics louder
            profile[i] = Float(i + 1) / Float(ddsp.harmonicCount)
        }

        ddsp.timbreProfile = profile
        ddsp.timbreBlend = 1.0
        ddsp.spectralShape = .natural  // trigger
        let blendedAmps = ddsp.harmonicAmplitudes

        // At blend 1.0, should be heavily influenced by profile
        // The exact values depend on normalization, but later harmonics
        // should be relatively stronger than in natural shape
        guard blendedAmps.count >= 4 else {
            XCTFail("Not enough harmonics")
            return
        }
        // In the profile, later harmonics are louder
        // After normalization, last harmonic should be relatively strong
        let lastIdx = blendedAmps.count - 1
        XCTAssertGreaterThan(blendedAmps[lastIdx], 0.5,
                             "At timbreBlend 1.0, profile's emphasis on high harmonics should be reflected")
    }

    func testTimbreTransfer_profileSmallerThanHarmonicCount_noEffect() {
        // Profile smaller than harmonicCount should not be applied
        // (source: `profile.count >= harmonicCount` guard)
        let smallProfile = [Float](repeating: 1.0, count: ddsp.harmonicCount - 1)
        ddsp.spectralShape = .natural
        let originalAmps = ddsp.harmonicAmplitudes

        ddsp.timbreProfile = smallProfile
        ddsp.timbreBlend = 1.0
        ddsp.spectralShape = .natural  // trigger
        let afterAmps = ddsp.harmonicAmplitudes

        for i in 0..<min(originalAmps.count, afterAmps.count) {
            XCTAssertEqual(afterAmps[i], originalAmps[i], accuracy: 0.01,
                           "Profile smaller than harmonicCount should have no effect at harmonic \(i)")
        }
    }

    func testTimbreTransfer_profileNil_noEffect() {
        ddsp.spectralShape = .natural
        let originalAmps = ddsp.harmonicAmplitudes

        ddsp.timbreProfile = nil
        ddsp.timbreBlend = 1.0
        ddsp.spectralShape = .natural
        let afterAmps = ddsp.harmonicAmplitudes

        for i in 0..<min(originalAmps.count, afterAmps.count) {
            XCTAssertEqual(afterAmps[i], originalAmps[i], accuracy: 0.01,
                           "Nil timbreProfile should have no effect at harmonic \(i)")
        }
    }
}

// MARK: - Bio-Reactive Parameter Tests

final class EchoelDDSPBioReactiveTests: XCTestCase {

    private var ddsp: EchoelDDSP!

    override func setUp() {
        super.setUp()
        ddsp = EchoelDDSP()
    }

    override func tearDown() {
        ddsp = nil
        super.tearDown()
    }

    func testVibratoRate_defaultIsZero() {
        XCTAssertEqual(ddsp.vibratoRate, 0, accuracy: 0.001)
    }

    func testVibratoDepth_defaultIsZero() {
        XCTAssertEqual(ddsp.vibratoDepth, 0, accuracy: 0.001)
    }

    func testVibratoRate_settingValidValue() {
        ddsp.vibratoRate = 5.0
        XCTAssertEqual(ddsp.vibratoRate, 5.0, accuracy: 0.001)
    }

    func testVibratoRate_settingTypicalRange() {
        ddsp.vibratoRate = 6.5
        XCTAssertEqual(ddsp.vibratoRate, 6.5, accuracy: 0.001)
    }

    func testVibratoDepth_settingValidValue() {
        ddsp.vibratoDepth = 0.5
        XCTAssertEqual(ddsp.vibratoDepth, 0.5, accuracy: 0.001)
    }

    func testVibratoDepth_settingSmallValue() {
        ddsp.vibratoDepth = 0.1
        XCTAssertEqual(ddsp.vibratoDepth, 0.1, accuracy: 0.001)
    }

    func testVibratoDepth_settingLargeValue() {
        ddsp.vibratoDepth = 2.0
        XCTAssertEqual(ddsp.vibratoDepth, 2.0, accuracy: 0.001)
    }

    func testFrequency_settingValidValues() {
        ddsp.frequency = 440.0
        XCTAssertEqual(ddsp.frequency, 440.0)

        ddsp.frequency = 20.0
        XCTAssertEqual(ddsp.frequency, 20.0)

        ddsp.frequency = 2000.0
        XCTAssertEqual(ddsp.frequency, 2000.0)
    }

    func testHarmonicity_settingRange() {
        ddsp.harmonicity = 0.0
        XCTAssertEqual(ddsp.harmonicity, 0.0, accuracy: 0.001)

        ddsp.harmonicity = 1.0
        XCTAssertEqual(ddsp.harmonicity, 1.0, accuracy: 0.001)

        ddsp.harmonicity = 0.5
        XCTAssertEqual(ddsp.harmonicity, 0.5, accuracy: 0.001)
    }

    func testAmplitude_settingRange() {
        ddsp.amplitude = 0.0
        XCTAssertEqual(ddsp.amplitude, 0.0, accuracy: 0.001)

        ddsp.amplitude = 1.0
        XCTAssertEqual(ddsp.amplitude, 1.0, accuracy: 0.001)
    }

    func testHarmonicLevel_settingRange() {
        ddsp.harmonicLevel = 0.0
        XCTAssertEqual(ddsp.harmonicLevel, 0.0, accuracy: 0.001)

        ddsp.harmonicLevel = 1.0
        XCTAssertEqual(ddsp.harmonicLevel, 1.0, accuracy: 0.001)
    }

    func testNoiseLevel_settingRange() {
        ddsp.noiseLevel = 0.0
        XCTAssertEqual(ddsp.noiseLevel, 0.0, accuracy: 0.001)

        ddsp.noiseLevel = 1.0
        XCTAssertEqual(ddsp.noiseLevel, 1.0, accuracy: 0.001)
    }

    func testADSR_settingCustomValues() {
        ddsp.attack = 0.05
        ddsp.decay = 0.2
        ddsp.sustain = 0.6
        ddsp.release = 0.5

        XCTAssertEqual(ddsp.attack, 0.05, accuracy: 0.001)
        XCTAssertEqual(ddsp.decay, 0.2, accuracy: 0.001)
        XCTAssertEqual(ddsp.sustain, 0.6, accuracy: 0.001)
        XCTAssertEqual(ddsp.release, 0.5, accuracy: 0.001)
    }
}

// MARK: - Reverb Tests

final class EchoelDDSPReverbTests: XCTestCase {

    private var ddsp: EchoelDDSP!

    override func setUp() {
        super.setUp()
        ddsp = EchoelDDSP()
    }

    override func tearDown() {
        ddsp = nil
        super.tearDown()
    }

    func testReverbMix_default() {
        XCTAssertEqual(ddsp.reverbMix, 0.0, accuracy: 0.001)
    }

    func testReverbDecay_default() {
        XCTAssertEqual(ddsp.reverbDecay, 1.5, accuracy: 0.001)
    }

    func testUpdateReverbDecay_changesValue() {
        ddsp.updateReverbDecay(2.5)
        XCTAssertEqual(ddsp.reverbDecay, 2.5, accuracy: 0.001)
    }

    func testUpdateReverbDecay_smallValue() {
        ddsp.updateReverbDecay(0.1)
        XCTAssertEqual(ddsp.reverbDecay, 0.1, accuracy: 0.001)
    }

    func testUpdateReverbDecay_largeValue() {
        ddsp.updateReverbDecay(10.0)
        XCTAssertEqual(ddsp.reverbDecay, 10.0, accuracy: 0.001)
    }

    func testUpdateReverbDecay_multipleUpdates() {
        ddsp.updateReverbDecay(1.0)
        XCTAssertEqual(ddsp.reverbDecay, 1.0, accuracy: 0.001)

        ddsp.updateReverbDecay(3.0)
        XCTAssertEqual(ddsp.reverbDecay, 3.0, accuracy: 0.001)

        ddsp.updateReverbDecay(0.5)
        XCTAssertEqual(ddsp.reverbDecay, 0.5, accuracy: 0.001)
    }

    func testReverbMix_settingValues() {
        ddsp.reverbMix = 0.5
        XCTAssertEqual(ddsp.reverbMix, 0.5, accuracy: 0.001)

        ddsp.reverbMix = 1.0
        XCTAssertEqual(ddsp.reverbMix, 1.0, accuracy: 0.001)

        ddsp.reverbMix = 0.0
        XCTAssertEqual(ddsp.reverbMix, 0.0, accuracy: 0.001)
    }
}

// MARK: - Noise Color Behavior Tests

final class EchoelDDSPNoiseColorBehaviorTests: XCTestCase {

    private var ddsp: EchoelDDSP!

    override func setUp() {
        super.setUp()
        ddsp = EchoelDDSP()
    }

    override func tearDown() {
        ddsp = nil
        super.tearDown()
    }

    func testNoiseColor_defaultIsPink() {
        XCTAssertEqual(ddsp.noiseColor, .pink)
    }

    func testNoiseColor_settingWhiteUpdatesNoiseMagnitudes() {
        let beforeMagnitudes = ddsp.noiseMagnitudes
        ddsp.noiseColor = .white
        let afterMagnitudes = ddsp.noiseMagnitudes
        // White noise has uniform magnitudes, pink does not
        XCTAssertNotEqual(beforeMagnitudes, afterMagnitudes,
                          "Changing noise color from pink to white should update magnitudes")
    }

    func testNoiseColor_whiteHasUniformMagnitudes() {
        ddsp.noiseColor = .white
        let mags = ddsp.noiseMagnitudes
        guard let first = mags.first, mags.count > 1 else {
            XCTFail("Not enough noise bands")
            return
        }
        // After normalization, white noise should have equal magnitudes
        for (index, mag) in mags.enumerated() {
            XCTAssertEqual(mag, first, accuracy: 0.01,
                           "White noise: all magnitudes should be equal, mismatch at band \(index)")
        }
    }

    func testNoiseColor_eachColorProducesDifferentProfile() {
        var profiles: [EchoelDDSP.NoiseColor: [Float]] = [:]
        for color in EchoelDDSP.NoiseColor.allCases {
            ddsp.noiseColor = color
            profiles[color] = ddsp.noiseMagnitudes
        }
        // White and pink should differ
        if let white = profiles[.white], let pink = profiles[.pink] {
            XCTAssertNotEqual(white, pink, "White and pink noise profiles should differ")
        }
        // Brown and blue should differ
        if let brown = profiles[.brown], let blue = profiles[.blue] {
            XCTAssertNotEqual(brown, blue, "Brown and blue noise profiles should differ")
        }
    }

    func testNoiseColor_noiseMagnitudesAreNormalized() {
        for color in EchoelDDSP.NoiseColor.allCases {
            ddsp.noiseColor = color
            let mags = ddsp.noiseMagnitudes
            guard let maxMag = mags.max() else { continue }
            XCTAssertLessThanOrEqual(maxMag, 1.01,
                                     "Noise color \(color): magnitudes should be normalized to <= 1.0")
        }
    }

    func testNoiseColor_noNegativeMagnitudes() {
        for color in EchoelDDSP.NoiseColor.allCases {
            ddsp.noiseColor = color
            for (index, mag) in ddsp.noiseMagnitudes.enumerated() {
                XCTAssertGreaterThanOrEqual(mag, 0.0,
                                            "Noise color \(color): magnitude at band \(index) should not be negative")
            }
        }
    }

    func testNoiseColor_noNaNMagnitudes() {
        for color in EchoelDDSP.NoiseColor.allCases {
            ddsp.noiseColor = color
            for (index, mag) in ddsp.noiseMagnitudes.enumerated() {
                XCTAssertFalse(mag.isNaN,
                               "Noise color \(color): magnitude at band \(index) should not be NaN")
            }
        }
    }
}

// MARK: - Multiple Instance Tests

final class EchoelDDSPMultipleInstanceTests: XCTestCase {

    func testMultipleInstances_independentState() {
        let ddsp1 = EchoelDDSP(harmonicCount: 32)
        let ddsp2 = EchoelDDSP(harmonicCount: 64)

        ddsp1.frequency = 440.0
        ddsp2.frequency = 880.0

        XCTAssertEqual(ddsp1.frequency, 440.0)
        XCTAssertEqual(ddsp2.frequency, 880.0)
        XCTAssertEqual(ddsp1.harmonicCount, 32)
        XCTAssertEqual(ddsp2.harmonicCount, 64)
    }

    func testMultipleInstances_independentSpectralShape() {
        let ddsp1 = EchoelDDSP()
        let ddsp2 = EchoelDDSP()

        ddsp1.spectralShape = .flat
        ddsp2.spectralShape = .dark

        XCTAssertEqual(ddsp1.spectralShape, .flat)
        XCTAssertEqual(ddsp2.spectralShape, .dark)
        XCTAssertNotEqual(ddsp1.harmonicAmplitudes, ddsp2.harmonicAmplitudes)
    }

    func testMultipleInstances_independentNoiseColor() {
        let ddsp1 = EchoelDDSP()
        let ddsp2 = EchoelDDSP()

        ddsp1.noiseColor = .white
        ddsp2.noiseColor = .brown

        XCTAssertEqual(ddsp1.noiseColor, .white)
        XCTAssertEqual(ddsp2.noiseColor, .brown)
    }
}

// MARK: - Envelope Curve Setting Tests

final class EchoelDDSPEnvelopeSettingTests: XCTestCase {

    private var ddsp: EchoelDDSP!

    override func setUp() {
        super.setUp()
        ddsp = EchoelDDSP()
    }

    override func tearDown() {
        ddsp = nil
        super.tearDown()
    }

    func testEnvelopeCurve_defaultIsExponential() {
        XCTAssertEqual(ddsp.envelopeCurve, .exponential)
    }

    func testEnvelopeCurve_settingLinear() {
        ddsp.envelopeCurve = .linear
        XCTAssertEqual(ddsp.envelopeCurve, .linear)
    }

    func testEnvelopeCurve_settingLogarithmic() {
        ddsp.envelopeCurve = .logarithmic
        XCTAssertEqual(ddsp.envelopeCurve, .logarithmic)
    }

    func testEnvelopeCurve_settingBackToExponential() {
        ddsp.envelopeCurve = .linear
        ddsp.envelopeCurve = .exponential
        XCTAssertEqual(ddsp.envelopeCurve, .exponential)
    }
}

// MARK: - Brightness Range Tests

final class EchoelDDSPBrightnessRangeTests: XCTestCase {

    private var ddsp: EchoelDDSP!

    override func setUp() {
        super.setUp()
        ddsp = EchoelDDSP()
    }

    override func tearDown() {
        ddsp = nil
        super.tearDown()
    }

    func testBrightness_default() {
        XCTAssertEqual(ddsp.brightness, 0.5, accuracy: 0.001)
    }

    func testBrightness_settingZero() {
        ddsp.brightness = 0.0
        XCTAssertEqual(ddsp.brightness, 0.0, accuracy: 0.001)
    }

    func testBrightness_settingOne() {
        ddsp.brightness = 1.0
        XCTAssertEqual(ddsp.brightness, 1.0, accuracy: 0.001)
    }

    func testBrightness_settingMidValue() {
        ddsp.brightness = 0.75
        XCTAssertEqual(ddsp.brightness, 0.75, accuracy: 0.001)
    }

    func testBrightness_amplitudesStayFinite() {
        for bright in stride(from: Float(0.0), through: 1.0, by: 0.1) {
            ddsp.brightness = bright
            for (index, amp) in ddsp.harmonicAmplitudes.enumerated() {
                XCTAssertTrue(amp.isFinite,
                              "Brightness \(bright): amplitude at \(index) should be finite")
            }
        }
    }
}

// MARK: - Harmonic Amplitudes Direct Manipulation Tests

final class EchoelDDSPHarmonicAmplitudesTests: XCTestCase {

    func testHarmonicAmplitudes_canBeSetDirectly() {
        let ddsp = EchoelDDSP(harmonicCount: 8)
        var customAmps = [Float](repeating: 0, count: 8)
        customAmps[0] = 1.0
        customAmps[1] = 0.5
        customAmps[2] = 0.25
        ddsp.harmonicAmplitudes = customAmps

        XCTAssertEqual(ddsp.harmonicAmplitudes[0], 1.0, accuracy: 0.001)
        XCTAssertEqual(ddsp.harmonicAmplitudes[1], 0.5, accuracy: 0.001)
        XCTAssertEqual(ddsp.harmonicAmplitudes[2], 0.25, accuracy: 0.001)
    }

    func testNoiseMagnitudes_canBeSetDirectly() {
        let ddsp = EchoelDDSP(noiseBandCount: 8)
        var customMags = [Float](repeating: 0.5, count: 8)
        customMags[0] = 1.0
        ddsp.noiseMagnitudes = customMags

        XCTAssertEqual(ddsp.noiseMagnitudes[0], 1.0, accuracy: 0.001)
        XCTAssertEqual(ddsp.noiseMagnitudes[1], 0.5, accuracy: 0.001)
    }

    func testHarmonicAmplitudes_initializedAfterInit() {
        let ddsp = EchoelDDSP(harmonicCount: 16)
        // After init, spectral envelope is applied, so amplitudes should not all be zero
        let hasNonZero = ddsp.harmonicAmplitudes.contains { $0 > 0 }
        XCTAssertTrue(hasNonZero, "After initialization, at least some harmonic amplitudes should be > 0")
    }

    func testNoiseMagnitudes_initializedAfterInit() {
        let ddsp = EchoelDDSP(noiseBandCount: 16)
        // After init, noise profile is applied, so magnitudes should not all be zero
        let hasNonZero = ddsp.noiseMagnitudes.contains { $0 > 0 }
        XCTAssertTrue(hasNonZero, "After initialization, at least some noise magnitudes should be > 0")
    }
}

// MARK: - Key-follow stereo pan (stable per-pitch image)

/// Guards the v10.40.0 stereo fix: pan must be a stable function of PITCH
/// (low→left, high→right), never of the reused voice-slot index.
final class EchoelPolyDDSPKeyFollowPanTests: XCTestCase {

    func testKeyFollowPan_centerOfSpanIsCentered() {
        // C4 (note 60) is the midpoint of the C2…C6 span → dead-centre.
        XCTAssertEqual(EchoelPolyDDSP.keyFollowPan(forNote: 60), 0, accuracy: 1e-6)
    }

    func testKeyFollowPan_lowLeftHighRight() {
        let low = EchoelPolyDDSP.keyFollowPan(forNote: 36)   // C2
        let high = EchoelPolyDDSP.keyFollowPan(forNote: 84)  // C6
        XCTAssertLessThan(low, 0, "low notes pan left")
        XCTAssertGreaterThan(high, 0, "high notes pan right")
        XCTAssertEqual(low, -0.35, accuracy: 1e-6)           // full ±spread at the edges
        XCTAssertEqual(high, 0.35, accuracy: 1e-6)
    }

    func testKeyFollowPan_monotonicAndClampedBeyondSpan() {
        // Strictly increasing across the musical span…
        XCTAssertLessThan(EchoelPolyDDSP.keyFollowPan(forNote: 48),
                          EchoelPolyDDSP.keyFollowPan(forNote: 72))
        // …and clamped (never exceeds ±spread) for notes outside C2…C6.
        XCTAssertEqual(EchoelPolyDDSP.keyFollowPan(forNote: 12), -0.35, accuracy: 1e-6)
        XCTAssertEqual(EchoelPolyDDSP.keyFollowPan(forNote: 120), 0.35, accuracy: 1e-6)
    }

    func testKeyFollowPan_isPitchStableNotSlotDependent() {
        // The whole point of the fix: the SAME pitch always yields the SAME pan,
        // regardless of how many other notes sound / which slot it reuses.
        let a = EchoelPolyDDSP.keyFollowPan(forNote: 67)
        let b = EchoelPolyDDSP.keyFollowPan(forNote: 67)
        XCTAssertEqual(a, b, accuracy: 0, "pan must depend only on pitch")
    }
}

// MARK: - Analog Pitch Drift (realism) Tests

/// Guards the per-note analog pitch drift (`pitchDriftCents`): a slow aperiodic
/// wander that makes chords beat and sustains breathe. Must stay subtle, finite,
/// deterministic (audio-thread safe), and be a true no-op when disabled.
final class EchoelDDSPPitchDriftTests: XCTestCase {

    /// Render a pure-tonal note past the onset transient and return the tail buffer.
    private func renderTail(_ ddsp: EchoelDDSP, frames: Int = 8192) -> [Float] {
        ddsp.frequency = 220.0
        ddsp.harmonicity = 1.0      // fully tonal → noise path off (onset chiff decays out)
        ddsp.noiseLevel = 0.0
        ddsp.noteOn()
        var buffer = [Float](repeating: 0, count: frames)
        ddsp.render(buffer: &buffer, frameCount: frames, stereo: false)
        return buffer
    }

    func testDefault_isSubtleNonZero() {
        // Small default so every voice breathes (mirrors the inharmonicity default),
        // yet well under a perceptible detune (<10 cents).
        let ddsp = EchoelDDSP()
        XCTAssertGreaterThan(ddsp.pitchDriftCents, 0, "default drift should give life")
        XCTAssertLessThan(ddsp.pitchDriftCents, 10, "default drift must stay imperceptible as detune")
    }

    func testDriftDisabled_isBitIdenticalAcrossRenders() {
        // pitchDriftCents 0 → no PRNG use for pitch → perfectly steady, reproducible.
        let a = EchoelDDSP(); a.pitchDriftCents = 0
        let b = EchoelDDSP(); b.pitchDriftCents = 0
        let ra = renderTail(a), rb = renderTail(b)
        XCTAssertEqual(ra, rb, "disabled drift must be deterministic and identical")
    }

    func testDriftEnabled_sameSeedIsDeterministic() {
        // Two voices with the SAME PRNG seed must drift identically — no nondeterminism
        // / undefined behaviour on the audio thread.
        let a = EchoelDDSP(); a.pitchDriftCents = 5
        let b = EchoelDDSP(); b.pitchDriftCents = 5
        XCTAssertEqual(renderTail(a), renderTail(b), "same seed → same drift")
    }

    func testDriftEnabled_changesOutputButStaysFiniteAndSubtle() {
        let dry = renderTail({ let d = EchoelDDSP(); d.pitchDriftCents = 0; return d }())
        let wet = renderTail({ let d = EchoelDDSP(); d.pitchDriftCents = 6; return d }())

        // The effect is audible (output differs from the perfectly-steady tone)…
        XCTAssertNotEqual(dry, wet, "drift must actually modulate pitch")

        // …but every sample stays finite and bounded (no NaN/Inf, no runaway).
        for s in wet {
            XCTAssertTrue(s.isFinite, "drift output must stay finite")
            XCTAssertLessThanOrEqual(abs(s), 1.5, "drift must not blow up the level")
        }

        // …and it is a PITCH effect, not a LEVEL effect: overall energy is ~unchanged.
        func rms(_ x: [Float]) -> Float {
            var acc: Float = 0; for v in x { acc += v * v }
            return (acc / Float(max(1, x.count))).squareRoot()
        }
        let rd = rms(dry), rw = rms(wet)
        XCTAssertGreaterThan(rd, 0, "steady tone should have signal")
        XCTAssertEqual(rw, rd, accuracy: rd * 0.25 + 1e-6, "drift must stay subtle (energy ~unchanged)")
    }

    func testPartialShimmer_defaultIsSubtleNonZero() {
        // A frozen RELATIVE spectrum reads as "organ/cheap synth" — every voice
        // ships with a little per-partial life, well under audible tremolo.
        let ddsp = EchoelDDSP()
        XCTAssertGreaterThan(ddsp.partialShimmer, 0, "default shimmer should give the sustain life")
        XCTAssertLessThanOrEqual(ddsp.partialShimmer, 0.2, "default shimmer must stay felt, not heard")
    }

    func testPartialShimmer_changesOutputButStaysFiniteAndSubtle() {
        // Isolate the shimmer: pitch/level drift off on both sides.
        func makeVoice(_ shimmer: Float) -> EchoelDDSP {
            let d = EchoelDDSP()
            d.pitchDriftCents = 0
            d.levelDriftAmount = 0
            d.partialShimmer = shimmer
            return d
        }
        let dry = renderTail(makeVoice(0))
        let wet = renderTail(makeVoice(0.5))

        XCTAssertNotEqual(dry, wet, "shimmer must actually move the partials")

        for s in wet {
            XCTAssertTrue(s.isFinite, "shimmer output must stay finite")
            XCTAssertLessThanOrEqual(abs(s), 1.5, "shimmer must not blow up the level")
        }

        // A SPECTRAL life effect, not a level effect: overall energy ~unchanged.
        func rms(_ x: [Float]) -> Float {
            var acc: Float = 0; for v in x { acc += v * v }
            return (acc / Float(max(1, x.count))).squareRoot()
        }
        let rd = rms(dry), rw = rms(wet)
        XCTAssertGreaterThan(rd, 0, "steady tone should have signal")
        XCTAssertEqual(rw, rd, accuracy: rd * 0.30 + 1e-6, "shimmer must stay subtle (energy ~unchanged)")
    }

    func testPartialShimmer_zeroIsBitIdenticalAcrossVoices() {
        func makeVoice() -> EchoelDDSP {
            let d = EchoelDDSP()
            d.pitchDriftCents = 0
            d.levelDriftAmount = 0
            d.partialShimmer = 0
            return d
        }
        // Two identically-configured voices with shimmer OFF render the same
        // samples — the disabled path must stay deterministic (bit-identical).
        XCTAssertEqual(renderTail(makeVoice()), renderTail(makeVoice()),
                       "shimmer 0 must be a true no-op path")
    }

    /// The onset chiff (attack noise transient) must scale with percussiveness:
    /// a pluck fires an immediate transient; a slow-attack pad/drone must start
    /// essentially silent (envelope still ramping AND no percussive chiff), so
    /// no digital "pff" pokes out of a sound that physically has no attack.
    func testOnsetChiff_slowAttackStartsSilent_pluckDoesNot() {
        func onset(_ attack: Float) -> Float {
            let d = EchoelDDSP()
            d.pitchDriftCents = 0; d.levelDriftAmount = 0; d.partialShimmer = 0
            d.frequency = 220.0
            d.harmonicity = 1.0        // pure tonal → the only onset noise is the chiff
            d.noiseLevel = 0.0
            d.attack = attack
            d.noteOn()
            var buf = [Float](repeating: 0, count: 256)  // ~5 ms @ 48 k
            d.render(buffer: &buf, frameCount: 256, stereo: false)
            var acc: Float = 0; for v in buf { acc += v * v }
            return (acc / Float(buf.count)).squareRoot()
        }
        let pluck = onset(0.004)   // percussive → chiff + fast envelope ⇒ immediate onset
        let pad   = onset(0.5)     // slow swell → no chiff + tiny envelope ⇒ near-silent
        XCTAssertGreaterThan(pluck, 0, "a pluck must have an audible onset transient")
        XCTAssertLessThan(pad, pluck * 0.5,
                          "a slow-attack pad must start far quieter than a pluck onset")
        for v in [pluck, pad] { XCTAssertTrue(v.isFinite, "onset energy must stay finite") }
    }

    // MARK: - Slide expression (touch gesture -> vibrato/ensemble) + portamento

    func testSlideExpression_zeroIsBitIdentical_nonZeroChangesOutput() {
        func makeVoice(_ express: Float) -> EchoelDDSP {
            let d = EchoelDDSP()
            d.pitchDriftCents = 0; d.levelDriftAmount = 0; d.partialShimmer = 0
            d.expressVibrato = express
            d.expressChorus = express
            return d
        }
        // OFF must remain a true no-op path (bit-identical across voices)...
        XCTAssertEqual(renderTail(makeVoice(0)), renderTail(makeVoice(0)),
                       "expression 0 must be a true no-op path")
        // ...and ON must audibly modulate, while staying finite and bounded.
        let dry = renderTail(makeVoice(0))
        let wet = renderTail(makeVoice(0.8))
        XCTAssertNotEqual(dry, wet, "expression must change the rendered samples")
        for v in wet {
            XCTAssertTrue(v.isFinite)
            XCTAssertLessThan(abs(v), 2.0, "expression stays a subtle pitch wobble, never a blow-up")
        }
    }

    func testSlideNote_movesTheHeldNoteWithoutRetrigger() {
        let p = EchoelPolyDDSP(maxVoices: 4)
        p.noteOn(note: 60)
        XCTAssertEqual(p.activeVoiceCount, 1)
        p.slideNote(from: 60, to: 62)
        // The voice now belongs to the NEW pitch: releasing the old one is a
        // no-op, releasing the new one frees the voice.
        p.noteOff(note: 60)
        XCTAssertEqual(p.activeVoiceCount, 1, "the slid voice must not release via its old pitch")
        p.noteOff(note: 62)
        XCTAssertEqual(p.activeVoiceCount, 0, "the slid voice releases via its new pitch")
    }

    func testSlideNote_ontoAGoneNote_fallsBackToNoteOn() {
        let p = EchoelPolyDDSP(maxVoices: 4)
        p.slideNote(from: 60, to: 64)   // nothing holds 60 -> plain noteOn(64)
        XCTAssertEqual(p.activeVoiceCount, 1)
        p.noteOff(note: 64)
        XCTAssertEqual(p.activeVoiceCount, 0)
    }

    func testPortamento_mapsTimeToClampedCoefficient() {
        let p = EchoelPolyDDSP(maxVoices: 2)
        XCTAssertEqual(p.portamentoCoeff, 0.01, "default = the legacy ~2 ms micro-glide")
        p.setPortamento(seconds: 0)                 // off -> legacy
        XCTAssertEqual(p.portamentoCoeff, 0.01)
        p.setPortamento(seconds: 0.2)               // musical glide -> slower coefficient
        XCTAssertLessThan(p.portamentoCoeff, 0.01)
        XCTAssertGreaterThan(p.portamentoCoeff, 0)
        p.setPortamento(seconds: .nan)              // garbage -> safe legacy value
        XCTAssertEqual(p.portamentoCoeff, 0.01)
    }
}

#endif
