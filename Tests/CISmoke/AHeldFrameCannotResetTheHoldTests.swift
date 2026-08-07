// AHeldFrameCannotResetTheHoldTests.swift
// Echoel — #447. The guard over a frame that carries NO measurement and used to be able to
// destroy the whole hold anyway.
//
// WHAT WAS WRONG. `BreathHold.observe` opened with two statements in this order:
//
//     if now < lastMeasuredAt { self = BreathHold() }      // the backwards-clock reset
//     guard let measured, measured.isFinite, … else { return }
//
// The reset therefore ran on EVERY frame, including the ones that carry no breath at all. And
// this app produces exactly such a frame on purpose, with a stamp that deliberately goes
// backwards: `CameraRPPGBioPublisher`'s pulse-HOLD republish carries `held.timestamp` ("do not
// re-stamp", its own comment) together with `breathRate: 0`. So a frame whose entire job is to
// say "nothing new happened" could wipe `rate`, `horizon`, `runStartedAt` and the weight.
//
// ⭐ THE TRIGGER IS NARROWER THAN "SOURCES INTERLEAVE", and naming it correctly is what makes
// this a one-statement move rather than a redesign. EVERY real measurement in this app stamps
// `CFAbsoluteTimeGetCurrent()` at RECEIPT — camera, BLE, demo and HealthKit alike (#98c2 is why
// the wrist path does too). Real measurements are therefore monotone ACROSS sources, and the
// hold republish is the one stamp in the system that intentionally moves backwards. With a
// single source it is harmless, because the frozen stamp EQUALS the last measurement and the
// reset needs a strict `<`. It takes a SECOND source to open the gap — and
// `healthBio.startIfAlreadyAuthorized` runs at app level, independent of the pulse pill's
// camera/BLE/sim choice, so a wrist frame can advance `lastMeasuredAt` past the frozen stamp at
// any time.
//
// ⚠️ MEASURED, because "it resets" understates it. Transcribed from the shipped source and
// driven with 1 Hz camera frames, one HealthKit frame, then hold republishes: the weight went
// 1.0 → **0.0 in a single lane sample** and stayed there, with `rate` and `horizon` wiped to 0.
// Nothing recovers until a new MEASURED frame arrives, and during a pulse dropout none does.
// That is the full step #434 built this type to remove, in the exact case it was built for,
// arriving through a guard written for a different problem.
//
// ⭐ WHY THE COUNTERWEIGHT IS HALF THE FILE. The reset is not junk — wall clock can move
// backwards under NTP, and without the reset `lastMeasuredAt` sits in the future and the
// `now > lastMeasuredAt` guard below it rejects EVERY later frame for ever: `rate` freezes on a
// rate nobody is breathing any more and `weight` keeps certifying it. That is the
// fabricated-number failure #433 removed, through the back door. So the fix must be a MOVE, and
// the file has to prove both halves — that a nil frame cannot fire it, and that a real
// backwards measurement still does and still un-latches the type.
//
// ⚠️ WHAT THIS DOES NOT COVER, stated rather than implied: two REAL measurements from different
// sources can still arrive out of stamp order through a publish race (both stamp receipt time,
// on different actors, microseconds apart). That case still resets, and it still should —
// nothing here can tell it from a clock step. Removing it needs per-source state
// (`BioEventPublisher`'s shape), which is a design decision about which hold wins, not a
// reordering. Task #447 keeps that half.
//
// ⚠️ AND THE LIMIT #433/#434/#444/#448 ALL STATE, INHERITED UNCHANGED: nothing here proves any
// of it is heard or recorded. `RecordController.onStep` opens with `guard armed else { return }`,
// `arm()` has zero callers in `Sources/`, and #204 records the controller as doorless. The
// repair is worth making BECAUSE the path is dormant — the same arithmetic behind a door would
// need a device listen, not a test.

import Foundation
import XCTest
@testable import Echoelmusic

final class AHeldFrameCannotResetTheHoldTests: XCTestCase {

    private let paced = 6.0
    private let cameraWindow = BioSource.cameraPPG.freshnessWindow
    private let wristWindow = BioSource.healthKit.freshnessWindow

    /// Six shipped-cadence camera frames, `t = 100 … 105`, which is enough for the climb to
    /// reach full weight (the attack is 3 s at this window).
    private func warmedCameraHold() -> BreathHold {
        var hold = BreathHold()
        for i in 0..<6 { hold.observe(measured: paced, at: 100 + Double(i), usableFor: cameraWindow) }
        return hold
    }

    // MARK: - The premise the scenario rests on

    /// The two windows must actually DIFFER, or every horizon assertion below proves less than
    /// it appears to. Asserted rather than assumed because both numbers live in another file.
    func testTheTwoLiveSourcesDeclareDifferentWindows() {
        XCTAssertNotEqual(cameraWindow, wristWindow,
                          "The scenario needs a second source with its own freshness window; if these ever converge, this file's horizon assertions stop discriminating.")
        XCTAssertGreaterThan(wristWindow, cameraWindow,
                             "The wrist window is the long one — that is what makes the wrist frame the one that widens the gap the frozen stamp then falls behind.")
    }

    // MARK: - The reddenable ones

    /// ⭐ THE INVARIANT, SWEPT RATHER THAN SAMPLED: a frame with NO measurement cannot change
    /// this type. Not "usually", not "when the stamp is newer" — never, for any stamp and any
    /// window. Swept because the pre-#447 order failed only on `now < lastMeasuredAt`, and a
    /// hand-picked stamp is exactly the thing a later refactor can walk around.
    ///
    /// `BreathHold` is `Equatable`, so the assertion is the whole value, not a chosen field.
    func testANonMeasurementCannotChangeTheHoldAtAnyStamp() {
        let windows: [TimeInterval] = [cameraWindow, wristWindow, BioSource.fallback.freshnessWindow]
        var checked = 0

        for window in windows {
            var offset = -20.0
            while offset <= 20.0 + 1e-9 {
                var hold = warmedCameraHold()
                let before = hold
                hold.observe(measured: nil, at: 105 + offset, usableFor: window)
                XCTAssertEqual(hold, before,
                               "A frame with no breath measurement changed the hold at stamp offset \(offset) with window \(window). Before #447 the backwards-clock reset ran before the measurement guard, so any offset < 0 wiped the type — including the camera's own pulse-hold republish, which freezes its stamp on purpose.")
                checked += 1
                offset += 0.25
            }
        }

        XCTAssertEqual(checked, 3 * 161, "sweep coverage changed — re-read the assertion before trusting it")
    }

    /// The concrete measured scenario, with the numbers from the file header: camera warms the
    /// hold to full weight, ONE wrist frame lands and advances the stamp, then the camera's
    /// pulse-hold republish arrives carrying the older frozen stamp and no breath.
    ///
    /// ⛔ THE FIRST DRAFT SAID "Pre-#447 every assertion here reads 0" AND THAT WAS AN
    /// OVERSTATEMENT of exactly the kind this repo keeps retracting — the reviewer found it. The
    /// first four assertions run BEFORE the hold republish and pass on the old order too; they
    /// are the PREMISE, not the finding. Only the four after the republish read 0 pre-#447. The
    /// distinction is not cosmetic: it is the line a later session reads to decide whether this
    /// test is load-bearing, and "every assertion" would let it delete the republish and still
    /// believe it was testing something.
    func testTheWristFrameDoesNotArmTheHoldRepublishToWipeEverything() {
        var hold = warmedCameraHold()
        XCTAssertEqual(hold.weight(at: 105), 1, accuracy: 1e-12,
                       "premise: six 1 Hz frames bring the climb to full weight")

        // A wrist reading lands half a second later. It is a real measurement, so it advances
        // `lastMeasuredAt` past the camera's last stamp and brings its own 90 s horizon.
        hold.observe(measured: 12, at: 105.5, usableFor: wristWindow)
        XCTAssertEqual(hold.rate, 12, accuracy: 1e-12)
        XCTAssertEqual(hold.horizon, wristWindow, accuracy: 1e-12)
        XCTAssertEqual(hold.weight(at: 105.5), 1, accuracy: 1e-12)

        // Now the camera's pulse-hold republish: frozen stamp (105.0, older than 105.5) and no
        // breath at all. It must be a no-op.
        hold.observe(measured: nil, at: 105.0, usableFor: cameraWindow)

        XCTAssertEqual(hold.rate, 12, accuracy: 1e-12,
                       "the last MEASURED rate must survive a frame that measured nothing")
        XCTAssertEqual(hold.horizon, wristWindow, accuracy: 1e-12,
                       "the horizon belongs to the last measurement's source, and no measurement happened")
        XCTAssertEqual(hold.weight(at: 105.5), 1, accuracy: 1e-12,
                       "pre-#447 this read 0 — the full 1.0 → 0.0 step in one lane sample, in the exact case #434 exists to remove")
        XCTAssertEqual(hold.weight(at: 106.5), 1, accuracy: 1e-12,
                       "and it stayed at 0, because only a MEASURED frame can rebuild the state the republish destroyed")
    }

    /// A whole dropout, sampled the way the lane would sample it. The point is the SHAPE: with
    /// the wrist frame's 90 s horizon the weight should still be 1 across the next few seconds,
    /// not a cliff.
    func testARunOfHoldRepublishesLeavesNoStepAtAll() {
        var hold = warmedCameraHold()
        hold.observe(measured: 12, at: 105.5, usableFor: wristWindow)

        var previous = hold.weight(at: 105.5)
        var worstStep = 0.0
        var t = 106.0
        while t <= 115.0 + 1e-9 {
            // Every one of these is the camera republishing its frozen stamp with no breath.
            hold.observe(measured: nil, at: 105.0, usableFor: cameraWindow)
            let now = hold.weight(at: t)
            worstStep = Swift.max(worstStep, abs(now - previous))
            previous = now
            t += 0.5
        }

        XCTAssertEqual(worstStep, 0, accuracy: 1e-12,
                       "inside the wrist frame's grace window a dropout must move the weight by nothing; pre-#447 the first republish alone stepped it by the full 1.0")
        XCTAssertEqual(previous, 1, accuracy: 1e-12)
    }

    // MARK: - The counterweight: the reset must still exist and still work

    /// A REAL measurement with a backwards stamp is the case the reset was written for, and it
    /// must still fire. Without it, `now > lastMeasuredAt` rejects everything after the clock
    /// step and the type latches on a rate nobody is breathing — #433's fabricated number,
    /// through the back door.
    ///
    /// The load-bearing assertion is the LAST one: a later frame is still accepted. Under a
    /// hypothetical no-reset version `lastMeasuredAt` would still be 105, so a frame at 91
    /// would be rejected for ever and `rate` would stay 6.
    func testARealBackwardsMeasurementStillResetsAndUnlatches() {
        var hold = warmedCameraHold()
        XCTAssertEqual(hold.rate, paced, accuracy: 1e-12)

        // Wall clock jumps back 15 s and a real measurement arrives on the new clock.
        hold.observe(measured: 7, at: 90, usableFor: cameraWindow)

        XCTAssertEqual(hold.rate, 7, accuracy: 1e-12,
                       "the measurement on the corrected clock must be adopted, not rejected as stale")
        XCTAssertEqual(hold.weight(at: 90), 0, accuracy: 1e-12,
                       "the reset costs the hold — one fade, the honest price stated in the source")
        XCTAssertEqual(hold.weight(at: 93), 1, accuracy: 1e-12,
                       "and the climb restarts from there rather than staying dead")

        // The un-latching half: the clock is now running forward from 90, and frames on it work.
        hold.observe(measured: 8, at: 91, usableFor: cameraWindow)
        XCTAssertEqual(hold.rate, 8, accuracy: 1e-12,
                       "without the reset `lastMeasuredAt` would still be 105 and this frame — and every later one — would be rejected for ever")
    }

    /// The single-source case is unchanged by #447 and must stay that way: the camera's own
    /// republish carries a stamp EQUAL to the last measurement, and the reset needs a strict
    /// `<`. Both orders are inert here. This is the assertion that keeps a future "simplify"
    /// from giving a nil frame any power at all.
    func testAFrozenStampEqualToTheLastMeasurementWasAlwaysInert() {
        var hold = warmedCameraHold()
        let before = hold
        hold.observe(measured: nil, at: 105, usableFor: cameraWindow)
        XCTAssertEqual(hold, before)

        // And a nil frame with a FORWARD stamp is inert too — it always was, and it must not
        // become a way to advance the age of a measurement that never happened.
        hold.observe(measured: nil, at: 200, usableFor: cameraWindow)
        XCTAssertEqual(hold, before)
    }
}
