// AUPluginRef.swift
// Echoel — AUv3-structure block U3. A pure, persistable reference to a hosted
// Audio Unit plugin: the four component codes + display names, enough to
// re-instantiate it (AudioComponentDescription) and show it. A timeline track
// stores these to record its instrument + FX-chain assignment.
//
// Identity law: a plugin's `id` is its parameter-registry prefix
// "au.<mfrFourCC>.<subFourCC>" — the SAME plugin identity its parameters carry
// as "au.<mfr>.<sub>.<address>" keyPaths, so a lane's assigned instrument and
// its automatable params line up. Foundation-only (no AVFoundation) so the
// timeline model stays engine-independent and CI-testable; the Audio layer maps
// this to/from HostedAUInfo.

import Foundation

public struct AUPluginRef: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    public var manufacturerName: String
    public var componentType: UInt32
    public var componentSubType: UInt32
    public var componentManufacturer: UInt32
    public var isInstrument: Bool

    public init(name: String, manufacturerName: String,
                componentType: UInt32, componentSubType: UInt32,
                componentManufacturer: UInt32, isInstrument: Bool) {
        self.name = name
        self.manufacturerName = manufacturerName
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturer = componentManufacturer
        self.isInstrument = isInstrument
    }

    /// Stable plugin identity = the parameter-registry prefix for this plugin.
    public var id: String {
        AUParameterMapping.pluginPrefix(manufacturer: componentManufacturer,
                                        subType: componentSubType)
    }

    /// True for an Apple Generator-typed ref claiming to be an instrument —
    /// AUAudioFilePlayer / AUScheduledSoundPlayer are programmatic file-player
    /// API units that never sound from MIDI notes. A lane assigned one (possible
    /// on pre-v272 builds, persisted in the timeline document) instantiates fine
    /// and then stays MUTE — the "silent track" trap, per-lane edition. Twin of
    /// AUv3Host.isAppleGeneratorRecord; literal FourCCs ('augn', 'appl') because
    /// this file is Foundation-only and Linux-CI-tested (no AudioToolbox).
    public var isAppleGeneratorTrap: Bool {
        isInstrument
            && componentType == 0x6175_676E      // 'augn' = kAudioUnitType_Generator
            && componentManufacturer == 0x6170_706C  // 'appl' = kAudioUnitManufacturer_Apple
    }
}
