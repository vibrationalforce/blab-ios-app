// HealthKitBioPublisherTests.swift
// Pins the #98c2 receipt-time fix: a HealthKit frame must be stamped with the
// RECEIPT clock (CFAbsoluteTimeGetCurrent), not the measurement time, so a resting
// Watch reading — whose measurement timestamp is minutes old — is still accepted by
// EngineBus's usableBio() 90 s window instead of being silently discarded.

#if canImport(HealthKit)
import XCTest
@testable import Echoelmusic

@MainActor
final class HealthKitBioPublisherTests: XCTestCase {

    /// Drive publishIfFresh, then let the bus's `Task { @MainActor }` hop land.
    private func awaitLatestBio(_ bus: EngineBus, tries: Int = 40) async -> BioSampleFrame? {
        for _ in 0..<tries {
            if let f = bus.latestBio { return f }
            await Task.yield()
        }
        return bus.latestBio
    }

    func testHealthKitFrame_stampsReceiptTime_staleMeasurementStaysUsable() async {
        let engine = EchoelBioEngine.shared
        let savedSource = engine.dataSource
        let savedSnap = engine.snapshot
        defer { engine.dataSource = savedSource; engine.snapshot = savedSnap }

        // A resting-Watch snapshot whose MEASUREMENT time is 3 minutes old — far past
        // even the 90 s HealthKit window if we (wrongly) stamped measurement time.
        var snap = BioSnapshot()
        snap.heartRate = 63
        snap.timestamp = Date(timeIntervalSinceNow: -180)
        engine.dataSource = .healthKit
        engine.snapshot = snap

        let bus = EngineBus()
        let publisher = HealthKitBioPublisher(engine: engine)
        publisher.publishIfFresh(to: bus)

        guard let f = await awaitLatestBio(bus) else {
            return XCTFail("a receipt-stamped HealthKit frame must reach the bus")
        }
        XCTAssertEqual(f.source, .healthKit)
        XCTAssertEqual(f.heartRateBPM, 63, accuracy: 0.5)

        // The whole point of the fix: usableBio() accepts it despite the 180 s-old
        // measurement, because the frame's timestamp is receipt-now (age ≈ 0 < 90 s).
        XCTAssertNotNil(bus.usableBio(),
                        "receipt-time stamp keeps a stale-measurement Watch reading usable")
        let receiptAge = CFAbsoluteTimeGetCurrent() - f.timestamp
        XCTAssertLessThan(receiptAge, 5,
                          "frame carries receipt time (~now), not the 180 s-old measurement time")
    }

    func testNonHealthKitSource_doesNotPublish() async {
        let engine = EchoelBioEngine.shared
        let savedSource = engine.dataSource
        let savedSnap = engine.snapshot
        defer { engine.dataSource = savedSource; engine.snapshot = savedSnap }

        // Source guard (engine.dataSource == .healthKit): a camera-sourced engine must
        // NOT have its snapshot republished by the HealthKit bridge.
        engine.dataSource = .camera
        engine.snapshot = BioSnapshot()

        let bus = EngineBus()
        HealthKitBioPublisher(engine: engine).publishIfFresh(to: bus)

        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(bus.latestBio, "non-HealthKit source must not publish onto the bus")
    }
}
#endif
