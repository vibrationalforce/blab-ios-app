// PianoRollPauseRequestTests.swift
// Echoelmusic — #161: the Notes editor's transport button is a PAUSE, not the end of the bio
// session. The ONE-Stop law means any transport stop ends the session (camera down, pulse lock
// lost, ~20 s of finger-on-lens to get back), which made the roll unusable during a live take.
// The roll now raises a ONE-SHOT flag before stopping the clock and the Studio consumes it.
//
// TWO layers are pinned here, because the first version of this file pinned only the first and
// the real defect was in the second:
//   1. the flag's accessor contract (read-and-clear), on PianoRollModel;
//   2. `TransportTransition.decide`, the extracted decision the Studio's observer runs.
// Layer 2 exists because the shipped observer read the flag AFTER a `guard running`, so a pause
// requested with no take live stayed outstanding and downgraded the next REAL Stop to a pause —
// music off, camera and torch still on. The accessor was flawless throughout; only a test at the
// decision seam could have caught it, which is why that seam is now a pure type in `Core/`
// (repo convention: FlashGuard, AutomationCanvasMath, LaunchQuantizer.shouldDefer).
//
// Still NOT covered: the two call sites themselves (PianoRollView's button, EchoelStudioView's
// onChange) sit in `View` bodies, unreachable from XCTest — same limit as the panic fan-out,
// task #168. Notably, `decide` cannot express the defect any more, but nothing here proves the
// observer calls it before its guard; that is enforced by comment, not by test.

import XCTest
@testable import Echoelmusic

@MainActor
final class PianoRollPauseRequestTests: XCTestCase {

    func testFreshModel_doesNotRequestAPause() {
        // Default must be the FULL stop: an accidental default of true would silently make
        // every transport stop in the app a pause and leave the camera running after Stop.
        let m = PianoRollModel()
        XCTAssertFalse(m.consumePlaybackOnlyStopRequest(),
                       "a model that was never asked to pause must not claim a pause")
    }

    func testRequest_isVisibleExactlyOnce() {
        let m = PianoRollModel()
        m.requestPlaybackOnlyStop()
        XCTAssertTrue(m.consumePlaybackOnlyStopRequest(), "the raised flag must be seen")
        XCTAssertFalse(m.consumePlaybackOnlyStopRequest(),
                       "the flag latched — a later REAL stop would be downgraded to a pause")
    }

    func testRequestAfterConsume_worksAgain() {
        // Pause → play → pause: the second pause must still be a pause, not a full stop.
        let m = PianoRollModel()
        m.requestPlaybackOnlyStop()
        XCTAssertTrue(m.consumePlaybackOnlyStopRequest())
        m.requestPlaybackOnlyStop()
        XCTAssertTrue(m.consumePlaybackOnlyStopRequest(),
                      "consuming must not permanently disable the request")
    }

    // MARK: - The decision the Studio's transport observer runs

    /// THE REGRESSION TEST for the shipped defect. A pause requested while no take is live must
    /// resolve to `.ignore` — and because the caller has already consumed the flag by the time
    /// `decide` runs, that request is gone rather than saved up for the next stop. This is the
    /// case the original inline `guard running` handled by returning BEFORE the read.
    func testDecide_pauseRequestedWithNoTakeLive_isIgnored() {
        XCTAssertEqual(TransportTransition.decide(isPlaying: false, running: false,
                                                  pauseRequested: true), .ignore)
        XCTAssertEqual(TransportTransition.decide(isPlaying: true, running: false,
                                                  pauseRequested: true), .ignore)
    }

    /// The ONE-Stop law: a stop with no pause request ends the session. If this ever returns
    /// `.pausePlayback`, the app's Stop button stops the music and leaves the camera live.
    func testDecide_plainStopDuringATake_endsTheSession() {
        XCTAssertEqual(TransportTransition.decide(isPlaying: false, running: true,
                                                  pauseRequested: false), .endSession)
    }

    func testDecide_requestedPauseDuringATake_pauses() {
        XCTAssertEqual(TransportTransition.decide(isPlaying: false, running: true,
                                                  pauseRequested: true), .pausePlayback)
    }

    /// Starting the clock during a live take resumes — never ends the session, and never
    /// depends on the pause flag (a stale request must not make a START do something odd).
    func testDecide_clockStartingDuringATake_resumes() {
        XCTAssertEqual(TransportTransition.decide(isPlaying: true, running: true,
                                                  pauseRequested: false), .resume)
        XCTAssertEqual(TransportTransition.decide(isPlaying: true, running: true,
                                                  pauseRequested: true), .resume)
    }

    /// Totality, so a future case cannot be added without a decision: every one of the eight
    /// input combinations must map somewhere, and only a stop during a live take may ever
    /// produce `.endSession` — the one outcome that tears the session down.
    func testDecide_isTotal_andOnlyAStopDuringATakeEndsTheSession() {
        for isPlaying in [true, false] {
            for running in [true, false] {
                for pauseRequested in [true, false] {
                    let action = TransportTransition.decide(isPlaying: isPlaying,
                                                            running: running,
                                                            pauseRequested: pauseRequested)
                    if action == .endSession {
                        XCTAssertTrue(!isPlaying && running && !pauseRequested,
                                      "endSession from isPlaying=\(isPlaying) running=\(running) "
                                      + "pauseRequested=\(pauseRequested)")
                    }
                    if !running {
                        XCTAssertEqual(action, .ignore,
                                       "no take live ⇒ nothing to pause, resume or end")
                    }
                }
            }
        }
    }
}
