//
//  AUv3Host.swift
//  Echoelmusic — Audio
//
//  First slice of the AUv3 HOSTING pillar (the DAW piece FL Studio Mobile lacks and
//  Cubasis/AUM do but cluttered): DISCOVERY. Lists the Audio Units installed on the
//  device via AVAudioUnitComponentManager, split into instruments and effects, so a
//  later cycle can instantiate one into a channel's node graph and embed its UI in an
//  Echoel-framed panel. Read-only + side-effect free here — no audio graph changes,
//  no real-time risk. See docs/dev/DMMW_ARCHITECTURE.md (AUv3 host arc).
//

import Foundation
#if canImport(Observation)
import Observation
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(AudioToolbox)
import AudioToolbox
#endif

/// A discovered Audio Unit (value type — safe to list, persist, test).
/// Codable (AU-2): the host records WHICH plugins occupy the global slots so
/// the loaded chains survive a relaunch like lane assignments already do.
public struct HostedAUInfo: Identifiable, Sendable, Equatable, Codable {
    public var id: String          // stable: manufacturer + name + subtype
    public var name: String
    public var manufacturer: String
    public var isInstrument: Bool  // instrument (generator/music device) vs effect
    /// The four OSType codes that identify this component, so it can be
    /// re-instantiated later (instantiation needs an AudioComponentDescription).
    public var componentType: UInt32
    public var componentSubType: UInt32
    public var componentManufacturer: UInt32

    public init(id: String, name: String, manufacturer: String, isInstrument: Bool,
                componentType: UInt32 = 0, componentSubType: UInt32 = 0,
                componentManufacturer: UInt32 = 0) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.isInstrument = isInstrument
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturer = componentManufacturer
    }
}

public extension AUPluginRef {
    /// Build a persistable track assignment (U3) from a discovered/loaded hosted
    /// AU. Lossless: carries the four component codes + names + kind, so the
    /// timeline model can re-instantiate the plugin and its `id` lines up with the
    /// plugin's registered parameter keyPaths.
    init(_ info: HostedAUInfo) {
        self.init(name: info.name, manufacturerName: info.manufacturer,
                  componentType: info.componentType,
                  componentSubType: info.componentSubType,
                  componentManufacturer: info.componentManufacturer,
                  isInstrument: info.isInstrument)
    }
}

@MainActor
@Observable
public final class AUv3Host {

    public private(set) var instruments: [HostedAUInfo] = []
    public private(set) var effects: [HostedAUInfo] = []
    public private(set) var didScan = false
    /// Re-scan trigger for late third-party AUv3 registrations (see scan()).
    /// The host lives for the app's lifetime, so the observer is never removed.
    @ObservationIgnored private var registrationObserver: NSObjectProtocol?
    /// Retry ladder for a cold / late-registering third-party AUv3 registry (see scan()).
    @ObservationIgnored private var scanAttempt = 0
    @ObservationIgnored private var scanGeneration = 0
    private static let maxScanRetries = 4

    // Manufacturer identity by STABLE FourCC OSType — NOT manufacturerName, which is
    // a display string derived from the AudioComponents `name` prefix and drifts
    // (plist vs project.yml). 'appl' = Apple's built-ins, 'Echo' = Echoel's OWN
    // bundled AUv3. Both are excluded when asking "are any real third-party units
    // present?" so our own Generator doesn't masquerade as a third-party plugin.
    nonisolated static func fourCC(_ s: String) -> UInt32 {
        s.unicodeScalars.reduce(0) { ($0 << 8) | (UInt32($1.value) & 0xFF) }
    }
    private static let appleManufacturer = AUv3Host.fourCC("appl")
    private static let ownManufacturer = AUv3Host.fourCC("Echo")

    /// True when a scan completed but returned NO real third-party units — only
    /// Apple's built-ins and/or Echoel's own bundled AUv3. Drives the browser's
    /// "open your plugin apps once" guidance (the founder has many installed that
    /// haven't surfaced to this host).
    public var hasNoThirdPartyUnits: Bool {
        didScan && total > 0 && (instruments + effects).allSatisfy {
            $0.componentManufacturer == Self.appleManufacturer || $0.componentManufacturer == Self.ownManufacturer
        }
    }

    // MARK: - Live hosting (instrument → audio graph)

    /// The plugin currently loaded into the audio graph (nil = none).
    public private(set) var loaded: HostedAUInfo?
    /// A load is in flight (instantiation is async).
    public private(set) var isLoading = false
    /// Last load failure, surfaced to the browser.
    public private(set) var loadError: String?

    /// When true AND a plugin is loaded, the hosted instrument REPLACES Echoel's
    /// built-in voice for the composition (no doubling) — the song drives only the
    /// plugin. When false the two layer. Persisted across launches. No effect when
    /// nothing is loaded.
    public var replaceBuiltInVoice: Bool {
        didSet { UserDefaults.standard.set(replaceBuiltInVoice, forKey: Self.replaceKey) }
    }
    private static let replaceKey = "auHost.replaceBuiltInVoice"

    /// True only when a loaded plugin should silence the built-in voice.
    public var suppressesBuiltInVoice: Bool { loaded != nil && replaceBuiltInVoice }

    /// The effect chain inserted on the hosted instrument's channel, in order:
    /// instrument → fx[0] → fx[1] → … → master (Ableton-device-chain style).
    /// Empty = the instrument runs dry.
    public private(set) var loadedEffects: [HostedAUInfo] = []

    /// The MASTER-bus effect chain — processes the ENTIRE Echoel mix (every built-in
    /// voice, drums, and the hosted instrument), inserted between the main mixer and
    /// the hardware output: mix → mfx[0] → … → output. Empty = the mix runs dry
    /// (default; the output wiring is never touched until the first master effect).
    public private(set) var loadedMasterEffects: [HostedAUInfo] = []

    #if canImport(AVFoundation)
    /// The instantiated instrument (held so we can re-wire + send it MIDI). Not observed.
    @ObservationIgnored private var instrumentUnit: AVAudioUnit?
    /// The instantiated insert-effect chain (parallel to `loadedEffects`).
    @ObservationIgnored private var effectUnits: [AVAudioUnit] = []
    /// The instantiated master-bus effect chain (parallel to `loadedMasterEffects`).
    @ObservationIgnored private var masterEffectUnits: [AVAudioUnit] = []
    /// The engine we attach into. Set once at wire-up.
    @ObservationIgnored private weak var engine: AudioEngine?
    #endif

    public init() {
        self.replaceBuiltInVoice = UserDefaults.standard.bool(forKey: Self.replaceKey)
    }

    public var total: Int { instruments.count + effects.count }

    // MARK: - Parameter bridge (U2c) — hosted-AU params → registry + router

    /// The shared parameter registry + router (Core types, no AVFoundation), set
    /// at app wiring so a loaded plugin's parameters become automatable in the
    /// track exactly like Echoel's own. weak: the app owns their lifetime.
    @ObservationIgnored private weak var parameterRegistry: EchoelParameterRegistry?
    @ObservationIgnored private weak var parameterRouter: ParameterApplyRouter?
    /// keyPaths bridged per loaded plugin (info.id → keyPaths), so unload can unbind.
    @ObservationIgnored private var bridgedKeyPaths: [String: [String]] = [:]

    /// Connect the shared parameter registry + router (U2c). Call once at app
    /// wiring. Until set, plugin loads simply don't register parameters (no-op).
    public func useParameters(registry: EchoelParameterRegistry, router: ParameterApplyRouter) {
        self.parameterRegistry = registry
        self.parameterRouter = router
    }

    /// Clear a stale load error so a past failure doesn't linger after the user
    /// has moved on (the browser calls this on reopen). QA #5. Safe anytime — no
    /// AVFoundation needed, just resets the display flag.
    public func clearLoadError() { loadError = nil }

    #if canImport(AVFoundation)
    /// Wire the host to the live audio engine (called once at app start).
    public func use(engine: AudioEngine) { self.engine = engine }

    /// Load a discovered AU into the hosted channel — an INSTRUMENT (the sound
    /// source) or an EFFECT (inserted on the instrument's channel: instrument →
    /// effect → master). Async (AU instantiation is asynchronous). Replaces the
    /// existing unit of the same kind and re-wires the chain.
    public func load(_ info: HostedAUInfo) async {
        guard let engine else { loadError = "Audio engine unavailable."; return }
        if info.isInstrument, loaded == info, instrumentUnit != nil { return }
        // Re-entrancy guard: a load suspends at `await instantiate`, so a second
        // fast tap must not interleave (last-writer-wins on `loaded`, a re-wire
        // against a mid-flight unit, an early spinner clear). @MainActor serializes
        // this synchronous prologue, so the flag reliably rejects the second call.
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        let desc = AudioComponentDescription(
            componentType: info.componentType,
            componentSubType: info.componentSubType,
            componentManufacturer: info.componentManufacturer,
            componentFlags: 0, componentFlagsMask: 0)
        do {
            let unit = try await AVAudioUnit.instantiate(with: desc, options: [])
            // AU-1 pre-flight (the lane path's H9a gate, now on the global path
            // too): connect() RAISES kAudioUnitErr_FormatNotSupported as an
            // uncatchable ObjC exception, and channel-restricted third-party
            // units are common — a refusing unit must never reach the graph.
            let accepted = info.isInstrument
                ? engine.instrumentAcceptsChainFormat(unit)
                : !engine.effectsAcceptingChainFormat([unit]).isEmpty
            guard accepted else {
                loadError = "\(info.name) needs a channel layout Echoel doesn't provide."
                log.audio("AUv3 \(info.name) rejects the chain format — not connected", level: .error)
                isLoading = false
                return
            }
            // Recall this plugin's saved settings (knob positions etc.) so a loaded
            // plugin comes back exactly as you left it across sessions.
            restoreState(unit, id: info.id)
            // H9b: tempo/transport context for tempo-synced delays & LFOs.
            AUHostContext.install(on: unit.auAudioUnit)
            engine.withGraphPaused {                        // one pause cycle: attach + re-wire
                engine.attachAU(unit)
                if info.isInstrument {
                    if let old = instrumentUnit, let oldInfo = loaded {
                        saveState(old, id: oldInfo.id)
                        unbridgeParameters(id: oldInfo.id)   // replaced instrument: unbind its params (U2c review)
                    }
                    if let old = instrumentUnit { engine.detachAU(old) }
                    instrumentUnit = unit
                } else {
                    // Effects APPEND to the chain (instrument → fx0 → fx1 → … → master).
                    effectUnits.append(unit)
                }
                connectChainNow()
            }
            if info.isInstrument { loaded = info } else { loadedEffects.append(info) }
            persistChains()   // AU-2: the chain survives a force-kill too
            bridgeParameters(of: unit, info: info)   // params → registry + router (U2c)
            log.audio("AUv3 \(info.isInstrument ? "instrument" : "effect") loaded: \(info.name)")
        } catch {
            loadError = "Could not load \(info.name): \(error.localizedDescription)"
            log.audio("AUv3 load failed: \(error)", level: .error)
        }
        isLoading = false
    }

    /// Remove the hosted instrument (and re-wire so the effect chain is left unfed).
    public func unload() {
        if let unit = instrumentUnit, let info = loaded { saveState(unit, id: info.id) }
        if let info = loaded { unbridgeParameters(id: info.id) }   // unbind params (U2c)
        let unit = instrumentUnit
        instrumentUnit = nil
        loaded = nil
        persistChains()   // AU-2
        engine?.withGraphPaused {
            if let unit { engine?.detachAU(unit) }
            connectChainNow()
        }
    }

    /// Remove one insert effect from the chain by index; the chain re-links around it.
    public func unloadEffect(at index: Int) {
        guard effectUnits.indices.contains(index) else { return }
        let unit = effectUnits[index]
        if loadedEffects.indices.contains(index) {
            saveState(unit, id: loadedEffects[index].id)
            unbridgeParameters(id: loadedEffects[index].id)   // unbind params (U2c)
        }
        effectUnits.remove(at: index)
        if loadedEffects.indices.contains(index) { loadedEffects.remove(at: index) }
        persistChains()   // AU-2
        engine?.withGraphPaused {
            engine?.detachAU(unit)
            connectChainNow()
        }
    }

    /// Load an EFFECT onto the master bus (processes the whole mix). Async; appends to
    /// the master chain and re-wires mix → mfx… → output. Distinct from `load`, which
    /// puts effects on the instrument's own channel.
    public func loadMasterEffect(_ info: HostedAUInfo) async {
        guard let engine else { loadError = "Audio engine unavailable."; return }
        guard !info.isInstrument else { return }   // master bus takes effects only
        guard !isLoading else { return }           // re-entrancy guard (see load())
        isLoading = true
        loadError = nil
        let desc = AudioComponentDescription(
            componentType: info.componentType,
            componentSubType: info.componentSubType,
            componentManufacturer: info.componentManufacturer,
            componentFlags: 0, componentFlagsMask: 0)
        do {
            let unit = try await AVAudioUnit.instantiate(with: desc, options: [])
            // AU-1 pre-flight against the MASTER format (rewireMasterFX connects
            // with the main mixer's output format, not auChainFormat) — a
            // refusing unit would raise inside withGraphPaused = crash mid-mix.
            guard !engine.effectsAcceptingMasterFormat([unit]).isEmpty else {
                loadError = "\(info.name) needs a channel layout Echoel doesn't provide."
                log.audio("AUv3 \(info.name) rejects the master format — not connected", level: .error)
                isLoading = false
                return
            }
            restoreState(unit, id: info.id)
            // H9b: tempo/transport context for tempo-synced delays & LFOs.
            AUHostContext.install(on: unit.auAudioUnit)
            engine.withGraphPaused {
                engine.attachAU(unit)
                masterEffectUnits.append(unit)
                engine.rewireMasterFX(masterEffectUnits)
            }
            loadedMasterEffects.append(info)
            persistChains()   // AU-2
            bridgeParameters(of: unit, info: info)   // params → registry + router (U2c)
            log.audio("AUv3 master-bus effect loaded: \(info.name)")
        } catch {
            loadError = "Could not load \(info.name): \(error.localizedDescription)"
            log.audio("AUv3 master effect load failed: \(error)", level: .error)
        }
        isLoading = false
    }

    /// Remove one master-bus effect by index; the master chain re-links (empty →
    /// the direct mix → output connection is restored).
    public func unloadMasterEffect(at index: Int) {
        guard masterEffectUnits.indices.contains(index) else { return }
        let unit = masterEffectUnits[index]
        if loadedMasterEffects.indices.contains(index) {
            saveState(unit, id: loadedMasterEffects[index].id)
            unbridgeParameters(id: loadedMasterEffects[index].id)   // unbind params (U2c)
        }
        masterEffectUnits.remove(at: index)
        if loadedMasterEffects.indices.contains(index) { loadedMasterEffects.remove(at: index) }
        persistChains()   // AU-2
        engine?.withGraphPaused {
            engine?.detachAU(unit)
            engine?.rewireMasterFX(masterEffectUnits)
        }
    }

    /// The AUAudioUnit of the master-bus effect at `index` (for its own UI). nil if none.
    public func masterEffectAudioUnit(at index: Int) -> AUAudioUnit? {
        masterEffectUnits.indices.contains(index) ? masterEffectUnits[index].auAudioUnit : nil
    }

    /// Persist the live settings of everything currently loaded (instrument + chains).
    /// Call when the app backgrounds so in-session tweaks survive a relaunch.
    public func persistState() {
        if let u = instrumentUnit, let info = loaded { saveState(u, id: info.id) }
        for (i, u) in effectUnits.enumerated() where loadedEffects.indices.contains(i) {
            saveState(u, id: loadedEffects[i].id)
        }
        for (i, u) in masterEffectUnits.enumerated() where loadedMasterEffects.indices.contains(i) {
            saveState(u, id: loadedMasterEffects[i].id)
        }
        persistChains()   // AU-2: the slot occupancy backgrounds with the settings
    }

    // MARK: - Chain persistence (AU-2: the loaded chains survive a relaunch)

    private static let chainInstrumentKey = "auHost.chain.instrument"
    private static let chainEffectsKey = "auHost.chain.effects"
    private static let chainMasterKey = "auHost.chain.masterEffects"
    @ObservationIgnored private var hasRestoredChains = false

    /// Record WHICH plugins occupy the three global slots (instrument · channel
    /// FX · master FX). Pre-AU-2 only per-plugin fullState settings persisted —
    /// after a relaunch the roll lane still showed "Instrument: X" (the lane
    /// assignment restores) but played the built-in voice, and the master chain
    /// was silently empty. Called on every chain mutation, so a force-kill
    /// loses nothing.
    private func persistChains() {
        // Review HIGH (b8258e7): NEVER rewrite the record from a mid-restore
        // load — memory holds only the entries restored SO FAR, so a write here
        // would forget everything still pending or transiently failed (cold AU
        // registry). The record stays byte-identical through restore; the next
        // USER chain mutation prunes stale entries naturally.
        guard !isRestoringChains else { return }
        let d = UserDefaults.standard
        if let loaded, let data = try? JSONEncoder().encode(loaded) {
            d.set(data, forKey: Self.chainInstrumentKey)
        } else {
            d.removeObject(forKey: Self.chainInstrumentKey)
        }
        d.set((try? JSONEncoder().encode(loadedEffects)) ?? Data(), forKey: Self.chainEffectsKey)
        d.set((try? JSONEncoder().encode(loadedMasterEffects)) ?? Data(), forKey: Self.chainMasterKey)
    }

    /// True while `restoreChains()` re-drives the persisted chains. The browser
    /// disables its rows on it (a tap in the gap between two restore loads would
    /// otherwise hit `load()`'s re-entrancy guard and be dropped silently).
    public private(set) var isRestoringChains = false
    /// AU-2 review MEDIUM: a restore FAILURE must stay visible — the browser
    /// clears `loadError` on every appear (stale-error hygiene), which would
    /// erase the one clue why a plugin vanished. This notice is NOT cleared by
    /// `clearLoadError()`; the browser shows it until explicitly dismissed.
    public private(set) var restoreNotice: String?
    public func clearRestoreNotice() { restoreNotice = nil }

    /// AU-2: re-load the chains the user had at last run — call ONCE at startup,
    /// after `use(engine:)` + `useParameters`. Each entry re-drives the normal
    /// async load paths (AU-1 format pre-flight, fullState recall, parameter
    /// bridge), so an uninstalled or format-refusing plugin degrades exactly
    /// like a user tap: loadError + built-in voice, never a crash. Nothing here
    /// makes SOUND by itself — a restored instrument sounds only when notes
    /// reach it (launch silence holds).
    ///
    /// REVIEW LAWS (b8258e7 CRITICAL/HIGH): (1) decode ALL THREE payloads into
    /// locals BEFORE the first await — every successful load() rewrites all
    /// three keys from in-memory state, so a lazy read would find the FX/master
    /// records already overwritten with []. (2) NO final persist: the AU
    /// registry is often cold at process start (see scan()'s retry ladder), so
    /// a transiently failing plugin must degrade THIS launch and retry the
    /// next — never be forgotten forever. Stale entries prune naturally at the
    /// next successful chain mutation.
    public func restoreChains() async {
        guard !hasRestoredChains else { return }
        hasRestoredChains = true
        let d = UserDefaults.standard
        let decoder = JSONDecoder()
        let instrument = d.data(forKey: Self.chainInstrumentKey)
            .flatMap { try? decoder.decode(HostedAUInfo.self, from: $0) }
        let effects = d.data(forKey: Self.chainEffectsKey)
            .flatMap { try? decoder.decode([HostedAUInfo].self, from: $0) } ?? []
        let masters = d.data(forKey: Self.chainMasterKey)
            .flatMap { try? decoder.decode([HostedAUInfo].self, from: $0) } ?? []
        guard instrument != nil || !effects.isEmpty || !masters.isEmpty else { return }
        isRestoringChains = true
        // Structural invariant (review hardening): if a future edit adds an early
        // return or a throwing call below, a stuck-true flag would suppress
        // persistChains() for the REST OF THE PROCESS — every later user chain
        // mutation silently unpersisted. defer makes the clear unconditional.
        defer { isRestoringChains = false }
        var failed: [String] = []
        if let instrument {
            await load(instrument)
            if loaded != instrument { failed.append(instrument.name) }
        }
        for info in effects {
            await load(info)
            if !loadedEffects.contains(info) { failed.append(info.name) }
        }
        for info in masters {
            await loadMasterEffect(info)
            if !loadedMasterEffects.contains(info) { failed.append(info.name) }
        }
        if !failed.isEmpty {
            restoreNotice = "Not restored: \(failed.joined(separator: ", ")) — the plugin may still be waking up; reload it from this list."
            log.audio("AUv3 chain restore incomplete: \(failed.joined(separator: ", "))", level: .error)
        }
    }

    // MARK: - Plugin state (fullState) persistence

    private func stateKey(_ id: String) -> String { "auHost.fullState." + id }

    /// Snapshot a plugin's `fullState` (its complete settings) into UserDefaults,
    /// guarded so a non-plist-encodable state can never crash the store.
    private func saveState(_ unit: AVAudioUnit, id: String) {
        guard let state = unit.auAudioUnit.fullState,
              PropertyListSerialization.propertyList(state, isValidFor: .binary) else { return }
        UserDefaults.standard.set(state, forKey: stateKey(id))
    }

    /// Recall a plugin's saved `fullState`, if any, onto a freshly-instantiated unit.
    private func restoreState(_ unit: AVAudioUnit, id: String) {
        guard let dict = UserDefaults.standard.dictionary(forKey: stateKey(id)) else { return }
        unit.auAudioUnit.fullState = dict
    }

    /// The connect logic — MUST be called inside `withGraphPaused`. (Re)builds the
    /// hosted channel: instrument → (effect →) master. Units are already attached;
    /// drop old output connections, then rebuild.
    private func connectChainNow() {
        guard let engine else { return }
        // Drop every node's current output, then relink in order.
        if let i = instrumentUnit { engine.disconnectAUOutput(i) }
        for e in effectUnits { engine.disconnectAUOutput(e) }
        // The chain only sounds with an instrument feeding it; effects without an
        // instrument are left unconnected (honest — master-FX is a separate slot).
        guard var prev = instrumentUnit else { return }
        for e in effectUnits {
            engine.connectAU(prev, to: e)
            prev = e
        }
        engine.connectAUToMaster(prev)   // last node in the chain → master
    }

    /// Preview: play a note on the hosted instrument (user-driven keyboard).
    /// Sends a MIDI note-on through the AU's host-MIDI block. No-op if nothing
    /// is loaded — preserves launch silence (nothing sounds until a user taps).
    public func noteOn(_ pitch: UInt8, velocity: UInt8 = 100, channel: UInt8 = 0) {
        sendMIDI(status: 0x90 | (channel & 0x0F), data1: pitch, data2: velocity)
    }

    /// The hosted instrument's AUAudioUnit (for its own view controller). nil if none.
    public func instrumentAudioUnit() -> AUAudioUnit? { instrumentUnit?.auAudioUnit }

    // MARK: - Parameter bridge extraction (U2c)

    /// Register + bind a just-loaded plugin's parameters so they are automatable
    /// (U2c). Reads the AU's parameterTree, maps each AUParameter to the registry
    /// descriptor shape, and binds a live setter that writes the parameter's own
    /// value. No-op until `useParameters` is wired or if the plugin has no tree.
    /// Control-plane only — the setter runs at automation-step rate, never render.
    private func bridgeParameters(of unit: AVAudioUnit, info: HostedAUInfo) {
        guard let registry = parameterRegistry, let router = parameterRouter,
              let tree = unit.auAudioUnit.parameterTree else { return }
        let params = tree.allParameters
        let metas = params.map { p in
            AUParamMeta(address: p.address, displayName: p.displayName,
                        minValue: p.minValue, maxValue: p.maxValue,
                        defaultValue: p.value, unit: p.unitName ?? "",
                        valueStrings: p.valueStrings)
        }
        var byAddress: [AUParameterAddress: AUParameter] = [:]
        for p in params { byAddress[p.address] = p }
        let keyPaths = AUParameterBridge.install(
            metas: metas, manufacturer: info.componentManufacturer,
            subType: info.componentSubType, into: registry, router: router) { addr in
            let param = byAddress[addr]
            return { v in param?.value = AUValue(v) }
        }
        bridgedKeyPaths[info.id] = keyPaths
    }

    /// Unbind a plugin's parameters on unload (U2c). Descriptors linger in the
    /// registry but, unbound, drop out of the automatable set (placebo law).
    private func unbridgeParameters(id: String) {
        guard let router = parameterRouter, let kps = bridgedKeyPaths[id] else { return }
        AUParameterBridge.uninstall(keyPaths: kps, router: router)
        bridgedKeyPaths[id] = nil
    }

    /// The AUAudioUnit of the insert effect at `index` in the chain (for its own UI).
    public func effectAudioUnit(at index: Int) -> AUAudioUnit? {
        effectUnits.indices.contains(index) ? effectUnits[index].auAudioUnit : nil
    }

    public func noteOff(_ pitch: UInt8, channel: UInt8 = 0) {
        sendMIDI(status: 0x80 | (channel & 0x0F), data1: pitch, data2: 0)
    }

    /// Release everything on the hosted instrument (MIDI CC 123, All Notes Off).
    public func allNotesOff(channel: UInt8 = 0) {
        sendMIDI(status: 0xB0 | (channel & 0x0F), data1: 123, data2: 0)
    }

    private func sendMIDI(status: UInt8, data1: UInt8, data2: UInt8) {
        guard let block = instrumentUnit?.auAudioUnit.scheduleMIDIEventBlock else { return }
        let bytes: [UInt8] = [status, data1, data2]
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            block(AUEventSampleTimeImmediate, 0, bytes.count, base)
        }
    }
    #endif

    /// Scan installed Audio Units (instruments + effects). Idempotent; cheap enough to
    /// call on appear. No-op where AVFoundation is unavailable.
    public func scan() {
        scanGeneration &+= 1
        scanAttempt = 0
        performScan(generation: scanGeneration)
    }

    private func performScan(generation: Int) {
        #if canImport(AVFoundation)
        let mgr = AVAudioUnitComponentManager.shared()
        // THIRD-PARTY VISIBILITY (founder 2026-07-12: "Ich sehe bisher nur die
        // Apple AUv3. Ich habe viele auf meinem Handy installiert"): iOS
        // registers third-party AUv3 app extensions ASYNCHRONOUSLY — a query
        // can land before the extension registry is populated and then only
        // Apple's built-ins exist. The system announces late arrivals via
        // kAudioComponentRegistrationsChangedNotification; subscribe ONCE and
        // re-scan on every change so the lists fill in live, no Rescan tap
        // needed. (The canonical AUv3-host pattern — AUM/Cubasis do the same.)
        if registrationObserver == nil {
            registrationObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name(kAudioComponentRegistrationsChangedNotification as String),
                object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scan() }
            }
        }
        // Query the all-match wildcard AND each hosted type explicitly, AND the
        // full-registry enumeration (`passingTest`), then de-dupe. The all-zero
        // wildcard is documented to return everything, but the enumeration path
        // walks the registry directly — belt-and-suspenders so EVERY installed
        // third-party instrument/effect shows up, not just Apple's.
        var descriptions = [AudioComponentDescription()]   // all-zero = every component
        for t in [kAudioUnitType_MusicDevice, kAudioUnitType_Generator,
                  kAudioUnitType_Effect, kAudioUnitType_MusicEffect] {
            var d = AudioComponentDescription()
            d.componentType = t
            descriptions.append(d)
        }
        var components: [AVAudioUnitComponent] = []
        for d in descriptions { components.append(contentsOf: mgr.components(matching: d)) }
        components.append(contentsOf: mgr.components(passingTest: { _, _ in true }))
        // Diagnostic ground truth (into the device log): what the OS returned
        // BEFORE our type filter — the distinct makers + component TYPEs. If a
        // non-Apple maker shows HERE but not in the hosted lists, our type filter
        // dropped it (the type FourCC says which type to add); if only Apple shows
        // here too, iOS hasn't registered the third-party AUv3 extensions to this
        // host yet (their containing apps must be opened once to activate them).
        let rawMakers = Set(components.map(\.manufacturerName)).sorted()
        let rawTypes = Set(components.map {
            AUParameterMapping.fourCC($0.audioComponentDescription.componentType) }).sorted()
        let infos: [HostedAUInfo] = components.compactMap { c in
            let type = c.audioComponentDescription.componentType
            // Host every AUv3 sound source + effect a DAW channel uses. NOTE: many
            // third-party AUv3 INSTRUMENTS register as Generator, not MusicDevice —
            // include it so they appear (founder: "sehe nur die Apple AUv3").
            let isInstrument = (type == kAudioUnitType_MusicDevice || type == kAudioUnitType_Generator)
            let isEffect = (type == kAudioUnitType_Effect || type == kAudioUnitType_MusicEffect)
            guard isInstrument || isEffect else { return nil }
            let desc = c.audioComponentDescription
            return HostedAUInfo(
                id: "\(c.manufacturerName).\(c.name).\(desc.componentSubType)",
                name: c.name,
                manufacturer: c.manufacturerName,
                isInstrument: isInstrument,
                componentType: desc.componentType,
                componentSubType: desc.componentSubType,
                componentManufacturer: desc.componentManufacturer
            )
        }
        let split = Self.split(infos)
        instruments = split.instruments
        effects = split.effects
        // Into the pastable device log: what the registry actually returned —
        // the one line that separates "our query filters them out" from "iOS
        // hasn't registered them" when a device shows only Apple units.
        let makers = Set(instruments.map(\.manufacturer) + effects.map(\.manufacturer))
            .sorted().joined(separator: ", ")
        // Discriminators for the device log: how many NON-Apple components the OS
        // returned, and whether even Echoel's OWN bundled AUv3 ("Echo") is visible.
        // ownAUv3=false with 3rd-party=0 ⇒ the host sees only in-process Apple units
        // (registry not warm for this process); 3rd-party>0 ⇒ discovery is working.
        let thirdPartyCount = components.filter {
            let m = $0.audioComponentDescription.componentManufacturer
            return m != Self.appleManufacturer && m != Self.ownManufacturer
        }.count
        let ownAUv3 = components.contains {
            $0.audioComponentDescription.componentManufacturer == Self.ownManufacturer
        }
        EchoelCrashLog.breadcrumb(
            "auv3 scan[try \(scanAttempt)]: \(instruments.count) instruments + \(effects.count) effects — makers: \(makers)"
            + " | raw \(components.count) comps, 3rd-party \(thirdPartyCount), ownAUv3 \(ownAUv3)"
            + ", rawMakers: [\(rawMakers.joined(separator: ","))]"
            + " rawTypes: [\(rawTypes.joined(separator: ","))]")
        didScan = true
        // Cold-cache / late-registration backstop: when the OS returns only Apple
        // built-ins, the third-party registry is likely not warm yet for this
        // process — and because those extensions were registered BEFORE this launch,
        // no kAudioComponentRegistrationsChangedNotification fires to prompt a
        // refresh (the manual Rescan hits the same cold cache). Re-scan a few times
        // with growing delay so they fill in without relaunching. Stops the moment
        // any third-party unit appears. Generation-guarded so a newer scan() cancels
        // stale pending retries.
        if thirdPartyCount == 0 && scanAttempt < Self.maxScanRetries {
            scanAttempt += 1
            let delaySeconds = Double(scanAttempt) * 0.8   // 0.8, 1.6, 2.4, 3.2 s
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                guard let self, generation == self.scanGeneration else { return }
                self.performScan(generation: generation)
            }
        }
        #else
        didScan = true
        #endif
    }

    /// Pure split + de-dupe + alphabetical sort (testable without any installed AUs).
    public static func split(_ infos: [HostedAUInfo]) -> (instruments: [HostedAUInfo], effects: [HostedAUInfo]) {
        var seen = Set<String>()
        let unique = infos.filter { seen.insert($0.id).inserted }
        let inst = unique.filter { $0.isInstrument }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        let fx = unique.filter { !$0.isInstrument }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        return (inst, fx)
    }
}
