// ResourceGovernorWarmupTests.swift
// Echoel — #271. The founder's device log 2478 (v10.79.361) showed the immersive visual
// frozen after launch: `redMot=1 detail=0.50` at 27 s and 32 s, `redMot=0 detail=0.70` at
// 37 s. Reported as "motion is tied to whether the visual window is open; it should run
// when you turn it on". Cause: the FPS estimate was SEEDED FROM A SINGLE MEASURED INTERVAL,
// and the first interval of the app's life spans the forced first-drawable allocation. One
// cold frame demoted a tier; demotions apply immediately by design while recovery needs a
// wider band plus a 4 s dwell.
//
// ⛔ THE FIRST VERSION OF THIS FILE ASSERTED ON `settings.tier`, AND ALL FOUR TESTS PASSED
// AGAINST THE UNFIXED SOURCE. Found in review. The reason is worth keeping, because it
// disqualifies the obvious assertion for any future test here:
//
//   `init()` leaves `settings` at its `.balanced` literal while the pressure tier on CI
//   hardware is `.high` — `recompute()` takes the promotion branch and RETURNS before
//   `apply` (a promotion must dwell 6 s). A one-tier FPS demotion from `.high` therefore
//   computes `.balanced`, which is what `settings.tier` already is, and `apply`'s
//   `guard next != settings` swallows it. The tier is literally unobservable in that
//   state, so "the tier did not move" is true with or without the mechanism.
//
// These tests assert on `trustedFPS` instead: the number the tier decision is actually
// allowed to see. `0` means "no trustworthy reading", which is the state the whole slice
// exists to produce. That is observable on any hardware and cannot pass vacuously.

import XCTest
@testable import Echoelmusic

@MainActor
final class ResourceGovernorWarmupTests: XCTestCase {

    /// Feed `count` frames at `fps` starting after `t0`; returns the last timestamp.
    @discardableResult
    private func feed(_ g: ResourceGovernor, count: Int, fps: Double,
                      from t0: CFTimeInterval) -> CFTimeInterval {
        var t = t0
        let dt = 1.0 / fps
        for _ in 0..<count { t += dt; g.recordFrame(timestamp: t) }
        return t
    }

    /// ⭐ THE REGRESSION. One slow warm-up frame must not become the reading a tier
    /// decision sees. Pre-fix this set the estimate to 4 fps outright.
    func testASingleColdFrameIsNotYetAReading() {
        let g = ResourceGovernor()
        g.recordFrame(timestamp: 100)        // cold start — no interval yet
        g.recordFrame(timestamp: 100.25)     // 4 fps: the worst interval of the session
        XCTAssertEqual(g.trustedFPS, 0,
                       "one warm-up interval became the FPS reading — this is the #271 "
                       + "freeze, where a single first-drawable stall demoted the tier and "
                       + "froze the visual until the recovery band plus its 4 s dwell")
    }

    /// And the cold interval must not dominate the FIRST reading either. Averaging the
    /// warm-up window (rather than EMA-seeding from frame one) caps its weight at 1/30:
    /// one 4 fps interval among 29 at 60 fps must still read as a healthy renderer.
    func testTheColdFrameIsDilutedNotJustDelayed() {
        let g = ResourceGovernor()
        g.recordFrame(timestamp: 200)
        g.recordFrame(timestamp: 200.25)                  // the cold one, 4 fps
        feed(g, count: 29, fps: 60, from: 200.25)         // 29 healthy ones
        XCTAssertGreaterThan(g.trustedFPS, 45,
                             "the cold interval still dominates the first reading "
                             + "(\(g.trustedFPS) fps) — 45 is the demotion floor for a "
                             + "60 fps target, so this is the freeze again, one gate later")
    }

    /// The gate must not become a mute button: a renderer that is GENUINELY too slow, for
    /// long enough to be evidence, still has to produce a reading. Otherwise #271 would
    /// have traded a short freeze for a permanently deaf governor.
    func testASustainedLowFrameRateStillProducesAReading() {
        let g = ResourceGovernor()
        g.recordFrame(timestamp: 300)
        feed(g, count: 300, fps: 4, from: 300)   // 75 s at 4 fps
        XCTAssertEqual(g.trustedFPS, 4, accuracy: 0.5,
                       "sustained 4 fps produced \(g.trustedFPS) — the warm-up gate is a "
                       + "delay, not a veto, and a device this slow must be able to demote")
    }

    /// ⭐ THE REGRESSION THE FIRST FIX INTRODUCED, caught in review before it shipped to a
    /// device. That version called `beginWarmup` on every gap ≥ 1 s, which zeroed the frame
    /// counter. A renderer that stalls MORE OFTEN than once per 30 measured frames then
    /// never completes the gate and is silenced forever — on exactly the struggling device
    /// the feedback exists for. The pre-#271 code demoted here; the "fix" would not have.
    func testARegularlyStutteringRendererStillReachesAReading() {
        let g = ResourceGovernor()
        var t: CFTimeInterval = 400
        g.recordFrame(timestamp: t)
        for _ in 0..<10 {                        // 200 slow frames, a 1.2 s stall every 20
            t = feed(g, count: 20, fps: 4, from: t)
            t += 1.2
            g.recordFrame(timestamp: t)          // the stall's own sample is unmeasurable
        }
        XCTAssertGreaterThan(g.trustedFPS, 0,
                            "a renderer that stalls every 20 frames never earned a reading "
                            + "— the stall reset the warm-up counter faster than the "
                            + "renderer could fill it, so the governor went permanently deaf")
        XCTAssertEqual(g.trustedFPS, 4, accuracy: 1,
                       "…and the reading it earned must describe the 4 fps it is actually "
                       + "delivering, not the stalls that were correctly discarded")
    }

    /// A gap is discarded, not measured: it must never enter the estimate as a ~0.8 fps
    /// sample. A healthy renderer that is hidden for 30 s and comes back must still read
    /// as healthy.
    func testAStallIsDiscardedRatherThanCountedAsASlowFrame() {
        let g = ResourceGovernor()
        g.recordFrame(timestamp: 500)
        var t = feed(g, count: 120, fps: 60, from: 500)
        XCTAssertEqual(g.trustedFPS, 60, accuracy: 1, "a healthy run must read as healthy")

        t += 30                                  // the window was hidden for 30 s
        g.recordFrame(timestamp: t)
        XCTAssertEqual(g.trustedFPS, 60, accuracy: 1,
                       "the 30 s gap was folded into the estimate as a slow frame; a hidden "
                       + "window would then demote the tier the moment it came back")
    }
}
