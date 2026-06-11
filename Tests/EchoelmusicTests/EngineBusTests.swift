import XCTest
@testable import Echoelmusic

@MainActor
final class EngineBusTests: XCTestCase {

    // MARK: - Init

    func testInit_emptyState() {
        let bus = EngineBus()
        XCTAssertNil(bus.latestBio)
        XCTAssertNil(bus.latestControllerEvent)
        XCTAssertNil(bus.latestBioEvent)
        XCTAssertTrue(bus.bioFrames.isEmpty)
        XCTAssertTrue(bus.controllerEvents.isEmpty)
        XCTAssertTrue(bus.bioEvents.isEmpty)
    }

    // MARK: - Bio frame publish

    func testPublishBio_enqueuesToQueue() {
        let bus = EngineBus()
        let frame = Self.makeBioFrame()

        bus.publish(bio: frame)

        XCTAssertEqual(bus.bioFrames.count, 1)
        let dequeued = bus.bioFrames.dequeue()
        XCTAssertEqual(dequeued, frame)
    }

    func testPublishBio_updatesLatestSnapshot() async {
        let bus = EngineBus()
        let frame = Self.makeBioFrame()

        bus.publish(bio: frame)
        await Task.yield()

        XCTAssertEqual(bus.latestBio, frame)
    }

    // MARK: - Controller event publish

    func testPublishController_enqueuesToQueue() {
        let bus = EngineBus()
        let event = ControllerEvent(
            timestamp: 1.0,
            kind: .noteOn,
            channel: 2,
            note: 60,
            value: 0.8,
            auxCC: 0
        )

        bus.publish(controller: event)

        XCTAssertEqual(bus.controllerEvents.count, 1)
        XCTAssertEqual(bus.controllerEvents.dequeue(), event)
    }

    func testPublishController_updatesLatestSnapshot() async {
        let bus = EngineBus()
        let event = ControllerEvent(
            timestamp: 2.0,
            kind: .airCC,
            channel: 1,
            note: 0,
            value: 0.5,
            auxCC: 21
        )

        bus.publish(controller: event)
        await Task.yield()

        XCTAssertEqual(bus.latestControllerEvent, event)
    }

    // MARK: - Bio event publish

    func testPublishBioEvent_enqueuesToQueue() {
        let bus = EngineBus()
        let event = BioEvent(
            timestamp: 3.0,
            kind: .heartbeat,
            confidence: 0.95,
            aux: 850.0
        )

        bus.publish(bioEvent: event)

        XCTAssertEqual(bus.bioEvents.count, 1)
        XCTAssertEqual(bus.bioEvents.dequeue(), event)
    }

    func testPublishBioEvent_updatesLatestSnapshot() async {
        let bus = EngineBus()
        let event = BioEvent(
            timestamp: 4.0,
            kind: .breathInhaleOnset,
            confidence: 0.7,
            aux: 0
        )

        bus.publish(bioEvent: event)
        await Task.yield()

        XCTAssertEqual(bus.latestBioEvent, event)
    }

    // MARK: - Capacity / overflow

    func testPublishBio_pastCapacity_dropsOldest() {
        let bus = EngineBus(bioCapacity: 4)
        for i in 0..<10 {
            bus.publish(bio: Self.makeBioFrame(timestamp: TimeInterval(i)))
        }

        // SPSCQueue rounds capacity to next power of 2; 4 stays 4.
        // Overflow drops oldest, so the queue retains the latest items.
        XCTAssertLessThanOrEqual(bus.bioFrames.count, 4)
        XCTAssertGreaterThan(bus.bioFrames.droppedCount, 0)
    }

    // MARK: - Topics are independent

    func testPublish_topicsAreIndependent() {
        let bus = EngineBus()

        bus.publish(bio: Self.makeBioFrame())
        bus.publish(controller: ControllerEvent(
            timestamp: 0, kind: .noteOff, channel: 2, note: 60, value: 0, auxCC: 0
        ))

        XCTAssertEqual(bus.bioFrames.count, 1)
        XCTAssertEqual(bus.controllerEvents.count, 1)
        XCTAssertEqual(bus.bioEvents.count, 0)
    }

    // MARK: - hrvRMSSDms field

    func testBioFrame_hrvRMSSDms_defaultsToZero() {
        let f = Self.makeBioFrame()
        XCTAssertEqual(f.hrvRMSSDms, 0, accuracy: 1e-9)
    }

    func testBioFrame_hrvRMSSDms_roundTrips() {
        let f = BioSampleFrame(
            timestamp: 0, heartRateBPM: 60, hrvNormalized: 0.42, breathRate: 6,
            breathPhase: 0, coherence: 0.5, motionEnergy: 0, source: .ble,
            hrvRMSSDms: 42.7
        )
        XCTAssertEqual(f.hrvRMSSDms, 42.7, accuracy: 1e-4)
    }

    // MARK: - Helpers

    private static func makeBioFrame(timestamp: TimeInterval = 0) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: timestamp,
            heartRateBPM: 72,
            hrvNormalized: 0.5,
            breathRate: 12,
            breathPhase: 0.25,
            coherence: 0.6,
            motionEnergy: 0.1,
            source: .oura
        )
    }
}
