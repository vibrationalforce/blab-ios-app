// MediaLibraryResolveTests.swift
// H6 (healing wave 2 — audit CRITICAL "silent data loss on app update"): a
// region's mediaRef persisted an ABSOLUTE path into the app-group container,
// whose UUID prefix changes on every app update/device migration — the file
// survives under the same media subdirectory, the path does not. resolveRef
// must re-root a dead absolute ref by its (import-time-UUID) file name.

import XCTest
@testable import Echoelmusic

final class MediaLibraryResolveTests: XCTestCase {

    /// Drop a real file into the library's audio home (Application Support /
    /// temp fallback in CI — same resolution the code under test uses).
    private func plantAudioFile(named name: String) throws -> URL {
        let dir = try XCTUnwrap(MediaLibrary.directory("Media/Audio"))
        let url = dir.appendingPathComponent(name, isDirectory: false)
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: url)   // 4 bytes suffice
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testResolveRef_liveAbsolutePath_resolvesDirectly() throws {
        let url = try plantAudioFile(named: "\(UUID().uuidString).wav")
        XCTAssertEqual(MediaLibrary.resolveRef(url.path), url)
    }

    func testResolveRef_deadContainerPrefix_reRootsByFileName() throws {
        // The app-update scenario: same file NAME, container prefix that no
        // longer exists. Resolution must find the real file in the new home.
        let url = try plantAudioFile(named: "\(UUID().uuidString).wav")
        let deadRef = "/private/var/mobile/Containers/Shared/AppGroup/DEAD-BEEF/"
            + "Media/Audio/\(url.lastPathComponent)"
        XCTAssertEqual(MediaLibrary.resolveRef(deadRef)?.lastPathComponent,
                       url.lastPathComponent,
                       "a dead absolute ref re-roots to the surviving file")
        XCTAssertNotNil(MediaLibrary.resolveRef(deadRef))
    }

    func testResolveRef_trulyVanishedFile_isNil() {
        let deadRef = "/private/var/mobile/Containers/Shared/AppGroup/DEAD-BEEF/"
            + "Media/Audio/\(UUID().uuidString).wav"
        XCTAssertNil(MediaLibrary.resolveRef(deadRef), "no fabricated URLs — honest nil")
    }

    func testResolveRef_emptyAndNil_areNil() {
        XCTAssertNil(MediaLibrary.resolveRef(nil))
        XCTAssertNil(MediaLibrary.resolveRef(""))
    }
}
