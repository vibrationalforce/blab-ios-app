//
//  SignalRouter.swift
//  Echoelmusic — Core
//
//  The live, observable holder of the universal patchbay (`SignalGraph`). Owns the
//  real port INVENTORY (the app's actual in/out endpoints), persists user ROUTES,
//  and exposes connect/disconnect/suggest for the Patchbay UI to bind to. The pure
//  graph logic + converters live in `SignalRouting.swift`; this adds app lifetime,
//  persistence, and the concrete endpoint list. See docs/dev/PRODUCT_DEFINITION.md
//  (DMMW_ARCHITECTURE.md is superseded history).
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
    ///
    /// ⚠️ `amount` is STORED, NOT APPLIED — see `SignalRoute.amount` (#171, decided
    /// 2026-07-28: kept with an expiry condition, not wired and not dropped).
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
        // this replaces was all-or-nothing: ONE unreadable route threw, `load` returned early
        // leaving the graph at its empty default, and the FIRST subsequent edit called `save()` —
        // writing that empty default back over the blob. Every route the user had patched,
        // gone silently and permanently, because of one bad edge.
        //
        // SCOPE, precisely: this fixes PARTIAL corruption — some elements readable, some not.
        // It does NOT fix the case where EVERY element fails (e.g. a new required field added to
        // `SignalRoute`): they all become holes, `compactMap` yields `[]`, and the wipe happens
        // exactly as before, just with a log line. That case is the DECODER's job, which is why
        // `SignalRoute` has a defensive `init(from:)` — the two halves only work together.
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
            // ⛔ THIS PORT WAS NAMED "MIDI / MPE In" AND THE APP CANNOT RECEIVE MPE (#766).
            // #548 measured it and corrected five surfaces — CLAUDE.md's pipeline line, the
            // FAQ, `architecture.html`, the App Store text and `ContentPipeline/CLAIMS.md` —
            // all of them PROSE. The routing screen was a sixth surface and the only one a
            // player reads while patching, so it kept the claim for two months. Measured:
            // `MIDIBusPublisher` parses MPE traffic but disambiguates no zones (its own header
            // says so), and `BioReactiveSynthVoice.apply(controller:)` runs into a single
            // `break` for `.slide`, `.airCC` and `.channelPressure` — the three dimensions that
            // MAKE it MPE — and never reads `event.channel`. MPE **out** is real and switchable
            // (#713), which is why the sink below keeps its name. Guard:
            // `Tests/CISmoke/TheMPEDimensionsReachNoVoiceTests`.
            SignalPort(id: "midi.in",     name: "MIDI In", kind: .note,                 direction: .source, transport: .coreMIDI),
            // Universal BLE heart-rate strap (0x180D — Polar/Garmin/Wahoo/…).
            // DATA-FLOW PORT ONLY — it does NOT drive the strap's lifecycle. B4
            // (2026-07-12) briefly made `applyRouting` start/stop the scan from
            // this port; BLE-3 (2026-07-15) removed that again because it made
            // routing a SECOND owner that killed a pill-started strap on every
            // unrelated Patchbay edit. The strap has ONE owner: the pulse-pill
            // source dropdown (`startBioSource`). See EchoelmusicApp.applyRouting.
            // `hasEnabledRoute(fromSource:)` consequently has NO production
            // caller today — do not re-derive a start hook from its existence.
            SignalPort(id: "blehrs.in",   name: "Heart strap (BLE)", kind: .controlBio,   direction: .source, transport: .bleHRS),
            // External outputs
            SignalPort(id: "midi.out",    name: "MIDI / MPE Out", kind: .note,         direction: .sink,   transport: .coreMIDI),
            SignalPort(id: "osc.out",     name: "OSC Out",       kind: .controlChange,  direction: .sink,   transport: .osc),
            SignalPort(id: "adm.out",     name: "ADM-OSC (spatial)", kind: .spatial,    direction: .sink,   transport: .admOSC),
            SignalPort(id: "artnet.out",  name: "Art-Net (light)",   kind: .light,      direction: .sink,   transport: .artNet),
            SignalPort(id: "sacn.out",    name: "sACN (light)",      kind: .light,      direction: .sink,   transport: .sacn),
            SignalPort(id: "audio.master", name: "Audio master",     kind: .audio,      direction: .sink,   transport: .audioIO),
            // Broadcast — sink ports only; the engine is not linked (CUT 2026-07-25), routes here carry nothing today.
            SignalPort(id: "rtmp.out",    name: "Broadcast (RTMP)",  kind: .audio,      direction: .sink,   transport: .rtmp),
            SignalPort(id: "srt.out",     name: "Broadcast (SRT)",   kind: .audio,      direction: .sink,   transport: .srt)
        ]
    }
}
