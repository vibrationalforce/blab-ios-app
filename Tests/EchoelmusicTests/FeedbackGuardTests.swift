// FeedbackGuardTests.swift
// Echoel — pure feedback-suppression heuristics for the live vocoder path.

import XCTest
@testable import Echoelmusic

final class FeedbackGuardTests: XCTestCase {

    // MARK: gain duck

    func testNoDuck_whenQuietOrStable() {
        XCTAssertEqual(FeedbackGuard.gainReductionDB(rmsHistory: [0.1, 0.1, 0.1]), 0, accuracy: 1e-6)
        // loud but not rising
        XCTAssertEqual(FeedbackGuard.gainReductionDB(rmsHistory: [0.95, 0.95, 0.95]), 0, accuracy: 1e-6)
    }

    func testDuck_whenRisingAboveCeiling() {
        let r = FeedbackGuard.gainReductionDB(rmsHistory: [0.5, 0.8, 0.99])
        XCTAssertGreaterThan(r, 0)
        XCTAssertLessThanOrEqual(r, 12)
    }

    func testDuck_ignoresShortHistory() {
        XCTAssertEqual(FeedbackGuard.gainReductionDB(rmsHistory: [0.99, 0.99]), 0, accuracy: 1e-6)
    }

    // MARK: ringing bin

    func testRingingBin_findsDominantPeak() {
        var mags = [Float](repeating: 0.1, count: 64)
        mags[20] = 5.0   // a strong ringing tone
        XCTAssertEqual(FeedbackGuard.ringingBin(magnitudes: mags), 20)
    }

    func testRingingBin_nilWhenFlat() {
        let mags = [Float](repeating: 0.5, count: 64)
        XCTAssertNil(FeedbackGuard.ringingBin(magnitudes: mags))
    }

    func testRingingBin_ignoresDC() {
        var mags = [Float](repeating: 0.1, count: 32)
        mags[0] = 100  // huge DC must be ignored
        mags[10] = 3.0
        XCTAssertEqual(FeedbackGuard.ringingBin(magnitudes: mags), 10)
    }

    // MARK: bin→Hz

    func testBinToHz() {
        // bin 10, 1024-pt FFT at 48 kHz → 10 * 48000 / 1024
        XCTAssertEqual(FeedbackGuard.binToHz(10, fftSize: 1024, sampleRate: 48000),
                       10.0 * 48000.0 / 1024.0, accuracy: 1e-6)
        XCTAssertEqual(FeedbackGuard.binToHz(5, fftSize: 0, sampleRate: 48000), 0, accuracy: 1e-9)
    }
}
