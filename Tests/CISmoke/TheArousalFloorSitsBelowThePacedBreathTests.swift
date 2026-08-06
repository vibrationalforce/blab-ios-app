//
//  TheArousalFloorSitsBelowThePacedBreathTests.swift
//  Echoelmusic — CISmoke (blocking bundle)
//
//  #433. The guard over `bioNormalized` (Sequencer/RecordAnchor.swift), which turns a live bio
//  frame into the 0…1 value the bio automation lane records.
//
//  WHAT WAS WRONG. Its breath window was `6.0...24.0`. `BreathPattern.resonance` (4+6 s) and
//  `BreathPattern.coherent` (5+5 s) are both EXACTLY 6.0/min, so a user following Echoel's own
//  guide sat exactly on the floor: the breath term read 0 at the paced target, and the whole
//  admitted set below 6 read 0 with it. Separately, `EngineBus.usableBio()` gates on FRESHNESS
//  only — a BLE-strap frame arrives with `breathRate: 0`, and that fabricated zero was blended
//  in as calm, halving the arousal value (the #215 argument, one path over).
//
//  ⚠️ WHAT THIS FILE CANNOT DO, stated first because the reviewer report that started #433 got
//  it wrong in the other direction: it cannot show that any of this is AUDIBLE or RECORDED
//  today. The path is dormant — `RecordController.onStep` opens with `guard armed else
//  { return }`, `arm()` has zero callers in `Sources/`, and task #204 records RecordController
//  as doorless. These tests pin ARITHMETIC on a pure function. That is the whole claim.
//
//  FIVE OF THESE EIGHT TESTS ARE RED ON THE OLD WINDOW: the paced-pattern chain, the travel
//  sweep, the pinned before/after pair, the unmeasured-breath fallback, and — less obviously —
//  `testTheHeartTermIsUntouched`, which pins breath OUTSIDE the gate and therefore depends on
//  the new fallback existing at all. ⛔ The first version filed that last one under
//  "counterweights, green before and after" in FIVE places at once (this header, a MARK, its
//  own doc comment, the commit body and CLAUDE.md). It is red: under the old window
//  `bioNormalized(85, 0)` was 0.25, not 0.5. Miscounting which of your own tests can fail is
//  the same defect as a guard that cannot fail, only harder to see.
//
//  Genuinely green on both sides, and labelled as such: the deliberately-narrow top and the
//  non-finite safety net.
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

    private static let gate = BioSampleFrame.plausibleBreathRate

    // MARK: - Red on the old window

    /// THE PRODUCT CHAIN. Every pattern the app actually paces must carry travel — measured
    /// behaviourally, because the floor is a local constant: with the heart term pinned at zero,
    /// "the floor is below r" is exactly "the value at r is above zero".
    ///
    /// ⛔ The first version of this test chained to `BreathPacer.minRate`/`maxRate` and called
    /// 5…12 "the pacer's whole range". Those two constants constrain NOTHING in the pacer —
    /// their only non-prose consumer is `ResonanceFinder`. `BreathPacer.tick` paces
    /// `pattern.cycleSeconds`, so the real paced set is `BreathPattern.curated`: 6.0, 6.0, 3.75
    /// (box) and 3.158 (4-7-8). Deriving it from the patterns means a new curated pattern is
    /// covered the day it is added, which a hardcoded band never is.
    func testEveryPacedPatternHasTravel() {
        XCTAssertFalse(BreathPattern.curated.isEmpty)
        for pattern in BreathPattern.curated {
            let rate = pattern.ratePerMinute
            XCTAssertTrue(Self.gate.contains(Float(rate)),
                          "\(pattern.name) paces \(rate)/min, outside the plausible gate — it "
                          + "could never be read as a measurement at all.")
            XCTAssertGreaterThan(
                Double(Self.breathHalf(rate)), 0,
                "The arousal floor swallows \(pattern.name) (\(rate)/min): a rate Echoel itself "
                + "paces reads as total calm and cannot move. This was the #433 defect exactly.")
        }
        // The two HOLD patterns clear the floor only barely, and that limit is real rather than
        // hidden: 0.018 and 0.004 of the lane. Pinned so nobody reads "has travel" as "enough".
        XCTAssertEqual(Double(Self.breathHalf(60.0 / 16.0)), 0.017857, accuracy: 1e-5)   // box
        XCTAssertEqual(Double(Self.breathHalf(60.0 / 19.0)), 0.003759, accuracy: 1e-5)   // 4-7-8
    }

    /// THE STRUCTURAL CHAIN, and the one that closes a coupling the first version left open:
    /// the floor is a literal 3.0 while `measuresBreath` admits exactly
    /// `BioSampleFrame.plausibleBreathRate`. If that gate's low bound ever moved to 2.0, rates
    /// in [2, 3) would be "measured" and read exactly 0 — #433's own defect, silently. Asserting
    /// EQUALITY makes that day a red test and therefore a decision.
    ///
    /// Both halves are needed: the first pins the floor no HIGHER than the gate, the second no
    /// LOWER (a floor below the gate would make the gate's own low bound read above zero).
    func testTheFloorIsExactlyTheGateFloor() {
        XCTAssertEqual(Self.breathHalf(Double(Self.gate.lowerBound)), 0, accuracy: 0,
                       "The arousal floor sits ABOVE the gate's low bound — everything between "
                       + "them is admitted as a measurement and given no depth.")
        XCTAssertGreaterThan(
            Double(Self.breathHalf(Double(Self.gate.lowerBound) + 0.001)), 0,
            "The arousal floor sits BELOW the gate's low bound, so the slowest admissible "
            + "breath is not the zero of the scale.")
    }

    /// Depth must be monotone across a realistic calm→moderate band, swept rather than sampled:
    /// a hand-picked pair survives a floor that is merely a hair lower, which is the shape of
    /// fix this test exists to reject. (5…12 is NOT "the paced band" — see the chain test above;
    /// it is simply the range a seated performer plausibly occupies.)
    func testTravelIsMonotoneAcrossACalmBand() {
        var previous = -Double.infinity
        var rate = 5.0
        while rate <= 12.0 + 1e-9 {
            let value = Double(Self.breathHalf(rate))
            XCTAssertGreaterThan(value, 0, "Rate \(rate)/min reads as total calm.")
            XCTAssertGreaterThan(
                value, previous,
                "The breath term is not monotone at \(rate)/min — a slower breath must never "
                + "read as more aroused than a faster one.")
            previous = value
            rate += 0.1
        }
        // 12/min is the top of that band; on the shipped window it reads 0.2143. The floor of
        // 0.15 is not a tuned number — it is the value the OLD window produced there (0.1667)
        // minus a margin, so this assertion fails if a future window ever gives 12/min LESS
        // depth than the window #433 replaced.
        XCTAssertGreaterThan(Double(Self.breathHalf(12.0)), 0.15)
    }

    /// The measured before/after at the three rates that matter, pinned so a later widening of
    /// the window shows up as a number and not as a feeling.
    func testTheDefaultPacedRateWasFlatBefore() {
        // These two exercise this file's own reimplementation of the old formula: they document
        // the predecessor, they cannot go red for any change to `Sources/`.
        XCTAssertEqual(Self.oldBreathTerm(5.0), 0, accuracy: 0)
        XCTAssertEqual(Self.oldBreathTerm(6.0), 0, accuracy: 0)

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

    /// THE COST OF THAT FALLBACK, exhibited rather than described. Leaving the gate is a JUMP,
    /// and the first version of this file only ever crossed the top edge at 120 bpm — the one
    /// heart rate where that particular jump is exactly zero. At 50 bpm the same step is half
    /// the lane. The old function had no step here at all; holding the last measured term across
    /// a dropout is the completion, and it is registered as its own slice rather than implied.
    func testLeavingTheGateIsAStepAndTheStepIsMeasured() {
        // Top edge, calm heart: 40 → 41 falls the whole way from 0.5 to 0.
        XCTAssertEqual(Double(bioNormalized(bpm: 50, breathRate: 41)), 0.0, accuracy: 1e-6)
        // Low edge, fast heart: the worst dropout step, at the rate the app paces.
        let measured = Double(bioNormalized(bpm: 120, breathRate: 6))
        let dropped = Double(bioNormalized(bpm: 120, breathRate: 0))
        XCTAssertEqual(measured, 0.571428, accuracy: 1e-5)
        XCTAssertEqual(dropped, 1.0, accuracy: 1e-6)
        XCTAssertEqual(dropped - measured, 0.428571, accuracy: 1e-5,
                       "The measured/unmeasured step at the paced rate changed size without "
                       + "anyone deciding to change it.")
    }

    // MARK: - Green before and after (they hold what must NOT move)

    /// The heart term is untouched by #433 — but this test is NOT green on the old window, and
    /// saying so is the point: it pins breath OUTSIDE the gate, so every case here depends on
    /// the new fallback. Under the old window `(85, 0)` was 0.25 and `(120, 0)` was 0.5.
    func testTheHeartTermIsUntouched() {
        // Breath pinned outside the gate → no breath term → the value IS the heart term.
        XCTAssertEqual(Double(bioNormalized(bpm: 50, breathRate: 0)), 0.0, accuracy: 1e-6)
        XCTAssertEqual(Double(bioNormalized(bpm: 85, breathRate: 0)), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Double(bioNormalized(bpm: 120, breathRate: 0)), 1.0, accuracy: 1e-6)
        XCTAssertEqual(Double(bioNormalized(bpm: 30, breathRate: 0)), 0.0, accuracy: 1e-6)
    }

    /// The top stays NARROWER than the gate, deliberately — 24/min is an active ceiling, the
    /// gate admits 40. Everything from 24 up TO THE GATE'S TOP reads identically; past the gate
    /// it is no longer a reading at all, which is a different branch (see the step test).
    /// This is the asymmetry #429 argued for on the modulation scale, restated here so nobody
    /// "fixes" it into symmetry.
    func testTheTopIsDeliberatelyNarrowerThanTheGate() {
        let atTop = Self.breathHalf(24)
        XCTAssertEqual(Double(atTop), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Self.breathHalf(30), atTop, accuracy: 0)
        XCTAssertEqual(Self.breathHalf(Double(Self.gate.upperBound)), atTop, accuracy: 0)
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
