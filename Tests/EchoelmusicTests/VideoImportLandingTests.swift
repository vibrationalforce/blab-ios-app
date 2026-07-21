// VideoImportLandingTests.swift
// DAW#4 slice a — "Videospuren importieren aus der Mediathek". The video-import
// path lands a picked file onto a video lane through the SAME pure seams as audio
// (free clip slot + append tick + factory region). Plus a real copy test for the
// one impure step (MediaLibrary), which runs on Linux CI via the Application
// Support fallback.

import XCTest
@testable import Echoelmusic

final class VideoImportLandingTests: XCTestCase {

    // MARK: - VideoClipFactory landing geometry (mirrors the audio path)

    func testVideoLanding_placesRegionAtAppendTick_withClipID() {
        let lane = UUID(); let clipID = UUID()
        let existing = TimelineDocument(regions: [
            TimelineRegion(laneID: lane, clipID: UUID(), startTick: 0, lengthTicks: 1920),
        ])
        let startTick = existing.nextStartTick(inLane: lane)
        let region = VideoClipFactory.region(forDurationSeconds: 3.0, bpm: 120,
                                             laneID: lane, clipID: clipID,
                                             startTick: startTick)
        XCTAssertEqual(region.startTick, 1920, "lands after the lane's existing region")
        XCTAssertEqual(region.clipID, clipID)
        XCTAssertEqual(region.laneID, lane)
        XCTAssertGreaterThan(region.lengthTicks, 0, "an imported video is never zero-length")
    }

    func testVideoClip_isVideoKind_withMediaRef() {
        let clip = VideoClipFactory.clip(name: "take", mediaRef: "/abs/path/take.mov", colorIndex: 2)
        XCTAssertEqual(clip.kind, .video)
        XCTAssertEqual(clip.mediaRef, "/abs/path/take.mov")
        XCTAssertEqual(clip.name, "take")
    }

    // MARK: - MediaLibrary copy (the one impure step) — real file I/O

    func testImportAudioAndVideo_copyIntoDistinctDirs_preservingExtension() throws {
        // A temp "picked" source file.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("echoel-import-src-\(UUID().uuidString).wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: tmp)   // "RIFF"
        defer { try? FileManager.default.removeItem(at: tmp) }

        let audioDest = try MediaLibrary.importAudio(from: tmp)
        defer { try? FileManager.default.removeItem(at: audioDest) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioDest.path), "audio copy lands on disk")
        XCTAssertEqual(audioDest.pathExtension, "wav", "extension is preserved")
        XCTAssertTrue(audioDest.path.contains("Media/Audio"), "audio goes under Media/Audio")
        // O11 gave imports a READABLE name (the source's own base name), not a UUID —
        // so a first-time import with nothing yet taken in Media/Audio naturally reuses
        // `tmp`'s own name; that is correct, not a collision. "Fresh unique name (no
        // collision)" is proven by re-importing the SAME source: the dest directory now
        // has that name taken, so the second copy must disambiguate (numeric suffix).
        let audioDest2 = try MediaLibrary.importAudio(from: tmp)
        defer { try? FileManager.default.removeItem(at: audioDest2) }
        XCTAssertNotEqual(audioDest2.lastPathComponent, audioDest.lastPathComponent,
                          "re-importing the same source gets a fresh unique name (no collision)")

        let videoSrc = FileManager.default.temporaryDirectory
            .appendingPathComponent("echoel-import-src-\(UUID().uuidString).mov")
        try Data([0x00, 0x00, 0x00, 0x18]).write(to: videoSrc)
        defer { try? FileManager.default.removeItem(at: videoSrc) }

        let videoDest = try MediaLibrary.importVideo(from: videoSrc)
        defer { try? FileManager.default.removeItem(at: videoDest) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: videoDest.path), "video copy lands on disk")
        XCTAssertEqual(videoDest.pathExtension, "mov")
        XCTAssertTrue(videoDest.path.contains("Media/Video"), "video goes under Media/Video (distinct dir)")
    }

    /// A missing source throws (copyFailed) rather than returning a bogus URL — the
    /// view's landing sets landingError and leaves the stores untouched on this throw.
    func testImport_missingSource_throwsCopyFailed() {
        let ghost = FileManager.default.temporaryDirectory
            .appendingPathComponent("echoel-does-not-exist-\(UUID().uuidString).mov")
        XCTAssertThrowsError(try MediaLibrary.importVideo(from: ghost)) { error in
            XCTAssertEqual(error as? MediaLibrary.MediaImportError, .copyFailed)
        }
    }
}
