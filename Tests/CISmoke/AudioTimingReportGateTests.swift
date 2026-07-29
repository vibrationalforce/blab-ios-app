// AudioTimingReportGateTests.swift
// Echoel — the crackle meter must not be able to go quiet in a way that reads as "all clean".
//
// THE DEFECT, found by reading the founder's FIRST real log (v10.79.357, build 2474,
// 2026-07-29). Nine minutes of session produced exactly one `audio timing:` line, at the
// 60-second mark: "nothing late in 60 s … 600 intervals seen". That is by design — after the
// first window the meter speaks only when a window is dirty, so silence is supposed to mean
// clean. I nearly reported the instrument as dead before checking, which is its own lesson.
//
// But the suppression asked `Tally.isClean`, and `isClean` is `glitchCount == 0`. It ignores
// the denominator entirely — the very denominator `RenderGapDetector` documents as "the
// honest denominator: a 60 s window in which the graph ran for 5 s is not 60 s of evidence".
// So a window in which the tap fired ZERO times (route torn down, tap lost after a
// media-services reset, graph stopped while the engine still claims to run) has glitchCount 0,
// counts as clean, and is silently swallowed.
//
// The consequence is precise and it is the whole reason the meter exists: the founder is asked
// to play until it crackles and then send the log. If the tap dies at minute two, every later
// window is silent, and the log he sends is indistinguishable from a perfect one. He would be
// told "not overload" on the strength of no measurement at all — a confidently wrong
// diagnostic, which is worse than none, because it ENDS the search.
//
// WHY A PURE PREDICATE. Same reasoning as the sibling `AudioEngineSelfHealTests`: the decision
// is the part that can be wrong, and it is the part no device can be asked to demonstrate on
// command (you cannot make a tap die to order). `shouldReportTimingWindow` is `nonisolated
// static` for the same reason `shouldSelfHeal` is — `AudioEngine` is `@MainActor`, and a
// predicate an ordinary test method cannot call is a predicate that will not be tested.
//
// WHAT THIS CANNOT PROVE: that the tap actually stops in the situations described, that
// `masterEngine.isRunning` is true when it does, or that the emitted line reaches
// echoel_diag.log. It proves the rule, not the wiring.

#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

final class AudioTimingReportGateTests: XCTestCase {

    /// Proof of life. Without this the very first "no line" is ambiguous between a clean
    /// audio path and an instrument that never started.
    func testTheFirstWindowAlwaysSpeaksEvenWhenPerfectlyClean() {
        XCTAssertTrue(AudioEngine.shouldReportTimingWindow(firstWindow: true,
                                                           isClean: true,
                                                           measuredIntervals: 600,
                                                           engineRunning: true))
    }

    /// The first window must speak even with nothing measured — that IS the proof of life,
    /// and the case where it matters most.
    func testTheFirstWindowSpeaksWithNothingMeasured() {
        XCTAssertTrue(AudioEngine.shouldReportTimingWindow(firstWindow: true,
                                                           isClean: true,
                                                           measuredIntervals: 0,
                                                           engineRunning: false))
    }

    /// The actual finding always speaks, however many windows have gone before.
    func testADirtyWindowAlwaysSpeaks() {
        XCTAssertTrue(AudioEngine.shouldReportTimingWindow(firstWindow: false,
                                                           isClean: false,
                                                           measuredIntervals: 600,
                                                           engineRunning: true))
    }

    /// ⛔ THE REGRESSION GUARD. Delete the blind-while-running clause and this goes red.
    /// A window that classified nothing while the engine claims to be running is a
    /// contradiction, and it must not be filed under "clean".
    func testABlindWindowSpeaksWhileTheEngineClaimsToBeRunning() {
        XCTAssertTrue(AudioEngine.shouldReportTimingWindow(firstWindow: false,
                                                           isClean: true,
                                                           measuredIntervals: 0,
                                                           engineRunning: true),
                      "A window that measured NOTHING is not evidence of a clean audio path. "
                      + "Suppressing it makes a dead instrument look identical to a healthy "
                      + "one in the log the founder actually sends.")
    }

    /// The other half, and the reason the clause is gated at all: a stopped instrument must
    /// stay quiet. A diagnostic that prints a line a minute while nobody is playing gets
    /// tuned out, and a tuned-out diagnostic is the same as no diagnostic — which is exactly
    /// how `continue-on-error` stayed invisible for fourteen hours.
    func testAStoppedInstrumentStaysQuiet() {
        XCTAssertFalse(AudioEngine.shouldReportTimingWindow(firstWindow: false,
                                                            isClean: true,
                                                            measuredIntervals: 0,
                                                            engineRunning: false))
    }

    /// The ordinary case, and the one that keeps the log readable: a clean measured window
    /// after the first says nothing at all.
    func testACleanMeasuredWindowStaysQuiet() {
        XCTAssertFalse(AudioEngine.shouldReportTimingWindow(firstWindow: false,
                                                            isClean: true,
                                                            measuredIntervals: 600,
                                                            engineRunning: true),
                       "Nine minutes of clean playing must not produce nine lines — that is "
                       + "what makes the ones that DO appear worth reading.")
    }
}
#endif
