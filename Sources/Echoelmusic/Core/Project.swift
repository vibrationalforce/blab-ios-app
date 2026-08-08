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

    /// Who the instrument was set to at save time (`SessionContext.artistName`, raw — NOT the
    /// filename-safe token `SessionNaming.sanitize` makes). Read it through
    /// `attribution(besideOwnName:)`, which is where the decision about SHOWING it lives.
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

    /// #217 — THE COMPOSER'S OWN BARS, before the mixer was baked into their velocities.
    ///
    /// WHAT IT FIXES, and it is a lying control, not a missing nicety. `EchoelStudioView`
    /// keeps the raw bars in `@State lastRawTake` so a Mix fader can RE-BAKE the take that
    /// already exists at the new level (#174) instead of composing a different one. `@State`
    /// is per app session and `open(_:)` restored an already-glued take via
    /// `pianoRoll.load(p.notes)`, so on every OPENED project that state was `nil` — and
    /// `rebalanceTake()`'s documented fallback is `recomposeIfRunning()`. Moving the bass
    /// fader on a saved take therefore handed the listener a NEW piece. Its own comment says
    /// so, and names persisting these bars as the answer.
    ///
    /// ⭐ THE GENRE TRAVELS WITH THE BARS, IN ONE VALUE, and that pairing is the whole reason
    /// this is a nested struct rather than two optional fields next to each other.
    /// `rebalanceTake()` re-glues with `take.genre`, **not** the picker's current `style` —
    /// the take must be re-glued in the genre it was COMPOSED in, even if the user has since
    /// picked another one. Two independent optionals make "bars without their genre"
    /// representable, and the only thing a reader could do with that state is the exact bug
    /// the pairing exists to prevent.
    ///
    /// ⭐ OPTIONAL, for the `toneSystemID` reason one field up: a take written before this
    /// build genuinely states no raw bars, and `nil` is the only honest reading. There is no
    /// `??` that could stand in — deriving them from `notes` is impossible (those velocities
    /// already carry a mixer level, and `notes` is the ONE sounding bar, not the arrangement).
    ///
    /// ⚠️ IT IS NOT FREE. `notes` holds one bar; this holds `loopBars` of them (default
    /// eight), so a saved take's JSON grows by roughly the note payload times the loop length.
    /// Accepted because the alternative is a control that lies, and because nothing reads
    /// these bars on the hot path — only a fader move and `open(_:)`.
    public var rawTake: RawTake?

    /// The composer's bars plus the genre they were composed in — see `rawTake`.
    public struct RawTake: Codable, Sendable, Equatable {

        /// `MusicStyle.rawValue` at COMPOSE time.
        public var styleRaw: String

        /// One entry per loop bar, in order, exactly as `BioComposer` produced them —
        /// BEFORE `mixGlued` folded the mixer into the velocities.
        public var bars: [[Note]]

        public init(styleRaw: String, bars: [[Note]]) {
            self.styleRaw = styleRaw
            self.bars = bars
        }

        /// ⚠️ DELIBERATELY OPTIONAL AND WITHOUT THE `?? .dubTechno` FALLBACK that
        /// `Project.style` carries, and the asymmetry is the point. There, an unknown genre
        /// still has to show SOMETHING in a picker. Here, an unknown genre would mean
        /// re-gluing a take in the wrong genre — the precise defect `rebalanceTake()`'s
        /// "`take.genre`, NOT `style`" comment exists to prevent. `nil` says "this build
        /// cannot re-bake these bars", and the caller then leaves the take alone.
        public var style: MusicStyle? { MusicStyle(rawValue: styleRaw) }

        private enum CodingKeys: String, CodingKey { case styleRaw, bars }

        /// ELEMENT-TOLERANT per note, for the reason spelled out at `Project.notes`: an
        /// unknown `NoteRole` raw value throws `dataCorrupted`, which `decodeIfPresent`
        /// cannot absorb. Without this, one note written by a future build would take the
        /// whole arrangement with it. Bars keep their POSITIONS (the outer array is the
        /// loop order); holes inside a bar are dropped, because a note's `startTick` carries
        /// its own position.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            styleRaw = try c.decodeIfPresent(String.self, forKey: .styleRaw) ?? ""
            let wrapped = try c.decodeIfPresent([[LossyDecoded<Note>]].self, forKey: .bars) ?? []
            bars = wrapped.map { $0.compactMap(\.value) }
            let dropped = wrapped.reduce(0) { $0 + $1.count } - bars.reduce(0) { $0 + $1.count }
            if dropped > 0 {
                log.log(.error, category: .system,
                        "Project raw take — dropped \(dropped) undecodable note(s) from the "
                        + "composer bars; the fader will re-bake without them")
            }
        }
    }

    public init(
        id: UUID = UUID(), name: String, savedAt: Date = Date(),
        styleRaw: String, keyRoot: Int, scaleRaw: String, bpm: Double,
        modeRaw: String, fxCharacterRaw: String, loopBars: Int,
        a4Hz: Double, toneSystemID: String?, artist: String,
        patch: SynthPatch, notes: [Note], rawTake: RawTake?,
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
        // as "wired" while every save wrote nothing. Counted over the WHOLE repo (#495) with
        // `git grep -n "[^A-Za-z]Project(" -- Sources Tests`, minus the `func`/`importProject`/
        // `currentProject`/`SharedEchoelProject` false friends and minus this file's own prose:
        // THIRTEEN construction sites as of #521 — `EchoelStudioView.currentProject()`, ten in
        // `Tests/CISmoke` (`AutosaveSlotTests`, `AFailedSaveLeavesATraceTests`,
        // `TheToneSystemTravelsWithTheTakeTests`, `TheModeTravelsWithTheTakeTests`,
        // `TheRawTakeTravelsWithTheTakeTests`, `TheSavePromiseMatchesTheSaveTests`,
        // `TheShareDoorDoesNotFabricateAnEmptyDocumentTests`,
        // `TheImportDoorReportsWhatItCannotReadTests`, `TheTakeSaysWhoMadeItTests`), and
        // `ColabPayloadTests` plus TWO in `ProjectStoreTests`.
        //
        // ⛔ AND THE COUNT WAS WRONG A THIRD TIME — it stood at EIGHT while the tree held
        // TWELVE, because #217/#514/#519/#520 each added one without carrying it. Nothing broke
        // this time (no required parameter was added since), so this is the CHEAP miss, and it
        // is worth more than the expensive one below precisely because it drifted silently:
        // four separate slices read this list, none re-ran the grep, and the list is the thing
        // the next slice consults before adding a parameter without a default. The command is
        // written out above so the next reader RUNS it instead of trusting the names.
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
        // ⚠️ `rawTake` (#217) FOLLOWS THE SAME RULE for the same reason and was added with the
        // count re-run over the whole repo first — it is still EIGHT, listed above. Every call
        // site that does not model a composed session passes `rawTake: nil`, written out, so
        // "this fixture states no raw bars" is a visible decision rather than a default nobody
        // read.
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
        self.patch = patch; self.notes = notes; self.rawTake = rawTake
        self.drumSteps = drumSteps; self.drumAccents = drumAccents
    }

    // MARK: - Defensive decoding (forward/backward-compatible)

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id, name, savedAt, styleRaw, keyRoot, scaleRaw, bpm, modeRaw
        case fxCharacterRaw, loopBars, a4Hz, toneSystemID, artist, patch, notes
        case rawTake
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
        // #217 — TWO LAYERS OF DEFENCE, each doing a DIFFERENT job, and the outer one is the
        // reason this field cannot re-open the hole the rest of this decoder closes.
        //
        // INNER (`RawTake.init(from:)`, per note): one note a future build wrote with an
        // unknown `NoteRole` becomes one missing note, not a lost arrangement.
        //
        // OUTER (`try?` here): a STRUCTURALLY broken raw take — `bars` not an array of
        // arrays, a truncated write — would otherwise throw out of `Project.init(from:)`,
        // and `ProjectStore`'s `try?` turns that into the user's ENTIRE take vanishing. That
        // is the exact bug `LossyDecoded` exists for, and adding an un-hardened field to a
        // hardened struct is how it comes back. `nil` here costs nothing that was reachable:
        // an unreadable raw take cannot be re-baked from anyway, and every other field —
        // including `notes`, the take you actually hear — survives.
        //
        // `contains` separates the two cases so the log line means something: ABSENT is the
        // ordinary legacy read (every take written before #217) and must stay silent, while
        // PRESENT-BUT-UNREADABLE is real bounded loss and gets the same telemetry the notes
        // array above gets, for the same reason — silence would make it the one invisible
        // failure.
        if c.contains(.rawTake) {
            rawTake = (try? c.decodeIfPresent(RawTake.self, forKey: .rawTake)) ?? nil
            if rawTake == nil {
                log.log(.error, category: .system,
                        "Project '\(name)' — raw composer bars present but undecodable; a mix "
                        + "fader will fall back to composing instead of re-baking")
            }
        } else {
            rawTake = nil
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
        // `encodeIfPresent` for the `toneSystemID` reason: a take that states no raw bars
        // writes NO key, so re-reading it yields `nil` again rather than a JSON null.
        try c.encodeIfPresent(rawTake, forKey: .rawTake)
        try c.encode(drumSteps, forKey: .drumSteps)
        try c.encode(drumAccents, forKey: .drumAccents)
    }

    // MARK: - Sharing (the ONE shared-document format)

    /// Encode this take as the portable `.echoel.json` document a user shares — AirDrop,
    /// Files, Messages, iCloud Drive, a collaborator's phone.
    ///
    /// ⛔ WHY THIS EXISTS AS ONE DEFINITION (#519, and it is the #416 shape at its quietest).
    /// "Encode a Project for sharing" was decided TWICE, in two places, with two different
    /// answers, and the two disagreed on BOTH halves of the decision:
    ///   · **Format.** `ProjectStore.exportData` set `.prettyPrinted` + `.sortedKeys` and its
    ///     doc called the result "human-diffable". `SharedEchoelProject` — the `ShareLink`
    ///     wrapper, which is the path a user actually reaches — used a bare `JSONEncoder()`,
    ///     so the shipped export was minified with unstable key order. The promise was made in
    ///     the method nobody calls and broken in the one everybody does.
    ///   · **Failure.** `exportData` returned `nil`. The `ShareLink` wrapper returned
    ///     `?? Data()`.
    ///
    /// ⭐ AND THAT `?? Data()` IS WORSE THAN SILENCE — it is the whole reason this is a slice
    /// and not a tidy-up. A `DataRepresentation` closure that RETURNS empty bytes has not
    /// failed; the share sheet completes, the file carries the take's real name
    /// (`<name>.echoel.json`), and the user believes the session is on its way. The failure
    /// surfaces on SOMEONE ELSE'S device, days later, as `importProject` returning `nil` —
    /// "not a valid Echoel session". A fabricated artefact that looks like success is the one
    /// outcome worse than a button that visibly does nothing (#518).
    ///
    /// ⭐ AND IT IS REACHABLE, not theoretical. `ProjectStore.save` does not validate
    /// encodability: it inserts into `projects` and calls `persist()`. A take carrying a
    /// non-finite value therefore stays in the in-memory library (its disk write fails and is
    /// logged since #514), its row renders like any other, and its share button is the thing
    /// that then produces the empty file. `JSONEncoder`'s default
    /// `nonConformingFloatEncodingStrategy` is `.throw`, and this type carries `bpm`, `a4Hz`,
    /// a whole `SynthPatch`, every `Note` and (since #217) a whole `RawTake`.
    ///
    /// ⚠️ IT THROWS RATHER THAN RETURNING `Data?`, for the #514/#518 reason: `EncodingError`
    /// names the FIELD through `codingPath`. "The disk is full" and "a NaN got into your
    /// piece" are different problems with different fixes, and `try?` folds both onto `nil`.
    ///
    /// ⛔ WHAT THIS IS DELIBERATELY **NOT** THE DEFINITION OF — do not fold these in later:
    ///   · **The on-disk library.** `AppGroupStore.save` encodes the whole `[Project]` array
    ///     for the App Group container. Pretty-printing that would inflate a file nobody
    ///     diffs, on every autosave.
    ///   · **The colab wire payload.** `ColabPayload` carries a `Project` over Multipeer.
    ///     #512 pinned its `nonConformingFloatEncodingStrategy`, and pretty-printing bytes on
    ///     an `.unreliable` transport spends bandwidth on whitespace nobody reads.
    /// The decision this owns is narrow on purpose: **a Project as a shared DOCUMENT.**
    ///
    /// `.sortedKeys` is what makes the output deterministic — two exports of the same take are
    /// byte-identical, which is what "diffable" actually requires.
    public func sharedDocumentData() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }

    // MARK: - Decoded accessors (raw → enum, with safe fallbacks)

    public var style: MusicStyle { MusicStyle(rawValue: styleRaw) ?? .dubTechno }
    public var scale: Scale { Scale(rawValue: scaleRaw) ?? .minor }
    public var key: MusicalKey { MusicalKey(root: keyRoot, scale: scale) }
    public var mode: ComposerMode { ComposerMode(rawValue: modeRaw) ?? .studioLocked }

    /// The artist stamp to SHOW for this take beside a reader whose own name is `readerName`,
    /// or `nil` when there is nothing worth showing.
    ///
    /// ⭐ #521 — `artist` has been stamped, encoded and decoded since this format existed and has
    /// ZERO readers. Measured, not assumed: nothing anywhere reads `p.artist` back — the field
    /// reaches the coder pair, `currentProject()` writes it, and there the trail ends. That is
    /// exactly #494's `modeRaw` shape, and it is the shape no persistence test can see: a field
    /// that round-trips perfectly and is never read is invisible to every round-trip assertion.
    ///
    /// ⛔ THE RECIPE THAT STOOD HERE WAS AN ENUMERATION, AND ENUMERATIONS ARE WHAT A LATER
    /// SESSION GREPS (#461). It claimed `git grep -n "\.artist" -- Sources` "finds the init, the
    /// coder pair, `SessionContext`'s own storage and the ONE write site". Run today it returns
    /// TEN hits, and the tenth — `WorkspaceView.swift`'s `session.artistName` read, which the
    /// pattern matches through `.artistName` — is in none of those four categories. The
    /// CONCLUSION survives (nothing reads `p.artist`); the list did not, and a reader who
    /// re-runs the recipe and counts ten reads the mismatch as a contradiction.
    ///
    /// ⛔ AND THE MOTIVATING SENTENCE WAS FALSE — it said "#520 made Import a door that REPORTS,
    /// **so** takes really do arrive from other people now". Measured against the parent tree:
    /// the pre-#520 call site was already `projects.importProject(from: url)`, and that path
    /// ends in `save(p)`. **A successful import landed in the library long before #520**; what
    /// #520 changed is the FAILURE path. Arrival is not new, reporting is. The honest form is
    /// the weaker one, and it is enough: however a take arrives, it renders exactly like one you
    /// made.
    ///
    /// ⚠️⚠️ THE HONEST REACH, AND IT IS THE FIRST THING TO READ: **no take any Echoel build can
    /// produce today shows a credit.** `SessionContext.artistName` has NO production writer —
    /// its only assignments are the two in `init`, and Swift does not run `didSet` from an
    /// initialiser, so the one line that would persist it never fires. Every device therefore
    /// reports `E~`, every take is stamped `E~`, and a take received from another person's
    /// Echoel carries `E~` too (`importProject` replaces only the `id`). The difference-gate
    /// below then correctly returns `nil`. Only a hand-edited document can make the row appear.
    /// **This is a mechanism with no producer, in the #506 shape** — written now because the
    /// decision is the same whether or not the door exists, and a door arriving later must not
    /// land on a silent contradiction. The door is registered as #522: a name field beside the
    /// existing manual place field in "Save & Export", which is the other half of the very same
    /// `SessionNaming.stem(artist:date:key:bpm:a4Hz:place:)` and is missing for the same reason.
    ///
    /// ⚠️ SHOWING IT ONLY WHEN IT DIFFERS IS A NOISE DECISION, NOT A TRUTH DECISION, and the two
    /// must not be confused. Every take THIS BUILD WRITES carries a stamp, and on an untouched
    /// install every one of them says `E~`, because `SessionContext.init` migrates `.none`, `""`
    /// and `"Echoel"` to that brand mark. (Not "every take" flat — a file written before the
    /// field existed carries none at all, which is the paragraph four below, and a slice must
    /// not contain both a claim and its refutation (#425).) An unconditional line would add one
    /// identical row of chrome to every library entry, teach the reader to skip it, and then say
    /// nothing on the day it carries information.
    ///
    /// ⚠️ EXACT COMPARE AFTER TRIMMING, WHICH ERRS TOWARD SHOWING — the direction is chosen, not
    /// inherited. Showing a credit that happens to be yours is noise; hiding one that is not is a
    /// silent claim of authorship. So `"E~"` and `"e~"` are two artists here, deliberately, and a
    /// later "tidy-up" to `caseInsensitiveCompare` trades a truth property for a cosmetic one.
    ///
    /// ⚠️ EMPTY MEANS ABSENT, NOT DEFAULT (#493/#494). A file written before this field existed
    /// decodes to `""` — the decoder's `?? ""` — and `""` states no artist at all. Substituting
    /// `E~` there would attribute a stranger's take to THIS device's brand mark, which is the
    /// fabricated-detail defect (#424/#426/#433/#461) pointed at a person.
    ///
    /// ⚠️ AND THE CONSEQUENCE THE DOOR WILL BRING, stated now so it is not discovered as a bug:
    /// once #522 lets you rename yourself, your own older takes begin showing your OLD name.
    /// That is what the stamp records — provenance, not identity — and it is precisely why the
    /// row must read as a neutral fact ("by <name>") and never as a claim of foreignness
    /// ("imported from …"): the same line has to stay true when the other artist is a former
    /// self. (Written in the future tense on purpose: today nothing can rename you, so this is
    /// a property of the design and not yet of the app.)
    public func attribution(besideOwnName readerName: String) -> String? {
        let stamped = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stamped.isEmpty else { return nil }
        guard stamped != readerName.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return stamped
    }

    /// #217 — the bars a Mix fader can RE-BAKE this take from, paired with the genre to
    /// re-glue them in, or `nil` when this take cannot be re-baked at all.
    ///
    /// ⭐ IT LIVES HERE, AND NOT AS THREE `guard`s AT THE OPEN SITE, for two reasons that are
    /// worth more than the tidiness. (1) The restore then becomes ONE TOTAL ASSIGNMENT —
    /// `lastRawTake = p.rebakeSource` — so "opening a take must not leave the PREVIOUS
    /// session's bars in place" holds by construction instead of resting on an `else` branch
    /// somebody later reads as noise. That branch is the defect this slice would otherwise
    /// have introduced: the first fader move would re-bake the wrong piece over the take just
    /// opened. (2) The three-way decision is then real, drivable behaviour on a `public`
    /// Foundation-only value type, rather than a source scan over a `private` member of a view
    /// no test bundle can instantiate.
    ///
    /// The three exclusions, each for its own reason and none of them interchangeable:
    /// · **no raw take** — every file written before #217, and every session that saved before
    ///   its first `generate()`. Honest `nil`, and the caller keeps its old fallback.
    /// · **unknown genre** — a take from a build that knows a `MusicStyle` this one does not.
    ///   Re-gluing it in some *other* genre is precisely the defect `rebalanceTake()`'s
    ///   "`take.genre`, NOT `style`" comment exists to prevent, so "cannot re-bake" is the
    ///   only honest answer. Note NO clamp to `MusicStyle.offered`: that clamp exists so the
    ///   picker shows something, while these bars must be re-glued in the genre they were
    ///   COMPOSED in, offered or not.
    /// · **empty bars** — nothing to re-bake; `rebalanceTake()` checks this anyway, and having
    ///   both ends agree costs one condition.
    public var rebakeSource: (genre: MusicStyle, bars: [[Note]])? {
        guard let raw = rawTake, let genre = raw.style, !raw.bars.isEmpty else { return nil }
        return (genre: genre, bars: raw.bars)
    }
    public var fxCharacter: FXCharacter { FXCharacter(rawValue: fxCharacterRaw) ?? .auto }
}
