// ProjectStoreTests.swift
// Echoel — the saved-projects library: Codable round-trip + save/open/delete.

import XCTest
@testable import Echoelmusic

final class ProjectCodableTests: XCTestCase {

    private func sample(_ name: String = "Take 1") -> Project {
        Project(
            name: name,
            styleRaw: MusicStyle.dubTechno.rawValue, keyRoot: 0, scaleRaw: Scale.minor.rawValue,
            bpm: 124, modeRaw: ComposerMode.studioLocked.rawValue,
            fxCharacterRaw: FXCharacter.underwater.rawValue, loopBars: 4,
            // #493 added `toneSystemID` with NO initialiser default on purpose (#440/#443).
            // ⛔ AND THIS FILE IS WHY THAT DECISION NEEDS A SECOND HALF: #493 shipped without
            // updating either of this file's two call sites, so `Tests/EchoelmusicTests` stopped
            // compiling and NOTHING went red — neither real gate builds this directory (#208),
            // and the non-blocking suite reports success regardless. The compiler error the
            // no-default buys is only worth something in a directory a gate actually compiles.
            a4Hz: 440, toneSystemID: "edo12", moodFields: nil, artist: "Echoel",
            patch: SynthPatch(name: "Default"),
            notes: [Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: 0.8)],
            rawTake: nil,
            drumSteps: [[true, false], [false, true]],
            drumAccents: [[false, false], [true, false]]
        )
    }

    func testRoundTripsThroughJSON() throws {
        let p = sample()
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(p, back)
    }

    func testDecodedAccessorsResolveEnums() {
        let p = sample()
        XCTAssertEqual(p.style, .dubTechno)
        XCTAssertEqual(p.scale, .minor)
        XCTAssertEqual(p.mode, .studioLocked)
        XCTAssertEqual(p.fxCharacter, .underwater)
        XCTAssertEqual(p.key.shortName, "Cm")
    }

    func testUnknownRawFallsBackSafely() {
        var p = sample()
        p.styleRaw = "garage"; p.fxCharacterRaw = "spaceecho"
        XCTAssertEqual(p.style, .dubTechno, "unknown style → safe default")
        XCTAssertEqual(p.fxCharacter, .auto, "unknown character → auto")
    }

    /// Forward-compat guard (Persistence-Steward): a project SAVED BY A NEWER BUILD
    /// carries fields this build doesn't know yet. Opening it must NOT throw — a
    /// TestFlight user on an older build (or an older reinstall reading the App
    /// Group's persisted projects) must never lose a newer-saved project. Synthesized
    /// Codable ignores unknown keys today; this locks that so a future custom decoder
    /// can't silently regress it into data loss.
    func testForwardCompat_unknownFutureKeysAreIgnored() throws {
        let p = sample("Cross-Build")
        let encoded = try JSONEncoder().encode(p)
        var obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        obj["swingFromAFutureBuild"] = 0.42          // a scalar a future schema might add
        obj["futureNestedThing"] = ["enabled": true] // …or a nested object
        let data = try JSONSerialization.data(withJSONObject: obj)
        let back = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(back, p, "unknown future keys ignored; every known field survives intact")
    }

    // MARK: - Backward-compat: MISSING fields must not vaporize the take

    func testMissingFields_loadWithDefaults_neverThrow() throws {
        // An older save (or one field lost) must still LOAD with defaults — not throw
        // keyNotFound and lose the user's whole take. This is why Project needs the
        // defensive decoder the other stored structs already have.
        let full = try JSONEncoder().encode(sample("Rescue"))
        var dict = try XCTUnwrap(try JSONSerialization.jsonObject(with: full) as? [String: Any])
        for key in ["a4Hz", "artist", "drumAccents", "loopBars", "bpm"] { dict.removeValue(forKey: key) }
        let trimmed = try JSONSerialization.data(withJSONObject: dict)
        let p = try JSONDecoder().decode(Project.self, from: trimmed)   // must NOT throw
        XCTAssertEqual(p.a4Hz, 440);        XCTAssertEqual(p.artist, "")
        XCTAssertEqual(p.drumAccents, []);  XCTAssertEqual(p.loopBars, 1)
        XCTAssertEqual(p.bpm, 120)
        // Fields that ARE present still survive intact.
        XCTAssertEqual(p.name, "Rescue")
        XCTAssertEqual(p.styleRaw, MusicStyle.dubTechno.rawValue)
    }

    func testMissingPatch_getsSafeDefault_neverThrow() throws {
        let full = try JSONEncoder().encode(sample())
        var dict = try XCTUnwrap(try JSONSerialization.jsonObject(with: full) as? [String: Any])
        dict.removeValue(forKey: "patch")
        let trimmed = try JSONSerialization.data(withJSONObject: dict)
        let p = try JSONDecoder().decode(Project.self, from: trimmed)   // must NOT throw
        XCTAssertEqual(p.patch.name, "Default")
    }

    // MARK: - Schema version (#189 slice 1)

    /// A file written before the stamp existed must decode as `0`, NOT as the current
    /// version. That distinction is the entire value of the field: a migration can only
    /// branch on it if pre-stamp files are distinguishable from current ones, and a
    /// `?? currentSchemaVersion` default would make every legacy take claim to be current.
    func testPreVersioningFile_decodesAsSchemaVersionZero() throws {
        let full = try JSONEncoder().encode(sample("Legacy"))
        var dict = try XCTUnwrap(try JSONSerialization.jsonObject(with: full) as? [String: Any])
        dict.removeValue(forKey: "schemaVersion")           // as every take saved before today
        let p = try JSONDecoder().decode(
            Project.self, from: try JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(p.schemaVersion, 0, "an unstamped file is pre-versioning, not current")
        XCTAssertEqual(p.name, "Legacy", "and it still loads completely")
    }

    /// THE TRAP THE EXPLICIT ENCODER EXISTS FOR. Re-saving a legacy take produces a file
    /// in TODAY's shape, so it must be stamped with today's version — the synthesized
    /// encoder would have written the loaded `0` straight back and left a current file
    /// permanently claiming to be pre-versioning, which a migration would then re-run on.
    func testResavingALegacyTake_stampsTheCurrentVersion() throws {
        let full = try JSONEncoder().encode(sample("Legacy"))
        var dict = try XCTUnwrap(try JSONSerialization.jsonObject(with: full) as? [String: Any])
        dict.removeValue(forKey: "schemaVersion")
        let legacy = try JSONDecoder().decode(
            Project.self, from: try JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(legacy.schemaVersion, 0)             // in memory: where it came from

        let resaved = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(legacy)) as? [String: Any])
        XCTAssertEqual(resaved["schemaVersion"] as? Int, Project.currentSchemaVersion,
                       "the bytes just written are in the current shape and must say so")
    }

    /// The explicit encoder replaced a synthesized one, so a field dropped from it would
    /// vanish from every save with nothing to catch it. Pin the key set.
    /// ⛔ #1010 — THIS LITERAL WAS MISSING `toneSystemID` AND HAD BEEN RED SINCE #493. That
    /// commit gave `sample()` a real tone system (`"edo12"`), so `encodeIfPresent` started
    /// writing a seventeenth key while the expected set still named sixteen. Invisible,
    /// because `full-tests.yml` carries `continue-on-error` on its build step.
    ///
    /// ⭐ AND THE LITERAL STAYS A LITERAL, WHICH IS THE OPPOSITE OF #1009's REPAIR — on
    /// purpose. There the test copied a list the source already owned, so deriving it removed
    /// a duplicate. Here there is nothing to derive from: `CodingKeys` is `private` and not
    /// `CaseIterable`, and deriving the expectation from `encode(to:)` would assert the
    /// encoder against itself. This claim IS the hand-written second opinion the encoder's own
    /// doc comment asks for ("a new stored property must be added HERE as well"). Its job is
    /// to go red when a field appears — so it must be written out by hand.
    ///
    /// ⚠️ WHAT DID CHANGE IS THE FIXTURE, and that is the real strengthening. The old check
    /// ran on a sample whose `moodFields` and `rawTake` were `nil`, so `encodeIfPresent` wrote
    /// no key and their absence from the expected set was silently "correct" — a new OPTIONAL
    /// field could have been forgotten in `encode(to:)` and this test would still have passed.
    /// `fullyPopulated()` sets every optional, so the key set is the COMPLETE field list and
    /// any omission is reachable. The second assertion pins that property of the fixture, so
    /// nobody can weaken the check by quietly nil-ing one back out.
    func testExplicitEncoder_writesEveryField() throws {
        let project = fullyPopulated()
        XCTAssertNotNil(project.toneSystemID)
        XCTAssertNotNil(project.moodFields)
        XCTAssertNotNil(project.rawTake, """
        the fixture no longer populates every optional, so `encodeIfPresent` writes no key for \
        the nil ones and this test can no longer see a field missing from `encode(to:)`.
        """)

        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(project)) as? [String: Any])
        let expected: Set<String> = [
            "schemaVersion", "id", "name", "savedAt", "styleRaw", "keyRoot", "scaleRaw",
            "bpm", "modeRaw", "fxCharacterRaw", "loopBars", "a4Hz", "toneSystemID",
            "moodFields", "artist", "patch", "notes", "rawTake", "drumSteps", "drumAccents"
        ]
        XCTAssertEqual(Set(obj.keys), expected, """
        a stored property missing from `encode(to:)` is silent data loss.

        written but not expected: \(Set(obj.keys).subtracting(expected).sorted())
        expected but not written: \(expected.subtracting(obj.keys).sorted())

        If a field was ADDED, add it to `CodingKeys`, to `encode(to:)`, to the decoder AND \
        to the set above — in that order, in one commit.
        """)
    }

    /// The `sample()` fixture with every optional filled in. Separate from `sample()` because
    /// the other cases want a plain take; only the completeness check needs all three.
    private func fullyPopulated() -> Project {
        var project = sample("Fully populated")
        project.moodFields = ["warmth": 0.5]
        project.rawTake = Project.RawTake(styleRaw: MusicStyle.dubTechno.rawValue,
                                          bars: [[Note(pitch: 60, startStep: 0)]])
        return project
    }

    // MARK: - Element-tolerant notes (#189 slice 1)

    /// ONE bad note must cost ONE note, not the whole take. `decodeIfPresent([Note].self)`
    /// absorbed a MISSING `notes` key but not a malformed ELEMENT inside a present one —
    /// that throw left `Project.init(from:)` and `ProjectStore`'s `try?` turned it into
    /// nothing at all.
    func testOneMalformedNote_costsOneNote_notTheWholeTake() throws {
        var p = sample("Partly corrupt")
        p.notes = [Note(pitch: 60, startStep: 0), Note(pitch: 64, startStep: 4),
                   Note(pitch: 67, startStep: 8)]
        var dict = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(p)) as? [String: Any])
        var notes = try XCTUnwrap(dict["notes"] as? [[String: Any]])
        notes[1] = ["pitch": "not a number"]                // wrong TYPE, which no default absorbs
        dict["notes"] = notes

        let back = try JSONDecoder().decode(
            Project.self, from: try JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(back.notes.count, 2, "the two readable notes survive")
        XCTAssertEqual(back.notes.map(\.pitch), [60, 67])
        XCTAssertEqual(back.name, "Partly corrupt", "and the take itself is not lost")
    }

    /// The concrete way this fires in the field, and the reason it is not paranoia:
    /// `NoteRole` is a `String`-raw enum, and the synthesized `RawRepresentable` decode
    /// THROWS on a raw value it does not know — `decodeIfPresent` only absorbs a missing
    /// key. So the day a build adds a fourth role, every take it saves would have been
    /// unreadable, whole-file, by every earlier build.
    func testUnknownFutureNoteRole_dropsThatNote_notTheTake() throws {
        var p = sample("From a newer build")
        p.notes = [Note(pitch: 60, startStep: 0), Note(pitch: 72, startStep: 4)]
        var dict = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(p)) as? [String: Any])
        var notes = try XCTUnwrap(dict["notes"] as? [[String: Any]])
        notes[0]["role"] = "percussion"                     // a role this build has never heard of
        dict["notes"] = notes

        let back = try JSONDecoder().decode(
            Project.self, from: try JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(back.notes.map(\.pitch), [72],
                       "only the note carrying the unknown role is lost")
        XCTAssertEqual(back.name, "From a newer build")
    }

    func testNearlyEmptyObject_stillDecodesToAValidTake() throws {
        // The extreme: almost nothing present. A valid Project, never a thrown error.
        let p = try JSONDecoder().decode(Project.self, from: Data("{\"name\":\"Salvaged\"}".utf8))
        XCTAssertEqual(p.name, "Salvaged")
        XCTAssertEqual(p.bpm, 120)
        XCTAssertTrue(p.notes.isEmpty)
        XCTAssertEqual(p.style, .dubTechno, "empty styleRaw resolves to the safe default")
    }
}

@MainActor
final class ProjectStoreTests: XCTestCase {

    private func freshStore() -> ProjectStore {
        let suite = "ProjectStoreTests-\(UUID().uuidString)"
        // AppGroupStore writes to the App Group container; in the test sandbox it
        // falls back gracefully. We still verify the in-memory list behaviour.
        return ProjectStore(store: AppGroupStore(subdirectory: suite))
    }

    private func project(_ name: String) -> Project {
        Project(
            name: name, styleRaw: "trap", keyRoot: 2, scaleRaw: "dorian", bpm: 140,
            modeRaw: "studioLocked", fxCharacterRaw: "auto", loopBars: 8, a4Hz: 440,
            toneSystemID: "edo12", moodFields: nil, artist: "E",
            patch: SynthPatch(name: "Default"), notes: [], rawTake: nil,
            drumSteps: [], drumAccents: []
        )
    }

    func testSaveInsertsNewestFirst() {
        let store = freshStore()
        let a = store.save(project("A"))
        let b = store.save(project("B"))
        XCTAssertEqual(store.projects.first?.id, b.id, "newest first")
        XCTAssertEqual(store.projects.count, 2)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testSaveUpsertsByID() {
        let store = freshStore()
        var p = store.save(project("Draft"))
        p.name = "Final"
        store.save(p)
        XCTAssertEqual(store.projects.count, 1, "same id updates, not duplicates")
        XCTAssertEqual(store.projects.first?.name, "Final")
    }

    func testDeleteRemoves() {
        let store = freshStore()
        let a = store.save(project("A"))
        store.save(project("B"))
        store.delete(id: a.id)
        XCTAssertNil(store.project(id: a.id))
        XCTAssertEqual(store.projects.count, 1)
    }

    // MARK: - Sharing (cross-device / community)

    func testExportImportRoundTripPreservesContent() {
        let store = freshStore()
        let original = project("Shared Take")
        guard let data = store.exportData(original) else {
            return XCTFail("export produced no data")
        }
        let imported = store.importProject(from: data)
        XCTAssertNotNil(imported)
        // Content travels intact…
        XCTAssertEqual(imported?.name, original.name)
        XCTAssertEqual(imported?.bpm, original.bpm)
        XCTAssertEqual(imported?.styleRaw, original.styleRaw)
        XCTAssertEqual(imported?.keyRoot, original.keyRoot)
        // …but the import gets a FRESH id so it never overwrites the source.
        XCTAssertNotEqual(imported?.id, original.id)
        XCTAssertEqual(store.projects.count, 1, "imported project lands in the library")
    }

    func testImportInvalidDataReturnsNil() {
        let store = freshStore()
        XCTAssertNil(store.importProject(from: Data("not a session".utf8)))
        XCTAssertTrue(store.projects.isEmpty)
    }

    func testImportingSameExportTwiceMakesTwoDistinctProjects() {
        let store = freshStore()
        guard let data = store.exportData(project("Dup")) else {
            return XCTFail("export produced no data")
        }
        let first = store.importProject(from: data)
        let second = store.importProject(from: data)
        XCTAssertNotEqual(first?.id, second?.id, "each import is independent")
        XCTAssertEqual(store.projects.count, 2)
    }
}
