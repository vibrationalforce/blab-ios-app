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
            a4Hz: 440, artist: "Echoel",
            patch: SynthPatch(name: "Default"),
            notes: [Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: 0.8)],
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
            modeRaw: "studioLocked", fxCharacterRaw: "auto", loopBars: 8, a4Hz: 440, artist: "E",
            patch: SynthPatch(name: "Default"), notes: [], drumSteps: [], drumAccents: []
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
