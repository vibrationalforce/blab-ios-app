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
        let savedHasHR = engine.hasHRSample
        defer { engine.dataSource = savedSource; engine.snapshot = savedSnap
                engine.hasHRSample = savedHasHR }
        engine.hasHRSample = true   // a real sample has landed

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

    func testSeedSnapshot_isNotPublishedAsAMeasurement() async {
        // `dataSource` flips to .healthKit when the QUERIES are installed, not when a
        // reading arrives. BioSnapshot seeds heartRate at a nominal 72 with a
        // construction-time timestamp, so the first poll used to broadcast that seed:
        // the bio strip showed a confident "72" and reported a live signal before the
        // Watch had said anything. (heartRate is the headline invented number, not the
        // only seeded one — breathPhase seeds at 0.5 and is published too. Dropping the
        // frame suppresses both.)
        //
        // WHAT THIS TEST DOES NOT COVER: it sets `hasHRSample` by hand, so it pins that
        // the publisher HONOURS the flag — not that the engine ever SETS it. The engine
        // side is driven by a live HealthKit query and is not deterministically testable
        // here; the structural argument is that `processHeartRateSamples` is the only
        // writer of BOTH `hasHRSample` and `snapshot.timestamp`, and the timestamp is
        // the dedup key, so no publishable frame can exist without the flag.
        let engine = EchoelBioEngine.shared
        let savedSource = engine.dataSource
        let savedSnap = engine.snapshot
        let savedHasHR = engine.hasHRSample
        defer { engine.dataSource = savedSource; engine.snapshot = savedSnap
                engine.hasHRSample = savedHasHR }

        engine.dataSource = .healthKit
        engine.snapshot = BioSnapshot()      // untouched seed: heartRate == 72
        engine.hasHRSample = false           // …and no real sample has arrived
        XCTAssertEqual(engine.snapshot.heartRate, 72, accuracy: 0.001,
                       "fixture check: the seed is the invented 72 this guards against")

        // ONE publisher across both halves — the production shape. This also pins the
        // load-bearing ordering: the `hasHRSample` guard sits BEFORE
        // `lastTimestamp = snap.timestamp`, so the suppressed seed does not poison the
        // dedup state. Move the guard below that line and the second half goes silent.
        let bus = EngineBus()
        let publisher = HealthKitBioPublisher(engine: engine)
        publisher.publishIfFresh(to: bus)

        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(bus.latestBio, "the 72 BPM seed must not reach the bus as a measurement")

        // …and the guard must LIFT the moment a real sample lands, or HealthKit is dead.
        engine.hasHRSample = true
        var real = BioSnapshot()
        real.heartRate = 58
        real.timestamp = Date()
        engine.snapshot = real
        publisher.publishIfFresh(to: bus)
        guard let f = await awaitLatestBio(bus) else {
            return XCTFail("a real HealthKit reading must publish once the seed guard lifts")
        }
        XCTAssertEqual(f.heartRateBPM, 58, accuracy: 0.5)
    }
}
#endif
