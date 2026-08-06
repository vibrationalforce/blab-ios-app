// TheWristReadingIsNotUnderweightedTests.swift
// Echoel — #448. The guard over a constant that was never chosen: `BreathHold`'s ATTACK.
//
// WHAT WAS WRONG. `BreathHold` fades the influence of a held breath rate instead of stepping it
// (#434). The header of `BreathHold.swift` derives the SPLIT — grace = release = horizon/2,
// chained to `BioSource.freshnessWindow` so the term's influence expires exactly when the bus
// stops trusting the frame (#426's form). It derives the ATTACK nowhere. `up` simply reused
// `half` as its divisor, so re-acquisition climbed at the same rate the expiry falls at, for a
// source whose window has nothing to do with how fast a lane should be allowed to move.
//
// ⭐ THE COST IS THE WRIST, AND IT IS THE OPPOSITE OF WHAT THE SOURCE IS FOR. HealthKit/Watch
// declare a 90 s window, so the attack was 45 s: a reading arriving minutes after the last one
// spent its entire usable life climbing and then falling, touching full weight for one instant.
// Continuous mean over the 90 s life: exactly **1/2**. The source whose whole premise is "a
// reading from a minute ago is still your current rate" was the one the accident coupled hardest
// against. `.oura` (600 s) is worse and has no producer today.
//
// ⭐ THE FIX INVENTS NO NUMBER — it generalises what the LIVE path already does. Camera/BLE's
// 6 s window makes its accidental attack 3 s, which is three frames at the ~1 Hz apply rate the
// bus actually runs at (`BioApplyRateIsTheDedupedRateTests`), i.e. the shortest ramp that reads
// as a ramp rather than a step on a lane sampled at that rate. `BreathHold.maximumAttack = 3.0`
// caps the attack there for every source, expressed as `min(releaseSeconds, …)`.
//
// ⭐ THAT `min` FORM IS LOAD-BEARING TWICE, which is why this file asserts it directly rather
// than only asserting the wrist improvement:
//   · camera (3 s) and `.fallback` (2.5 s) come out BIT-IDENTICAL, so every assertion in
//     `TheGapClimbCannotChangeTheResumeTests` still measures what it measured;
//   · #444's theorem needs `elapsed > half >= attack` at every restart to conclude `up > 1`.
//     A bare constant larger than some source's release would silently break that proof, and
//     nothing in the neighbouring file would go red — it only drives the camera window.
//
// ⚠️ MEASURED, WITH THE GRID STATED. Weight sampled every 0.5 s across one full 90 s wrist life:
// mean **0.4972 → 0.7293**. The exact continuous means are grid-free and cleaner: **1/2 → 11/15**.
// Camera (6 s) and `.fallback` (5 s): max |Δ| exactly **0** at every sample. The number the
// `BreathHold` header carried before this slice — "mean weight 0.4712" — was quoted with no grid
// and no sampling of the old shape reproduces it; it is retracted there, for the same reason
// #443 and #430 each had to retract an unreproducible count.
//
// ⚠️ WHAT THIS CANNOT SHOW, and it is the same limit #433/#434 stated: nothing here proves any of
// it is heard or recorded. `RecordController.onStep` opens with `guard armed else { return }`,
// `arm()` has zero callers in `Sources/`, and #204 records the controller as doorless. The repair
// is worth making BECAUSE the path is dormant — the same arithmetic behind a door would need a
// device listen, not a test.
//
// ⚠️ AND WHICH OF THESE CAN FAIL ON THE OLD CODE, said out loud because a file where everything
// looks like a regression invites the wrong kind of trust: three can — the wrist mean, the
// window-independence of the attack, and the attack/release inequality (which the old code
// satisfies only with equality, so it is stated as `<` for the slow sources). The other three are
// counterweights and are green on both sides by design.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheWristReadingIsNotUnderweightedTests: XCTestCase {

    private let paced = 6.0
    private let wristWindow = BioSource.watch.freshnessWindow          // 90
    private let cameraWindow = BioSource.cameraPPG.freshnessWindow     // 6
    private let fallbackWindow = BioSource.fallback.freshnessWindow    // 5

    /// One measurement at t = 0 and nothing after it — the wrist case exactly: HealthKit
    /// publishes once per new reading, minutes apart, so every reading starts a fresh run from
    /// `resumeWeight == 0`. Returns the weight sampled on a STATED grid.
    private func lifeTrace(window: TimeInterval, step: TimeInterval = 0.5) -> [Double] {
        var hold = BreathHold()
        hold.observe(measured: paced, at: 0, usableFor: window)
        var out: [Double] = []
        var i = 0
        while Double(i) * step <= window + 1e-9 {
            out.append(hold.weight(at: Double(i) * step))
            i += 1
        }
        return out
    }

    // MARK: - The regression

    /// RED on the old code: the wrist mean was 0.4972 on this grid.
    func testAWristReadingSpendsMostOfItsLifeAtFullWeight() {
        let trace = lifeTrace(window: wristWindow)
        XCTAssertGreaterThan(trace.count, 150, """
            Only \(trace.count) samples cover the 90 s wrist life, so the mean below is measured \
            on too little of it to mean anything.
            """)
        let mean = trace.reduce(0, +) / Double(trace.count)

        // 0.70 sits well clear of both measured values (old 0.4972, new 0.7293) rather than
        // hugging either — a threshold picked to pass the code under test is the #404 mistake.
        XCTAssertGreaterThan(mean, 0.70, """
            A wrist breath reading counts at mean weight \(mean) across the 90 s the bus considers \
            it usable. That is the attack scaling with the freshness window again: a 90 s window \
            gives a 45 s climb, so the reading spends its whole life ramping and then fading and \
            touches full weight for one instant. The attack must be capped (BreathHold.maximumAttack), \
            not derived from the window — the window decides EXPIRY, never re-acquisition.
            """)
    }

    /// RED on the old code, where the attack WAS the release and therefore scaled 90 → 600.
    func testTheAttackDoesNotScaleWithTheWindow() {
        var wrist = BreathHold()
        wrist.observe(measured: paced, at: 0, usableFor: wristWindow)
        var oura = BreathHold()
        oura.observe(measured: paced, at: 0, usableFor: BioSource.oura.freshnessWindow)

        XCTAssertNotEqual(wrist.releaseSeconds, oura.releaseSeconds, accuracy: 1e-9, """
            The two sources no longer declare different freshness windows, so this test cannot \
            tell whether the attack scales with the window. Read that before the assertion below.
            """)
        XCTAssertEqual(wrist.attackSeconds, oura.attackSeconds, accuracy: 1e-12, """
            A 90 s source attacks over \(wrist.attackSeconds) s and a 600 s source over \
            \(oura.attackSeconds) s. Re-acquisition speed is a property of how fast the LANE may \
            move, not of how long the source stays fresh; letting it scale with the window is the \
            accident #448 removed.
            """)
        XCTAssertEqual(wrist.attackSeconds, BreathHold.maximumAttack, accuracy: 1e-12,
                       "A slow source should sit on the ceiling, not somewhere below it.")
    }

    /// The precondition #444's theorem rests on, asserted here because the neighbouring file
    /// only ever drives the camera window and would stay green if a later edit made the attack
    /// exceed the release for some slower source.
    func testTheAttackNeverExceedsTheRelease() {
        for window in [fallbackWindow, cameraWindow, wristWindow,
                       BioSource.oura.freshnessWindow, BreathHold.minimumHorizon, 0.1] {
            var hold = BreathHold()
            hold.observe(measured: paced, at: 0, usableFor: window)
            XCTAssertLessThanOrEqual(hold.attackSeconds, hold.releaseSeconds, """
                For a \(window) s window the attack (\(hold.attackSeconds) s) is longer than the \
                release (\(hold.releaseSeconds) s). #444 proved that `up > 1` at every restart \
                from `elapsed > half >= attack`; break that inequality and the proof — and the \
                sweep that backs it — silently stop applying.
                """)
        }
    }

    // MARK: - The counterweights (green on both sides, and that is their job)

    /// The live path must not move at all. Stated as an equality on the two accessors rather
    /// than as a trace comparison, because that is the property a later edit would break: drop
    /// `maximumAttack` below 2.5 and camera/BLE starts attacking faster than it fades.
    func testTheLivePathIsBitIdentical() {
        for window in [cameraWindow, fallbackWindow] {
            var hold = BreathHold()
            hold.observe(measured: paced, at: 0, usableFor: window)
            XCTAssertEqual(hold.attackSeconds, hold.releaseSeconds, accuracy: 1e-12, """
                The \(window) s window now attacks over \(hold.attackSeconds) s and fades over \
                \(hold.releaseSeconds) s. #448 is a CEILING on slow sources; the camera/BLE and \
                fallback traces are supposed to be untouched, and every assertion in \
                TheGapClimbCannotChangeTheResumeTests is measured on the camera window.
                """)
        }
    }

    /// A capped attack must not keep a rate alive past the point the bus trusts its frame —
    /// the one invariant the whole split exists for (#426's form).
    func testTheHeldRateStillRetiresExactlyAtTheHorizon() {
        let trace = lifeTrace(window: wristWindow)
        XCTAssertEqual(trace.last ?? -1, 0, accuracy: 1e-12, """
            At t = 90 s — the source's own freshness window — the held wrist rate still counts \
            \(trace.last ?? -1). A faster attack must not extend the life of the measurement; it \
            only changes how quickly a FRESH one takes effect.
            """)
        var hold = BreathHold()
        hold.observe(measured: paced, at: 0, usableFor: wristWindow)
        let wellPast = hold.weight(at: wristWindow * 2)
        XCTAssertEqual(wellPast, 0, accuracy: 1e-12,
                       "Weight at twice the horizon is \(wellPast), not 0.")
    }

    /// Re-acquisition must still resume from the weight already held — swept on the WRIST
    /// window, which `TheGapClimbCannotChangeTheResumeTests` explicitly lists as uncovered
    /// (it drives the camera window throughout). A shorter attack is exactly the kind of change
    /// that could reintroduce the #433 step on the re-acquisition edge.
    func testEveryResumePointIsContinuousOnAWristWindow() {
        var worst = 0.0
        var worstAt = 0.0
        var checked = 0

        var offset = 0.5
        while offset <= 120.0 + 1e-9 {
            var hold = BreathHold()
            hold.observe(measured: paced, at: 0, usableFor: wristWindow)
            let at = offset
            let before = hold.weight(at: at)
            hold.observe(measured: paced, at: at, usableFor: wristWindow)
            let after = hold.weight(at: at)
            let step = abs(after - before)
            if step > worst { worst = step; worstAt = offset }
            checked += 1
            offset += 0.5
        }

        XCTAssertGreaterThan(checked, 200, """
            Only \(checked) resume points were swept — the loop stopped early, so a green result \
            here says nothing about the population it claims to cover.
            """)
        XCTAssertEqual(worst, 0, accuracy: 1e-12, """
            Re-acquisition on a 90 s window stepped the weight by \(worst) at a gap of \(worstAt) s. \
            A returning measurement must resume from the weight already held; capping the attack \
            must not turn re-acquisition back into a snap.
            """)
    }
}
