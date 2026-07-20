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
#if canImport(UIKit)
import UIKit
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

/// Founder-visible discovery diagnostic — the on-screen twin of the device-log
/// breadcrumb built in `performScan`. Pure value type so its `guidance` is unit-
/// tested off-device: the whole point is that the NEXT TestFlight build tells the
/// founder WHICH cold-registry cause they hit without pasting a log.
public struct AUv3ScanDiagnostic: Equatable, Sendable {
    /// Total AudioComponents the OS returned to this process (all types).
    public var rawComponentCount: Int
    /// How many of those are NON-Apple, NON-Echoel (real third-party) units.
    public var thirdPartyCount: Int
    /// Whether Echoel's OWN bundled AUv3 surfaced (proves the registry serves
    /// out-of-process components to this process at all).
    public var ownAUv3Present: Bool
    /// Which retry pass produced this snapshot (0…maxScanRetries).
    public var scanAttempt: Int
    /// Verdict of the once-per-process self-instantiate probe (nil until it runs).
    public var selfProbe: SelfProbe?
    /// The DISTINCT manufacturer display-names iOS returned to THIS process, before
    /// our type filter. This is the single most decisive field: if it lists only
    /// "Apple" while AUM (same device) shows dozens, iOS is serving this process an
    /// Apple-only registry (an app/process issue); if it names Moog/Imaginando/etc.
    /// yet the instrument list stays empty, OUR split/filter dropped them. Sorted.
    public var rawMakers: [String]

    /// The own-AUv3 self-instantiate probe result (see `performScan`).
    public enum SelfProbe: Equatable, Sendable {
        /// Registry SERVES our appex; the component LIST is stale for this process.
        case instantiateOK
        /// iOS has NOT registered the appex on this device (restart/reinstall).
        case failed(domain: String, code: Int)
    }

    public init(rawComponentCount: Int, thirdPartyCount: Int, ownAUv3Present: Bool,
                scanAttempt: Int, selfProbe: SelfProbe? = nil, rawMakers: [String] = []) {
        self.rawComponentCount = rawComponentCount
        self.thirdPartyCount = thirdPartyCount
        self.ownAUv3Present = ownAUv3Present
        self.scanAttempt = scanAttempt
        self.selfProbe = selfProbe
        self.rawMakers = rawMakers
    }

    /// Cold ⇒ the process saw NO real third-party units and not even our own AUv3.
    public var isCold: Bool { thirdPartyCount == 0 && !ownAUv3Present }

    /// One-line, founder-readable cause + the ONE action that helps. Empty when
    /// discovery is healthy (the browser only shows this while cold). The probe
    /// verdict is what discriminates "quit+reopen" (stale list) from "reinstall"
    /// (unregistered appex) — the two remaining causes once the retries are spent.
    public var guidance: String {
        guard isCold else { return "" }
        let counts = "iOS handed this app \(rawComponentCount) Audio Units — 0 third-party, own AUv3 not visible."
        switch selfProbe {
        case .none:
            return counts + " Running a self-test to find out why…"
        case .instantiateOK:
            return counts
                + " Self-test: OK — iOS DOES serve our plugin, but this app's plugin LIST is stale."
                + " Fully quit Echoelmusic (swipe it away) and reopen — that reliably refreshes the list."
        case let .failed(domain, code):
            return counts
                + " Self-test: FAILED (\(domain) \(code)) — the plugin extension isn't registered on this device."
                + " Reinstall Echoelmusic or restart the device. For third-party plugins, open each plugin's own app once."
        }
    }

    /// A complete, self-contained diagnostic the founder can COPY with one tap and
    /// paste back — so the deciding fact (which makers iOS returns to THIS process)
    /// travels without hunting for a small on-screen line or exporting a device log.
    /// Pure/deterministic, so it is CI-verifiable off-device.
    public var report: String {
        let probe: String
        switch selfProbe {
        case .none:            probe = "pending"
        case .instantiateOK:   probe = "instantiate-OK (list stale)"
        case let .failed(d, c): probe = "FAILED \(d)#\(c) (appex unregistered)"
        }
        let makers = rawMakers.isEmpty ? "none" : rawMakers.joined(separator: ", ")
        return "Echoel AUv3 scan[try \(scanAttempt)]: iOS returned \(rawComponentCount) Audio Units — "
            + "\(thirdPartyCount) third-party, own AUv3 \(ownAUv3Present ? "visible" : "not visible"), "
            + "self-probe \(probe). Makers iOS gave this app: [\(makers)]."
    }

    /// A founder- and log-friendly one-line reason for a FAILED AU load — for the
    /// symptom AFTER discovery works: the plugin is listed but won't open (founder
    /// 2026-07-19: "wird in AUM erkannt aber lässt sich nicht öffnen"). The raw
    /// OSStatus is what actually pins the cause (e.g. NSOSStatusErrorDomain -3000
    /// invalidComponentID = the extension isn't instantiable for this process;
    /// -10868 = unsupported format), but `localizedDescription` buries it under
    /// "The operation couldn’t be completed." — so the domain#code is surfaced
    /// explicitly. Pure/primitive, so it is CI-verifiable off-device.
    static func loadFailureMessage(name: String, domain: String, code: Int, localized: String) -> String {
        "Could not load \(name): \(localized) [\(domain) \(code)]"
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
    /// Re-scan trigger for AUv3 extensions registered BEFORE this launch: those never
    /// fire kAudioComponentRegistrationsChangedNotification, so RETURNING to the
    /// foreground (after the user opened a plugin's own app to activate it) is the
    /// missing signal. Set once; never removed (host lives the app's lifetime).
    @ObservationIgnored private var foregroundObserver: NSObjectProtocol?
    /// Retry ladder for a cold / late-registering third-party AUv3 registry (see scan()).
    @ObservationIgnored private var scanAttempt = 0
    /// Once-per-process gate for the own-AUv3 self-instantiate probe (see the
    /// diagnostic block at the end of `performScan`).
    @ObservationIgnored private var didProbeOwnComponent = false
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

    /// Night audit 2026-07-16: the registry is COLD for this process — the scan
    /// saw neither any third-party component NOR Echoel's own embedded AUv3
    /// (device log: "3rd-party 0, ownAUv3 false"). In that state the retry
    /// ladder and the manual Rescan hit the same cold cache (see performScan's
    /// backstop comment) — the only user action that reliably helps is
    /// RESTARTING the app. The browser shows that honestly instead of the
    /// provably ineffective "tap Rescan" advice.
    public private(set) var registryColdForProcess = false

    /// Founder-visible discovery diagnostic (the on-screen twin of the device-log
    /// breadcrumb). Set at the end of every scan pass; its `selfProbe` is filled
    /// in later when the once-per-process own-AUv3 probe completes. The browser
    /// renders `diagnostic.guidance` while cold so the cause is legible without a log.
    public private(set) var diagnostic: AUv3ScanDiagnostic?

    /// Restore records that failed against the cold registry, held for ONE
    /// retry when kAudioComponentRegistrationsChanged announces late arrivals
    /// (before this, a failed restore was never re-attempted for the whole
    /// process — the plugin came back only after the user manually reloaded it).
    @ObservationIgnored private var pendingRestoreInstrument: HostedAUInfo?
    @ObservationIgnored private var pendingRestoreEffects: [HostedAUInfo] = []
    @ObservationIgnored private var pendingRestoreMasters: [HostedAUInfo] = []

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
        // Defense-in-depth for records that predate the scan filter: an Apple
        // Generator (file-player API unit) must never become THE instrument —
        // it cannot sound from notes, so loading it silences the track.
        if Self.isAppleGeneratorRecord(info) {
            loadError = "\(info.name) is a system file-player unit, not a playable instrument."
            return
        }
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
            let unit = try await Self.instantiate(desc, name: info.name)
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
            let e = error as NSError
            loadError = AUv3ScanDiagnostic.loadFailureMessage(
                name: info.name, domain: e.domain, code: e.code, localized: e.localizedDescription)
            EchoelCrashLog.breadcrumb("auv3 load FAILED '\(info.name)': \(e.domain)#\(e.code) — \(e.localizedDescription)")
            log.audio("AUv3 load failed: \(e.domain)#\(e.code)", level: .error)
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
            let unit = try await Self.instantiate(desc, name: info.name)
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
            let e = error as NSError
            loadError = AUv3ScanDiagnostic.loadFailureMessage(
                name: info.name, domain: e.domain, code: e.code, localized: e.localizedDescription)
            EchoelCrashLog.breadcrumb("auv3 master-fx load FAILED '\(info.name)': \(e.domain)#\(e.code) — \(e.localizedDescription)")
            log.audio("AUv3 master effect load failed: \(e.domain)#\(e.code)", level: .error)
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
        var instrument = d.data(forKey: Self.chainInstrumentKey)
            .flatMap { try? decoder.decode(HostedAUInfo.self, from: $0) }
        let effects = d.data(forKey: Self.chainEffectsKey)
            .flatMap { try? decoder.decode([HostedAUInfo].self, from: $0) } ?? []
        let masters = d.data(forKey: Self.chainMasterKey)
            .flatMap { try? decoder.decode([HostedAUInfo].self, from: $0) } ?? []
        // HEAL, don't retry: a persisted Apple-Generator "instrument" (file-player
        // API unit — can never sound from notes) is INVALID data, not a transient
        // cold-registry failure, so the retention law does not apply. Before this
        // filter existed, one experimental tap on AUAudioFilePlayer was resurrected
        // on EVERY launch, permanently silencing the track (founder 2026-07-16).
        // Drop the record, say so, and the built-in voice returns.
        if let inst = instrument, Self.isAppleGeneratorRecord(inst) {
            d.removeObject(forKey: Self.chainInstrumentKey)
            instrument = nil
            restoreNotice = "\(inst.name) is a system file-player, not a playable instrument — removed. The built-in voice is back."
            log.audio("AUv3 restore pruned Apple generator instrument record: \(inst.name)", level: .error)
        }
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
            if loaded != instrument {
                failed.append(instrument.name)
                pendingRestoreInstrument = instrument   // one retry when the registry warms
            }
        }
        for info in effects {
            await load(info)
            if !loadedEffects.contains(info) {
                failed.append(info.name)
                pendingRestoreEffects.append(info)
            }
        }
        for info in masters {
            await loadMasterEffect(info)
            if !loadedMasterEffects.contains(info) {
                failed.append(info.name)
                pendingRestoreMasters.append(info)
            }
        }
        if !failed.isEmpty {
            // COMPOSE, don't assign: the trap-heal note set above must survive a
            // simultaneous load failure — an assignment here would overwrite the
            // only explanation of why the instrument record vanished (review LOW).
            restoreNotice = Self.composedNotice(restoreNotice,
                adding: "Not restored: \(failed.joined(separator: ", ")) — the plugin may still be waking up; reload it from this list.")
            log.audio("AUv3 chain restore incomplete: \(failed.joined(separator: ", "))", level: .error)
        }
    }

    /// True for an Apple Generator-typed record claiming to be an instrument —
    /// AUAudioFilePlayer / AUScheduledSoundPlayer etc. are programmatic file-player
    /// API units that never sound from MIDI notes (the "one tap = silent track"
    /// trap). Pure + static so tests pin it. Records predating the component
    /// codes (componentType == 0) pass — they fail instantiation honestly instead.
    nonisolated static func isAppleGeneratorRecord(_ info: HostedAUInfo) -> Bool {
        info.isInstrument
            && info.componentType == kAudioUnitType_Generator
            && info.componentManufacturer == kAudioUnitManufacturer_Apple
    }

    /// Append a restore problem to an existing notice instead of overwriting it —
    /// during one restore pass several things can go wrong (trap-heal + a failed
    /// plugin load) and each explanation must stay visible. Pure + static so
    /// tests pin the compose behavior.
    nonisolated static func composedNotice(_ existing: String?, adding addition: String) -> String {
        guard let existing, !existing.isEmpty else { return addition }
        return existing + "\n" + addition
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
                Task { @MainActor [weak self] in
                    self?.scan()
                    // Late registrations may include exactly the plugins whose
                    // chain restore failed at launch — re-drive those loads ONCE.
                    self?.retryFailedRestores()
                }
            }
        }
        // FOREGROUND RE-SCAN (baseline AU-host hygiene, mirrors the registration
        // observer above): an extension registered BEFORE this launch never fires
        // kAudioComponentRegistrationsChangedNotification, and an in-session Rescan
        // hits the same cold process cache — but RETURNING TO THE FOREGROUND (the user
        // just opened the plugin's own app to activate it, then came back to Echoel) is
        // a genuinely new registry state iOS may now serve this process. Re-scan on
        // foreground WHILE STILL COLD; a no-op once warm (guarded) and independent of
        // the once-per-process self-probe diagnostic (a warm result just clears the cold
        // UI, it never changes the probe verdict). Subscribe ONCE; host lives app-life.
        #if canImport(UIKit)
        if foregroundObserver == nil {
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.registryColdForProcess else { return }
                    self.scan()
                }
            }
        }
        #endif
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
            // APPLE's own Generator units (AUAudioFilePlayer, AUScheduledSoundPlayer)
            // are programmatic file-player API building blocks — they NEVER sound
            // from MIDI notes. Listed as "Instruments" they were a silence trap:
            // one tap replaced the built-in voice with a player that stays mute,
            // and since v267 the chain restore resurrected that mistake on every
            // launch (founder 2026-07-16: "Sound funktioniert gerade generell
            // nicht"). Third-party Generators stay — many real instruments
            // register with that type.
            if type == kAudioUnitType_Generator,
               desc.componentManufacturer == kAudioUnitManufacturer_Apple { return nil }
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
        // Honest cold-state flag (tracks every pass; flips false the moment ANY
        // non-built-in appears — incl. our own AUv3, which proves the registry
        // serves out-of-process components to this process).
        registryColdForProcess = (thirdPartyCount == 0 && !ownAUv3)
        // Founder-visible twin of the breadcrumb above. Preserve any self-probe
        // verdict already captured this process (the probe runs at most once, after
        // the last retry — a later scan pass must not erase its result).
        diagnostic = AUv3ScanDiagnostic(rawComponentCount: components.count,
                                        thirdPartyCount: thirdPartyCount,
                                        ownAUv3Present: ownAUv3,
                                        scanAttempt: scanAttempt,
                                        selfProbe: diagnostic?.selfProbe,
                                        rawMakers: rawMakers)
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
        // SELF-INSTANTIATE PROBE (founder log 2026-07-17, v279/2385: ownAUv3 false in
        // EVERY scan although the archive verifiably embeds the appex with the correct
        // registration structure — TestFlight run 29545339997 "AUv3 embed OK"): the
        // component LIST and the component REGISTRY can disagree per process. Probing
        // our OWN component by description makes the NEXT device log discriminate the
        // two remaining causes: instantiation OK while the list is empty ⇒ the process's
        // component-list cache is stale (registry actually serves the appex); an
        // OSStatus error (e.g. -3000 invalidComponentID) ⇒ iOS genuinely has not
        // registered the appex on this device (restart/reinstall territory). Runs ONCE
        // per process, only after the LAST retry still shows no own component. The
        // probed unit is discarded, never attached; the 10 s instantiate deadline and
        // the exactly-once gate already guard the hang case.
        if !ownAUv3, scanAttempt >= Self.maxScanRetries, !didProbeOwnComponent {
            didProbeOwnComponent = true
            var probeDesc = AudioComponentDescription()
            probeDesc.componentType = kAudioUnitType_Generator
            probeDesc.componentSubType = Self.fourCC("echl")
            probeDesc.componentManufacturer = Self.ownManufacturer
            Task { @MainActor in
                do {
                    _ = try await Self.instantiate(probeDesc, name: "Echoelmusic (own-AUv3 probe)")
                    EchoelCrashLog.breadcrumb(
                        "auv3 self-probe: INSTANTIATE OK — registry serves the own appex; the component LIST is stale for this process")
                    // Surface the verdict on-screen too (founder-visible), so the
                    // next build discriminates stale-list vs. unregistered without a log.
                    diagnostic?.selfProbe = .instantiateOK
                } catch {
                    let e = error as NSError
                    EchoelCrashLog.breadcrumb(
                        "auv3 self-probe: FAILED \(e.domain)#\(e.code) — own appex not registered on this device (restart/reinstall territory)")
                    diagnostic?.selfProbe = .failed(domain: e.domain, code: e.code)
                }
            }
        }
        #else
        didScan = true
        #endif
    }

    // MARK: - Instantiation with a hard deadline (night audit MEDIUM)

    #if canImport(AVFoundation)
    /// A defective third-party extension can hang its XPC handshake FOREVER; a
    /// plain `try await AVAudioUnit.instantiate` then never returns, `isLoading`
    /// stays true for the rest of the process — permanent spinner, no other
    /// plugin loadable. NOTE a task-group timeout would NOT help here: the group
    /// awaits its (un-cancellable) instantiate child on scope exit, so the hang
    /// just moves. The completion-handler API + an exactly-once gate gives a real
    /// deadline: on timeout the load path surfaces a loadError and releases the
    /// gate; a unit arriving late is discarded on the spot (never attached).
    private static let instantiateTimeoutSeconds: Double = 10

    private enum AUInstantiateError: LocalizedError {
        case timedOut(String)
        var errorDescription: String? {
            switch self {
            case .timedOut(let name):
                return "\(name) is not responding — open the plugin's own app once, or reinstall it."
            }
        }
    }

    /// Exactly-once gate for racing the completion handler against the deadline.
    /// Control-plane only (never the audio thread), so the lock is fine.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        func run(_ body: () -> Void) {
            lock.lock(); defer { lock.unlock() }
            guard !resumed else { return }
            resumed = true
            body()
        }
    }

    /// Sendable carrier for the freshly built (non-Sendable) unit — the closure
    /// parameter is task-isolated under region isolation, so resuming the
    /// continuation with it raw is the one plausible Swift-6 compile failure
    /// here (concurrency review #1); the box is unconditionally correct.
    private struct AVUnitBox: @unchecked Sendable { let unit: AVAudioUnit }

    nonisolated private static func instantiate(_ desc: AudioComponentDescription,
                                                name: String) async throws -> AVAudioUnit {
        let box: AVUnitBox = try await withCheckedThrowingContinuation { cont in
            let once = ResumeOnce()
            let deadline = Task {
                try? await Task.sleep(nanoseconds: UInt64(Self.instantiateTimeoutSeconds * 1_000_000_000))
                once.run { cont.resume(throwing: AUInstantiateError.timedOut(name)) }
            }
            AVAudioUnit.instantiate(with: desc, options: []) { unit, error in
                once.run {
                    deadline.cancel()
                    if let unit {
                        cont.resume(returning: AVUnitBox(unit: unit))
                    } else {
                        cont.resume(throwing: error ?? AUInstantiateError.timedOut(name))
                    }
                }
            }
        }
        return box.unit
    }
    #endif

    /// One-shot retry of restore records that failed at launch, fired from the
    /// registrationsChanged observer (the registry just announced new arrivals).
    /// Cleared BEFORE the loads so a second notification can't double-drive them;
    /// a load that fails again surfaces its normal loadError — no loop.
    private func retryFailedRestores() {
        guard pendingRestoreInstrument != nil
                || !pendingRestoreEffects.isEmpty
                || !pendingRestoreMasters.isEmpty else { return }
        let instrument = pendingRestoreInstrument
        let fx = pendingRestoreEffects
        let masters = pendingRestoreMasters
        pendingRestoreInstrument = nil
        pendingRestoreEffects = []
        pendingRestoreMasters = []
        log.audio("AUv3 registry warmed — retrying failed chain restores")
        Task { @MainActor in
            // Lost-update guard (concurrency review #2): a retry can be silently
            // dropped by load()'s isLoading gate (e.g. the notification fires while
            // another load is suspended at instantiate) — re-appending on failure
            // keeps the record for the NEXT registrationsChanged instead of losing
            // the plugin until a manual reload.
            if let instrument {
                await self.load(instrument)
                if self.loaded != instrument { self.pendingRestoreInstrument = instrument }
            }
            for info in fx {
                await self.load(info)
                if !self.loadedEffects.contains(info) { self.pendingRestoreEffects.append(info) }
            }
            for info in masters {
                await self.loadMasterEffect(info)
                if !self.loadedMasterEffects.contains(info) { self.pendingRestoreMasters.append(info) }
            }
        }
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
