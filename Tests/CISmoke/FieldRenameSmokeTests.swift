// FieldRenameSmokeTests.swift
// Echoel — the play surface was renamed to "Field" (founder 2026-07-29, "Der Visual Touch
// Synth soll optimiert und umbenannt werden. Übernimm du das!"), in the BLOCKING bundle.
//
// A rename is the cheapest change in an app and one of the most dangerous, because the same
// word usually lives in two places with completely different lifetimes: on screen, where
// changing it costs nothing, and in a PERSISTENCE KEY, where changing it silently discards
// everything the user already dialled in. There is no error, no warning, no crash — the
// setting is simply gone and reads as a factory default. This repo has paid for that class
// twice already (#163, #170).
//
// So the visible strings moved and the storage keys did not, and this file keeps those two
// facts from drifting apart. It asserts the KEYS, because that is the half that fails
// silently; the visible half fails the moment anyone looks at the screen.
//
// Deliberately written against `StudioDefaultKeys` — the app's own single source of truth
// for shared preferences — rather than against the source text. The first draft of this file
// read the `.swift` files and grepped for key literals, and it invented two keys that do not
// exist (`touch.syncStrength`, `touch.syncGrid`; the real ones are `touch.sync.strength` and
// `touch.sync.grid`). A test asserting keys nobody wrote would have failed the gate while
// looking rigorous. Compiling against the real declarations makes that impossible.

import XCTest
@testable import Echoelmusic

final class FieldRenameSmokeTests: XCTestCase {

    /// THE ONE THAT MATTERS. Every shared preference behind the play surface, pinned to the
    /// string it has always been stored under. The `touch.` prefix is STORAGE, not
    /// vocabulary — it survives the surface being renamed to "Field", and it must survive
    /// every rename after this one.
    ///
    /// ⚠️ If a key rename is ever genuinely wanted, it needs a migration that reads the old
    /// key and writes the new one. Editing the literal is not a migration, and deleting this
    /// test is not either.
    func testThePlaySurfaceKeepsItsStorageKeysAcrossTheRename() {
        XCTAssertEqual(StudioDefaultKeys.touchMorphDepth.key, "touch.morphDepth")
        XCTAssertEqual(StudioDefaultKeys.touchSlideVibrato.key, "touch.slideVibrato")
        XCTAssertEqual(StudioDefaultKeys.touchSlideChorus.key, "touch.slideChorus")
        XCTAssertEqual(StudioDefaultKeys.touchGlide.key, "touch.glide")
        XCTAssertEqual(StudioDefaultKeys.touchLevel.key, "touch.level")
        XCTAssertEqual(StudioDefaultKeys.touchLife.key, "touch.life")
        XCTAssertEqual(StudioDefaultKeys.touchSyncStrength.key, "touch.sync.strength")
        XCTAssertEqual(StudioDefaultKeys.touchSyncGrid.key, "touch.sync.grid")
    }

    /// The defaults behind those keys are founder decisions and a rename is not the moment
    /// to revisit them. Pinned separately from the keys because the two fail for different
    /// reasons: a changed key loses stored settings, a changed default changes how the
    /// instrument behaves on a fresh install — and only one of those is visible in a diff
    /// that claims to be "just a rename".
    func testTheRenameChangedNoDefaultBehindThoseKeys() {
        XCTAssertEqual(StudioDefaultKeys.touchMorphDepth.value, 0.6, accuracy: 1e-9)
        XCTAssertEqual(StudioDefaultKeys.touchSlideVibrato.value, 0.35, accuracy: 1e-9)
        XCTAssertEqual(StudioDefaultKeys.touchSlideChorus.value, 0.30, accuracy: 1e-9)
        XCTAssertEqual(StudioDefaultKeys.touchGlide.value, 0.0, accuracy: 1e-9)
        XCTAssertEqual(StudioDefaultKeys.touchLevel.value, 1.0, accuracy: 1e-9)
        XCTAssertEqual(StudioDefaultKeys.touchLife.value, 0.35, accuracy: 1e-9)
        // Sync OFF on a fresh install: the surface plays exactly where the finger lands
        // until someone asks for the grid. A rename must not quietly arm it.
        XCTAssertEqual(StudioDefaultKeys.touchSyncStrength.value, 0.0, accuracy: 1e-9)
    }
}
