// BioAutomationRecorder.swift
// Per-track BIO record (B18) — the PURE half: turn a stream of bio samples over
// transport time into an AutomationLane the arrangement can replay.
//
// A bio-armed lane records the body (heart / breath / coherence) as a normalized
// [0..1] automation curve, song-absolute in 480-PPQ ticks. The device-gated
// TakeRecorder polls `bus.usableBio()` at ~10 Hz (the audited snapshot path — NOT
// the reserved SPSC queue) and feeds each sample here; this decides which samples
// become keyframes. Pure value logic — no engine, no audio, no @MainActor — so the
// capture/decimation contract is unit-tested on every platform. Consumers replay
// the lane via `AutomationLane.value(atTick:)`, identical to any other automation.

import Foundation

/// Accumulates normalized bio samples into a compact `AutomationLane`.
public struct BioAutomationRecorder: Sendable {

    /// Parameter key the recorded lane drives (e.g. a bio source key). The lane only
    /// stores normalized values; the consumer interprets the key.
    public let parameter: String
    /// Song-absolute tick where recording started; samples before it are ignored.
    public let anchorTick: Int
    /// Minimum tick gap between kept keyframes (decimation) — a 10 Hz bio stream over
    /// a long take would otherwise bloat the lane. Default = one transport step (120t).
    public let minTickInterval: Int

    private var captured: [AutomationPoint] = []
    private var lastKeptTick: Int?

    public init(parameter: String, anchorTick: Int = 0,
                minTickInterval: Int = TimelineTime.ticksPerTransportStep) {
        self.parameter = parameter
        self.anchorTick = max(0, anchorTick)
        self.minTickInterval = max(1, minTickInterval)
    }

    /// Number of keyframes kept so far.
    public var pointCount: Int { captured.count }

    /// Record a normalized [0..1] bio value at a song-absolute tick. Ignored before
    /// the anchor; decimated so no two kept keyframes are closer than
    /// `minTickInterval` (the first sample at/after the anchor is always kept, and a
    /// non-advancing / backwards tick is skipped by the same guard). Non-finite or
    /// out-of-range values are clamped to [0..1] (via `AutomationPoint`).
    public mutating func capture(value: Double, atTick tick: Int) {
        guard tick >= anchorTick else { return }
        if let last = lastKeptTick, tick < last + minTickInterval { return }
        captured.append(AutomationPoint(tick: tick, value: value))   // clamps value + tick
        lastKeptTick = tick
    }

    /// The recorded lane (keyframes sorted ascending by tick). Empty when nothing was
    /// captured — the caller can drop an empty take rather than commit a flat lane.
    public func lane() -> AutomationLane {
        AutomationLane(parameter: parameter, points: captured)
    }

    /// True when at least one keyframe was captured.
    public var hasContent: Bool { !captured.isEmpty }
}
