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
    /// Hence the pull: the host calls this every publish, and staleness becomes a function of
    /// the clock rather than of the supply. Nothing else moves — the filters, the envelope and
    /// the cycle count are untouched, so a beat that arrives later behaves exactly as before,
    /// and because only the freshness factor depends on `t`, ageing can never RAISE confidence.
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
        // 7.5–15 fps, so every interval is quantised to 67–133 ms — ±4 to ±8 bpm of aliasing
        // noise at 60 bpm, several times the 1.5 bpm scale this floor is set to. A still hand
        // can therefore clear the gate on quantisation alone. The invariant here is right and
        // strictly better than the old blend, but "separates a shallow breather from noise"
        // only becomes true of the shipped path once peak timing is sub-sample. Do not quote
        // this comment as evidence that it already does.
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
        // Grace is 1.5 expected periods (a real cycle always lands inside that), then a
        // linear fade to zero over another 1.5 — so at the 6/min resonance rate the gate
        // closes ~30 s after the last crossing. Before the FIRST crossing there is nothing to
        // be stale about and the term is inert, which is why a fresh estimator still behaves
        // exactly as it did. The fallback period is the slowest supported rate: with no
        // measured period yet, assuming the shortest one would expire a slow breather.
        let expectedPeriod = periodEMA > 0 ? periodEMA : 60.0 / Self.minRate
        let grace = expectedPeriod * 1.5
        let sinceCross = lastCrossT.map { t - $0 } ?? 0
        let freshness = sinceCross <= grace
            ? 1.0
            : Swift.max(0.0, 1.0 - (sinceCross - grace) / grace)

        confidence = Swift.max(0.0, Swift.min(1.0, 0.5 * envConf + 0.5 * countConf)) * freshness
    }

    /// Clear all state (e.g. when the camera signal drops or a session restarts).
    public mutating func reset() { self = RespirationEstimator() }
}
