// AutomationCanvasMath.swift
// Echoel — the pure geometry behind the drawable automation canvas (A3,
// founder: "Automation kenne ich eher so, dass man es zeichnet wie in
// Ableton"). Maps one bar of lane time to canvas space, hit-tests points and
// segments, snaps to the 16th grid, and encodes the touch law for bending a
// segment (Ableton's Alt+Drag as a plain vertical drag). Foundation-only so
// every rule is unit-tested on CI without SwiftUI.

import Foundation

public enum AutomationCanvasMath {

    /// One bar of automation in ticks (16 steps × 120).
    public static let barTicks = 16 * Note.ticksPerStep
    /// Snap grid for tap-added points: one 16th step.
    public static let snapTicks = Note.ticksPerStep

    // MARK: Coordinate mapping (x = time L→R, y = value TOP high → BOTTOM low)

    public static func x(forTick tick: Int, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return width * Double(min(max(0, tick), barTicks)) / Double(barTicks)
    }

    public static func tick(forX x: Double, width: Double) -> Int {
        guard width > 0, x.isFinite else { return 0 }
        let f = min(1, max(0, x / width))
        return Int((f * Double(barTicks)).rounded())
    }

    public static func y(forValue value: Double, height: Double) -> Double {
        guard height > 0 else { return 0 }
        return height * (1 - min(1, max(0, value)))
    }

    public static func value(forY y: Double, height: Double) -> Double {
        guard height > 0, y.isFinite else { return 0 }
        return min(1, max(0, 1 - y / height))
    }

    /// Snap a tick to the nearest 16th step (clamped into the bar).
    public static func snappedTick(_ tick: Int) -> Int {
        let s = ((tick + snapTicks / 2) / snapTicks) * snapTicks
        return min(max(0, s), barTicks)
    }

    // MARK: Hit-testing

    /// The point nearest to a canvas location, with its screen distance —
    /// the caller decides the touch radius. nil for an empty lane.
    public static func nearestPoint(toX x: Double, y: Double,
                                    points: [AutomationPoint],
                                    width: Double, height: Double)
        -> (id: UUID, distance: Double)? {
        var best: (UUID, Double)?
        for p in points {
            let dx = Self.x(forTick: p.tick, width: width) - x
            let dy = Self.y(forValue: p.value, height: height) - y
            let d = (dx * dx + dy * dy).squareRoot()
            if best == nil || d < best!.1 { best = (p.id, d) }
        }
        return best.map { (id: $0.0, distance: $0.1) }
    }

    /// The LEFT point of the segment under `x`, when `x` lies strictly between
    /// two sorted points — the point whose `curvature` bends that segment.
    /// nil before the first, after the last, or with fewer than 2 points.
    public static func segmentLeftPoint(atX x: Double,
                                        points: [AutomationPoint],
                                        width: Double) -> AutomationPoint? {
        guard points.count >= 2 else { return nil }
        let tick = Double(barTicks) * min(1, max(0, width > 0 ? x / width : 0))
        let sorted = points.sorted { $0.tick < $1.tick }
        for (left, right) in zip(sorted, sorted.dropFirst()) {
            if Double(left.tick) < tick, tick < Double(right.tick) { return left }
        }
        return nil
    }

    // MARK: The bend law (vertical drag on a segment → curvature)

    /// Dragging UP must bulge the segment UP, whichever way it runs. For a
    /// RISING segment the mid-point moves up when curvature goes NEGATIVE
    /// (ease-out: shapedFraction(0.5, −1) ≈ 0.92 pulls the middle toward the
    /// higher right value); for a FALLING segment the same visual bulge needs
    /// POSITIVE curvature. `dragUpPoints` is finger travel upward in screen
    /// points; `sensitivity` is the travel for a full ±1 sweep.
    public static func bentCurvature(start: Double, dragUpPoints: Double,
                                     risingSegment: Bool,
                                     sensitivity: Double = 120) -> Double {
        guard dragUpPoints.isFinite, sensitivity > 0 else { return start }
        let bulge = min(1, max(-1, dragUpPoints / sensitivity))
        let c = start + (risingSegment ? -bulge : bulge)
        return min(1, max(-1, c))
    }

    /// A finished drag below this travel counts as a TAP (adds a point).
    public static let tapSlopPoints = 6.0
}
