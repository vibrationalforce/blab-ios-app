// EchoelRecorderTests.swift
// Echoelmusic — MultiTrackRecorder state machine.

#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

@MainActor
final class MultiTrackRecorderTests: XCTestCase {

    func testInitialStateIsIdle() {
        let r = MultiTrackRecorder()
        XCTAssertFalse(r.isRecording)
        XCTAssertTrue(r.trackURLs.isEmpty)
        XCTAssertNil(r.lastError)
        XCTAssertEqual(r.recordingSeconds, 0)
    }

    func testStartWithoutEngineSetsEngineNotReady() {
        let r = MultiTrackRecorder()
        r.startRecording()
        XCTAssertFalse(r.isRecording)
        if case .engineNotReady = r.lastError {} else {
            XCTFail("expected .engineNotReady, got \(String(describing: r.lastError))")
        }
    }

    func testStopWhenIdleReturnsEmptyAndStaysIdle() async {
        let r = MultiTrackRecorder()
        let urls = await r.stopRecording()
        XCTAssertTrue(urls.isEmpty)
        XCTAssertFalse(r.isRecording)
    }
}
#endif
