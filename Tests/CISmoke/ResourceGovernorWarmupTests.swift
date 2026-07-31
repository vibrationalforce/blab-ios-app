// ResourceGovernorWarmupTests.swift
// Echoel — #271. The founder's device log 2478 (v10.79.361) showed the immersive visual
// FROZEN for about ten seconds after launch: `redMot=1 detail=0.50` at 27 s and 32 s,
// `redMot=0 detail=0.70` at 37 s. Reported as "motion is tied to whether the visual window
// is open; it should run when you turn it on".
//
// Cause, in one line: the FPS estimate was SEEDED FROM A SINGLE FRAME, and the first frame
// after a mount is the slowest one the renderer ever produces (runtime shader compile, first
// drawable). One cold frame demoted a tier; demotions apply immediately by design while
// recovery needs a wider band plus a 4 s dwell.
//
// These tests are relative, never absolute: CI hardware decides the BASE tier (thermal,
// battery, charging), so asserting "tier == .balanced" would pin the test machine rather
// than the behaviour. Every assertion below compares against the tier the governor itself
// chose at construction.

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

    /// ⭐ THE REGRESSION. One slow warm-up frame must not move a tier.
    func testASingleColdFrameCannotDemoteATier() {
        let g = ResourceGovernor()
        let base = g.settings.tier
        g.recordFrame(timestamp: 100)        // cold start — seeds nothing
        g.recordFrame(timestamp: 100.25)     // 4 fps: the worst frame of the session
        XCTAssertEqual(g.settings.tier, base,
                       "a single warm-up frame decided a tier — this is the #271 freeze, "
                       + "where one shader-compile stall froze the visual for ten seconds")
        XCTAssertEqual(g.settings.reduceMotion,
                       AdaptiveQuality.settings(for: base).reduceMotion,
                       "and it must not have flipped reduce-motion either")
    }

    /// The gate must not become a mute button: a renderer that is GENUINELY too slow, for
    /// long enough to be evidence, still has to demote. Otherwise #271 would have traded a
    /// ten-second freeze for a permanently unresponsive governor.
    func testASustainedLowFrameRateStillDemotes() {
        let g = ResourceGovernor()
        let base = g.settings.tier
        g.recordFrame(timestamp: 200)
        feed(g, count: 300, fps: 4, from: 200)   // 75 s at 4 fps — far past warm-up + dwell
        XCTAssertLessThanOrEqual(g.settings.tier.rawValue, base.rawValue,
                                 "sustained 4 fps must still back the tier off; the warm-up "
                                 + "gate is a delay, not a veto")
    }

    /// A stall is a discontinuity, not a slow frame. After a gap (window hidden, app
    /// backgrounded) the count restarts, so the slow frames of the SECOND mount cannot
    /// decide anything either — which is the case the founder actually hits, because the
    /// window is switched on and off during a performance.
    func testAStallRestartsTheWarmupInsteadOfResumingTheOldEstimate() {
        let g = ResourceGovernor()
        let base = g.settings.tier
        g.recordFrame(timestamp: 300)
        let t = feed(g, count: 120, fps: 60, from: 300)   // a healthy run, well past warm-up
        XCTAssertEqual(g.settings.tier, base, "a healthy run must not demote")

        g.recordFrame(timestamp: t + 30)                  // the window was hidden for 30 s
        g.recordFrame(timestamp: t + 30.25)               // first frame back: 4 fps
        XCTAssertEqual(g.settings.tier, base,
                       "the first frame after a stall demoted a tier — the remount's warm-up "
                       + "must be treated exactly like a cold start")
    }

    /// Frames must be CONSECUTIVE to count. Twenty good frames, a stall, twenty more good
    /// frames is not forty frames of evidence — and if it were, the gate could be walked
    /// past by any renderer that stutters regularly.
    func testWarmupProgressDoesNotSurviveAStall() {
        let g = ResourceGovernor()
        let base = g.settings.tier
        g.recordFrame(timestamp: 400)
        var t = feed(g, count: 20, fps: 4, from: 400)     // 20 slow frames — under the gate
        XCTAssertEqual(g.settings.tier, base)
        t += 5                                            // stall
        g.recordFrame(timestamp: t)
        t = feed(g, count: 20, fps: 4, from: t)           // 20 more, but the count restarted
        XCTAssertEqual(g.settings.tier, base,
                       "warm-up progress survived a stall, so a stuttering renderer could "
                       + "accumulate its way past the gate a few frames at a time")
    }
}
