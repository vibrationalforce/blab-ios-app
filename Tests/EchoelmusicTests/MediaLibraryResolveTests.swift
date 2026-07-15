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
        XCTAssertEqual(MediaLibrary.resolveRef(deadRef), url,
                       "a dead absolute ref re-roots to the surviving file (full URL)")
    }

    func testResolveRef_bareName_resolvesAgainstDocumentsVideos() throws {
        // Convention 3 (VisualRecorder captures persist a BARE name): the old
        // dedicated `!ref.contains("/")` branch was subsumed by the re-root
        // path — pin that the convention still resolves.
        let fm = FileManager.default
        let docs = try XCTUnwrap(fm.urls(for: .documentDirectory, in: .userDomainMask).first)
        let dir = docs.appendingPathComponent("Videos", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "echoel_\(UUID().uuidString).mp4"
        let url = dir.appendingPathComponent(name, isDirectory: false)
        try Data([0x00, 0x00, 0x00, 0x18]).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(MediaLibrary.resolveRef(name), url)
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
