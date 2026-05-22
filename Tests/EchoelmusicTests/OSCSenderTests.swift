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
