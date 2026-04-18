#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

@MainActor
final class RetroCaptureTests: XCTestCase {

    var capture: RetroCapture!

    override func setUp() async throws {
        capture = RetroCapture()
    }

    // MARK: - Initial state

    func testInitialState_notRecording() {
        XCTAssertFalse(capture.isRecording)
    }

    func testInitialState_zeroSeconds() {
        XCTAssertEqual(capture.recordingSeconds, 0)
    }

    func testInitialState_noLastURL() {
        XCTAssertNil(capture.lastURL)
    }

    func testInitialState_waveformSamples_200() {
        XCTAssertEqual(capture.waveformSamples.count, 200)
    }

    func testInitialState_waveformSamples_allZero() {
        XCTAssertTrue(capture.waveformSamples.allSatisfy { $0 == 0 })
    }

    // MARK: - snapshotPreRoll

    func testSnapshotPreRoll_defaultLength() {
        // With no data written, should return 30s worth of silence
        let snap = capture.snapshotPreRoll(seconds: 30)
        // 30s × 48000 × 2ch = 2,880,000 floats
        XCTAssertEqual(snap.count, 30 * 48000 * 2)
    }

    func testSnapshotPreRoll_shorterDuration() {
        let snap = capture.snapshotPreRoll(seconds: 5)
        XCTAssertEqual(snap.count, 5 * 48000 * 2)
    }

    func testSnapshotPreRoll_silenceBeforeAnyAudio() {
        let snap = capture.snapshotPreRoll(seconds: 1)
        XCTAssertTrue(snap.allSatisfy { $0 == 0 })
    }

    // MARK: - stopRecording idempotency

    func testStopRecording_whenNotRecording_noOp() {
        // Should not crash
        capture.stopRecording()
        XCTAssertFalse(capture.isRecording)
    }

    func testStopRecording_completionNotCalledWhenNotRecording() {
        var called = false
        capture.stopRecording { _ in called = true }
        XCTAssertFalse(called)
    }
}
#endif
