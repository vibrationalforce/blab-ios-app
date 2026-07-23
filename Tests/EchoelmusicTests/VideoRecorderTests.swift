// VideoRecorderTests.swift
// Echoel — P3 Video capture sink. Covers the pure, device-free surface of
// VideoRecorder: the H.264 writer settings, the bitrate heuristic + clamp, and
// the output-URL shape. Live AVAssetWriter append/finish is exercised on device.

#if canImport(AVFoundation)
import XCTest
import AVFoundation
@testable import Echoelmusic

final class VideoRecorderTests: XCTestCase {

    typealias R = VideoRecorder

    // MARK: - Video settings

    func testVideoSettings_carriesCodecAndDimensions() {
        let s = R.videoSettings(width: 1920, height: 1080, bitRate: 8_000_000)
        XCTAssertEqual(s[AVVideoCodecKey] as? AVVideoCodecType, .h264)
        XCTAssertEqual(s[AVVideoWidthKey] as? Int, 1920)
        XCTAssertEqual(s[AVVideoHeightKey] as? Int, 1080)
    }

    func testVideoSettings_carriesBitrateInCompressionProperties() {
        let s = R.videoSettings(width: 1280, height: 720, bitRate: 6_000_000)
        let props = s[AVVideoCompressionPropertiesKey] as? [String: Any]
        XCTAssertEqual(props?[AVVideoAverageBitRateKey] as? Int, 6_000_000)
        XCTAssertNotNil(props?[AVVideoProfileLevelKey])
    }

    func testVideoSettings_declaresNominalFrameRateForNLEIngest() {
        // The declared source rate must match the REAL producer: the Metal visual's
        // draw loop (MetalBioView baseline 60 fps), which is what VisualRecorder feeds
        // to VideoRecorder — NOT the 15 Hz rPPG camera. It anchors the encoder's
        // rate-control and stamps the fps an NLE (DaVinci Resolve) reads on ingest.
        let s = R.videoSettings(width: 1920, height: 1080, bitRate: 8_000_000)
        let props = s[AVVideoCompressionPropertiesKey] as? [String: Any]
        XCTAssertEqual(props?[AVVideoExpectedSourceFrameRateKey] as? Int, 60)
        XCTAssertEqual(props?[AVVideoMaxKeyFrameIntervalKey] as? Int, 60)
    }

    // MARK: - Bitrate heuristic

    func testRecommendedBitRate_clampsFloorForTinyFrames() {
        // 320x240 * 4 = 307_200 → below the 2 Mbps floor.
        XCTAssertEqual(R.recommendedBitRate(width: 320, height: 240), 2_000_000)
    }

    func testRecommendedBitRate_clampsCeilingForHugeFrames() {
        // 4K (3840x2160) * 4 ≈ 33 M → clamped to the 20 Mbps ceiling.
        XCTAssertEqual(R.recommendedBitRate(width: 3840, height: 2160), 20_000_000)
    }

    func testRecommendedBitRate_scalesInBand() {
        // 1080p (1920x1080=2_073_600) * 4 = 8_294_400 → inside 2–20 M band, untouched.
        XCTAssertEqual(R.recommendedBitRate(width: 1920, height: 1080), 8_294_400)
    }

    func testRecommendedBitRate_zeroDimensions_clampToFloor() {
        XCTAssertEqual(R.recommendedBitRate(width: 0, height: 0), 2_000_000)
    }

    // MARK: - Output URL

    func testMakeOutputURL_isMp4UnderVideos() throws {
        let url = try R.makeOutputURL()
        XCTAssertEqual(url.pathExtension, "mp4")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Videos")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("echoel_"))
    }

    // MARK: - State

    @MainActor
    func testInitialStateIsIdle() {
        let rec = VideoRecorder()
        XCTAssertEqual(rec.recordState, .idle)
        XCTAssertEqual(rec.recordedSeconds(), 0)
    }

    @MainActor
    func testStartRecording_movesToRecording() {
        let rec = VideoRecorder()
        rec.startRecording()
        XCTAssertEqual(rec.recordState, .recording)
        XCTAssertTrue(rec.recordState.isRecording)
    }

    @MainActor
    func testStopWithoutFrames_returnsNilAndResets() async {
        let rec = VideoRecorder()
        rec.startRecording()
        let url = await rec.stopRecording()
        XCTAssertNil(url)                       // armed but no frame ever arrived
        XCTAssertEqual(rec.recordState, .idle)
    }

    @MainActor
    func testStopWhenIdle_isNoOp() async {
        let rec = VideoRecorder()
        let url = await rec.stopRecording()
        XCTAssertNil(url)
        XCTAssertEqual(rec.recordState, .idle)
    }

    @MainActor
    func testStartWhileRecording_isRejected() {
        // The re-arm guard must still reject an ALREADY-active capture (double-tap
        // safety): a second start while `.recording` must not tear down writer state.
        let rec = VideoRecorder()
        rec.startRecording()
        XCTAssertEqual(rec.recordState, .recording)
        rec.startRecording()                       // second call — must be a no-op
        XCTAssertEqual(rec.recordState, .recording)
    }

    @MainActor
    func testReArmAfterTerminalState_returnsToRecording() async {
        // Regression for "kann ich das danach nicht mehr machen": after a capture
        // ends (here via the no-frame path → `.idle`, but the guard now also accepts
        // `.done`/`.error`), a fresh start must re-arm to `.recording`. The old guard
        // required exactly `.idle`, silently dropping the second capture after `.done`.
        let rec = VideoRecorder()
        rec.startRecording()
        _ = await rec.stopRecording()              // terminal state reached
        rec.startRecording()                       // must re-arm
        XCTAssertEqual(rec.recordState, .recording)
    }
}
#endif
