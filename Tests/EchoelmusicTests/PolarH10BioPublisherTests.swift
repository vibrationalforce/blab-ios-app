#if canImport(CoreBluetooth)
import XCTest
@testable import Echoelmusic

final class PolarH10BioPublisherTests: XCTestCase {

    // MARK: - parseHRMeasurement

    // Canonical BLE spec test vector: HR = 65 bpm (uint8), no RR.
    //   flags = 0x00 (uint8 HR, no energy, no RR)
    //   hr    = 0x41 (65)
    // MARK: - rmssdMs (true HRV in milliseconds)

    func testRMSSD_fewerThanTwoIntervals_returnsZero() {
        XCTAssertEqual(PolarH10BioPublisher.rmssdMs(fromRRSeconds: []), 0, accuracy: 1e-9)
        XCTAssertEqual(PolarH10BioPublisher.rmssdMs(fromRRSeconds: [0.85]), 0, accuracy: 1e-9)
    }

    func testRMSSD_knownVector() {
        // RR (s): 1.0, 0.5, 1.5 → successive diffs (ms): -500, +1000.
        // RMSSD = sqrt((500^2 + 1000^2) / 2) = sqrt(625000) ≈ 790.5694 ms.
        let v = PolarH10BioPublisher.rmssdMs(fromRRSeconds: [1.0, 0.5, 1.5])
        XCTAssertEqual(v, 790.569415, accuracy: 1e-4)
    }

    func testRMSSD_constantIntervals_isZero() {
        XCTAssertEqual(PolarH10BioPublisher.rmssdMs(fromRRSeconds: [0.8, 0.8, 0.8, 0.8]), 0, accuracy: 1e-9)
    }

    func testParse_uint8HR_noRR() {
        let data = Data([0x00, 0x41])
        let parsed = PolarH10BioPublisher.parseHRMeasurement(data)
        XCTAssertEqual(parsed.hr, 65)
        XCTAssertEqual(parsed.rrIntervals, [])
    }

    // HR = 300 bpm via uint16 (impossible physiologically; tests the
    // wide-format branch).
    //   flags = 0x01 (uint16 HR)
    //   hr    = 0x2C 0x01 → 300, little-endian
    func testParse_uint16HR_noRR() {
        let data = Data([0x01, 0x2C, 0x01])
        let parsed = PolarH10BioPublisher.parseHRMeasurement(data)
        XCTAssertEqual(parsed.hr, 300)
        XCTAssertEqual(parsed.rrIntervals, [])
    }

    // HR = 72 + one RR-interval of 1.0 s (1024 in 1/1024s units).
    //   flags = 0x10 (RR present)
    //   hr    = 0x48 (72)
    //   rr    = 0x00 0x04 → 1024 → 1.0 s
    func testParse_uint8HR_singleRR() {
        let data = Data([0x10, 0x48, 0x00, 0x04])
        let parsed = PolarH10BioPublisher.parseHRMeasurement(data)
        XCTAssertEqual(parsed.hr, 72)
        XCTAssertEqual(parsed.rrIntervals.count, 1)
        XCTAssertEqual(parsed.rrIntervals[0], 1.0, accuracy: 1e-6)
    }

    // HR = 60 + three RR-intervals: 1.0 s, 0.5 s, 1.5 s.
    //   1.0 s → 1024 → 0x00 0x04
    //   0.5 s →  512 → 0x00 0x02
    //   1.5 s → 1536 → 0x00 0x06
    func testParse_uint8HR_multipleRR() {
        let data = Data([
            0x10, 0x3C,
            0x00, 0x04,
            0x00, 0x02,
            0x00, 0x06
        ])
        let parsed = PolarH10BioPublisher.parseHRMeasurement(data)
        XCTAssertEqual(parsed.hr, 60)
        XCTAssertEqual(parsed.rrIntervals.count, 3)
        XCTAssertEqual(parsed.rrIntervals[0], 1.0, accuracy: 1e-6)
        XCTAssertEqual(parsed.rrIntervals[1], 0.5, accuracy: 1e-6)
        XCTAssertEqual(parsed.rrIntervals[2], 1.5, accuracy: 1e-6)
    }

    // HR with energy-expended field (skipped) then one RR.
    //   flags  = 0x18 (energy + RR)
    //   hr     = 0x46 (70)
    //   energy = 0x10 0x00 (16 kJ — skipped)
    //   rr     = 0x00 0x04 (1.0 s)
    func testParse_skipsEnergyExpended() {
        let data = Data([0x18, 0x46, 0x10, 0x00, 0x00, 0x04])
        let parsed = PolarH10BioPublisher.parseHRMeasurement(data)
        XCTAssertEqual(parsed.hr, 70)
        XCTAssertEqual(parsed.rrIntervals.count, 1)
        XCTAssertEqual(parsed.rrIntervals[0], 1.0, accuracy: 1e-6)
    }

    func testParse_empty_returnsZero() {
        let parsed = PolarH10BioPublisher.parseHRMeasurement(Data())
        XCTAssertEqual(parsed.hr, 0)
        XCTAssertEqual(parsed.rrIntervals, [])
    }

    func testParse_truncatedUint16_returnsZero() {
        // flags says uint16 but only 1 byte of HR follows
        let data = Data([0x01, 0x48])
        let parsed = PolarH10BioPublisher.parseHRMeasurement(data)
        XCTAssertEqual(parsed.hr, 0)
        XCTAssertEqual(parsed.rrIntervals, [])
    }

    // MARK: - Lifecycle

    @MainActor
    func testInit_idleState() {
        let pub = PolarH10BioPublisher()
        XCTAssertEqual(pub.state, .idle)
        XCTAssertFalse(pub.isPublishing)
    }
}
#endif
