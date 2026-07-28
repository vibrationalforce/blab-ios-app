// Project.swift
// Echoel — one saved take, the whole point of the app: the body-generated loop
// plus everything needed to recall and re-export it. Pure Codable value type so it
// round-trips to JSON in the App Group (see ProjectStore). Enums are stored as raw
// strings for forward-compatible decoding.

import Foundation

public struct Project: Codable, Sendable, Identifiable, Equatable {

    /// The format version THIS build writes. Bump it when a change to the saved shape
    /// cannot be expressed as "a new optional field with a default" — i.e. when an
    /// existing field changes MEANING or units, which `decodeIfPresent` cannot detect
    /// and would silently misread.
    ///
    /// WHY IT EXISTS BEFORE THERE IS ANY MIGRATION TO RUN (#189, founder 2026-07-27:
    /// "erst vollständig + versioniert, DANN Cloud"). A version stamp is only useful if
    /// it was already in the file BEFORE the breaking change — added afterwards, every
    /// pre-existing save is indistinguishable from the new format and the migration has
    /// nothing to branch on. `SpatialScene` is the only other stored type here that
    /// carries one; every remaining store would have this same blind spot on its first
    /// real format change. This closes it for the one format that holds the user's takes.
    ///
    /// 1 = the shape as of 2026-07-28. A file written before this field existed decodes
    /// as `0`, which is a TRUE statement about it (pre-versioning) and not a default
    /// standing in for "current" — that distinction is the whole point of the field.
    public static let currentSchemaVersion = 1

    /// Version of the format this instance was WRITTEN in — `0` for a file that predates
    /// the stamp. Not `let`: a future migration rewrites it after upgrading the payload.
    public var schemaVersion: Int

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
        // Deliberately NOT an init parameter: a freshly-built Project is by definition in
        // the format this build writes, and there is no caller that could honestly supply
        // anything else. Keeping it out also leaves all ~10 existing call sites untouched.
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id; self.name = name; self.savedAt = savedAt
        self.styleRaw = styleRaw; self.keyRoot = keyRoot; self.scaleRaw = scaleRaw
        self.bpm = bpm; self.modeRaw = modeRaw; self.fxCharacterRaw = fxCharacterRaw
        self.loopBars = loopBars; self.a4Hz = a4Hz; self.artist = artist
        self.patch = patch; self.notes = notes
        self.drumSteps = drumSteps; self.drumAccents = drumAccents
    }

    // MARK: - Defensive decoding (forward/backward-compatible)

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id, name, savedAt, styleRaw, keyRoot, scaleRaw, bpm, modeRaw
        case fxCharacterRaw, loopBars, a4Hz, artist, patch, notes, drumSteps, drumAccents
    }

    /// Custom decoder so a take saved by an OLDER (or FUTURE) build — one that predates
    /// a field, or was written after one was added — still loads instead of throwing
    /// `keyNotFound` and vaporizing the user's whole saved take. Every field tolerates
    /// absence via `decodeIfPresent` + a sensible default (the house persistence law that
    /// the ~15 other stored structs, incl. the embedded SynthPatch, already follow —
    /// Project was the one top-level save format that skipped it).
    ///
    /// Encoding is now EXPLICIT rather than synthesized — see `encode(to:)` for the one
    /// reason it had to stop being synthesized (the version stamp must describe the bytes
    /// being written, not the bytes this instance was read from).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `?? 0` and NOT `?? currentSchemaVersion`: a file with no stamp is genuinely
        // pre-versioning, and saying so is the only thing that makes a later migration
        // able to tell the two apart.
        schemaVersion  = try c.decodeIfPresent(Int.self,      forKey: .schemaVersion)  ?? 0
        id             = try c.decodeIfPresent(UUID.self,     forKey: .id)             ?? UUID()
        name           = try c.decodeIfPresent(String.self,   forKey: .name)           ?? "Take"
        savedAt        = try c.decodeIfPresent(Date.self,     forKey: .savedAt)        ?? Date()
        styleRaw       = try c.decodeIfPresent(String.self,   forKey: .styleRaw)       ?? ""
        keyRoot        = try c.decodeIfPresent(Int.self,      forKey: .keyRoot)        ?? 0
        scaleRaw       = try c.decodeIfPresent(String.self,   forKey: .scaleRaw)       ?? ""
        bpm            = try c.decodeIfPresent(Double.self,   forKey: .bpm)            ?? 120
        modeRaw        = try c.decodeIfPresent(String.self,   forKey: .modeRaw)        ?? ""
        fxCharacterRaw = try c.decodeIfPresent(String.self,   forKey: .fxCharacterRaw) ?? ""
        loopBars       = try c.decodeIfPresent(Int.self,      forKey: .loopBars)       ?? 1
        a4Hz           = try c.decodeIfPresent(Double.self,   forKey: .a4Hz)           ?? 440
        artist         = try c.decodeIfPresent(String.self,   forKey: .artist)         ?? ""
        patch          = try c.decodeIfPresent(SynthPatch.self, forKey: .patch)        ?? SynthPatch(name: "Default")
        // ELEMENT-TOLERANT, and this is the half of the defence `decodeIfPresent` cannot
        // give. `try c.decodeIfPresent([Note].self, …)` was still ALL-OR-NOTHING inside the
        // array: the key is present, so a single malformed element throws rather than
        // returning nil, that throw leaves `Project.init(from:)`, and `ProjectStore`'s
        // `try?` turns the user's ENTIRE take into nothing. `LossyDecoded` turns one bad
        // note into one missing note. (The library-level wipe was already fixed by
        // `loadLossyArray`; this is the same bug one level deeper — inside a single take.)
        //
        // THE CONCRETE WAY IT FIRES, so this does not read as paranoia: `Note.role` is a
        // `String`-raw enum decoded with `decodeIfPresent(NoteRole.self, …)`, and the
        // synthesized `RawRepresentable` decode THROWS `dataCorrupted` on a raw value it
        // does not know — `decodeIfPresent` only absorbs a MISSING key, never an unknown
        // case. So the day a build adds a fourth `NoteRole`, every take saved by it is
        // unreadable by any earlier build, whole-file. Element tolerance bounds that to
        // the notes actually carrying the new role.
        //
        // Unordered content, so holes are dropped (`compactMap`) — the note's own
        // `startTick` carries its position, unlike `ClipStore`'s index-is-the-slot grid.
        notes          = (try c.decodeIfPresent([LossyDecoded<Note>].self, forKey: .notes) ?? [])
            .compactMap(\.value)
        // NOT hardened the same way, deliberately: these two are the drum apparatus the
        // founder removed (#166), scheduled for deletion by #167. Left exactly as they are
        // so the removal is a clean subtraction rather than a revert of new work — and
        // dropping the keys later is safe, since an unlisted key is simply ignored.
        drumSteps      = try c.decodeIfPresent([[Bool]].self, forKey: .drumSteps)      ?? []
        drumAccents    = try c.decodeIfPresent([[Bool]].self, forKey: .drumAccents)    ?? []
    }

    /// Explicit, for exactly ONE reason: the version stamp must describe the BYTES BEING
    /// WRITTEN, not the bytes this instance was read from.
    ///
    /// The synthesized encoder would write back `schemaVersion` verbatim — so a take
    /// loaded from a pre-stamp file (`0`) and re-saved by this build would keep claiming
    /// `0` forever, even though the file it just produced carries every current field. A
    /// migration reading that stamp would then re-run on already-migrated data. Writing
    /// `currentSchemaVersion` unconditionally is what makes the field mean what it says.
    ///
    /// Every other key is written verbatim, so a fully-populated JSON still round-trips
    /// unchanged. ⚠️ A new stored property must be added HERE as well as to `CodingKeys`
    /// and the decoder — synthesis is no longer covering for an omission, and a field
    /// silently missing from a save is the same data loss this whole file guards against.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(savedAt, forKey: .savedAt)
        try c.encode(styleRaw, forKey: .styleRaw)
        try c.encode(keyRoot, forKey: .keyRoot)
        try c.encode(scaleRaw, forKey: .scaleRaw)
        try c.encode(bpm, forKey: .bpm)
        try c.encode(modeRaw, forKey: .modeRaw)
        try c.encode(fxCharacterRaw, forKey: .fxCharacterRaw)
        try c.encode(loopBars, forKey: .loopBars)
        try c.encode(a4Hz, forKey: .a4Hz)
        try c.encode(artist, forKey: .artist)
        try c.encode(patch, forKey: .patch)
        try c.encode(notes, forKey: .notes)
        try c.encode(drumSteps, forKey: .drumSteps)
        try c.encode(drumAccents, forKey: .drumAccents)
    }

    // MARK: - Decoded accessors (raw → enum, with safe fallbacks)

    public var style: MusicStyle { MusicStyle(rawValue: styleRaw) ?? .dubTechno }
    public var scale: Scale { Scale(rawValue: scaleRaw) ?? .minor }
    public var key: MusicalKey { MusicalKey(root: keyRoot, scale: scale) }
    public var mode: ComposerMode { ComposerMode(rawValue: modeRaw) ?? .studioLocked }
    public var fxCharacter: FXCharacter { FXCharacter(rawValue: fxCharacterRaw) ?? .auto }
}
