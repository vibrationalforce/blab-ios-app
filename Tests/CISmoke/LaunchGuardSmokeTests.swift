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
// WHAT THESE TESTS DO NOT COVER, stated plainly because an earlier cycle shipped a
// test file that overclaimed and review caught it: they exercise `LaunchGuard` in
// isolation. They do NOT prove that `OnboardingView`'s `.onAppear` calls
// `confirmHealthy()` — that wiring lives in `EchoelmusicApp`'s scene body, which no unit
// test here can render. What they pin is that `confirmHealthy()` is a real reset and that
// two unconfirmed launches are what trips Safe Mode — the mechanism the fix leans on.
//
// ⭐ #915 NARROWED THAT CAVEAT BY EXACTLY ONE STEP, and no further. The last claim below
// READS `EchoelmusicApp.swift` and pins that EVERY `LaunchGuard` call site is still there
// and still announced in the exported diag log. (⛔ The first draft wrote "the five call
// sites". There are six — it had missed the Safe-Mode `.onAppear` reset, which was also the
// site with no line of its own. A count in prose is a date, not a fact.) So "delete that one line and
// every test stays green" is no longer true for the CALL ITSELF. It is still true for the
// BEHAVIOUR: nothing here renders a scene, so no test proves `.onAppear` ever fires.
//
// ⛔ #955 TURNED THAT LAST CLAIM RED ON CORRECT CODE, and #955b repaired it in the claim
// itself. The crumb needle was the literal SHAPE `"LaunchGuard:`; #955 replaced three of
// those literals in `EchoelmusicApp.swift` with named constants, so three call sites owned
// no breadcrumb and the scan failed for a reason that had nothing to do with the property it
// guards (#364). The needle set now also accepts the constants BY NAME — and anchors them,
// by asserting each still carries the `LaunchGuard:` shape, so the widening cannot quietly
// become a scan for a variable name (#650).

import Foundation
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

    // MARK: - #915: the self-healing net leaves a trail

    /// `unconfirmedCount` exists for the diag log and must stay a WITNESS, never a second
    /// verdict. Two properties, both driven: it follows the live counter (so it can say
    /// what `isSafeMode` cannot — how long the streak is), and it is decoupled from the
    /// frozen verdict in BOTH directions.
    func testTheStreakCountIsAWitnessAndNotASecondVerdict() {
        LaunchGuard.beginLaunch()
        XCTAssertEqual(LaunchGuard.unconfirmedCount, 1, """
            Read right after the first beginLaunch the streak must be 1 — which is exactly \
            what the log line means: the PREVIOUS run confirmed healthy.
            """)
        LaunchGuard.beginLaunch()
        XCTAssertEqual(LaunchGuard.unconfirmedCount, 2)
        XCTAssertTrue(LaunchGuard.isSafeMode)
        LaunchGuard.confirmHealthy()
        XCTAssertEqual(LaunchGuard.unconfirmedCount, 0, """
            It tracks the LIVE counter, so it drops to 0 the moment the launch is confirmed.
            """)
        XCTAssertTrue(LaunchGuard.isSafeMode, """
            …and the frozen verdict is untouched by it. If this ever flips, the Safe-Mode \
            screen would vanish under a user who is mid-read.
            """)
    }

    /// ⭐ THE ONE CLAIM HERE THAT READS THE APP. Every `LaunchGuard` state change must be
    /// legible in the exported `echoel_diag.log`, or a founder crash log cannot say which
    /// launch path the run took — and a Safe-Mode run executes a DIFFERENT tree, so a
    /// conclusion drawn from one about the normal path is simply wrong.
    ///
    /// ⛔ **THIS IS THE THIRD ATTEMPT AT THIS SHAPE IN THIS REPO, AND THE FIRST TWO ARE A
    /// RECORDED DEAD-END** (`HARNESS_LEDGER.md`: *"einen FENSTER-Scan bauen … ZWEIMAL
    /// versucht, zweimal verworfen"*). The two rejections failed in OPPOSITE directions and
    /// the difference is the whole design here:
    ///   · **#875** was rejected for FALSE REDS — a 260-character window called 4 of 5
    ///     correct sites unprotected, the #665 cry-wolf trap.
    ///   · **#909** was rejected for being BLIND — it passed on a driven `deinit` mutant.
    /// ⛔ The first draft of THIS claim cited #875 for the blindness, which is backwards, and
    /// then reproduced #909's failure anyway: it used a ±8-line window, and the Safe-Mode
    /// `.onAppear` reset — which had no `LaunchGuard:` line at all — passed because the
    /// walk-back reached over a closure brace into the NEIGHBOURING site's line. The review
    /// drove that mutant; the ledger had predicted it.
    ///
    /// ⭐ SO THERE IS NO WINDOW AND NO BOUND AT ALL — the rule is OWNERSHIP. A breadcrumb
    /// belongs to the call site it is CLOSEST to, and every site must own at least one, on
    /// its own side. Draft 2 tried "the territory between neighbouring calls" and TWO driven
    /// mutants still passed: these sites are hundreds of lines apart, so a neighbour's line
    /// falls inside the gap as easily as inside a window. Ownership has no constant to widen
    /// and no gap to fall through; one deleted line reds exactly one site.
    ///
    /// ⚠️ WHAT THIS STILL DOES NOT PROVE: that the line is ever WRITTEN at run time. No test
    /// here renders a scene.
    func testEveryLaunchGuardStateChangeIsAnnouncedInTheDiagLog() throws {
        // `SourceText.codeOnly` BLANKS comments and preserves the line count, so the numbers
        // in the messages below are the real ones. The first draft used a private stripper
        // that DELETED comment lines — every reported line number was 172–726 off, and a
        // trailing `// LaunchGuard:` comment satisfied the scan (#460's blind spot).
        let lines = SourceText.codeOnly(try appSource())
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let mutators = ["LaunchGuard.reset()",
                        "LaunchGuard.confirmHealthy()",
                        "LaunchGuard.armForRiskyStartup()"]
        let calls = lines.indices.filter { i in
            (mutators + ["LaunchGuard.beginLaunch()"]).contains { lines[i].contains($0) }
        }
        XCTAssertGreaterThanOrEqual(calls.count, 4, """
            Only \(calls.count) `LaunchGuard` call sites found in EchoelmusicApp.swift. \
            Below four this claim has stopped selecting the thing it names and reports GREEN \
            on less (#454) — re-anchor it, or record in this file's header why the \
            self-healing net no longer takes those steps. A COUNT is deliberately not pinned \
            here: it would go stale on ordinary work, which is how count pins rot (#903).
            """)

        // ⭐ NO WINDOW AND NO TERRITORY — OWNERSHIP. A breadcrumb belongs to the call site
        // it is CLOSEST to, and every site must own at least one, on its own side. The
        // territory form (the gap between neighbouring calls) was the second draft and two
        // driven mutants still passed on it: the sites here are hundreds of lines apart, so a
        // neighbour's line falls inside the gap just as easily as inside a window. Ownership
        // has no constant to widen and no gap to fall through.
        // ⛔ #955 BROKE THIS CLAIM AND #955b REPAIRED IT — the mirror of the failure this
        // file is otherwise about. The needle was the literal SHAPE `"LaunchGuard:` (the
        // opening quote is part of it), so when #955 replaced three breadcrumb literals in
        // `EchoelmusicApp.swift` with `EchoelCrashLog.confirmedHealthyMarker` /
        // `.recoveryScreenClearedMarker`, three call sites owned no crumb and this claim went
        // RED on CORRECT code (#364). What is widened is the VOCABULARY, not a bound: a named
        // constant IS a breadcrumb. The widening is anchored one block below — both constants
        // must still carry the `LaunchGuard:` shape, so this cannot quietly stop selecting the
        // property it exists for (#650: a renamed logged string leaves scans green for a dead
        // reason).
        let crumbNeedles = ["\"LaunchGuard:",
                            "EchoelCrashLog.confirmedHealthyMarker",
                            "EchoelCrashLog.recoveryScreenClearedMarker",
                            "EchoelCrashLog.rearmMarker"]
        let crumbs = lines.indices.filter { i in crumbNeedles.contains { lines[i].contains($0) } }

        // THE ANCHOR for the constant needles. Without it the scan would pass on the NAME
        // while the exported log had lost the marker entirely — green for a dead reason.
        // (⛔ The first draft of this line said "the two". #955b added the third in the same
        // commit; a count in prose is a date, not a fact — this file's own header carries the
        // identical retraction about "the five call sites".)
        for (name, marker) in [("confirmedHealthyMarker", EchoelCrashLog.confirmedHealthyMarker),
                               ("recoveryScreenClearedMarker",
                                EchoelCrashLog.recoveryScreenClearedMarker),
                               ("rearmMarker", EchoelCrashLog.rearmMarker)] {
            XCTAssertTrue(marker.hasPrefix("LaunchGuard:"), """
                `EchoelCrashLog.\(name)` is "\(marker)", which no longer starts with \
                `LaunchGuard:`. The scan above accepts that constant as a breadcrumb PRECISELY \
                because it writes a `LaunchGuard:` line into the exported log; once the shape \
                is gone, a reader of `echoel_diag.log` can no longer find the state change by \
                the same word, and this claim would be selecting a variable name instead of a \
                logged fact. Fix the constant, not this assertion.
                """)
        }
        func owner(of crumb: Int) -> Int {
            calls.min(by: { (abs($0 - crumb), $0) < (abs($1 - crumb), $1) }) ?? -1
        }
        for at in calls {
            // `beginLaunch` is the ONE site whose line must come AFTER the call, and that is
            // the rung law's own boundary rather than an exception to it: the fact being
            // logged (the verdict and the streak) DOES NOT EXIST until the call returns.
            let isBegin = lines[at].contains("LaunchGuard.beginLaunch()")
            let mine = crumbs.filter { owner(of: $0) == at && (isBegin ? $0 >= at : $0 <= at) }
            XCTAssertFalse(mine.isEmpty, """
                The `LaunchGuard` call at line \(at + 1) owns no `LaunchGuard:` breadcrumb \
                \(isBegin ? "after" : "before") it. Every state change the self-healing net \
                makes has to be readable back out of the exported log; a silent one leaves \
                the reader inferring it from an ABSENCE (#445/#579).

                \(isBegin
                  ? "beginLaunch announces AFTER: the verdict does not exist before the call."
                  : "A mutator announces BEFORE it acts (#859): a line written after a step is lost exactly when that step is the one that dies.")

                ⚠️ DO NOT WIDEN ANYTHING TO MAKE THIS PASS — there is deliberately no bound \
                to widen. Give the site its OWN line. Two earlier drafts (a ±8-line window, \
                then a between-neighbours territory) each let a site with no line of its own \
                pass on a neighbour's, which is the failure `HARNESS_LEDGER` predicts for \
                this whole family of scans.
                """)
        }
    }

    private func appSource() throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let text = try String(contentsOf: root
            .appendingPathComponent("Sources/Echoelmusic/EchoelmusicApp.swift"), encoding: .utf8)
        return text
    }
}
