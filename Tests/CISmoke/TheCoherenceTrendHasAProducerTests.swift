// TheCoherenceTrendHasAProducerTests.swift
// Echoel — #813: the third producerless bio channel gets a producer.
//
// WHAT THIS GUARDS. `EchoelDDSP.applyBioReactive` has taken a `coherenceTrend` in −1…1 since it
// was written and used it for the rising/falling spectral morph — deadband 0.10, then
// `.natural` (rising) or `.metallic` (falling), capped at 0.30. Every `…BioParams(` site in
// `Sources/` passed the literal `0`, so `trendMag` was exactly 0 on every frame the shipped app
// could produce and the whole else-branch was unreachable (#496). The consumer's own comment
// asked for this slice by name: "deriving one from the coherence history is a real slice — this
// branch is what it will drive."
//
// ⚠️ NO WELLBEING VALENCE, inherited from the consumer and binding here: rising coherence is an
// ENGINEERING mapping. Nothing in this slice touches user-facing copy, and the always-on panel
// still deliberately names FOUR channels. Adding a fifth is a copy decision, not a side effect
// of wiring one.
//
// ⭐ EVERY NUMBER BELOW IS DRIVEN, NOT PREDICTED — and one prediction was wrong, which is why
// the distinction is written here rather than assumed. The violent-jump case was labelled "must
// saturate at 1.0" while driving it; measured, a single-frame jump reaches **0.221**, because
// the rate-based smoothing (α ≈ 0.22 at dt = 1 s) attenuates any one frame to about a fifth of
// its raw slope. That is better behaviour than the label predicted — one wild reading must not
// slam a spectral rebuild — so the claim below pins the MEASURED bound and says so. #808 is the
// standing lesson: a needle written from a prediction is not verified by being plausible.
//
// KIND (§1): **FORWARD, behavioural.** Every claim drives the pure `CoherenceTrend` this commit
// creates, so none has a verdict on the parent tree (§3 — stated rather than left to read as a
// regression). The SAFETY half is everything under the SAFETY heading: the situations that
// would otherwise mint a full-scale trend out of nothing, or divide by a zero interval.
// ⛔ This line carried a claim RANGE ("5–7", then "5–9") and it went stale twice, the second
// time inside the very commit that had just repaired it. The headings name SETS now; no
// number here describes how many claims this file holds.
//
// ⚠️ WHAT NO TEST HERE CAN SAY: whether the resulting timbre shift is audible-but-not-
// distracting. `fullScaleRisePerSecond` is an estimate. NEEDS-FOUNDER-VERIFY: run a session,
// let coherence climb and fall, and say whether the shift is right.

import Foundation   // TimeInterval. XCTest re-exports it on Darwin; the bundle spells it out.
import XCTest
@testable import Echoelmusic

final class TheCoherenceTrendHasAProducerTests: XCTestCase {

    /// The sensor every claim EXCEPT the source-switch one uses, deliberately the same value
    /// throughout. A trend is a statement about one sensor's readings; holding the source fixed
    /// is what makes the nine inherited claims measure slope and nothing else, and it is why
    /// threading `source:` through them changed not one driven number (verified before the
    /// parameter was added: old and new logic produce identical output for all nine).
    private static let oneSensor: BioSource = .cameraPPG

    /// The sensor the hand-over claims switch TO. Named rather than spelled at the call site so
    /// it cannot silently become equal to `oneSensor` — a hand-over claim whose two sources are
    /// the same value still passes, for the wrong reason.
    private static let otherSensor: BioSource = .ble

    // MARK: - THE FIXTURES THEMSELVES

    func testTheTwoNamedSensorsAreActuallyDifferent() {
        XCTAssertNotEqual(Self.oneSensor, Self.otherSensor, """
            The hand-over claims switch between two values that are equal, so they no longer test \
            a hand-over at all — they would pass as a same-sensor run for the wrong reason.
            """)
    }

    /// One frame per second, the app's measured apply rate (the poll is 10 Hz; every consumer
    /// deduplicates on `frame.timestamp` and every wired publisher sends at ~1 Hz).
    private func drive(_ readings: [(Float, Bool)], startAt t0: TimeInterval = 0) -> [Float] {
        var trend = CoherenceTrend()
        return readings.enumerated().map { index, r in
            trend.update(coherence: r.0, measured: r.1, source: Self.oneSensor, at: t0 + TimeInterval(index))
        }
    }

    // MARK: - SLOPE  a slope produces a signed trend, and the sign follows the direction

    func testASlowRiseProducesAPositiveTrendPastTheDeadband() {
        let out = drive((0..<9).map { (0.40 + 0.02 * Float($0), true) })
        XCTAssertEqual(out.first, 0, """
            The first measured reading of a run produced a trend. One point has no slope; a
            non-zero answer there is the tracker inventing movement out of its own initial state.
            """)
        XCTAssertTrue(out.last! > 0.30, """
            A steady 0.02/s climb — the rate the producer's header calls typical — did not reach
            past 0.30. Driven, it settles near 0.35 and the consumer's deadband is 0.10, so a
            result below that leaves the branch as dead as it was before this slice.
            """)
        XCTAssertTrue(zip(out, out.dropFirst()).allSatisfy { $0.1 >= $0.0 }, """
            The trend did not rise monotonically under a monotonic climb. The smoothing is one
            pole; it may lag, it may not reverse.
            """)
    }

    func testAFallMirrorsTheRiseExactly() {
        let up = drive((0..<9).map { (0.40 + 0.02 * Float($0), true) })
        let down = drive((0..<9).map { (0.60 - 0.02 * Float($0), true) })
        for (u, d) in zip(up, down) {
            XCTAssertEqual(u, -d, accuracy: 1e-6, """
                Rise and fall are not mirror images. The consumer picks `.natural` vs `.metallic`
                purely on the sign, so an asymmetry here makes one direction reach the morph
                sooner than the other for no physical reason.
                """)
        }
    }

    // MARK: - RESTRAINT  a flat body stays inside the deadband, and one wild frame does not slam it

    func testFlatCoherenceProducesExactlyZero() {
        XCTAssertTrue(drive((0..<6).map { _ in (Float(0.55), true) }).allSatisfy { $0 == 0 }, """
            Unchanging coherence produced a non-zero trend. Zero is not an approximation here:
            the consumer rebuilds a spectral buffer whenever the morph changes, so drift on a
            still body is audible work done for nothing.
            """)
    }

    func testASingleWildFrameIsAttenuatedNotSaturated() {
        let out = drive([(0.10, true), (0.95, true), (0.95, true)])
        XCTAssertTrue(out[1] > 0.15 && out[1] < 0.30, """
            A one-frame jump from 0.10 to 0.95 left the smoothing. Driven, it reaches 0.221 —
            about a fifth of the raw saturated slope — and that attenuation IS the design: one
            wild reading must move the timbre a little, never to the 0.30 morph cap. A value
            near 1.0 means the smoothing was removed or its time constant collapsed.
            """)
        XCTAssertTrue(out[2] < out[1], """
            The trend did not decay once the jump stopped. With coherence held still the slope is
            zero, so the pole must pull the value back toward the deadband.
            """)
    }

    // MARK: - SAFETY  the situations that would otherwise mint a trend out of nothing
    //
    // ⛔ THIS HEADING SAID "5–7 the three transitions" OVER FOUR METHODS, then "5–9" over six.
    // The out-of-order regression was appended without renumbering; #920 added two more and the
    // range went stale again in the same commit that had just corrected it. **A heading that
    // names a count or a range is a date, not a fact (#818)** — every number is gone from the
    // headings now, and the size of this suite is re-derived by
    // `grep -c "    func test" Tests/CISmoke/TheCoherenceTrendHasAProducerTests.swift`.

    func testAnUnmeasuredRunCannotSpikeWhenTheBodyArrives() {
        let out = drive([(0.0, false), (0.0, false), (0.62, true), (0.63, true)])
        XCTAssertEqual(out[0], 0); XCTAssertEqual(out[1], 0)
        XCTAssertEqual(out[2], 0, """
            The first MEASURED reading after an unmeasured stretch produced a trend. That is the
            0.5-neutral-placeholder spike this type exists to prevent: substituting a neutral for
            an unmeasured channel is right for a LEVEL and wrong for a DERIVATIVE, because the
            substitution itself reads as movement.
            """)
        XCTAssertTrue(abs(out[3]) < 0.10, """
            The second measured reading already cleared the consumer's deadband off a 0.01
            change. A new run must start quiet.
            """)
    }

    func testALongGapStartsANewRunInsteadOfASlope() {
        var trend = CoherenceTrend()
        _ = trend.update(coherence: 0.40, measured: true, source: Self.oneSensor, at: 0)
        let before = trend.update(coherence: 0.42, measured: true, source: Self.oneSensor, at: 1)
        XCTAssertTrue(before > 0, "A real 1 s slope produced nothing; the control for this test is broken.")
        let across = trend.update(coherence: 0.90, measured: true, source: Self.oneSensor, at: 30)
        XCTAssertEqual(across, 0, """
            A 29-second gap was read as a slope. A paused or backgrounded session resumes with a
            completely different body state; dividing that difference by the gap is arithmetic
            about two unrelated moments.
            """)
    }

    func testADuplicateStampHoldsRatherThanDividingByZero() {
        var trend = CoherenceTrend()
        _ = trend.update(coherence: 0.40, measured: true, source: Self.oneSensor, at: 0)
        let first = trend.update(coherence: 0.44, measured: true, source: Self.oneSensor, at: 1)
        let repeated = trend.update(coherence: 0.44, measured: true, source: Self.oneSensor, at: 1)
        XCTAssertEqual(repeated, first, """
            A repeated timestamp changed the trend. dt = 0 has no slope to compute and the
            division would be by zero; holding the last value is the only honest answer.
            """)
    }

    /// ⛔ REGRESSION FOR A BUG THE MANDATORY REVIEW FOUND IN THIS SLICE'S OWN FIRST DRAFT. The
    /// producer stored the new reading in a `defer`, which fires on EVERY path — including the
    /// dt ≤ 0 one. An out-of-order frame therefore became the baseline, and the NEXT real frame
    /// measured its interval from that older moment: an inflated dt, so a genuine slope read as
    /// a slower one. The voices' `frame.timestamp != lastTimestamp` check excludes exact
    /// duplicates but not reordering, and a producer that leans on its caller's deduplication is
    /// the shape this repo keeps paying for.
    func testAnOutOfOrderFrameDoesNotBecomeTheBaseline() {
        var poisoned = CoherenceTrend()
        _ = poisoned.update(coherence: 0.40, measured: true, source: Self.oneSensor, at: 10)
        _ = poisoned.update(coherence: 0.44, measured: true, source: Self.oneSensor, at: 11)
        _ = poisoned.update(coherence: 0.20, measured: true, source: Self.oneSensor, at: 4)   // arrives late, older stamp
        let afterReorder = poisoned.update(coherence: 0.48, measured: true, source: Self.oneSensor, at: 12)

        var clean = CoherenceTrend()
        _ = clean.update(coherence: 0.40, measured: true, source: Self.oneSensor, at: 10)
        _ = clean.update(coherence: 0.44, measured: true, source: Self.oneSensor, at: 11)
        let withoutReorder = clean.update(coherence: 0.48, measured: true, source: Self.oneSensor, at: 12)

        XCTAssertEqual(afterReorder, withoutReorder, accuracy: 1e-6, """
            An out-of-order frame changed what the NEXT frame computed. Dropping a late frame
            has to mean dropping it entirely — value AND baseline — or the reordering silently
            rescales every interval that follows it.
            """)
    }

    /// ⛔ THE RESET CLAUDE.md PROMISED BEFORE IT EXISTED. The bio table listed the three resets
    /// as "ungemessen→gemessen, Quellenwechsel, langes Loch"; the built third safeguard was the
    /// duplicate/out-of-order stamp hold, so the doc named an absent guard and omitted a present
    /// one. #920 built the missing one because the artefact is real and measured, not because a
    /// sentence asked for it.
    ///
    /// ⚠️ THE GAP GUARD DOES NOT COVER THIS and that is the whole point: a hand-over inside the
    /// six-second freshness window never reaches it.
    func testASensorHandOverDoesNotReadAsABodyChange() {
        var trend = CoherenceTrend()
        _ = trend.update(coherence: 0.20, measured: true, source: Self.oneSensor, at: 0)
        let across = trend.update(coherence: 0.75, measured: true, source: Self.otherSensor, at: 2)
        XCTAssertEqual(across, 0, """
            A sensor hand-over produced a trend. Driven on the real constants, camera 0.20 → \
            strap 0.75 two seconds later mints 0.393 — nearly four times the consumer's 0.10 \
            deadband, and INDISTINGUISHABLE from the fastest genuine rise this mapping can \
            express (a saturating climb over the same 2 s is 0.3935 too). The player would hear \
            the spectral morph swing because they changed sensor, not because their body did. \
            A trend is a statement about ONE sensor's readings.
            """)

        let next = trend.update(coherence: 0.76, measured: true, source: Self.otherSensor, at: 3)
        XCTAssertTrue(abs(next) < 0.10, """
            The first reading AFTER the hand-over already cleared the deadband off a 0.01 change. \
            The switch has to start a genuinely new run, not merely suppress one frame.
            """)
    }

    /// ⛔ THE MANDATORY REVIEW CALLED THIS A DEFECT AND THE COUNTERFACTUAL REFUTED IT — pinned so
    /// the same doubt is not re-litigated. The reading was: the switch guard writes
    /// `lastTimestamp` with no monotonicity check, so a LATE frame carrying a new source becomes
    /// the baseline, defeating `testAnOutOfOrderFrameDoesNotBecomeTheBaseline`. Driven, the trend after the reordering is 0.3518 — and
    /// the RIGHT counterfactual is not "the late frame never existed" (which trivially gives 0)
    /// but "the same two readings of the new sensor, in order", which gives 0.3518 as well. The
    /// tracker returns the same answer whether or not the frame was reordered, which is exactly
    /// the property that claim demands. The 0.3518 is a genuine 0.20 → 0.30 over 3 s of real strap
    /// data; nothing is minted.
    ///
    /// ⚠️ THE LESSON IS ABOUT THE COUNTERFACTUAL, not about this guard: an out-of-order claim can
    /// only be settled against the in-order run of the SAME readings. Comparing against a run
    /// that is missing one of them measures the missing frame, not the reordering.
    func testAReorderedFrameAcrossAHandOverStillMatchesTheInOrderRun() {
        var reordered = CoherenceTrend()
        _ = reordered.update(coherence: 0.40, measured: true, source: Self.oneSensor, at: 10)
        _ = reordered.update(coherence: 0.44, measured: true, source: Self.oneSensor, at: 11)
        _ = reordered.update(coherence: 0.20, measured: true, source: Self.otherSensor, at: 9)  // late, older stamp, NEW source
        let afterReorder = reordered.update(coherence: 0.30, measured: true, source: Self.otherSensor, at: 12)

        var inOrder = CoherenceTrend()
        _ = inOrder.update(coherence: 0.20, measured: true, source: Self.otherSensor, at: 9)
        let withoutReorder = inOrder.update(coherence: 0.30, measured: true, source: Self.otherSensor, at: 12)

        XCTAssertEqual(afterReorder, withoutReorder, accuracy: 1e-6, """
            A frame that arrived late AND carried a new source produced a different answer than \
            the same two readings of that source in order. The switch guard seeds a new run from \
            whatever frame announces the new sensor; if that seed is not equivalent to the \
            in-order seed, the hand-over guard has reintroduced exactly the baseline poisoning \
            `testAnOutOfOrderFrameDoesNotBecomeTheBaseline` forbids.
            """)
        XCTAssertTrue(afterReorder > 0.10, """
            The control for this test is broken: the in-order run must produce a REAL slope past \
            the deadband, or the equality above would hold trivially at zero and prove nothing.
            """)
    }

    // MARK: - NON-FINITE INPUT

    func testANonFiniteReadingResetsAndNeverPropagates() {
        let out = drive([(0.4, true), (Float.nan, true), (0.5, true)])
        XCTAssertTrue(out.allSatisfy { $0.isFinite }, """
            A NaN reached the trend output. It would travel to `applyBioReactive`, whose own
            sanitizer would catch it — but a producer that relies on its consumer's sanitizer is
            the pattern this repo has paid for in shipped permanent silence.
            """)
        XCTAssertEqual(out[1], 0, "A NaN reading did not reset the run.")
        XCTAssertEqual(out[2], 0, """
            The reading after a NaN produced a slope. The NaN reset the history, so the next
            value is a first point again.
            """)
    }
}
