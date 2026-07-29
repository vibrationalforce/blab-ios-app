// LoopExporterCancelTests.swift
// Echoel — the abort contract. Founder 2026-07-28: "Es ist schon wichtig das man die
// Aufnahme dann auch abbrechen kann, wenn man sich verspielt hat."
//
// Driving a real capture needs an AudioEngine + BeatPlayer, so what is pinned here is the
// part that is pure STATE and that a future edit could quietly break: WHEN the abort is
// offered. Both directions matter equally —
//   · offering it when nothing can be stopped is a lying control (the tap does nothing);
//   · withholding it while a take runs is the defect this change exists to fix.

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
@testable import Echoelmusic

@MainActor
final class LoopExporterCancelTests: XCTestCase {

    func testAFreshExporter_offersNoAbort() {
        let exporter = LoopExporter()
        XCTAssertEqual(exporter.status, .idle)
        XCTAssertFalse(exporter.isCancellable, "there is nothing to abort before a take starts")
    }

    func testCancelOnIdle_isASilentNoOp_notAStateChange() {
        // The button is disabled here, but a stray call (double tap, a future caller that
        // forgets to check) must not push the exporter into some half-state.
        let exporter = LoopExporter()
        exporter.cancel()
        XCTAssertEqual(exporter.status, .idle)
        XCTAssertFalse(exporter.isCancellable)
    }

    func testResetFromIdle_staysIdle_andStillOffersNoAbort() {
        let exporter = LoopExporter()
        exporter.reset()
        XCTAssertEqual(exporter.status, .idle)
        XCTAssertFalse(exporter.isCancellable)
    }

    // MARK: - Ending an attempt must not erase why it failed (#216)

    /// THE DEFECT. Both UI callers ended with an unconditional `reset()`, which wiped
    /// `.failed` in the same synchronous turn — so not one of the exporter's six failure
    /// messages could ever be rendered. The take vanished and the button read "Record 8
    /// bars → send" again, which says "nothing happened", not "that did not work".
    ///
    /// Same reason this is a pure static: every path that produces a `.failed` needs a
    /// live `AudioEngine`, so a test that tried to reach one would pin nothing.
    func testAFailedAttemptSurvivesTheEndOfTheAttempt() {
        XCTAssertFalse(
            LoopExporter.shouldReturnToIdle(after: .failed("Recording could not be written to disk")),
            "the reason a take was lost is the one thing left to show the user")
    }

    /// And every other status still clears, or the button hangs on "Writing .wav…" — the
    /// defect the unconditional reset was there to prevent in the first place. Both
    /// directions, so a "fix" that just stops resetting cannot pass.
    func testEveryNonFailureStatusStillReturnsToIdle() {
        for status: LoopExporter.Status in [.idle, .capturing, .rendering,
                                            .done(URL(fileURLWithPath: "/tmp/x.wav"))] {
            XCTAssertTrue(LoopExporter.shouldReturnToIdle(after: status),
                          "\(status) must clear — a busy state left standing is a hung button")
        }
    }

    /// A stray call on an idle exporter must not invent a state — same contract the
    /// `cancel()` test above pins. It proves nothing about the predicate; see the
    /// disclaimer below, which review corrected me on.
    func testFinishAttemptFromIdleIsANoOp() {
        let exporter = LoopExporter()
        exporter.finishAttempt()
        XCTAssertEqual(exporter.status, .idle)
    }

    // NOT TESTED HERE, stated so the gap is known rather than assumed covered: that a
    // running capture actually stops, that the temp file is deleted, and that the
    // transport is left stopped. All three need a live AudioEngine + BeatPlayer, which
    // this suite cannot stand up. They are device-verify items — see the commit body.
    //
    // AND THE #216 FIX ITSELF IS NOT PINNED, which is a sharper gap than the first version
    // of this block admitted. Exactly ONE thing above is a regression test: the truth table
    // of `shouldReturnToIdle`. Everything else would survive a revert —
    //   · put `exporter.reset()` back at both `EchoelStudioView` call sites and all three
    //     new tests stay green; the defect WAS the call site;
    //   · implement `finishAttempt()` as a bare `status = .idle` — identical to `reset()` —
    //     and they still pass, because from `.idle` the two are indistinguishable and no
    //     test here can reach `.failed` without an engine;
    //   · delete the warning line in `EchoelStudioView` and nothing here notices, since no
    //     unit test in this suite can build that view.
    // The predicate is the piece a future "simplification" is most likely to collapse, so
    // pinning it is worth something — but it is not the same as pinning the fix.
}
#endif
