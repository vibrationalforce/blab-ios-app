// DeletingAClipIsUndoableTests.swift
// Echoel — deleting a recorded clip parks the file instead of erasing it, and every control in
// a clip's row says WHICH clip it belongs to.
//
// WHAT THIS GUARDS. The video library is the only surface in the app that can destroy something
// unrepeatable. A preset can be dialled again and a generated take re-generated; a recorded
// performance cannot be performed again. The control that destroyed it was an icon-only
// `Button(role: .destructive)` — SwiftUI only COLOURS that red, nothing asks — sitting ten
// points from Share in a row of three look-alike glyphs, calling `FileManager.removeItem`
// directly.
//
// THE FIX IS A PARK, NOT A PROMPT, which is the same answer #357 gave for the project open, the
// randomize and both preset deletes, and it works here for a reason worth writing down: the
// library lives in `Documents` and the park in `tmp`, which are the same volume inside the app
// container, so `moveItem` is a rename and not a copy. A four-hundred-megabyte clip is parked in
// the same time as an empty one, and the way back is the same rename reversed.
//
// (⛔ Do NOT restate the argument the sibling guards shipped first — "a dialog would grow the
// presentation chain the black-screen law forbids growing". It was struck everywhere: that law
// governs modifiers appended to `EchoelStudioView.body` itself, and this panel reaches the body
// through `dropdownContent: AnyView` like every other one. A dialog here would cost no slot. The
// reason a park beats a prompt is simply that a prompt can only warn.)
//
// ⚠️ ORDER IS THE BUG SURFACE, AS EVER. A park written after the removal has nothing to park.
// This file therefore asserts that `delete(_:)` contains NO `removeItem` at all — the strongest
// available form here, because unlike a preset store there is no in-memory copy to fall back on:
// if the bytes are unlinked, no later line can invent them.
//
// ⚠️ AND THE NAMES. "Play clip" / "Share clip" / "Delete clip" is correct for one row and
// useless in a list, which is the only shape this surface has. A VoiceOver user swiping through
// six recordings heard the same three words six times with nothing to distinguish them — and
// one of those three deletes a performance. The guard asserts the labels interpolate, without
// pinning the wording, because the phrasing is a copy decision and pinning it would make every
// improvement a red for no reason.
//
// ⚠️ HONEST LIMITS. Source-text scan, no simulator. It proves the park is spelled, that nothing
// unlinks the file on the delete path, that a restore exists, and that the row controls carry an
// interpolated name. It cannot prove the restored file plays, and it cannot prove the offer is
// findable. NEEDS-FOUNDER-VERIFY: record a clip in the visual window, open Video, delete it,
// tap "Undo delete of …" — is it back in the list and does it still play? Then delete one,
// close the Video panel, reopen it: the offer is GONE by design and the clip stays deleted —
// is that the right trade, or should the park survive the panel?
//
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest

final class DeletingAClipIsUndoableTests: XCTestCase {

    private static let panel = "Sources/Echoelmusic/Studio/VideoLibraryPanel.swift"

    /// The delete path parks the file and never unlinks it.
    ///
    /// ⛔ THE DOTS IN `.moveItem(` AND `.removeItem(` ARE LOAD-BEARING, and the first version of
    /// this file left them off. `"moveItem("` is a SUBSTRING of `"removeItem("`, so the
    /// park assertion was satisfied by the very call it exists to forbid — green on the pre-fix
    /// source, which makes the whole guard decorative. Caught by running both assertions against
    /// `git show HEAD:` before committing, which is the only reason it is not in the tree. The
    /// leading dot separates them because `removeItem` is preceded by `re`, not by `.`.
    func testDeleteParksInsteadOfRemoving() throws {
        let source = try codeLines(Self.panel)
        let body = try window(source, from: "private func delete(_ clip: EchoelVideoClip)")

        XCTAssertTrue(body.contains { $0.contains(".moveItem(") }, """
            `delete(_:)` no longer moves the clip anywhere, so the recording is being disposed \
            of with no way back. This is the one surface in the app that can destroy something \
            unrepeatable — a performance, not a preset — behind an icon-only destructive button \
            that nothing confirms. Park the file in `tmp` (same volume, so the move is a rename) \
            and offer the way back.
            """)

        XCTAssertFalse(body.contains { $0.contains(".removeItem(") }, """
            `delete(_:)` unlinks the clip. Unlike a preset there is no in-memory copy to restore \
            from, so once the bytes are gone NO later line can bring them back — the undo row \
            becomes a button that cannot keep its word. Move the file instead of removing it.
            """)
    }

    /// A way back exists and puts the file where it came from.
    func testRestorePutsTheClipBack() throws {
        let source = try codeLines(Self.panel)
        let body = try window(source, from: "private func restore()")

        XCTAssertTrue(body.contains { $0.contains(".moveItem(") }, """
            `restore()` does not move the parked clip back, so the park is a one-way trip and \
            the row offering it is decoration. A snapshot with no restore reads like a safety \
            net and is not one.
            """)

        // ⛔ THE OVERWRITE CHECK IS THE POINT OF THIS ASSERTION, not the move. `moveItem` throws
        // onto an occupied path, and the tempting "fix" for that throw is to remove whatever is
        // in the way first — which would make a RESTORE destroy a newer recording. Requiring the
        // existence check keeps the safe branch (come back beside it) spelled out.
        XCTAssertTrue(body.contains { $0.contains(".fileExists(") }, """
            `restore()` no longer checks the destination before moving. `moveItem` throws onto \
            an occupied path, and the obvious repair for that throw — delete what is there first \
            — would turn the restore into a second destructive action against a file the user \
            never asked to lose. Keep the check and land beside the occupant instead.
            """)
    }

    /// Each control in a clip's row names the clip it acts on.
    func testRowControlsNameTheirClip() throws {
        let source = try codeLines(Self.panel)
        let row = try window(source, from: "private func clipRow(_ clip: EchoelVideoClip)")
        let labels = row.filter { $0.contains(".accessibilityLabel(") }

        guard labels.count >= 3 else {
            throw XCTSkip("""
                Expected the three per-clip controls (play/stop, share, delete) to carry \
                accessibility labels inside `clipRow`, found \(labels.count). The row was \
                restructured; rewrite this guard with it rather than letting it report on a \
                shape it no longer describes
                """)
        }

        for label in labels {
            let text = label.trimmingCharacters(in: .whitespaces)
            XCTAssertTrue(label.contains("\\("), """
                A control in `clipRow` is labelled with a constant string: \(text) In a list \
                every row then speaks the same words, so a VoiceOver user cannot tell which \
                recording the trash belongs to — and one of these three destroys a performance. \
                Interpolate the clip's own name (the visible title) into the label.
                """)
        }
    }

    // MARK: - Reading the source

    /// Lines from `declaration` to the closing brace at the declaration's own indentation.
    ///
    /// Structural rather than a line count or a naming convention — both of those shapes have
    /// already failed in this bundle; `CoachingTextScalesTests`,
    /// `LockCueDoesNotShoveTheControlsTests`, `OpeningAProjectRescuesTheLiveTakeTests`,
    /// `RandomizeIsUndoableTests` and `DeletingAPresetIsUndoableTests` carry the same helper and
    /// the reasoning at length.
    ///
    /// ⚠️ Accepted limit: a multi-line string literal containing a line that is exactly the
    /// declaration's indentation plus `}` would end the window early. None of the three members
    /// inspected here contains one.
    private func window(_ source: [String], from declaration: String) throws -> ArraySlice<String> {
        guard let start = source.firstIndex(where: { $0.contains(declaration) }) else {
            throw XCTSkip("""
                `\(declaration)` is gone from VideoLibraryPanel — if the library was \
                restructured this guard should be rewritten with it, not left to pass vacuously
                """)
        }
        let indent = String(source[start].prefix { $0 == " " })
        let closer = indent + "}"
        guard let end = source[start...].dropFirst().firstIndex(where: {
            $0.hasPrefix(closer) && $0.trimmingCharacters(in: .whitespaces) == "}"
        }) else {
            throw XCTSkip("""
                `\(declaration)` has no closing brace at its own indentation — the file was \
                reformatted or the member restructured, and reading on would inspect the wrong \
                lines. Rewrite this guard with the new shape rather than letting it report on a \
                window it cannot delimit
                """)
        }
        return source[start...end]
    }

    /// Lines of `path` that are not whole-line comments.
    ///
    /// Load-bearing here for a reason that DOES hold, unlike the version three sibling files
    /// had to strike: the rationale comments inside `delete(_:)` and `restore()` name
    /// `removeItem` and `moveItem` in prose, sitting INSIDE the windows these assertions read.
    /// Unfiltered, the "no `removeItem`" assertion would fail on the paragraph explaining why
    /// there is no `removeItem`.
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
                root.appendingPathComponent(Self.panel).path) else {
            throw XCTSkip("Source tree not present next to the test bundle — nothing to check")
        }
        return root
    }
}
