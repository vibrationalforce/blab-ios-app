//
//  LaunchGuard.swift
//  Echoelmusic — Core
//
//  Self-healing crash-loop guard. The app must NEVER trap the user at a black
//  screen again: if a launch crashes before the UI reaches a healthy steady
//  state, the *next* launch boots into a minimal Safe Mode (a plain recovery
//  screen with the diagnostics + a one-tap "continue normally") instead of
//  re-rendering the view tree that just crashed.
//
//  The whole decision is pure `UserDefaults` integer bookkeeping — no SwiftUI,
//  no allocation games, no risky types — so the guard itself can never be the
//  thing that crashes. Mechanism:
//
//    • `beginLaunch()`  (called first thing in app init) increments a persisted
//      "unconfirmed launches" counter and flushes it synchronously.
//    • `confirmHealthy()` (called a few seconds after the main UI appears) resets
//      the counter to 0 — proof this launch rendered and survived.
//    • A launch that crashes before `confirmHealthy()` leaves the counter raised,
//      so the next `beginLaunch()` pushes it past the threshold → Safe Mode.
//

import Foundation

/// Pure-`UserDefaults` crash-loop detector. `@MainActor` because it is only ever
/// touched from the app's main-actor launch path; no cross-thread access.
@MainActor
enum LaunchGuard {

    /// Number of consecutive launches NOT yet confirmed healthy. ≥ `safeModeThreshold`
    /// after `beginLaunch()` means the previous run(s) crashed before becoming healthy.
    private static let countKey = "launch.unconfirmedCount"

    /// Enter Safe Mode once this many launches in a row have failed to confirm
    /// healthy. 2 = after a single crash the very next launch is protected, so the
    /// user never sees a second black screen. Safe Mode is trivially exitable.
    private static let safeModeThreshold = 2

    /// Decided ONCE per process in `beginLaunch()` and cached, so reading it later
    /// (after the counter has been reset by `confirmHealthy()`) stays stable.
    private static var cachedSafeMode = false

    /// Record that a launch has started. Increments the unconfirmed-launch counter,
    /// flushes it to disk immediately (a crash moments later must not lose it), and
    /// freezes the Safe-Mode decision for this process. Call FIRST in app init.
    static func beginLaunch() {
        let d = UserDefaults.standard
        let next = d.integer(forKey: countKey) + 1
        d.set(next, forKey: countKey)
        // Force a synchronous write — the launch we are guarding against may crash
        // milliseconds from now, before the normal periodic flush.
        d.synchronize()
        cachedSafeMode = next >= safeModeThreshold
    }

    /// Whether this launch should boot into Safe Mode (frozen at `beginLaunch()`).
    static var isSafeMode: Bool { cachedSafeMode }

    /// Mark the app healthy: the main UI rendered and survived. Resets the counter
    /// so the *next* launch starts clean. Call a few seconds after the root view
    /// appears (a crash during initial render fires before this, leaving the count
    /// raised — exactly what escalates to Safe Mode).
    static func confirmHealthy() {
        let d = UserDefaults.standard
        guard d.integer(forKey: countKey) != 0 else { return }
        d.set(0, forKey: countKey)
        d.synchronize()
    }

    /// Re-arm the counter for a risky startup that a UI-reached confirmation already
    /// cleared. A no-op on a normal launch, where the counter is already ≥ 1.
    ///
    /// This exists because of an asymmetry review found in #214. Confirming healthy when
    /// the ONBOARDING screen renders is right — the launch reached a UI, which is what
    /// the counter measures — but onboarding differs from the Safe-Mode screen in one
    /// decisive way: `mainContent` still runs afterwards, in the SAME process, and its
    /// startup (graph build · voice attach · engine start) is exactly what the guard was
    /// written for. Without re-arming, a crash there would be uncounted, and the launch
    /// that loses the protection is the worst one to lose it on: the first-ever full
    /// startup on a fresh install — cold caches, first permission prompts, the profile of
    /// the build-1363 crash itself.
    ///
    /// Deliberately does NOT touch `cachedSafeMode`: this launch keeps the verdict it was
    /// given, so the screen cannot change under a user mid-session.
    static func armForRiskyStartup() {
        let d = UserDefaults.standard
        guard d.integer(forKey: countKey) == 0 else { return }
        d.set(1, forKey: countKey)
        d.synchronize()
    }

    /// User chose to leave Safe Mode and try the full app again — clear the counter
    /// so we don't immediately re-enter it. (The cached `isSafeMode` for this
    /// process is unaffected; the caller flips its own state to render normally.)
    static func reset() {
        let d = UserDefaults.standard
        d.set(0, forKey: countKey)
        d.synchronize()
    }

    #if DEBUG
    /// TEST ONLY — also clears the frozen per-process verdict. Never call from product
    /// code: `reset()` deliberately leaves `cachedSafeMode` alone so the Safe-Mode screen
    /// does not vanish under the user who is reading it.
    ///
    /// Tests need the stronger form because `cachedSafeMode` is process-global and the
    /// blocking test bundle runs INSIDE the host app (`TEST_HOST`). A test that leaves it
    /// `true` flips the live app to `SafeModeView` on the next body evaluation, tearing
    /// down `WorkspaceView` and cancelling its startup task. Harmless while no test
    /// observes the view tree — a trap for the next one that does.
    static func resetForTesting() {
        reset()
        cachedSafeMode = false
    }
    #endif
}
