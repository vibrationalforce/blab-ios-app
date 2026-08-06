// TheBandHoldsAtEveryRestingPulseTests.swift
// Echoel — #424 review. The band tolerance was fitted to ONE pulse, and 60 bpm is the one
// pulse at which the low edge does not need it.
//
// ⭐ THE DEFECT, and it is a defect in a TEST METHOD as much as in a constant.
// `TheBandEdgeIsMeasurableTests` sweeps all 360 whole-degree breathing phases and calls that a
// sweep. Every take in it runs at `meanBPM: 60`. At 60 bpm a 4 breaths/min cycle is exactly
// 15 beats, so the upward zero-crossing lands on the boundary period dead-on and a tolerance of
// 1.00002 clears it. Off that pulse the mechanism is plain beat quantisation: with N beats per
// breath cycle the crossing rounds to `floor(N)` or `ceil(N)`, so the required tolerance is
// ≈ 1 + 1/(2N) — that is **1 + 2/pulse** at the low edge.
//
// Measured requirement at 4 breaths/min: pulse 46 → 1.0439, 50 → 1.0403, 58 → 1.0347,
// 70 → 1.0287, 90 → 1.0223. **Sixteen of the 66 integer pulses in 45…110 need more than 1.02.**
// The tolerance shipped at 1.02 for one commit, and at those pulses it removed NONE of the
// silence it was written to remove — 19 of 360 phases still silent at pulse 46, 21 at 50,
// 27 at 62, 32 at 70, 44 at 90, bit-for-bit the pre-#424 behaviour.
//
// ⭐ WHY THIS IS ITS OWN FILE. Nothing in the blocking bundle could tell 1.02 from 1.06 — every
// behavioural number in both sibling files is identical across that whole interval, because
// they all run at 60 bpm. A constant no test can distinguish is a constant the next session will
// "simplify". These four tests are red at 1.02 and green at the shipped value, which is the only
// property that makes the constant defensible.
//
// ⛔ THE PULSE SET IS CHOSEN FROM PHYSIOLOGY, NOT FROM WHAT PASSES. It spans a resting-to-active
// adult range and deliberately MIXES degenerate and non-degenerate pulses: 55, 84 and 100 are
// degenerate at 4/min (integer beats per cycle — zero silence even pre-#424) and are here as the
// control, because a set made only of failing pulses would look like it was picked to fail.
// 42/46/50/62/70/90 are the non-degenerate ones that carry the assertion.
//
// ⛔ HONEST LIMITS.
//   · This drives the PURE estimator with exact timestamps. It proves the band arithmetic across
//     the pulse axis; it does not prove the camera path measures a real 4/min breather at any
//     pulse (that is #304/#410, and 4/min is 15 s per cycle).
//   · A constant pulse is itself a fixture. A real take drifts, and drift moves N continuously
//     rather than sitting on one value. The claim here is the weaker, checkable one: at a FIXED
//     pulse anywhere in the range, the advertised limits are measurable.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBandHoldsAtEveryRestingPulseTests: XCTestCase {

    private struct Beat { let time: Double; let heartRate: Double }

    /// Same generator as the two sibling files, with the pulse exposed. It is copied rather than
    /// shared for the reason `TheBandEdgeIsMeasurableTests` states: a tweak made for one file's
    /// property must not silently move another file's numbers.
    private static func rsaBeats(seconds: Double,
                                 breathsPerMinute: Double,
                                 phase: Double,
                                 meanBPM: Double,
                                 swingBPM: Double = 3) -> [Beat] {
        var out: [Beat] = []
        var t = 0.0
        while t < seconds {
            let hr = meanBPM + swingBPM * sin(2 * .pi * (breathsPerMinute / 60) * t + phase)
            out.append(Beat(time: t, heartRate: hr))
            t += 60 / hr
        }
        return out
    }

    private static let sweptPhases: [Double] = (0..<360).map { Double($0) * .pi / 180 }

    /// Resting → moderately active. Mixed on purpose: see the ⛔ at the top.
    ///   degenerate at 4/min (zero silence even pre-#424): 55, 84, 100
    ///   non-degenerate (silent at 1.02, measured counts in the comment): 42, 46, 50, 62, 70, 90
    private static let restingPulses: [Double] = [42, 46, 50, 55, 62, 70, 84, 90, 100]

    private static func measure(breathsPerMinute: Double,
                                phase: Double,
                                pulse: Double) -> RespirationEstimator {
        var estimator = RespirationEstimator()
        for beat in rsaBeats(seconds: 60,
                             breathsPerMinute: breathsPerMinute,
                             phase: phase,
                             meanBPM: pulse) {
            estimator.ingest(heartRate: beat.heartRate, at: beat.time)
        }
        return estimator
    }

    // MARK: - The two edges, off the fixture pulse

    /// ⭐ THE REGRESSION. Red at tolerance 1.02 at six of these nine pulses (16/19/21/27/32/44
    /// silent phases at 42/46/50/62/70/90), green at the shipped value at all nine.
    func testTheSlowestBreathIsMeasuredAtEveryRestingPulse() {
        for pulse in Self.restingPulses {
            var silent = 0
            for phase in Self.sweptPhases where
                Self.measure(breathsPerMinute: RespirationEstimator.minRate,
                             phase: phase,
                             pulse: pulse).ratePerMinute <= 0 {
                silent += 1
            }
            XCTAssertEqual(silent, 0, """
                At a \(pulse) bpm pulse the estimator reported NO rate at \(silent) of \
                \(Self.sweptPhases.count) starting phases for a body breathing at its own \
                advertised `minRate`. The band tolerance covers the 60 bpm fixture and not this \
                pulse — required tolerance is about 1 + 2/pulse at the low edge. Read the ⭐ at \
                the top of this file before changing the constant.
                """)
        }
    }

    /// The high edge, same treatment. Its requirement is far smaller (worst 1.00111 over
    /// pulse 45…110, at 60 bpm) so this is green on both sides of the tolerance change — it is
    /// here so a future narrowing cannot quietly reopen the edge this epic started with.
    func testTheFastestBreathIsMeasuredAtEveryRestingPulse() {
        for pulse in Self.restingPulses {
            var silent = 0
            for phase in Self.sweptPhases where
                Self.measure(breathsPerMinute: RespirationEstimator.maxRate,
                             phase: phase,
                             pulse: pulse).ratePerMinute <= 0 {
                silent += 1
            }
            XCTAssertEqual(silent, 0, """
                At a \(pulse) bpm pulse, \(RespirationEstimator.maxRate) breaths/min went silent \
                at \(silent) of \(Self.sweptPhases.count) phases.
                """)
        }
    }

    // MARK: - The ceiling on the tolerance

    /// ⭐ THE OTHER WALL, and the reason the constant is derived from a WINDOW rather than from a
    /// minimum. A wider acceptance band eventually admits a period that is not the breath cycle,
    /// and the report drags with it: at the fixture pulse the 4/min body reads 3.99993 for every
    /// tolerance up to 1.067 and 3.8197 at 1.068. So the usable window is bounded below by
    /// physiology (≈1.054 to cover pulses down to ~37 bpm) and above by measurement quality
    /// (≈1.067), and the shipped value sits inside it.
    ///
    /// ⛔ AND THIS TEST RUNS AT 60 bpm ONLY — IN A FILE WHOSE WHOLE POINT IS THAT 60 bpm IS NOT
    /// ENOUGH. That is not an oversight, it is where the quantity discriminates, and the first
    /// draft of this test got it wrong in exactly the way the file is about: it swept all nine
    /// pulses against a flat 3.9 and would have been RED ON THE SHIPPED CODE, because off the
    /// fixture the same beat quantisation that causes the silence also puts the honest floor at
    /// 3.812 (pulse 42) … 3.927 (pulse 55). At those pulses the shipped value and the
    /// over-wide one are 3.81 vs 3.82 — indistinguishable. At 60 bpm the step is 3.99993 → 3.8197,
    /// a factor of 2500 in the deviation, so any threshold strictly between them separates them
    /// and 0.1/min is a round one. **Taking a number measured at one pulse and asserting it at
    /// nine is the same mistake as deriving a constant at one pulse — one file apart.**
    func testAWiderBandStillRejectsPeriodsThatAreNotTheCycle() {
        let fixturePulse = 60.0
        let floorTolerance = 0.1
        var lowest = Double.infinity
        for phase in Self.sweptPhases {
            let r = Self.measure(breathsPerMinute: RespirationEstimator.minRate,
                                 phase: phase,
                                 pulse: fixturePulse).ratePerMinute
            guard r > 0 else { continue }
            lowest = Swift.min(lowest, r)
        }
        XCTAssertLessThan(lowest, Double.infinity,
                          "premise: the fixture pulse must answer at some phase")
        XCTAssertGreaterThan(lowest, RespirationEstimator.minRate - floorTolerance, """
            At \(fixturePulse) bpm the reported rate for a \(RespirationEstimator.minRate)/min \
            breather fell to \(lowest) — more than \(floorTolerance)/min under the advertised \
            floor, where the shipped tolerance reads 3.99993. The acceptance band is now wide \
            enough to swallow a period that is not the breath cycle; that wall is measured \
            between 1.067 and 1.068 and it is the ceiling on `bandTolerance`.
            """)
    }

    /// ⭐ THE COUNTERWEIGHT, carried over to the pulse axis. The objection to a wider band is
    /// "noise gets in", and the answer is the same at every pulse: the band is not the noise
    /// filter, the envelope veto is. Measured max confidence 0.150317 at pulses 46 · 60 · 90
    /// under tolerance 1.0, 1.02 and 1.055 alike — identical to six decimals, because none of
    /// this touches `envConf`.
    func testAStillHandPublishesNothingAtEveryRestingPulse() {
        for pulse in Self.restingPulses {
            for seed in 0..<24 {
                var estimator = RespirationEstimator()
                var t = 0.0
                var step = 0
                while t < 60 {
                    // Same deterministic pseudo-jitter as the sibling file: fixed irrational
                    // stride, no RNG, so this means the same thing on every machine.
                    let jitter = 0.6 * sin(Double(step) * 2.399963 + Double(seed))
                    estimator.ingest(heartRate: pulse + jitter, at: t)
                    t += 1.0
                    step += 1
                }
                let publishes = estimator.confidence >= 0.4 && estimator.ratePerMinute > 0
                XCTAssertFalse(publishes, """
                    A motionless hand at \(pulse) bpm (seed \(seed)) published \
                    \(estimator.ratePerMinute) breaths/min at confidence \(estimator.confidence). \
                    Beat jitter is not breathing, at any pulse and at any band width.
                    """)
            }
        }
    }
}
