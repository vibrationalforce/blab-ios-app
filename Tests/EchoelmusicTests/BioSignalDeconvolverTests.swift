import XCTest
@testable import Echoelmusic

final class BioSignalDeconvolverTests: XCTestCase {

    // MARK: - Warmup → validity = .recovering

    func testProcess_duringWarmup_validityIsRecovering() {
        var dec = BioSignalDeconvolver(preset: .ppg, sampleRate: 130)
        let out = dec.process(0.0)
        XCTAssertEqual(out.validity, .recovering)
    }

    func testProcess_afterWarmup_validityIsValid() {
        var dec = BioSignalDeconvolver(preset: .ppg, sampleRate: 130)
        // PPG warmup = max(130, 4/0.5) = 130 samples. Feed 131.
        var last = CleanedSample(value: 0, validity: .recovering)
        for _ in 0..<131 {
            last = dec.process(0.0)
        }
        XCTAssertEqual(last.validity, .valid)
    }

    // MARK: - Saturation → validity = .corrupt

    func testProcess_saturatedInput_validityIsCorrupt() {
        var dec = BioSignalDeconvolver(preset: .ppg, sampleRate: 130)
        // Push past warmup.
        for _ in 0..<131 { _ = dec.process(0.0) }
        // Saturation default is 0.95 absolute.
        let out = dec.process(1.5)
        XCTAssertEqual(out.validity, .corrupt)
    }

    func testProcess_nanInput_validityIsCorrupt() {
        var dec = BioSignalDeconvolver(preset: .ppg, sampleRate: 130)
        for _ in 0..<131 { _ = dec.process(0.0) }
        let out = dec.process(.nan)
        XCTAssertEqual(out.validity, .corrupt)
    }

    // MARK: - Detrend strips DC

    func testProcess_constantInput_outputTrendsToZero() {
        var dec = BioSignalDeconvolver(preset: .ppg, sampleRate: 130)
        // Feed a DC offset of 0.5 for several seconds; HP at 0.5 Hz
        // should bring the output close to zero after settling.
        var last: Float = .nan
        for _ in 0..<(130 * 5) {
            last = dec.process(0.5).value
        }
        XCTAssertEqual(last, 0, accuracy: 0.01)
    }

    // MARK: - Notch attenuates mains

    func testProcess_mainsFrequencySine_isAttenuated() {
        let sr: Double = 1000
        let mains: Double = 50
        var dec = BioSignalDeconvolver(preset: .ecg, sampleRate: sr, mainsFrequency: mains)

        // Bypass warmup so the validity flag reflects steady state.
        for _ in 0..<Int(sr) { _ = dec.process(0.0) }

        var inPower: Float = 0
        var outPower: Float = 0
        for n in 0..<Int(sr) {
            let x = Float(sin(2 * .pi * mains * Double(n) / sr))
            inPower += x * x
            // One process() call per sample — the prior double call advanced the
            // stateful notch filter twice per loop iteration and squared two
            // different consecutive outputs instead of one measurement.
            let y = dec.process(x).value
            outPower += y * y
        }
        // Notch should drop power by at least 20 dB. Use a generous
        // 10x ratio threshold so the test survives Q tuning.
        XCTAssertLessThan(outPower * 10, inPower)
    }

    // MARK: - BiquadStage design

    func testHighpass_dcResponseIsZero() {
        var hp = BiquadStage.highpass(cutoff: 1.0, sampleRate: 1000, q: 0.707)
        // Feed DC, after enough samples output approaches zero.
        var last: Float = 0
        for _ in 0..<5000 {
            last = hp.process(1.0)
        }
        XCTAssertEqual(last, 0, accuracy: 0.01)
    }

    func testReset_clearsBiquadState() {
        var hp = BiquadStage.highpass(cutoff: 1.0, sampleRate: 1000, q: 0.707)
        _ = hp.process(0.5)
        XCTAssertNotEqual(hp.z1, 0)
        hp.reset()
        XCTAssertEqual(hp.z1, 0)
        XCTAssertEqual(hp.z2, 0)
    }

    // MARK: - Preset cutoffs

    func testDetrendCutoff_perPreset() {
        XCTAssertEqual(BioSignalDeconvolver.detrendCutoff(for: .ppg), 0.5)
        XCTAssertEqual(BioSignalDeconvolver.detrendCutoff(for: .ecg), 0.5)
        XCTAssertEqual(BioSignalDeconvolver.detrendCutoff(for: .eeg), 1.0)
        XCTAssertEqual(BioSignalDeconvolver.detrendCutoff(for: .accelerometer), 0.1)
    }
}
