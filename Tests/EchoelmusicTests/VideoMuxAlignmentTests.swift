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

    // MARK: - Loop-mode cut (founder 2026-07-24: video cut exactly to the loop bars)

    func testLoopAligned_cutsExactLoopLengthFromBothEnds() {
        // 20 s video + 20 s audio, want an 8 s loop (e.g. 4 bars @ 120 bpm). Each track
        // keeps its LAST 8 s → both start at 12, duration is exactly the loop length.
        let a = A.loopAligned(videoDuration: 20, audioDuration: 20, loopSeconds: 8)
        XCTAssertEqual(a, A(videoStartSeconds: 12, audioStartSeconds: 12, durationSeconds: 8))
    }

    func testLoopAligned_durationIsAlwaysExactlyLoopSeconds_notMinOfTracks() {
        // Unlike endAligned, the kept length is the LOOP, never min(v,a): a long capture
        // still yields exactly one loop.
        let a = A.loopAligned(videoDuration: 63, audioDuration: 63, loopSeconds: 16)
        XCTAssertNotNil(a)
        // `?? Double.nan`, not a bare optional: the `accuracy:` overload of XCTAssertEqual
        // takes a NON-optional FloatingPoint, so a `Double?` fails to type-check. NaN keeps
        // the assertion honest — a missing alignment compares equal to nothing.
        XCTAssertEqual(a?.durationSeconds ?? Double.nan, 16, accuracy: 1e-9)
        XCTAssertEqual(a?.videoStartSeconds ?? Double.nan, 47, accuracy: 1e-9)
    }

    func testLoopAligned_unequalDurations_eachCutFromItsOwnEnd() {
        // Video 30 s, audio 20 s, 8 s loop. Both end at stop, so the SAME wall-clock
        // window is the last 8 s of each — but from different track lengths that means
        // different offsets: video starts at 22, audio at 12. This is the whole reason
        // the struct carries two separate start fields.
        let a = A.loopAligned(videoDuration: 30, audioDuration: 20, loopSeconds: 8)
        XCTAssertEqual(a, A(videoStartSeconds: 22, audioStartSeconds: 12, durationSeconds: 8))
    }

    func testLoopAligned_secondsSinceBarStart_phaseAlignsToDownbeat() {
        // The last downbeat was 1.5 s ago → the loop window ends at that downbeat, so the
        // cut is the loopSeconds BEFORE it: start = dur − 1.5 − loopSeconds (same law as
        // StudioCalculator.loopTrimWindow, so the video matches the audio bounce phase).
        let a = A.loopAligned(videoDuration: 20, audioDuration: 20,
                              loopSeconds: 8, secondsSinceBarStart: 1.5)
        XCTAssertEqual(a, A(videoStartSeconds: 10.5, audioStartSeconds: 10.5, durationSeconds: 8))
    }

    func testLoopAligned_tooShortForOneLoop_returnsNil() {
        // Capture shorter than one loop (+ phase offset) can't hold an aligned loop →
        // nil, so the caller falls back to endAligned.
        XCTAssertNil(A.loopAligned(videoDuration: 5, audioDuration: 20, loopSeconds: 8))
        XCTAssertNil(A.loopAligned(videoDuration: 20, audioDuration: 5, loopSeconds: 8))
        XCTAssertNil(A.loopAligned(videoDuration: 8, audioDuration: 8,
                                   loopSeconds: 8, secondsSinceBarStart: 0.5))
    }

    func testLoopAligned_nonFiniteOrNonPositive_returnsNil() {
        XCTAssertNil(A.loopAligned(videoDuration: .nan, audioDuration: 20, loopSeconds: 8))
        XCTAssertNil(A.loopAligned(videoDuration: 20, audioDuration: 20, loopSeconds: 0))
        XCTAssertNil(A.loopAligned(videoDuration: 20, audioDuration: 20, loopSeconds: .infinity))
        // A non-finite phase offset is treated as 0, not a failure (defensive, like the
        // audio path): the exact-length cut still succeeds.
        XCTAssertEqual(A.loopAligned(videoDuration: 20, audioDuration: 20,
                                     loopSeconds: 8, secondsSinceBarStart: .nan),
                       A(videoStartSeconds: 12, audioStartSeconds: 12, durationSeconds: 8))
    }

    func testLoopAligned_bothStartsShareTheSamePhase() {
        // Property: video & audio keep the SAME window length and the SAME offset from
        // their own ends, so the muxed clip stays in sync while being an exact loop.
        for (v, a, loop, ago) in [(30.0, 30.0, 4.0, 0.0), (55.0, 55.0, 32.0, 2.0),
                                  (18.0, 18.0, 2.0, 0.25)] {
            guard let al = A.loopAligned(videoDuration: v, audioDuration: a,
                                         loopSeconds: loop, secondsSinceBarStart: ago) else {
                return XCTFail("expected an alignment for \(v),\(a),\(loop),\(ago)")
            }
            XCTAssertEqual(al.durationSeconds, loop, accuracy: 1e-9)
            XCTAssertEqual(v - al.videoStartSeconds, a - al.audioStartSeconds, accuracy: 1e-9)
            XCTAssertEqual(v - al.videoStartSeconds, ago + loop, accuracy: 1e-9)
        }
    }
}
