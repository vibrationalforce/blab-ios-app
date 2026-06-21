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

    #if canImport(AVFoundation)
    /// The instantiated unit (held so we can detach + send it MIDI). Not observed.
    @ObservationIgnored private var hostedUnit: AVAudioUnit?
    /// The engine we attach into. Set once at wire-up.
    @ObservationIgnored private weak var engine: AudioEngine?
    #endif

    public init() {}

    public var total: Int { instruments.count + effects.count }

    #if canImport(AVFoundation)
    /// Wire the host to the live audio engine (called once at app start).
    public func use(engine: AudioEngine) { self.engine = engine }

    /// Load a discovered instrument into the audio graph so it can be played.
    /// Async (AU instantiation is asynchronous); idempotent per-info. Only
    /// instruments are hosted in this slice — effect insertion comes next.
    public func load(_ info: HostedAUInfo) async {
        guard info.isInstrument else {
            loadError = "Effect hosting is the next step — instruments only for now."
            return
        }
        guard let engine else { loadError = "Audio engine unavailable."; return }
        if loaded == info, hostedUnit != nil { return }   // already loaded
        isLoading = true
        loadError = nil
        unloadUnit()                                       // free any previous unit
        let desc = AudioComponentDescription(
            componentType: info.componentType,
            componentSubType: info.componentSubType,
            componentManufacturer: info.componentManufacturer,
            componentFlags: 0, componentFlagsMask: 0)
        do {
            let unit = try await AVAudioUnit.instantiate(with: desc, options: [])
            engine.attachAUNode(unit)
            hostedUnit = unit
            loaded = info
            log.audio("AUv3 instrument loaded: \(info.name)")
        } catch {
            loadError = "Could not load \(info.name): \(error.localizedDescription)"
            log.audio("AUv3 load failed: \(error)", level: .error)
        }
        isLoading = false
    }

    /// Remove the hosted instrument from the graph.
    public func unload() {
        unloadUnit()
        loaded = nil
    }

    private func unloadUnit() {
        if let unit = hostedUnit { engine?.detachAUNode(unit) }
        hostedUnit = nil
    }

    /// Preview: play a note on the hosted instrument (user-driven keyboard).
    /// Sends a MIDI note-on through the AU's host-MIDI block. No-op if nothing
    /// is loaded — preserves launch silence (nothing sounds until a user taps).
    public func noteOn(_ pitch: UInt8, velocity: UInt8 = 100, channel: UInt8 = 0) {
        sendMIDI(status: 0x90 | (channel & 0x0F), data1: pitch, data2: velocity)
    }

    public func noteOff(_ pitch: UInt8, channel: UInt8 = 0) {
        sendMIDI(status: 0x80 | (channel & 0x0F), data1: pitch, data2: 0)
    }

    /// Release everything on the hosted instrument (MIDI CC 123, All Notes Off).
    public func allNotesOff(channel: UInt8 = 0) {
        sendMIDI(status: 0xB0 | (channel & 0x0F), data1: 123, data2: 0)
    }

    private func sendMIDI(status: UInt8, data1: UInt8, data2: UInt8) {
        guard let block = hostedUnit?.auAudioUnit.scheduleMIDIEventBlock else { return }
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
