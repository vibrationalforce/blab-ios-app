// TheBreathScaleSpansWhatTheGateAdmitsTests.swift
// Echoel — #429. `ModSource.breathRate.range` was `4...30`, copied from
// `RespirationEstimator.minRate`/`maxRate`. Two source docs already named it as the last
// live instance of that copy and both declined to fix it.
//
// ⭐ THE DEFECT, and it is a defect of REACH, not of accuracy. The set of values that can
// ever arrive at `normalizedValue` on a GATED route is exactly
// `BioSampleFrame.plausibleBreathRate` (`3...40`) — `ModSource.isMeasured` drops everything
// else. (⛔ This said "before a route ever runs", full stop. Three of the six consumers gate;
// `ModulationMatrix.output(for:frame:)` and `BoundParameter.resolved` do not, and the former
// says so in its own KNOWN, DEFERRED note. It changes no arithmetic — outside `3...40` both
// scales go negative or past 1 and `clamp01` flattens them identically — but a hedge dropped
// from a sentence is how the next reader inherits a premise the code contradicts.)
// A scale that started at 4 therefore left `[3, 4)` admitted-and-dead: the
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
// exists as an ASSERTION rather than as a comment. Widening to `3...40` costs a flat 27% of
// travel at EVERY rate in 3…30 (the ratio 27/37 is independent of the rate) — 0.170 absolute
// at 20/min, 0.270 at 30/min. It squeezes every rate a seated performer actually breathes, to
// buy resolution for panting. Saturating above 30 at full depth is a bounded answer; spending
// zero below 4 was not. (⛔ This said "0.27 of travel at 20/min" — 0.27 is the RELATIVE loss,
// identical at every rate, and the ABSOLUTE loss at 30/min. One number, two units, wrong rate.)
//
// ⚠️ WHO HEARS IT. ⛔ This said "no SHIPPED route binds `.breathRate` (the enum case appears
// only in `ModulationMatrix`'s own switches), so nothing a user hears today changes". Both
// halves were false: `hasProducer` is true for `.breathRate`, so `FXModCarrier.allChoices`
// (built from `ModSource.allCases.filter`) puts **"Breath rate"** in the live FX bio-mod
// carrier Picker, and `FXModulation.swift` has its own `switch` on `ModSource`. What is true
// is weaker: no PERSISTED route and no default binds it (`FXBioModulator.routes` is in-memory,
// starts empty, and the "+" button creates a coherence route), so a fresh launch is unchanged
// — but a route built in-session sounds different. `testTheBreathCarrierIsOfferedToTheUser`
// below turns that correction into a guard, because a grep of one file cannot see `allCases`.
//
// ⚠️ WHAT THIS FILE CANNOT DO. It measures a mapping, not a sound. The deeper question stays
// open on purpose: the scale is LINEAR over a 10× span while rate is perceived roughly
// logarithmically, so the resonance band still occupies a small slice of it. (And the 27%
// top-end price above is itself a consequence of that linearity — on a log rate map the same
// widening would cost ~11%. The two decisions interact; only one of them is made here.)
//
// ⚠️ THREE OF THESE EIGHT TESTS ARE RED ON THE OLD CONSTANT: `testTheScaleStartsWhereTheGate
// Starts`, `testEveryAdmittedSlowBreathSpendsDepth`, and `testTheResonanceBandKeepsTheTravel
// ItGained` (its `after` values and its strict-increase assertion both fail). ⛔ This said
// "only two of these six", while a doc comment 80 lines below already called the third one
// red — two contradicting sentences in one file, and the count was of six methods in a file
// that had seven. The rest pin what must NOT move and say so rather than posing as
// regressions.

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
                           """
                           the pre-#429 value for \(rate)/min. (⛔ This message claimed the \
                           value is "quoted in three source docs"; it is quoted in ONE, and \
                           for 4.5 and 5.0 in none — the sibling docs quote the BOUNDS.)
                           """)
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
                          costs a flat 27% of travel at every rate — 0.170 absolute at 20/min, \
                          0.270 at 30/min — to buy resolution for panting. The reason is \
                          written at `ModSource.range`.
                          """)
        XCTAssertEqual(ModSource.breathRate.range.upperBound, 30, accuracy: 1e-6)
    }

    /// ⭐ THE CLAIM THE FIRST VERSION GOT WRONG, TURNED INTO A GUARD. The commit said "no
    /// shipped route binds `.breathRate` — the enum case appears only in `ModulationMatrix`'s
    /// own switches", which was true of a grep and false of the product: `hasProducer` is
    /// `true`, so `FXModCarrier.allChoices` (`ModSource.allCases.filter(\.hasProducer)`) puts
    /// "Breath rate" in the live FX bio-mod carrier `Picker`. A grep cannot see `allCases`.
    /// This test asserts the reachability directly, so the next range change reads a fact
    /// rather than a claim. If breath ever stops being offered, this goes red and whoever
    /// removed it must also correct the audibility paragraph at `ModSource.range`.
    func testTheBreathCarrierIsOfferedToTheUser() {
        XCTAssertTrue(ModSource.breathRate.hasProducer,
                      "breath has a producer; `allChoices` filters on exactly this")
        XCTAssertTrue(FXModCarrier.allChoices.contains(.bio(.breathRate)),
                      """
                      "Breath rate" must be selectable in the FX bio-mod carrier picker. \
                      Any change to `ModSource.breathRate.range` is therefore audible to a \
                      user who builds a breath route in-session — it is NOT a dormant path.
                      """)
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
