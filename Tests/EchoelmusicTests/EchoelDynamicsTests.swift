// EchoelDynamicsTests.swift
// Echoelmusic — dynamics (compressor + brick-wall limiter).

import XCTest
@testable import Echoelmusic

final class EchoelDynamicsTests: XCTestCase {

    private let sr: Float = 48000

    // MARK: - Limiter

    func testLimiterNeverExceedsCeiling() {
        let lim = EchoelLimiter(sampleRate: sr)
        lim.ceilingDb = -6 // ~0.5012 linear
        let ceiling = powf(10.0, -6.0 / 20.0)
        var maxOut: Float = 0
        for i in 0..<4000 {
            let x = 4.0 * sinf(Float(i) * 0.1) // way over the ceiling
            let (l, r) = lim.processStereo(x, x)
            maxOut = Swift.max(maxOut, Swift.max(abs(l), abs(r)))
        }
        XCTAssertLessThanOrEqual(maxOut, ceiling * 1.001)
    }

    func testLimiterTransparentBelowCeiling() {
        let lim = EchoelLimiter(sampleRate: sr)
        lim.ceilingDb = -0.3 // ~0.966 linear
        for i in 0..<2000 {
            let x = 0.1 * sinf(Float(i) * 0.1) // well below ceiling
            let (l, _) = lim.processStereo(x, x)
            XCTAssertEqual(l, x, accuracy: 1e-5)
        }
    }

    // MARK: - Compressor

    func testCompressorTransparentBelowThreshold() {
        let comp = EchoelCompressor(sampleRate: sr)
        comp.thresholdDb = -18; comp.ratio = 4; comp.makeupDb = 0
        for i in 0..<2000 {
            let x = 0.01 * sinf(Float(i) * 0.1) // -40 dBFS, below knee
            let (l, _) = comp.processStereo(x, x)
            XCTAssertEqual(l, x, accuracy: 1e-6)
        }
    }

    func testCompressorReducesLevelAboveThreshold() {
        let comp = EchoelCompressor(sampleRate: sr)
        comp.thresholdDb = -24; comp.ratio = 4; comp.makeupDb = 0
        comp.attackMs = 5; comp.releaseMs = 120

        var inSum: Float = 0, outSum: Float = 0
        let total = 8000
        for i in 0..<total {
            let x = 1.0 * sinf(Float(i) * 0.1) // 0 dBFS peaks
            let (l, _) = comp.processStereo(x, x)
            if i >= total - 2000 { inSum += x * x; outSum += l * l }
        }
        let inRMS = sqrtf(inSum / 2000)
        let outRMS = sqrtf(outSum / 2000)
        XCTAssertLessThan(outRMS, inRMS * 0.6)            // clear reduction
        XCTAssertLessThan(comp.gainReductionDb, -1.0)     // actively compressing
    }

    func testCompressorOutputIsFinite() {
        let comp = EchoelCompressor(sampleRate: sr)
        comp.thresholdDb = -30; comp.ratio = 20; comp.makeupDb = 6
        for i in 0..<20_000 {
            let x = (i % 2 == 0 ? 1.0 : -1.0) as Float
            let (l, r) = comp.processStereo(x, x)
            XCTAssertTrue(l.isFinite && r.isFinite)
        }
    }
}
