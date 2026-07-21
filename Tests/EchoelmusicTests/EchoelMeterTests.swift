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
        // A FRESH meter's inter-sample interpolation history starts at zero, so the
        // very first call sees a genuine 0→1 step edge — the Catmull-Rom estimator
        // correctly reports the inter-sample overshoot that edge produces (real
        // true-peak-meter behavior, not a bug). Process the DC buffer twice so the
        // history is warmed to true steady state before asserting the "flat DC"
        // reading — matches how a continuous audio stream (no cold-start edge)
        // actually measures.
        m.process(buf, frameCount: buf.count)
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

    func testPointerOverloadMatchesArrayPath() {
        var left = [Float](repeating: 0, count: 1024)
        var right = [Float](repeating: 0, count: 1024)
        for i in 0..<left.count {
            left[i] = 0.4 * sinf(Float(i) * 0.2)
            right[i] = 0.6 * sinf(Float(i) * 0.27 + 0.5)
        }
        let mArray = EchoelMeter()
        mArray.processStereo(left: left, right: right, frameCount: left.count)
        let mPtr = EchoelMeter()
        left.withUnsafeBufferPointer { lp in
            right.withUnsafeBufferPointer { rp in
                guard let lb = lp.baseAddress, let rb = rp.baseAddress else { return XCTFail("no base") }
                mPtr.processStereo(left: lb, right: rb, frameCount: left.count)
            }
        }
        XCTAssertEqual(mPtr.peakDb, mArray.peakDb, accuracy: 0.01)
        XCTAssertEqual(mPtr.truePeakDb, mArray.truePeakDb, accuracy: 0.01)
        XCTAssertEqual(mPtr.rmsDb, mArray.rmsDb, accuracy: 0.01)
    }

    func testPointerOverloadMonoUsesLeftForBoth() {
        var buf = [Float](repeating: 0, count: 512)
        for i in 0..<buf.count { buf[i] = 0.5 * sinf(Float(i) * 0.3) }
        let m = EchoelMeter()
        buf.withUnsafeBufferPointer { bp in
            guard let b = bp.baseAddress else { return XCTFail("no base") }
            m.processStereo(left: b, right: nil, frameCount: buf.count)
        }
        XCTAssertGreaterThan(m.peakDb, EchoelMeter.floorDb)
        XCTAssertGreaterThanOrEqual(m.truePeakDb, m.peakDb - 0.01)
    }

    func testResetReturnsToFloor() {
        let m = EchoelMeter()
        m.process([Float](repeating: 1.0, count: 256), frameCount: 256)
        m.reset()
        XCTAssertEqual(m.peakDb, EchoelMeter.floorDb, accuracy: 0.01)
        XCTAssertEqual(m.truePeakDb, EchoelMeter.floorDb, accuracy: 0.01)
        XCTAssertEqual(m.truePeakMaxDb, EchoelMeter.floorDb, accuracy: 0.01)
    }

    func testTruePeakMaxHold_doesNotDecay() {
        let m = EchoelMeter()
        m.holdDecay = 0.5 // make the regular held value decay quickly
        m.process([Float](repeating: 1.0, count: 1024), frameCount: 1024) // full scale
        let maxAfterLoud = m.truePeakMaxDb
        XCTAssertGreaterThan(maxAfterLoud, -1.0) // ~0 dBFS
        for _ in 0..<20 { m.process([Float](repeating: 0, count: 512), frameCount: 512) }
        // Max-hold is unchanged; the regular true-peak has decayed well below it.
        XCTAssertEqual(m.truePeakMaxDb, maxAfterLoud, accuracy: 0.01)
        XCTAssertLessThan(m.truePeakDb, m.truePeakMaxDb - 6.0)
    }
}
