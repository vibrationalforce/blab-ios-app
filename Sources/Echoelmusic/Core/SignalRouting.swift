//
//  SignalRouting.swift
//  Echoelmusic — Core
//
//  The universal, type-aware signal router (patchbay) the founder specified:
//  "intelligentes Routing für alle Kanäle App-intern, rein und raus aus der App
//  für alle Protokolle: MIDI, MIDI 2.0, MPE, Audio, Video, Visuals etc."
//
//  This is the PURE DOMAIN MODEL only — value types + deterministic graph logic,
//  no I/O, no audio/UI wiring. It GENERALIZES what already exists rather than
//  replacing it: EngineBus topics + voices/renderers are INTERNAL ports; the
//  CoreMIDI / OSC / ADM-OSC / Art-Net / sACN / BLE / Camera bridges are EXTERNAL
//  ports; `ModulationMatrix` is the control→control projection of this graph.
//  The runtime (adapters that actually move bytes) is built in later cycles per
//  the founder-chosen protocol priority — this layer is what they all route into.
//
//  "Intelligent" = type-aware connect (only compatible kinds connect, directly
//  or through a registered converter) + auto-suggested default patches.
//
//  See docs/dev/DMMW_ARCHITECTURE.md.
//

import Foundation

// MARK: - What flows

/// The class of signal carried on an edge. Coarse on purpose — specifics
/// (which bio field, which DMX channel) live in the port id / converter, so the
/// graph stays small and the UI legible. `video`/`visual` are typed now but their
/// engines are roadmap (surfaced honestly, never pretended to flow).
public enum SignalKind: String, Codable, Sendable, CaseIterable {
    case controlBio        // bio scalar streams (HR/HRV/coherence/breath/motion)
    case controlMusical    // musical params (notes/chord/key/tempo/levels)
    case controlMacro      // generic [0..1] macro / LFO / envelope
    case note              // note on/off + per-note expression (MIDI · MPE · MIDI 2.0)
    case controlChange     // CC / parameter messages
    case audio             // an audio bus
    case light             // DMX / Art-Net / sACN channels
    case spatial           // immersive object position + gain (ADM)
    case clock             // transport / tempo clock + transport events
    case video             // video frames (roadmap)
    case visual            // visual scene / params (roadmap)

    /// Whether a real engine for this kind ships today (honesty for the UI).
    public var isLive: Bool {
        switch self {
        case .video, .visual: return false
        default: return true
        }
    }
}

// MARK: - Where it lives (protocol / location)

/// The transport a port speaks. `internalBus` = app-internal; everything else is
/// an in/out protocol adapter. Covers the relevant iPhone industry standards
/// (MIDI 1.0/2.0/MPE, RTP-MIDI, OSC, ADM-OSC, Art-Net, sACN, Audio I/O, AUv3, BLE
/// HRS, RTMP/SRT broadcast, NDI video-over-IP, Ableton Link clock). Several are
/// typed now and wired per founder priority — honesty via `status`.
public enum SignalTransport: String, Codable, Sendable, CaseIterable {
    case internalBus
    case coreMIDI       // MIDI 1.0 (CoreMIDI)
    case midi2          // MIDI 2.0 / UMP (+ MIDI-CI capability inquiry)
    case mpe            // MPE over CoreMIDI
    case rtpMIDI        // RTP-MIDI / network MIDI session
    case osc            // OSC 1.0/1.1 (+ OSCQuery discovery)
    case admOSC         // ADM-OSC immersive objects
    case artNet         // DMX over Art-Net
    case sacn           // DMX over sACN (E1.31)
    case audioIO        // device / interface / Bluetooth audio buses
    case auv3           // Audio Unit v3 host
    case abletonLink    // tempo / transport sync (free lib, Council-gated)
    case bleHRS         // BLE Heart Rate Service (0x180D) + bio
    case camera         // camera rPPG / capture
    case healthKit      // Apple Health
    case rtmp           // broadcast — RTMP
    case srt            // broadcast — SRT (low-latency)
    case ndi            // video over IP (pro-production)

    /// True for app-internal transports (no external I/O).
    public var isInternal: Bool { self == .internalBus }

    /// Implementation status — keeps the patchbay honest (no dead endpoints
    /// pretending to work). `live` = shipping today; `roadmap` = typed, not wired.
    public enum Status: String, Codable, Sendable { case live, roadmap }

    public var status: Status {
        switch self {
        case .internalBus, .coreMIDI, .mpe, .rtpMIDI, .osc, .admOSC,
             .artNet, .sacn, .audioIO, .bleHRS, .camera, .healthKit:
            return .live
        case .midi2, .auv3, .abletonLink, .rtmp, .srt, .ndi:
            return .roadmap
        }
    }
}

// MARK: - Direction

public enum PortDirection: String, Codable, Sendable {
    case source        // can be a route's origin
    case sink          // can be a route's destination
    case bidirectional // both

    public var canSource: Bool { self == .source || self == .bidirectional }
    public var canSink: Bool { self == .sink || self == .bidirectional }
}

// MARK: - Port

/// One routable endpoint. `id` is stable (e.g. "bus.bio", "midi.out.echoel",
/// "artnet.universe0") so saved patches survive relaunch and device changes.
public struct SignalPort: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var kind: SignalKind
    public var direction: PortDirection
    public var transport: SignalTransport

    public init(id: String, name: String, kind: SignalKind,
                direction: PortDirection, transport: SignalTransport) {
        self.id = id
        self.name = name
        self.kind = kind
        self.direction = direction
        self.transport = transport
    }
}

// MARK: - Converter catalog (the "intelligent" part)

/// A declared, allowed transformation between two signal kinds. The pure model
/// only records that a converter EXISTS (so the graph can validate a cross-kind
/// route and the UI can offer it); the runtime supplies the actual transform.
public struct SignalConverter: Codable, Sendable, Identifiable, Equatable {
    public var id: String          // e.g. "bio→cc", "pitch→colour", "pitch→admPos"
    public var name: String
    public var from: SignalKind
    public var to: SignalKind

    public init(id: String, name: String, from: SignalKind, to: SignalKind) {
        self.id = id; self.name = name; self.from = from; self.to = to
    }
}

/// The set of conversions this build knows how to perform. Same-kind edges are
/// always allowed (identity) and are NOT listed here.
public struct ConverterCatalog: Codable, Sendable, Equatable {
    public var converters: [SignalConverter]
    public init(converters: [SignalConverter] = []) { self.converters = converters }

    /// A converter from→to, if one is registered (nil for identity/same-kind).
    public func converter(from: SignalKind, to: SignalKind) -> SignalConverter? {
        converters.first { $0.from == from && $0.to == to }
    }

    /// Kinds that `from` can reach: itself (identity) plus every registered target.
    public func reachableKinds(from: SignalKind) -> Set<SignalKind> {
        var s: Set<SignalKind> = [from]
        for c in converters where c.from == from { s.insert(c.to) }
        return s
    }

    /// Echoel's default conversions — the music/bio → multimedia mappings that make
    /// the DMMW promise ("shape visuals/light/spatial by musical parameters") real.
    public static let `default` = ConverterCatalog(converters: [
        SignalConverter(id: "bio→cc",       name: "Bio → MIDI CC",        from: .controlBio,     to: .controlChange),
        SignalConverter(id: "bio→light",    name: "Bio → Light",          from: .controlBio,     to: .light),
        SignalConverter(id: "bio→spatial",  name: "Bio → Spatial object", from: .controlBio,     to: .spatial),
        SignalConverter(id: "bio→macro",    name: "Bio → Macro",          from: .controlBio,     to: .controlMacro),
        SignalConverter(id: "music→light",  name: "Pitch/Chord → Colour", from: .controlMusical, to: .light),
        SignalConverter(id: "music→spatial",name: "Pitch → Position",     from: .controlMusical, to: .spatial),
        SignalConverter(id: "music→cc",     name: "Music → MIDI CC",      from: .controlMusical, to: .controlChange),
        SignalConverter(id: "macro→cc",     name: "Macro → MIDI CC",      from: .controlMacro,   to: .controlChange),
        SignalConverter(id: "macro→light",  name: "Macro → Light",        from: .controlMacro,   to: .light),
        SignalConverter(id: "macro→spatial",name: "Macro → Spatial",      from: .controlMacro,   to: .spatial)
    ])
}

// MARK: - Route

/// One source-port → sink-port connection with a transform amount and an
/// optional named converter (nil = identity / same-kind pass-through).
public struct SignalRoute: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var sourcePortID: String
    public var sinkPortID: String
    public var enabled: Bool
    /// Intended transform depth / gain, [0..1] — but NO CONSUMER TODAY. It is persisted and
    /// clamped and nothing reads it, so changing it has no audible or visible effect (#171:
    /// wire it into the converters or drop it from the schema). Do not document it as if it
    /// already scales anything.
    public var amount: Float
    /// Named converter id when source/sink kinds differ; nil for same-kind edges.
    public var converterID: String?

    public init(id: UUID = UUID(), sourcePortID: String, sinkPortID: String,
                enabled: Bool = true, amount: Float = 1.0, converterID: String? = nil) {
        self.id = id
        self.sourcePortID = sourcePortID
        self.sinkPortID = sinkPortID
        self.enabled = enabled
        self.amount = Swift.min(1, Swift.max(0, amount.isNaN ? 1 : amount))
        self.converterID = converterID
    }

    private enum CodingKeys: String, CodingKey {
        case id, sourcePortID, sinkPortID, enabled, amount, converterID
    }

    /// DEFENSIVE DECODE — the half that element-tolerance cannot cover.
    ///
    /// `SignalRouter` decodes its stored routes element-tolerantly, so ONE unreadable route
    /// no longer wipes the patchbay. But that only helps when SOME elements still decode: if
    /// a future version adds one non-optional property, the synthesized decoder makes EVERY
    /// persisted route throw at once — every element becomes a hole, the compact yields `[]`,
    /// and the first edit persists that emptiness. Tolerance without a forgiving decoder just
    /// relabels the same total loss. So only the two fields that IDENTIFY a route are
    /// required; everything else falls back to the value the memberwise `init` would give a
    /// freshly-made route. A route missing its ports is not a degraded route, it is not a
    /// route — that one still throws, and the tolerant array turns it into a single hole.
    ///
    /// This is the pattern already used for `SynthPatch`, `Project` and `ArrangementSection`
    /// (law 9). `encode(to:)` stays synthesized and the CodingKeys above match the property
    /// names in declaration order, so the KEY SET is unchanged and a well-formed in-range
    /// route round-trips byte-for-byte. Two values are deliberately NOT byte-preserved, and
    /// the next `save()` re-encodes them: an out-of-range `amount` is clamped, and an
    /// unreadable/absent `id` is regenerated.
    ///
    /// `amount` — PRE-EMPTIVE, not a closed live bug. The synthesized decoder did assign it
    /// raw, bypassing the clamp in the memberwise `init`; delegating to that `init` keeps the
    /// clamp in one place. But nothing anywhere READS `route.amount` today — it is a stored
    /// promise with no consumer (task #171) — and `JSONDecoder` throws on non-conforming
    /// floats by default, so a persisted NaN was never representable in the first place. An
    /// earlier version of this comment claimed a NaN "reached the transform depth"; there is
    /// no transform depth to reach.
    ///
    /// `enabled` defaults to TRUE when absent or non-boolean. Safe only because nothing can
    /// produce a disabled route today: `routes` is `private(set)`, there is no setter, and
    /// `SignalRouter.toggle` disconnects rather than disabling. THE DAY a mute/bypass control
    /// lands in the Patchbay, revisit this — the default would silently re-arm a route the
    /// user muted, and a re-armed Art-Net/OSC edge is output the user did not ask for.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            // A missing id costs nothing to replace: it only addresses the route for
            // `disconnect`, and is never matched against anything else that was persisted.
            id: (try? c.decode(UUID.self, forKey: .id)) ?? UUID(),
            sourcePortID: try c.decode(String.self, forKey: .sourcePortID),
            sinkPortID: try c.decode(String.self, forKey: .sinkPortID),
            enabled: (try? c.decode(Bool.self, forKey: .enabled)) ?? true,
            amount: (try? c.decode(Float.self, forKey: .amount)) ?? 1.0,
            converterID: try? c.decode(String.self, forKey: .converterID)
        )
    }
}

// MARK: - Graph

/// The patchbay: a port inventory + the active routes + pure connection logic.
/// `@Observable`-friendly value type; the runtime owns one and mutates it, the UI
/// binds to it. Deterministic + side-effect free → safe to evaluate anywhere.
public struct SignalGraph: Codable, Sendable, Equatable {

    public private(set) var ports: [SignalPort]
    public private(set) var routes: [SignalRoute]
    public var catalog: ConverterCatalog

    public init(ports: [SignalPort] = [], routes: [SignalRoute] = [],
                catalog: ConverterCatalog = .default) {
        self.ports = ports
        self.routes = routes
        self.catalog = catalog
    }

    // MARK: Inventory

    public func port(_ id: String) -> SignalPort? { ports.first { $0.id == id } }

    public var sources: [SignalPort] { ports.filter { $0.direction.canSource } }
    public var sinks: [SignalPort] { ports.filter { $0.direction.canSink } }

    /// Add or replace a port (by id). Used by adapters as endpoints appear
    /// (CoreMIDI device plugged in, AUv3 instantiated, BLE strap connects).
    public mutating func upsert(_ port: SignalPort) {
        if let i = ports.firstIndex(where: { $0.id == port.id }) { ports[i] = port }
        else { ports.append(port) }
    }

    /// Remove a port and any routes touching it (endpoint disappeared).
    public mutating func removePort(_ id: String) {
        ports.removeAll { $0.id == id }
        routes.removeAll { $0.sourcePortID == id || $0.sinkPortID == id }
    }

    // MARK: Connection logic (pure, type-aware)

    /// Why a proposed connection is/least valid — drives the UI + tests.
    public enum ConnectionCheck: Equatable {
        case ok(converterID: String?)      // nil = identity (same kind)
        case unknownPort
        case wrongDirection
        case incompatibleKinds             // no converter from source.kind → sink.kind
        case duplicate
    }

    /// Validate a source→sink connection without mutating.
    public func check(sourceID: String, sinkID: String) -> ConnectionCheck {
        guard let s = port(sourceID), let d = port(sinkID) else { return .unknownPort }
        guard s.direction.canSource, d.direction.canSink else { return .wrongDirection }
        if routes.contains(where: { $0.sourcePortID == sourceID && $0.sinkPortID == sinkID }) {
            return .duplicate
        }
        if s.kind == d.kind { return .ok(converterID: nil) }
        if let c = catalog.converter(from: s.kind, to: d.kind) { return .ok(converterID: c.id) }
        return .incompatibleKinds
    }

    public func canConnect(sourceID: String, sinkID: String) -> Bool {
        if case .ok = check(sourceID: sourceID, sinkID: sinkID) { return true }
        return false
    }

    /// Connect if valid, picking the right converter automatically. Returns the new
    /// route, or nil if the connection is invalid (caller can show `check` reason).
    @discardableResult
    public mutating func connect(sourceID: String, sinkID: String, amount: Float = 1.0) -> SignalRoute? {
        guard case let .ok(converterID) = check(sourceID: sourceID, sinkID: sinkID) else { return nil }
        let route = SignalRoute(sourcePortID: sourceID, sinkPortID: sinkID,
                                amount: amount, converterID: converterID)
        routes.append(route)
        return route
    }

    public mutating func disconnect(_ routeID: UUID) {
        routes.removeAll { $0.id == routeID }
    }

    /// Replace routes with a persisted set, keeping only those whose BOTH ports still
    /// exist in the current inventory — so an endpoint that disappeared (or a port
    /// removed in a new app version) drops its saved routes instead of dangling.
    public mutating func restore(_ saved: [SignalRoute]) {
        routes = saved.filter { port($0.sourcePortID) != nil && port($0.sinkPortID) != nil }
    }

    public func routes(forSource id: String) -> [SignalRoute] {
        routes.filter { $0.sourcePortID == id }
    }
    public func routes(forSink id: String) -> [SignalRoute] {
        routes.filter { $0.sinkPortID == id }
    }

    /// True if any ENABLED route targets this sink — the runtime uses this to bring
    /// the sink's output online (start its sender) only when something feeds it.
    public func hasEnabledRoute(toSink id: String) -> Bool {
        routes.contains { $0.sinkPortID == id && $0.enabled }
    }

    /// True if any ENABLED route originates from this source — the runtime uses this
    /// to bring an INPUT online (start its receiver, e.g. MIDI-in) only when wired.
    public func hasEnabledRoute(fromSource id: String) -> Bool {
        routes.contains { $0.sourcePortID == id && $0.enabled }
    }

    /// True if a specific ENABLED route exists from `source` to `sink` — used for
    /// direct pass-throughs (e.g. MIDI-in → MIDI-out thru).
    public func hasEnabledRoute(from source: String, to sink: String) -> Bool {
        routes.contains { $0.sourcePortID == source && $0.sinkPortID == sink && $0.enabled }
    }

    // MARK: Intelligent defaults

    /// Propose sensible connections that don't yet exist: every source to every
    /// sink it is type-compatible with, EXCLUDING internal→internal echoes (those
    /// are wired in code) and dead (non-live) kinds. The UI offers these as
    /// one-tap "smart patches"; nothing is applied automatically.
    public func suggestedConnections() -> [(sourceID: String, sinkID: String, converterID: String?)] {
        var out: [(String, String, String?)] = []
        for s in sources where s.kind.isLive {
            for d in sinks where d.kind.isLive {
                guard s.id != d.id else { continue }
                // Skip purely-internal echoes; the interesting routes cross a boundary.
                if s.transport.isInternal && d.transport.isInternal { continue }
                if case let .ok(converterID) = check(sourceID: s.id, sinkID: d.id) {
                    out.append((s.id, d.id, converterID))
                }
            }
        }
        return out.map { (sourceID: $0.0, sinkID: $0.1, converterID: $0.2) }
    }
}
