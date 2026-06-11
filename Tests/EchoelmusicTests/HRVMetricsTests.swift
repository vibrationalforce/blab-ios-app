// HRVMetricsTests.swift
// Echoelmusic — shared time-domain HRV math (ms-based).

import XCTest
@testable import Echoelmusic

final class HRVMetricsTests: XCTestCase {

    // RR (ms): 1000, 500, 1500 → successive diffs 500, 1000.

    func testRMSSD_knownVector() {
        // sqrt((500^2 + 1000^2)/2) = sqrt(625000) ≈ 790.5694
        XCTAssertEqual(HRVMetrics.rmssd(rrMs: [1000, 500, 1500]), 790.569415, accuracy: 1e-4)
    }

    func testSDNN_knownVector() {
        // mean 1000; deviations 0,−500,+500 → sqrt((0+250000+250000)/2) = 500
        XCTAssertEqual(HRVMetrics.sdnn(rrMs: [1000, 500, 1500]), 500.0, accuracy: 1e-6)
    }

    func testPNN50_allDifferencesOver50() {
        // both diffs (500, 1000) exceed 50 ms → 100 %
        XCTAssertEqual(HRVMetrics.pnn50(rrMs: [1000, 500, 1500]), 100.0, accuracy: 1e-6)
    }

    func testPNN50_mixed() {
        // diffs 60 (>50) and 10 (≤50) → 1/2 = 50 %
        XCTAssertEqual(HRVMetrics.pnn50(rrMs: [800, 860, 870]), 50.0, accuracy: 1e-6)
    }

    func testPNN50_noneOver50() {
        XCTAssertEqual(HRVMetrics.pnn50(rrMs: [800, 820, 840]), 0.0, accuracy: 1e-6)
    }

    func testConstantIntervals_rmssdAndSdnnZero() {
        let rr = [850.0, 850.0, 850.0, 850.0]
        XCTAssertEqual(HRVMetrics.rmssd(rrMs: rr), 0, accuracy: 1e-9)
        XCTAssertEqual(HRVMetrics.sdnn(rrMs: rr), 0, accuracy: 1e-9)
        XCTAssertEqual(HRVMetrics.pnn50(rrMs: rr), 0, accuracy: 1e-9)
    }

    func testInsufficientData_returnsZero() {
        XCTAssertEqual(HRVMetrics.rmssd(rrMs: []), 0, accuracy: 1e-9)
        XCTAssertEqual(HRVMetrics.sdnn(rrMs: [800]), 0, accuracy: 1e-9)
        XCTAssertEqual(HRVMetrics.pnn50(rrMs: [800]), 0, accuracy: 1e-9)
    }

    // Polar adapter (seconds → ms) must agree with the ms kernel.
    #if canImport(CoreBluetooth)
    func testPolarSecondsAdapterMatchesMsKernel() {
        XCTAssertEqual(PolarH10BioPublisher.rmssdMs(fromRRSeconds: [1.0, 0.5, 1.5]),
                       HRVMetrics.rmssd(rrMs: [1000, 500, 1500]), accuracy: 1e-6)
    }
    #endif
}
