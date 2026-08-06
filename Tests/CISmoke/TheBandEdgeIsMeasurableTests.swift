// TheBandEdgeIsMeasurableTests.swift
// Echoel — #424. The estimator was blind at the two rates it advertises as its limits.
//
// ⭐ THE DEFECT. `RespirationEstimator` publishes `minRate = 4` and `maxRate = 30` breaths/min
// as its supported band. A new upward zero-crossing produced a period, and that period was
// ACCEPTED only if `minRate <= 60/period <= maxRate`. Rejected meant rejected outright: no
// `periodEMA` update, no `crossingCount`, no rate. So a breath cycle whose jitter put the
// implied rate a hair OUTSIDE the band did not read as "roughly at the edge" — it read as
// nothing at all, and the estimator kept reporting `ratePerMinute == 0`, which the publisher's
// gate (`confidence >= 0.4 && ratePerMinute > 0`) turns into no bio frame.
//
// Simulated over all 360 whole-degree breathing phases, 60 s takes, the file's own RSA
// generator, resting pulse:
//   ·  4 breaths/min — the LOW edge: `ratePerMinute == 0` at 240 of 360 phases (67 %).
//   · 30 breaths/min — the HIGH edge: 0 at 61 of 360 (17 %), plus 53 phases reading ~10.
// The LOW edge — which nobody had looked at, including the review that found this — is four
// times worse than the high one.
//
// ⛔ "AT EVERY RATE STRICTLY INSIDE THE BAND THE BEHAVIOUR IS BIT-IDENTICAL" STOOD HERE FOR ONE
// COMMIT AND IS FALSE AS A UNIVERSAL. Swept at 0.25/min steps, the reported rate moves at
// 4.0–4.75 and again from 20.5 to 30: jitter can push an INTERIOR rate's implied period outside
// the old band, so the repair reaches inward from both ends. The true, narrower claim is the one
// `testInsideTheBandNothingMoved` pins — bit-identical at 5, 6, 10, 15 and 20 — and where it
// does move, it improves (4.25/min worst error 0.4226 → 0.3661, 24/min 4.9626 → 2.2217; better
// at every changed rate except 21.5, which is 0.0108/min worse). This is the same defect the
// (⛔ 0.0044 here for two commits: 90 phases sampled and called a sweep. `RespirationEstimator`
// retracted it; this file is the fourth of the four places it stood and was missed by the
// retraction that names it. A correction has to be applied at every site it lists.)
// file's own ⛔s keep retracting: a sweep was run, and the conclusion was stated wider than it.
//
// ⭐ THE FIX, in one sentence: ACCEPT into a wider band than you REPORT. Acceptance uses
// `[minRate / bandTolerance, maxRate * bandTolerance]`; the reported
// `ratePerMinute` is the raw EMA and is NOT clamped back. A measurement at 30.4/min is a 30/min
// breath with jitter, not nonsense — refusing it is not conservative, it is blind.
//
// ⛔ THE FIRST VERSION OF THAT SENTENCE SHIPPED A TOLERANCE OF 1.2 *AND* A CLAMP, and both
// halves were wrong. 1.2 was ~180× the measured minimum repairing tolerance (1.00111); the
// clamp turned the boundary into a rail — at 3.5 breaths/min the estimator published at 360 of
// 360 phases with `ratePerMinute` exactly 4.000 at 358 of them, and
// `HealthWritePolicy.respiratoryRange` (4...40 then; 3.7...40 since #426) CONTAINS 4.0, so a fabricated value would have
// been written to Apple Health. `testTheReportedRateIsAMeasurementAndNotARail` is the guard.
//
// ⛔ WHY THIS IS A GUARD AND NOT JUST A FIX. The obvious objection to widening an acceptance
// band is that it lets noise in. That objection is the reason `testAStillHandStillPublishesNothing`
// exists and is the most important test in this file: a hand with no respiratory swing at all,
// only beat jitter, must not produce a published rate. It does not, at either tolerance, with
// identical confidence — because the envelope veto (`envConf`), not the band, is what rejects
// noise. Widening the band does not touch that mechanism. If a later change makes the band the
// noise filter, that test goes red and this comment is the explanation.
//
// ⛔ HONEST LIMITS.
//   · This drives the PURE estimator with exact timestamps. It proves the arithmetic and the
//     band logic; it does not prove the camera path measures a real 4/min breather (that is
//     #304/#410, and 4/min is 15 s per cycle — the acquisition has to survive that long).
//   · ⛔ THIS BULLET READ "the smallest tolerance that removes the silence at both edges is
//     1.00111, so 1.02 is that minimum with ~18× margin" — the exact derivation
//     `RespirationEstimator.bandTolerance` now spends four paragraphs retracting as
//     fixture-fitted, left standing in a block titled HONEST LIMITS, which is the most expensive
//     place for a retracted derivation to survive. 1.00111 is the 60 bpm value and 60 bpm is
//     degenerate at the low edge. The real floor is measured per pulse
//     (`TheBandHoldsAtEveryRestingPulseTests`): worst 1.0595 at pulse 34, which is what the
//     shipped 1.06 clears. What is derived outright is the SHAPE: accept-band ⊋ report-band. The
//     tests below pin the shape, the two edges and the no-rail property.
//   · Every behavioural number in THIS file is a 60 bpm number. That is not a flaw in the
//     numbers — it is why the pulse-axis file exists, and why no assertion here should be read
//     as a property of the estimator rather than of this fixture.
//   · Nothing here says the reading at the edge is GOOD. At 30/min the RMS error is 1.19/min
//     after the fix, against 8.52 before.
//     ⛔ That "before" figure carried the parenthetical "dominated by the zeros" for one commit
//     and the zeros are not in it at all: 8.52 is the RMS over the 299 phases that ANSWERED,
//     and the 61 silent ones are excluded by construction. Counting them as full 30/min errors
//     gives 14.59. What actually dominates the 8.52 is the 55 half-rate reads — they carry
//     99.995 % of its sum of squares, and without them the 299 answering phases sit at 0.066.
//     A one-word attribution, wrong, inside the bullet whose job is to keep the claim modest.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBandEdgeIsMeasurableTests: XCTestCase {

    private struct Beat { let time: Double; let heartRate: Double }

    /// Deliberately a private copy of the generator in
    /// `ResonanceBreathingNeedsMoreThanOneWindowTests` rather than a shared helper: these two
    /// files pin different properties of the same struct, and a shared fixture means a tweak
    /// for one silently moves the other's numbers. The duplication is fifteen lines — fourteen
    /// for the generator plus the one-line `Beat`. ("Eleven" stood here for one commit and was
    /// never counted; a cost stated to justify a design decision has to be measured like any
    /// other number in this file.)
    private static func rsaBeats(seconds: Double,
                                 breathsPerMinute: Double,
                                 phase: Double,
                                 meanBPM: Double = 60,
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

    private static func measure(breathsPerMinute: Double,
                                phase: Double,
                                seconds: Double = 60,
                                swingBPM: Double = 3) -> RespirationEstimator {
        var estimator = RespirationEstimator()
        for beat in rsaBeats(seconds: seconds,
                             breathsPerMinute: breathsPerMinute,
                             phase: phase,
                             swingBPM: swingBPM) {
            estimator.ingest(heartRate: beat.heartRate, at: beat.time)
        }
        return estimator
    }

    // MARK: - The two edges

    /// ⭐ THE REGRESSION, low edge. Red on the shipped code at 240 of 360 phases.
    func testTheSlowestSupportedBreathIsMeasured() {
        var silent: [Double] = []
        var worstError = 0.0
        for phase in Self.sweptPhases {
            let e = Self.measure(breathsPerMinute: RespirationEstimator.minRate, phase: phase)
            if e.ratePerMinute <= 0 { silent.append(phase); continue }
            worstError = Swift.max(worstError, abs(e.ratePerMinute - RespirationEstimator.minRate))
        }
        XCTAssertTrue(silent.isEmpty, """
            \(RespirationEstimator.minRate) breaths/min is the estimator's OWN advertised \
            `minRate`, and it reported no rate at all at \(silent.count) of \
            \(Self.sweptPhases.count) starting phases. A rate at the edge of the band must be \
            accepted into the band, not discarded — see the ⭐ note at the top of this file.
            """)
        XCTAssertLessThan(worstError, 1.0, """
            The slowest supported breath is measured, but the worst phase is off by \
            \(worstError)/min. Widening the ACCEPT band must not widen the ERROR; if this \
            fails, the tolerance let something in that is not a breath cycle.
            """)
    }

    /// ⭐ THE REGRESSION, high edge. Red on the shipped code at 61 of 360 phases.
    ///
    /// This is the one the review found, and its cause is measured rather than inferred: at
    /// every one of those 61 phases EVERY crossing was rejected with an implied rate of
    /// 30.000000…x — a hair over `maxRate`, from beat quantisation, not from a wrong period.
    func testTheFastestSupportedBreathIsMeasured() {
        var silent = 0
        var wildlyWrong = 0
        for phase in Self.sweptPhases {
            let e = Self.measure(breathsPerMinute: RespirationEstimator.maxRate, phase: phase)
            if e.ratePerMinute <= 0 { silent += 1; continue }
            if abs(e.ratePerMinute - RespirationEstimator.maxRate) > 5 { wildlyWrong += 1 }
        }
        XCTAssertEqual(silent, 0, """
            \(RespirationEstimator.maxRate) breaths/min is the estimator's OWN advertised \
            `maxRate` and it went silent at \(silent) of \(Self.sweptPhases.count) phases.
            """)
        XCTAssertLessThanOrEqual(wildlyWrong, 4, """
            \(wildlyWrong) phases at the top of the band read more than 5/min away from the \
            truth. A handful of half-rate reads is a known consequence of ~2 beats per breath \
            cycle at a resting pulse (#421); a large share means the widened band is accepting \
            periods that are not cycles.
            """)
    }

    // MARK: - What must NOT change

    /// ⭐ THE COUNTERWEIGHT, and the reason a widened acceptance band is safe. A hand with NO
    /// respiratory swing — beat jitter only — must not produce a published reading, and the
    /// band is not what stops it: the envelope veto is. If the band ever becomes the noise
    /// filter, this goes red.
    func testAStillHandStillPublishesNothing() {
        for seed in 0..<24 {
            var estimator = RespirationEstimator()
            var t = 0.0
            var step = 0
            while t < 60 {
                // Deterministic pseudo-jitter: a fixed irrational stride, no RNG, so this test
                // means the same thing on every machine and in every run.
                let jitter = 0.6 * sin(Double(step) * 2.399963 + Double(seed))
                estimator.ingest(heartRate: 60 + jitter, at: t)
                t += 1.0
                step += 1
            }
            let publishes = estimator.confidence >= 0.4 && estimator.ratePerMinute > 0
            XCTAssertFalse(publishes, """
                A motionless hand (seed \(seed)) published \(estimator.ratePerMinute) \
                breaths/min at confidence \(estimator.confidence). Beat jitter is not breathing; \
                the envelope veto must reject it regardless of how wide the acceptance band is.
                """)
        }
    }

    /// The interior of the band must be untouched — this change is an edge repair, not a
    /// retune. The first five rates are the ones the product actually targets (6 is the
    /// resonance rate `BioScienceInfo` cites) and were bit-identical in simulation before and
    /// after.
    ///
    /// ⛔ THE LAST TWO ARE HERE BECAUSE "BIT-IDENTICAL INSIDE THE BAND" WAS FALSE — see the ⛔ in
    /// the header. 4.25 and 24 are the two places the sweep says the repair reaches INWARD, and
    /// they are pinned at their post-#424 values so a later widening cannot quietly undo the
    /// improvement while the five untouched rates go on passing. Both got better (4.25:
    /// 0.4226 → 0.3661; 24: 4.9626 → 2.2217), so these two bounds would be RED on the pre-#424
    /// code — unlike the other five, which are green on both sides by construction.
    ///
    /// ⛔ THE BOUNDS BELOW ARE MEASURED, AND THE FIRST VERSION'S WERE NOT. It asserted a flat
    /// `< 1.0` at every rate "because the simulated worst was under 0.4", which was true of
    /// three of the five: the worst phase is 1.123/min at 15 and 2.190 at 20 — IDENTICAL
    /// before and after the widening, so a flat 1.0 would have gone red on the code it was
    /// written to protect and invited the fix of loosening it to 2.5 afterwards. Picking a
    /// threshold that your own change happens to clear is the failure mode this repo has paid
    /// for; these are per-rate, taken from the sweep, with a stated margin.
    ///
    /// They are therefore a "no worse than today" bound, not a quality claim: a test cannot
    /// compare against a value the code no longer produces, so "nothing moved" is enforced as
    /// "nothing got worse at any of the five rates the product cares about".
    func testInsideTheBandNothingMoved() {
        // rate : worst |error| over all 360 phases, simulated identically on both sides of
        // #424, + ~15 % margin.
        let measuredWorst: [(rate: Double, bound: Double)] = [
            (5.0, 0.42),     // measured 0.357  — identical before/after
            (6.0, 0.34),     // measured 0.285  — identical before/after
            (10.0, 0.40),    // measured 0.337  — identical before/after
            (15.0, 1.30),    // measured 1.123  — identical before/after
            (20.0, 2.55),    // measured 2.190  — identical before/after
            (4.25, 0.42),    // measured 0.366  — was 0.423, so this bound is red pre-#424
            (24.0, 2.55)     // measured 2.222  — was 4.963, so this bound is red pre-#424
        ]
        for (rate, bound) in measuredWorst {
            var worst = 0.0
            for phase in Self.sweptPhases {
                let e = Self.measure(breathsPerMinute: rate, phase: phase)
                XCTAssertGreaterThan(e.ratePerMinute, 0,
                                     "\(rate)/min at phase \(phase) went silent — the interior " +
                                     "of the band must be unaffected by an edge repair")
                worst = Swift.max(worst, abs(e.ratePerMinute - rate))
            }
            XCTAssertLessThan(worst, bound,
                              "\(rate)/min: worst phase off by \(worst)/min against a measured " +
                              "bound of \(bound). The interior was bit-identical across #424, " +
                              "so a failure here means the EMA is being fed periods it was not " +
                              "fed before — check the tolerance, not this number.")
        }
    }

    /// ⭐ THE SECOND COUNTERWEIGHT, and it replaced a test that could not fail. The first
    /// version of this file asserted `minRate <= rate <= maxRate` — a property a `clamped(to:)`
    /// call three lines away enforced unconditionally, so it could only go red in the one case
    /// the source scan also caught. Worse, the clamp it was pinning was itself the defect: a
    /// body breathing BELOW the band published `ratePerMinute` exactly 4.000 at 358 of 360
    /// phases (at 3.5/min), confidently, where before #424 it published at 37 and never at the
    /// boundary. A saturating output on a measurement path invents data at the rail, and
    /// `HealthWritePolicy.respiratoryRange` (4...40 then; 3.7...40 since #426) contains that rail — it would have reached
    /// Apple Health as a respiratory sample.
    ///
    /// So the property worth holding is not "inside the band" but "NOT PINNED TO THE BAND": a
    /// reported rate that lands exactly on a boundary across a whole sweep is a saturating
    /// output, not a measurement. The overshoot is bounded separately, from the sweep.
    func testTheReportedRateIsAMeasurementAndNotARail() {
        // Swept 4…30/min: max report above `maxRate` is 0.064/min, and nothing lands below
        // `minRate` at all. A hair over a boundary is honest; sitting ON it is not.
        let overshootAllowance = 0.15
        for rate in [RespirationEstimator.minRate, 6.0, 15.0, 24.0, RespirationEstimator.maxRate] {
            var atFloor = 0
            var atCeiling = 0
            var answered = 0
            for phase in Self.sweptPhases {
                let r = Self.measure(breathsPerMinute: rate, phase: phase).ratePerMinute
                guard r > 0 else { continue }
                answered += 1
                if r == RespirationEstimator.minRate { atFloor += 1 }
                if r == RespirationEstimator.maxRate { atCeiling += 1 }
                XCTAssertGreaterThan(r, RespirationEstimator.minRate - overshootAllowance,
                                     "\(rate)/min reported \(r) — further below the floor than " +
                                     "the swept \(overshootAllowance)/min allowance")
                XCTAssertLessThan(r, RespirationEstimator.maxRate + overshootAllowance,
                                  "\(rate)/min reported \(r) — further above the ceiling than " +
                                  "the swept \(overshootAllowance)/min allowance")
            }
            XCTAssertGreaterThan(answered, 0, "premise: \(rate)/min must answer at some phase")
            XCTAssertLessThanOrEqual(atFloor + atCeiling, 1, """
                \(rate)/min reported EXACTLY the band boundary at \(atFloor + atCeiling) of \
                \(answered) answering phases. An exact repeat of `minRate`/`maxRate` across a \
                sweep is a saturating output — the rail this test exists to prevent. A clamp \
                was reintroduced, or the tolerance grew far enough to admit bodies that are \
                genuinely outside the band.
                """)
        }
    }

    // MARK: - The shape, not the constant

    /// ⛔ ANCHOR FIRST, OR THIS SCAN CANNOT FAIL. The natural shape ("if the tolerance is
    /// present, check it") returns green on a file that lost the whole mechanism. So assert
    /// the tolerance EXISTS, then assert both halves of the shape it must produce.
    ///
    /// This is what stops a later session from "simplifying" the two bands back into one: the
    /// value may move, the shape may not.
    ///
    /// ⛔ AND IT ONLY CHECKS THE SHAPE — IT SAYS NOTHING ABOUT THE MAGNITUDE. `bandTolerance =
    /// 0.9` would satisfy every assertion here while INVERTING the design (accept narrower than
    /// you report). The name says "wider" and this scan cannot see that; the magnitude is held
    /// behaviourally instead, by the two edge tests (a tolerance below 1 puts 4/min and 30/min
    /// straight back into silence) and, for the pulse axis, by
    /// `TheBandHoldsAtEveryRestingPulseTests`. Saying so here is the point: a source scan that
    /// reads like more than it proves is how a green bundle certifies a property nobody measured.
    ///
    /// ⛔ AND THE SENTENCE ABOVE NAMED THE WRONG END FOR ONE COMMIT. It said the upper magnitude
    /// is held by `testTheReportedRateIsAMeasurementAndNotARail` "at the top end". Measured: the
    /// 30/min report saturates at 30.0345 for EVERY tolerance from 1.02 to 3.0 — the ceiling
    /// cannot go red however wide the band gets, so nothing up there constrains anything. The
    /// ceiling on the tolerance is at the FLOOR: a 4/min body reads 3.99993 up to 1.067 and drops
    /// to 3.8197 at 1.068, which is `testAWiderBandStillRejectsPeriodsThatAreNotTheCycle` in the
    /// pulse-axis file. Naming a bound is only useful if the named test can actually fail there.
    ///
    /// ⛔ AND `XCTAssertFalse` BELOW FORBIDS ONE SPELLING, NOT ONE BEHAVIOUR.
    /// `min(max(v, Self.minRate), Self.maxRate)` reintroduces the exact rail this file was
    /// written to retract and passes green — and that spelling is the one this repo's own
    /// NaN-order law would push a session towards. The behavioural half is
    /// `testTheReportedRateIsAMeasurementAndNotARail`; this line is a tripwire for the literal
    /// that was there, not a proof that no clamp exists.
    func testTheAcceptBandIsWiderThanTheReportBand() throws {
        let source = try estimatorSource()
        let code = codeOnly(source)
        XCTAssertTrue(code.contains("bandTolerance"), """
            `RespirationEstimator` no longer declares a band tolerance. If the two-band design \
            was deliberately reverted, re-derive this whole file — but read the two edge tests \
            above first: without it, 4/min is silent at two thirds of starting phases.
            """)
        XCTAssertTrue(code.contains("Self.minRate / Self.bandTolerance")
                        && code.contains("Self.maxRate * Self.bandTolerance"), """
            The acceptance test no longer divides/multiplies by the tolerance. Accepting on the \
            bare `minRate`/`maxRate` is the shipped-until-#424 behaviour and is what this file \
            exists to prevent.
            """)
        // ⛔ THE OPPOSITE OF WHAT THIS ASSERTION SAID FOR ONE COMMIT. It demanded
        // `clamped(to: Self.minRate...Self.maxRate)` on the reported rate, "so the published
        // contract is unchanged" — and that clamp is exactly what made a body outside the band
        // read as a confident rail on the boundary value (see the header ⛔ and
        // `testTheReportedRateIsAMeasurementAndNotARail`). The report is now the raw EMA, so
        // the clamp must NOT come back; the band claim is held by the no-rail test plus the
        // measured overshoot, not by saturating the output. Comments are stripped first, so
        // this ⛔ naming the forbidden expression cannot itself trip the scan.
        XCTAssertFalse(code.contains("clamped(to: Self.minRate...Self.maxRate)"), """
            The reported rate is clamped back into the advertised band again. That looks like \
            contract hygiene and is a fabrication: a breather outside the band then publishes \
            EXACTLY `minRate`/`maxRate` with full confidence, and \
            `HealthWritePolicy.respiratoryRange` (4...40 then; 3.7...40 since #426) contains those values, so the invented \
            number reaches Apple Health. Bound the overshoot instead — at the shipped tolerance \
            it is 0.064/min above `maxRate` at this fixture's 60 bpm pulse and 0.074 at 90.
            """)
    }

    // MARK: - Reading the source

    /// One definition for the whole bundle (#453). This was the shape eleven private copies
    /// diverged from; the shared one additionally refuses to treat a `//` or `/*` inside a
    /// string literal as a comment, which this file's own scans never needed and the next one
    /// might.
    private func codeOnly(_ text: String) -> String { SourceText.codeOnly(text) }

    private func estimatorSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root
            .appendingPathComponent("Sources/Echoelmusic/Bio/RespirationEstimator.swift")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("RespirationEstimator.swift not present — this scan cannot report green")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
