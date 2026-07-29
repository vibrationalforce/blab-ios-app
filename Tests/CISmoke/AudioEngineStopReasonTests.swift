// AudioEngineStopReasonTests.swift
// Echoel — an engine the SYSTEM stopped must come back; one the USER stopped must not.
//
// THE DEFECT, from the founder's device log 2475 (v10.79.358) and his four words:
// *"Ich hab keinen Sound alles stumm"*.
//
// One boolean, `intentionallyStopped`, was answering two questions that have OPPOSITE
// correct answers for the same event:
//   1. "May a self-healing path resurrect this engine?" — for the 2.5.4 idle stop: NO.
//      Restarting an idle engine in the background is the "plays silent audio to stay
//      alive" rejection signature (audio-thread review 2026-07-16, F1/F2).
//   2. "May coming back to the FOREGROUND start it again?" — for the same stop: YES. That
//      is the entire point of only stopping while idle.
//
// The flag said no to both. The log shows the consequence with nothing left to infer:
//
//     1785340629.599  scene: inactive → background
//     1785340629.657  scene: idle audio engine stopped (2.5.4)
//     1785340641.907  scene: inactive → active          ← and NO "scene: audio resumed"
//     1785340644.127  Start tapped
//     1785340644.302  polyVoice.noteOn#1 enqueue pitch=64
//
// Transport running, generator running, notes enqueued, visuals moving — and the
// AVAudioEngine paused since second 629. Total silence with every other indicator healthy,
// and no way back short of relaunching the app. It is the worst shape a bug can have,
// because everything the user can see says it is working.
//
// WHAT HID IT WAS THE NAME. "Intentionally" reads as "the user meant it", and the resume
// gate was written against that reading. But both `stop()` callers are the idle rule
// (`EchoelmusicApp`: the `.background` branch and the `background-idle` transport
// subscriber) — there is NO user-initiated engine stop in this app at all. The gate was
// suppressing resume on behalf of an intent nobody had ever expressed.
//
// WHY TWO PURE FUNCTIONS AND NOT ONE WITH A COMMENT: they differ on exactly one input, and
// that difference is the whole fix. Merged back into a single predicate, the next person to
// touch it has to rediscover why — which is how this happened the first time.
//
// WHAT THIS CANNOT PROVE: that iOS delivers the scene-phase transitions, that `start()`
// succeeds on the way back, or that sound actually returns. It proves the two rules, not
// the wiring — the same honest limit the sibling `AudioEngineSelfHealTests` states.

#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

final class AudioEngineStopReasonTests: XCTestCase {

    // MARK: - The bug

    /// ⛔ THE REGRESSION GUARD. Revert the fix — pass `intentionallyStopped` to the resume
    /// gate again, or make `resumeSuppressed` return true for `.idleBackground` — and this
    /// goes red. It is the difference between an app that comes back and one that is silent
    /// until relaunch.
    func testAnIdleBackgroundStopMustNotSuppressTheForegroundResume() {
        XCTAssertFalse(AudioEngine.resumeSuppressed(after: .idleBackground),
                       "The 2.5.4 idle stop is the SYSTEM's decision, not the user's. If it "
                       + "suppresses resume, returning to the foreground leaves a dead engine "
                       + "and every later Start is silent — device log 2475.")
    }

    /// The other direction. A user stop must survive a foreground return, or the app
    /// restarts audio against the user's last explicit instruction.
    func testAUserStopSuppressesTheForegroundResume() {
        XCTAssertTrue(AudioEngine.resumeSuppressed(after: .user))
    }

    /// A running engine is not suppressed by anything.
    func testARunningEngineResumesFreely() {
        XCTAssertFalse(AudioEngine.resumeSuppressed(after: nil))
    }

    // MARK: - The half that must NOT change

    /// 2.5.4 compliance. BOTH reasons stand the self-healing paths down: an in-flight
    /// recovery Task or a late configuration-change notification must never restart an
    /// engine in the background. This is the behaviour the fix deliberately preserves, and
    /// a test that only pinned the new half would have let the fix trade one rejection risk
    /// for a silence bug.
    func testBothStopReasonsStandDownSelfHealing() {
        XCTAssertTrue(AudioEngine.selfHealSuppressed(after: .idleBackground),
                      "Resurrecting an idle engine in the background is the App Store 2.5.4 "
                      + "'silent audio to stay alive' signature.")
        XCTAssertTrue(AudioEngine.selfHealSuppressed(after: .user))
    }

    func testARunningEngineMaySelfHeal() {
        XCTAssertFalse(AudioEngine.selfHealSuppressed(after: nil))
    }

    /// The two predicates must NOT be the same function. If someone simplifies them back
    /// into one, this fails — and it fails on the exact input where the app broke.
    func testTheTwoRulesDisagreeAndThatDisagreementIsThePoint() {
        XCTAssertNotEqual(AudioEngine.selfHealSuppressed(after: .idleBackground),
                          AudioEngine.resumeSuppressed(after: .idleBackground),
                          "An idle-background stop must block self-healing AND allow a "
                          + "foreground resume. One boolean cannot carry both answers — that "
                          + "was the defect.")
    }
}
#endif
