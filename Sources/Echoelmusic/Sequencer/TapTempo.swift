//
//  TapTempo.swift
//  Echoelmusic
//
//  Tap-tempo estimator — a performance staple. Tap a button in time and it returns
//  the BPM from the averaged inter-tap interval. Pure value type (no timers, no
//  audio, no UI) so it is trivially unit-testable; the view feeds it a monotonic
//  clock and applies the result to the transport + metronome.
//

import Foundation

public struct TapTempo: Sendable {

    /// A gap longer than this (seconds) starts a fresh measurement — the performer
    /// stopped tapping and began a new tempo.
    public var resetGap: TimeInterval = 2.0
    /// Clamp the estimate to the app's musical range.
    public var minBPM: Double = 40
    public var maxBPM: Double = 240
    /// Sliding window of taps to average (smooths jitter without lagging changes).
    public var maxTaps: Int = 6

    private var taps: [TimeInterval] = []

    public init() {}

    /// Record a tap at monotonic time `now` (e.g. `ProcessInfo.processInfo.systemUptime`).
    /// Returns the current BPM estimate once at least two taps exist within the window,
    /// otherwise nil (the first tap of a new measurement).
    public mutating func tap(at now: TimeInterval) -> Double? {
        if let last = taps.last, now - last > resetGap { taps.removeAll() }
        taps.append(now)
        if taps.count > maxTaps { taps.removeFirst(taps.count - maxTaps) }
        guard taps.count >= 2 else { return nil }
        // Pair each tap with the previous → inter-tap intervals (later − earlier).
        let intervals = zip(taps.dropFirst(), taps).map { $0 - $1 }
        let avg = intervals.reduce(0, +) / Double(intervals.count)
        guard avg > 0 else { return nil }
        let bpm = 60.0 / avg
        return min(max(bpm, minBPM), maxBPM)
    }

    /// Forget the current measurement (e.g. when the field loses focus).
    public mutating func reset() { taps.removeAll() }
}
