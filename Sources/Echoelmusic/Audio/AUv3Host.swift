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
public struct HostedAUInfo: Identifiable, Sendable, Equatable {
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

@MainActor
@Observable
public final class AUv3Host {

    public private(set) var instruments: [HostedAUInfo] = []
    public private(set) var effects: [HostedAUInfo] = []
    public private(set) var didScan = false

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

    /// The effect inserted on the hosted instrument's channel (instrument → effect →
    /// master), Ableton-device-chain style. nil = the instrument runs dry.
    public private(set) var loadedEffect: HostedAUInfo?

    #if canImport(AVFoundation)
    /// The instantiated instrument (held so we can re-wire + send it MIDI). Not observed.
    @ObservationIgnored private var instrumentUnit: AVAudioUnit?
    /// The instantiated insert effect on the instrument's channel.
    @ObservationIgnored private var effectUnit: AVAudioUnit?
    /// The engine we attach into. Set once at wire-up.
    @ObservationIgnored private weak var engine: AudioEngine?
    #endif

    public init() {
        self.replaceBuiltInVoice = UserDefaults.standard.bool(forKey: Self.replaceKey)
    }

    public var total: Int { instruments.count + effects.count }

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
        if !info.isInstrument, loadedEffect == info, effectUnit != nil { return }
        isLoading = true
        loadError = nil
        let desc = AudioComponentDescription(
            componentType: info.componentType,
            componentSubType: info.componentSubType,
            componentManufacturer: info.componentManufacturer,
            componentFlags: 0, componentFlagsMask: 0)
        do {
            let unit = try await AVAudioUnit.instantiate(with: desc, options: [])
            engine.withGraphPaused {                        // one pause cycle: attach + re-wire
                engine.attachAU(unit)
                if info.isInstrument {
                    if let old = instrumentUnit { engine.detachAU(old) }
                    instrumentUnit = unit
                } else {
                    if let old = effectUnit { engine.detachAU(old) }
                    effectUnit = unit
                }
                connectChainNow()
            }
            if info.isInstrument { loaded = info } else { loadedEffect = info }
            log.audio("AUv3 \(info.isInstrument ? "instrument" : "effect") loaded: \(info.name)")
        } catch {
            loadError = "Could not load \(info.name): \(error.localizedDescription)"
            log.audio("AUv3 load failed: \(error)", level: .error)
        }
        isLoading = false
    }

    /// Remove the hosted instrument (and re-wire so any effect is left dry/unfed).
    public func unload() {
        let unit = instrumentUnit
        instrumentUnit = nil
        loaded = nil
        engine?.withGraphPaused {
            if let unit { engine?.detachAU(unit) }
            connectChainNow()
        }
    }

    /// Remove the insert effect (instrument reconnects straight to master).
    public func unloadEffect() {
        let unit = effectUnit
        effectUnit = nil
        loadedEffect = nil
        engine?.withGraphPaused {
            if let unit { engine?.detachAU(unit) }
            connectChainNow()
        }
    }

    /// The connect logic — MUST be called inside `withGraphPaused`. (Re)builds the
    /// hosted channel: instrument → (effect →) master. Units are already attached;
    /// drop old output connections, then rebuild.
    private func connectChainNow() {
        guard let engine else { return }
        if let i = instrumentUnit { engine.disconnectAUOutput(i) }
        if let e = effectUnit { engine.disconnectAUOutput(e) }
        if let i = instrumentUnit, let e = effectUnit {
            engine.connectAU(i, to: e)
            engine.connectAUToMaster(e)
        } else if let i = instrumentUnit {
            engine.connectAUToMaster(i)
        }
        // Effect with no instrument has no source to process → left unconnected.
    }

    /// Preview: play a note on the hosted instrument (user-driven keyboard).
    /// Sends a MIDI note-on through the AU's host-MIDI block. No-op if nothing
    /// is loaded — preserves launch silence (nothing sounds until a user taps).
    public func noteOn(_ pitch: UInt8, velocity: UInt8 = 100, channel: UInt8 = 0) {
        sendMIDI(status: 0x90 | (channel & 0x0F), data1: pitch, data2: velocity)
    }

    /// The underlying AUAudioUnit (instrument or insert effect) so the UI layer can
    /// request the plugin's own view controller. nil when that slot is empty.
    public func auAudioUnit(forEffect: Bool) -> AUAudioUnit? {
        (forEffect ? effectUnit : instrumentUnit)?.auAudioUnit
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
        #if canImport(AVFoundation)
        let any = AudioComponentDescription()   // all-zero matches every component
        let components = AVAudioUnitComponentManager.shared().components(matching: any)
        let infos: [HostedAUInfo] = components.compactMap { c in
            let type = c.audioComponentDescription.componentType
            // Only host the kinds a DAW channel uses: instruments + effects.
            let isInstrument = (type == kAudioUnitType_MusicDevice)
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
        #endif
        didScan = true
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
