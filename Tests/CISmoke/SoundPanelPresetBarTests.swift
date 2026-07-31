// SoundPanelPresetBarTests.swift
// Echoel — #132 Slice 6. `Sources/Echoelmusic/Studio/PatchEditorView.swift` is DELETED. It had
// zero instantiation sites (doorless since the 2026-07-02 Tools-grid removal) and duplicated
// part of `soundPanel`, the live timbre editor behind the Sound chip.
//
// ⭐ WHAT MADE THE DELETION SAFE, and therefore what this file pins. Deleting a doorless view
// is only free if every capability it held has a SECOND home. Five of its PARAMETER rows were
// ported first (#281 `unisonVoices`/`unisonDetuneCents`, #286 `spectralShape`/`noiseColor`/
// `outputLevel`) and `UnisonRowDefaultsTests` guards those. Nothing guarded the other half —
// its PRESET BAR: pick a sound, favourite it, save changes, save-as, delete, submit to the
// community. Those all exist in `presetRow`, which is why the file could go; but nothing said
// they must stay. Strip one in a future "simplify the Sound panel" pass and the justification
// recorded in the deletion commit becomes retroactively false, with no duplicate to fall back
// on.
//
// ⛔ THIS IS NOT A "the deleted file stays deleted" test. Restoring `PatchEditorView.swift`
// would be harmless on its own — it was doorless. What would be harmful is losing a capability
// from the panel that replaced it. So the assertions point at what must EXIST. (One absence
// check is included with a narrower reason — see `testTheStaleDuplicateIsNotBackWithoutItsGuards`.)
//
// ⛔ THE FIRST VERSION OF THIS FILE SCOPED EVERY MATCH TO `presetRow`'s OWN BODY AND JUSTIFIED
// IT WITH A CLAIM THAT IS FALSE. It said each token "also appears elsewhere in this 6000-line
// file (the community menu in the FX and mood bars, `patchStore` in the apply path), so a
// whole-file scan would stay green after the preset bar itself was gutted." A reviewer counted:
// all seven tokens occur ONLY inside `presetRow` — `CommunityLibrary.` appears exactly twice in
// the file, both there, and this file holds no FX or mood community menu at all. The scoping
// therefore bought nothing and cost real fragility: the slice ended at the next `    private `
// line, so extracting the overflow `Menu` into its own `private var soundActionsMenu` — this
// file's own prevailing idiom — would move five of six tokens out and redden the BLOCKING gate
// with six messages each claiming a capability had been deleted. Wrong justification, and the
// mechanism it justified was the harmful half. Both are corrected below.
//
// ⚠️ THE TRADE THIS VERSION MAKES, stated rather than left to be discovered. Whole-file matching
// cannot tell "the call moved into a helper `presetRow` still calls" (fine) from "the call moved
// into a helper NOTHING calls" (a real loss). `testThePresetBarIsMountedInTheSoundPanel` covers
// the coarse half — the bar itself must still hang in the panel — but a capability buried in a
// never-called helper would slip through. That case is narrow and deliberate; the case this file
// exists for is the broad one, someone simplifying the panel and dropping a row. Guarding the
// narrow case with a text slice costs a false red on every ordinary refactor, which is worse:
// a guard that cries wolf gets deleted, and then neither case is covered.
//
// ⚠️ WHY A SOURCE SCAN AT ALL. `presetRow` and `soundPanel` are `private` members of a view;
// `@testable import` grants `internal`, not `private`, and this environment has no simulator.
// House pattern: `UnisonRowDefaultsTests`, `SaveDoorNamingTests`, `ChromeDynamicTypeTests`.
//
// ⛔ HONEST LIMIT: this proves the capabilities are WRITTEN and the bar is mounted. It cannot
// prove the panel renders, that the Sound chip reaches it, or that saving a sound round-trips
// to disk. That is device-verified only.

import Foundation
import XCTest

final class SoundPanelPresetBarTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// The six preset-bar capabilities `PatchEditorView` also held. Each is matched by the CALL
    /// it makes, not by its button title — titles are copy and may be reworded (the deleted
    /// file's "Save as…" is already "Save as new sound…" here), while a store call disappearing
    /// IS the capability loss. Every token below occurs exactly once in the file, inside
    /// `presetRow` (`CommunityLibrary.patches` twice, both there) — that uniqueness is why a
    /// whole-file match is as strong as a scoped one and far less brittle.
    private static let capabilities: [(what: String, token: String)] = [
        ("load a saved sound",      "patchStore.sortedPatches"),
        ("load a community sound",  "CommunityLibrary.patches"),
        ("favourite / unfavourite", "patchStore.toggleFavorite(id: currentPatch.id)"),
        ("save changes",            "patchStore.save(currentPatch)"),
        ("delete a user sound",     "patchStore.delete(id: currentPatch.id)"),
        ("submit to the community", "currentPatch.communityMailtoURL()"),
    ]

    func testEveryCapabilityTheDeletedEditorHadStillExists() throws {
        let studio = try codeLines(Self.studio)
        for cap in Self.capabilities {
            XCTAssertTrue(studio.contains { $0.contains(cap.token) }, """
            the Sound panel can no longer \(cap.what) — `\(cap.token)` is gone from \
            \(Self.studio). That was one of six capabilities `PatchEditorView` also offered, and \
            their presence here is why #132 Slice 6 could delete that file without losing \
            anything. There is no second editor to fall back on. If a capability is being \
            dropped deliberately, say so in the commit and remove its line from `capabilities`.
            """)
        }
    }

    /// The coarse reachability half. The tokens above prove the CALLS exist somewhere in the
    /// file; this proves the bar that holds them still hangs in the panel the Sound chip opens.
    /// Together they are weaker than a full slice and much less likely to fire on a refactor —
    /// the trade is spelled out in the header.
    func testThePresetBarIsMountedInTheSoundPanel() throws {
        let body = try soundPanelBody()
        XCTAssertTrue(body.contains { $0.trimmingCharacters(in: .whitespaces) == "presetRow" }, """
        `presetRow` is no longer mounted in `soundPanel`. The preset bar — load, favourite, \
        save, save-as, delete, submit — is the half of `PatchEditorView` that was never ported \
        because it was already here. Unmounting it removes all six at once, and #132 Slice 6 \
        deleted the only other place they existed.
        """)
    }

    /// Save-as is checked separately because it lives in a FLAG, not a store call: `presetRow`
    /// only sets `showSavePatchAs`, and the alert that reads it sits far away on the body's
    /// modifier chain. A setter with no reader is the doorless slot this repo keeps
    /// re-discovering (CLAUDE.md: "a slot proves nothing about reachability"), so both ends are
    /// asserted.
    func testSaveAsHasBothItsSetterAndItsReader() throws {
        let studio = try codeLines(Self.studio)
        XCTAssertTrue(studio.contains { $0.contains("showSavePatchAs = true") }, """
        nothing opens the save-as door any more. Saving the current sound under a new name was \
        `PatchEditorView`'s "Save as…" too, and that file is deleted (#132 Slice 6).
        """)
        XCTAssertTrue(studio.contains { $0.contains("$showSavePatchAs") }, """
        nothing presents anything for `showSavePatchAs` any more, so the menu item sets a flag \
        no one reads — a control that looks like it works and does nothing. Re-point this guard \
        if the presentation moved; do not delete it.
        """)
    }

    /// ⛔ THE NARROW REASON THIS ABSENCE IS CHECKED, and it is not tidiness. Four assertions in
    /// `UnisonRowDefaultsTests` justify themselves in their FAILURE TEXT with "`PatchEditorView`
    /// is deleted … so removing this row does not leave a second way in". If the file returns,
    /// those messages start lying to the next session at exactly the moment it is deciding
    /// whether a row is safe to remove. Either both facts hold, or both texts change.
    func testTheStaleDuplicateIsNotBackWithoutItsGuards() throws {
        let path = try repoRoot().appendingPathComponent("Sources/Echoelmusic/Studio/PatchEditorView.swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path), """
        `PatchEditorView.swift` is back. That is not forbidden — it was doorless, so it harms \
        nothing by itself. What it DOES break is the failure text of four assertions in \
        `UnisonRowDefaultsTests`, which tell a future session that no second editor exists for \
        five persisted parameters. Restoring the file means updating those messages in the same \
        commit, and deleting this assertion once they no longer claim it.
        """)
    }

    /// The lines of `soundPanel`'s body: from its declaration to the next member declaration.
    /// Same helper shape as `UnisonRowDefaultsTests`; kept local because CISmoke files are
    /// standalone by design.
    private func soundPanelBody() throws -> [String] {
        let lines = try codeLines(Self.studio)
        guard let start = lines.firstIndex(where: { $0.contains("private var soundPanel") }) else {
            XCTFail("""
            `soundPanel` is gone from \(Self.studio) — that is the live patch editor, the panel \
            behind the Sound chip. If it was renamed, move this guard with it.
            """)
            return []
        }
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("    private ") } ?? lines.endIndex
        return Array(lines[start..<end])
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`, three levels up:
    /// CISmoke → Tests → repo).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()              // Tests
            .deletingLastPathComponent()              // repo
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
            source tree not present at \(sources.path) — this test inspects source text, so it \
            SKIPS rather than reporting a green it did not earn.
            """)
        }
        return root
    }

    /// Every line of `path` that is not a whole-line comment. The prose in and around
    /// `presetRow` quotes several of the tokens searched for here, so without this filter the
    /// assertions would pass on comments after the code they describe had been deleted.
    /// (It does not strip block or trailing comments; neither occurs near these call sites.)
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }
}
