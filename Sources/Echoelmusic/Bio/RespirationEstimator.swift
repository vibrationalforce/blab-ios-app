//
//  RespirationEstimator.swift
//  Echoelmusic — Bio
//
//  Estimates breathing from the heart-rate signal the rPPG camera already produces,
//  via Respiratory Sinus Arrhythmia (RSA): breathing modulates heart rate — inhale
//  speeds it up, exhale slows it down — so the instantaneous-HR series oscillates at
//  the breathing frequency (~0.1–0.4 Hz). We band-pass that oscillation, normalize it
//  to a [0,1] amplitude (1 = inhale peak / lungs full) for the breath ball, and read
//  the breathing rate from its cycle length. This makes the guide TRUE biofeedback:
//  the ball follows the body's MEASURED breath instead of a fixed metronome.
//
//  Pure, deterministic value type: feed instantaneous HR samples (bpm) with their
//  timestamps via `ingest(heartRate:at:)`; read `amplitude` / `ratePerMinute` /
//  `confidence`. Time-aware EMAs make it robust to the irregular sample spacing of an
//  IBI stream. No allocation, no timers, no I/O — host-loop friendly.
//
//  This is self-observation, not a medical respiration monitor.
//

import Foundation

public struct RespirationEstimator {

    // MARK: Tuning (seconds)
    /// High-pass: removes the slow HR baseline so only the respiratory swing remains.
    private static let trendTau = 8.0
    /// Low-pass: keeps the respiration band, drops beat-to-beat jitter.
    private static let smoothTau = 0.8
    /// Envelope decay used to normalize the swing to [0,1].
    private static let envTau = 6.0
    /// Subtracted from the measured staleness to pay for the delay between the beat that marks
    /// a breath cycle and that beat reaching `ingest`. See `age(to:)` and the grace comment
    /// below — without it the pull turns a pipeline delay into apparent staleness at the fast
    /// end of the supported band.
    ///
    /// DERIVED FROM THE THREE PIPELINE TERMS, measured from the LAST BEAT (which is where the
    /// host's `age(to:)` clock effectively starts): a peak needs two later samples to be
    /// confirmed (`CameraAnalyzer`'s `val > window[i+1] && val > window[i+2]`), the peak scan
    /// is throttled to every 4th frame, and the publish drain runs at ~1 Hz. At 15 fps that is
    /// 0.13 + 0.27 + 1.0 ≈ 1.40 s; at 7.5 fps — the low end `CameraAnalyzer` documents for
    /// this device range — the two frame-counted terms double to 1.80 s. This is the 7.5 fps
    /// figure, so the slower device is covered rather than the faster one.
    ///
    /// ⚠️ IT IS A BUDGET, NOT AN EXACT SUM, and the "≈" is carrying two known errors in
    /// opposite directions. The frame terms overcount by one frame (a peak at frame k is
    /// confirmable at k+2 and the next `peakTick % 4 == 0` scan is at most k+5, so five frames,
    /// not 2+4 = 6), and the capture hop is missing entirely (`sampleQueue.push` stamps
    /// `systemUptime` and the 100 ms loop drains it on the next tick, ≤0.1 s). They roughly
    /// cancel. Both errors are in the safe direction for an ALLOWANCE — an overpaid allowance
    /// only widens the stale window slightly — but the line reads like three exact terms, and
    /// this file has already paid for one budget that read exact and was not.
    ///
    /// ⛔ A FOURTH TERM WAS IN THE FIRST VERSION AND DOES NOT BELONG: "the crossing is stamped
    /// at a beat (≈1 s at rest)". That quantisation is real, but it is already inside
    /// `lastBeat − lastCrossT`, so adding it to a lag measured FROM the last beat counts it
    /// twice — and it applied identically before the pull, so it is not part of the delta the
    /// pull introduced. That mistake put the constant at 2.5 s and the comment opened with
    /// "THE ALLOWANCE IS NOT PADDING", which was then exactly what the extra second was.
    /// The correction narrows the case as well as the number: with the three real terms the
    /// worst phase at 28 breaths/min reads 0.457 at 15 fps — no defect — and 0.394 at 7.5 fps,
    /// under the 0.4 gate. This is a slow-device defect, and saying so is the point.
    ///
    /// Two tests in `ResonanceBreathingNeedsMoreThanOneWindowTests` bracket this constant and
    /// nothing else does: `…FastBreathers…` goes red below ≈0.74 s, `…AgesWithTheClock…` above
    /// ≈15.0 s. 1.8 therefore sits ≈1.06 s above the floor and ≈13.2 s below the ceiling —
    /// deliberately close to the floor, because every second of allowance is a second the
    /// estimator keeps claiming a rate it can no longer see.
    private static let pullLagAllowance = 1.8

    // MARK: Respiration band (breaths/min)
    /// The band this estimator ADVERTISES and REPORTS in. `ratePerMinute` never leaves it.
    public static let minRate = 4.0
    public static let maxRate = 30.0

    /// ⭐ ACCEPT WIDER THAN YOU REPORT (#424). A candidate period is accepted if its implied
    /// rate falls in `[minRate / bandTolerance, maxRate * bandTolerance]`; the reported rate is
    /// then clamped back into `[minRate, maxRate]`.
    ///
    /// Until #424 there was ONE band doing both jobs, and a measurement whose jitter put it a
    /// hair outside was discarded entirely — no period, no crossing count, no rate. That is not
    /// conservative at the edges, it is blind: swept over all 360 whole-degree phases with 60 s
    /// takes at a resting pulse, `ratePerMinute` stayed 0 at **240 of 360 phases at 4/min** and
    /// **61 of 360 at 30/min** — the estimator's own advertised limits. At every rate strictly
    /// inside the band the behaviour is bit-identical, so this is an edge repair, not a retune.
    ///
    /// ⚠️ THE LOW EDGE IS THE WORSE ONE and was found only by sweeping it. The review that
    /// raised this named 30/min; 4/min is four times worse and nobody had looked. When a bound
    /// turns out to be wrong at one end, measure the other end before writing the fix.
    ///
    /// ⚠️ WIDENING THIS DOES NOT LET NOISE IN, and it is worth knowing why before touching it:
    /// the band is not the noise filter. `envConf` is — a hand with no respiratory swing has no
    /// envelope, so `confidence` stays far under the publish gate no matter what the band says.
    /// `TheBandEdgeIsMeasurableTests.testAStillHandStillPublishesNothing` holds that, and it is
    /// the test to read before changing this constant.
    ///
    /// 1.2 is a judgement — roughly "one jittered beat of slack at either end". What is derived
    /// is the SHAPE (accept ⊋ report), and that is what the guard pins.
    private static let bandTolerance = 1.2

    // MARK: State
    private var lastT: Double?
    private var trend = 0.0          // slow HR baseline (EMA)
    private var smooth = 0.0         // band-passed respiration signal
    private var prevSmooth = 0.0
    private var env = 0.0            // |smooth| envelope (normalization)
    private var lastCrossT: Double?  // last upward zero-crossing time
    private var periodEMA = 0.0      // smoothed respiration period (s)
    private var crossingCount = 0

    // MARK: Outputs
    /// Breath amplitude [0,1] — 1 = inhale peak (lungs full). 0.5 when no clear
    /// respiratory oscillation is present (drives the ball to mid-rest).
    public private(set) var amplitude = 0.5
    /// Estimated breathing rate (breaths/min); 0 until a cycle has been measured.
    public private(set) var ratePerMinute = 0.0
    /// How clear the respiratory oscillation is [0,1] — the UI should only trust the
    /// measured ball above a threshold and otherwise fall back to the paced guide.
    public private(set) var confidence = 0.0

    public init() {}

    /// Feed one instantaneous heart-rate sample (bpm) at time `t` (seconds).
    /// Out-of-range or non-finite samples and time gaps are ignored safely.
    public mutating func ingest(heartRate hr: Double, at t: Double) {
        guard hr.isFinite, hr > 20, hr < 240, t.isFinite else { return }

        guard let last = lastT else {       // first sample seeds the baseline
            lastT = t; trend = hr; smooth = 0; prevSmooth = 0
            return
        }
        let dt = t - last
        guard dt > 0 else { return }
        lastT = t
        guard dt < 5 else { return }        // long gap: skip this step (keep state)

        // High-pass: subtract the slow baseline.
        let aTrend = 1 - exp(-dt / Self.trendTau)
        trend += aTrend * (hr - trend)
        let hp = hr - trend

        // Low-pass the high-passed signal → respiration band.
        let aSmooth = 1 - exp(-dt / Self.smoothTau)
        prevSmooth = smooth
        smooth += aSmooth * (hp - smooth)

        // Decaying envelope of |smooth| for normalization.
        let aEnv = 1 - exp(-dt / Self.envTau)
        env += aEnv * (abs(smooth) - env)
        let e = Swift.max(env, 1e-6)

        // Normalized amplitude [0,1]; 0.5 with no oscillation. 1.4 ≈ peak/mean-abs
        // of a sine, so a clean breath swings roughly the full range.
        let norm = Swift.max(-1.0, Swift.min(1.0, smooth / (e * 1.4)))
        amplitude = 0.5 + 0.5 * norm

        // Upward zero-crossing marks one respiration cycle → rate.
        if prevSmooth <= 0, smooth > 0 {
            if let lc = lastCrossT {
                let period = t - lc
                let r = period > 0 ? 60.0 / period : 0
                // Accept into a band wider than the one we report in — see `bandTolerance`.
                if r >= Self.minRate / Self.bandTolerance, r <= Self.maxRate * Self.bandTolerance {
                    periodEMA = periodEMA == 0 ? period : periodEMA + 0.3 * (period - periodEMA)
                    if periodEMA > 0 {
                        // The published contract of `/echoelmusic/bio/breath/rate` is
                        // [minRate, maxRate]; accepting wider must never widen the REPORT.
                        ratePerMinute = (60.0 / periodEMA)
                            .clamped(to: Self.minRate...Self.maxRate)
                    }
                    crossingCount += 1
                }
            }
            lastCrossT = t
        }

        refreshConfidence(at: t)
    }

    /// Age `confidence` forward to `t` WITHOUT feeding a beat.
    ///
    /// ⭐ THE STALENESS TERMS ONLY RUN WHEN A BEAT ARRIVES, and that is not the same thing as
    /// "when time passes". `ingest` is the only writer of `confidence`, so a host that keeps
    /// publishing while the beat supply dries up freezes the last value indefinitely — the
    /// very latch the freshness term and the envelope veto were written to prevent, reached by
    /// a path neither of them can see.
    ///
    /// It is a real device state, not a thought experiment: `CameraAnalyzer` returns early
    /// without touching `rrIntervals`/`beatTimes` when it finds fewer than three peaks, while
    /// `fallbackBPM` keeps `estimatedBPM` and `bpmConfidence` alive off the autocorrelation.
    /// The analyzer names that case itself ("peaks<3 with a strong acf → rounded waveform").
    /// So the publisher goes on emitting bio frames at ~1 Hz with ZERO beats reaching here,
    /// and a confidence of 1.0 earned a minute ago keeps certifying a breathing rate.
    ///
    /// Hence the pull: the host ages on every publish that carries a live measurement, and
    /// staleness becomes a function of the clock rather than of the supply. Nothing else moves
    /// — the filters, the envelope and the cycle count are untouched, so a beat that arrives
    /// later behaves exactly as before.
    ///
    /// ⚠️ "Every publish" is deliberately NOT what the caller does, and the first version of
    /// this line said it did. THREE paths through `CameraRPPGBioPublisher`'s 1 Hz block skip
    /// the ageing, and a future reader deciding "can this estimator go stale?" needs all three:
    /// (1) the `shouldPublish` else-branch re-emits the last good frame for up to
    /// `bioHoldTicks` — bounded, and it carries the held frame's OWN timestamp, so
    /// timestamp-dedup consumers treat it as a no-op; (2) the `inboundRateEMA` guard `continue`s
    /// past the whole block; (3) the `guard tick % 10 == 0, let bus = self.bus` at the top of
    /// the block — `bus` is `weak`, so a released `EngineBus` also `continue`s. (2) and (3) are
    /// benign for the same reason: a claim that is never emitted cannot go stale.
    /// ⛔ The first version named only (1); the commit that corrected it named only (1) and (2)
    /// while its own summary bullet read "named two of three". An exhaustiveness claim has to be
    /// counted against the source each time it is edited, not extended by one.
    ///
    /// ⚠️ Nor can it be stated flatly that ageing never RAISES confidence — it holds for the
    /// case that matters and fails in two corners. (1) A fresh estimator with `lastT == nil`
    /// passes the guard trivially and lands on ~3.3e-7 instead of 0: `env` is 0, so `envConf`
    /// is the 1e-6 floor over 1.5. Six orders of magnitude below the 0.4 gate, and a rate of 0
    /// blocks it anyway. (2) `age(to:)` does NOT advance `lastT`, so a caller that ages
    /// backwards after ageing forwards re-evaluates at the earlier time and comes back up.
    /// The shipped caller passes monotonic `systemUptime`, so neither is reachable today.
    ///
    /// `t` must be on the same clock as `ingest` (the camera path uses
    /// `ProcessInfo.processInfo.systemUptime`). Ageing to a time before the last beat is
    /// refused rather than clamped: it means the caller mixed clocks, and silently accepting
    /// it would hide that.
    public mutating func age(to t: Double) {
        guard t.isFinite, t >= (lastT ?? t) else { return }
        refreshConfidence(at: t)
    }

    /// The confidence expression, evaluated at time `t`. Split out of `ingest` so `age(to:)`
    /// can run it without a sample; the arithmetic is unchanged.
    private mutating func refreshConfidence(at t: Double) {
        let e = Swift.max(env, 1e-6)

        // Confidence: meaningful swing AND a few consistent cycles seen — but read the veto
        // below before trusting that sentence: past four crossings the count term is dead and
        // the expression is `envConf * freshness` exactly.
        let envConf = Swift.min(1.0, e / 1.5)                 // ~1.5 bpm RSA = decent
        // ⭐ THE ENVELOPE VETOES THE COUNT, so the whole expression obeys one stated
        // invariant: `confidence <= envConf * freshness`. We may never claim more certainty
        // than the size of the swing supports, however many cycles we have counted.
        //
        // Without it the freshness term below is INERT against the failure that actually
        // ends a long take. Freshness keys on `lastCrossT`, so it only fires when the
        // crossings STOP — a flat heart rate. But a fingertip that drifts, or a hand that
        // relaxes, does not produce a flat trace: it produces a small noisy one, which keeps
        // manufacturing crossings inside the 4…30/min band. Then `crossingCount` goes on
        // rising, `lastCrossT` stays fresh, and confidence sits on the 0.5 floor while the
        // swing that justified it is gone. Simulated on the shipped constants — 60 s of clean
        // 6/min RSA followed by 90 s of a 0.15 bpm wobble — confidence held at 0.524 (gate
        // OPEN) with an envelope of 0.071, publishing a fabricated 11.9 breaths/min. With the
        // veto the same series ends at 0.048 and the gate closes.
        //
        // ⚠️ IT COSTS THE SHALLOWEST BREATHERS, and that is a deliberate trade, not an
        // oversight. Measured on 60 s of clean 6/min: an RSA swing of ±1.2 bpm (2.6 bpm
        // peak-to-peak) reads 0.448 (still measured), ±1.0 (2.1 p-p) reads 0.373 — below the
        // 0.4 gate, where the old blend would have said 0.686. The gate closes below ±1.07 at
        // phase 0 and ±1.28 at the worst phase. Such a body falls back to the paced guide
        // instead of driving the ball. That is the designed fallback; narrating a rate read
        // out of noise is not, and is the worse failure of the two.
        //
        // ⛔ The ± matters and the first version of this note omitted it. RSA is conventionally
        // quoted PEAK-TO-PEAK, so a bare "1.0 bpm" understates the cost by a factor of two to
        // anyone applying the convention. At the 6/min resonance rate — where the whole point
        // is that RSA is MAXIMISED — a healthy adult sits far above 2.6 bpm p-p, which is why
        // the trade is defensible on signal grounds and not merely on principle.
        //
        // ⚠️ AND IT DOES NOT YET DO THIS ON THE DEVICE. `CameraAnalyzer` takes peak times at
        // whole-sample resolution (no sub-sample interpolation) and the camera runs at
        // 7.5–15 fps, so every interval is quantised to one frame period — 1.6 bpm RMS at
        // 15 fps and 3.2 at 7.5 (peaks of ±4/±8), against the 1.5 bpm scale this floor is set
        // to. A still hand can therefore clear the gate on quantisation alone. (⛔ The first
        // version quoted only the PEAK and called it "several times" the floor. A floor
        // responds to the RMS, and the honest ratio is 1.1–2.2×, not 3–5×. Right direction,
        // overstated — and overstating the case for a fix is how a fix gets scoped wrong.)
        // The invariant here is right and strictly better than the old blend, but "separates a
        // shallow breather from noise" only becomes true of the shipped path once peak timing
        // is sub-sample — and #421 has since measured that naive 3-point parabolic
        // interpolation is WORSE than whole-sample at this signal's SNR, so that is not a
        // one-line change either. Do not quote this comment as evidence that it already works.
        let countConf = Swift.min(Swift.min(1.0, Double(crossingCount) / 4.0), envConf)

        // ⭐ FRESHNESS — a reported rate is only as good as the last cycle that produced it.
        //
        // `crossingCount` is monotonic and `ratePerMinute` holds its last value forever, so
        // without this term `countConf` pins at 1.0 after four cycles and `confidence`
        // acquires a permanent floor of 0.5 — above every consumer gate in this repo
        // (`CameraRPPGBioPublisher` uses 0.4). The estimator would go on certifying a rate
        // long after the breathing that produced it stopped.
        //
        // This was HARMLESS while the estimator was rebuilt on every publish: state could not
        // outlive one 10 s window. #343 made it live for a whole take, and in doing so turned
        // a bounded staleness into a latch. Measured on a 60 s 6/min series followed by a
        // perfectly flat heart rate: confidence settled at exactly 0.500 and never moved, so
        // "6.0 breaths/min, measured" was published indefinitely with no breathing at all.
        //
        // It is HALF the answer. Freshness catches the take that ends in a flat trace; the
        // envelope veto above catches the take that ends in a noisy one, where crossings keep
        // arriving and nothing here ever goes stale. Neither substitutes for the other.
        //
        // Grace is 1.5 expected periods (a real cycle always lands inside that), then a linear
        // fade to zero over the same span. The pipeline lag is SUBTRACTED FROM THE MEASURED
        // STALENESS rather than added to the grace — see below. Before the FIRST crossing there
        // is nothing to be stale about and the term is inert, which is why a fresh estimator
        // still behaves exactly as it did. The fallback period is the slowest supported rate:
        // with no measured period yet, assuming the shortest one would expire a slow breather.
        //
        // ⭐ THE ALLOWANCE PAYS FOR A DELAY THIS TERM CANNOT SEE. While the estimator was only
        // refreshed from inside `ingest`, the since-crossing age was measured at a BEAT time.
        // `age(to:)` moved the evaluation to wall-clock now, which adds the camera pipeline
        // between the beat and this call. That is measurement latency, not staleness, and
        // charging it to the breather is wrong. Swept over all 360 whole-degree breathing
        // phases at a 2.5 s lag: at 28 breaths/min the worst phase read confidence 0.284
        // WITHOUT the allowance — under the publisher's 0.4 gate, so a fast breather's own
        // measurement flickered off — and 0.487 with it. The cost at the other end is
        // negligible because the envelope veto dominates there: the 60 s-then-flat series that
        // `testAMeasuredRateExpiresWhenTheBreathingStops` drives ends at 0.0054 instead of
        // 0.0019, both far under the gate.
        //
        // ⛔ SUBTRACT FROM THE MEASURED AGE, DO NOT ADD TO `grace` — the first version added it
        // and the difference is not cosmetic, because `grace` appears TWICE: once as the flat
        // window and once as the fade denominator. Adding a constant there therefore also
        // STRETCHES the fade, which nothing about a fixed measurement lag justifies.
        //
        // The exact statement is analytic, not measured: subtracting A shifts the whole
        // freshness curve later by EXACTLY A at every rate, while adding A to a grace that
        // appears twice shifts it by A and then scales the fade by (1 + A/grace) — so the two
        // forms agree only where the fade has not started. At 6/min the flat window ends
        // 15 s after the crossing either way; the 0.4 crossing is what separates them. Time
        // from the last crossing to `confidence < 0.4`, PHASE 0, this file's own generator,
        // before / added 2.5 / subtracted 1.8: 6/min 24.00 → 28.00 → 25.80 s · 15/min
        // 9.06 → 12.83 → 10.86 s · 28/min 4.53 → 8.14 → 6.34 s. Subtracting buys the identical
        // fast-end protection (0.4871 at every phase — the same number to four decimals) for a
        // smaller extension of the stale window at every rate.
        //
        // ⛔ AND THE PHASE HAD TO BE NAMED. The first version of that table wrote 24.1 / 28.1 /
        // 25.9 for the 6/min row and 4.7 / 8.4 / 6.5 for the 28/min row, with no phase given.
        // The 28/min row reproduces only near phase 19–20°, the 15/min row near 2°, and the
        // 6/min row reproduces at NO phase at all — the achievable "before" values jump
        // 24.001 → 24.247 and 24.1 falls in the gap. Three lines above, this same paragraph
        // retracts a figure for exactly this reason ("when a table has two minima, name which
        // one"). A phase-free table is the same defect with more digits.
        //
        // ⛔ AND THE FIRST VERSION MISREAD ITS OWN RETRACTION. It said "an earlier draft quoted
        // 0.313 off a 180-phase sweep". No phase set produces 0.313 here: 180 phases give
        // 0.2841 and 360 give 0.2837. The 0.313 was the confidence at the phase with the worst
        // FRESHNESS, read out of the wrong column of my own table — so the cautionary example
        // in a paragraph about hand-picked figures was itself a number nobody could reproduce.
        // The lesson is narrower than "sweep": when a table has two minima, name which one.
        //
        // ⚠️ ABOVE 28.7/min A GROWING SHARE OF PHASES STILL FAILS THE GATE, and the first
        // version blamed Nyquist for it. That was written from ONE phase and the sweep refutes
        // it: at 30 breaths/min the measured rate is ~30 at 244 of 360 phases, 0 at 61, ~10 at
        // 53, and one phase each at 10.3 and 18.8 — the modal answer is the RIGHT one. So the
        // residual is a CONFIDENCE problem of the same lag/freshness kind, not a sampling
        // limit, and neither this allowance nor a larger one closes it (29/min worst phase at
        // the same 2.5 s lag: 0.000 before, 0.179 with subtract-1.8, 0.266 with subtract-2.5,
        // 0.318 under the previous commit's add-2.5 — all under the gate). Two real causes sit
        // under the 61 zeros at 30/min and are registered on the board, not fixed here:
        // `lastCrossT` is quantised to a beat (#423), and `r <= Self.maxRate` REJECTS a
        // crossing whose jitter puts it a hair over 30/min instead of accepting the measurement
        // into a wider band than it reports (#424) — at every one of those 61 phases, EVERY
        // crossing was rejected with r = 30.000000…x, so that cause is measured, not inferred.
        //
        // ⛔ THE HISTOGRAM ABOVE READ "244 / 61 / 54" FOR ONE COMMIT AND SUMMED TO 359. The
        // ~10 bucket is 53; the two stragglers at 10.3 and 18.8 belonged to no named bucket and
        // were silently dropped. A partial reading, quoted inside the paragraph that retracts a
        // partial reading — the same shape, one level down. If a partition is offered as
        // evidence, its parts have to add up to the sweep.
        let expectedPeriod = periodEMA > 0 ? periodEMA : 60.0 / Self.minRate
        let grace = expectedPeriod * 1.5
        // NAMED FOR WHAT IT IS: the raw age of the crossing, versus the age this term is
        // allowed to CHARGE the breather after the pipeline's own delay is paid off. The
        // earlier `sinceCross` held the raw value and then held the reduced one, which is
        // exactly the stale-name trap this repo has already paid for once (#373/#374).
        let rawSinceCross = lastCrossT.map { t - $0 } ?? 0
        let chargeableSince = Swift.max(0.0, rawSinceCross - Self.pullLagAllowance)
        let freshness = chargeableSince <= grace
            ? 1.0
            : Swift.max(0.0, 1.0 - (chargeableSince - grace) / grace)

        confidence = Swift.max(0.0, Swift.min(1.0, 0.5 * envConf + 0.5 * countConf)) * freshness
    }

    /// Clear all state (e.g. when the camera signal drops or a session restarts).
    public mutating func reset() { self = RespirationEstimator() }
}
