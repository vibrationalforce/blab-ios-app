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
// WHY THIS FILE IS IN `Tests/CISmoke` AND NOT `Tests/EchoelmusicTests`: it was written
// into the latter, and review pointed out that this made the paragraph above a lie.
// `project.yml`'s blocking `EchoelmusicTests` target sources ONLY `Tests/CISmoke`; the
// 300+ files in the other directory run in `full-tests.yml`, which is `continue-on-error`
// on its build step (#208). "Deleting either half fails a test" is only true of a test
// that something can actually fail on. A silent-forever audio bug is precisely the class
// `SilenceClassSmokeTests` states this bundle exists for, so this belongs here on merit,
// not as a workaround.
//
// What this CANNOT prove: that iOS delivers the notification, that `setActive(true)`
// succeeds while another app holds the session, or that the engine graph survives. Nor
// does it cover the OTHER two decisions this change makes — the `.ended` foreground gate
// and the scene-phase resume — both of which live in code this predicate cannot reach.
// Review found real defects in exactly that uncovered area, which is the honest measure
// of what a pure-predicate test buys: rigour over a third of the change.

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

    // MARK: - The scene-phase twin (the gate that could not see the law)

    /// Returning to the foreground after an interruption must restart the engine — this
    /// is the Siri / alarm-banner case, where the app never reached `.background` so
    /// neither of the other two conditions can fire.
    func testForegroundResume_healsAnInterruptionThatNeverBackgroundedTheApp() {
        XCTAssertTrue(Engine.shouldResumeOnForeground(cameFromBackground: false,
                                                      wasBackgrounded: false,
                                                      wasInterrupted: true,
                                                      intentionallyStopped: false),
                      "Siri and an alarm banner leave the app foreground — this is the "
                      + "only condition that can see them")
    }

    /// THE REGRESSION THIS PREDICATE EXISTS FOR. Written inline in the view, the gate
    /// could not read `intentionallyStopped` (it is private to `AudioEngine`), so a
    /// stopped-but-previously-interrupted engine restarted itself on the next
    /// `.inactive → .active` transition — a Control-Centre swipe was enough.
    func testForegroundResume_neverOverridesADeliberateStop() {
        for (name, fromBackground, wasBackgrounded, interrupted) in [
            ("plain foreground return", true,  true,  false),
            ("interrupted then stopped", false, false, true),
            ("everything at once",       true,  true,  true)
        ] {
            XCTAssertFalse(Engine.shouldResumeOnForeground(cameFromBackground: fromBackground,
                                                           wasBackgrounded: wasBackgrounded,
                                                           wasInterrupted: interrupted,
                                                           intentionallyStopped: true),
                           "\(name): the user's last explicit intent outranks every "
                           + "automatic reason to start audio")
        }
    }

    /// And the two conditions that were already there keep working, so the new predicate
    /// is a faithful replacement for the inline `||` and not a behaviour change.
    func testForegroundResume_preservesTheTwoOriginalConditions() {
        XCTAssertTrue(Engine.shouldResumeOnForeground(cameFromBackground: true, wasBackgrounded: false,
                                                      wasInterrupted: false, intentionallyStopped: false))
        XCTAssertTrue(Engine.shouldResumeOnForeground(cameFromBackground: false, wasBackgrounded: true,
                                                      wasInterrupted: false, intentionallyStopped: false))
        XCTAssertFalse(Engine.shouldResumeOnForeground(cameFromBackground: false, wasBackgrounded: false,
                                                       wasInterrupted: false, intentionallyStopped: false),
                       "a foreground return with no reason behind it must not start audio")
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
