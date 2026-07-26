//
//  SignalRouter.swift
//  Echoelmusic — Core
//
//  The live, observable holder of the universal patchbay (`SignalGraph`). Owns the
//  real port INVENTORY (the app's actual in/out endpoints), persists user ROUTES,
//  and exposes connect/disconnect/suggest for the Patchbay UI to bind to. The pure
//  graph logic + converters live in `SignalRouting.swift`; this adds app lifetime,
//  persistence, and the concrete endpoint list. See docs/dev/DMMW_ARCHITECTURE.md.
//
//  Honesty: the inventory reflects endpoints that exist today; each port carries its
//  transport `status` (live/roadmap), and the UI shows it — no dead patch points.
//

import Foundation
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class SignalRouter {

    /// The live patchbay. The UI binds to it; mutations persist via `save()`.
    public private(set) var graph: SignalGraph

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "signalGraph.routes.v1"

    /// Called after every routing change (and on load) so the app can bring the
    /// affected outputs online/offline (start/stop senders, enable MIDI out). Set by
    /// the app; nil = no side effects (e.g. in tests).
    @ObservationIgnored public var onChange: (() -> Void)?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.graph = SignalGraph(ports: Self.defaultInventory(), catalog: .default)
        load()
    }

    // MARK: - Editing (persisted)

    /// Connect if type-compatible (auto-picks the converter). Persists on success.
    @discardableResult
    public func connect(_ sourceID: String, _ sinkID: String, amount: Float = 1.0) -> Bool {
        guard graph.connect(sourceID: sourceID, sinkID: sinkID, amount: amount) != nil else { return false }
        save()
        return true
    }

    public func disconnect(_ routeID: UUID) {
        graph.disconnect(routeID)
        save()
    }

    /// Toggle a source→sink edge (used by the matrix cells).
    public func toggle(_ sourceID: String, _ sinkID: String) {
        if let existing = graph.routes.first(where: { $0.sourcePortID == sourceID && $0.sinkPortID == sinkID }) {
            disconnect(existing.id)
        } else {
            connect(sourceID, sinkID)
        }
    }

    public func isConnected(_ sourceID: String, _ sinkID: String) -> Bool {
        graph.routes.contains { $0.sourcePortID == sourceID && $0.sinkPortID == sinkID }
    }

    /// Smart, not-yet-made connections the UI offers as one-tap patches.
    public func suggestions() -> [(sourceID: String, sinkID: String, converterID: String?)] {
        graph.suggestedConnections()
    }

    /// Apply every suggested connection at once ("Auto-patch").
    public func applyAllSuggestions() {
        for s in suggestions() { graph.connect(sourceID: s.sourceID, sinkID: s.sinkID) }
        save()
    }

    public func clearAll() {
        for r in graph.routes { graph.disconnect(r.id) }
        save()
    }

    // MARK: - Persistence (routes only; ports are code-defined inventory)

    public func save() {
        if let data = try? JSONEncoder().encode(graph.routes) {
            defaults.set(data, forKey: storageKey)
        }
        onChange?()   // bring outputs online/offline to match the new routing
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }   // nothing saved = normal
        // Element-tolerant (see `decodeLossyArray`). The strict `try? decode([SignalRoute].self)`
        // this replaces was all-or-nothing: ONE unreadable route threw, `load` returned early,
        // and the FIRST subsequent edit called `save()` — writing the surviving defaults back
        // over the file. The user's whole patchbay, including the `blehrs.in` route that is the
        // heart-strap's only start hook, would silently disappear and stay gone.
        //
        // `SignalRoute` has NO custom decoder: every field is required and synthesized, so
        // adding one non-optional field in a future version makes EVERY persisted route throw.
        // That is not a hypothetical — it is one careless property away.
        //
        // Routes are an unordered set ⇒ compact. This matches what `restore` already does with
        // routes whose ports vanished: drop the unusable edge, keep the rest of the patchbay.
        guard let loaded = decodeLossyArray(SignalRoute.self, from: data,
                                            label: "SignalRouter: \(storageKey)") else { return }
        graph.restore(loaded.compactMap { $0 })
    }

    // MARK: - The real endpoint inventory

    /// The app's actual routable endpoints today. Internal sources (the bus topics)
    /// and the external in/out bridges that ship. Visual/Video/AUv3 join when they
    /// become routable; the transport `status` keeps each honest.
    ///
    /// Roadmap-transport ports (RTMP/SRT broadcast) are FILTERED OUT of the shipped
    /// inventory (App Store audit 2026-07-16, Guideline 2.1: a reviewer opening
    /// Routing must not see named features that do not exist — even disabled+"soon"
    /// reads as placeholder UI). The entries stay in the list below so re-adding a
    /// port on ship day = flipping its transport's `status` to `.live`, nothing else.
    public nonisolated static func defaultInventory() -> [SignalPort] {
        allPortsIncludingRoadmap().filter { $0.transport.status == .live }
    }

    /// The full typed inventory including not-yet-wired roadmap ports. Internal —
    /// UI and routing must use `defaultInventory()` (live only).
    nonisolated static func allPortsIncludingRoadmap() -> [SignalPort] {
        [
            // Internal sources (the bus)
            SignalPort(id: "bus.bio",     name: "Body (bio)",   kind: .controlBio,     direction: .source, transport: .internalBus),
            SignalPort(id: "bus.musical", name: "Music",        kind: .controlMusical, direction: .source, transport: .internalBus),
            // External input
            SignalPort(id: "midi.in",     name: "MIDI / MPE In", kind: .note,          direction: .source, transport: .coreMIDI),
            // Universal BLE heart-rate strap (0x180D — Polar/Garmin/Wahoo/…).
            // The receiver has shipped since build 1543 but had NO start hook
            // (Deep Audit 2026-07-12: "GEBAUT, NIE GESTARTET") — this port is
            // its door: wiring the strap to any destination starts the scan
            // (applyRouting), unwiring stops it. B4 in the Profi-Level batch.
            SignalPort(id: "blehrs.in",   name: "Herzgurt (BLE)", kind: .controlBio,   direction: .source, transport: .bleHRS),
            // External outputs
            SignalPort(id: "midi.out",    name: "MIDI / MPE Out", kind: .note,         direction: .sink,   transport: .coreMIDI),
            SignalPort(id: "osc.out",     name: "OSC Out",       kind: .controlChange,  direction: .sink,   transport: .osc),
            SignalPort(id: "adm.out",     name: "ADM-OSC (spatial)", kind: .spatial,    direction: .sink,   transport: .admOSC),
            SignalPort(id: "artnet.out",  name: "Art-Net (light)",   kind: .light,      direction: .sink,   transport: .artNet),
            SignalPort(id: "sacn.out",    name: "sACN (light)",      kind: .light,      direction: .sink,   transport: .sacn),
            SignalPort(id: "audio.master", name: "Audio master",     kind: .audio,      direction: .sink,   transport: .audioIO),
            // Broadcast — stream the live instrument from the phone (TIER-2).
            SignalPort(id: "rtmp.out",    name: "Broadcast (RTMP)",  kind: .audio,      direction: .sink,   transport: .rtmp),
            SignalPort(id: "srt.out",     name: "Broadcast (SRT)",   kind: .audio,      direction: .sink,   transport: .srt)
        ]
    }
}
