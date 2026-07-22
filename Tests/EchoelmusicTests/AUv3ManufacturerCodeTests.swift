// AUv3ManufacturerCodeTests.swift
// Guards the FourCC packing that AUv3 third-party discovery now depends on: the
// "is this Apple's / Echoel's own unit?" classification matches on the stable
// componentManufacturer OSType, not the drifting manufacturerName display string.
// A packing/transcription error here would silently break discovery (our own unit
// mis-counted, retry ladder + guidance mis-firing), so pin the codes exactly.

#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

final class AUv3ManufacturerCodeTests: XCTestCase {

    func testFourCC_packsCharsBigEndian() {
        // 'a'=0x61 'p'=0x70 'p'=0x70 'l'=0x6C  → Apple's manufacturer OSType.
        XCTAssertEqual(AUv3Host.fourCC("appl"), 0x6170_706C)
        // 'E'=0x45 'c'=0x63 'h'=0x68 'o'=0x6F  → Echoel's own bundled AUv3.
        XCTAssertEqual(AUv3Host.fourCC("Echo"), 0x4563_686F)
        // Sanity vs a known component TYPE code (matches AUParameterMapping.fourCC's
        // inverse), so the packing order is the one CoreAudio actually uses.
        XCTAssertEqual(AUv3Host.fourCC("aufx"), 0x6175_6678)
        // Our own AUv3 declares type 'aumu' (music device / instrument) as of B1 —
        // pin it, and note it equals kAudioUnitType_MusicDevice (0x61756D75), the
        // type the host categorizer files under `.instrument`.
        XCTAssertEqual(AUv3Host.fourCC("aumu"), 0x6175_6D75)
    }
}
#endif
