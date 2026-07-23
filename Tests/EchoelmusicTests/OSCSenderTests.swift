#if canImport(Network)
import XCTest
@testable import Echoelmusic

final class OSCSenderTests: XCTestCase {

    // MARK: - encode(address:floats:)

    // OSC reference vector (Berkeley OSC 1.0, §4.2):
    //   "/foo" + 1 float (1.0)
    //   Address "/foo\0\0\0\0" → 8 bytes
    //   TypeTag ",f\0\0"        → 4 bytes
    //   Float 1.0 big-endian    → 0x3F 0x80 0x00 0x00
    func testEncode_oneFloat_matchesOSCSpec() {
        let data = OSCSender.encode(address: "/foo", floats: [1.0])
        let expected: [UInt8] = [
            0x2F, 0x66, 0x6F, 0x6F, 0x00, 0x00, 0x00, 0x00,
            0x2C, 0x66, 0x00, 0x00,
            0x3F, 0x80, 0x00, 0x00
        ]
        XCTAssertEqual(Array(data), expected)
    }

    // Address that is already 4-byte aligned must still get a NULL
    // terminator plus one full pad of NULLs (OSC 1.0 spec).
    //   "/abcd" → 5 bytes literal, needs +3 padding → 8 bytes total
    func testEncode_addressPadding_alwaysIncludesTerminator() {
        let data = OSCSender.encode(address: "/abcd", floats: [])
        let expected: [UInt8] = [
            0x2F, 0x61, 0x62, 0x63, 0x64, 0x00, 0x00, 0x00,
            0x2C, 0x00, 0x00, 0x00
        ]
        XCTAssertEqual(Array(data), expected)
    }

    func testEncode_multipleFloats_typeTagGrowsAccordingly() {
        let data = OSCSender.encode(address: "/m", floats: [0.0, 0.5, 1.0])
        // Address "/m\0\0" 4 bytes
        // TypeTag ",fff\0\0\0\0" 8 bytes (",fff" + null + 3 pad)
        // Floats: 0x00000000, 0x3F000000, 0x3F800000
        let expected: [UInt8] = [
            0x2F, 0x6D, 0x00, 0x00,
            0x2C, 0x66, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x3F, 0x00, 0x00, 0x00,
            0x3F, 0x80, 0x00, 0x00
        ]
        XCTAssertEqual(Array(data), expected)
    }

    func testEncode_zeroFloats_typeTagIsBareComma() {
        let data = OSCSender.encode(address: "/x", floats: [])
        // Address "/x\0\0" + TypeTag ",\0\0\0"
        let expected: [UInt8] = [
            0x2F, 0x78, 0x00, 0x00,
            0x2C, 0x00, 0x00, 0x00
        ]
        XCTAssertEqual(Array(data), expected)
    }

    // MARK: - address(for:) — discrete bio-event mapping

    func testAddress_eachKind_mapsToExpectedPath() {
        XCTAssertEqual(OSCSender.address(for: .heartbeat),         "/echoelmusic/bio/event/heartbeat")
        XCTAssertEqual(OSCSender.address(for: .breathInhaleOnset), "/echoelmusic/bio/event/breath/inhale")
        XCTAssertEqual(OSCSender.address(for: .breathExhaleOnset), "/echoelmusic/bio/event/breath/exhale")
        XCTAssertEqual(OSCSender.address(for: .motionPeak),        "/echoelmusic/bio/event/motion")
        XCTAssertEqual(OSCSender.address(for: .coherenceShift),    "/echoelmusic/bio/event/coherence")
        XCTAssertEqual(OSCSender.address(for: .eegBurst),          "/echoelmusic/bio/event/eeg")
    }

    func testAddress_allKinds_areUniqueAndUnderEventNamespace() {
        let kinds: [BioEvent.Kind] = [
            .heartbeat, .breathInhaleOnset, .breathExhaleOnset,
            .motionPeak, .coherenceShift, .eegBurst
        ]
        let addresses = kinds.map { OSCSender.address(for: $0) }
        XCTAssertEqual(Set(addresses).count, kinds.count, "addresses must be unique per kind")
        for a in addresses {
            XCTAssertTrue(a.hasPrefix("/echoelmusic/bio/event/"), "\(a) must live under the event namespace")
        }
    }

    // A heartbeat event encodes to address + [confidence, aux] as two floats.
    func testEncode_heartbeatEvent_addressPlusTwoFloats() {
        let data = OSCSender.encode(
            address: OSCSender.address(for: .heartbeat),
            floats: [1.0, 0.0]
        )
        // ",ff" type tag → two big-endian floats follow the padded address.
        XCTAssertEqual(Array(data.suffix(8)), [0x3F, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    // MARK: - bioMessages(for:) — per-metric HRV gating

    private func frame(rmssd: Float = 0, sdnn: Float = 0, pnn50: Float = 0) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: 0, heartRateBPM: 72, hrvNormalized: 0.5,
            breathRate: 12, breathPhase: 0.5, coherence: 0.5, motionEnergy: 0,
            source: .healthKit, hrvRMSSDms: rmssd, hrvSDNNms: sdnn, hrvPNN50: pnn50)
    }

    private func addresses(_ f: BioSampleFrame) -> [String] {
        OSCSender.bioMessages(for: f).map(\.address)
    }

    func testBioMessages_healthKitSDNNOnly_stillEmitsSDNN() {
        // HealthKit has native SDNN but NO beat-to-beat RR → RMSSD/pNN50 absent.
        // The SDNN must still be sent (the bug: it used to hide behind the RMSSD gate).
        let addrs = addresses(frame(rmssd: 0, sdnn: 45, pnn50: 0))
        XCTAssertTrue(addrs.contains("/echoelmusic/bio/heart/sdnn"), "native SDNN must emit")
        XCTAssertFalse(addrs.contains("/echoelmusic/bio/heart/rmssd"), "no RR → no RMSSD")
        XCTAssertFalse(addrs.contains("/echoelmusic/bio/heart/pnn50"), "no RR → no pNN50")
    }

    func testBioMessages_realRRSource_emitsAllThree() {
        // Camera/Polar provide RR → RMSSD + pNN50 + SDNN all present.
        let addrs = addresses(frame(rmssd: 50, sdnn: 60, pnn50: 0.3))
        XCTAssertTrue(addrs.contains("/echoelmusic/bio/heart/rmssd"))
        XCTAssertTrue(addrs.contains("/echoelmusic/bio/heart/pnn50"))
        XCTAssertTrue(addrs.contains("/echoelmusic/bio/heart/sdnn"))
    }

    func testBioMessages_noHRV_emitsNoUnnormalizedMetrics() {
        let addrs = addresses(frame(rmssd: 0, sdnn: 0, pnn50: 0))
        for a in ["/echoelmusic/bio/heart/rmssd", "/echoelmusic/bio/heart/sdnn", "/echoelmusic/bio/heart/pnn50"] {
            XCTAssertFalse(addrs.contains(a), "\(a) must not be sent with no source value")
        }
        // The always-on core frame is still fully present.
        XCTAssertTrue(addrs.contains("/echoelmusic/bio/heart/bpm"))
        XCTAssertTrue(addrs.contains("/echoelmusic/bio/heart/hrv"))
        XCTAssertTrue(addrs.contains("/echoelmusic/bio/coherence"))
    }

    func testBioMessages_sdnnValueIsCarriedThrough() {
        let msgs = OSCSender.bioMessages(for: frame(sdnn: 47.5))
        let sdnn = msgs.first { $0.address == "/echoelmusic/bio/heart/sdnn" }
        XCTAssertEqual(sdnn?.floats.first, 47.5)
    }

    // Compliance lock (App Store 5.1.3): a HealthKit-sourced frame — the only native
    // SDNN source — must be dropped BEFORE any network send, so its SDNN never leaves
    // the device even though `bioMessages` would build a /sdnn message for it. This is
    // the invariant `sendIfFresh` enforces upstream; pin it so the SDNN-egress fix can
    // never be misread as "HealthKit now streams over OSC".
    func testEgressPolicy_healthKitBlocked_bleAndCameraAllowed() {
        XCTAssertFalse(BioEgressPolicy.allowsEgress(.healthKit), "HealthKit data must not egress (5.1.3)")
        XCTAssertFalse(BioEgressPolicy.allowsEgress(.watch), "Watch (HealthKit-store) must not egress")
        XCTAssertFalse(BioEgressPolicy.allowsEgress(.oura), "Oura (HealthKit-store) must not egress")
        XCTAssertTrue(BioEgressPolicy.allowsEgress(.ble), "the BLE strap is a direct sensor — egress OK")
        XCTAssertTrue(BioEgressPolicy.allowsEgress(.cameraPPG), "camera rPPG is on-device sensing — egress OK")
    }

    // MARK: - Lifecycle

    @MainActor
    func testInit_defaultEndpoint() {
        let sender = OSCSender()
        XCTAssertEqual(sender.host, "localhost")
        XCTAssertEqual(sender.port, 8000)
        XCTAssertFalse(sender.isActive)
    }

    @MainActor
    func testInit_customEndpoint() {
        let sender = OSCSender(host: "192.168.1.42", port: 9001)
        XCTAssertEqual(sender.host, "192.168.1.42")
        XCTAssertEqual(sender.port, 9001)
    }
}
#endif
