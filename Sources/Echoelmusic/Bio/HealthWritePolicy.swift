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
    /// own RSA generator, **214 of 360 admitted at a 42 bpm pulse** — and all nine pulses of the
    /// sibling sweep, because quoting four of nine is how this file's neighbours have been wrong
    /// before: 42 → 214, 46 → 217, 50 → 218, 55 → 209, 62 → 219, 70 → 217, **84 → 137**,
    /// 90 → 210, **100 → 146**. The two WORST were the two the first version omitted. This is at
    /// the resonance rate the product is built around.
    ///
    /// ⭐ AND THE COST WAS NOT "FEWER SAMPLES", IT WAS BIAS — the filter cut at almost exactly
    /// the mean of the distribution, so the survivors were the high half. Mean error of the
    /// WRITTEN subset vs. the whole published population, same sweep: pulse 42 **+0.1522 vs
    /// +0.0497**, 46 +0.1430 vs +0.0492, 62 +0.1212 vs +0.0457, 90 +0.1093 vs +0.0415 — a ratio
    /// of ~3 at these four, and **2.54× (pulse 55) to 4.38× (pulse 84)** across all nine, so
    /// "roughly three" is the middle of a band and not a constant. A range filter that truncates
    /// near the mean does not clean a measurement, it skews it. At the widened bound every
    /// published phase is admitted at all nine pulses and the written bias IS the population
    /// bias.
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
    /// ⛔ "IT ADMITS NOTHING NEW THAT IS GARBAGE" STOOD HERE AND WAS BOTH FALSE IN ITS PREMISE
    /// AND UNMEASURED IN ITS CONCLUSION. The premise named `CameraRPPGBioPublisher` as "the only
    /// producer of a non-zero `breathRate` in `Sources/`" — wrong: `BioSimulator` writes a flat
    /// 12 and `HealthKitBioPublisher` forwards Apple's own value. It then cited
    /// `PolarH10BioPublisher`, which publishes 0. So it picked the wrong exemplars AND never
    /// named the gate that actually does the work: **`isWritableSource`** (`.ble | .cameraPPG`),
    /// checked in `shouldWrite` before `values(for:)` is ever reached, excludes `.fallback` and
    /// `.healthKit`. The conclusion survives — only the estimator's report can deliver a non-zero
    /// respiratory value to `HealthKitWriter` — but it survives for a reason the sentence did not
    /// give. (The high bound is untouched: 40 is well above the accept ceiling of 31.8.)
    ///
    /// ⚠️ AND WHAT THE WIDENING ADMITS WAS THEN ACTUALLY MEASURED, because "nothing new that is
    /// garbage" was an assertion from the accept floor alone. A body breathing BELOW the band
    /// does publish, and the new window `[3.7736, 4.0)` admits more of it: at 3.0 breaths/min,
    /// pulse 42, 36 of 360 phases publish and the admitted count goes **10 → 36**, with 11 of
    /// them sitting within 0.01 of the accept floor. That floor cluster is real and is the
    /// nearest relative of the rail #424 removed.
    ///
    /// ⭐ THE DECIDING MEASUREMENT IS THE ONE NEITHER SIDE HAD: the newly admitted sub-band
    /// samples are **less wrong than the ones already being written**, because the old bound kept
    /// exactly the largest over-reads. Mean |error| against the true rate, 4.0 → 3.7:
    /// 3.0/min · pulse 42 **1.1426 → 0.8850**, pulse 90 1.0628 → 0.9391 (pulse 60 wrote NOTHING
    /// before and now writes 17 at 0.9645); 3.5/min · pulse 42 0.8156 → 0.5432, 60 0.8890 →
    /// 0.7325, 90 0.7891 → 0.6909. The widening improves the out-of-band case as well; it does
    /// not merely spare it.
    ///
    /// ⚠️ IT IS STILL A TRADE, AND THE TRADE IS STRUCTURAL, NOT NUMERIC. The empirically minimal
    /// bound is ~**3.792** (the lowest report a genuine `minRate` body produces anywhere over
    /// pulses 37…110), and a bound there would admit every correct measurement while rejecting
    /// the floor cluster. 3.7 is lower on purpose: the guard chains this range to
    /// `RespirationEstimator.reportableRange`, and a bound fitted to today's measurements would
    /// have to be re-fitted after every DSP change — which is the maintenance failure this file's
    /// neighbours document at length. Chain over fit, deliberately.
    ///
    /// ⚠️ THERE ARE FIVE RESPIRATION BANDS IN THIS REPO — the fifth is the arousal window inside
    /// `bioNormalized` (`Sequencer/RecordAnchor.swift`), `3.0...24.0` since #433; all five are
    /// enumerated at `RespirationEstimator.reportableRange`. (⛔ This called that fifth band "the
    /// most reachable" and put it "on the shipped capture path": both were wrong — the record
    /// controller is doorless, see the retraction at that enumeration.)
    /// `BioSampleFrame.plausibleBreathRate`
    /// is `3...40` (it gates `hasMeasuredBreath`, OSC egress and what `PerformerSignature`
    /// learns), `RespirationEstimator.reportableRange` is 3.7736…31.8 (what the estimator can
    /// EMIT — the one this range is chained to, two paragraphs above), `ModSource.breathRate
    /// .range` is `3...30` (a modulation scaling range, not a validity test — it shares the
    /// gate's LOW bound since #429 and keeps its own top), and this one is `3.7...40`. They are
    /// NOT redundant — writing into a health record is a stricter act than lighting a readout —
    /// but a reader asking "why not reuse the repo-wide band?" deserves the answer here rather
    /// than a SIXTH definition of "plausible" appearing later (#416). (⛔ It said "FIFTH" while
    /// the paragraph above it had just been edited to list five. The ordinal was made stale by
    /// its own commit, six lines away — the shortest-lived of this file's stale numbers.)
    ///
    /// ⚠️ AND "FIVE" IS A CLAIM ABOUT THE MEASUREMENT/SCALING BANDS ONLY. At least four more
    /// breath-rate bands exist for other purposes — `RespirationEstimator.minRate/maxRate`
    /// (4…30, what the estimator TARGETS), `BreathPacer.minRate/maxRate` (5…12, which turns out
    /// to constrain nothing — see `RecordAnchor.bioNormalized`), `ResonanceFinder` (5…7, the
    /// search grid) and `EntrainmentEngine.minBreathsPerMinute` (4.5…7, the safe pacing band).
    /// Those describe what we ASK a body to do; the five here describe what we BELIEVE a body
    /// did. Stated because #433 turned a pacing band into a load-bearing input for one of the
    /// five, and the sentence was silent about the distinction.
    ///
    /// ⛔ THIS SAID "THREE BANDS ... AND THIS IS THE NARROWEST" AND BOTH HALVES WERE WRONG
    /// (and the first correction said FOUR, still one short — see above).
    /// It omitted `reportableRange` while the same file chains to it, and it is not the
    /// narrowest by span (36.3 here against 21 for `bioNormalized`'s arousal window and 27 for
    /// `ModSource.breathRate.range` — ⛔ that 27 was cited as the minimum and stopped being one
    /// when #433 added a 21, in the very sentence whose point is that an uncomputed superlative
    /// rots) nor even the strictest low bound (3.7736 for `reportableRange` sits above this
    /// 3.7). What is true is narrower and duller: this is the only one of the five that decides
    /// what enters a health
    /// record, and its low bound sits DELIBERATELY below the estimator's floor — chain over
    /// fit, argued above. A superlative that survives four edits without being recomputed is
    /// exactly the shape this file keeps apologising for.
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
