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

    // MARK: - Freshness window (Bio-Acceptance v1)

    func testFreshBio_nilWhenNoFrame() {
        XCTAssertNil(EngineBus().freshBio())
    }

    func testFreshBio_returnsRecentFrame() async {
        let bus = EngineBus()
        bus.publish(bio: Self.makeBioFrame(timestamp: CFAbsoluteTimeGetCurrent()))
        await Task.yield()
        XCTAssertNotNil(bus.freshBio(maxAge: 5), "a frame stamped now must be fresh")
    }

    func testFreshBio_expiresStaleFrame() async {
        let bus = EngineBus()
        // A frame stamped well in the past (e.g. a dropped strap's last reading).
        bus.publish(bio: Self.makeBioFrame(timestamp: CFAbsoluteTimeGetCurrent() - 100))
        await Task.yield()
        XCTAssertNil(bus.freshBio(maxAge: 5), "a stale frame must not read as live")
        // latestBio still holds it (raw snapshot), only the freshness view expires.
        XCTAssertNotNil(bus.latestBio)
    }

    // MARK: - usableBio() per-source window (drives the bio-shaping readout)

    /// The bio-shaping guide reads `usableBio()` (the SAME gate the sound engine
    /// uses), NOT the fixed-5 s `freshBio()`. A latent wrist/Watch reading stays
    /// usable for 90 s and keeps driving the music — so the guide must keep showing
    /// its amounts, where `freshBio(5 s)` would falsely blank them to "—".
    func testUsableBio_keepsLatentWatchFrame_whereFreshBioDrops() async {
        let bus = EngineBus()
        let sixtySecondsOld = CFAbsoluteTimeGetCurrent() - 60
        bus.publish(bio: BioSampleFrame(
            timestamp: sixtySecondsOld, heartRateBPM: 64, hrvNormalized: 0.5,
            breathRate: 12, breathPhase: 0.25, coherence: 0.6, motionEnergy: 0.1,
            source: .watch))                       // 90 s window
        await Task.yield()
        XCTAssertNotNil(bus.usableBio(),
            "a 60 s-old Watch reading is still usable (90 s window) — the sound uses it")
        XCTAssertNil(bus.freshBio(maxAge: 5),
            "the old fixed 5 s gate would have blanked it — the reason the guide switched")
    }

    /// usableBio() still blanks a truly frozen LIVE source: a BLE strap frame past
    /// its 6 s window is not usable, so the readout honestly goes quiet.
    func testUsableBio_expiresFrozenLiveSource() async {
        let bus = EngineBus()
        bus.publish(bio: BioSampleFrame(
            timestamp: CFAbsoluteTimeGetCurrent() - 10, heartRateBPM: 72,
            hrvNormalized: 0.5, breathRate: 12, breathPhase: 0.25, coherence: 0.6,
            motionEnergy: 0.1, source: .ble))      // 6 s window
        await Task.yield()
        XCTAssertNil(bus.usableBio(), "a 10 s-old BLE frame is past its 6 s window")
        XCTAssertNotNil(bus.latestBio, "raw snapshot still held, only the usable view expires")
    }

    // MARK: - BioSource.faceCam (A5 additive source)

    func testFaceCam_rawValueAppendedStable() {
        // Appended at the end so persisted raw values of existing sources are unmoved.
        XCTAssertEqual(BioSource.faceCam.rawValue, 6)
        XCTAssertEqual(BioSource.cameraPPG.rawValue, 5)
        XCTAssertEqual(BioSource.fallback.rawValue, 0)
    }

    func testFaceCam_isLiveSourceWindow() {
        // Live front-camera expression expires fast, like rPPG/BLE.
        XCTAssertEqual(BioSource.faceCam.freshnessWindow, 6)
    }

    func testFaceCam_carriesNoTrustedHRV() {
        // Only a BLE chest strap gives beat-to-beat RR; face tracking has no pulse.
        XCTAssertFalse(BioSource.faceCam.providesTrustedHRV)
    }

    @MainActor
    func testFaceExpressionPublisher_inertUntilSupported() {
        // No CI environment supports ARKit face tracking, so start() is a guarded
        // no-op and the publisher never claims to publish. This also proves the
        // non-ARKit stub compiles and behaves.
        let bus = EngineBus()
        let pub = FaceExpressionBioPublisher()
        XCTAssertFalse(pub.isPublishing)
        pub.start(publishing: bus)
        XCTAssertEqual(pub.isPublishing, FaceExpressionBioPublisher.isSupported,
                       "publishing only when the device supports face tracking")
        pub.stop()
        XCTAssertFalse(pub.isPublishing, "stop() is idempotent and resets state")
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
