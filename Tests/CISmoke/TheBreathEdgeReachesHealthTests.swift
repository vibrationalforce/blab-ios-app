// TheBreathEdgeReachesHealthTests.swift
// Echoel — #426. The write path dropped the measurement it exists to record.
//
// ⭐ THE DEFECT. `HealthWritePolicy.respiratoryRange` opened at exactly 4.0 breaths/min, copied
// from `RespirationEstimator.minRate`. But `minRate` is the rate the estimator TARGETS, not a
// bound its output obeys: #424 made acceptance use a wider band and the reported rate the raw
// EMA of accepted periods, so the report lives in `RespirationEstimator.reportableRange`
// (3.7736…31.8 today). A body breathing at exactly `minRate` therefore had a large share of its
// CORRECT measurements thrown away by `values(for:)`, which DROPS an out-of-range value rather
// than clamping it. Swept over all 360 whole-degree breathing phases, 60 s takes, this file's
// RSA generator: admitted at a 42 bpm pulse **214 of 360**, at 46 → 217, 50 → 218, 55 → 209,
// 62 → 219, 70 → 217, 84 → 137, 90 → 210, 100 → 146. Nine pulses, none of them clean.
//
// ⭐ AND THE COST IS NOT "FEWER SAMPLES", IT IS BIAS — which is why this is a defect and not a
// conservative filter doing its job. The cut sits almost exactly at the mean of the corrected
// distribution, so the survivors are the high half. Mean error of the WRITTEN subset vs. the
// whole published population: pulse 42 **+0.1522 vs +0.0497**, 46 +0.1430 vs +0.0492,
// 62 +0.1212 vs +0.0457, 90 +0.1093 vs +0.0415. Roughly a factor of three, on data that ends up
// in a person's health record and in `PerformerSignature`.
//
// ⭐ THE FIX IS WIDEN, NOT ROUND, and #424 is why. The version of the estimator that CLAMPED its
// report published exactly 4.000 at 358 of 360 phases for a body breathing 3.5/min — a fabricated
// number, inside the policy range, on its way to Apple Health. Rounding at the writer would
// rebuild that rail one layer down. The bound moves to 3.7 and nothing is pushed up into it.
//
// ⭐ WHY THE TWO CONSTANTS ARE CHAINED BY A TEST AND NOT BY AN EXPRESSION. `respiratoryRange`
// stays a LITERAL: what Echoel writes into a health record must not widen as a side effect of
// someone retuning a DSP constant. `testThePolicyAdmitsEverythingTheEstimatorCanReport` is the
// link — raise `bandTolerance` and this file goes red, so the widening becomes a decision
// somebody makes on purpose instead of a consequence nobody reads.
//
// ⛔ HONEST LIMITS — what these tests cannot show.
//   · They drive the PURE estimator with exact timestamps. They prove the arithmetic and the
//     range logic; they do NOT prove the camera path can hold a 4/min breather for the 15 s its
//     cycle takes (that is #304/#410).
//   · They stop at `HealthWritePolicy.values(for:)`. Whether `HealthKitWriter` actually stores
//     the sample needs HealthKit and a device; no CI host can answer it.
//   · `values(for:)` is not the whole gate — `shouldWrite` decides whether anything is written
//     at all, and it checks `enabled`, `authorized`, the `minWriteGap`, **`isWritableSource`**
//     and then the heart rate. (⛔ This bullet said "it looks only at the heart rate" for one
//     commit, in the block whose job is the honest limits — and the omitted `isWritableSource`
//     is the single fact that makes the widened bound safe, because it is what keeps
//     `BioSimulator`'s flat 12 and `HealthKitBioPublisher`'s echo off this path.) These tests
//     deliberately do not restate that gate; `HealthWritePolicyTests` covers it, and a second
//     weaker copy of a live claim is its own defect (#416).
//

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBreathEdgeReachesHealthTests: XCTestCase {

    private struct Beat { let time: Double; let heartRate: Double }

    /// Same generator as `TheBandEdgeIsMeasurableTests` and `TheBandHoldsAtEveryRestingPulseTests`,
    /// copied rather than shared for the reason those files state: a tweak made for one file's
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

    /// The same nine pulses the sibling file sweeps, so the counts in the header can be compared
    /// against its counts without re-deriving anything.
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

    /// A frame shaped the way `CameraRPPGBioPublisher` builds one: the estimator's report
    /// narrowed to `Float`, source `.cameraPPG`. The narrowing matters — it is the only rounding
    /// on this path, and a test that compared against the `Double` would be testing a value the
    /// policy never sees.
    ///
    /// ⚠️ "EXACTLY THE WAY" WAS TOO STRONG FOR ONE COMMIT, and the gap is the kind this file is
    /// about: the publisher gates on `resp.confidence >= 0.4 && resp.ratePerMinute > 0` before a
    /// report becomes a `breathRate`, while the sweeps below gate only on `rate > 0`. So the
    /// counts could in principle be measured over a superset of the shipped population. Measured:
    /// at `minRate` the confidence gate does not bite at ANY of the nine pulses — 360 of 360
    /// phases clear 0.4 at each — so every count in this file is identical on both populations.
    /// The qualification stays because it will stop being true if the gate or the confidence
    /// terms move.
    private static func cameraFrame(breathRate: Double, pulse: Double) -> BioSampleFrame {
        BioSampleFrame(timestamp: 1,
                       heartRateBPM: Float(pulse),
                       hrvNormalized: 0.5,
                       breathRate: Float(breathRate),
                       breathPhase: 0.5,
                       coherence: 0.5,
                       motionEnergy: 0,
                       source: .cameraPPG)
    }

    // MARK: - The chain between the two constants

    /// ⭐ THE STRUCTURAL GUARD. Red if you revert only the constant (`4.0 > 3.7736`) — not
    /// literally "before #426", since `reportableRange` arrived in the same commit — and red the
    /// moment anyone widens the estimator's acceptance band without deciding what that means for
    /// a health record. It is the reason `respiratoryRange` may stay a literal.
    func testThePolicyAdmitsEverythingTheEstimatorCanReport() {
        let reportable = RespirationEstimator.reportableRange
        let policy = HealthWritePolicy.respiratoryRange

        XCTAssertLessThanOrEqual(policy.lowerBound, reportable.lowerBound, """
            The health-write filter starts at \(policy.lowerBound) breaths/min but the estimator \
            can report down to \(reportable.lowerBound). Everything in between is a correct \
            measurement that gets silently discarded on the way to Apple Health — and because \
            the cut sits near the middle of the distribution, what survives is biased high, not \
            merely thinner. Widen `HealthWritePolicy.respiratoryRange` (do NOT clamp or round the \
            report — #424 shows that fabricates a value on the rail), or decide deliberately that \
            the edge must not be written and say so here.
            """)
        XCTAssertGreaterThanOrEqual(policy.upperBound, reportable.upperBound, """
            The health-write filter stops at \(policy.upperBound) breaths/min but the estimator \
            can report up to \(reportable.upperBound). Same defect at the other end.
            """)
    }

    // MARK: - The behaviour that filter decides

    /// ⭐ THE REGRESSION. Pre-#426 this failed at every one of the nine pulses — 214/217/218/209/
    /// 219/217/137/210/146 of 360 ADMITTED, i.e. 146/143/142/151/141/143/223/150/210 dropped.
    /// (Both directions are spelled out because the first version of the CLAUDE.md entry for this
    /// slice printed the admitted counts as if they were the losses.) The rate swept is the estimator's own `minRate` —
    /// the resonance end the product is built around, not a contrived edge.
    func testTheSlowestBreathIsWrittenAtEveryRestingPulse() {
        for pulse in Self.restingPulses {
            var published = 0
            var dropped = 0
            for phase in Self.sweptPhases {
                let rate = Self.measure(breathsPerMinute: RespirationEstimator.minRate,
                                        phase: phase,
                                        pulse: pulse).ratePerMinute
                guard rate > 0 else { continue }
                published += 1
                if HealthWritePolicy.values(for: Self.cameraFrame(breathRate: rate,
                                                                 pulse: pulse)).respiratoryRate == nil {
                    dropped += 1
                }
            }
            XCTAssertGreaterThan(published, 0, """
                No rate was published at all at a \(pulse) bpm pulse, so this test proved \
                nothing. That is a #424 regression, not a #426 one — fix the band first.
                """)
            XCTAssertEqual(dropped, 0, """
                At a \(pulse) bpm pulse, \(dropped) of \(published) published measurements of a \
                body breathing at `minRate` were dropped by `HealthWritePolicy.values(for:)`. \
                They are correct measurements: the estimator reports the raw EMA and it sits just \
                under 4.0 for roughly half the breathing phases. Dropping them does not make the \
                health record cleaner — it makes it biased high.
                """)
        }
    }

    /// ⭐ THE POINT OF THE WHOLE SLICE, and the half that a wider bound alone would not prove:
    /// what is written is the MEASUREMENT, bit for bit, and it really does go below `minRate`.
    /// If a later change "fixes" the drop by rounding the report up to 4.0, the first assertion
    /// stays green and this one goes red — which is the correct alarm, because a value on the
    /// rail is invented data (#424).
    func testTheWrittenValueIsTheMeasurementAndReallyGoesBelowMinRate() {
        for pulse in [42.0, 90.0] {
            var belowMinRate = 0
            var checked = 0
            for phase in Self.sweptPhases {
                let rate = Self.measure(breathsPerMinute: RespirationEstimator.minRate,
                                        phase: phase,
                                        pulse: pulse).ratePerMinute
                guard rate > 0 else { continue }
                let frame = Self.cameraFrame(breathRate: rate, pulse: pulse)
                guard let written = HealthWritePolicy.values(for: frame).respiratoryRate else { continue }
                checked += 1
                XCTAssertEqual(written, Double(frame.breathRate), """
                    The value handed to Apple Health is not the value in the frame \
                    (\(written) vs \(frame.breathRate)). `values(for:)` must pass the measurement \
                    through untouched — no clamp, no rounding into the range.
                    """)
                if written < RespirationEstimator.minRate { belowMinRate += 1 }
            }
            XCTAssertGreaterThan(checked, 0, "Nothing was written at a \(pulse) bpm pulse.")
            XCTAssertGreaterThan(belowMinRate, 0, """
                At a \(pulse) bpm pulse NOT ONE written sample of a `minRate` breather landed \
                below \(RespirationEstimator.minRate). Measured, roughly 40 % of them do — so \
                either the estimator started clamping its report, or the frame is no longer built \
                the way `CameraRPPGBioPublisher` builds it. Both mean this file is now green \
                without testing anything.
                """)
        }
    }

    /// ⛔ THE COUNTERWEIGHT. Widening a plausibility filter invites the obvious objection: what
    /// else does it now let in? Nothing — the low bound sits below what the estimator can emit
    /// and above everything that is not a measurement. `0` in particular is not a slow breath: it
    /// is what `PolarH10BioPublisher` publishes literally, and what `CameraRPPGBioPublisher`
    /// publishes when it has not measured a breath.
    func testTheThingsThatAreNotMeasurementsAreStillRejected() {
        let notMeasurements: [Float] = [0, -1, 2.5, 3.0, 45, 99, .nan, .infinity]
        for value in notMeasurements {
            let frame = Self.cameraFrame(breathRate: Double(value), pulse: 60)
            XCTAssertNil(HealthWritePolicy.values(for: frame).respiratoryRate, """
                \(value) breaths/min was accepted as a respiratory sample. The widened bound is \
                there to admit the estimator's own low-edge jitter (it cannot emit below \
                \(RespirationEstimator.reportableRange.lowerBound)), not to weaken the filter.
                """)
        }
    }

    /// The heart-rate half of `values(for:)` is untouched by this slice; this pins that it did not
    /// move while the respiratory bound did. One frame, one fact — not a re-test of
    /// `HealthWritePolicyTests`.
    func testTheHeartRateIsStillPassedThroughUnchanged() {
        let frame = Self.cameraFrame(breathRate: 3.8, pulse: 61)
        XCTAssertEqual(HealthWritePolicy.values(for: frame).heartRate, 61, accuracy: 0.0001)
    }
}
