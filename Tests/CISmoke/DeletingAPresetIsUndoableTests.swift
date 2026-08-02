// DeletingAPresetIsUndoableTests.swift
// Echoel — deleting a user sound or a user mood can be taken back, and the snapshot is taken
// before the store forgets the preset.
//
// WHAT THIS GUARDS. Both Deletes live in an overflow `Menu` as `Button(role: .destructive)`,
// which SwiftUI only COLOURS red — nothing asks. Both are gated on `!isFactory`, so the only
// thing they can remove is a preset the user made themselves; a factory preset is never at
// risk and a hand-made one is the irreplaceable kind. SAVING the same sound, meanwhile, goes
// through an alert. One tap, no prompt, no way back was the asymmetry.
//
// THE FIX IS A SNAPSHOT, NOT A CONFIRMATION, and the reason is the same one the project-open
// rescue and the randomize snapshot give: a `.confirmationDialog` would add a modifier to a
// presentation chain the black-screen law (CLAUDE.md, 10.76.34) says must not grow, and all it
// could ever do is warn. Keeping the removed preset costs no presentation slot and gives it
// back.
//
// ⚠️ ORDER IS THE WHOLE BUG SURFACE. `PatchStore.delete` / `MoodPresetStore.delete` remove the
// preset from the store's array AND drop its id from `favorites`. A snapshot taken afterwards
// finds nothing (mood) or an already-cleared star (both). So this file asserts that the capture
// precedes the delete call, not merely that a capture exists somewhere in the action.
//
// ⚠️ HONEST LIMITS. Source-text scan, no simulator. It proves the capture happens and happens
// first, and that a restore path exists that re-applies the star. It cannot prove the restored
// preset is byte-identical, and it cannot prove a user finds a row that only appears when the
// menu is REOPENED — that limit is real and is written down beside the state it belongs to.
// NEEDS-FOUNDER-VERIFY: save a sound, star it, delete it, reopen the same ⋯ menu, tap "Undo
// delete of …" — is it back in the list, still starred, and is it the sound you hear?
//
// WHICH ASSERTION GOES RED ON THE PRE-FIX SOURCE (`156e0c5`), per-assertion, re-derived
// against `git show`. Test 1 goes red for BOTH surfaces: nothing was captured at all, so there
// is nothing above either delete call. Test 2 SKIPS there — `if let d = deletedPatch {` does
// not exist yet, so the window helper cannot delimit anything and refuses to report rather
// than passing vacuously. That is the honest behaviour for a guard on a row that has to exist
// before it can be checked, and it is stated here rather than left for the next session to
// discover; an earlier version of test 2 scanned the whole file instead and was GREEN on the
// pre-fix commit, which would have made this whole guard look falsifiable when half of it was
// not.
//
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest

final class DeletingAPresetIsUndoableTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// One surface's delete/undo pair, so the two assertions read once and run twice.
    private struct Surface {
        let name: String
        /// The store call that performs the destructive removal.
        let deleteCall: String
        /// The `@State` the snapshot is written into.
        let snapshot: String
        /// The store call that puts the preset back.
        let restoreCall: String
        /// The favourite-restoring call, which `save(_:)` does NOT do on its own.
        let favouriteCall: String
        /// The `if let` that gates the undo row — the window every restore assertion reads.
        let rowGate: String
    }

    private static let surfaces = [
        Surface(name: "sound", deleteCall: "patchStore.delete(", snapshot: "deletedPatch =",
                restoreCall: "patchStore.save(", favouriteCall: "patchStore.toggleFavorite(",
                rowGate: "if let d = deletedPatch {"),
        Surface(name: "mood", deleteCall: "moodStore.delete(", snapshot: "deletedMood =",
                restoreCall: "moodStore.save(", favouriteCall: "moodStore.toggleFavorite(",
                rowGate: "if let d = deletedMood {")
    ]

    /// The preset is captured before the store forgets it.
    func testTheSnapshotIsTakenBeforeTheDelete() throws {
        let source = try codeLines(Self.studio)
        for s in Self.surfaces {
            guard let delete = source.firstIndex(where: { $0.contains(s.deleteCall) }) else {
                throw XCTSkip("""
                    `\(s.deleteCall)` is gone from EchoelStudioView — if the \(s.name) library \
                    was restructured this guard should be rewritten with it, not left to pass \
                    vacuously
                    """)
            }
            // Look BACKWARDS from the delete, not across the whole file: a capture written
            // after the call is the exact defect this asserts against, and a file-wide
            // `contains` would happily accept it.
            let before = source[..<delete]
            XCTAssertTrue(before.contains { $0.contains(s.snapshot) }, """
                The \(s.name) Delete removes the preset without first capturing it. \
                `\(s.deleteCall)` drops it from the store's array and drops its id from \
                `favorites`, so nothing after that line can put it back — and the button is a \
                `Button(role: .destructive)` in a `Menu`, which SwiftUI only colours red. One \
                tap, no prompt, no way back. Write `\(s.snapshot) …` ABOVE the delete rather \
                than adding a confirmation dialog: a prompt grows the presentation chain the \
                black-screen law forbids growing, and it can only warn.
                """)
        }
    }

    /// The undo row puts the preset back, star included.
    ///
    /// ⛔ SCOPED TO THE UNDO ROW, NOT THE FILE. The first version asserted that
    /// `patchStore.save(` and `patchStore.toggleFavorite(` appear ANYWHERE in the source — and
    /// they already did, from the "Save changes" and "Favorite" rows of the very same menu. It
    /// was green on the pre-fix commit, which means it proved nothing about the undo at all.
    /// The window below starts at the `if let d = deleted…` that gates the undo row, so the
    /// calls have to be INSIDE it.
    func testTheUndoRowRestoresThePresetAndItsStar() throws {
        let source = try codeLines(Self.studio)
        for s in Self.surfaces {
            let row = try window(source, from: s.rowGate)
            XCTAssertTrue(row.contains { $0.contains(s.restoreCall) }, """
                The \(s.name) undo row does not call `\(s.restoreCall)`, so the captured preset \
                is held and never given back — a snapshot with no restore is dead weight that \
                reads like a safety net.
                """)
            XCTAssertTrue(row.contains { $0.contains(s.favouriteCall) }, """
                The \(s.name) undo row does not call `\(s.favouriteCall)`, so a restored preset \
                comes back un-starred. The store's `delete` drops the id from `favorites` and \
                `save(_:)` does not put it back, so re-saving alone is a silent half-restore: \
                the preset returns, the user's own marking of it does not.
                """)
            XCTAssertTrue(row.contains { $0.contains("= nil") }, """
                The \(s.name) undo row never clears its snapshot, so "Undo delete of …" stays \
                in the menu after it has been used — and tapping it again would re-save a \
                preset the user may have deliberately deleted a second time. The row has to be \
                a one-shot.
                """)
        }
    }

    // MARK: - Reading the source

    /// Lines from `declaration` to the closing brace at the declaration's own indentation.
    ///
    /// Structural rather than a line count or a naming convention — both of those shapes have
    /// already failed in this bundle; `CoachingTextScalesTests`,
    /// `LockCueDoesNotShoveTheControlsTests`, `OpeningAProjectRescuesTheLiveTakeTests` and
    /// `RandomizeIsUndoableTests` carry the same helper and the reasoning at length.
    ///
    /// ⚠️ Accepted limit: a multi-line string literal containing a line that is exactly the
    /// declaration's indentation plus `}` would end the window early. Neither undo row contains
    /// one.
    private func window(_ source: [String], from declaration: String) throws -> ArraySlice<String> {
        guard let start = source.firstIndex(where: { $0.contains(declaration) }) else {
            throw XCTSkip("""
                `\(declaration)` is gone from EchoelStudioView — the undo row was removed or \
                rewritten, and this guard should be rewritten with it rather than left to pass \
                vacuously
                """)
        }
        let indent = String(source[start].prefix { $0 == " " })
        let closer = indent + "}"
        guard let end = source[start...].dropFirst().firstIndex(where: {
            $0.hasPrefix(closer) && $0.trimmingCharacters(in: .whitespaces) == "}"
        }) else {
            throw XCTSkip("""
                `\(declaration)` has no closing brace at its own indentation — the file was \
                reformatted or the row restructured, and reading on would inspect the wrong \
                lines. Rewrite this guard with the new shape rather than letting it report on a \
                window it cannot delimit
                """)
        }
        return source[start...end]
    }

    /// Lines of `path` that are not whole-line comments. Load-bearing here for the usual
    /// reason: the rationale blocks in `EchoelStudioView` name `patchStore.delete`,
    /// `deletedPatch` and `toggleFavorite` in prose, so an unfiltered scan could satisfy every
    /// assertion from the paragraphs explaining the fix while the code itself had lost it.
    ///
    /// ⚠️ Whole-line only — a TRAILING comment on a code line survives and reads as code.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath:
                root.appendingPathComponent(Self.studio).path) else {
            throw XCTSkip("Source tree not present next to the test bundle — nothing to check")
        }
        return root
    }
}
