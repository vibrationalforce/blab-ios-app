// SoundPanelPresetBarTests.swift
// Echoel — #132 Slice 6. `Sources/Echoelmusic/Studio/PatchEditorView.swift` is DELETED. It had
// zero instantiation sites (doorless since the 2026-07-02 Tools-grid removal) and was a
// near-duplicate of `soundPanel`, the live timbre editor behind the Sound chip.
//
// ⭐ WHAT MADE THE DELETION SAFE, and therefore what this file pins. Deleting a doorless view
// is only free if every capability it held has a SECOND home. Five of its PARAMETER rows were
// ported first (#281 `unisonVoices`/`unisonDetuneCents`, #286 `spectralShape`/`noiseColor`/
// `outputLevel`) and `UnisonRowDefaultsTests` guards those. Nothing guarded the other half —
// its PRESET BAR: pick a sound, favourite it, save changes, save-as, delete, submit to the
// community. Those all exist in `presetRow`, which is why the file could go; but they existed
// there by accident of history, with no test saying they must stay. Strip one of them in a
// future "simplify the Sound panel" pass and the justification recorded in the deletion commit
// becomes retroactively false, with the duplicate no longer around to fall back on.
//
// ⛔ THIS IS NOT A "the deleted file stays deleted" test, and the difference matters. Restoring
// `PatchEditorView.swift` would be harmless on its own — it was doorless. What would be
// harmful is losing a capability from the panel that replaced it. So the assertions point at
// what must EXIST, not at what must be absent. (One absence check is included, and its reason
// is narrower than "keep it deleted" — see `testTheStaleDuplicateIsNotBackWithoutItsGuards`.)
//
// ⚠️ WHY A SOURCE SCAN. `presetRow` and `soundPanel` are `private` members of a view;
// `@testable import` grants `internal`, not `private`, and this environment has no simulator.
// The realistic regression is textual and a textual check catches exactly it. House pattern:
// `UnisonRowDefaultsTests`, `SaveDoorNamingTests`, `ChromeDynamicTypeTests`.
//
// ⛔ HONEST LIMIT: this proves the capabilities are WRITTEN into `presetRow`. It cannot prove
// the panel renders them, that the Sound chip reaches the panel, or that saving a sound
// actually round-trips to disk. That is device-verified only.

import Foundation
import XCTest

final class SoundPanelPresetBarTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// The six preset-bar capabilities `PatchEditorView` also held. Each is matched by the CALL
    /// it makes, not by its button title — titles are copy and may be reworded (the ellipsis in
    /// "Save as new sound…" already differs from the deleted file's "Save as…"), while a store
    /// call disappearing is the actual capability loss.
    private static let capabilities: [(what: String, token: String)] = [
        ("load a saved sound",      "patchStore.sortedPatches"),
        ("load a community sound",  "CommunityLibrary.patches"),
        ("favourite / unfavourite", "patchStore.toggleFavorite(id: currentPatch.id)"),
        ("save changes",            "patchStore.save(currentPatch)"),
        ("delete a user sound",     "patchStore.delete(id: currentPatch.id)"),
        ("submit to the community", "currentPatch.communityMailtoURL()"),
    ]

    func testThePresetBarStillHoldsEveryCapabilityTheDeletedEditorHad() throws {
        let body = try presetRowBody()
        for cap in Self.capabilities {
            XCTAssertTrue(body.contains { $0.contains(cap.token) }, """
            `presetRow` can no longer \(cap.what) — `\(cap.token)` is gone from it. That was one \
            of the six capabilities `PatchEditorView` also offered, and its presence here is the \
            reason #132 Slice 6 could delete that file without losing anything. There is no \
            second editor to fall back on any more. If this row is being restructured, move the \
            call and this guard together; if a capability is being dropped deliberately, say so \
            in the commit and delete its line from `capabilities` above.
            """)
        }
    }

    /// The save-as door is checked separately because it is the one capability that lives in a
    /// FLAG rather than a store call: `presetRow` only sets `showSavePatchAs`, and the alert
    /// that reads it sits far away on the body's modifier chain. A setter with no reader is the
    /// classic doorless slot this repo keeps re-discovering (CLAUDE.md: "a slot proves nothing
    /// about reachability"), so both ends are asserted, whole-file for the reader.
    func testSaveAsHasBothItsSetterAndItsReader() throws {
        let body = try presetRowBody()
        XCTAssertTrue(body.contains { $0.contains("showSavePatchAs = true") }, """
        `presetRow` no longer opens the save-as door. Saving the current sound under a new name \
        was `PatchEditorView`'s "Save as…" too, and that file is deleted (#132 Slice 6).
        """)

        let studio = try codeLines(Self.studio)
        XCTAssertTrue(studio.contains { $0.contains("$showSavePatchAs") }, """
        nothing presents anything for `showSavePatchAs` any more, so the menu item sets a flag \
        no one reads — a control that looks like it works and does nothing. Re-point the guard \
        if the presentation moved; do not delete it.
        """)
    }

    /// ⛔ THE NARROW REASON THIS ABSENCE IS CHECKED, and it is not tidiness. Four assertions in
    /// `UnisonRowDefaultsTests` justify themselves in their FAILURE TEXT with "`PatchEditorView`
    /// is doorless and queued for deletion … so removing this row does not leave a second way
    /// in". If the file returns, those messages start lying to the next session at exactly the
    /// moment it is deciding whether a row is safe to remove. Either both facts hold, or both
    /// texts change — this test is the coupling that forces the pair.
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

    /// The lines of `presetRow`'s body: from its declaration to the next member declaration.
    /// Scoping matters — every token above also appears elsewhere in this 6000-line file (the
    /// community menu in the FX and mood bars, `patchStore` in the apply path), so a whole-file
    /// scan would stay green after the preset bar itself was gutted.
    private func presetRowBody() throws -> [String] {
        let lines = try codeLines(Self.studio)
        guard let start = lines.firstIndex(where: { $0.contains("private var presetRow") }) else {
            XCTFail("`presetRow` is gone from \(Self.studio) — that is the Sound panel's preset "
                    + "bar (load / favourite / save / delete / submit). If it was renamed or "
                    + "split, move this guard with it rather than dropping it.")
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
            throw XCTSkip("source tree not present at \(sources.path) — this test inspects source "
                          + "text, so it SKIPS rather than reporting a green it did not earn")
        }
        return root
    }

    /// Every line of `path` that is not a whole-line comment. The prose in and around
    /// `presetRow` quotes several of the tokens searched for here, so without this filter the
    /// assertions would pass on comments after the code they describe had been deleted.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }
}
