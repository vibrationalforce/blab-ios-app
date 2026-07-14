// AutomationGestureRecorder.swift
// Multi-dimensional automation GESTURE record — the PURE half of a Touch surface
// that captures SEVERAL named parameter dimensions AT ONCE (e.g. an immersive
// object's X, Y, Z, focus, and an effect param), so one finger-gesture over the
// surface lands as N synchronized `AutomationLane`s the arrangement can replay.
//
// This is the N-parameter sibling of `BioAutomationRecorder` (which records ONE
// bio dimension). It mirrors that recorder's contract EXACTLY — anchor-gate +
// per-lane decimation + [0...1] clamp — but keeps an independent decimation
// cursor per parameter so a 10-D gesture stays compact and each dimension keeps
// its own keyframe cadence. Emitted lanes carry CLIP-RELATIVE ticks (anchor
// subtracted), so a recorded gesture drops straight into a clip at tick 0.
//
// Pure value logic — no engine, no audio, no @MainActor, Foundation only — so
// the capture/decimation/anchor contract is unit-tested on every platform
// (Linux included). Control-plane math: no audio-thread work, no allocation
// concerns beyond ordinary value semantics.

import Foundation

/// Accumulates normalized samples for several named parameters at once, one
/// compact `AutomationLane` per parameter that received content.
public struct AutomationGestureRecorder: Sendable {

    /// The parameter dimensions this recorder tracks. Only keys in this set are
    /// captured; a value for an unknown key is ignored (the gesture defines its
    /// own dimensions up front). Order here is the order `lanes()` returns.
    public let parameters: [String]
    /// Song-absolute tick where the gesture started; samples before it are
    /// ignored, and every emitted keyframe tick is relative to this anchor.
    public let anchorTick: Int
    /// Minimum tick gap between kept keyframes, applied PER parameter — a
    /// high-rate touch stream would otherwise bloat every lane. Each dimension
    /// keeps its own decimation cursor.
    public let minTickInterval: Int

    /// Clip-relative keyframes per parameter (only params that got a value appear).
    private var captured: [String: [AutomationPoint]] = [:]
    /// Last KEPT song-absolute tick per parameter (the decimation cursor).
    private var lastKeptTick: [String: Int] = [:]
    /// Fast membership test for `parameters`.
    private let known: Set<String>

    public init(parameters: [String], anchorTick: Int = 0, minTickInterval: Int = 60) {
        self.parameters = parameters
        self.anchorTick = max(0, anchorTick)
        self.minTickInterval = max(1, minTickInterval)
        self.known = Set(parameters)
    }

    /// Total keyframes kept across all parameters.
    public var pointCount: Int { captured.values.reduce(0) { $0 + $1.count } }

    /// Keyframes kept so far for one parameter (0 if never captured / unknown).
    public func pointCount(for parameter: String) -> Int {
        captured[parameter]?.count ?? 0
    }

    /// Record a snapshot of one or more parameter values at a song-absolute tick.
    ///
    /// Each PRESENT, KNOWN parameter is handled independently and identically to
    /// `BioAutomationRecorder.capture`: ignored before the anchor; decimated so
    /// no two kept keyframes for THAT parameter are closer than `minTickInterval`
    /// (the first sample at/after the anchor is always kept, and a non-advancing
    /// or backwards tick is skipped by the same guard); the value is clamped to
    /// [0...1] (via `AutomationPoint`). Stored ticks are clip-relative
    /// (`tick - anchorTick`). Unknown keys and absent parameters do nothing.
    public mutating func capture(_ values: [String: Double], atTick tick: Int) {
        guard tick >= anchorTick else { return }
        let relativeTick = tick - anchorTick
        for (parameter, value) in values {
            guard known.contains(parameter) else { continue }
            if let last = lastKeptTick[parameter], tick < last + minTickInterval { continue }
            captured[parameter, default: []].append(
                AutomationPoint(tick: relativeTick, value: value))   // clamps value + tick
            lastKeptTick[parameter] = tick
        }
    }

    /// One `AutomationLane` per parameter that captured at least one keyframe,
    /// in declared `parameters` order. Parameters that never received a value are
    /// dropped (no flat/empty lane). Ticks are clip-relative.
    public func lanes() -> [AutomationLane] {
        parameters.compactMap { parameter in
            guard let points = captured[parameter], !points.isEmpty else { return nil }
            return AutomationLane(parameter: parameter, points: points)
        }
    }

    /// True when at least one keyframe was captured for any parameter.
    public var hasContent: Bool { !captured.isEmpty }
}
