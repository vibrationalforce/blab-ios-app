// ImmersiveStageMath.swift
// Pure geometry for the Immersive Stage — the top-down "room map" where each track
// is a puck you drag to place its sound in space. Kept Foundation-only (plain Double
// tuples, no CoreGraphics) so it is Linux-CI-tested like AutomationCanvasMath, and the
// SwiftUI view stays a thin shell over it.
//
// Convention (matches SpatialPosition): azimuth 0 = FRONT, +90 = LEFT. On screen the
// listener sits at the disc centre facing UP, so front maps to the top of the disc and
// left maps to screen-left. Distance 0…1 is the normalized radius (centre = at the
// listener, rim = far). A 2D top-down move changes azimuth + distance only; elevation
// (height) is preserved by the caller.

import Foundation

/// Pure mapping between a `SpatialPosition` and a point on the round stage view.
public enum ImmersiveStageMath {

    /// Where a position's puck sits on the disc.
    ///
    /// - Parameters:
    ///   - azimuthDeg: 0 = front (up), +90 = left. Any value; wrapped by the trig.
    ///   - distance: 0…1 normalized radius (clamped).
    ///   - center: disc centre in view points.
    ///   - radius: disc radius in view points (the rim = distance 1).
    /// - Returns: the puck centre in view points.
    public static func point(azimuthDeg: Double,
                             distance: Double,
                             center: (x: Double, y: Double),
                             radius: Double) -> (x: Double, y: Double) {
        let d = min(max(distance, 0), 1)
        let az = azimuthDeg * .pi / 180
        // front = up (−y), left = −x. x = −sin(az)·d·R, y = −cos(az)·d·R.
        let x = center.x - sin(az) * d * radius
        let y = center.y - cos(az) * d * radius
        return (x: x, y: y)
    }

    /// Invert a dragged view point back to (azimuthDeg, distance).
    ///
    /// - Parameters:
    ///   - point: the finger position in view points.
    ///   - center: disc centre in view points.
    ///   - radius: disc radius in view points.
    /// - Returns: azimuth in degrees (−180…+180) and distance 0…1 (clamped to the rim).
    public static func azimuthDistance(forPoint point: (x: Double, y: Double),
                                       center: (x: Double, y: Double),
                                       radius: Double) -> (azimuthDeg: Double, distance: Double) {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let r = (dx * dx + dy * dy).squareRoot()
        guard radius > 0 else { return (0, 0) }
        let distance = min(r / radius, 1)
        // Dead-centre has no defined direction — keep front to avoid a jump.
        guard r > 0.0001 else { return (0, distance) }
        // Invert x = −sin·…, y = −cos·… ⇒ az = atan2(−dx, −dy).
        let az = atan2(-dx, -dy) * 180 / .pi
        return (azimuthDeg: az, distance: distance)
    }
}
