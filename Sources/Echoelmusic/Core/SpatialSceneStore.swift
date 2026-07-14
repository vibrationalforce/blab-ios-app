// SpatialSceneStore.swift
// The live immersive scene: one SpatialObject per track, placed by ImmersiveObjectDefaults
// so "every instrument is immersive" by default. This is the control-plane model the Touch
// automation surface moves, the VBAPPanner / BinauralPanner render, and ADMOSCSender streams
// out (send(scene:)). Rebuilding from the timeline's lanes keeps the scene in step with the
// tracks; user/automation moves are preserved across a rebuild (only new/removed lanes change).
//
// @MainActor @Observable control plane — no audio-thread work. Pure mapping (lanes → objects)
// is delegated to ImmersiveObjectDefaults, so this stays a thin, testable store.

import Foundation
import Observation

@MainActor
@Observable
public final class SpatialSceneStore {

    /// The live scene — every playable track as a positioned immersive object.
    public private(set) var scene = SpatialScene()

    public init() {}

    /// The lanes that become immersive objects: real (non-bio) tracks. Bio lanes drive
    /// modulation, not placement, so they are never objects.
    private static func objectLanes(_ lanes: [TimelineLane]) -> [TimelineLane] {
        lanes.filter { !$0.isBio }
    }

    /// Rebuild the scene from the timeline's lanes. Each lane becomes one object placed by
    /// ImmersiveObjectDefaults (evenly around the ring, instrument-appropriate). A lane that
    /// already has an object KEEPS its current position (user/automation moves survive);
    /// only newly-added lanes get a default placement, and removed lanes drop out.
    public func rebuild(from lanes: [TimelineLane]) {
        let objectLanes = Self.objectLanes(lanes)
        let count = objectLanes.count
        var next = SpatialScene()
        for (index, lane) in objectLanes.enumerated() {
            let id = lane.id.uuidString
            if let existing = scene.object(id: id) {
                next.upsert(existing)            // preserve a moved object as-is
            } else {
                let instrument = lane.builtinInstrument ?? .polySynth
                next.upsert(ImmersiveObjectDefaults.defaultObject(
                    for: instrument, laneID: lane.id, laneIndex: index, laneCount: count))
            }
        }
        // Only replace when something actually changed (avoids needless revision churn).
        if next.objects != scene.objects { scene = next }
    }

    /// Move one track's object (the Touch surface / recorded automation drives this).
    public func setPosition(laneID: UUID, _ position: SpatialPosition) {
        guard var object = scene.object(id: laneID.uuidString) else { return }
        object.position = position
        scene.upsert(object)
    }

    /// Set one track's apparent size / focus (0 = point source … 1 = enveloping).
    public func setExtent(laneID: UUID, _ extent: Float) {
        guard var object = scene.object(id: laneID.uuidString) else { return }
        object.extent = extent
        scene.upsert(object)
    }

    /// The object for a lane, if the scene has one.
    public func object(forLane laneID: UUID) -> SpatialObject? {
        scene.object(id: laneID.uuidString)
    }
}
