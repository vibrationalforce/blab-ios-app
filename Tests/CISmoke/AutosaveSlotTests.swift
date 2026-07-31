// AutosaveSlotTests.swift
// Echoel — #273. The founder said "Session speichern … fehlt". Saving existed; what did not
// exist was any save he had not tapped for. Every `ProjectStore.save` caller in `Sources/` was
// an explicit user action and no `scenePhase` observer touched the PROJECT store — so a
// backgrounded app or a phone call took the take with it. A body-generated take cannot be
// reproduced by repeating the inputs, so that loss is final.
//
// ⛔ Two corrections to the first version of this header, kept rather than swapped: there are
// THREE save callers, not two (the Save alert, the peer receive, and `importProject`); and
// `EchoelmusicApp` HAS flushed the TIMELINE store from `.background` all along — only the
// project store was unserved. Nor does any of this survive a CRASH: a crash delivers no
// scene-phase transition, so nothing here runs.
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
    ///
    /// ⛔ THE UUID IS NOT DECORATION, and leaving it out is a trap this file walked into: the
    /// tag alone is stable across runs, and a simulator container is REUSED, so the second run
    /// of `testAnAutosaveCannotOverwriteAUserSavedTake` loads the two rows the first run wrote
    /// and its `count == 2` becomes 4. That failure would arrive on a commit that changed
    /// nothing — the worst kind, because the first thing suspected is the innocent change.
    private func isolatedStore(_ tag: String = #function) -> ProjectStore {
        ProjectStore(store: AppGroupStore(subdirectory:
            "EchoelTests-autosave-\(tag)-\(UUID().uuidString)"))
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
    ///
    /// ⛔ THE SECOND ASSERTION HERE USED TO BE VACUOUS, and it is worth naming because it read
    /// as a real check: it built `prefix + "Session 120"` and then asserted the result had the
    /// prefix. String concatenation guarantees that — it would have passed with the prefix
    /// removed from `autosaveTake()` entirely. The property it MEANT to check lives in the
    /// view, so it moved to the source scan below.
    func testTheReservedRowIsRecognisableInTheLibrary() {
        XCTAssertFalse(Project.autosaveNamePrefix.trimmingCharacters(in: .whitespaces).isEmpty,
                       "the autosave prefix is blank, so the reserved row is indistinguishable "
                       + "from a take the user named")
    }

    // MARK: - The trigger, which no assertion above can reach

    /// ⚠️ WHY A SOURCE SCAN. Everything above proves the SLOT behaves; none of it proves the
    /// autosave is ever CALLED. `autosaveTake()` and the `scenePhase` observer are `private`
    /// members of a view that cannot be instantiated in this bundle (no simulator, and
    /// `@testable` grants `internal`, not `private`). The realistic regression is textual —
    /// someone tidies the observer, or drops the emptiness guard as redundant — and a textual
    /// check catches exactly that. House pattern: `ChromeDynamicTypeTests`.
    ///
    /// It does NOT prove the observer fires, that the write lands, or that the recovered take
    /// sounds like the one that was lost. That is device-verified only.
    func testTheDepartureTriggerAndItsGuardAreStillWired() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/EchoelStudioView.swift")

        XCTAssertTrue(lines.contains { $0.contains("autosaveTake()") && $0.contains("old == .active") },
                      "the autosave is no longer called from a scene DEPARTURE. Either it is "
                      + "not called at all (#273 is silently undone and nothing else here goes "
                      + "red), or `old == .active` was dropped — and `.inactive` is also the "
                      + "first phase on the way BACK, so without it the write happens twice per "
                      + "round trip.")

        XCTAssertTrue(lines.contains { $0.contains("!pianoRoll.notes.isEmpty") },
                      "the emptiness guard is gone. `hasComposed` alone is set true "
                      + "unconditionally by `open()` and never set back, so an empty roll would "
                      + "overwrite the single reserved slot — destroying the one recovery point "
                      + "the user has, with no undo. This is the only line here whose loss "
                      + "DESTROYS data rather than failing to save it.")

        XCTAssertTrue(lines.contains { $0.contains("take.id = Project.autosaveSlotID") },
                      "the autosave no longer stamps the reserved id, so every departure adds a "
                      + "fresh row and the library fills with takes the user did not make")

        XCTAssertTrue(lines.contains { $0.contains("Project.autosaveNamePrefix +") },
                      "the autosave no longer prefixes its name, so the reserved row is "
                      + "indistinguishable from a take the user named and saved")
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…` → up two).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()              // Tests
            .deletingLastPathComponent()              // repo
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("source tree not present at \(sources.path) — this test inspects "
                          + "source text, so it SKIPS rather than reporting a green it did "
                          + "not earn")
        }
        return root
    }

    /// Every line of `path` that is not a whole-line comment. Comments are dropped because the
    /// view QUOTES all four of these tokens in its own prose (that is where #273 explains
    /// itself), and matching those would pass on the very removal this guards.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }
}
