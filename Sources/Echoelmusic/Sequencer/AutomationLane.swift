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
    /// BEND of the segment to the next point (Ableton-style curvature, founder
    /// 2026-07-12: "Automation kenne ich eher so das man es zeichnet wie in
    /// Ableton"): 0 = straight line, +1 = slow start / late rise (ease-in),
    /// −1 = fast start / early rise (ease-out). Applied only while `curve` is
    /// `.linear`; endpoints are always exact. Old saved arrangements decode
    /// with 0 (straight) — fully backward compatible.
    public var curvature: Double

    public init(id: UUID = UUID(), tick: Int, value: Double,
                curve: AutomationCurve = .linear, curvature: Double = 0) {
        self.id = id
        self.tick = max(0, tick)
        self.value = AutomationPoint.clamp(value)
        self.curve = curve
        self.curvature = AutomationPoint.clampCurvature(curvature)
    }

    static func clamp(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return Swift.min(1, Swift.max(0, v))
    }

    static func clampCurvature(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return Swift.min(1, Swift.max(-1, v))
    }

    // Custom decode so pre-curvature JSON (every arrangement saved before
    // 2026-07-12) loads as straight segments instead of failing.
    private enum CodingKeys: String, CodingKey { case id, tick, value, curve, curvature }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The decodeIfPresent LAW (SynthPatch/Project): every field tolerates absence
        // via a sensible default, so a renamed/removed field degrades THIS field, never
        // throws — an AutomationPoint decode error otherwise cascades up through
        // TimelineDocument and vaporizes the user's whole song. `id` folds to a fresh
        // UUID (identity is per-keyframe, not user-meaningful); the rest default neutral.
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        tick = max(0, try c.decodeIfPresent(Int.self, forKey: .tick) ?? 0)
        value = AutomationPoint.clamp(try c.decodeIfPresent(Double.self, forKey: .value) ?? 0)
        curve = try c.decodeIfPresent(AutomationCurve.self, forKey: .curve) ?? .linear
        curvature = AutomationPoint.clampCurvature(
            try c.decodeIfPresent(Double.self, forKey: .curvature) ?? 0)
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

    // Defensive decode (the decodeIfPresent LAW). AutomationLane decodes inside
    // TimelineDocument; a synthesized decoder makes id/parameter/points REQUIRED, so a
    // single renamed field threw → TimelineDocument rethrew → AppGroupStore.load nil →
    // the user's whole song was lost. Now: identity fields fall back (id→fresh UUID,
    // parameter→""), and points decode ELEMENT-tolerantly so one corrupt keyframe is
    // dropped, not the lane. Encoding stays synthesized/bit-identical (same keys).
    private enum CodingKeys: String, CodingKey { case id, parameter, points }

    /// Wrapper that decodes an AutomationPoint or yields nil on a malformed element,
    /// always consuming exactly one array slot (so the unkeyed decode can't stall).
    private struct LossyPoint: Decodable {
        let point: AutomationPoint?
        init(from decoder: Decoder) throws { point = try? AutomationPoint(from: decoder) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        parameter = try c.decodeIfPresent(String.self, forKey: .parameter) ?? ""
        // `points` absent/renamed → []; present-but-wrong-type → []; a valid array with
        // some corrupt elements → the good keyframes only (LossyPoint drops the bad).
        let decoded: [LossyPoint]? = try? c.decodeIfPresent([LossyPoint].self, forKey: .points)
        points = (decoded ?? []).compactMap { $0.point }.sorted { $0.tick < $1.tick }
    }

    public var isEmpty: Bool { points.isEmpty }

    // MARK: Editing (keeps `points` sorted)

    /// Add a keyframe and return it. Re-sorts so reads stay correct.
    @discardableResult
    public mutating func addPoint(tick: Int, value: Double,
                                  curve: AutomationCurve = .linear,
                                  curvature: Double = 0) -> AutomationPoint {
        let p = AutomationPoint(tick: tick, value: value, curve: curve, curvature: curvature)
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

    /// Bend the segment leaving this point (Ableton's curvature drag), −1…1.
    public mutating func setCurvature(id: UUID, _ curvature: Double) {
        guard let i = points.firstIndex(where: { $0.id == id }) else { return }
        points[i].curvature = AutomationPoint.clampCurvature(curvature)
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
                let shaped = Self.shapedFraction(frac, curvature: p0.curvature)
                return p0.value + (p1.value - p0.value) * shaped
            }
            p0 = p1
        }
        return last.value
    }

    /// The Ableton-style segment shape: a power bend of the linear fraction.
    /// curvature 0 → identity (straight); +1 → γ = 8 (ease-in, slow start);
    /// −1 → γ = 1/8 (ease-out, fast start). Monotonic for every curvature, and
    /// exact at both endpoints (0→0, 1→1), so bent segments can never overshoot
    /// or step — safe to feed any parameter.
    public static func shapedFraction(_ frac: Double, curvature: Double) -> Double {
        let f = Swift.min(1, Swift.max(0, frac))
        let c = AutomationPoint.clampCurvature(curvature)
        if c == 0 { return f }
        return pow(f, exp2(c * 3))
    }
}
