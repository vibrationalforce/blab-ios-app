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
    public static let respiratoryRange: ClosedRange<Double> = 4...40      // breaths/min

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
