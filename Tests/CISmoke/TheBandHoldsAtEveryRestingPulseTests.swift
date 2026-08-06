// TheBandHoldsAtEveryRestingPulseTests.swift
// Echoel — #424 review. The band tolerance was fitted to ONE pulse, and 60 bpm is the one
// pulse at which the low edge does not need it.
//
// ⭐ THE DEFECT, and it is a defect in a TEST METHOD as much as in a constant.
// `TheBandEdgeIsMeasurableTests` sweeps all 360 whole-degree breathing phases and calls that a
// sweep. Every take in it runs at `meanBPM: 60`. At 60 bpm a 4 breaths/min cycle is exactly
// 15 beats, so the upward zero-crossing lands on the boundary period dead-on and a tolerance of
// 1.00002 clears it. Off that pulse the mechanism is plain beat quantisation: with N beats per
// breath cycle the crossing rounds to `floor(N)` or `ceil(N)`.
//
// Measured requirement at 4 breaths/min: pulse 46 → 1.0439, 50 → 1.0403, 58 → 1.0347,
// 70 → 1.0287, 90 → 1.0223. **Sixteen of the 66 integer pulses in 45…110 need more than 1.02.**
// The tolerance shipped at 1.02 for one commit, and at those pulses it removed NONE of the
// silence it was written to remove — 19 of 360 phases still silent at pulse 46, 21 at 50,
// 27 at 62, 32 at 70, 44 at 90, bit-for-bit the pre-#424 behaviour.
//
// ⛔ THE FIRST VERSION OF THIS HEADER CALLED `1 + 1/(2N)` — "1 + 2/pulse" at the low edge — THE
// REQUIREMENT. It is the WORST CASE, attained only when N's fractional part is 0.5. Measured
// against it: pulse 45 (N = 11.25) needs **1.0** where the formula says 1.0444, pulse 55 (13.75)
// needs 1.0185 against 1.0364. Safe direction, so nothing downstream moved — but a bound quoted
// as an equality is how the next session picks a constant from arithmetic instead of measuring.
//
// ⭐ WHY THIS IS ITS OWN FILE. Nothing in the blocking bundle could tell 1.02 from 1.06 — every
// behavioural number in both sibling files is identical across that whole interval, because
// they all run at 60 bpm. A constant no test can distinguish is a constant the next session will
// "simplify". `testTheSlowestBreath…` is red at 1.02 at six of the nine pulses and green at the
// shipped value, which is the property that makes the constant defensible.
//
// ⛔ "THESE FOUR TESTS ARE RED AT 1.02" IS WHAT THAT PARAGRAPH SAID, AND IT IS TRUE OF ONE OF
// THEM. Each test's own doc comment already said so — `…FastestBreath…` says "green on both
// sides", `…AStillHand…` says "identical at every tolerance" — so the header stated a property
// of one test as a property of four, in a file whose thesis is that a conclusion must not be
// stated wider than the sweep that produced it.
//
// ⛔ AND THE PARAGRAPH DEFENDING THE PULSE SET WAS FALSE ON BOTH HALVES, WITH THE MECHANISM
// INVERTED. It read: "55, 84 and 100 are degenerate at 4/min (integer beats per cycle — zero
// silence even pre-#424) and are here as the control." (1) **55 is not degenerate** — 4/min at
// 55 bpm is 13.75 beats per cycle. (2) **Pre-#424 silence at those three is 112 / 223 / 214 of
// 360**, the WORST three in the set, not zero. A degenerate pulse is the knife-edge case, not
// the safe one: the crossing lands on the boundary period exactly, so it goes silent at two
// thirds of all phases and any ε > 0 clears it (which is why 60 bpm showed 240/360 and needs
// only 1.00002). What the paragraph meant was "zero silence AT TOLERANCE 1.02" — measured, and
// true — and it substituted "pre-#424" for that. **There is no control in this set: all nine
// pulses are red pre-#424.** The honest defence of the set is the one below it — it spans a
// physiological range rather than a chosen one — and that defence stands on its own.
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

    /// Resting → moderately active, chosen to span a physiological range rather than to pass.
    /// Degenerate at 4/min (integer beats per cycle): 84, 100. Non-degenerate: 42, 46, 50, 55,
    /// 62, 70, 90. Pre-#424 low-edge silence, all nine, of 360 phases: 42→16, 46→19, 50→21,
    /// 55→112, 62→27, 70→32, 84→223, 90→44, 100→214. At 1.02 the last three drop to zero and the
    /// first six do not — that split is the regression this file exists for.
    private static let restingPulses: [Double] = [42, 46, 50, 55, 62, 70, 84, 90, 100]

    /// ⭐ THE HIGH EDGE NEEDS A DIFFERENT SET, AND NOT HAVING ONE MADE THE HIGH-EDGE TEST INERT.
    /// Measured requirement at 30 breaths/min over pulses 37…110: **1.0 at every pulse in
    /// `restingPulses`** — so `testTheFastestBreath…` was green with the whole two-band mechanism
    /// reverted, i.e. 3 240 sixty-second takes pinning nothing. The edge is only defective in a
    /// two-bpm neighbourhood: pulse **61** goes silent at 123 of 360 phases pre-#424 (requirement
    /// 1.0127) and pulse **60** at 61 (requirement 1.00111). Those two are appended so the test
    /// can fail. Same lesson as the file's thesis, one axis over: a sweep that never crosses the
    /// defect is not a sweep.
    private static let highEdgePulses: [Double] = restingPulses + [60, 61]

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

    /// The high edge, same treatment, over `highEdgePulses`. Its requirement is far smaller than
    /// the low edge's — worst **1.0127, at pulse 61** — so this is green on both sides of the
    /// 1.02 → 1.06 change. It is here so a narrowing below ~1.013 cannot quietly reopen the edge
    /// this epic started with. ⛔ Over `restingPulses` alone it could not do that: the
    /// requirement is 1.0 at all nine, so it was green with the whole mechanism reverted.
    func testTheFastestBreathIsMeasuredAtEveryRestingPulse() {
        for pulse in Self.highEdgePulses {
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

    /// ⭐ WHAT THIS PINS: the degenerate fixture keeps its exactness. At 60 bpm the 4/min body
    /// reads 3.99993 for every tolerance up to 1.067 and 3.8197 at 1.068.
    ///
    /// ⛔ IT WAS SOLD AS "THE OTHER WALL … the constant is derived from a WINDOW rather than from
    /// a minimum", AND THAT WAS A FIXTURE ARTEFACT DRESSED AS A MEASUREMENT-QUALITY BOUND. 1.067
    /// is where a 60 bpm pulse starts accepting the 16-beat quantisation of its own 15 s cycle —
    /// the same slow neighbour the fix deliberately admits at every non-degenerate pulse, and
    /// which is already admitted well below that: pulse 42's lowest report is 3.8120 at 1.055 and
    /// unchanged at 1.068, 1.08 and 1.1. So the assertion message's "wide enough to swallow a
    /// period that is not the breath cycle" is wrong about the mechanism. There is ONE measured
    /// wall on this constant, at the bottom (1.0595 at pulse 34), and the shipped 1.06 clears it.
    /// This test still earns its place — it holds the fixture's exactness, which is what makes
    /// the sibling files' 60 bpm numbers mean anything — but it is not a ceiling.
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
            floor, where the shipped tolerance reads 3.99993. The degenerate fixture has stopped \
            resolving its own cycle exactly, which happens above ~1.067. That is a property of \
            THIS pulse, not a ceiling on `bandTolerance` — read the ⛔ above before treating it \
            as one.
            """)
    }

    /// ⭐ THE COUNTERWEIGHT, carried over to the pulse axis. The objection to a wider band is
    /// "noise gets in", and the answer is the same at every pulse: the band is not the noise
    /// filter, the envelope veto is. Measured max confidence 0.150317 at pulses 46 · 60 · 90
    /// under tolerance 1.0, 1.02, 1.055 and 1.06 alike — identical to six decimals, because none
    /// of this touches `envConf`.
    ///
    /// ⚠️ AND IT IS PULSE-INDEPENDENT BY CONSTRUCTION, so the 9 × 24 loop is 216 evaluations of
    /// one quantity. The generator steps `t += 1.0` and feeds `pulse + jitter`, so `trend − pulse`
    /// obeys a pulse-free recursion and only cancellation noise depends on the pulse — hence the
    /// nine identical decimals. It is kept because it costs little and states the invariant next
    /// to the tests it guards, but "carried over to the pulse axis" overstates what the fixture
    /// can show; the counterweight it duplicates lives in `TheBandEdgeIsMeasurableTests`.
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
