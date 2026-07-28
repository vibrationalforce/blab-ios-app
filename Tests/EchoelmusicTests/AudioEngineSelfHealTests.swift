// AudioEngineSelfHealTests.swift
// Echoel — an interrupted engine must heal itself; a stopped one must not.
//
// THE DEFECT. `AudioConfiguration.onInterruptionBegan` sets `isRunning = false`, and the
// configuration-change watchdog used to read `guard isRunning || degraded`. So the
// interruption handler DISARMED the one mechanism that could rescue it. Combined with the
// `.ended` branch resuming only on `.shouldResume` (and returning early when the options
// key was absent), an interruption could leave the instrument silent for the rest of the
// session with no in-app way back — the app looks alive, the visuals keep running, and
// there is no sound until relaunch. On a live instrument that is worse than a crash.
//
// WHY THE RULE IS A PURE FUNCTION AND NOT AN `if`: the two halves pull in opposite
// directions and both have already been gotten wrong once. A deliberate stop must NEVER
// self-heal — review finding F2 caught a stale `degraded` re-opening the gate while the
// app was backgrounded, i.e. resurrecting a silent engine nobody could hear. An
// interrupted engine must ALWAYS heal. Written inline, the next person who touches the
// guard has to rediscover both. Written here, deleting either half fails a test.
//
// What this CANNOT prove: that iOS delivers the notification, that `setActive(true)`
// succeeds while another app holds the session, or that the engine graph survives. Those
// need a device. This pins the decision, not the outcome.

#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

final class AudioEngineSelfHealTests: XCTestCase {

    private typealias Engine = AudioEngine

    // MARK: - The interruption half (the bug)

    /// THE REGRESSION TEST. An interruption leaves `isRunning == false` and nothing else
    /// set — exactly the state that used to read as "not our problem".
    func testAnInterruptedEngineHeals_eventhoughItIsNotRunning() {
        XCTAssertTrue(Engine.shouldSelfHeal(isRunning: false,
                                            degraded: false,
                                            wasInterrupted: true,
                                            intentionallyStopped: false),
                      "a paused-by-interruption engine is the case this rule exists for")
    }

    /// And a plain stopped engine that was NOT interrupted still must not heal, or the
    /// flag would be decoration: the fix has to be the flag, not a loosened guard.
    func testAStoppedEngineThatWasNotInterrupted_staysStopped() {
        XCTAssertFalse(Engine.shouldSelfHeal(isRunning: false,
                                             degraded: false,
                                             wasInterrupted: false,
                                             intentionallyStopped: false),
                       "without a reason to run, do not start audio behind the user's back")
    }

    // MARK: - The deliberate-stop half (review finding F2)

    /// An explicit stop outranks EVERY other reason. Each of the three heal-triggers is
    /// checked against it separately — a `||` chain that forgot the intentional-stop
    /// guard would pass a test that only tried one of them.
    func testAnIntentionalStopOutranksEveryReasonToHeal() {
        for (name, isRunning, degraded, interrupted) in [
            ("running",     true,  false, false),
            ("degraded",    false, true,  false),
            ("interrupted", false, false, true),
            ("all three",   true,  true,  true)
        ] {
            XCTAssertFalse(Engine.shouldSelfHeal(isRunning: isRunning,
                                                 degraded: degraded,
                                                 wasInterrupted: interrupted,
                                                 intentionallyStopped: true),
                           "\(name): a deliberate stop must never resurrect a silent "
                           + "engine in the background (review F2)")
        }
    }

    // MARK: - The two pre-existing triggers must survive the change

    /// `degraded` was already a heal trigger before `wasInterrupted` existed. Pinned so
    /// the new flag is an ADDITION, not a replacement — the failure mode of a rewrite.
    func testTheTwoOriginalTriggersStillHeal() {
        XCTAssertTrue(Engine.shouldSelfHeal(isRunning: true, degraded: false,
                                            wasInterrupted: false, intentionallyStopped: false),
                      "a running engine whose graph was rebuilt must be restarted")
        XCTAssertTrue(Engine.shouldSelfHeal(isRunning: false, degraded: true,
                                            wasInterrupted: false, intentionallyStopped: false),
                      "a degraded engine is the retry case")
    }
}
#endif
