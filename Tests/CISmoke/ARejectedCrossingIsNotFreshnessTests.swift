// ARejectedCrossingIsNotFreshnessTests.swift
// Echoel — #452. The guard over a latch that publishes the PREVIOUS technique's breath rate,
// at full confidence, while the body breathes something the band cannot read.
//
// THE DEFECT. `RespirationEstimator.ingest` set `lastCrossT = t` OUTSIDE the accept branch,
// and `refreshConfidence` measured staleness from `lastCrossT`. `ratePerMinute` holds its last
// ACCEPTED value forever (the file says so at the declaration). So a body whose breathing
// produces crossings the band REJECTS kept the freshness anchor moving: staleness stayed at
// zero, freshness stayed pinned at 1.0, and the old rate went on being certified.
//
// ⭐ THIS IS THE THIRD LATCH IN ONE FILE, and the file already names the other two — the
// freshness term ("catches the take that ends in a flat trace") and the envelope veto
// ("catches the take that ends in a NOISY one"), with its own comment saying each "is HALF the
// answer" and that neither substitutes for the other. Both halves are about a trace that
// DEGRADES. This third case is a trace that stays perfectly clean and simply moves outside the
// band: the envelope is healthy so the veto is silent, and the anchor kept advancing so
// freshness never fired. A taxonomy with two cases is not a proof that there are two.
//
// ⭐ AND THE TRIGGER IS A PATTERN ECHOEL ITSELF PACES. `BreathPattern.curated` offers Box at
// 3.75/min and 4-7-8 at 3.158/min, both BELOW `reportableRange` (#435). Transcribing `ingest`
// and `refreshConfidence` line-for-line and driving them from `BreathPattern.sample` — 120 s of
// resonance, then 180 s of 4-7-8 — at ALL 66 integer resting pulses 45…110 the estimator
// published a mean **5.985/min at confidence exactly 1.000** while the body breathed 3.158.
// A **+89.5% error, certified**. Box the same (11 rejected crossings, confidence 1.000).
// Anchored on ACCEPTANCE, all 66 fall to confidence 0.000 and publish nothing — which is the
// honest answer: we cannot read this pace, so we say nothing rather than repeating the number
// the previous technique produced.
//
// ⚠️ THE SWEEP IS A MODEL AND IS NOT ASSERTED HERE, for the same reason #435 refused to assert
// its own: those numbers come from my transcription, and pinning them would pin the
// transcription rather than the product. What this file asserts is what the SHIPPED type does
// when driven directly.
//
// ⚠️ AND WHAT IS NOT CLAIMED AT ALL: the ABOVE-band case. The fixture built for it (1.0 s in /
// 0.9 s out, 31.6/min) never produced a rejected crossing — the smoothing merges cycles and the
// estimator settled at 27/min, inside the band. An above-band latch is plausible by the same
// argument and is UNMEASURED. Do not cite this file for it.

import Foundation
import XCTest
@testable import Echoelmusic

final class ARejectedCrossingIsNotFreshnessTests: XCTestCase {

    /// Beat-timed heart-rate samples whose instantaneous rate follows lung volume — the same
    /// RSA model `BreathPattern.sample` describes, and the only one this estimator is built for.
    /// Returns the estimator after `seconds` of breathing `pattern` starting at cycle time 0.
    private func drive(_ est: inout RespirationEstimator,
                       pattern: BreathPattern,
                       from t0: Double,
                       seconds: Double,
                       meanBPM: Double,
                       swing: Double = 3.0) -> Double {
        var t = t0
        let end = t0 + seconds
        while t < end {
            let a = pattern.sample(atCycleTime: t - t0).amplitude
            let hr = meanBPM + swing * (2 * a - 1)
            est.ingest(heartRate: hr, at: t)
            t += 60.0 / hr
        }
        return t
    }

    private func curated(_ id: String) throws -> BreathPattern {
        try XCTUnwrap(BreathPattern.curated.first { $0.id == id },
                      "No curated pattern with id \(id).")
    }

    // MARK: - The latch itself

    /// THE REGRESSION. Red on the shipped code before #452: it published ~6/min at confidence
    /// 1.000 for a body breathing 3.16/min.
    func testSwitchingToAnUnreadablePaceStopsCertifyingTheOldRate() throws {
        let resonance = try curated("resonance")
        let relaxing478 = try curated("relaxing478")

        var est = RespirationEstimator()
        let t1 = drive(&est, pattern: resonance, from: 0, seconds: 120, meanBPM: 60)

        // The in-band half must have worked, or the test below proves nothing.
        XCTAssertGreaterThan(est.ratePerMinute, 0, """
            The resonance half measured nothing, so the "stale rate" this test is about was \
            never established. Fix that before reading the assertion below.
            """)
        XCTAssertGreaterThanOrEqual(est.confidence, 0.4,
                                    "Resonance did not reach the publisher gate; see above.")
        let staleRate = est.ratePerMinute

        _ = drive(&est, pattern: relaxing478, from: t1, seconds: 180, meanBPM: 60)

        // `ratePerMinute` is DOCUMENTED to hold its last accepted value, so it is expected to
        // still read ~6. What must not survive is the CONFIDENCE that certifies it.
        XCTAssertLessThan(est.confidence, 0.4, """
            After 180 s of 4-7-8 (paced \(String(format: "%.4f", relaxing478.ratePerMinute))/min, \
            below RespirationEstimator.reportableRange) the estimator still certifies \
            \(String(format: "%.4f", est.ratePerMinute))/min at confidence \
            \(String(format: "%.4f", est.confidence)) — the rate the PREVIOUS pattern produced \
            (\(String(format: "%.4f", staleRate))). Every crossing in that stretch was rejected \
            by the band, and a rejected crossing must not refresh the freshness anchor: it is \
            evidence AGAINST the held rate, never for it.
            """)
    }

    /// Box is the other curated pattern below the band, and it fails differently from 4-7-8
    /// (#435) — so it gets its own case rather than being assumed equivalent.
    func testTheSameHoldsForBox() throws {
        let resonance = try curated("resonance")
        let box = try curated("box")

        var est = RespirationEstimator()
        let t1 = drive(&est, pattern: resonance, from: 0, seconds: 120, meanBPM: 60)
        XCTAssertGreaterThanOrEqual(est.confidence, 0.4, "Resonance half did not establish a rate.")
        _ = drive(&est, pattern: box, from: t1, seconds: 180, meanBPM: 60)

        XCTAssertLessThan(est.confidence, 0.4, """
            After 180 s of Box (paced \(String(format: "%.4f", box.ratePerMinute))/min) the \
            estimator still certifies \(String(format: "%.4f", est.ratePerMinute))/min at \
            confidence \(String(format: "%.4f", est.confidence)).
            """)
    }

    // MARK: - The counterweights

    /// The fix must cost NOTHING to a take that stays inside the band. This is the assertion
    /// that would go red if somebody "simplified" the anchor into something stricter than
    /// acceptance — e.g. requiring a crossing every cycle.
    func testAnInBandTakeIsUnaffected() throws {
        for id in ["resonance", "coherent"] {
            let p = try curated(id)
            var est = RespirationEstimator()
            _ = drive(&est, pattern: p, from: 0, seconds: 300, meanBPM: 60)

            XCTAssertEqual(est.ratePerMinute, p.ratePerMinute, accuracy: 0.25, """
                \(id) paces \(p.ratePerMinute)/min and the estimator reports \
                \(est.ratePerMinute). The in-band path moved.
                """)
            XCTAssertGreaterThanOrEqual(est.confidence, 0.4, """
                \(id) is squarely readable and the estimator no longer clears the publisher \
                gate (confidence \(est.confidence)). Anchoring freshness on acceptance must not \
                cost an in-band take anything.
                """)
        }
    }

    /// Sweeping the counterweight, because a single pulse is a fixture and the defect this
    /// guards against (an over-strict anchor) would bite at some pulses and not others — the
    /// #424 lesson about measuring the other axis.
    func testTheInBandTakeSurvivesAtEveryRestingPulse() throws {
        let resonance = try curated("resonance")
        var failures: [Int] = []
        for pulse in stride(from: 45, through: 110, by: 5) {
            var est = RespirationEstimator()
            _ = drive(&est, pattern: resonance, from: 0, seconds: 300, meanBPM: Double(pulse))
            if est.confidence < 0.4 || est.ratePerMinute <= 0 { failures.append(pulse) }
        }
        XCTAssertTrue(failures.isEmpty, """
            Resonance breathing — the pattern this whole product is about — stopped clearing the \
            publisher gate at pulses \(failures). Whatever tightened the freshness anchor went \
            past "reject what the band rejected".
            """)
    }

    /// A fresh estimator must be inert, and the reason is worth pinning: before the first
    /// ACCEPTED crossing `ratePerMinute` is 0, so the publisher gate cannot pass no matter what
    /// confidence does. Widening the inert window by one crossing (#452) therefore cannot
    /// change any published value.
    func testAFreshEstimatorPublishesNothing() {
        let est = RespirationEstimator()
        XCTAssertEqual(est.ratePerMinute, 0, "A fresh estimator claims a rate it never measured.")
        XCTAssertEqual(est.confidence, 0, "A fresh estimator claims confidence in nothing.")
        XCTAssertEqual(est.amplitude, 0.5, accuracy: 1e-9,
                       "A fresh estimator's ball should rest mid-travel, not at an extreme.")
    }

    // MARK: - The wiring

    /// The anchor must be a DIFFERENT variable from the crossing baseline. Both are needed:
    /// `lastCrossT` is what the next period is measured against (accepted or not), `lastAcceptT`
    /// is what staleness is measured from. Collapsing them either way reintroduces a defect —
    /// one direction is this latch, the other makes every rejected cycle restart the period.
    func testTheAnchorIsSeparateFromThePeriodBaseline() throws {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent("Sources/Echoelmusic/Bio/RespirationEstimator.swift")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        let code = try String(contentsOf: path, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        XCTAssertTrue(code.contains("lastAcceptT"), """
            RespirationEstimator no longer has a separate acceptance anchor. If freshness went \
            back to reading `lastCrossT`, the latch is back: a rejected crossing would refresh \
            the staleness clock and certify the previous technique's rate indefinitely.
            """)
        XCTAssertTrue(code.contains("rawSinceAccept"), """
            The staleness value is no longer named for what it measures. This file's own doc \
            calls that the stale-name trap it already paid for once (#373/#374).
            """)
        XCTAssertFalse(code.contains("rawSinceCross"), """
            `rawSinceCross` is back in the code — the freshness term is measuring the age of ANY \
            crossing again, not of an accepted measurement.
            """)
    }
}
