// PianoRollPauseRequestTests.swift
// Echoelmusic — #161: the Notes editor's transport button is a PAUSE, not the end of the bio
// session. The ONE-Stop law means any transport stop ends the session (camera down, pulse lock
// lost, ~20 s of finger-on-lens to get back), which made the roll unusable during a live take.
// The roll now raises a ONE-SHOT flag before stopping the clock and the Studio consumes it.
//
// This pins the flag's contract, which is the whole mechanism and the whole risk: a flag that
// stuck would turn a LATER real Stop into a pause — a session that refuses to end. Note what
// this does NOT cover: the two call sites (PianoRollView's button, EchoelStudioView's transport
// onChange) are inside `View` bodies and unreachable from XCTest — same limit as the panic
// fan-out, task #168. What is tested is that the flag cannot latch.

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

    func testRepeatedRequests_stillYieldOneConsume() {
        // The roll can raise it twice (double-tap, a re-entrant button) without banking two
        // pauses; one raise and ten raises must be indistinguishable to the consumer.
        let m = PianoRollModel()
        m.requestPlaybackOnlyStop()
        m.requestPlaybackOnlyStop()
        m.requestPlaybackOnlyStop()
        XCTAssertTrue(m.consumePlaybackOnlyStopRequest())
        XCTAssertFalse(m.consumePlaybackOnlyStopRequest(), "raises must not accumulate")
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

    func testConsumeDoesNotTouchTheEditablePattern() {
        // The flag lives on the model that also owns the user's notes; reading it must be
        // pure. A consume that snapshotted or cleared anything would eat an undo step.
        let m = PianoRollModel()
        m.add(pitch: 60, startStep: 0)
        m.add(pitch: 64, startStep: 4)
        let before = m.notes
        let canUndoBefore = m.canUndo

        m.requestPlaybackOnlyStop()
        _ = m.consumePlaybackOnlyStopRequest()
        _ = m.consumePlaybackOnlyStopRequest()

        XCTAssertEqual(m.notes.count, before.count, "the pause request altered the pattern")
        XCTAssertEqual(m.notes.map(\.pitch), before.map(\.pitch))
        XCTAssertEqual(m.canUndo, canUndoBefore, "the pause request disturbed the undo stack")
    }
}
