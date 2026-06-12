// Project.swift
// Echoel — one saved take, the whole point of the app: the body-generated loop
// plus everything needed to recall and re-export it. Pure Codable value type so it
// round-trips to JSON in the App Group (see ProjectStore). Enums are stored as raw
// strings for forward-compatible decoding.

import Foundation

public struct Project: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var savedAt: Date

    // Musical setup
    public var styleRaw: String        // MusicStyle.rawValue
    public var keyRoot: Int            // 0…11
    public var scaleRaw: String        // Scale.rawValue
    public var bpm: Double
    public var modeRaw: String         // ComposerMode.rawValue
    public var fxCharacterRaw: String  // FXCharacter.rawValue
    public var loopBars: Int
    public var a4Hz: Double            // Kammerton
    public var artist: String

    // Generated content
    public var patch: SynthPatch
    public var notes: [Note]
    public var drumSteps: [[Bool]]
    public var drumAccents: [[Bool]]

    public init(
        id: UUID = UUID(), name: String, savedAt: Date = Date(),
        styleRaw: String, keyRoot: Int, scaleRaw: String, bpm: Double,
        modeRaw: String, fxCharacterRaw: String, loopBars: Int,
        a4Hz: Double, artist: String,
        patch: SynthPatch, notes: [Note],
        drumSteps: [[Bool]], drumAccents: [[Bool]]
    ) {
        self.id = id; self.name = name; self.savedAt = savedAt
        self.styleRaw = styleRaw; self.keyRoot = keyRoot; self.scaleRaw = scaleRaw
        self.bpm = bpm; self.modeRaw = modeRaw; self.fxCharacterRaw = fxCharacterRaw
        self.loopBars = loopBars; self.a4Hz = a4Hz; self.artist = artist
        self.patch = patch; self.notes = notes
        self.drumSteps = drumSteps; self.drumAccents = drumAccents
    }

    // MARK: - Decoded accessors (raw → enum, with safe fallbacks)

    public var style: MusicStyle { MusicStyle(rawValue: styleRaw) ?? .dubTechno }
    public var scale: Scale { Scale(rawValue: scaleRaw) ?? .minor }
    public var key: MusicalKey { MusicalKey(root: keyRoot, scale: scale) }
    public var mode: ComposerMode { ComposerMode(rawValue: modeRaw) ?? .studioLocked }
    public var fxCharacter: FXCharacter { FXCharacter(rawValue: fxCharacterRaw) ?? .auto }
}
