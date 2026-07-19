//
//  SpatialScene.swift
//  Echoelmusic — Core
//
//  S1 of the Spatial Expansion (founder prompt v2.0, Layer 1 "EchoelSpace"):
//  the ONE shared scene description every renderer and every peer speaks.
//  A scene is a set of audio OBJECTS (position + extent + gain + room send)
//  plus a ROOM model and a LISTENER pose. Renderers (binaural, OSC rig
//  bridge, future EchoelRender multichannel) consume this; they never own it.
//
//  Pure value types, Foundation-only (P4 portable core): Codable, Sendable,
//  Equatable, no Observation, no platform imports. Wire format + role model
//  are specified in docs/ECHOEL_SESSION_PROTOCOL.md (P3: protocol lives in
//  the SAME commit as the types it describes).
//
//  Coordinate convention (ADM / BS.2076, same as ADMOSCSender):
//    azimuth    degrees  -180 … +180   0 = front, positive = LEFT (CCW)
//    elevation  degrees   -90 … +90    positive = up
//    distance   normalized  0 … 1      room-relative
//  Cartesian (derived):  x = right, y = front, z = up
//    x = -sin(az)·cos(el)·d   y = cos(az)·cos(el)·d   z = sin(el)·d
//

import Foundation

// MARK: - Position

/// A spherical object position (ADM convention), clamped on init so a scene
/// can never carry an out-of-range coordinate — bad input degrades, it does
/// not propagate.
public struct SpatialPosition: Codable, Sendable, Equatable, Hashable {

    /// Degrees, -180…+180. 0 = front, positive = left (counter-clockwise).
    public let azimuth: Float
    /// Degrees, -90…+90. Positive = up.
    public let elevation: Float
    /// Normalized 0…1, room-relative.
    public let distance: Float

    public init(azimuth: Float, elevation: Float, distance: Float) {
        // Non-finite input collapses to the safe origin-front default.
        self.azimuth   = azimuth.isFinite   ? min(max(azimuth, -180), 180) : 0
        self.elevation = elevation.isFinite ? min(max(elevation, -90), 90) : 0
        self.distance  = distance.isFinite  ? min(max(distance, 0), 1)     : 0
    }

    public static let front = SpatialPosition(azimuth: 0, elevation: 0, distance: 1)

    /// Derived ADM cartesian (x right, y front, z up), unit-scaled by distance.
    public var cartesian: (x: Float, y: Float, z: Float) {
        let azR = azimuth * .pi / 180
        let elR = elevation * .pi / 180
        let cosEl = cosf(elR)
        return (x: -sinf(azR) * cosEl * distance,
                y:  cosf(azR) * cosEl * distance,
                z:  sinf(elR) * distance)
    }
}

// MARK: - Object

/// One audio object in the scene. `id` is the stable protocol identity —
/// diffs and OSC object indices key on it, so it never changes for the life
/// of the object.
public struct SpatialObject: Codable, Sendable, Equatable, Identifiable {

    public let id: String
    public var position: SpatialPosition
    /// Apparent source size, 0 (point) … 1 (envelopes the listener).
    public var extent: Float
    /// Object gain 0…1 (linear).
    public var gain: Float
    /// Send level into the room/reverb model, 0…1.
    public var roomSend: Float
    /// Optional link to a motion trajectory (Layer 7); nil = static.
    public var motionRef: String?
    /// Optional link to a visual object (Layer 3 AVObjects); nil = audio-only.
    public var visualRef: String?
    /// Peer that authored/owns this object (P2 every-device-a-peer); nil = local.
    public var ownerPeer: String?

    public init(id: String,
                position: SpatialPosition = .front,
                extent: Float = 0,
                gain: Float = 1,
                roomSend: Float = 0.2,
                motionRef: String? = nil,
                visualRef: String? = nil,
                ownerPeer: String? = nil) {
        self.id = id
        self.position = position
        self.extent   = extent.isFinite   ? min(max(extent, 0), 1)   : 0
        self.gain     = gain.isFinite     ? min(max(gain, 0), 1)     : 0
        self.roomSend = roomSend.isFinite ? min(max(roomSend, 0), 1) : 0
        self.motionRef = motionRef
        self.visualRef = visualRef
        self.ownerPeer = ownerPeer
    }
}

// MARK: - Room + listener

/// Where the listener sits and faces, in ADM cartesian room coordinates.
public struct ListenerPose: Codable, Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var z: Float
    /// Heading in degrees, -180…+180, 0 = facing +y (front), positive = left.
    public var yaw: Float

    public init(x: Float = 0, y: Float = 0, z: Float = 0, yaw: Float = 0) {
        self.x = x.isFinite ? x : 0
        self.y = y.isFinite ? y : 0
        self.z = z.isFinite ? z : 0
        self.yaw = yaw.isFinite ? min(max(yaw, -180), 180) : 0
    }

    public static let center = ListenerPose()
}

/// The acoustic room the objects live in — consumed by the FDN room core
/// (S4) and by any external renderer that models distance/reverb.
public struct RoomModel: Codable, Sendable, Equatable {
    /// Meters. Also the scale reference for `SpatialPosition.distance` = 1.
    public var width: Float
    public var depth: Float
    public var height: Float
    /// RT60-style decay in seconds.
    public var decayTime: Float
    /// 0 (discrete echoes) … 1 (dense diffuse field).
    public var diffusion: Float
    public var listener: ListenerPose

    public init(width: Float = 8,
                depth: Float = 10,
                height: Float = 4,
                decayTime: Float = 1.2,
                diffusion: Float = 0.7,
                listener: ListenerPose = .center) {
        self.width  = width.isFinite  ? min(max(width, 1), 200)  : 8
        self.depth  = depth.isFinite  ? min(max(depth, 1), 200)  : 10
        self.height = height.isFinite ? min(max(height, 1), 60)  : 4
        self.decayTime = decayTime.isFinite ? min(max(decayTime, 0.1), 30) : 1.2
        self.diffusion = diffusion.isFinite ? min(max(diffusion, 0), 1)    : 0.7
        self.listener = listener
    }
}

// MARK: - Roles (P2: every device is a peer WITH a role)

/// What a peer is allowed to do in a shared session. One device can hold
/// several roles (an iPhone on stage is performer + renderer).
public enum SpatialRole: String, Codable, Sendable, CaseIterable {
    /// Owns the scene document — may add/remove objects and edit the room.
    case author
    /// Feeds live control data (bio, MIDI, motion) into its own objects.
    case performer
    /// Renders audio/visual output (binaural, rig bridge, multichannel).
    case renderer
    /// May adjust gains/sends/room live without owning the scene.
    case mixControl
    /// Receives the scene read-only (audience view, monitoring).
    case observer

    /// May this role structurally edit the scene (add/remove objects, room)?
    public var canEditScene: Bool { self == .author }
    /// May this role change levels/positions of existing objects?
    public var canAdjustMix: Bool { self == .author || self == .mixControl }
    /// May this role write live control values into objects it owns?
    public var canPerform: Bool { self == .author || self == .performer }
    /// Does this role produce audible/visible output?
    public var rendersOutput: Bool { self == .renderer }
}

// MARK: - Scene

/// The versioned scene document. `revision` increments on every structural
/// mutation so peers can order updates; `schemaVersion` is the wire-format
/// major version (ECHOEL_SESSION_PROTOCOL.md).
public struct SpatialScene: Codable, Sendable, Equatable {

    /// Wire-format major version. Bump ONLY with a protocol doc update.
    public static let schemaVersion = 1

    /// Encoded schema version of this instance (decodes from older payloads).
    public let version: Int
    /// Monotonic edit counter — peers resolve "newer" by revision, not time.
    public private(set) var revision: UInt64
    public private(set) var objects: [SpatialObject]
    public var room: RoomModel {
        didSet { if room != oldValue { revision &+= 1 } }
    }

    public init(objects: [SpatialObject] = [], room: RoomModel = RoomModel()) {
        self.version = Self.schemaVersion
        self.revision = 0
        self.objects = objects
        self.room = room
    }

    public func object(id: String) -> SpatialObject? {
        objects.first { $0.id == id }
    }

    /// Insert or replace by id. No-op (no revision bump) if unchanged.
    public mutating func upsert(_ object: SpatialObject) {
        if let idx = objects.firstIndex(where: { $0.id == object.id }) {
            guard objects[idx] != object else { return }
            objects[idx] = object
        } else {
            objects.append(object)
        }
        revision &+= 1
    }

    /// Remove by id. No-op (no revision bump) if absent.
    public mutating func removeObject(id: String) {
        let before = objects.count
        objects.removeAll { $0.id == id }
        if objects.count != before { revision &+= 1 }
    }

    // MARK: Diff (the protocol's scene.diff payload)

    /// What changed between two scenes — the minimal update a peer sends
    /// instead of the full document.
    public struct Diff: Codable, Sendable, Equatable {
        public let added: [SpatialObject]
        public let removed: [String]
        public let changed: [SpatialObject]
        /// Present only when the room differs.
        public let room: RoomModel?
        /// Revision of the scene this diff produces.
        public let toRevision: UInt64
        /// The TARGET object order (ids), present only when the order differs from
        /// `old` — array position is the ADM/IEM object index (the scene array is
        /// the routing table), so order is semantic and must converge too. Without
        /// it, a pure reorder (or a remove+re-add that moves an id to the end)
        /// produces an EMPTY structural diff, and the peers would silently disagree
        /// on which object is /adm/obj/1. Optional for wire back-compat: a diff
        /// that omits it (a legacy sender) applies add/remove/change only, the
        /// pre-order behavior. Absent key auto-decodes to nil (synthesized Codable).
        public let order: [String]?

        public var isEmpty: Bool {
            added.isEmpty && removed.isEmpty && changed.isEmpty && room == nil && order == nil
        }
    }

    /// Compute the diff that turns `old` into `self`.
    public func diff(from old: SpatialScene) -> Diff {
        let oldByID = Dictionary(uniqueKeysWithValues: old.objects.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
        var added: [SpatialObject] = []
        var changed: [SpatialObject] = []
        for obj in objects {
            if let prior = oldByID[obj.id] {
                if prior != obj { changed.append(obj) }
            } else {
                added.append(obj)
            }
        }
        let removed = old.objects.map(\.id).filter { newByID[$0] == nil }
        let newOrder = objects.map(\.id)
        return Diff(added: added,
                    removed: removed,
                    changed: changed,
                    room: room == old.room ? nil : room,
                    toRevision: revision,
                    // Carry the target order only when it actually differs, so an
                    // unchanged/content-only diff stays `isEmpty`-clean and lean.
                    order: newOrder == old.objects.map(\.id) ? nil : newOrder)
    }

    /// Apply a diff (from a peer). Returns the updated scene; `revision`
    /// adopts the diff's `toRevision` so both sides converge.
    public func applying(_ diff: Diff) -> SpatialScene {
        var next = self
        for id in diff.removed { next.objects.removeAll { $0.id == id } }
        for obj in diff.changed {
            if let idx = next.objects.firstIndex(where: { $0.id == obj.id }) {
                next.objects[idx] = obj
            }
        }
        for obj in diff.added where next.object(id: obj.id) == nil {
            next.objects.append(obj)
        }
        // Reconcile ORDER last (after add/remove/change so every target id is
        // present), so array position — the ADM/IEM object index — converges too.
        // A well-formed diff's `order` lists every target id; anything not named
        // (never happens for a diff from diff()) is kept at the end so no object
        // is ever dropped.
        if let order = diff.order {
            let byID = Dictionary(next.objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var reordered = order.compactMap { byID[$0] }
            if reordered.count != next.objects.count {
                let named = Set(order)
                reordered.append(contentsOf: next.objects.filter { !named.contains($0.id) })
            }
            next.objects = reordered
        }
        if let room = diff.room { next.room = room }
        next.revision = diff.toRevision
        return next
    }
}
