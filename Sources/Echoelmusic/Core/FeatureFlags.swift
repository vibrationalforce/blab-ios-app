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
        /// Multi-Roll (keystone): each MIDI lane plays its OWN voice via a
        /// pre-attached LaneVoiceRack + TimelineRegionPlayer fan-out, each lane with
        /// its own TimelineLane.patch timbre. DEFAULT-ON since 2026-07-14 (registered
        /// true at EchoelmusicApp startup — the per-instrument vision). The OFF path
        /// stays bit-identical (no rack attached, fan-out capacity 0) and a dev/user
        /// `FeatureFlags.set(.multiRoll, false)` overrides the registration domain, so
        /// it remains the one-line rollback lever if device-verify (CPU/mem, two dense
        /// tracks sound simultaneously) ever fails. NEVER delete the OFF branches.
        case multiRoll         = "feature.multiRoll"
        /// S2-W2 ("Spur = Instrument"): heterogeneous rack voices — a sub-bass lane
        /// plays a dedicated SubBassVoice (⛔ a drums lane played a LaneDrumKitVoice
        /// until #167, founder 2026-07-27; it now allocates to poly like any other
        /// unit-less kind), bound at the rack boundary by the pure KindVoiceAllocator. DEFAULT-ON
        /// since 2026-07-17 (registered true at EchoelmusicApp startup — founder
        /// verdict: the OFF-until-device-verify gate was a deadlock, since no UI
        /// exposes the flag; risk activates only through the explicit act of
        /// assigning a sub-bass instrument to a track — ⛔ "drums/sub" stood here;
        /// no drums instrument can be assigned since #167).
        /// ⛔ "Sampler/bioVoice kinds still resolve to poly until their units ship"
        /// also stood here and is FALSE: `LaneVoiceRack.attachAll` creates both a
        /// `SamplerVoice` and a `BioReactiveSynthVoice` under this same flag, and
        /// `LaneVoiceRackTests`/`BodyVibeBioRackTests` pin the routing. The one kind
        /// that always falls back to poly today is `.drums` — and only because its
        /// voice was deleted. `FeatureFlags.set(.voiceKindRouting, false)` is the one-line
        /// rollback lever. NEVER delete the OFF branches.
        case voiceKindRouting  = "feature.voiceKindRouting"
        /// A5 BodyVibe camera modulator: front-camera facial-EXPRESSION tracking
        /// (ARKit blendShapes → smile/brow/jaw control channels) as an opt-in bio
        /// source. DEFAULT-OFF until the selection wiring + device verify land — the
        /// publisher file compiles but nothing instantiates it while this is off, so
        /// the app is bit-identical. Expression/movement as a control signal, never
        /// an inferred emotion. `FeatureFlags.set(.cameraExpression, true)` is the
        /// one-line enable lever once wired.
        case cameraExpression  = "feature.cameraExpression"
        /// Task #13 (PLAN_AUDIO_LANE_RECORDING_2026-07-21.md): real mic capture
        /// onto an armed audio-input lane via `MultiTrackRecorder`. OFF = the app
        /// wires `RecordController` with no audio recorder at all, so its new
        /// audio-capture branch never runs — Release bit-identical.
        /// `RecordPlan.targets`/`RecordSource.captureImplemented` deliberately
        /// keep excluding `.audioInput` regardless of this flag (this flag only
        /// gates the CAPTURE wiring itself — the honest Record-button gate is a
        /// separate, still-device-gated follow-up flip, S3 in the plan).
        case audioLaneRecording = "feature.audioLaneRecording"
        /// Vision Step 1 (founder 2026-07-22): the app HOME is the living
        /// instrument — WorkspaceView opens directly into the existing
        /// `FloatingVisualWindow` FULLSCREEN (MetalBioView + TouchInstrumentView),
        /// and the DAW chrome stays mounted beneath, reachable via the visual's
        /// contract button ("app open → it lives", no menu/setup). DEFAULT-ON via
        /// registration (same rationale as multiRoll/voiceKindRouting: a
        /// default-OFF flag with no UI to flip it is an un-verifiable deadlock).
        /// The OFF path is bit-identical to the old chrome-first home;
        /// `FeatureFlags.set(.instrumentHome, false)` is the one-line rollback lever.
        case instrumentHome     = "feature.instrumentHome"
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
    public static var multiRoll: Bool { isOn(.multiRoll) }
    public static var voiceKindRouting: Bool { isOn(.voiceKindRouting) }
    public static var cameraExpression: Bool { isOn(.cameraExpression) }
    public static var audioLaneRecording: Bool { isOn(.audioLaneRecording) }
    public static var instrumentHome: Bool { isOn(.instrumentHome) }

    // MARK: - Writes (developer/staging surfaces only — no shipped UI yet)

    public static func set(_ key: Key, _ on: Bool, defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: key.rawValue)
    }
}
