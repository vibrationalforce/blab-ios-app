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

    public init(id: String, name: String, manufacturer: String, isInstrument: Bool) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.isInstrument = isInstrument
    }
}

@MainActor
@Observable
public final class AUv3Host {

    public private(set) var instruments: [HostedAUInfo] = []
    public private(set) var effects: [HostedAUInfo] = []
    public private(set) var didScan = false

    public init() {}

    public var total: Int { instruments.count + effects.count }

    /// Scan installed Audio Units (instruments + effects). Idempotent; cheap enough to
    /// call on appear. No-op where AVFoundation is unavailable.
    public func scan() {
        #if canImport(AVFoundation)
        var any = AudioComponentDescription()   // all-zero matches every component
        let components = AVAudioUnitComponentManager.shared().components(matching: any)
        _ = any                                  // silence unused-mutation note
        let infos: [HostedAUInfo] = components.compactMap { c in
            let type = c.audioComponentDescription.componentType
            // Only host the kinds a DAW channel uses: instruments + effects.
            let isInstrument = (type == kAudioUnitType_MusicDevice)
            let isEffect = (type == kAudioUnitType_Effect || type == kAudioUnitType_MusicEffect)
            guard isInstrument || isEffect else { return nil }
            let sub = c.audioComponentDescription.componentSubType
            return HostedAUInfo(
                id: "\(c.manufacturerName).\(c.name).\(sub)",
                name: c.name,
                manufacturer: c.manufacturerName,
                isInstrument: isInstrument
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
