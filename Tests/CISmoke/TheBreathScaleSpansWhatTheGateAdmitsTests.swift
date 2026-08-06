// TheBreathScaleSpansWhatTheGateAdmitsTests.swift
// Echoel — #429. `ModSource.breathRate.range` was `4...30`, copied from
// `RespirationEstimator.minRate`/`maxRate`. Two source docs already named it as the last
// live instance of that copy and both declined to fix it.
//
// ⭐ THE DEFECT, and it is a defect of REACH, not of accuracy. The set of values that can
// ever arrive at `normalizedValue` on a gated route is exactly
// `BioSampleFrame.plausibleBreathRate` (`3...40`) — `ModSource.isMeasured` drops everything
// else before a
// route ever runs. A scale that started at 4 therefore left `[3, 4)` admitted-and-dead: the
// gate called that frame a measurement, and the scale spent exactly zero depth on it,
// indistinguishable from a body that is not breathing at all. Same excursion, surviving
// inside the gate. Measured: 3.5/min normalized to 0.000000, and so did 3.9.
//
// ⭐ WHY THE GATE AND NOT THE ESTIMATOR. Chaining to `RespirationEstimator.reportableRange`
// (3.7736…) was the obvious move after #426 and it is the wrong one twice over: it mints a
// FIFTH respiration number, and it still leaves `[3, 3.7736)` dead — HealthKit forwards
// whatever the watch reports and is not bounded by our camera estimator. The gate is the
// only band that answers "what can actually get here".
//
// ⚠️ THE TOP IS DELIBERATELY NOT WIDENED, and that is why `testTheTopStaysNarrowerThanTheGate`
// exists as an ASSERTION rather than as a comment. Widening to `3...40` would cost 0.27 of
// travel at 20/min — squeezing every rate a seated performer actually breathes — to buy
// resolution for panting. Saturating above 30 at full depth is a bounded answer. Spending
// zero below 4 was not.
//
// ⚠️ WHAT THIS FILE CANNOT DO. It measures a mapping, not a sound. No SHIPPED route binds
// `.breathRate` (the enum case appears only in `ModulationMatrix`'s own switches), so nothing
// a user hears today changes — which also means no listening test can confirm the curve is
// the RIGHT one. And the deeper question stays open on purpose: the scale is LINEAR over a
// 10× span while rate is perceived roughly logarithmically, so the resonance band still
// occupies a small slice of it. That is a curve decision with no route to hear it on.
//
// ⚠️ ONLY TWO OF THESE SIX TESTS ARE RED ON THE OLD CONSTANT (`testTheScaleStartsWhereTheGate
// Starts` and `testEveryAdmittedSlowBreathSpendsDepth`). The other four pin what must NOT
// move — the untouched top, the untouched heart-rate case, the untouched gate, and bit
// identity at and above 30 — and they say so here rather than posing as regressions.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBreathScaleSpansWhatTheGateAdmitsTests: XCTestCase {

    /// A camera frame carrying one breath rate. `.cameraPPG` because that is the source
    /// whose estimator this range used to be copied from; the range does not read `source`.
    private static func frame(breathRate: Float) -> BioSampleFrame {
        BioSampleFrame(timestamp: 1,
                       heartRateBPM: 60,
                       hrvNormalized: 0.5,
                       breathRate: breathRate,
                       breathPhase: 0.5,
                       coherence: 0.5,
                       motionEnergy: 0,
                       source: .cameraPPG)
    }

    /// The pre-#429 mapping, kept here so the "did not move" tests compare against a real
    /// number rather than against a remembered one.
    private static func oldNormalized(_ v: Float) -> Float {
        ModulationMatrix.normalize(v, in: 4...30)
    }

    // MARK: - The chain (RED on the old constant)

    /// ⭐ THE STRUCTURAL GUARD. Red the moment anyone reverts the constant, and red — on
    /// purpose — if anyone moves `BioSampleFrame.plausibleBreathRate`'s low bound without moving
    /// this one. That second direction is the point: the gate decides what arrives, so the
    /// two cannot drift apart silently. It is a LITERAL in the source and a CHAIN here,
    /// which is the shape #426 settled on: a modulation curve must not move as a side
    /// effect of someone retuning a plausibility band, it must move as a decision.
    func testTheScaleStartsWhereTheGateStarts() {
        XCTAssertEqual(ModSource.breathRate.range.lowerBound,
                       BioSampleFrame.plausibleBreathRate.lowerBound,
                       accuracy: 1e-6,
                       """
                       The breath modulation scale must start where the measurement gate \
                       starts. Anything the gate admits reaches `normalizedValue`; anything \
                       below this bound spends zero depth and is indistinguishable from a \
                       body that is not breathing. Gate low bound is \
                       \(BioSampleFrame.plausibleBreathRate.lowerBound), scale low bound is \
                       \(ModSource.breathRate.range.lowerBound).
                       """)
    }

    /// ⭐ THE BEHAVIOURAL HALF, and it runs through `normalizedValue(from:)` on a real frame
    /// rather than through `normalize(_:in:)` — a correct range with no caller is the same
    /// defect with more steps. Every rate the gate admits, strictly above its floor and
    /// below the scale's top, must spend some depth.
    func testEveryAdmittedSlowBreathSpendsDepth() {
        let floor = BioSampleFrame.plausibleBreathRate.lowerBound
        for rate in [Float(3.2), 3.5, 3.7736, 3.9, 3.99, 4.0, 4.5, 5.0, 6.0] {
            let f = Self.frame(breathRate: rate)
            XCTAssertTrue(ModSource.breathRate.isMeasured(in: f),
                          "\(rate)/min is inside the gate and must read as a measurement")
            let v = ModSource.breathRate.normalizedValue(from: f)
            XCTAssertGreaterThan(v, 0,
                                 """
                                 \(rate)/min is above the gate floor (\(floor)) and must spend \
                                 some modulation depth, not saturate at zero. Got \(v).
                                 """)
            XCTAssertLessThan(v, 1, "\(rate)/min must not saturate at the top either")
        }
    }

    // MARK: - The measured cost, pinned so a later widening is a decision

    /// ⚠️ GREEN BEFORE AND AFTER IN SPIRIT — it pins the NEW numbers, so it is red on the old
    /// constant only incidentally. Its real job is the future: widening the top to the gate's
    /// 40 would shrink every one of these, so this test turns that into a red line rather
    /// than a quiet loss of travel.
    func testTheResonanceBandKeepsTheTravelItGained() {
        // rate → (pre-#429, post-#429). The resonance band `BreathPacer` paces sat in the
        // bottom 8% of every breath route.
        let expected: [(Float, Float, Float)] = [
            (4.5,  0.019231, 0.055556),
            (5.0,  0.038462, 0.074074),
            (6.0,  0.076923, 0.111111),
            (12.0, 0.307692, 0.333333),
            (20.0, 0.615385, 0.629630),
        ]
        for (rate, before, after) in expected {
            XCTAssertEqual(Self.oldNormalized(rate), before, accuracy: 1e-6,
                           "the pre-#429 value for \(rate)/min is quoted in three source docs")
            let now = ModSource.breathRate.normalizedValue(from: Self.frame(breathRate: rate))
            XCTAssertEqual(now, after, accuracy: 1e-6,
                           """
                           \(rate)/min must map to \(after). If this moved, the scale's bounds \
                           moved — check that the doc at `ModSource.range` still matches, and \
                           that widening the TOP was a decision and not a reflex.
                           """)
            XCTAssertGreaterThan(now, before,
                                 "#429 moves slow breathing UP the scale, never down")
        }
    }

    /// ⚠️ WHAT DID NOT MOVE. At and above the scale's top both mappings clamp to exactly 1.0,
    /// so the change is bit-identical there — stated as a test because "it only affects slow
    /// breathing" is the kind of claim that ages badly.
    func testNothingAtOrAboveTheTopMoved() {
        for rate in [Float(30.0), 31.8, 35.0, 40.0] {
            let now = ModSource.breathRate.normalizedValue(from: Self.frame(breathRate: rate))
            XCTAssertEqual(now, Self.oldNormalized(rate), accuracy: 0,
                           "\(rate)/min must be bit-identical across #429")
            XCTAssertEqual(now, 1.0, accuracy: 0, "\(rate)/min saturates at full depth")
        }
    }

    // MARK: - The counterweights (green on both sides, and they say so)

    /// ⭐ THE STANDING OBJECTION, ANSWERED. "You widened the band, now noise gets in." The
    /// band is not the filter — the GATE is, and #429 did not touch it. A 2/min or 41/min
    /// reading is still not a measurement, so no route ever sees it.
    func testTheGateStillDecidesWhatCountsAsAMeasurement() {
        for rate in [Float(0), 1.0, 2.0, 2.9, 41.0, 60.0] {
            XCTAssertFalse(ModSource.breathRate.isMeasured(in: Self.frame(breathRate: rate)),
                           """
                           \(rate)/min is outside `BioSampleFrame.plausibleBreathRate` and must not \
                           read as a measurement. #429 widened the SCALE, not the gate — if \
                           this fails, someone collapsed the two.
                           """)
        }
    }

    /// ⚠️ THE TOP IS NARROWER THAN THE GATE ON PURPOSE. Green before and after; it exists so
    /// that "make the scale the gate" cannot be done as tidying-up. If a founder decision
    /// ever widens the top, delete this test in the same commit — do not relax it.
    func testTheTopStaysNarrowerThanTheGate() {
        XCTAssertLessThan(ModSource.breathRate.range.upperBound,
                          BioSampleFrame.plausibleBreathRate.upperBound,
                          """
                          The scale's top is deliberately below the gate's: widening it to 40 \
                          costs ~0.27 of travel at 20/min — every rate a seated performer \
                          actually breathes — to buy resolution for panting. The reason is \
                          written at `ModSource.range`.
                          """)
        XCTAssertEqual(ModSource.breathRate.range.upperBound, 30, accuracy: 1e-6)
    }

    /// ⚠️ #429 TOUCHED ONE CASE. Heart rate's range is a free physiological span with no
    /// sibling gate to chain to, and it must not be dragged along by this slice.
    func testTheHeartRateScaleIsUntouched() {
        XCTAssertEqual(ModSource.heartRate.range.lowerBound, 40, accuracy: 1e-6)
        XCTAssertEqual(ModSource.heartRate.range.upperBound, 200, accuracy: 1e-6)
        for source in [ModSource.hrv, .breathPhase, .coherence, .motion,
                       .faceSmile, .faceBrow, .faceJaw] {
            XCTAssertEqual(source.range.lowerBound, 0, accuracy: 1e-6,
                           "\(source) is a unit channel")
            XCTAssertEqual(source.range.upperBound, 1, accuracy: 1e-6,
                           "\(source) is a unit channel")
        }
    }
}
