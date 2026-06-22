// AutomationLane.swift
// Echoel — time-based parameter automation: a named lane of keyframes that a
// parameter follows over song time (Ableton-style automation, the founder's
// "arrangiert … mit automationen"). Pure value types in PPQ ticks (same time
// base as `Note`), so a whole automated arrangement persists as JSON and the
// interpolation is fully unit-testable without any audio engine or clock.
//
// The lane is parameter-AGNOSTIC: values are normalized [0...1]; the consumer
// maps that to its own range (Hz, dB, mix). Playback reads `value(atTick:)` each
// block and writes the result to the live param — wiring lands in a later cycle.

import Foundation

/// How a keyframe reaches the NEXT keyframe.
public enum AutomationCurve: String, Codable, Sendable, CaseIterable {
    /// Step: hold this value until the next keyframe (no glide).
    case hold
    /// Straight-line interpolation to the next keyframe.
    case linear
}

/// One keyframe: a normalized value at an absolute PPQ tick.
public struct AutomationPoint: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Absolute PPQ tick (`Note.ticksPerQuarter`), clamped to ≥0.
    public var tick: Int
    /// Normalized value [0...1].
    public var value: Double
    /// Shape of the segment from this point to the next.
    public var curve: AutomationCurve

    public init(id: UUID = UUID(), tick: Int, value: Double, curve: AutomationCurve = .linear) {
        self.id = id
        self.tick = max(0, tick)
        self.value = AutomationPoint.clamp(value)
        self.curve = curve
    }

    static func clamp(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return Swift.min(1, Swift.max(0, v))
    }
}

/// A named automation lane: keyframes (kept sorted by tick) for one parameter.
public struct AutomationLane: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Parameter key the lane drives, e.g. "filter.cutoff" or "mix.level". The
    /// consumer interprets it; the lane only stores normalized values.
    public var parameter: String
    /// Keyframes, always sorted ascending by tick (ties keep insertion order).
    public private(set) var points: [AutomationPoint]

    public init(id: UUID = UUID(), parameter: String, points: [AutomationPoint] = []) {
        self.id = id
        self.parameter = parameter
        self.points = points.sorted { $0.tick < $1.tick }
    }

    public var isEmpty: Bool { points.isEmpty }

    // MARK: Editing (keeps `points` sorted)

    /// Add a keyframe and return it. Re-sorts so reads stay correct.
    @discardableResult
    public mutating func addPoint(tick: Int, value: Double, curve: AutomationCurve = .linear) -> AutomationPoint {
        let p = AutomationPoint(tick: tick, value: value, curve: curve)
        points.append(p)
        resort()
        return p
    }

    public mutating func removePoint(id: UUID) {
        points.removeAll { $0.id == id }
    }

    /// Move a keyframe in time (clamped ≥0) and keep the lane sorted.
    public mutating func movePoint(id: UUID, toTick tick: Int) {
        guard let i = points.firstIndex(where: { $0.id == id }) else { return }
        points[i].tick = max(0, tick)
        resort()
    }

    public mutating func setValue(id: UUID, _ value: Double) {
        guard let i = points.firstIndex(where: { $0.id == id }) else { return }
        points[i].value = AutomationPoint.clamp(value)
    }

    public mutating func setCurve(id: UUID, _ curve: AutomationCurve) {
        guard let i = points.firstIndex(where: { $0.id == id }) else { return }
        points[i].curve = curve
    }

    public mutating func clear() { points.removeAll() }

    private mutating func resort() {
        points.sort { $0.tick < $1.tick }
    }

    // MARK: Evaluation

    /// The automated value at an absolute tick, or `nil` if the lane is empty.
    ///
    /// Before the first keyframe holds the first value; after the last holds the
    /// last value. Between two keyframes the LEFT point's `curve` decides: `.hold`
    /// keeps the left value until the right point; `.linear` interpolates.
    public func value(atTick tick: Int) -> Double? {
        guard let first = points.first, let last = points.last else { return nil }
        if tick <= first.tick { return first.value }
        if tick >= last.tick { return last.value }

        // Find the segment [p0, p1] with p0.tick <= tick < p1.tick.
        var p0 = first
        for p1 in points.dropFirst() {
            if tick < p1.tick {
                let span = p1.tick - p0.tick
                guard span > 0, p0.curve == .linear else { return p0.value }
                let frac = Double(tick - p0.tick) / Double(span)
                return p0.value + (p1.value - p0.value) * frac
            }
            p0 = p1
        }
        return last.value
    }
}
