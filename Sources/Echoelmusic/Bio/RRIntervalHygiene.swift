//
//  RRIntervalHygiene.swift
//  Echoelmusic — Bio
//
//  Artifact rejection for beat-to-beat RR intervals, so the HRV numbers we SHOW as
//  real milliseconds are computed from beats that actually happened.
//
//  WHY THIS EXISTS (sensor audit 2026-07-25). The chest strap is the source we call
//  most accurate — `BioSource.ble.providesTrustedHRV` is true only for it, and it is
//  the only path allowed to drive frequency-domain coherence. It was also the only
//  path with ZERO artifact rejection: `PolarH10BioPublisher` appended every RR the
//  strap sent, straight into RMSSD/SDNN/pNN50. The UNTRUSTED camera path, meanwhile,
//  has done IQR outlier rejection on its intervals all along. The most-trusted source
//  was the least filtered.
//
//  That asymmetry matters because RMSSD is built from SUCCESSIVE DIFFERENCES: a single
//  missed beat (one RR that is the sum of two) or one extra beat inflates it by tens of
//  ms — and the app prints that as a real figure and feeds it to the sound.
//
//  METHOD (standard, not invented here):
//    • plausibility band — an RR outside 300…2000 ms (≈ 30…200 bpm) is not a human
//      resting-to-active beat interval; it is a dropped or doubled packet.
//    • Malik rule (Malik et al. 1989) — reject an interval differing by more than 20 %
//      from the previous ACCEPTED one. This is the classic ectopic-beat filter.
//
//  THE PART THAT IS EASY TO GET WRONG: you must not just delete the bad intervals and
//  carry on. RMSSD and pNN50 read CONSECUTIVE pairs, so a compacted array makes the two
//  beats either side of a removed one look adjacent — manufacturing exactly the large
//  successive difference the filter was meant to remove. So this returns SEGMENTS (runs
//  of genuinely consecutive accepted intervals) and `HRVMetrics` pools differences only
//  WITHIN a segment. Nothing is interpolated or synthesised: a rejected beat leaves a
//  gap, it is never replaced by a made-up value.
//
//  Pure Foundation, no device needed to test.
//

import Foundation

public enum RRIntervalHygiene {

    /// Shortest plausible beat interval (≈ 200 bpm).
    public static let minPlausibleMs = 300.0

    /// Longest plausible beat interval (≈ 30 bpm — covers a resting endurance athlete).
    public static let maxPlausibleMs = 2000.0

    /// Malik ectopic threshold: a beat may differ from its predecessor by at most this
    /// fraction. 20 % is the classic value; tighter starts rejecting real respiratory
    /// sinus arrhythmia, which is the signal we actually want to keep.
    public static let maxRelativeStep = 0.20

    /// Plausible instantaneous heart rate, for the strap's own HR field (which is
    /// transmitted separately from the RR intervals and can arrive corrupted on its own).
    public static let minPlausibleBPM = 25
    public static let maxPlausibleBPM = 250

    /// The accept/reject decision as a STREAMING gate, so the live beat path and the
    /// windowed metrics path share one implementation instead of drifting apart. The
    /// publisher runs a gate per arriving beat (to decide whether it may fire a discrete
    /// heartbeat event); `acceptedSegments` runs one over a whole window.
    /// `Sendable` is declared, not inferred: public types get no implicit conformance
    /// (SE-0302). Nothing sends a `Gate` across an isolation boundary today, so this
    /// costs nothing now — it just means a future caller gating on a background queue
    /// meets the value semantics it expects instead of a confusing conformance error.
    public struct Gate: Sendable {
        /// The last accepted interval — the Malik comparison anchor. `nil` means the next
        /// plausible beat starts a fresh run and cannot be judged against anything.
        public private(set) var anchorMs: Double?

        public init() {}

        /// Feed one interval. Returns true if it is a beat we are willing to call real.
        ///
        /// A rejection clears the anchor on purpose: comparing forever against a pre-gap
        /// value would reject every beat of a genuine sustained rate change (standing up,
        /// starting to move) and silently freeze HRV at the old body state.
        public mutating func accept(intervalMs rr: Double) -> Bool {
            guard rr.isFinite, rr >= minPlausibleMs, rr <= maxPlausibleMs else {
                anchorMs = nil
                return false
            }
            if let anchorMs, abs(rr - anchorMs) / anchorMs > maxRelativeStep {
                self.anchorMs = nil
                return false
            }
            anchorMs = rr
            return true
        }
    }

    /// Split a raw RR series (milliseconds) into runs of consecutive ACCEPTED intervals.
    ///
    /// Segments of length 1 are kept: they carry no successive difference, but they are
    /// still valid NN intervals for SDNN.
    public static func acceptedSegments(rrMs: [Double]) -> [[Double]] {
        var segments: [[Double]] = []
        var current: [Double] = []
        var gate = Gate()

        for rr in rrMs {
            if gate.accept(intervalMs: rr) {
                current.append(rr)
            } else if !current.isEmpty {
                segments.append(current)
                current = []
            }
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    /// Every accepted interval, order preserved — for metrics that do NOT read
    /// successive pairs (SDNN). Convenience over `acceptedSegments`.
    public static func accepted(rrMs: [Double]) -> [Double] {
        acceptedSegments(rrMs: rrMs).flatMap { $0 }
    }

    /// Fraction of the raw intervals that survived, 0…1 (1 when there was nothing to
    /// judge). A low value means the strap contact is poor — useful as an honest signal,
    /// never as a reason to fabricate the missing beats.
    public static func acceptedFraction(rrMs: [Double]) -> Double {
        guard !rrMs.isEmpty else { return 1 }
        return Double(accepted(rrMs: rrMs).count) / Double(rrMs.count)
    }

    /// Is this a beat rate a human body can plausibly be at?
    public static func isPlausibleBPM(_ bpm: Int) -> Bool {
        bpm >= minPlausibleBPM && bpm <= maxPlausibleBPM
    }
}
