//
//  HealthWritePolicy.swift
//  Echoelmusic — Bio
//
//  Pure, platform-agnostic rules for writing Echoel's OWN measurements back to
//  Apple Health (opt-in). No HealthKit import here so the decision logic is unit-
//  testable on every CI host; the actual HKHealthStore calls live in
//  HealthKitWriter (HealthKit-guarded).
//
//  Two honesty/safety rules are encoded here:
//   1. NON-CIRCULAR: only write readings WE measured (camera rPPG / BLE strap) —
//      never echo HealthKit/Watch data back into Health (that would duplicate).
//   2. TRUSTWORTHY UNITS ONLY: we write heart rate (BPM) and respiratory rate
//      (breaths/min), which we have as real physical values. We do NOT write HRV
//      (our `hrvNormalized` is a 0…1 control value, not SDNN in ms).
//

import Foundation

public enum HealthWritePolicy {

    /// Minimum seconds between writes, so a 5 s poll never floods Health with
    /// hundreds of near-identical samples.
    public static let minWriteGap: TimeInterval = 15

    /// Plausible physiological ranges (anything outside is dropped, not written).
    public static let heartRateRange: ClosedRange<Double> = 30...240      // BPM

    /// ⛔ THE LOW BOUND WAS 4.0 AND THAT WAS THE WRONG NUMBER (#426). It was copied from
    /// `RespirationEstimator.minRate` — the rate the estimator TARGETS — while the value that
    /// actually arrives here is the raw EMA of accepted periods, which lives in the wider
    /// `RespirationEstimator.reportableRange` (3.7736…31.8 today). A body breathing at exactly
    /// 4/min therefore had a large share of its CORRECT measurements silently dropped on the
    /// write path: swept over all 360 whole-degree breathing phases, 60 s takes, the estimator's
    /// own RSA generator, **214 of 360 admitted at a 42 bpm pulse** (217 at 46, 219 at 62,
    /// 210 at 90) — at the resonance rate the product is built around.
    ///
    /// ⭐ AND THE COST WAS NOT "FEWER SAMPLES", IT WAS BIAS — the filter cut at almost exactly
    /// the mean of the distribution, so the survivors were the high half. Mean error of the
    /// WRITTEN subset vs. the whole published population, same sweep: pulse 42 **+0.1522 vs
    /// +0.0497**, 46 +0.1430 vs +0.0492, 62 +0.1212 vs +0.0457, 90 +0.1093 vs +0.0415. A range
    /// filter that truncates near the mean does not clean a measurement, it skews it. At the
    /// widened bound every published phase is admitted at all four pulses and the written bias
    /// IS the population bias.
    ///
    /// ⚠️ WIDEN, DO NOT CLAMP — #424 paid for that lesson on this exact path. A clamped report
    /// published exactly 4.000 at 358 of 360 phases for a body breathing 3.5/min, and 4.0 is
    /// inside this range, so a fabricated number would have been written to Apple Health. The
    /// low bound moves; nothing is rounded up into it.
    ///
    /// ⭐ WHY 3.7 IS A LITERAL AND NOT `RespirationEstimator.reportableRange.lowerBound`. What
    /// Echoel writes into a user's health record must not widen as a side effect of a DSP
    /// constant being retuned. The two are chained by a TEST instead
    /// (`Tests/CISmoke/TheBreathEdgeReachesHealthTests`): if the estimator can ever report
    /// outside this range, that guard goes red and the widening becomes a decision someone makes
    /// on purpose. 3.7 sits below both the accept floor (3.7736) and the lowest report measured
    /// over pulses 37…110 (3.7920 at pulse 38), with margin.
    ///
    /// ⚠️ It admits nothing new that is garbage: the only producer of a non-zero `breathRate` in
    /// `Sources/` is `CameraRPPGBioPublisher`, which forwards this estimator's report, and the
    /// estimator cannot emit below its accept floor. `PolarH10BioPublisher` publishes a literal
    /// 0, which stays rejected. The high bound is untouched — 40 is already well above the
    /// accept ceiling of 31.8.
    public static let respiratoryRange: ClosedRange<Double> = 3.7...40    // breaths/min

    /// Sources whose readings Echoel itself measures and Apple Health would not
    /// otherwise have — the only ones safe to write (non-circular).
    public static func isWritableSource(_ source: BioSource) -> Bool {
        source == .ble || source == .cameraPPG
    }

    /// Whether to write a sample for this frame now. Pure + deterministic.
    public static func shouldWrite(frame: BioSampleFrame?, enabled: Bool, authorized: Bool,
                                   lastWriteAt: TimeInterval, now: TimeInterval) -> Bool {
        guard enabled, authorized, let f = frame else { return false }
        guard now - lastWriteAt >= minWriteGap else { return false }
        guard isWritableSource(f.source) else { return false }
        // Need at least a valid heart rate to bother writing.
        let hr = Double(f.heartRateBPM)
        return hr.isFinite && heartRateRange.contains(hr)
    }

    /// The trustworthy values to write for a frame: heart rate (always, once
    /// `shouldWrite` passed) and respiratory rate when it is in range.
    public static func values(for frame: BioSampleFrame) -> (heartRate: Double, respiratoryRate: Double?) {
        let hr = Double(frame.heartRateBPM)
        let br = Double(frame.breathRate)
        let resp = (br.isFinite && respiratoryRange.contains(br)) ? br : nil
        return (hr, resp)
    }
}
