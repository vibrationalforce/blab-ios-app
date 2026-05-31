import XCTest
@testable import Echoelmusic

final class BioFeedbackManagerTests: XCTestCase {

    private func suite() -> String { "BioFeedbackTests.\(UUID().uuidString)" }

    func testPublishThenRefresh_roundTripsAndUpdatesAtomicFields() {
        let s = suite(); defer { UserDefaults().removePersistentDomain(forName: s) }
        let mgr = BioFeedbackManager(appGroup: s)
        XCTAssertTrue(mgr.isAvailable)
        mgr.publish(BioVitals(heartRateBPM: 128, hrvNormalized: 0.7,
                              breathPhase: 0.25, coherence: 0.8, timestamp: 42))
        let got = mgr.refreshFromSharedStore()
        XCTAssertEqual(got?.heartRateBPM, 128)
        XCTAssertEqual(mgr.heartRate, 128, accuracy: 1e-6)
        XCTAssertEqual(mgr.hrv, 0.7, accuracy: 1e-6)
        XCTAssertEqual(mgr.breathPhase, 0.25, accuracy: 1e-6)
        XCTAssertEqual(mgr.coherence, 0.8, accuracy: 1e-6)
    }

    // The cross-process contract: a second instance on the same container
    // reads what the first published (app → AUv3 extension).
    func testCrossInstance_sharesViaContainer() {
        let s = suite(); defer { UserDefaults().removePersistentDomain(forName: s) }
        let producer = BioFeedbackManager(appGroup: s)
        let consumer = BioFeedbackManager(appGroup: s)
        producer.publish(BioVitals(heartRateBPM: 99, coherence: 0.33))
        XCTAssertEqual(consumer.refreshFromSharedStore()?.heartRateBPM, 99)
        XCTAssertEqual(consumer.coherence, 0.33, accuracy: 1e-6)
    }

    func testRefresh_emptyStore_returnsNilAndKeepsDefaults() {
        let s = suite(); defer { UserDefaults().removePersistentDomain(forName: s) }
        let mgr = BioFeedbackManager(appGroup: s)
        XCTAssertNil(mgr.refreshFromSharedStore())
        XCTAssertEqual(mgr.heartRate, 60, accuracy: 1e-6)
        XCTAssertEqual(mgr.coherence, 0.5, accuracy: 1e-6)
    }

    func testVitals_codableRoundTrip() throws {
        let v = BioVitals(heartRateBPM: 72, hrvNormalized: 0.6,
                          breathPhase: 0.5, coherence: 0.9, timestamp: 1)
        let data = try JSONEncoder().encode(v)
        XCTAssertEqual(try JSONDecoder().decode(BioVitals.self, from: data), v)
    }
}
