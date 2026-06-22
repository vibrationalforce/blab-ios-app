import XCTest
@testable import Echoelmusic

final class SpectrumAnalysisTests: XCTestCase {

    func testEmpty_isAllZero() {
        let b = SpectrumAnalysis.bands(from: [], count: 16)
        XCTAssertEqual(b.count, 16)
        XCTAssertEqual(b.max() ?? 1, 0, accuracy: 0.0001)
    }

    func testSingleNote_fundamentalIsLoudestBand() {
        // 440 Hz alone → its fundamental band is the peak (normalized to 1.0).
        let b = SpectrumAnalysis.bands(from: [(hz: 440, amplitude: 1)], count: 28, overtones: 6, undertones: 2)
        XCTAssertEqual(b.max() ?? 0, 1.0, accuracy: 0.0001)
        // The fundamental lands in the band that contains 440 Hz.
        let idx = (0..<28).max(by: { b[$0] < b[$1] })!
        let lo = SpectrumAnalysis.centerFrequency(band: idx - 1, count: 28)
        let hi = SpectrumAnalysis.centerFrequency(band: idx + 1, count: 28)
        XCTAssertTrue(440 >= lo && 440 <= hi, "peak band should bracket 440 Hz")
    }

    func testOvertones_populateHigherBands() {
        // A low note must light up higher bands too (its overtones), not just one.
        let b = SpectrumAnalysis.bands(from: [(hz: 110, amplitude: 1)], count: 28, overtones: 6, undertones: 0)
        let nonZero = b.filter { $0 > 0.001 }.count
        XCTAssertGreaterThan(nonZero, 1, "overtones should occupy multiple bands")
    }

    func testNormalization_peakIsOne() {
        let b = SpectrumAnalysis.bands(from: [(hz: 220, amplitude: 0.3)], count: 20)
        XCTAssertEqual(b.max() ?? 0, 1.0, accuracy: 0.0001, "energies normalize to the loudest band")
    }

    func testCenterFrequency_isMonotonicAndInRange() {
        let lo = SpectrumAnalysis.centerFrequency(band: 0, count: 24, fMin: 30, fMax: 16000)
        let hi = SpectrumAnalysis.centerFrequency(band: 23, count: 24, fMin: 30, fMax: 16000)
        XCTAssertGreaterThan(hi, lo)
        XCTAssertGreaterThanOrEqual(lo, 30)
        XCTAssertLessThanOrEqual(hi, 16000)
    }

    // MARK: visible-spectrum colour mapping

    func testVisibleColor_lowFreqIsReddish_highFreqIsBluish() {
        let low = SpectralColor.visibleColor(forFrequency: 40)     // → ~700 nm red
        let high = SpectralColor.visibleColor(forFrequency: 12000) // → ~400 nm violet/blue
        XCTAssertGreaterThan(low.r, low.b, "low frequency should be red-dominant")
        XCTAssertGreaterThan(high.b, high.r, "high frequency should be blue/violet-dominant")
    }

    func testVisibleColor_invalidIsNeutral() {
        XCTAssertEqual(SpectralColor.visibleColor(forFrequency: 0), SpectralColor.neutral)
    }
}
