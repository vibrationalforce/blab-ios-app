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

    /// Version of the file this instance was READ FROM — `0` for a file that predates the
    /// stamp. It is PROVENANCE, not the state of any file on disk: `encode(to:)` always
    /// writes `currentSchemaVersion`, so after a save the bytes say 1 while this value still
    /// says where the take came from.
    ///
    /// ⚠️ THE CONSEQUENCE FOR ANY FUTURE MIGRATION, because getting it wrong re-runs the
    /// migration on already-migrated data: **migrate at LOAD, in `init(from:)`, not at save
    /// and not off this property later in the session.** A take loaded as `0` keeps reading
    /// `0` in memory for the whole session even after `ProjectStore.save()` has written a
    /// current-shape file. `var` rather than `let` only so a migration inside the decoder can
    /// stamp the value it produced.
    public var schemaVersion: Int

    public var id: UUID
    public var name: String
    public var savedAt: Date

    /// #273 — THE ONE RESERVED SLOT THE AUTOSAVE WRITES TO, and the reason it is a fixed
    /// constant rather than a fresh `UUID()`.
    ///
    /// Until this existed there was no autosave at all: every `ProjectStore.save` caller in
    /// `Sources/` was an explicit user action, and no `scenePhase` observer touched the
    /// PROJECT store. Backgrounding the app or taking a call lost the take — and a
    /// body-generated take cannot be reproduced by repeating the inputs, so "lost" is final.
    ///
    /// ⛔ THREE THINGS THE FIRST VERSION OF THIS DOC CLAIMED THAT ARE FALSE, corrected here
    /// rather than silently swapped, because each one would send the next reader looking for
    /// something that is not there:
    ///   1. "exactly two callers" — there are THREE (`saveCurrent`'s alert, the peer receive,
    ///      and `importProject`'s own `return save(p)` behind the live `.fileImporter`).
    ///      Counting them wrong is how one gets missed when the shape changes.
    ///   2. "neither `scenePhase` observer touched a store" — `EchoelmusicApp` has flushed the
    ///      TIMELINE store from its `.background` branch all along
    ///      (`timelineStore.flushPendingSave()`). That is the house precedent this slice
    ///      follows, not a novelty; only the PROJECT store was unserved.
    ///   3. "or crashing" — this fixes NO crash. A crash delivers no scene-phase transition,
    ///      so nothing runs. What it covers is an orderly departure: home button, app switch,
    ///      incoming call.
    ///
    /// ⚠️ AND THE FORCE-UNWRAP IS KNOWINGLY BENT (`CLAUDE.md` bans them). It is pinned by a
    /// blocking-bundle test that asserts this exact string, so a typo goes red in CI before it
    /// ships. Worth naming anyway: were it ever to fail it would trap at the FIRST AUTOSAVE —
    /// on the way out of the app, with the user's take in hand — not at launch where it would
    /// be found in a second.
    ///
    /// `ProjectStore.save` matches by `id`, so a fixed one makes every autosave REPLACE the
    /// previous one: one row in the library, not a row per app switch. It also guarantees the
    /// autosave can never overwrite a take the user named and saved deliberately — those
    /// carry their own random ids, and this value is not reachable through any other path.
    ///
    /// ⚠️ NEVER CHANGE THIS VALUE. An installation carrying an autosave written under the old
    /// constant would keep it forever as an ordinary-looking library row that the next
    /// autosave no longer replaces, and the user has no way to tell the two apart.
    public static let autosaveSlotID = UUID(uuidString: "E0000000-0000-4000-8000-000000000A05")!

    /// Prefix that marks the reserved row in the library list. Cosmetic — the `id` is what
    /// makes the slot reserved — but a row the user did not create has to say so, or the
    /// first thing they learn about the autosave is that "their" save renamed itself.
    public static let autosaveNamePrefix = "Auto · "

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

    /// #493 — THE SECOND TUNING AXIS, and it was the only one that did not travel with the
    /// take. `a4Hz` (the Kammerton) has been saved and restored since this format existed;
    /// the TONE SYSTEM — the twelve cent offsets that make a take Maqām Rāst rather than
    /// 12-TET — lived only in `@AppStorage("toneSystemID")`, i.e. in the instrument, never
    /// in the take. Saving a Rāst loop, switching to 12-TET and reopening the loop gave you
    /// 12-TET: the same "two tunings at once" defect #312/#338 fixed inside one session,
    /// arriving instead through the save path.
    ///
    /// ⭐ OPTIONAL, AND THE OPTIONALITY IS THE DESIGN, not laziness about defaults. A
    /// non-optional `String` with `?? "edo12"` would mean every take written before this
    /// build claims 12-TET — so opening a legacy take would silently drag a player who has
    /// chosen Gamelan back to 12-TET, on a value they never set in that take. `nil` says the
    /// only true thing about such a file: **this take does not state a tone system**, and
    /// the open path then leaves the instrument's current one alone. That asymmetry is
    /// deliberate and is pinned by `TheToneSystemTravelsWithTheTakeTests`.
    ///
    /// It carries the RAW id (`TuningSystem.named(_:)`'s key), not a resolved table, for the
    /// same forward-compatibility reason every other enum here is stored as a raw string: a
    /// take written by a build that knows a system this one does not must still load, and
    /// `TuningSystem.named` already falls back for an unknown id.
    ///
    /// ⚠️ NOT the same question as `a4Hz`, even though they are set in the same header strip
    /// and `LaneVoiceRack` latches them together (#338). A4 is a single scalar the whole
    /// world agrees on; the tone system chooses which twelve pitch classes exist. Both now
    /// travel; neither implies the other.
    public var toneSystemID: String?

    // Generated content
    public var patch: SynthPatch
    public var notes: [Note]
    public var drumSteps: [[Bool]]
    public var drumAccents: [[Bool]]

    public init(
        id: UUID = UUID(), name: String, savedAt: Date = Date(),
        styleRaw: String, keyRoot: Int, scaleRaw: String, bpm: Double,
        modeRaw: String, fxCharacterRaw: String, loopBars: Int,
        a4Hz: Double, toneSystemID: String?, artist: String,
        patch: SynthPatch, notes: [Note],
        drumSteps: [[Bool]], drumAccents: [[Bool]]
    ) {
        // Deliberately NOT an init parameter: a freshly-built Project is by definition in
        // the format this build writes, and there is no caller that could honestly supply
        // anything else. Keeping it out also leaves all ~10 existing call sites untouched.
        //
        // ⚠️ `toneSystemID` IS a parameter and deliberately has NO DEFAULT, which is the
        // opposite decision for the opposite reason. `= nil` would have kept both call sites
        // compiling untouched — and that is exactly the failure mode #440/#443 paid for
        // twice: an argument no call site writes appears in no diff, so the field would read
        // as "wired" while every save wrote nothing. Counted with `git grep -n "Project("` over
        // the WHOLE repo (#494) there are SEVEN call sites: `EchoelStudioView.currentProject()`,
        // `AutosaveSlotTests`, `TheToneSystemTravelsWithTheTakeTests`,
        // `TheModeTravelsWithTheTakeTests`, `ColabPayloadTests`, and TWO in `ProjectStoreTests`.
        //
        // ⛔ THE COUNT HAS NOW BEEN WRONG TWICE, AND THE SECOND MISS BROKE A BUILD. The first
        // version said TWO — it named the two I had edited and omitted `ColabPayloadTests`. The
        // correction said FOUR, and it was written in the same breath as the rule "a count of
        // call sites is a `git grep` over the WHOLE repo" — while still missing the two in
        // `ProjectStoreTests`, so #493 shipped with `Tests/EchoelmusicTests` NOT COMPILING and
        // nothing went red. **That is the real lesson, and it is not about counting.** Both
        // misses sit in `Tests/EchoelmusicTests`, the directory neither real gate compiles
        // (#208) and whose own workflow reports `success` regardless: the compiler error a
        // missing default is supposed to buy is only collectable where a gate compiles the
        // caller. In the other half of the tree a required argument buys silence.
        //
        // ⛔ THE FIRST VERSION OF THIS COMMENT SAID "TWO", and the miss is worth keeping: it
        // named the two I had edited and omitted `ColabPayloadTests`, which lives in
        // `Tests/EchoelmusicTests` — the NON-blocking suite (#208). Neither real gate compiles
        // that directory, so a call site missed there does not go red at either one; it would
        // have surfaced only in `swift build`, and this container has no toolchain. **A count of
        // call sites is a `git grep` over the WHOLE repo, not over the files one happens to have
        // open** — and the half of the tree that no gate compiles is exactly the half where an
        // uncounted caller can sit unnoticed.
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id; self.name = name; self.savedAt = savedAt
        self.styleRaw = styleRaw; self.keyRoot = keyRoot; self.scaleRaw = scaleRaw
        self.bpm = bpm; self.modeRaw = modeRaw; self.fxCharacterRaw = fxCharacterRaw
        self.loopBars = loopBars; self.a4Hz = a4Hz; self.toneSystemID = toneSystemID
        self.artist = artist
        self.patch = patch; self.notes = notes
        self.drumSteps = drumSteps; self.drumAccents = drumAccents
    }

    // MARK: - Defensive decoding (forward/backward-compatible)

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id, name, savedAt, styleRaw, keyRoot, scaleRaw, bpm, modeRaw
        case fxCharacterRaw, loopBars, a4Hz, toneSystemID, artist, patch, notes
        case drumSteps, drumAccents
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
        // ⭐ NO `??` HERE, and it is the only field in this decoder without one. The absence
        // of a fallback IS the fallback: a take written before #493 genuinely does not state
        // a tone system, and `nil` is the only honest reading of that. Giving it `?? "edo12"`
        // would turn "unknown" into an assertion, and the open path would then act on it —
        // silently pulling a player who has chosen Gamelan back to 12-TET on a value that
        // take never carried. (`decodeIfPresent` on an `Optional` property is exactly right:
        // key missing → nil, key present → the stored id.)
        toneSystemID   = try c.decodeIfPresent(String.self,   forKey: .toneSystemID)
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
        let wrappedNotes = try c.decodeIfPresent([LossyDecoded<Note>].self, forKey: .notes) ?? []
        notes = wrappedNotes.compactMap(\.value)
        // TELEMETRY — do not remove, and it is not optional politeness. `LossyDecoded`'s own
        // file states the law: dropping elements is still PERMANENT loss (the next
        // `ProjectStore.persist()` re-encodes only the survivors and the bad bytes are gone),
        // just bounded loss — so without this line the partly-corrupt case becomes the one
        // SILENT failure, which is worse than the all-or-nothing behaviour it replaced,
        // because that at least threw. `AutomationState` already does exactly this for its
        // keyed lossy array; `Project` shipped without it for one commit. Logged once per
        // decode, never per note. `name` is decoded above, so the line can say WHICH take.
        let droppedNotes = wrappedNotes.count - notes.count
        if droppedNotes > 0 {
            log.log(.error, category: .system,
                    "Project '\(name)' — dropped \(droppedNotes)/\(wrappedNotes.count) "
                    + "undecodable note(s); they are gone at the next save")
        }
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
        // `encodeIfPresent`, so a take that states no tone system writes NO key rather than
        // `null` — and re-reading it yields `nil` again instead of a JSON null that a
        // stricter future decoder would have to special-case. Round-trip-stable in both
        // directions, which `TheToneSystemTravelsWithTheTakeTests` asserts.
        try c.encodeIfPresent(toneSystemID, forKey: .toneSystemID)
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
