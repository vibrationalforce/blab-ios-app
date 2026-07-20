// SpatialAutomationMapping.swift
// The pure bridge that turns an Immersive-Stage puck GESTURE into replayable
// automation and back — the missing connective tissue between three cores that
// already exist:
//   • `AutomationGestureRecorder` captures N synchronized normalized dimensions,
//   • `AutomationLane.value(atTick:)` samples one dimension at any song tick,
//   • `SpatialPosition` (ADM azimuth/elevation/distance) is what the stage moves.
//
// A puck move is three dimensions at once (azimuth, elevation, distance). To
// record it we normalize each to [0…1] (the recorder's/lane's native range); to
// play it back we sample the recorded lanes at the playhead tick and denormalize
// to a `SpatialPosition`. Any dimension the gesture never touched falls back to a
// caller-supplied base, so a 2D top-down drag (azimuth + distance only) replays
// with the object's existing height instead of snapping it to the floor.
//
// Pure value logic — Foundation only, no engine, no @MainActor, no audio-thread
// work — so the normalize/denormalize round-trip and the multi-lane sampling are
// unit-tested on every platform (Linux included), exactly like the recorder and
// lane it sits between. The SwiftUI stage view stays a thin shell over this.
//
// Range convention (matches `SpatialPosition` / ADM BS.2076):
//   azimuth   −180…+180 → 0…1   as (az + 180) / 360
//   elevation  −90…+90  → 0…1   as (el +  90) / 180
//   distance     0…1    → 0…1   identity
// Endpoints map exactly (−180→0, +180→1, …), so a round-trip is lossless within
// Float precision and can never push a coordinate out of `SpatialPosition`'s
// clamped range.

import Foundation

/// Maps between a `SpatialPosition` and the normalized [0…1] automation
/// dimensions an `AutomationGestureRecorder` records / `AutomationLane`s replay.
public enum SpatialAutomationMapping {

    // MARK: Dimension keys

    /// Parameter key for the azimuth automation lane.
    public static let azimuthKey = "spatial.azimuth"
    /// Parameter key for the elevation (height) automation lane.
    public static let elevationKey = "spatial.elevation"
    /// Parameter key for the distance automation lane.
    public static let distanceKey = "spatial.distance"

    /// The three dimension keys, in the order a recorder should declare them.
    public static var dimensionKeys: [String] { [azimuthKey, elevationKey, distanceKey] }

    // MARK: Encode (position → normalized snapshot)

    /// A `SpatialPosition` as a normalized [0…1] snapshot keyed by dimension —
    /// feed straight to `AutomationGestureRecorder.capture(_:atTick:)`.
    public static func normalized(_ position: SpatialPosition) -> [String: Double] {
        [azimuthKey: Double((position.azimuth + 180) / 360),
         elevationKey: Double((position.elevation + 90) / 180),
         distanceKey: Double(position.distance)]
    }

    // MARK: Decode (one normalized dimension → spatial units)

    /// Denormalize an azimuth value from [0…1] back to −180…+180°.
    public static func azimuth(fromNormalized n: Double) -> Float { Float(n) * 360 - 180 }
    /// Denormalize an elevation value from [0…1] back to −90…+90°.
    public static func elevation(fromNormalized n: Double) -> Float { Float(n) * 180 - 90 }
    /// Denormalize a distance value from [0…1] (identity, kept for symmetry).
    public static func distance(fromNormalized n: Double) -> Float { Float(n) }

    // MARK: Replay (recorded lanes → position at a tick)

    /// Reconstruct the puck's `SpatialPosition` at `tick` by sampling the recorded
    /// lanes. A dimension whose lane is absent or empty keeps `base`'s value — so a
    /// gesture that only moved azimuth + distance replays with the object's existing
    /// elevation rather than dropping it to the floor. Lanes for keys other than the
    /// three dimensions are ignored.
    public static func position(atTick tick: Int,
                                from lanes: [AutomationLane],
                                base: SpatialPosition = .front) -> SpatialPosition {
        func sample(_ key: String, _ fallback: Float, _ denorm: (Double) -> Float) -> Float {
            guard let lane = lanes.first(where: { $0.parameter == key }),
                  let value = lane.value(atTick: tick) else { return fallback }
            return denorm(value)
        }
        let az = sample(azimuthKey, base.azimuth, azimuth(fromNormalized:))
        let el = sample(elevationKey, base.elevation, elevation(fromNormalized:))
        let di = sample(distanceKey, base.distance, distance(fromNormalized:))
        return SpatialPosition(azimuth: az, elevation: el, distance: di) // clamps
    }

    // MARK: Recorder factory

    /// A gesture recorder pre-declared for the three stage dimensions, so the view
    /// layer never repeats the key list.
    public static func recorder(anchorTick: Int = 0,
                                minTickInterval: Int = 60) -> AutomationGestureRecorder {
        AutomationGestureRecorder(parameters: dimensionKeys,
                                  anchorTick: anchorTick,
                                  minTickInterval: minTickInterval)
    }
}
