//
//  RRIntervalHygieneTests.swift
//  Echoelmusic — artifact rejection for the trusted (chest-strap) HRV path.
//
//  The strap is the one source whose HRV we display as real milliseconds and the only
//  one allowed to drive frequency-domain coherence — and until now it was the only one
//  with no artifact rejection at all, while the UNTRUSTED camera path did IQR outlier
//  cleaning. These tests pin the filter and, more importantly, the segment discipline:
//  RMSSD reads successive pairs, so simply deleting a bad beat and closing the gap
//  recreates the artifact you just removed.
//

import XCTest
@testable import Echoelmusic

final class RRIntervalHygieneTests: XCTestCase {

    private typealias H = RRIntervalHygiene

    // MARK: - Plausibility band

    func testImplausibleIntervalsAreRejected() {
        // 250 ms ≈ 240 bpm and 2500 ms ≈ 24 bpm are dropped/doubled packets, not beats.
        let raw = [900.0, 250.0, 900.0, 2500.0, 900.0]
        XCTAssertEqual(H.accepted(rrMs: raw), [900.0, 900.0, 900.0])
    }

    func testNonFiniteIntervalIsRejectedRatherThanPoisoningTheMetrics() {
        // One NaN through to RMSSD makes every downstream number NaN — brightness,
        // humanisation and the displayed ms figure all at once.
        let segments = H.acceptedSegments(rrMs: [880.0, .nan, 880.0, .infinity, 880.0])
        XCTAssertFalse(HRVMetrics.rmssd(segments: segments).isNaN)
        XCTAssertEqual(H.accepted(rrMs: [880.0, .nan, 880.0]), [880.0, 880.0])
    }

    func testTheBandBoundariesThemselvesAreAccepted() {
        XCTAssertEqual(H.accepted(rrMs: [H.minPlausibleMs]), [H.minPlausibleMs])
        XCTAssertEqual(H.accepted(rrMs: [H.maxPlausibleMs]), [H.maxPlausibleMs])
    }

    // MARK: - Malik ectopic rule

    func testASingleEctopicBeatIsRejectedAndItsCompensatoryPauseIsIsolated() {
        // The classic signature: a premature (short) beat, then a compensatory long one.
        // The short beat is >20 % from its predecessor and is dropped.
        //
        // The long one is NOT dropped, and that is deliberate rather than a miss: the
        // rejection cleared the anchor, so the pause starts a fresh run. It is a beat the
        // heart really made — the flash it fires is honest, just late. Rejecting it
        // instead would mean judging post-gap beats against a stale pre-gap anchor, which
        // is exactly what locks the filter out during a real rate change.
        //
        // ⚠ In THIS record the pause lands alone between two gaps, so it forms a length-1
        // segment and contributes no successive difference. Do NOT generalise that to
        // "RMSSD never sees a compensatory pause" — an earlier version of this comment
        // did, and it is false. It only holds when the beat AFTER the pause is also >20 %
        // from it (1100→800 = 27 %, so it is here). With a shallower return — 1000 ·
        // premature 600 · pause 1200 · return 1000 — the return is only 16.7 % from the
        // pause and is ACCEPTED, so the segment [1200, 1000] feeds a fabricated 200 ms
        // difference straight into RMSSD.
        //
        // Note also the collateral: the 5th interval is a perfectly genuine 800 ms beat,
        // and it is discarded because it is measured against the pause.
        let raw = [800.0, 800.0, 500.0, 1100.0, 800.0, 800.0]
        let segments = H.acceptedSegments(rrMs: raw)
        XCTAssertFalse(H.accepted(rrMs: raw).contains(500.0))
        XCTAssertEqual(segments, [[800.0, 800.0], [1100.0], [800.0]])
        // True RMSSD of this record is 0: every genuine consecutive pair is 800→800.
        XCTAssertEqual(HRVMetrics.rmssd(segments: segments), 0, accuracy: 1e-9)
        // Unfiltered it reports √(540000/5) ≈ 328.6 ms — the inflation this exists to
        // stop, and the number the app used to print as a real measurement.
        XCTAssertEqual(HRVMetrics.rmssd(rrMs: raw), 328.63, accuracy: 0.01)
    }

    func testTheShallowReturnCaseThatSlipsThrough() {
        // The counter-example named above, pinned so the limitation is documented in code
        // rather than in a comment nobody re-derives. A single ectopic CAN still leave one
        // fabricated successive difference when the return to baseline is within 20 % of
        // the compensatory pause.
        let raw = [1000.0, 1000.0, 600.0, 1200.0, 1000.0, 1000.0]
        let segments = H.acceptedSegments(rrMs: raw)
        XCTAssertEqual(segments, [[1000.0, 1000.0], [1200.0, 1000.0, 1000.0]],
                       "the shallow return is accepted against the pause — known limitation "
                       + "of the previous-beat Malik variant")
        // √(40000/3) ≈ 115.5 ms, all of it from the single 1200→1000 step.
        XCTAssertGreaterThan(HRVMetrics.rmssd(segments: segments), 100)
    }

    func testIsolatedBeatsAreExcludedFromSDNN() {
        // A length-1 segment is by construction "an interval with a rejection on both
        // sides" — in practice the compensatory pause. Pooling it into SDNN is NOT
        // negligible: one 1100 ms pause among flat 800 ms beats fabricates ~39 ms of
        // spread out of a true ~0. (An earlier comment of mine called that negligible;
        // it is wrong by an order of magnitude.)
        var raw = [Double](repeating: 800.0, count: 8)
        raw.insert(contentsOf: [400.0, 1100.0], at: 4)   // ectopic + isolated pause
        let segments = H.acceptedSegments(rrMs: raw)
        XCTAssertTrue(segments.contains([1100.0]), "precondition: the pause is isolated")
        XCTAssertEqual(HRVMetrics.sdnn(segments: segments), 0, accuracy: 1e-9,
                       "the isolated pause must not manufacture spread out of flat beats")
    }

    func testRespiratorySinusArrhythmiaSurvives() {
        // This is the whole point of biofeedback — breathing-driven beat-to-beat swing
        // MUST pass. A filter tight enough to remove it would flatten the signal we
        // exist to show. ±8 % here, well inside the 20 % rule.
        let raw = [820.0, 860.0, 890.0, 870.0, 830.0, 800.0, 780.0, 810.0]
        XCTAssertEqual(H.accepted(rrMs: raw), raw)
    }

    func testASustainedRateChangeIsNotLockedOut() {
        // Standing up / starting to move ramps the rate. Each STEP stays inside 20 %, so
        // the anchor follows the body instead of freezing at the old resting value.
        var raw: [Double] = []
        var rr = 1000.0
        for _ in 0..<12 { raw.append(rr); rr *= 0.90 }   // 10 % per beat, ~1000 → ~314 ms
        // 12 is deliberate, not arbitrary: a 13th interval would be 282 ms, under
        // `minPlausibleMs`, and the test would then fail on the BAND rather than on the
        // Malik rule it is here to exercise. Keep the last value above 300 ms.
        XCTAssertGreaterThan(raw.last ?? 0, H.minPlausibleMs)
        XCTAssertEqual(H.accepted(rrMs: raw).count, raw.count,
                       "a genuine rate ramp must not be filtered away as artifact")
    }

    func testRejectionReAnchors_soOneBadBeatDoesNotKillEverythingAfterIt() {
        // After a rejection the gate forgets its anchor: the next plausible beat starts a
        // fresh run. Without that, a body that settled at a new rate would be rejected
        // forever against a stale pre-gap value.
        let raw = [1000.0, 1000.0, 400.0, 600.0, 600.0, 600.0]
        let accepted = H.accepted(rrMs: raw)
        XCTAssertEqual(accepted, [1000.0, 1000.0, 600.0, 600.0, 600.0])
    }

    // MARK: - Segment discipline (the part that is easy to get wrong)

    func testGapIsNotClosed_soRMSSDDoesNotInventASuccessiveDifference() {
        // Steady 800 ms, one implausible packet, steady 800 ms again. True RMSSD is 0.
        // Deleting the bad beat and flattening would pair 800 with 800 across the gap —
        // which happens to be harmless here — so the sharper case is a rate CHANGE
        // across the gap, tested below. This one pins the baseline.
        let raw = [800.0, 800.0, 2500.0, 800.0, 800.0]
        let segments = H.acceptedSegments(rrMs: raw)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(HRVMetrics.rmssd(segments: segments), 0, accuracy: 1e-9)
    }

    func testFlatteningAcrossAGapWouldFabricateVariability() {
        // 1000 ms run, a dropout, then a settled 600 ms run. Within each run the beats
        // are identical, so the honest RMSSD is 0. Naively concatenating the survivors
        // pairs 1000 with 600 and reports a large spurious value — this asserts the
        // difference, so nobody "simplifies" the segments back into one array.
        let raw = [1000.0, 1000.0, 1000.0, 2500.0, 600.0, 600.0, 600.0]
        let segments = H.acceptedSegments(rrMs: raw)
        XCTAssertEqual(HRVMetrics.rmssd(segments: segments), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(HRVMetrics.rmssd(rrMs: segments.flatMap { $0 }), 100,
                             "the flattened form is exactly the artifact we are avoiding")
    }

    func testPNN50AlsoRespectsSegmentBoundaries() {
        let raw = [1000.0, 1000.0, 1000.0, 2500.0, 600.0, 600.0, 600.0]
        let segments = H.acceptedSegments(rrMs: raw)
        XCTAssertEqual(HRVMetrics.pnn50(segments: segments), 0, accuracy: 1e-9)
    }

    func testSDNNPoolsAcrossSegments_becauseASpreadHasNoAdjacencyRequirement() {
        let raw = [1000.0, 1000.0, 2500.0, 600.0, 600.0]
        let segments = H.acceptedSegments(rrMs: raw)
        XCTAssertEqual(HRVMetrics.sdnn(segments: segments),
                       HRVMetrics.sdnn(rrMs: [1000.0, 1000.0, 600.0, 600.0]), accuracy: 1e-9)
    }

    func testCleanSeriesIsUntouched_soTheFilterCostsNothingWhenTheStrapIsGood() {
        let raw = [812.0, 828.0, 841.0, 833.0, 820.0]
        let segments = H.acceptedSegments(rrMs: raw)
        XCTAssertEqual(segments, [raw])
        XCTAssertEqual(HRVMetrics.rmssd(segments: segments),
                       HRVMetrics.rmssd(rrMs: raw), accuracy: 1e-9)
        XCTAssertEqual(HRVMetrics.pnn50(segments: segments),
                       HRVMetrics.pnn50(rrMs: raw), accuracy: 1e-9)
    }

    func testEmptyAndSingleBeatInputsAreSafe() {
        XCTAssertTrue(H.acceptedSegments(rrMs: []).isEmpty)
        XCTAssertEqual(HRVMetrics.rmssd(segments: []), 0)
        XCTAssertEqual(HRVMetrics.pnn50(segments: []), 0)
        XCTAssertEqual(HRVMetrics.sdnn(segments: []), 0)
        // A lone interval carries no successive difference but is a valid NN interval.
        XCTAssertEqual(H.acceptedSegments(rrMs: [850.0]), [[850.0]])
        XCTAssertEqual(HRVMetrics.rmssd(segments: [[850.0]]), 0)
    }

    // MARK: - Quality signal + the HR field

    func testAcceptedFractionReportsContactQualityHonestly() {
        XCTAssertEqual(H.acceptedFraction(rrMs: []), 1, accuracy: 1e-9)
        XCTAssertEqual(H.acceptedFraction(rrMs: [800.0, 800.0, 800.0, 800.0]), 1, accuracy: 1e-9)
        XCTAssertLessThan(H.acceptedFraction(rrMs: [800.0, 2500.0, 250.0, 800.0]), 0.75)
    }

    func testHRVIsWithheldWhenTooMuchOfTheRecordWasRejected() {
        // Filtering is not free: what survives had its LARGEST differences preferentially
        // removed, and the coherence spectrum is built from a spliced record. Past a
        // rejection rate the numbers stop meaning what they look like, and the publisher
        // must show "—" rather than a confident figure. The sharpest case is atrial
        // fibrillation: RR steps there routinely exceed the Malik threshold, so most beats
        // are discarded and a LOW variability would be displayed where the physiological
        // truth is extremely high.
        let good = [Double](repeating: 800.0, count: 40)
        XCTAssertTrue(H.canStateHRV(rrMs: good))

        // One stray ectopic in a full window must NOT withhold — that is normal life.
        var oneEctopic = good
        oneEctopic.insert(400.0, at: 20)
        XCTAssertTrue(H.canStateHRV(rrMs: oneEctopic),
                      "a single artifact in ~40 beats must not blank the readout")

        // A wildly irregular record must.
        let irregular = (0..<40).map { $0 % 2 == 0 ? 500.0 : 1200.0 }
        XCTAssertLessThan(H.acceptedFraction(rrMs: irregular), H.minAcceptedFractionForHRV)
        XCTAssertFalse(H.canStateHRV(rrMs: irregular))
    }

    func testImplausibleHeartRateFieldIsRejected() {
        // The strap transmits HR separately from the RR intervals, so it can arrive
        // corrupted on its own. The old gate was only `> 0`, which passed 255.
        XCTAssertTrue(H.isPlausibleBPM(60))
        XCTAssertTrue(H.isPlausibleBPM(H.minPlausibleBPM))
        XCTAssertTrue(H.isPlausibleBPM(H.maxPlausibleBPM))
        XCTAssertFalse(H.isPlausibleBPM(0))
        XCTAssertFalse(H.isPlausibleBPM(255))
        XCTAssertFalse(H.isPlausibleBPM(-1))
    }

    // MARK: - The streaming gate is the same decision as the windowed pass

    func testStreamingGateAgreesWithTheWindowedPass() {
        // The live beat-event path runs a `Gate` per arriving beat; the publish loop runs
        // `acceptedSegments` over the window. If those two ever disagree, the pulse the
        // stage sees stops matching the numbers the screen shows.
        let raw = [800.0, 820.0, 500.0, 1100.0, 830.0, 810.0, .nan, 805.0, 2500.0, 790.0]
        var gate = H.Gate()
        let streamed = raw.filter { gate.accept(intervalMs: $0) }
        XCTAssertEqual(streamed, H.accepted(rrMs: raw))
    }
}
