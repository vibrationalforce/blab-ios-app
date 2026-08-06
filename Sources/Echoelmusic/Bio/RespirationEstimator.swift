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
    /// ⛔ A FOURTH TERM WAS IN THE FIRST VERSION AND DOES NOT BELONG: "the crossing is stamped
    /// at a beat (≈1 s at rest)". That quantisation is real, but it is already inside
    /// `lastBeat − lastCrossT`, so adding it to a lag measured FROM the last beat counts it
    /// twice — and it applied identically before the pull, so it is not part of the delta the
    /// pull introduced. That mistake put the constant at 2.5 s and the comment opened with
    /// "THE ALLOWANCE IS NOT PADDING", which was then exactly what the extra second was.
    /// The correction narrows the case as well as the number: with the three real terms the
    /// worst phase at 28 breaths/min reads 0.457 at 15 fps — no defect — and 0.394 at 7.5 fps,
    /// under the 0.4 gate. This is a slow-device defect, and saying so is the point.
    private static let pullLagAllowance = 1.8

    // MARK: Respiration band (breaths/min)
    public static let minRate = 4.0
    public static let maxRate = 30.0

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
                if r >= Self.minRate, r <= Self.maxRate {
                    periodEMA = periodEMA == 0 ? period : periodEMA + 0.3 * (period - periodEMA)
                    if periodEMA > 0 { ratePerMinute = 60.0 / periodEMA }
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
    /// this line said it did. TWO paths through `CameraRPPGBioPublisher`'s 1 Hz block skip the
    /// ageing, and a future reader deciding "can this estimator go stale?" needs both:
    /// (1) the `shouldPublish` else-branch re-emits the last good frame for up to
    /// `bioHoldTicks` — bounded, and it carries the held frame's OWN timestamp, so
    /// timestamp-dedup consumers treat it as a no-op; (2) the `inboundRateEMA` guard above it
    /// `continue`s past the whole block, so nothing is published AND nothing is aged — benign,
    /// because a claim that is never emitted cannot go stale. The first version named only (1).
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
        // refreshed from inside `ingest`, `sinceCross` was measured at a BEAT time. `age(to:)`
        // moved the evaluation to wall-clock now, which adds the camera pipeline between the
        // beat and this call. That is measurement latency, not staleness, and charging it to
        // the breather is wrong. Swept over all 360 whole-degree breathing phases at a 2.5 s
        // lag: at 28 breaths/min the worst phase read confidence 0.284 WITHOUT the allowance —
        // under the publisher's 0.4 gate, so a fast breather's own measurement flickered off —
        // and 0.487 with it. The cost at the other end is negligible because the envelope veto
        // dominates there: the 60 s-then-flat series that
        // `testAMeasuredRateExpiresWhenTheBreathingStops` drives ends at 0.0054 instead of
        // 0.0019, both far under the gate.
        //
        // ⛔ SUBTRACT FROM `sinceCross`, DO NOT ADD TO `grace` — the first version added it and
        // the difference is not cosmetic, because `grace` appears TWICE: once as the flat
        // window and once as the fade denominator. Adding a constant there therefore also
        // STRETCHES the fade, which nothing about a fixed measurement lag justifies. Measured
        // time from the last crossing to `confidence < 0.4`, before / added 2.5 / subtracted
        // 1.8: 6/min 24.1 → 28.1 → 25.9 s · 15/min 9.0 → 12.8 → 10.8 s · 28/min 4.7 → 8.4 →
        // 6.5 s. Subtracting buys the identical fast-end protection (0.487 at every phase, the
        // same number) for a smaller extension of the stale window at every rate.
        //
        // ⛔ AND THE FIRST VERSION MISREAD ITS OWN RETRACTION. It said "an earlier draft quoted
        // 0.313 off a 180-phase sweep". No phase set produces 0.313 here: 180 phases give
        // 0.2841 and 360 give 0.2837. The 0.313 was the confidence at the phase with the worst
        // FRESHNESS, read out of the wrong column of my own table — so the cautionary example
        // in a paragraph about hand-picked figures was itself a number nobody could reproduce.
        // The lesson is narrower than "sweep": when a table has two minima, name which one.
        //
        // ⚠️ ABOVE ~28.5/min A GROWING SHARE OF PHASES STILL FAILS THE GATE, and the first
        // version blamed Nyquist for it. That was written from ONE phase and the sweep refutes
        // it: at 30 breaths/min the measured rate is 30 at 244 of 360 phases, 0 at 61 and ~10
        // at 54 — the modal answer is the RIGHT one. So the residual is a CONFIDENCE problem of
        // the same lag/freshness kind, not a sampling limit, and neither this allowance nor a
        // larger one closes it (29/min worst phase at the same 2.5 s lag: 0.000 before, 0.179
        // with 1.8, 0.266 with 2.5 — all under the gate). Two real causes sit under the 61
        // zeros at 30/min and are
        // registered on the board, not fixed here: `lastCrossT` is quantised to a beat, and
        // line `r <= Self.maxRate` REJECTS a crossing whose jitter puts it a hair over 30/min
        // instead of accepting the measurement into a wider band than it reports.
        let expectedPeriod = periodEMA > 0 ? periodEMA : 60.0 / Self.minRate
        let grace = expectedPeriod * 1.5
        let measuredSince = lastCrossT.map { t - $0 } ?? 0
        let sinceCross = Swift.max(0.0, measuredSince - Self.pullLagAllowance)
        let freshness = sinceCross <= grace
            ? 1.0
            : Swift.max(0.0, 1.0 - (sinceCross - grace) / grace)

        confidence = Swift.max(0.0, Swift.min(1.0, 0.5 * envConf + 0.5 * countConf)) * freshness
    }

    /// Clear all state (e.g. when the camera signal drops or a session restarts).
    public mutating func reset() { self = RespirationEstimator() }
}
