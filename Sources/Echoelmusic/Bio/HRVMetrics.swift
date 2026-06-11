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
}
