#if canImport(Network)
import XCTest
@testable import Echoelmusic

final class ArtNetSenderTests: XCTestCase {

    private func frame(
        hr: Float = 120, hrv: Float = 0.5, breathPhase: Float = 0.5, coherence: Float = 0.5
    ) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: 0, heartRateBPM: hr, hrvNormalized: hrv,
            breathRate: 6, breathPhase: breathPhase, coherence: coherence,
            motionEnergy: 0, source: .fallback
        )
    }

    // MARK: - ArtDMX packet structure

    func testArtDMXPacket_headerMatchesArtNetSpec() {
        let pkt = Array(ArtNetSender.artDMXPacket(universe: 0, sequence: 1, channels: [0, 0]))
        // "Art-Net\0"
        XCTAssertEqual(Array(pkt[0..<8]), [0x41, 0x72, 0x74, 0x2D, 0x4E, 0x65, 0x74, 0x00])
        // OpCode OpOutput 0x5000, little-endian
        XCTAssertEqual(Array(pkt[8..<10]), [0x00, 0x50])
        // ProtVer 14, big-endian
        XCTAssertEqual(Array(pkt[10..<12]), [0x00, 0x0E])
        XCTAssertEqual(pkt[12], 1)      // sequence
        XCTAssertEqual(pkt[13], 0)      // physical
    }

    func testArtDMXPacket_universeSplitsIntoSubUniAndNet() {
        // universe 0x0123 → SubUni 0x23, Net 0x01
        let pkt = Array(ArtNetSender.artDMXPacket(universe: 0x0123, sequence: 5, channels: [1, 2]))
        XCTAssertEqual(pkt[14], 0x23)   // SubUni
        XCTAssertEqual(pkt[15], 0x01)   // Net
    }

    func testArtDMXPacket_lengthIsEvenBigEndianAndDataAppended() {
        // odd channel count → padded to even
        let pkt = Array(ArtNetSender.artDMXPacket(universe: 0, sequence: 1, channels: [10, 20, 30]))
        let lenHi = Int(pkt[16]); let lenLo = Int(pkt[17])
        let length = (lenHi << 8) | lenLo
        XCTAssertEqual(length, 4, "3 channels padded to even = 4")
        XCTAssertEqual(length % 2, 0)
        XCTAssertEqual(Array(pkt[18..<22]), [10, 20, 30, 0])
        XCTAssertEqual(pkt.count, 18 + length)
    }

    func testArtDMXPacket_clampsToMax512Channels() {
        let pkt = Array(ArtNetSender.artDMXPacket(universe: 0, sequence: 1,
                                                  channels: Array(repeating: 255, count: 600)))
        let length = (Int(pkt[16]) << 8) | Int(pkt[17])
        XCTAssertEqual(length, 512)
        XCTAssertEqual(pkt.count, 18 + 512)
    }

    // MARK: - Bio → DMX mapping

    func testDmxChannels_fourChannelsInByteRange() {
        let ch = ArtNetSender.dmxChannels(for: frame())
        XCTAssertEqual(ch.count, 4)
        for c in ch { XCTAssertTrue(c <= 255) }  // UInt8 is inherently ≤255; sanity
    }

    func testDmxChannels_dimmerNeverFullyDark_andTracksCoherence() {
        let dark = ArtNetSender.dmxChannels(for: frame(coherence: 0))[0]
        let bright = ArtNetSender.dmxChannels(for: frame(coherence: 1))[0]
        XCTAssertGreaterThanOrEqual(Int(dark), Int(0.3 * 255) - 2, "always some light")
        XCTAssertGreaterThan(Int(bright), Int(dark), "more coherent = brighter")
        XCTAssertEqual(Int(bright), 255, accuracy: 2)
    }

    func testDmxChannels_breathDrivesBlue() {
        let low = ArtNetSender.dmxChannels(for: frame(breathPhase: 0))[3]
        let high = ArtNetSender.dmxChannels(for: frame(breathPhase: 1))[3]
        XCTAssertEqual(Int(low), 0, accuracy: 2)
        XCTAssertEqual(Int(high), 255, accuracy: 2)
    }

    func testDmxChannels_outOfRangeBioClampsToByte() {
        let wild = ArtNetSender.dmxChannels(for: frame(hr: 999, hrv: 5, breathPhase: -3, coherence: 9))
        XCTAssertEqual(wild.count, 4)  // all UInt8, no crash/overflow
    }

    // MARK: - Lifecycle

    @MainActor
    func testInit_defaultEndpoint() {
        let s = ArtNetSender()
        XCTAssertEqual(s.host, "255.255.255.255")
        XCTAssertEqual(s.port, 6454)
        XCTAssertEqual(s.universe, 0)
        XCTAssertFalse(s.isActive)
    }
}
#endif
