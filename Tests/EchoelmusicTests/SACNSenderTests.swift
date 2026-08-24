#if canImport(Network)
import XCTest
@testable import Echoelmusic

final class SACNSenderTests: XCTestCase {

    private let cid: [UInt8] = Array(0..<16)

    func testPacket_totalLengthIsFullUniverse() {
        let p = SACNSender.e131Packet(universe: 1, sequence: 0, cid: cid, channels: [1, 2, 3], synthetic: nil)
        // 126-byte header + 512 slots = 638.
        XCTAssertEqual(p.count, 638)
    }

    func testPacket_rootLayerIdentifiers() {
        let p = [UInt8](SACNSender.e131Packet(universe: 1, sequence: 0, cid: cid, channels: [], synthetic: nil))
        // Preamble size 0x0010, postamble 0x0000.
        XCTAssertEqual(Array(p[0..<4]), [0x00, 0x10, 0x00, 0x00])
        // ACN Packet Identifier "ASC-E1.17\0\0\0".
        XCTAssertEqual(Array(p[4..<16]), [0x41, 0x53, 0x43, 0x2D, 0x45, 0x31, 0x2E, 0x31, 0x37, 0x00, 0x00, 0x00])
        // Root vector = VECTOR_ROOT_E131_DATA (4).
        XCTAssertEqual(Array(p[18..<22]), [0x00, 0x00, 0x00, 0x04])
        // CID echoed.
        XCTAssertEqual(Array(p[22..<38]), cid)
    }

    func testPacket_framingVectorPriorityUniverseAndSequence() {
        let p = [UInt8](SACNSender.e131Packet(universe: 0x0102, sequence: 7, cid: cid, channels: [], synthetic: nil))
        // Framing vector = VECTOR_E131_DATA_PACKET (2) at offset 40.
        XCTAssertEqual(Array(p[40..<44]), [0x00, 0x00, 0x00, 0x02])
        // Priority 100 at offset 108; sequence at 111; universe BE at 113..114.
        XCTAssertEqual(p[108], 100)
        XCTAssertEqual(p[111], 7)
        XCTAssertEqual(Array(p[113..<115]), [0x01, 0x02])
    }

    func testPacket_dmpStartCodeAndPropertyCount() {
        let p = [UInt8](SACNSender.e131Packet(universe: 1, sequence: 0, cid: cid, channels: [9, 8, 7], synthetic: nil))
        // DMP vector 0x02 at 117, addr/type 0xA1 at 118.
        XCTAssertEqual(p[117], 0x02)
        XCTAssertEqual(p[118], 0xA1)
        // Property value count = 513 (0x0201) at 123..124.
        XCTAssertEqual(Array(p[123..<125]), [0x02, 0x01])
        // DMX start code 0x00 at 125, then the channels.
        XCTAssertEqual(p[125], 0x00)
        XCTAssertEqual(Array(p[126..<129]), [9, 8, 7])
    }

    func testPacket_channelsPaddedAndClampedTo512() {
        let over = [UInt8](repeating: 200, count: 600)
        let p = SACNSender.e131Packet(universe: 1, sequence: 0, cid: cid, channels: over, synthetic: nil)
        XCTAssertEqual(p.count, 638)   // still exactly one full universe
    }

    func testMulticastHost_matchesSpecGroup() {
        XCTAssertEqual(SACNSender.multicastHost(universe: 1), "239.255.0.1")
        XCTAssertEqual(SACNSender.multicastHost(universe: 258), "239.255.1.2")  // 0x0102
    }

    @MainActor
    func testInit_defaults() {
        let s = SACNSender()
        XCTAssertEqual(s.port, 5568)
        XCTAssertEqual(s.universe, 1)
        XCTAssertFalse(s.isActive)
    }
}
#endif
