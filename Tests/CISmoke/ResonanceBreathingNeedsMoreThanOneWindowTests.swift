// ResonanceBreathingNeedsMoreThanOneWindowTests.swift
// Echoel — #343. The camera could not measure the one breathing rate the product is about.
//
// ⭐ THE DEFECT, and it is not a settling-time nuisance. `CameraRPPGBioPublisher` built a
// FRESH `RespirationEstimator` on every publish and fed it only the newest analysis window.
// That window is 10 s (`CameraAnalyzer`: `min(n, Int(effectiveSampleRate * 10))`). Respiration
// rate is read from the time between two UPWARD zero-crossings of the band-passed RSA signal,
// so a window that spans ONE breath cycle can hold at most one crossing — and one crossing is
// not a period. At 6 breaths/min the cycle IS 10 s.
//
// 6/min is not an arbitrary corner. It is the HRV-resonance rate this app cites in
// `BioScienceInfo` (Lehrer/Vaschillo) and paces toward in `BreathPacer`. So the camera was
// structurally blind exactly where the product aims, and it said so in the least useful way:
// `confidence` still landed at 0.458–0.625 — ABOVE the 0.4 gate the publisher then used — at
// EVERY one of 360 whole-degree phases, while `ratePerMinute` stayed 0 at 345 of them and
// read a fabricated 7.4 at the other 15. "Breath measured: yes. Rate: zero, or wrong."
//
// ⛔ THIS PARAGRAPH IS WHERE THE FILE FIRST LIED TO ITSELF. It said "0.46–0.50 … rate stayed
// 0", sampled from four hand-picked phases, and it survived a whole commit whose thesis was
// that four phases are not a sweep — the corrected copy went into
// `CameraRPPGBioPublisher.swift` while this one, the passage a reader meets FIRST, stood.
// A header is not commentary on the tests below it; it is the claim they support.
//
// It went unnoticed because it is RATE-DEPENDENT, which `testFasterBreathingMostlyWorked`
// pins: at 15 breaths/min a 10 s window usually holds two or three crossings, so the old code
// was right at 278 of 360 phases. Anyone testing by breathing normally saw a working feature.
//
// THE FIX is not a longer window (that costs latency everywhere — see #340, which calls the
// 10 s window the single largest item in the bio→audio budget). It is to stop throwing the
// estimator away: ONE estimator per take, each beat ingested exactly once, via the absolute
// `CameraAnalyzer.beatTimes` this slice adds. Windows overlap ~90 % and interval VALUES carry
// no identity, so "newer than the last beat I consumed" is the only exact de-duplication.
//
// ⚠️ HONEST LIMITS.
//   · The behavioural half drives the PURE estimator with a synthetic RSA series. It proves
//     the arithmetic and the blind spot. It does NOT prove the camera path works on a real
//     finger — that needs a device run, and the acquisition itself is a separate open
//     problem (#304/#410).
//   · The wiring half is a source scan, so it can confirm that the estimator is long-lived
//     and reset on stop, not that the values reach the ear.
//   · Real RSA is noisier and shallower than a clean sine. The thresholds here are floors
//     against the STRUCTURAL failure (one window never reaching the true rate), not quality
//     judgements. Test 1 asserts `|rate − 6| > 1`, not `rate == 0` — see its own ⛔ note.
//   · Nothing here sees the DEVICE's noise floor. `CameraAnalyzer` takes peak times at
//     whole-sample resolution at 7.5–15 fps, so real intervals are quantised to one frame
//     period: 1.6 bpm RMS at 15 fps, 3.2 at 7.5, against the 1.5 bpm scale the confidence
//     floor is set to. These tests drive the pure estimator with exact timestamps, so they
//     prove the arithmetic and say nothing about how well the shipped path separates a
//     shallow breather from a still hand — simulated, a MOTIONLESS hand clears the gate on
//     quantisation alone in 86 of 120 sampled cases at 15 fps and 109 of 120 at 7.5.
//     ⛔ THIS BULLET SAID "±4 to ±8 bpm … several times the 1.5 bpm scale" AND `d7e0424`
//     RETRACTED THAT SENTENCE IN `RespirationEstimator.swift` WITHOUT TOUCHING THE COPY HERE.
//     ±4/±8 is the PEAK; a floor responds to the RMS, so the honest ratio is 1.1–2.2×, not
//     3–5×. Third time in this one epic that a corrected number survived in a second file —
//     line 597 below already carries the lesson ("the fix belongs everywhere `grep` finds the
//     number"), and the retraction commit itself walked past it. The old last clause ("that
//     needs sub-sample peak timing first") is stale too: #421 has since measured naive
//     3-point parabolic interpolation as WORSE than whole-sample at this signal's ≈4 dB SNR,
//     so sub-sample timing is an open design question, not the standing plan.
//   · ⛔ SEVEN OF THESE TWELVE TESTS COULD FAIL ON THE CODE THEY GUARD: the three source scans
//     (the long-lived estimator, the paired `beatTimes`, the evidence-gated publish), the
//     three staleness guards (`…ExpiresWhenTheBreathingStops`, `…WeakNoisySignal…`,
//     `…AgesWithTheClock…`) and `…FastBreathersOwnMeasurementSurvivesThePipelineLag`, which
//     read 0.2582 against a 0.4 gate before the grace paid for the lag.
//     TWO are counterweights — they hold bounds that must NOT move and could only fail if the
//     grace were TIGHTENED: `…AgeingInsideTheGraceWindow…` and `…ContinuingSlowBreathNever…`.
//     And the file brackets `pullLagAllowance` from BOTH sides, which is worth knowing before
//     anyone moves it: `…AgesWithTheClock…` is the only upper bound (red once the constant
//     passes ≈15.0 s under the shipped subtract-from-staleness form, ≈9.4 s under the
//     add-to-grace form the first version used), and `…FastBreathers…` is the only lower one
//     (red below ≈0.87 s). The shipped 1.8 therefore sits ≈0.93 s above the floor and ≈13.2 s
//     below the ceiling. The other two staleness guards stay green past a 400 s allowance and
//     constrain nothing here.
//     ⛔ THE FLOOR READ ≈0.74 s (MARGIN ≈1.06 s) UNTIL #424, which touched a DIFFERENT constant.
//     `…FastBreathers…` runs at 28/min, near enough to the band edge that widening ACCEPTANCE
//     changes which crossings feed `periodEMA` and therefore the grace; `…AgesWithTheClock…`
//     runs at 6/min and did not move. One of the two brackets on `pullLagAllowance` went stale
//     without anything touching `pullLagAllowance` — re-measure both after any band change.
//     The remaining three describe the pure estimator on inputs these commits
//     leave bit-identical — they are green on both sides and exist to state the SHAPE of the
//     defect, not to catch its return. That is NOT the same as "the arithmetic did not
//     change": `32c3dcc` changed the confidence expression, which moved
//     `testAccumulatingAcrossWindows…`'s worst-phase value from 0.9716 to 0.9432. Those
//     assertions are live upper bounds on the veto; do not read this bullet as licence to
//     loosen them.
//   · The generator's ±3 bpm RSA swing is not incidental. The "harmful, not merely
//     incomplete" half — that the 0.4 confidence gate stands open while the rate is wrong —
//     holds at every phase only down to a swing of about ±2.62. At ±2.5, 134 of 360 phases
//     already fall below the gate, so `testOneWindowCannotMeasureResonanceBreathing` would
//     go red; at ±1 the window reads 0.15–0.29 and the old behaviour was honest silence.
//     ⛔ The first version of this bullet said "roughly 2.5 bpm or more" — the last
//     hand-picked figure in a file whose whole thesis is that hand-picked is not swept, and
//     wrong in the direction that invites someone to lower the constant.

import Foundation
import XCTest
@testable import Echoelmusic

final class ResonanceBreathingNeedsMoreThanOneWindowTests: XCTestCase {

    /// The rate `BioScienceInfo` cites and `BreathPacer` paces toward.
    private static let resonanceBreathsPerMinute = 6.0
    /// `CameraAnalyzer` analyses `effectiveSampleRate * 10` samples.
    private static let analysisWindowSeconds = 10.0
    /// The publisher's own gate: `resp.confidence >= 0.4` means "breath measured".
    private static let measuredBreathGate = 0.4
    /// Well inside the estimator's 4…30/min band but far enough up it that the proportional
    /// grace has shrunk to the same order as the pipeline lag. NOT 30, but not for the reason
    /// the first version gave — see the ⚠️ on
    /// `testAFastBreathersOwnMeasurementSurvivesThePipelineLag`. Swept at the shipped 1.8 s
    /// allowance and this test's 2.5 s wall, the worst-phase confidence is 0.4871 at 28.0/min,
    /// 0.4046 at 28.7 and 0.3880 at 28.8 — so the last rate at which EVERY phase passes is
    /// 28.7, and above it a growing share fails for a reason nothing in this file fixes.
    /// Testing up there would pin a failure rather than a guarantee. (⛔ The first version of
    /// this sentence said "~28.5", which no measurement supports; a rate boundary quoted
    /// without the lag it depends on is the same shape as the thing this commit corrects.)
    private static let fastBreathsPerMinute = 28.0
    /// Delay between the last beat reaching `ingest` and `age(to:)` being called on it: two
    /// samples to confirm the peak, the ~4 Hz peak-scan throttle, and the ~1 Hz publish drain.
    /// Derived: ≈1.40 s at 15 fps, ≈1.80 s at 7.5 fps (the two frame-counted terms double).
    ///
    /// This test deliberately uses a LARGER value than `RespirationEstimator`'s allowance
    /// (1.8 s) so it asserts margin, not the constant: a missed peak or a slow drain pushes the
    /// real delay past the derived figure, and the gate must still hold. It stays red without
    /// the allowance at either value (0.3725 at 1.8 s, 0.2582 at 2.5 s).
    ///
    /// ⛔ THOSE READ 0.394 / 0.284 UNTIL #424 and it was not this constant that moved them —
    /// widening the estimator's ACCEPTANCE band changed which crossings feed `periodEMA` at
    /// 28/min, hence `grace`, hence this confidence. A number measured on a neighbouring
    /// constant's behaviour goes stale when THAT constant moves, and nothing warns you.
    ///
    /// ⛔ It said "worst-case delay … one beat interval, plus …". The beat interval does NOT
    /// belong: the delay is measured FROM the last beat, so beat quantisation is already inside
    /// `lastBeat − lastCrossT`. Counting it twice is what put the allowance at 2.5 s.
    private static let publishPipelineLagSeconds = 2.5

    // MARK: - The blind spot

    /// ⭐ THE DEFECT, stated as itself rather than as the repair: ONE analysis window never
    /// yields the resonance breathing rate, at ANY starting phase.
    ///
    /// ⛔ SWEPT, not sampled, and that correction is the useful part of this test. The first
    /// version asserted `rate == 0` at four hand-picked phases and called it "not luck". It
    /// WAS luck: the estimator seeds `smooth`/`prevSmooth` at zero, so a window that opens on
    /// a rising edge manufactures an upward crossing that is not a breath. 15 of the 360
    /// whole-degree phases (≈4 %, clustered around 1.0–1.3 rad) therefore report a confident
    /// 7.4 breaths/min — worse than the silence the other 345 give. A single `phase = 1.1`
    /// would have turned that test red on completely untouched code.
    ///
    /// So the honest property is not "the rate is zero" but "the rate is never RIGHT", and it
    /// is asserted over the whole circle: no phase gets within 1 breath/min of the truth.
    func testOneWindowCannotMeasureResonanceBreathing() {
        var spurious = 0
        for phase in Self.sweptPhases {
            var estimator = RespirationEstimator()
            for beat in Self.rsaBeats(seconds: Self.analysisWindowSeconds,
                                      breathsPerMinute: Self.resonanceBreathsPerMinute,
                                      phase: phase) {
                estimator.ingest(heartRate: beat.heartRate, at: beat.time)
            }
            if estimator.ratePerMinute > 0 { spurious += 1 }
            let error = abs(estimator.ratePerMinute - Self.resonanceBreathsPerMinute)
            XCTAssertGreaterThan(error, 1.0,
                                 """
                                 A single \(Self.analysisWindowSeconds) s window measured \
                                 \(estimator.ratePerMinute) breaths/min at phase \(phase) — \
                                 within 1/min of the truth. If the estimator changed so that \
                                 one window CAN see a resonance cycle, re-derive this guard; \
                                 do not delete it, it is the reason the estimator is \
                                 long-lived.
                                 """)
            // The half that made it harmful rather than merely incomplete: the CONFIDENCE
            // gate stands open, so the frame went out as a measured breath regardless.
            // (The publisher now also requires `ratePerMinute > 0` — see
            // `testThePublishGateAlsoRequiresARate`. This assertion is about the estimator,
            // which is where the mismatch lives, and it is what that second condition exists
            // to compensate for.)
            XCTAssertGreaterThanOrEqual(
                estimator.confidence, Self.measuredBreathGate,
                """
                Phase \(phase): confidence \(estimator.confidence) fell below the \
                \(Self.measuredBreathGate) gate. That would make the old behaviour honest \
                (no claim at all) and this test's premise wrong — recheck before trusting it.
                """)
        }
        // Not a threshold, a receipt: it records that the "always zero" reading is false and
        // fails loudly if a change ever makes the whole sweep silent, which would mean the
        // seeding artefact is gone and the comment above has become fiction.
        XCTAssertGreaterThan(spurious, 0,
                             """
                             No phase produced a spurious rate any more. That is an \
                             IMPROVEMENT, not a failure — but this file's header explains the \
                             defect in terms of that artefact, so rewrite it before deleting \
                             this line.
                             """)
    }

    /// The same signal, accumulated the way the publisher now does it, is measured correctly.
    /// 60 s is roughly six resonance cycles — the estimator needs four crossings for full
    /// count-confidence, so this is the first duration at which the answer is not marginal.
    func testAccumulatingAcrossWindowsMeasuresResonanceBreathing() {
        for phase in Self.sweptPhases {
            var estimator = RespirationEstimator()
            for beat in Self.rsaBeats(seconds: 60,
                                      breathsPerMinute: Self.resonanceBreathsPerMinute,
                                      phase: phase) {
                estimator.ingest(heartRate: beat.heartRate, at: beat.time)
            }
            XCTAssertEqual(estimator.ratePerMinute, Self.resonanceBreathsPerMinute, accuracy: 1.0,
                           "phase \(phase): 60 s of 6/min RSA read as \(estimator.ratePerMinute)")
            XCTAssertGreaterThanOrEqual(estimator.confidence, Self.measuredBreathGate,
                                        "phase \(phase): confidence \(estimator.confidence)")
        }
    }

    /// Why nobody caught it: at an ordinary resting rate one window mostly works. This is the
    /// control that keeps the finding narrow — the window was never "too short" in general,
    /// it was too short for slow breathing.
    ///
    /// ⛔ "Mostly", not "always", and the same sweep that corrected the test above corrected
    /// this one's NAME. At 15/min, 36 of 360 phases still read 0 (the window can open just
    /// after the second-to-last crossing) and another 46 land outside ±2/min. Four
    /// hand-picked phases all happened to work, so the original claim looked total.
    ///
    /// The real contrast is a ratio, and it is the whole point of the file: at 15/min a
    /// single window measures a usable rate at 278 of 360 phases (77 %); at 6/min the test
    /// above shows it does so at NONE of them. The floor is 60 %, well under the measured
    /// value — a guard set at the measurement is a guard that fails on rounding.
    func testFasterBreathingMostlyWorked() {
        var usable = 0
        for phase in Self.sweptPhases {
            var estimator = RespirationEstimator()
            for beat in Self.rsaBeats(seconds: Self.analysisWindowSeconds,
                                      breathsPerMinute: 15, phase: phase) {
                estimator.ingest(heartRate: beat.heartRate, at: beat.time)
            }
            if abs(estimator.ratePerMinute - 15) <= 2 { usable += 1 }
        }
        let fraction = Double(usable) / Double(Self.sweptPhases.count)
        XCTAssertGreaterThan(fraction, 0.6,
                             """
                             Only \(usable)/\(Self.sweptPhases.count) phases measured 15 \
                             breaths/min from a single window (77 % when this was written). \
                             If that collapses, the defect is no longer rate-specific and \
                             this file's whole framing — "the window was too short for SLOW \
                             breathing" — needs rewriting.
                             """)
    }

    // MARK: - The wiring

    /// A correct estimator that is thrown away every second is the same defect with more
    /// steps, so the fix is only real if the publisher HOLDS one. Anchored on the property
    /// existing first — a scan that only forbids the old shape passes on a file that lost
    /// both (the #367 trap: a guard whose pass carries no information).
    func testThePublisherHoldsOneEstimatorForTheWholeTake() throws {
        let text = Self.codeOnly(try Self.source("Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"))
        XCTAssertTrue(text.contains("private var respiration = RespirationEstimator()"),
                      """
                      The publisher no longer holds a long-lived RespirationEstimator. Without \
                      it, resonance breathing is unmeasurable again — see this file's header.
                      """)
        XCTAssertFalse(text.contains("var resp = RespirationEstimator()"),
                       """
                       A per-publish RespirationEstimator is back. That is the #343 defect \
                       verbatim: it can only ever see one 10 s window.
                       """)
        XCTAssertTrue(text.contains("respiration.reset()"),
                      """
                      `stop()` must reset the estimator. A new take gets a new one: the last \
                      take's baseline, envelope and cycle count say nothing about this body \
                      now. (The first version of this message blamed a stale cursor across a \
                      camera teardown — false: the clock is `systemUptime`, monotonic since \
                      boot. Right conclusion, wrong reason.)
                      """)
    }

    /// ⭐ THE REGRESSION #343 ITSELF INTRODUCED, and the reason this file grew a fourth
    /// behavioural test. `crossingCount` is monotonic and `ratePerMinute` keeps its last
    /// value, so once four cycles are seen `countConf` pins at 1.0 and `confidence` has a
    /// hard floor of 0.5 — permanently above the publisher's 0.4 "measured" gate.
    ///
    /// While the estimator was rebuilt every publish that floor could not outlive one 10 s
    /// window. Making it live for a whole take turned a bounded staleness into a LATCH: on a
    /// 60 s resonance series followed by a perfectly flat heart rate, confidence sat at
    /// exactly 0.500 forever and the publisher went on reporting "6.0 breaths/min, measured"
    /// with no breathing at all — a frozen value stamped with a fresh timestamp, the very
    /// thing the pulse path already has a truth gate for.
    ///
    /// So the fix for #343 is only honest WITH the freshness term, and this test is what
    /// keeps the two together.
    func testAMeasuredRateExpiresWhenTheBreathingStops() {
        var estimator = RespirationEstimator()
        for beat in Self.rsaBeats(seconds: 60,
                                  breathsPerMinute: Self.resonanceBreathsPerMinute,
                                  phase: 0) {
            estimator.ingest(heartRate: beat.heartRate, at: beat.time)
        }
        XCTAssertGreaterThanOrEqual(estimator.confidence, Self.measuredBreathGate,
                                    "premise: 60 s of clean RSA must read as measured first")

        // Breathing stops; the heart keeps beating at a flat rate. Nothing new to see.
        var t = 60.0
        for _ in 0..<30 {
            t += 1
            estimator.ingest(heartRate: 60, at: t)
        }
        XCTAssertLessThan(estimator.confidence, Self.measuredBreathGate,
                          """
                          30 s after the last breath cycle the estimator still reports \
                          confidence \(estimator.confidence) — at or above the publisher's \
                          \(Self.measuredBreathGate) gate — so `breathRate` \
                          \(estimator.ratePerMinute) keeps being published as MEASURED. That \
                          is the latch the freshness term exists to prevent; do not remove it \
                          without replacing it.
                          """)
    }

    /// The other half of the same rule: the expiry must not fire while breathing continues.
    /// Without this, "make confidence decay" could be satisfied by a term that also kills a
    /// perfectly good resonance measurement — the slowest supported rate has 15 s between
    /// cycles, which is longer than most naive timeouts.
    func testAContinuingSlowBreathNeverExpires() {
        var estimator = RespirationEstimator()
        for beat in Self.rsaBeats(seconds: 120,
                                  breathsPerMinute: Self.resonanceBreathsPerMinute,
                                  phase: 0) {
            estimator.ingest(heartRate: beat.heartRate, at: beat.time)
        }
        XCTAssertGreaterThanOrEqual(estimator.confidence, Self.measuredBreathGate,
                                    """
                                    Two minutes of uninterrupted 6/min breathing expired to \
                                    \(estimator.confidence). The freshness grace is too tight \
                                    for the rate this product is built around.
                                    """)
        XCTAssertEqual(estimator.ratePerMinute, Self.resonanceBreathsPerMinute, accuracy: 1.0)
    }

    /// ⭐ THE SECOND HALF OF THAT SAME REGRESSION, and the one the freshness term does NOT
    /// cover. Freshness keys on the last upward crossing, so it only fires when the crossings
    /// STOP. A take does not usually end in a flat trace — it ends in a drifting fingertip, a
    /// relaxing hand, a noisy one. That keeps producing crossings inside the 4…30/min band,
    /// so `crossingCount` keeps rising, `lastCrossT` stays fresh, and the 0.5 floor stands
    /// while the swing that justified it is long gone.
    ///
    /// Measured before the fix: 60 s of clean 6/min followed by 90 s of a 0.15 bpm wobble
    /// ended at confidence 0.524 — gate OPEN — publishing a fabricated 11.9 breaths/min off
    /// an envelope of 0.07. The fix is that the envelope VETOES the count, i.e. confidence
    /// can never exceed what the swing alone supports.
    ///
    /// This is the worse of the two failures: a rate read out of noise is narrated with the
    /// same certainty as a real one, whereas the silence it replaced was at least honest.
    func testAWeakNoisySignalCannotKeepTheGateOpen() {
        var estimator = RespirationEstimator()
        for beat in Self.rsaBeats(seconds: 60,
                                  breathsPerMinute: Self.resonanceBreathsPerMinute,
                                  phase: 0) {
            estimator.ingest(heartRate: beat.heartRate, at: beat.time)
        }
        XCTAssertGreaterThanOrEqual(estimator.confidence, Self.measuredBreathGate,
                                    "premise: 60 s of clean RSA must read as measured first")

        // Breathing becomes invisible in the trace: the heart still wobbles, by a fortieth of
        // the earlier swing, fast enough that crossings never stop arriving.
        var t = 60.0
        while t < 150 {
            let hr = 60.0 + 0.15 * sin(2 * .pi * 0.2 * t)
            estimator.ingest(heartRate: hr, at: t)
            t += 60 / hr
        }
        XCTAssertLessThan(estimator.confidence, Self.measuredBreathGate,
                          """
                          90 s after the RSA collapsed to noise the estimator still reports \
                          confidence \(estimator.confidence), so \(estimator.ratePerMinute) \
                          breaths/min keeps being published as MEASURED. The freshness term \
                          alone cannot catch this — crossings never stopped. What catches it \
                          is the envelope vetoing the count; do not remove that without \
                          replacing it.
                          """)
    }

    // MARK: - Staleness the estimator cannot see from inside

    /// ⭐ THE THIRD LATCH, and the one neither earlier term can reach. Both the freshness
    /// factor and the envelope veto are evaluated inside `ingest`, so they measure "beats
    /// since the last cycle", not "time since the last cycle". A take whose beat supply dries
    /// up while the publisher keeps running therefore freezes `confidence` at whatever it last
    /// earned — forever, with no breathing and no beats.
    ///
    /// It is a real device state: `CameraAnalyzer` returns early without touching
    /// `rrIntervals`/`beatTimes` when it finds fewer than three peaks, while `fallbackBPM`
    /// keeps the pulse alive off the autocorrelation and the publisher goes on emitting
    /// frames. The analyzer names that case in its own source ("peaks<3 with a strong acf").
    ///
    /// The first half of this test is the defect; the second is the proof that the fix is the
    /// PULL and not something the old code already did.
    func testConfidenceAgesWithTheClockNotOnlyWithBeats() {
        var aged = RespirationEstimator()
        for beat in Self.rsaBeats(seconds: 60,
                                  breathsPerMinute: Self.resonanceBreathsPerMinute,
                                  phase: 0) {
            aged.ingest(heartRate: beat.heartRate, at: beat.time)
        }
        var frozen = aged        // value type: an exact copy of the same earned state
        XCTAssertGreaterThanOrEqual(aged.confidence, Self.measuredBreathGate,
                                    "premise: 60 s of clean RSA must read as measured first")

        // 30 s pass. No beats reach the estimator — only the clock moves.
        aged.age(to: 90)
        XCTAssertLessThan(aged.confidence, Self.measuredBreathGate,
                          """
                          30 s after the last beat, with the clock pulled forward, the \
                          estimator still reports \(aged.confidence) — so a take whose beat \
                          supply dried up keeps publishing \(aged.ratePerMinute) \
                          breaths/min as MEASURED. `age(to:)` is what makes staleness a \
                          function of time rather than of supply; do not remove it.
                          """)
        // And the copy that was never aged proves the old behaviour was the freeze, i.e. that
        // the assertion above is not passing for some unrelated reason.
        XCTAssertGreaterThanOrEqual(frozen.confidence, Self.measuredBreathGate,
                                    """
                                    Without the pull the value should still be frozen at what \
                                    it earned; it reads \(frozen.confidence). If this fails, \
                                    something else now ages the estimator and the test above \
                                    is no longer measuring what it claims.
                                    """)
        // Silence the "never mutated" warning honestly: this IS the mutation under test —
        // ageing backwards must be refused, so the copy stays exactly where it was.
        frozen.age(to: 0)
        XCTAssertGreaterThanOrEqual(frozen.confidence, Self.measuredBreathGate,
                                    """
                                    Ageing to a time BEFORE the last beat changed the value. \
                                    That means a caller mixing clocks could silently revive a \
                                    stale confidence; the guard in `age(to:)` must refuse it.
                                    """)
    }

    /// The counterweight, and the reason the pull is safe to call on every publish: ageing to
    /// a time inside the grace window must be a no-op, or a breather at the 6/min resonance
    /// rate would be expired between their own cycles — 10 s apart, longer than most naive
    /// timeouts, which is exactly the body this product is built around.
    func testAgeingInsideTheGraceWindowChangesNothing() {
        var estimator = RespirationEstimator()
        for beat in Self.rsaBeats(seconds: 60,
                                  breathsPerMinute: Self.resonanceBreathsPerMinute,
                                  phase: 0) {
            estimator.ingest(heartRate: beat.heartRate, at: beat.time)
        }
        let earned = estimator.confidence
        estimator.age(to: 61)
        XCTAssertEqual(estimator.confidence, earned, accuracy: 1e-12,
                       """
                       One second after the last beat the confidence moved from \(earned) to \
                       \(estimator.confidence). The grace window is 1.5 expected periods for \
                       a reason: a resonance breather is silent for 10 s at a time between \
                       cycles, and expiring them inside that is the opposite defect.
                       """)
    }

    /// ⭐ THE PRICE OF THE PULL, made a decision instead of a side-effect. `age(to:)` moved the
    /// freshness evaluation from the last BEAT's timestamp to wall-clock now, and the camera
    /// pipeline sits in between: two samples to confirm the peak, the ~4 Hz peak-scan throttle
    /// and the ~1 Hz publish drain — ≈1.40 s at 15 fps, ≈1.80 s at 7.5 fps. The grace, being
    /// purely proportional to the breathing period, charged that to the breather. A slow
    /// breather never noticed (15 s of grace at 6/min); a fast one did, because their grace
    /// shrinks while the pipeline delay does not.
    ///
    /// Swept over all 360 phases at 28 breaths/min, the worst phase read confidence 0.3725 at
    /// the 7.5 fps delay and 0.2582 at the 2.5 s wall this test uses — both UNDER the
    /// publisher's 0.4 gate. Their own, correctly measured breath (rate 25.783–29.653 at EVERY
    /// phase) flickered off and on at their breathing rate. With `pullLagAllowance` it reads
    /// 0.4871. At 15 fps the worst phase is 0.4378 and there is no defect — this is a
    /// slow-device failure, and the test says so rather than implying the fix was always needed.
    ///
    /// ⛔ FOUR OF THOSE FIVE NUMBERS MOVED WITH #424, WHICH IS IN A DIFFERENT CONSTANT. The
    /// no-allowance figures were 0.394 / 0.284, the 15 fps figure 0.457, and the rate span
    /// 24.6–28.7 — all measured before the acceptance band widened. Only the with-allowance
    /// 0.4871 is unchanged. The span is the one worth staring at, and only one thing about it is
    /// measured: the worst deviation from the true 28/min shrank from 3.418 to 2.217/min.
    ///
    /// ⛔ AND THE JUSTIFICATION THAT STOOD HERE WAS REFUTED BY THE LINE TWO ABOVE IT. It read "it
    /// now overshoots slightly ABOVE 28 where it never used to, so 'tighter', not 'shifted up',
    /// is the honest reading" — while the pre-#424 span quoted two lines up is 24.582–28.675,
    /// i.e. it ALREADY read above 28. The conclusion happens to be right (the span narrowed on
    /// both sides), the reason given for it is false, and it was false against a number in the
    /// same paragraph. The honest version needs no story: the deviation shrank, and the premise
    /// assertion below keys on the LOW end, which is why both numbers are quoted rather than
    /// summarised.
    ///
    /// ⚠️ THIS IS A COUNTERWEIGHT, NOT A CLAIM THAT THE WHOLE BAND WORKS, and the first version
    /// misdiagnosed the residual. It said 30/min is unreachable because the RSA sits at Nyquist
    /// and the rate aliases to ~10/min. That was written from ONE phase (phase 0) and the sweep
    /// refutes it: at 30/min the measured rate WAS ~30 at 244 of 360 phases, 0 at 61, ~10 at 53
    /// and one phase each at 10.3 and 18.8 (244 + 61 + 53 + 2 = 360 — the first version wrote
    /// "54" for the ~10 bucket and accounted for only 359, i.e. quoted a partial reading in the
    /// paragraph about quoting a partial reading). The modal answer is the RIGHT one. What
    /// actually fails above 28.7/min is the CONFIDENCE, for the same lag-versus-shrinking-grace
    /// reason this test is about, and neither this allowance nor a larger one closes it
    /// (29/min worst phase, all three under the gate: 0.000 with no allowance, 0.1685 with the
    /// shipped subtract-1.8, 0.2572 with subtract-2.5 — and 0.3134 under the previous commit's
    /// add-2.5-to-grace form, which is the number a reader would otherwise assume the middle
    /// column meant).
    ///
    /// ⭐ THE "REGISTERED ON THE BOARD AS #424; NOT FIXED HERE" THAT CLOSED THIS PARAGRAPH IS
    /// DONE. The acceptance band was widened, and the same sweep now reads ~30 at 358 of 360
    /// phases with NO zeros — both the 61-strong silent bucket and the 53-strong half-rate one
    /// are gone; only the two stragglers at 10.3 and 18.8 remain, which is exactly why the
    /// original count insisted on naming them. The histogram above is kept in the past tense as
    /// the record of the defect. What is NOT fixed is the confidence residual: the 29/min column
    /// is measured on today's band and still sits under the gate.
    /// Writing "Nyquist" in the file whose thesis is "swept, not sampled" — off one phase — is
    /// the exact habit this epic has now retracted three times.
    func testAFastBreathersOwnMeasurementSurvivesThePipelineLag() {
        var worst = Double.infinity
        var worstRate = 0.0
        var slowestRate = Double.infinity
        for phase in Self.sweptPhases {
            var estimator = RespirationEstimator()
            let beats = Self.rsaBeats(seconds: 60,
                                      breathsPerMinute: Self.fastBreathsPerMinute,
                                      phase: phase)
            guard let last = beats.last else {
                return XCTFail("premise: a 60 s take at \(Self.fastBreathsPerMinute)/min has beats")
            }
            for beat in beats { estimator.ingest(heartRate: beat.heartRate, at: beat.time) }
            estimator.age(to: last.time + Self.publishPipelineLagSeconds)
            slowestRate = Swift.min(slowestRate, estimator.ratePerMinute)
            if estimator.confidence < worst {
                worst = estimator.confidence
                worstRate = estimator.ratePerMinute
            }
        }
        // Premise first: a confidence floor is worth nothing if the rate underneath it is 0 —
        // that combination would satisfy this assertion while failing the publish gate anyway.
        XCTAssertGreaterThan(slowestRate, 20.0,
                             """
                             At \(Self.fastBreathsPerMinute) breaths/min the estimator's \
                             slowest measured rate across all \(Self.sweptPhases.count) \
                             phases was \(slowestRate). The premise of this test is that a \
                             fast breather IS measured; if that broke, fix it before reading \
                             the confidence assertion below.
                             """)
        XCTAssertGreaterThanOrEqual(worst, Self.measuredBreathGate,
                                    """
                                    A fast breather's own measurement fell to confidence \
                                    \(worst) (rate \(worstRate)) once the publisher's \
                                    \(Self.publishPipelineLagSeconds) s pipeline lag was added \
                                    to the wait — under the \(Self.measuredBreathGate) gate, so \
                                    their breath stops being published while they are breathing \
                                    it. The grace must pay for the lag it cannot see; that is \
                                    what `pullLagAllowance` is for.
                                    """)
    }

    /// ⭐ THE SURVIVING "MEASURED, RATE ZERO". `confidence` bounds the claim about the SWING;
    /// it says nothing about whether a period was ever measured. With zero crossings and a
    /// healthy envelope the expression is `0.5 * envConf`, which clears 0.4 — so 345 of the
    /// 360 one-window phases in the first test would still have published as measured.
    ///
    /// `breathRate` was harmless there (0 either way), but `breathPhase` carried
    /// `resp.amplitude` — a real number with no measured period — into `BreathArp.direction`
    /// and `BioComposer`'s inhale bias. The publish gate therefore needs both halves.
    ///
    /// A source scan, so it holds the WIRING, not the arithmetic: the two behavioural halves
    /// live in the tests above.
    func testThePublishGateAlsoRequiresARate() throws {
        let text = Self.codeOnly(try Self.source("Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"))
        XCTAssertTrue(text.contains("resp.confidence >= 0.4 && resp.ratePerMinute > 0"),
                      """
                      The publish gate no longer requires a measured RATE. Confidence alone \
                      admits the zero-crossing case: `breathPhase` then publishes an \
                      amplitude that no period supports, into the composer's inhale bias.
                      """)
        XCTAssertTrue(text.contains("respiration.age(to:"),
                      """
                      The publisher no longer ages the estimator before reading it. Without \
                      that pull, a take whose beat supply dries up freezes `confidence` at \
                      its last value — see `testConfidenceAgesWithTheClockNotOnlyWithBeats`.
                      """)
    }

    /// `beatTimes` only works as a de-duplication key while it stays 1:1 with `rrIntervals`.
    /// The two are produced together today; this holds the pairing so a later edit to one
    /// side cannot silently desynchronise them into an off-by-one respiration signal.
    ///
    /// (That paragraph spent one commit orphaned 110 lines up the file: a new section was
    /// inserted between its third and fourth line, leaving a `///` block documenting a `MARK`
    /// and this test opening mid-thought. Nothing diagnoses that — a doc comment separated
    /// from its declaration is still valid Swift.)
    ///
    /// ⛔ ADJACENCY, not a head-count. The first version compared two totals, which two
    /// unrelated edits — one site losing its pairing while a third gained one — would leave
    /// perfectly balanced. It counted, it did not pair. This walks the lines and requires the
    /// partner to be the very next statement, which is how the four sites read today.
    func testEveryRRAssignmentCarriesItsBeatTimes() throws {
        let text = Self.codeOnly(try Self.source("Sources/Echoelmusic/Video/CameraAnalyzer.swift"))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var checked = 0
        for (i, line) in lines.enumerated() {
            let partner: String
            if line.contains("rrIntervals = cleanIntervals") {
                partner = "beatTimes = cleanEndTimes"
            } else if line.contains("rrIntervals.removeAll()") {
                partner = "beatTimes.removeAll()"
            } else {
                continue
            }
            checked += 1
            let next = lines.dropFirst(i + 1).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            XCTAssertTrue(next?.contains(partner) == true,
                          """
                          `\(line.trimmingCharacters(in: .whitespaces))` is not immediately \
                          followed by `\(partner)` — the next statement is \
                          `\(next?.trimmingCharacters(in: .whitespaces) ?? "<end of file>")`. \
                          The two arrays index each other by position, so a consumer would \
                          read the wrong beat's interval, or a surviving times array would \
                          outlive the intervals it indexes.
                          """)
        }
        XCTAssertEqual(checked, 4,
                       """
                       Expected 4 `rrIntervals` write sites (2 publications, 2 clears), found \
                       \(checked). If the analyzer grew or lost one, re-derive this guard \
                       rather than adjusting the number — a site added without its partner is \
                       exactly what it exists to catch.
                       """)
    }

    // MARK: - Helpers

    /// Every whole degree. A handful of hand-picked phases is what made two claims in this
    /// file false at once (see the two ⛔ notes above): the seeding artefact and the
    /// 15/min misses both live in narrow bands that four samples walked straight past.
    /// 360 × a few hundred ingests is microseconds — there is no reason to sample.
    private static let sweptPhases: [Double] = (0..<360).map { Double($0) * .pi / 180 }

    private struct Beat { let time: Double; let heartRate: Double }

    /// Beat series of a heart whose rate is sinusoidally modulated by breathing (RSA) —
    /// the signal `RespirationEstimator` is built to read. Each beat lands one interval after
    /// the last, so the sample spacing is irregular exactly as it is on a real pulse.
    /// The ±3 bpm swing is a deliberately generous but not absurd resting RSA amplitude —
    /// and it is load-bearing, not decoration. `confidence` scales with the envelope, so the
    /// "the gate stands open while the rate is wrong" half of the defect needs a swing of
    /// about ±2.62 bpm or more (the swept all-phase floor — see the header bullet, and note
    /// the ± : RSA is conventionally quoted peak-to-peak, so that is ~5.2 bpm p-p); at ±1 the
    /// same window reads 0.15–0.29 and the old code was honestly silent. Lowering this default
    /// therefore does not make the tests stricter, it makes them describe a different (and
    /// less interesting) body.
    ///
    /// ⛔ This doc said "roughly 2.5 bpm or more", without the ±, for a whole commit after the
    /// header bullet retracted exactly that number as hand-picked and replaced it with the
    /// swept figure. Second copy of a corrected fact, second time in this one epic — the fix
    /// belongs everywhere `grep` finds the number, not only where the retraction is written.
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

    /// Comments blanked by `SourceText.codeOnly` (#453). This file's scans look for shapes that
    /// the SOURCE also describes in prose (the fixed code documents the broken form by name),
    /// and a raw-text scan cannot tell code from a comment — a trap this repo has paid for from
    /// both directions (#404, #420). The private copy it replaces truncated at the first `//`
    /// even inside a string literal; measured before the swap, both scanned files strip
    /// byte-identically, so no assertion here moved.
    private static func codeOnly(_ text: String) -> String {
        SourceText.codeOnly(text)
    }

    private static func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(relativePath) not present — this scan cannot report a green")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
