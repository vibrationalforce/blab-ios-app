//
//  HRVMetrics.swift
//  Echoelmusic — Bio
//
//  Shared, pure time-domain HRV math so every source (Polar/BLE, camera rPPG,
//  …) computes the SAME metric the SAME way — no duplicated, drifting formulas.
//  All inputs are RR/NN intervals in MILLISECONDS (the HRV standard unit);
//  callers convert from their native unit at the boundary.
//
//  Definitions (Task Force 1996 / standard HRV):
//    • RMSSD — root mean square of successive RR differences (parasympathetic).
//    • SDNN  — standard deviation of NN intervals (overall variability).
//    • pNN50 — percent of successive |differences| greater than 50 ms.
//
//  Each returns 0 when there is not enough data (fewer than two intervals);
//  callers treat 0 as "unknown" and never display it for a real sensor.
//

import Foundation

public enum HRVMetrics {

    /// RMSSD in milliseconds. Pure; unit-testable without a device.
    public static func rmssd(rrMs: [Double]) -> Double {
        guard rrMs.count >= 2 else { return 0 }
        var sumSq = 0.0
        for i in 1..<rrMs.count {
            let d = rrMs[i] - rrMs[i - 1]
            sumSq += d * d
        }
        return (sumSq / Double(rrMs.count - 1)).squareRoot()
    }

    /// SDNN in milliseconds — sample standard deviation (divides by n−1).
    public static func sdnn(rrMs: [Double]) -> Double {
        let n = rrMs.count
        guard n >= 2 else { return 0 }
        let mean = rrMs.reduce(0, +) / Double(n)
        var sumSq = 0.0
        for x in rrMs {
            let d = x - mean
            sumSq += d * d
        }
        return (sumSq / Double(n - 1)).squareRoot()
    }

    /// pNN50 as a percentage [0…100]: successive |differences| > 50 ms.
    public static func pnn50(rrMs: [Double]) -> Double {
        guard rrMs.count >= 2 else { return 0 }
        var nn50 = 0
        for i in 1..<rrMs.count where abs(rrMs[i] - rrMs[i - 1]) > 50.0 {
            nn50 += 1
        }
        return Double(nn50) / Double(rrMs.count - 1) * 100.0
    }

    // MARK: - Segment-aware forms (after artifact rejection)

    // RMSSD and pNN50 read CONSECUTIVE pairs, so they cannot be fed a series that has
    // had bad beats deleted from the middle: the two survivors either side of a removed
    // interval are not adjacent in time, and treating them as adjacent manufactures the
    // very artifact the rejection removed. `RRIntervalHygiene.acceptedSegments` returns
    // runs of genuinely consecutive intervals; these overloads pool differences only
    // WITHIN a run. SDNN has no such constraint — it is a spread over the accepted NN
    // intervals — so it simply flattens.

    /// RMSSD in milliseconds over all WITHIN-segment successive differences.
    /// Returns 0 when no segment holds a pair (the "unknown" convention above).
    public static func rmssd(segments: [[Double]]) -> Double {
        var sumSq = 0.0
        var pairs = 0
        for segment in segments where segment.count >= 2 {
            for i in 1..<segment.count {
                let d = segment[i] - segment[i - 1]
                sumSq += d * d
                pairs += 1
            }
        }
        guard pairs > 0 else { return 0 }
        return (sumSq / Double(pairs)).squareRoot()
    }

    /// SDNN in milliseconds over every accepted interval, gaps closed — a spread has no
    /// adjacency requirement, so pooling across segments is the standard definition.
    public static func sdnn(segments: [[Double]]) -> Double {
        sdnn(rrMs: segments.flatMap { $0 })
    }

    /// pNN50 [0…100] over all WITHIN-segment successive differences.
    public static func pnn50(segments: [[Double]]) -> Double {
        var nn50 = 0
        var pairs = 0
        for segment in segments where segment.count >= 2 {
            for i in 1..<segment.count {
                if abs(segment[i] - segment[i - 1]) > 50.0 { nn50 += 1 }
                pairs += 1
            }
        }
        guard pairs > 0 else { return 0 }
        return Double(nn50) / Double(pairs) * 100.0
    }
}
