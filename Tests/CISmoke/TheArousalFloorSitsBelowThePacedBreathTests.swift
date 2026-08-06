//
//  TheArousalFloorSitsBelowThePacedBreathTests.swift
//  Echoelmusic — CISmoke (blocking bundle)
//
//  #433. The guard over `bioNormalized` (Sequencer/RecordAnchor.swift), which turns a live bio
//  frame into the 0…1 value the bio automation lane records.
//
//  WHAT WAS WRONG. Its breath window was `6.0...24.0`. `BreathPacer.defaultRate` is EXACTLY 6.0
//  and the pacer's whole range is 5…12, so a user following Echoel's own resonance guide sat on
//  the floor: the breath term read exactly 0 at the paced target and had no travel at all across
//  the coached band's slow half. Separately, `EngineBus.usableBio()` gates on FRESHNESS only —
//  a BLE-strap frame arrives with `breathRate: 0`, and that fabricated zero was blended in as
//  calm, halving the arousal value (the #215 argument, one path over).
//
//  ⚠️ WHAT THIS FILE CANNOT DO, stated first because the reviewer report that started #433 got
//  it wrong in the other direction: it cannot show that any of this is AUDIBLE or RECORDED
//  today. The path is dormant — `RecordController.onStep` opens with `guard armed else
//  { return }`, `arm()` has zero callers in `Sources/`, and task #204 records RecordController
//  as doorless. These tests pin ARITHMETIC on a pure function. That is the whole claim.
//
//  FOUR OF THESE SEVEN TESTS ARE RED ON THE OLD WINDOW — the paced-band sweep, the pinned
//  default-rate pair, the unmeasured-breath fallback and the floor-vs-pacer chain. The other
//  three hold what must NOT move (the heart term, the deliberately narrow top, non-finite
//  safety) and say so in their own doc comments.
//

import Foundation
import XCTest
@testable import Echoelmusic

final class TheArousalFloorSitsBelowThePacedBreathTests: XCTestCase {

    /// The old window, so "it got better" is measured against the real predecessor and not
    /// against a remembered one.
    private static func oldBreathTerm(_ rate: Double) -> Double {
        let span = 24.0 - 6.0
        return Swift.max(0, Swift.min(1, (rate - 6.0) / span))
    }

    /// Pins the heart term at its floor (50 bpm reads 0), so the returned value is exactly half
    /// the breath term and the breath half can be measured on its own.
    private static func breathHalf(_ rate: Double) -> Float {
        bioNormalized(bpm: 50, breathRate: rate)
    }

    // MARK: - Red on the old window

    /// THE CHAIN. The floor must sit strictly BELOW every rate the app's own pacer can ask for,
    /// measured behaviourally because the floor is a local constant: with the heart term pinned
    /// at zero, "the floor is below r" is exactly "the value at r is above zero".
    ///
    /// This is the test that goes red if someone raises the floor again, or lowers
    /// `BreathPacer.minRate` under it — either way the decision stops being silent.
    func testTheFloorSitsBelowEveryPacedRate() {
        XCTAssertGreaterThan(
            Self.breathHalf(BreathPacer.minRate), 0,
            "The arousal floor swallows BreathPacer.minRate (\(BreathPacer.minRate)/min): the "
            + "slowest rate the guide paces reads as total calm and cannot move.")
        XCTAssertGreaterThan(
            Self.breathHalf(BreathPacer.defaultRate), 0,
            "The arousal floor swallows BreathPacer.defaultRate (\(BreathPacer.defaultRate)/min)"
            + " — the rate Echoel paces by default. This was the #433 defect exactly.")
    }

    /// Every paced rate must carry DEPTH, not just be non-zero, and the depth must be monotone.
    /// Swept rather than sampled: a hand-picked pair survives a floor that is merely a hair
    /// lower, which is the shape of fix this test exists to reject.
    func testEveryPacedRateHasTravel() {
        var previous = -Double.infinity
        var rate = BreathPacer.minRate
        while rate <= BreathPacer.maxRate + 1e-9 {
            let value = Double(Self.breathHalf(rate))
            XCTAssertGreaterThan(value, 0, "Paced rate \(rate)/min reads as total calm.")
            XCTAssertGreaterThan(
                value, previous,
                "The breath term is not monotone at \(rate)/min — a slower breath must never "
                + "read as more aroused than a faster one.")
            previous = value
            rate += 0.1
        }
        // The far end of the paced band must be meaningfully clear of the floor, not a sliver.
        XCTAssertGreaterThan(Double(Self.breathHalf(BreathPacer.maxRate)), 0.15)
    }

    /// The measured before/after at the three rates that matter, pinned so a later widening of
    /// the window shows up as a number and not as a feeling.
    func testTheDefaultPacedRateWasFlatBefore() {
        XCTAssertEqual(Self.oldBreathTerm(BreathPacer.minRate), 0, accuracy: 0)
        XCTAssertEqual(Self.oldBreathTerm(BreathPacer.defaultRate), 0, accuracy: 0)

        XCTAssertEqual(Double(Self.breathHalf(5.0)), 0.047619, accuracy: 1e-5)
        XCTAssertEqual(Double(Self.breathHalf(6.0)), 0.071428, accuracy: 1e-5)
        XCTAssertEqual(Double(Self.breathHalf(12.0)), 0.214285, accuracy: 1e-5)
    }

    /// A frame with no breath reading must not be mixed in as calm. `usableBio()` checks
    /// freshness only, so a strap frame really does arrive with `breathRate: 0`; blending it
    /// halved the arousal value for a body whose heart said the opposite.
    func testAnUnmeasuredBreathIsNotBlendedInAsCalm() {
        XCTAssertEqual(bioNormalized(bpm: 120, breathRate: 0), 1.0, accuracy: 1e-6,
                       "A missing breath reading was blended in as maximum calm.")
        // Below and above the plausible set are both "no reading", not "very calm"/"frantic".
        XCTAssertEqual(bioNormalized(bpm: 120, breathRate: 2.9), 1.0, accuracy: 1e-6)
        XCTAssertEqual(bioNormalized(bpm: 120, breathRate: 41), 1.0, accuracy: 1e-6)
        // And the boundary of the gate IS a reading — 40 is in, 41 is out.
        XCTAssertEqual(Double(bioNormalized(bpm: 120, breathRate: 40)), 1.0, accuracy: 1e-6)
        XCTAssertEqual(Double(bioNormalized(bpm: 50, breathRate: 40)), 0.5, accuracy: 1e-6,
                       "40/min is inside the gate and above the arousal top: half of one, zero "
                       + "of the other.")
    }

    // MARK: - Counterweights (green before and after — they hold what must NOT move)

    /// The heart term is untouched by #433. Green on both sides on purpose: this file changes
    /// the breath half only, and a later "tidy-up" that rescales heart arousal has to argue with
    /// these numbers.
    func testTheHeartTermIsUntouched() {
        // Breath pinned outside the gate → no breath term → the value IS the heart term.
        XCTAssertEqual(Double(bioNormalized(bpm: 50, breathRate: 0)), 0.0, accuracy: 1e-6)
        XCTAssertEqual(Double(bioNormalized(bpm: 85, breathRate: 0)), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Double(bioNormalized(bpm: 120, breathRate: 0)), 1.0, accuracy: 1e-6)
        XCTAssertEqual(Double(bioNormalized(bpm: 30, breathRate: 0)), 0.0, accuracy: 1e-6)
    }

    /// The top stays NARROWER than the gate, deliberately — 24/min is an active ceiling, the
    /// gate admits 40. Everything from 24 up reads identically. This is the asymmetry #429
    /// argued for on the modulation scale, restated here so nobody "fixes" it into symmetry.
    func testTheTopIsDeliberatelyNarrowerThanTheGate() {
        let atTop = Self.breathHalf(24)
        XCTAssertEqual(Double(atTop), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Self.breathHalf(30), atTop, accuracy: 0)
        XCTAssertEqual(Self.breathHalf(40), atTop, accuracy: 0)
    }

    /// Non-finite input stays safe and finite — the render/UI side of this value can never be
    /// handed a NaN. `clamp01` maps NaN to 0 here by explicit check, not by argument order.
    func testNonFiniteIsStillSafe() {
        for value in [bioNormalized(bpm: .nan, breathRate: .nan),
                      bioNormalized(bpm: .infinity, breathRate: .nan),
                      bioNormalized(bpm: 70, breathRate: .nan),
                      bioNormalized(bpm: .nan, breathRate: 12)] {
            XCTAssertTrue(value.isFinite, "bioNormalized returned a non-finite control value.")
            XCTAssertTrue((0...1).contains(value))
        }
        XCTAssertEqual(bioNormalized(bpm: .nan, breathRate: .nan), 0, accuracy: 0)
    }
}
