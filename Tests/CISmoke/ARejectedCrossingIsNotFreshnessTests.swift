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
// A **+89.5% error, certified**. Anchored on ACCEPTANCE, all 66 fall to confidence 0.000 and
// publish nothing — which is the honest answer: we cannot read this pace, so we say nothing
// rather than repeating the number the previous technique produced.
//
// ⛔ BOX IS NOT A COPY OF 4-7-8, AND THE FIRST TWO VERSIONS OF THIS HEADER BOTH GOT IT WRONG.
// The first said "Box the same (11 rejected crossings, confidence 1.000)" — an unqualified
// claim built from ONE pulse, in a file whose own `minRate` doc says a bound measured at one
// pulse is quoted with that pulse or not quoted. The second said the fix leaves box publishing
// "every one of them box's OWN rate". Swept over all 66 pulses: shipped, box publishes at 66/66
// and at **16 of them the number is the stale RESONANCE rate** (>5/min); with the fix it still
// publishes at **45/66** and the stale-resonance count is **0**. But those 45 read
// 3.8168…4.7743/min for a body pacing 3.7500 — **+1.8% to +27.3%, mean +8.8%**. So the fix
// removes the previous technique's number and does NOT make box accurate; the beat-quantisation
// error (#435) is a different, unfixed problem. `testTheSameHoldsForBox` asserts only the part
// that survives the sweep.
//
// ⚠️ THE WHOLE 4-7-8 / BOX RESULT IS HOSTAGE TO THE HOLD MODEL, and this is the limitation that
// matters most — it was missing from the first version and it is load-bearing. `BreathPattern
// .sample` returns a FLAT amplitude across `holdFull`/`holdEmpty`, so the driven heart rate is
// held flat through a hold and each cycle yields exactly one upward zero-crossing. CLAUDE.md's
// own #435 entry records the alternative as at-least-equally-plausible and UNMEASURED on device:
// with no respiratory drive during a hold the pulse RELAXES toward baseline, which adds a SECOND
// crossing per cycle — 4-7-8 would then imply ≈6.3/min, inside the band, accepted, published
// confidently and indistinguishable from resonance. Under that model every 4-7-8 crossing is
// accepted, #452 changes nothing, and both latch tests below go RED. That is not a reason to
// weaken them: it is the reason a strap take decides this, not a third model.
//
// ⚠️ THE SWEEP IS A MODEL AND IS NOT ASSERTED HERE, for the same reason #435 refused to assert
// its own: those numbers come from my transcription, and pinning them would pin the
// transcription rather than the product. Every threshold below is deliberately loose for the
// same reason. What this file asserts is what the SHIPPED type does when driven directly.
//
// ⚠️ AND WHAT IS NOT CLAIMED AT ALL: the ABOVE-band case — nor is the first version's REASON for
// that true. It blamed the smoothing ("merges cycles… settled at 27/min"). That described the
// transcription, which skipped `BreathPattern.init`. In the shipped type `minActiveSeconds = 1.0`
// clamps both legs, so the fixture built for the above-band case (1.0 s in / 0.9 s out) is
// constructed as 1.0/1.0 = exactly 30.0/min — under the 31.8 accept ceiling — and NO
// inhale+exhale `BreathPattern` can pace above 30/min at all. The above-band case is unreachable
// through this fixture type, not merely unmeasured. Do not cite this file for it, and do not send
// anyone to investigate the smoothing.

import Foundation
import XCTest
@testable import Echoelmusic

final class ARejectedCrossingIsNotFreshnessTests: XCTestCase {

    /// Beat-timed heart-rate samples whose instantaneous rate follows lung volume — the same
    /// RSA model `BreathPattern.sample` describes, and the only one this estimator is built for.
    /// Advances `est` in place and RETURNS THE WALL-CLOCK TIME REACHED, which is load-bearing:
    /// it is the `from:` argument of the second leg in every switch test below. (The first
    /// version of this line said "returns the estimator" — the estimator goes out via `inout`.
    /// A doc that contradicts the signature two lines under it is this repo's most-repeated
    /// defect, and it should not have appeared in a brand-new comment.)
    @discardableResult
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

    /// A symmetric inhale/exhale pattern at a given pace, for the band-edge counterweights.
    /// Goes through the real initialiser, so it inherits the same clamping the app applies.
    private func twoPhase(_ ratePerMinute: Double) -> BreathPattern {
        let half = (60.0 / ratePerMinute) / 2.0
        return BreathPattern(id: "test.twoPhase", name: "two phase", evidence: "test fixture",
                             segments: [.init(kind: .inhale, seconds: half),
                                        .init(kind: .exhale, seconds: half)])
    }

    private let restingPulses = Array(45...110)

    private func publishes(_ est: RespirationEstimator) -> Bool {
        // The publisher gate, both halves — `CameraRPPGBioPublisher` requires a rate AND the
        // confidence. Checking only confidence would call a rate-less estimator "publishing".
        est.confidence >= 0.4 && est.ratePerMinute > 0
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

        drive(&est, pattern: relaxing478, from: t1, seconds: 180, meanBPM: 60)

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

    /// Box is the other curated pattern below the band, and it fails DIFFERENTLY from 4-7-8
    /// (#435) — so the invariant asserted here is different too.
    ///
    /// ⛔ THE FIRST VERSION OF THIS TEST DROVE A SINGLE PULSE — 60 — AND PASSED FOR THE WRONG
    /// REASON. CLAUDE.md #435 already names 60 bpm as THE degenerate pulse for box (a 16 s cycle
    /// is exactly 16 beats, both quantisations land on 3.75, so everything is rejected and box
    /// behaves exactly like 4-7-8). Swept, the fixed estimator still publishes at 45 of 66
    /// pulses. So a green at pulse 60 was a property of the fixture, not of box — the #424
    /// lesson ("measure the other AXIS") applied to the counterweight in this file and withheld
    /// from the case it was written for.
    ///
    /// The invariant that survives the sweep is not "box goes silent": it is that box never
    /// publishes the PREVIOUS technique's number. Measured, that is 16 of 66 pulses before the
    /// fix and 0 of 66 after.
    func testTheSameHoldsForBox() throws {
        let resonance = try curated("resonance")
        let box = try curated("box")

        var offenders: [(pulse: Int, rate: Double)] = []
        var everPublished = 0
        var establishedAt = 0

        for pulse in restingPulses {
            var est = RespirationEstimator()
            let t1 = drive(&est, pattern: resonance, from: 0, seconds: 120, meanBPM: Double(pulse))
            guard publishes(est) else { continue }   // no stale rate was established here
            establishedAt += 1
            let stale = est.ratePerMinute

            drive(&est, pattern: box, from: t1, seconds: 180, meanBPM: Double(pulse))
            if publishes(est) {
                everPublished += 1
                // Box paces 3.75; the resonance leg paces 6.0. Anything at or above the midpoint
                // is the previous technique's number surviving, not a box measurement read high.
                let midpoint = (box.ratePerMinute + resonance.ratePerMinute) / 2
                if est.ratePerMinute >= midpoint { offenders.append((pulse, stale)) }
            }
        }

        XCTAssertGreaterThan(establishedAt, 40, """
            The resonance leg only established a rate at \(establishedAt) of \
            \(restingPulses.count) pulses, so most of this sweep proves nothing. Read that \
            before the assertion below.
            """)
        // Hoisted out of the message: a closure inside a string interpolation inside a
        // multi-line literal is the shape #287 made the blocking gate red with.
        let offendingPulses: [Int] = offenders.map { $0.pulse }
        let boxPace = String(format: "%.4f", box.ratePerMinute)
        XCTAssertTrue(offenders.isEmpty, """
            After 180 s of Box (paced \(boxPace)/min) the estimator is still publishing the \
            RESONANCE rate at pulses \(offendingPulses) — the latch #452 closed. Box publishing \
            its own (quantisation-inflated) number is expected and is not what this asserts; it \
            did so at \(everPublished) of \(restingPulses.count) pulses here.
            """)
    }

    // MARK: - The counterweights

    /// The fix must cost NOTHING to a take that stays comfortably inside the band. This is the
    /// assertion that would go red if somebody "simplified" the anchor into something stricter
    /// than acceptance — e.g. requiring a crossing every cycle.
    func testAnInBandTakeIsUnaffected() throws {
        for id in ["resonance", "coherent"] {
            let p = try curated(id)
            var est = RespirationEstimator()
            drive(&est, pattern: p, from: 0, seconds: 300, meanBPM: 60)

            // 0.01 rather than the 0.25 the first version used: the measured error at this pulse
            // is 0.0003, so 0.25 was ~830x the signal and could not fail for its stated reason.
            XCTAssertEqual(est.ratePerMinute, p.ratePerMinute, accuracy: 0.01, """
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

    /// Both ENDS of the band, because the defect happened to involve one rate near the middle
    /// and "costs nothing in band" was asserted from it twice.
    ///
    /// ⚠️ THE LOW END IS 4.00, NOT THE ACTUAL FLOOR, and that is deliberate and measured: the
    /// accept floor is `minRate / bandTolerance` = 3.7736, and the fix genuinely DOES change the
    /// sliver just above it (3.78/min publishes at 64 of 66 pulses before and 51 after; 3.80 goes
    /// 66 → 58). Those silenced readings were +2.8%…+8.3% wrong, so the direction is right — but
    /// asserting "nothing changes" there would be false. #426 widened `HealthWritePolicy` down to
    /// 3.7 to admit exactly that sliver, so the cost is real and is written down rather than
    /// tested away.
    ///
    /// ⚠️ AND THE FAST END DOES NOT REACH 66 EVEN WITHOUT THIS FIX: at 28/min three pulses
    /// (56, 57, 58) fail to publish in BOTH variants — beat quantisation at the fast edge, older
    /// than #452. The floor here is set well under the measured 63 for the reason in the header:
    /// these counts come from a transcription, and a tight count would pin the transcription.
    func testTheFixIsFreeAtBothEndsOfTheBand() {
        for rate in [4.0, 28.0] {
            let p = twoPhase(rate)
            var published = 0
            for pulse in restingPulses {
                var est = RespirationEstimator()
                drive(&est, pattern: p, from: 0, seconds: 300, meanBPM: Double(pulse))
                if publishes(est) { published += 1 }
            }
            XCTAssertGreaterThanOrEqual(published, 50, """
                A steady \(rate)/min breather — inside the estimator's own reportable range \
                \(RespirationEstimator.reportableRange) — cleared the publisher gate at only \
                \(published) of \(restingPulses.count) resting pulses. Whatever tightened the \
                freshness anchor went past "reject what the band rejected".
                """)
        }
    }

    /// Sweeping the counterweight, because a single pulse is a fixture and the defect this
    /// guards against (an over-strict anchor) would bite at some pulses and not others — the
    /// #424 lesson about measuring the other axis. All 66, not a stride: the method name says
    /// "AtEveryRestingPulse", and the first version sampled 14.
    func testTheInBandTakeSurvivesAtEveryRestingPulse() throws {
        let resonance = try curated("resonance")
        var failures: [Int] = []
        for pulse in restingPulses {
            var est = RespirationEstimator()
            drive(&est, pattern: resonance, from: 0, seconds: 300, meanBPM: Double(pulse))
            if !publishes(est) { failures.append(pulse) }
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
    ///
    /// ⚠️ This one is GREEN on both sides of #452 — it is documentation of the reason the fix is
    /// safe, not a regression. Said out loud because the sibling guards in this bundle say it and
    /// a file where every test looks like a regression invites the wrong kind of trust.
    func testAFreshEstimatorPublishesNothing() {
        let est = RespirationEstimator()
        XCTAssertEqual(est.ratePerMinute, 0, "A fresh estimator claims a rate it never measured.")
        XCTAssertEqual(est.confidence, 0, "A fresh estimator claims confidence in nothing.")
        XCTAssertEqual(est.amplitude, 0.5, accuracy: 1e-9,
                       "A fresh estimator's ball should rest mid-travel, not at an extreme.")
    }

    // MARK: - The wiring

    /// The anchor must be a DIFFERENT variable from the crossing baseline, and freshness must
    /// actually READ the anchor. Both are needed: `lastCrossT` is what the next period is
    /// measured against (accepted or not), `lastAcceptT` is what staleness is measured from.
    ///
    /// ⛔ THE FIRST VERSION OF THIS TEST COULD NOT FAIL FOR THE REASON IT STATED — #367, in the
    /// one file in this bundle whose subject is a term that silently stopped meaning what its
    /// name said. It asserted three NAMES: that `lastAcceptT` appears, that `rawSinceAccept`
    /// appears, that `rawSinceCross` does not. The reviewer restored the whole latch with a
    /// one-token edit — `let rawSinceAccept = lastCrossT.map { … }`, leaving the declaration and
    /// the assignment in place — and all three passed. The failure message said "If freshness
    /// went back to reading `lastCrossT`, the latch is back"; that is exactly what it could not
    /// see. A guard over a variable must assert the BINDING, not the vocabulary.
    func testTheAnchorIsSeparateFromThePeriodBaseline() throws {
        let code = try estimatorSource()

        XCTAssertTrue(code.contains("rawSinceAccept = lastAcceptT"), """
            The freshness term no longer reads the acceptance anchor. If it went back to \
            `lastCrossT`, the latch is back: a rejected crossing would refresh the staleness \
            clock and certify the previous technique's rate indefinitely. This asserts the \
            BINDING and not the name, because asserting the name is what let the defect back in \
            under an earlier version of this test.
            """)
        XCTAssertTrue(code.contains("lastAcceptT = t"), """
            Nothing assigns the acceptance anchor any more. A `lastAcceptT` that is declared, \
            read, and never written pins freshness at its nil branch — silently inert, and green \
            on every other assertion in this file.
            """)
        XCTAssertTrue(code.contains("lastCrossT"), """
            The period baseline is gone. Collapsing the two the OTHER way — measuring the next \
            period from the last ACCEPTED crossing — is a different defect, not a simplification: \
            every rejected cycle would then be folded into the next period measurement.
            """)
    }

    /// Comment-stripped source of the estimator, or a skip when the tree is not present.
    ///
    /// ⚠️ This is the second copy of `TheBandEdgeIsMeasurableTests.codeOnly` in this bundle,
    /// which is the #416 shape — that one is `private`, so sharing it means hoisting it into a
    /// bundle-level helper, and that is a separate slice (#453), not a drive-by edit to a
    /// neighbouring guard. It strips TRAILING `//` comments as well as whole comment lines, and
    /// that half is load-bearing rather than cosmetic: a future trailing comment mentioning a
    /// forbidden token would trip a negative assertion on prose (the #404 trap, one file over).
    private func estimatorSource() throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent("Sources/Echoelmusic/Bio/RespirationEstimator.swift")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return try String(contentsOf: path, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                let trimmed = line.drop { $0 == " " }
                if trimmed.hasPrefix("//") { return "" }
                guard let slashes = line.range(of: "//") else { return line }
                return line[line.startIndex..<slashes.lowerBound]
            }
            .joined(separator: "\n")
    }
}
