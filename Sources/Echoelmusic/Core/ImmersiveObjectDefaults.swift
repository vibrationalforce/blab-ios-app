// ImmersiveObjectDefaults.swift
// Echoel — Core (Spatial Expansion, Layer 1 "EchoelSpace")
//
// "All instruments and effects are immersive" by DEFAULT: this pure mapper hands
// every Echoel track a sensible starting placement in the shared SpatialScene, so
// the moment a lane exists it already has an ADM object position — no track sits
// silently at the origin, nobody has to place it by hand first.
//
// The rule of thumb it encodes:
//   • spread lanes EVENLY around the ring by lane index (azimuth evenly distributed,
//     so N tracks never all stack in the same direction),
//   • then bias by instrument role — bass/sub pulled central + front-low (a mono sub
//     belongs in the middle, not panned), drums slightly wide, pads wider + set back
//     (envelope the listener), bio intimate/near.
//
// PURE value math on the control plane. Foundation-only, deterministic (no random,
// no Date, no clock) so the same lane always lands in the same place across peers and
// across app launches. Uses ONLY the real SpatialPosition / SpatialObject fields
// (azimuth / elevation / distance; extent / gain / roomSend). No AVFoundation, no
// UIKit, no SwiftUI, no audio-thread work, no allocation on any render path.

import Foundation

/// Default immersive placement for Echoel instruments.
///
/// `defaultPosition(for:laneIndex:laneCount:)` returns where a lane sits in the ring;
/// `defaultObject(for:laneID:laneIndex:laneCount:)` wraps that position in a
/// `SpatialObject` with an instrument-appropriate focus (extent) and room send.
public enum ImmersiveObjectDefaults {

    // MARK: - Per-instrument placement profile

    /// How one instrument biases the even ring spread. All values are pre-clamped
    /// to `SpatialPosition`'s legal ranges by construction, and `SpatialPosition`
    /// clamps again defensively on init.
    private struct Profile {
        /// Multiplier on the even-spread ring azimuth. < 1 pulls the lane toward
        /// front-centre (mono sub), > 1 pushes it wider (pads envelop the listener).
        let azimuthScale: Float
        /// Fixed elevation in degrees (-90…+90). Negative = below ear line (sub),
        /// positive = lifted/behind (pads).
        let elevation: Float
        /// Room-relative distance 0…1. Nearer = more direct/present, farther = set back.
        let distance: Float
        /// Apparent source size 0 (point) … 1 (wraps the listener) — the object's "focus".
        let extent: Float
        /// Send into the room/reverb model, 0…1 — more send reads as more immersive/back.
        let roomSend: Float
        /// Object gain 0…1 (linear). 1 for everything today; a hook for future balance.
        let gain: Float
    }

    /// The placement profile for each built-in instrument. Central/front for low end,
    /// progressively wider + set back toward the pads.
    private static func profile(for instrument: TrackInstrument) -> Profile {
        switch instrument {
        case .subBass:
            // Mono sub: central, front, low, direct point source — never panned wide.
            return Profile(azimuthScale: 0.20, elevation: -18, distance: 0.55,
                           extent: 0.05, roomSend: 0.08, gain: 1)
        case .bioVoice:
            // The body voice: intimate, near, close to centre, a touch of room.
            return Profile(azimuthScale: 0.45, elevation: -4, distance: 0.50,
                           extent: 0.15, roomSend: 0.25, gain: 1)
        case .drums:
            // Kit: slightly wide of centre, at the ear line, present.
            return Profile(azimuthScale: 0.85, elevation: 0, distance: 0.70,
                           extent: 0.20, roomSend: 0.20, gain: 1)
        case .breakLoop:
            // Break: same wide-ish placement as drums, a little more room.
            return Profile(azimuthScale: 0.90, elevation: 0, distance: 0.72,
                           extent: 0.25, roomSend: 0.28, gain: 1)
        case .sampler:
            // Sampler one-shots: mid-wide, present.
            return Profile(azimuthScale: 0.95, elevation: 4, distance: 0.75,
                           extent: 0.30, roomSend: 0.30, gain: 1)
        case .polySynth:
            // Pads / chords: widest, lifted and set BACK, large extent, most room.
            return Profile(azimuthScale: 1.20, elevation: 12, distance: 0.92,
                           extent: 0.55, roomSend: 0.45, gain: 1)
        }
    }

    // MARK: - Even ring spread

    /// The base azimuth for a lane before any instrument bias: lanes spread evenly
    /// across the full ring. Slice centres are used (the `+ 0.5`) so lane 0 does not
    /// sit exactly on the -180/+180 seam and the layout stays symmetric about front.
    ///
    /// - Returns: degrees in the open interval (-180, +180).
    private static func ringAzimuth(laneIndex: Int, laneCount: Int) -> Float {
        // Guard the division and pin degenerate counts to a single front-centre slot.
        guard laneCount > 1 else { return 0 }
        // Clamp the index into range so an out-of-bounds lane still lands somewhere legal.
        let idx = min(max(laneIndex, 0), laneCount - 1)
        let fraction = (Float(idx) + 0.5) / Float(laneCount)   // (0, 1)
        return fraction * 360 - 180                            // (-180, 180)
    }

    // MARK: - Public API

    /// The default immersive position for an instrument on a given lane.
    ///
    /// Azimuth is the even ring spread (`ringAzimuth`) scaled by the instrument's
    /// centrality bias; elevation and distance come straight from its profile.
    /// Deterministic in all three inputs.
    public static func defaultPosition(for instrument: TrackInstrument,
                                       laneIndex: Int,
                                       laneCount: Int) -> SpatialPosition {
        let p = profile(for: instrument)
        let azimuth = ringAzimuth(laneIndex: laneIndex, laneCount: laneCount) * p.azimuthScale
        // SpatialPosition re-clamps azimuth (-180…180) / elevation (-90…90) / distance (0…1).
        return SpatialPosition(azimuth: azimuth, elevation: p.elevation, distance: p.distance)
    }

    /// A default immersive `SpatialObject` for a lane: the position above plus an
    /// instrument-appropriate focus (extent), gain and room send. `laneID` is the
    /// stable scene identity — the object id is its UUID string, so re-deriving the
    /// object for the same lane never changes its scene key.
    public static func defaultObject(for instrument: TrackInstrument,
                                     laneID: UUID,
                                     laneIndex: Int,
                                     laneCount: Int) -> SpatialObject {
        let p = profile(for: instrument)
        let position = defaultPosition(for: instrument,
                                       laneIndex: laneIndex,
                                       laneCount: laneCount)
        return SpatialObject(id: laneID.uuidString,
                             position: position,
                             extent: p.extent,
                             gain: p.gain,
                             roomSend: p.roomSend)
    }
}
