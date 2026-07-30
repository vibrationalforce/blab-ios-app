// ArpPushRowTests.swift
// Echoel — #258 (A2c): the arp's "Laid back" row and its persisted key. BLOCKING bundle, because
// the other suite cannot fail a merge (#208).
//
// WHAT THIS FILE IS FOR. The row's range is HALF the model's — 0…`RoleRhythm.maxPush`, while
// `RoleRhythm.Params.push` is bipolar −0.45…0.45. That asymmetry looks like an oversight to anyone
// who reads only one of the two files, and "fixing" it would re-create the exact defect it avoids:
// `FieldAutoPlay.pushDelaySeconds` folds every value ≤ 0 to "on the grid" (the consumer delays an
// onset with a sleep, and a note that should have sounded EARLIER cannot be delayed into
// existence), so the negative half would be a dial whose entire left side does nothing — the
// #164/#227 lying control. These tests pin the FOLD, so the day someone widens the row without
// building look-ahead, the reason the range was narrow is still enforced by something that runs.
//
// ⚠️ WHAT IT CANNOT REACH. The row itself lives in `EchoelStudioView.fieldArpRhythmFields`, which
// is `private` inside a view — no test in this bundle can instantiate or read it. So nothing here
// proves the row EXISTS or that its `range:` argument is the one below; that pairing is held by
// the source and by review only. What IS testable is the contract the row was built against: the
// key, its default, and the fold that decides the range. Stated so the coverage is not overread —
// the same honesty `RoleRhythm`'s own header applies to `shouldPublish` ("the predicate is pinned;
// the wiring is not").

import Foundation
import XCTest
@testable import Echoelmusic

final class ArpPushRowTests: XCTestCase {

    // MARK: - What a fresh install hears

    /// ⚠️ THE KEY AND ITS DEFAULT ARE NOT PINNED HERE, ON PURPOSE. `TouchSurfaceStorageKeysTests`
    /// already owns every `StudioDefaultKeys` claim for this surface, and #258 extended it there
    /// (`fieldArpRhythmPush.key` + `value == FieldAutoPlay.Params().arpRhythm.push`). A first draft
    /// of this file duplicated both — two files claiming the same thing is how a claim gets
    /// corrected in one place and left stale in the other.
    ///
    /// What IS this file's own is the claim about the SOUND rather than the storage: the shipped
    /// arp is ON THE GRID, so the row adds nothing until a player asks for it. The character's own
    /// bias (`syncopated` +0.12 off the beat, `flowing` +0.05) stays the whole of what a new
    /// install hears, exactly as before the row existed — which is what makes #258 a reachability
    /// slice and not a re-voicing.
    func testTheShippedArpAddsNoPushOfItsOwn() {
        let shipped = FieldAutoPlay.Params().arpRhythm
        XCTAssertEqual(FieldAutoPlay.pushDelaySeconds(shipped.push, cellSeconds: 0.125), 0,
                       "the arp now lands late on a fresh install. Whether that is an improvement "
                       + "is a founder call, but it is a change to what every existing user hears "
                       + "on update — it may not arrive as a side effect of the row that exposes it.")
    }

    // MARK: - The fold that decides the range

    /// ⛔ THE REASON THE ROW STOPS AT 0. Everything at or below zero produces NO delay, so the
    /// negative half of the model's range is unreachable through this consumer. Asserted across the
    /// whole negative span rather than at one point, because a future `pushDelaySeconds` that
    /// handled negatives by *shortening* a delay would pass a single-point check at exactly 0.
    ///
    /// ⚠️ EXPLICIT VALUES, NOT `stride` — the first version of this test walked
    /// `stride(from: Float(-0.45), through: 0, by: 0.05)`, and Float accumulation lands the last
    /// step near 1.5e-8 rather than on 0. That is `> 0`, so it produces a real delay and the test
    /// would have failed for a reason that has nothing to do with the property it names. Same trap
    /// in the sibling test below.
    func testEveryNonPositivePushLandsOnTheGrid() {
        let cell = 0.125                      // one 1/16 at 120 BPM
        let nonPositive: [Float] = [-0.45, -0.4, -0.3, -0.2, -0.12, -0.05, -0.001, 0]
        for push in nonPositive {
            XCTAssertEqual(FieldAutoPlay.pushDelaySeconds(push, cellSeconds: cell), 0,
                           "push \(push) produced a delay. Nothing may: the consumer schedules an "
                           + "onset LATE, so 'earlier than the grid' is not expressible without "
                           + "look-ahead. If that changes, the row's 0…maxPush range in "
                           + "EchoelStudioView must widen in the SAME commit — otherwise the "
                           + "engine gains an ability no control can reach.")
        }
    }

    /// And the positive half must actually do something across the row's whole span, or the dial
    /// the player now sees is decoration. Monotone, because a range that is flat anywhere reads as
    /// a broken control even when the endpoints differ.
    ///
    /// ⚠️ THIS IS THE FOLD ONLY — IT IS NOT A CLAIM THAT THE ROW IS MONOTONE END TO END. Between
    /// the row and this function sits `RoleRhythm.hit`, which ADDS the character's `pushBias` and
    /// clamps the sum at `maxPush`: on `flowing` (+0.05 everywhere) the total saturates from about
    /// 0.40, on `syncopated` (+0.12 off the beat) from about 0.33 on those cells. So the row DOES
    /// have a flat top on two of six characters — stated in the panel's caveat rather than hidden,
    /// and stated here because the failure message below reads as a general promise it cannot make.
    func testTheRowsWholeRangeProducesAStrictlyGrowingDelay() {
        let cell = 0.125
        var previous = FieldAutoPlay.pushDelaySeconds(0, cellSeconds: cell)
        // Ends on `maxPush` itself rather than a literal 0.45, so the last step is the SAME Float
        // the view's range ends on — a stride would drift off it (see the note above).
        let rising: [Float] = [0.05, 0.1, 0.2, 0.3, 0.4, RoleRhythm.maxPush]
        for push in rising {
            let delay = FieldAutoPlay.pushDelaySeconds(push, cellSeconds: cell)
            XCTAssertGreaterThan(delay, previous,
                                 "push \(push) did not land later than the value below it "
                                 + "(\(delay) s vs \(previous) s). The FOLD itself must stay strictly "
                                 + "monotone — the character's own lean can flatten the top for two "
                                 + "characters (see the doc above), but a flat stretch in this "
                                 + "function would flatten the row for all six.")
            previous = delay
        }
        XCTAssertEqual(previous, Double(RoleRhythm.maxPush) * cell, accuracy: 1e-9,
                       "the row's top end no longer delays by maxPush of a cell — the range in "
                       + "the view and the ceiling in the generator have drifted apart")
    }

    /// ⛔ THE ROW MAY NEVER OUTRUN THE ENGINE. `EchoelStudioView` writes `range: 0...maxPush`, so a
    /// value from the row is always within what `pushDelaySeconds` will honour un-clamped. Pinned
    /// because the two live in different files: if `maxPush` shrank, a stored setting from an older
    /// build would silently be capped, and the number the player sees would stop matching the
    /// timing they hear.
    func testTheRowsCeilingIsExactlyTheEnginesCeiling() {
        let cell = 0.125
        let atCeiling = FieldAutoPlay.pushDelaySeconds(RoleRhythm.maxPush, cellSeconds: cell)
        let overCeiling = FieldAutoPlay.pushDelaySeconds(RoleRhythm.maxPush + 0.2, cellSeconds: cell)
        XCTAssertEqual(atCeiling, overCeiling, accuracy: 1e-9,
                       "a push ABOVE maxPush now produces a longer delay than maxPush itself, so "
                       + "the row's ceiling is no longer the engine's. Either the row is now too "
                       + "narrow to reach what the engine allows, or a stored value above it can "
                       + "push a note past its own cell.")
        // ⚠️ NOT asserting `FieldAutoPlay.maxPushFraction == RoleRhythm.maxPush` here — but the
        // reason is DUPLICATION, not futility, and the first version of this note got that wrong.
        // It said the assertion "could never fail". It can: `maxPushFraction` is declared as a
        // MIRROR (`{ RoleRhythm.maxPush }`), and the edit worth catching is someone replacing that
        // mirror with a literal. `FieldAutoPlayPushTests.testTheCeilingIsTheRhythmsOwnCeilingAndNot`
        // `ASecondNumber` already guards exactly that, in this same blocking bundle, and says so in
        // its own doc — two files giving opposite verdicts on one assertion is worse than either
        // verdict. The risk THIS file is closest to (the view's `range:` vs the engine's clamp) is
        // not reachable from a test at all; the argument is private to the view.
    }

    // MARK: - The stored value's own guard

    /// A hand-edited or corrupt preference must not reach the generator as a negative or a
    /// non-finite number. `FloatingVisualWindow` clamps to 0…maxPush on the way in; this pins the
    /// behaviour that clamp relies on rather than the clamp itself (which lives in a view).
    func testANonFiniteStoredPushIsTreatedAsOnTheGrid() {
        let cell = 0.125
        for bad: Float in [.nan, .infinity, -.infinity] {
            XCTAssertEqual(FieldAutoPlay.pushDelaySeconds(bad, cellSeconds: cell), 0,
                           "a non-finite stored push (\(bad)) produced a delay — a corrupt "
                           + "preference would then schedule an onset at an arbitrary time, or "
                           + "trap converting it")
        }
        XCTAssertEqual(FieldAutoPlay.pushDelaySeconds(0.3, cellSeconds: 0), 0,
                       "a zero-length cell produced a delay — at a degenerate grid the generator "
                       + "must fall back to the grid, not divide into it")
    }
}
