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
}
