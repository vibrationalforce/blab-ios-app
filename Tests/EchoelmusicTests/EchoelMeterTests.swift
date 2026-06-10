// EchoelMeterTests.swift
// Echoelmusic — peak / RMS / true-peak meter.

import XCTest
@testable import Echoelmusic

final class EchoelMeterTests: XCTestCase {

    func testSilenceReadsFloor() {
        let m = EchoelMeter()
        let buf = [Float](repeating: 0, count: 512)
        m.process(buf, frameCount: buf.count)
        XCTAssertEqual(m.peakDb, EchoelMeter.floorDb, accuracy: 0.01)
        XCTAssertEqual(m.rmsDb, EchoelMeter.floorDb, accuracy: 0.01)
        XCTAssertEqual(m.truePeakDb, EchoelMeter.floorDb, accuracy: 0.01)
    }

    func testFullScaleDCIsZeroDb() {
        let m = EchoelMeter()
        let buf = [Float](repeating: 1.0, count: 2000)
        m.process(buf, frameCount: buf.count)
        XCTAssertEqual(m.peakDb, 0, accuracy: 0.1)
        XCTAssertEqual(m.rmsDb, 0, accuracy: 0.1)
        XCTAssertEqual(m.truePeakDb, 0, accuracy: 0.2)
    }

    func testTruePeakCatchesInterSampleOver() {
        // Sine straddling its crest: samples peak at 0.707 (−3 dBFS) but the
        // true inter-sample peak rises toward full scale.
        let m = EchoelMeter()
        var buf = [Float](repeating: 0, count: 2000)
        for n in 0..<buf.count {
            buf[n] = sinf(Float.pi * 0.5 * Float(n) + Float.pi * 0.25)
        }
        m.process(buf, frameCount: buf.count)
        XCTAssertEqual(m.peakDb, -3.0, accuracy: 0.3)          // sample peak ~0.707
        XCTAssertGreaterThan(m.truePeakDb, m.peakDb + 1.0)     // true-peak clearly higher
        XCTAssertGreaterThan(m.truePeakDb, -1.5)               // approaches full scale
        XCTAssertLessThanOrEqual(m.truePeakDb, 1.0)            // but not absurd
    }

    func testTruePeakNeverBelowSamplePeak() {
        let m = EchoelMeter()
        var buf = [Float](repeating: 0, count: 1500)
        for i in 0..<buf.count {
            buf[i] = 0.5 * sinf(Float(i) * 0.3) + 0.2 * sinf(Float(i) * 1.1)
        }
        m.process(buf, frameCount: buf.count)
        XCTAssertGreaterThanOrEqual(m.truePeakDb, m.peakDb - 0.01)
    }

    func testStereoLinksLouderChannel() {
        let m = EchoelMeter()
        let left = [Float](repeating: 0.25, count: 1000)   // −12 dB
        let right = [Float](repeating: 0.5, count: 1000)   // −6 dB
        m.processStereo(left: left, right: right, frameCount: 1000)
        XCTAssertEqual(m.peakDb, -6.0, accuracy: 0.2)      // louder side drives peak
    }

    func testResetReturnsToFloor() {
        let m = EchoelMeter()
        m.process([Float](repeating: 1.0, count: 256), frameCount: 256)
        m.reset()
        XCTAssertEqual(m.peakDb, EchoelMeter.floorDb, accuracy: 0.01)
        XCTAssertEqual(m.truePeakDb, EchoelMeter.floorDb, accuracy: 0.01)
    }
}
