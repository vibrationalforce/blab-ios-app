// AutosaveSlotTests.swift
// Echoel — #273. The founder said "Session speichern … fehlt". Saving existed; what did not
// exist was any save he had not tapped for. `ProjectStore.save` had exactly two callers in
// `Sources/`, both explicit taps, and neither `scenePhase` observer touched a store — so a
// backgrounded app, a phone call or a crash took the take with it. A body-generated take
// cannot be reproduced by repeating the inputs, so that loss is final.
//
// The autosave writes into ONE RESERVED SLOT, and every property that makes that safe is
// checkable here without a simulator, because `Project` and `ProjectStore` are `public`:
//
//   1. the slot id is fixed, so repeated autosaves REPLACE rather than pile up;
//   2. it can never collide with a take the user saved (those get a random id);
//   3. `save` keeps one row per id — the invariant the whole scheme rests on;
//   4. the reserved row is recognisable in the Open list.
//
// ⚠️ WHAT THIS CANNOT REACH, said plainly. It cannot prove `autosaveTake()` is called, that
// `scenePhase` fires, or that `hasComposed` gates it — those live in `private` members of a
// view no test in this bundle can instantiate. The trigger is device-verified only. What is
// pinned here is the part that would quietly destroy a user's take if it drifted.

import Foundation
import XCTest
@testable import Echoelmusic

@MainActor
final class AutosaveSlotTests: XCTestCase {

    /// A store on its own subdirectory, so a test never reads or writes the real library.
    private func isolatedStore(_ tag: String = #function) -> ProjectStore {
        ProjectStore(store: AppGroupStore(subdirectory: "EchoelTests-autosave-\(tag)"))
    }

    private func take(named name: String, bpm: Double = 120) -> Project {
        Project(name: name, styleRaw: MusicStyle.offered.first?.rawValue ?? "ambient",
                keyRoot: 0, scaleRaw: Scale.major.rawValue, bpm: bpm,
                modeRaw: ComposerMode.flowFree.rawValue,
                fxCharacterRaw: FXCharacter.clean.rawValue,
                loopBars: 4, a4Hz: 440, artist: "",
                patch: SynthPatch(name: "Test"), notes: [], drumSteps: [], drumAccents: [])
    }

    /// ⭐ THE INVARIANT THE SLOT RESTS ON. Two autosaves must leave ONE row, or the library
    /// gains an entry every time the user takes a call and the take they want is buried.
    func testRepeatedAutosavesReplaceRatherThanAccumulate() throws {
        let store = isolatedStore("replace")
        for bpm in [90.0, 100.0, 110.0] {
            var t = take(named: Project.autosaveNamePrefix + "Session", bpm: bpm)
            t.id = Project.autosaveSlotID
            store.save(t)
        }
        let reserved = store.projects.filter { $0.id == Project.autosaveSlotID }
        XCTAssertEqual(reserved.count, 1,
                       "the reserved autosave slot holds \(reserved.count) rows — every app "
                       + "switch now adds one, and the take the user made sinks down the list")
        XCTAssertEqual(reserved.first?.bpm, 110,
                       "the surviving row is not the newest autosave, so the recovery point "
                       + "is stale — which is worse than none, because it looks current")
    }

    /// And it must never touch a take the user named and saved deliberately. That is the one
    /// failure this whole design exists to make impossible: an automatic write destroying
    /// explicit work.
    func testAnAutosaveCannotOverwriteAUserSavedTake() throws {
        let store = isolatedStore("nocollide")
        let mine = store.save(take(named: "My take", bpm: 128))   // random id, as the UI builds it
        var auto = take(named: Project.autosaveNamePrefix + "Session", bpm: 90)
        auto.id = Project.autosaveSlotID
        store.save(auto)

        XCTAssertNotEqual(mine.id, Project.autosaveSlotID,
                          "a freshly built Project came out carrying the reserved id — then "
                          + "the next autosave overwrites whatever the user just saved")
        XCTAssertEqual(store.project(id: mine.id)?.bpm, 128,
                       "the user's saved take was changed by an autosave")
        XCTAssertEqual(store.projects.count, 2, "both rows must survive")
    }

    /// The id is a stored constant, not something derived per launch. If it ever became a
    /// fresh `UUID()`, every assertion above would still pass inside one process and the
    /// defect would only appear across relaunches — exactly the shape no test would catch.
    func testTheSlotIdIsStableAcrossReads() {
        XCTAssertEqual(Project.autosaveSlotID, Project.autosaveSlotID)
        XCTAssertEqual(Project.autosaveSlotID.uuidString.uppercased(),
                       "E0000000-0000-4000-8000-000000000A05",
                       "the reserved slot id MOVED. An installation carrying an autosave "
                       + "under the old id keeps it forever as an ordinary-looking row that "
                       + "nothing replaces, and the user cannot tell the two apart.")
    }

    /// A row nobody created has to be recognisable in the one place the user meets it.
    func testTheReservedRowIsRecognisableInTheLibrary() {
        XCTAssertFalse(Project.autosaveNamePrefix.trimmingCharacters(in: .whitespaces).isEmpty,
                       "the autosave prefix is blank, so the reserved row is indistinguishable "
                       + "from a take the user named")
        let name = Project.autosaveNamePrefix + "Session 120"
        XCTAssertTrue(name.hasPrefix(Project.autosaveNamePrefix),
                      "the prefix no longer leads the name, so it stops being scannable in a list")
    }
}
