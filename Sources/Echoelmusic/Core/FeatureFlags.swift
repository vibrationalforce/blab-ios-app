//
//  FeatureFlags.swift
//  Echoelmusic — Core
//
//  S0 of the Spatial Expansion (founder prompt v2.0, Guardrail 1): every new
//  spatial/collab capability ships behind a flag that is OFF by default — an
//  absent key reads false, so a Release build is bit-identical until a flag is
//  deliberately turned on (developer settings / TestFlight staging later).
//
//  Pure value logic, Foundation-only (P4 portable core): no singleton state,
//  no Observation — call sites read at decision points, they do not observe.
//  UserDefaults is injectable so tests never touch the real store.
//

import Foundation

/// The staged-rollout switchboard for the spatial expansion. All OFF until
/// their layer's gate is device-verified (never flip a default before then).
public enum FeatureFlags {

    // MARK: - Keys (stable — they become the staged-rollout contract)

    public enum Key: String, CaseIterable, Sendable {
        case spatialEngine     = "feature.spatialEngine"      // Layer 1 — EchoelSpace scene/renderers
        case bioSpace          = "feature.bioSpace"           // Layer 2 — biosignal→space mapping
        case echoelRender      = "feature.echoelRender"       // Layer 6 — multichannel renderer capability
        case motionEngine      = "feature.motionEngine"       // Layer 7.1/7.2 — trajectories + clouds
        case showControl       = "feature.showControl"        // Layer 7.3 — cues/snapshots/GO
        case avObjects         = "feature.avObjects"          // Layer 3 — audiovisual objects
        case performerTracking = "feature.performerTracking"  // Layer 4 — stage tracking tiers
        case liveCollab        = "feature.liveCollab"         // Layer 5 — session/scene sync
        /// Sub-flag of spatialEngine (Layer 1 Renderer A): headphone head tracking.
        case headTracking      = "feature.headTracking"
        /// EchoelAI (ADR 2026-07-12): the on-device planner + tool surface.
        /// OFF = zero EchoelAI code paths run; the app renders pixel-identical.
        case echoelAI          = "feature.echoelAI"
        /// StoreKit purchase surface. OFF = launch touches NO StoreKit (no product
        /// load, no entitlement check, no Transaction.updates listener) — the app
        /// has no purchasable product today (one-time-unlock positioning), so this
        /// stays dark until a real purchase surface ships. Release bit-identical.
        case storeKit          = "feature.storeKit"
    }

    // MARK: - Reads (absent key = false = OFF; Release default)

    public static func isOn(_ key: Key, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key.rawValue)
    }

    public static var spatialEngine: Bool { isOn(.spatialEngine) }
    public static var bioSpace: Bool { isOn(.bioSpace) }
    public static var echoelRender: Bool { isOn(.echoelRender) }
    public static var motionEngine: Bool { isOn(.motionEngine) }
    public static var showControl: Bool { isOn(.showControl) }
    public static var avObjects: Bool { isOn(.avObjects) }
    public static var performerTracking: Bool { isOn(.performerTracking) }
    public static var liveCollab: Bool { isOn(.liveCollab) }
    public static var headTracking: Bool { isOn(.headTracking) }
    public static var echoelAI: Bool { isOn(.echoelAI) }
    public static var storeKit: Bool { isOn(.storeKit) }

    // MARK: - Writes (developer/staging surfaces only — no shipped UI yet)

    public static func set(_ key: Key, _ on: Bool, defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: key.rawValue)
    }
}
