// O11 — imported media keeps a readable name (was a raw UUID). Tests the pure
// name-computation `MediaLibrary.uniqueName` (the filesystem check is injected,
// so this runs headless with no App Group container).

import XCTest
@testable import Echoelmusic

final class MediaLibraryNameTests: XCTestCase {

    func testUniqueName_readableBase_preservedWithExtension() {
        let name = MediaLibrary.uniqueName(base: "MyLoop", ext: "wav", taken: { _ in false })
        XCTAssertEqual(name, "MyLoop.wav", "a free readable name is used as-is (no UUID)")
    }

    func testUniqueName_collision_disambiguatesWithNumericSuffix() {
        // "kick.wav" already exists → "kick-1.wav".
        var taken: Set<String> = ["kick.wav"]
        XCTAssertEqual(MediaLibrary.uniqueName(base: "kick", ext: "wav", taken: { taken.contains($0) }),
                       "kick-1.wav")
        // "kick.wav" AND "kick-1.wav" exist → "kick-2.wav".
        taken.insert("kick-1.wav")
        XCTAssertEqual(MediaLibrary.uniqueName(base: "kick", ext: "wav", taken: { taken.contains($0) }),
                       "kick-2.wav")
    }

    func testUniqueName_sanitizesPathAndReservedChars() {
        let name = MediaLibrary.uniqueName(base: "a/b:c*?<>|\"\\d", ext: "wav", taken: { _ in false })
        XCTAssertEqual(name, "abcd.wav", "path separators + reserved chars are stripped")
    }

    func testUniqueName_emptyOrGarbageBase_fallsBackToSample() {
        XCTAssertEqual(MediaLibrary.uniqueName(base: "", ext: "wav", taken: { _ in false }), "sample.wav")
        XCTAssertEqual(MediaLibrary.uniqueName(base: "   ", ext: "wav", taken: { _ in false }), "sample.wav")
        XCTAssertEqual(MediaLibrary.uniqueName(base: "///", ext: "m4a", taken: { _ in false }), "sample.m4a")
    }

    func testUniqueName_capsLength() {
        let long = String(repeating: "x", count: 200)
        let name = MediaLibrary.uniqueName(base: long, ext: "wav", taken: { _ in false })
        XCTAssertEqual(name, String(repeating: "x", count: 60) + ".wav", "base is capped at 60 chars")
    }
}
