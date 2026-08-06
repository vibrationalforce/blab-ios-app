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
// At every rate strictly inside the band the behaviour is bit-identical. The defect is
// entirely a band-edge artefact, and the LOW edge — which nobody had looked at, including the
// review that found this — is four times worse than the high one.
//
// ⭐ THE FIX, in one sentence: ACCEPT into a wider band than you REPORT. Acceptance now uses
// `[minRate / bandTolerance, maxRate * bandTolerance]`; the reported `ratePerMinute` is clamped
// to `[minRate, maxRate]`, so the published contract is unchanged. A measurement at 30.4/min is
// a 30/min breath with jitter, not nonsense — refusing it is not conservative, it is blind.
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
//   · The `tolerance` value (1.2) is a judgement, not a derivation. What is derived is the
//     SHAPE: accept-band ⊋ report-band. The tests below pin the shape and the two edges, not
//     the constant — a later session may widen or narrow it and only the source-scan test
//     will notice, deliberately.
//   · Nothing here says the reading at the edge is GOOD. At 30/min the RMS error is 1.19/min
//     after the fix (8.52 before, dominated by the zeros). It says the estimator answers
//     instead of going silent.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBandEdgeIsMeasurableTests: XCTestCase {

    private struct Beat { let time: Double; let heartRate: Double }

    /// Deliberately a private copy of the generator in
    /// `ResonanceBreathingNeedsMoreThanOneWindowTests` rather than a shared helper: these two
    /// files pin different properties of the same struct, and a shared fixture means a tweak
    /// for one silently moves the other's numbers. The duplication is eleven lines.
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
    /// retune. These are the rates the product actually targets (6 is the resonance rate
    /// `BioScienceInfo` cites), and all five were bit-identical in simulation before and after.
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
            (5.0, 0.42),     // measured 0.357
            (6.0, 0.34),     // measured 0.285
            (10.0, 0.40),    // measured 0.337
            (15.0, 1.30),    // measured 1.123
            (20.0, 2.55)     // measured 2.190
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

    /// The published contract is `[minRate, maxRate]`. Accepting wider must never leak a
    /// wider REPORT — that would silently change what every consumer of
    /// `/echoelmusic/bio/breath/rate` receives.
    func testTheReportedRateNeverLeavesTheAdvertisedBand() {
        for rate in [RespirationEstimator.minRate, 6.0, 15.0, RespirationEstimator.maxRate] {
            for phase in Self.sweptPhases {
                let r = Self.measure(breathsPerMinute: rate, phase: phase).ratePerMinute
                guard r > 0 else { continue }
                XCTAssertGreaterThanOrEqual(r, RespirationEstimator.minRate,
                                            "reported \(r)/min, below the advertised floor")
                XCTAssertLessThanOrEqual(r, RespirationEstimator.maxRate,
                                         "reported \(r)/min, above the advertised ceiling")
            }
        }
    }

    // MARK: - The shape, not the constant

    /// ⛔ ANCHOR FIRST, OR THIS SCAN CANNOT FAIL. The natural shape ("if the tolerance is
    /// present, check it") returns green on a file that lost the whole mechanism. So assert
    /// the tolerance EXISTS, then assert both halves of the shape it must produce.
    ///
    /// This is what stops a later session from "simplifying" the two bands back into one: the
    /// value may move, the shape may not.
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
        XCTAssertTrue(code.contains("clamped(to: Self.minRate...Self.maxRate)"), """
            The reported rate is no longer clamped to the advertised band. Accepting wider \
            without clamping the report changes the published contract of \
            `/echoelmusic/bio/breath/rate`. (Comments are stripped before this scan, so a \
            mention of the clamp in prose cannot satisfy it — the expression has to be there.)
            """)
    }

    // MARK: - Reading the source

    private func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                let trimmed = line.drop { $0 == " " }
                if trimmed.hasPrefix("//") { return "" }
                guard let slashes = line.range(of: "//") else { return line }
                return line[line.startIndex..<slashes.lowerBound]
            }
            .joined(separator: "\n")
    }

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
