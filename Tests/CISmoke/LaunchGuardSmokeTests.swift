// LaunchGuardSmokeTests.swift
// Echoel — the counter that decides whether a user reaches the instrument at all.
//
// THE DEFECT (#214). `beginLaunch()` counts EVERY launch; the only thing that resets it,
// `confirmHealthy()`, lived solely in `mainContent`'s startup task — and `mainContent` is
// not built at all while onboarding is unfinished. So a brand-new user who installs,
// opens, gets interrupted before finishing the intro and comes back later meets the
// crash-recovery screen on their SECOND launch, having never crashed. As a first
// impression of the product.
//
// WHY IT IS IN CISmoke, since this bundle should not become a dumping ground: this is
// the blocking bundle (`project.yml`'s `EchoelmusicTests` target sources only this
// directory), and `LaunchGuard` decides whether the app presents the instrument or a
// recovery screen. "The user cannot reach the product" is the same class the bundle
// exists for. It is also pure `UserDefaults` arithmetic — fast, deterministic, no device.
//
// WHAT THESE TESTS DO NOT COVER, stated plainly because the previous cycle shipped a
// test file that overclaimed and review caught it: they exercise `LaunchGuard` in
// isolation. They do NOT prove that `OnboardingView`'s `.onAppear` calls
// `confirmHealthy()` — that wiring lives in `EchoelmusicApp`'s scene body, which no unit
// test here can render. If someone deletes that one line, every test below stays green.
// What they pin is that `confirmHealthy()` is a real reset and that two unconfirmed
// launches are what trips Safe Mode — the mechanism the fix leans on.

import XCTest
@testable import Echoelmusic

@MainActor
final class LaunchGuardSmokeTests: XCTestCase {

    // `LaunchGuard`'s counter lives in `UserDefaults.standard`, which under a TEST_HOST
    // build is the host app's own domain. Normalise on both sides so these tests neither
    // inherit a stale count nor leave one behind for whatever runs next.
    //
    // `resetForTesting()`, not `reset()`: the product form deliberately leaves the
    // process-global `cachedSafeMode` alone, and two tests below set it `true`. Since
    // this bundle runs INSIDE the host app, leaving it set flips the LIVE app to
    // `SafeModeView` on its next body evaluation — tearing down `WorkspaceView` and
    // cancelling its startup task. Nothing here observes the view tree, so it is a trap
    // for the next test added rather than a present failure. Review found it; closing it
    // now is cheaper than debugging it later.
    override func setUp() async throws { LaunchGuard.resetForTesting() }
    override func tearDown() async throws { LaunchGuard.resetForTesting() }

    /// THE REGRESSION THIS FIX LEANS ON. One confirmed launch must leave the next one
    /// clean — that is the entire mechanism `OnboardingView.onAppear` now uses.
    func testAConfirmedLaunchLeavesTheNextOneOutOfSafeMode() {
        LaunchGuard.beginLaunch()
        LaunchGuard.confirmHealthy()
        LaunchGuard.beginLaunch()
        XCTAssertFalse(LaunchGuard.isSafeMode,
                       "a launch that confirmed itself healthy must not push its "
                       + "successor into a crash-recovery screen (#214)")
    }

    /// And the protection still works: two launches in a row that never confirm ARE what
    /// Safe Mode is for. Without this, "fix the false positive" could be implemented by
    /// gutting the guard and both tests would still look fine.
    func testTwoUnconfirmedLaunchesDoTripSafeMode() {
        LaunchGuard.beginLaunch()
        XCTAssertFalse(LaunchGuard.isSafeMode, "one unconfirmed launch is not a crash loop")
        LaunchGuard.beginLaunch()
        XCTAssertTrue(LaunchGuard.isSafeMode,
                      "two in a row is the signal the guard exists to catch")
    }

    /// `reset()` is what the Safe-Mode screen itself calls, so a user who lands there
    /// once does not land there forever (the lock-in a fast quit/relaunch used to cause).
    func testResetClearsTheCounterSoSafeModeIsAOneShot() {
        LaunchGuard.beginLaunch()
        LaunchGuard.beginLaunch()
        XCTAssertTrue(LaunchGuard.isSafeMode)
        LaunchGuard.reset()
        LaunchGuard.beginLaunch()
        XCTAssertFalse(LaunchGuard.isSafeMode, "Safe Mode is a speed bump, not a state")
    }

    // MARK: - Re-arming for the risky startup (review finding on #214)

    /// THE ASYMMETRY THAT MAKES THE FIX SAFE. Onboarding confirms the launch healthy, and
    /// `mainContent` then runs its first-ever startup IN THE SAME PROCESS. Without
    /// re-arming, a crash in that startup would be uncounted — and it is the launch least
    /// able to afford that: cold caches, first permission prompts, the profile of the
    /// crash the guard was written for.
    func testRiskyStartupIsReArmedAfterAUIConfirmation() {
        LaunchGuard.beginLaunch()
        LaunchGuard.confirmHealthy()        // what onboarding's .onAppear does
        LaunchGuard.armForRiskyStartup()    // what mainContent's task does next
        LaunchGuard.beginLaunch()           // the launch after a startup crash
        XCTAssertTrue(LaunchGuard.isSafeMode,
                      "a crash in the first post-onboarding startup must still escalate — "
                      + "otherwise the fix trades a false positive for a missed real one")
    }

    /// And on every NORMAL launch it must change nothing, or it would double-count and
    /// bring Safe Mode one launch too EARLY — the opposite failure.
    func testReArmingIsANoOpOnANormalLaunch() {
        LaunchGuard.beginLaunch()           // counter is 1, nothing confirmed it
        LaunchGuard.armForRiskyStartup()    // must not touch it
        LaunchGuard.beginLaunch()
        XCTAssertTrue(LaunchGuard.isSafeMode, "two unconfirmed launches, unchanged")

        LaunchGuard.resetForTesting()
        LaunchGuard.beginLaunch()
        LaunchGuard.armForRiskyStartup()
        LaunchGuard.confirmHealthy()        // a healthy studio launch, confirmed at 4/4
        LaunchGuard.beginLaunch()
        XCTAssertFalse(LaunchGuard.isSafeMode, "a confirmed launch still leaves a clean slate")
    }

    /// The decision is frozen for the process at `beginLaunch()`. Confirming later must
    /// not flip the screen out from under a user who is already reading it — the branch
    /// in `EchoelmusicApp` reads `isSafeMode` on every body evaluation.
    func testTheSafeModeDecisionIsFrozenForTheProcess() {
        LaunchGuard.beginLaunch()
        LaunchGuard.beginLaunch()
        XCTAssertTrue(LaunchGuard.isSafeMode)
        LaunchGuard.confirmHealthy()
        XCTAssertTrue(LaunchGuard.isSafeMode,
                      "the counter is cleared for NEXT launch; this one keeps its verdict")
    }
}
