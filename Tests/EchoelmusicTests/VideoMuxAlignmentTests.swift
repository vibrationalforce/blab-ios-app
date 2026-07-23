// VideoMuxAlignmentTests.swift
// Pins the #96 A/V-desync fix: VideoMuxer must END-align the video and audio tracks
// (both recordings stop at the same wall-clock instant) by taking the LAST min(v,a)
// seconds of each — NOT the first (which played the video's HEAD over the audio's TAIL
// whenever the video was longer than the audio ring, i.e. any recording > ~30 s).
// Pure Double math, Foundation-free, runs on every gate incl. Linux SwiftPM.

import XCTest
@testable import Echoelmusic

final class VideoMuxAlignmentTests: XCTestCase {

    private typealias A = VideoMuxAlignment

    func testEqualDurations_bothStartAtZero() {
        let a = A.endAligned(videoDuration: 30, audioDuration: 30)
        XCTAssertEqual(a, A(videoStartSeconds: 0, audioStartSeconds: 0, durationSeconds: 30))
    }

    func testLongVideoShortAudio_trimsVideoHead_theBugCase() {
        // 60 s video, 30 s audio ring. The old code laid both at 0 → video HEAD [0,30]
        // over audio TAIL. Correct: take the video's LAST 30 s so it lines up with the
        // audio's last 30 s (both are the real final 30 s of the session).
        let a = A.endAligned(videoDuration: 60, audioDuration: 30)
        XCTAssertEqual(a, A(videoStartSeconds: 30, audioStartSeconds: 0, durationSeconds: 30))
    }

    func testLongAudioShortVideo_trimsAudioHead() {
        // The symmetric case (audio ring longer than the video): trim the audio's head.
        let a = A.endAligned(videoDuration: 20, audioDuration: 30)
        XCTAssertEqual(a, A(videoStartSeconds: 0, audioStartSeconds: 10, durationSeconds: 20))
    }

    func testZeroOrNegativeDuration_returnsNil() {
        XCTAssertNil(A.endAligned(videoDuration: 0, audioDuration: 30))
        XCTAssertNil(A.endAligned(videoDuration: 30, audioDuration: 0))
        XCTAssertNil(A.endAligned(videoDuration: -5, audioDuration: 30))
    }

    func testNonFiniteDuration_returnsNil() {
        XCTAssertNil(A.endAligned(videoDuration: .nan, audioDuration: 30))
        XCTAssertNil(A.endAligned(videoDuration: 30, audioDuration: .infinity))
    }

    func testStartsAreNeverNegative_andDurationIsTheShorter() {
        // Property: both starts ≥ 0, duration == min(v,a), and each start + duration
        // equals that track's full length (end-aligned to stop time).
        for (v, a) in [(45.0, 12.0), (12.0, 45.0), (33.3, 33.3), (100.0, 1.0)] {
            guard let al = A.endAligned(videoDuration: v, audioDuration: a) else {
                return XCTFail("expected an alignment for \(v),\(a)")
            }
            XCTAssertGreaterThanOrEqual(al.videoStartSeconds, 0)
            XCTAssertGreaterThanOrEqual(al.audioStartSeconds, 0)
            XCTAssertEqual(al.durationSeconds, Swift.min(v, a), accuracy: 1e-9)
            XCTAssertEqual(al.videoStartSeconds + al.durationSeconds, v, accuracy: 1e-9)
            XCTAssertEqual(al.audioStartSeconds + al.durationSeconds, a, accuracy: 1e-9)
        }
    }
}
