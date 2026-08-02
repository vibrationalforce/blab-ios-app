// RandomizeIsUndoableTests.swift
// Echoel — the Sound panel's two wholesale timbre writers share ONE undo point, and the
// affordance names what it actually undoes.
//
// WHAT THIS GUARDS. "Randomize timbre" replaces `currentPatch` outright: a random factory
// character plus four jittered fields. A hand-dialled sound was one accidental tap from gone,
// with nothing to get it back from — while the row DIRECTLY ABOVE it, the sound prompt, had
// kept exactly one undo step since it shipped. Two neighbouring controls doing the same thing
// to the same value, one reversible and one not, and the Undo arrow between them looked like
// it covered both. It now does.
//
// THE FIX IS A SNAPSHOT, NOT A PROMPT, for the same reason the project-open rescue was: a
// `.confirmationDialog` would add a modifier to a presentation chain the black-screen law
// (CLAUDE.md, 10.76.34) says must not grow, and all it could ever do is warn. One assignment
// makes the tap undoable instead of merely announced.
//
// ⚠️ THE NAME IS PART OF THE FIX, which is why this file pins it. The snapshot was called
// `patchBeforePrompt` while only the prompt wrote it; a second writer inheriting that name
// would tell the NEXT author that the slot is the prompt's private business. Same for the
// VoiceOver label, which said "Undo the last shaping" — after a randomize that is simply not
// what the arrow does, and a blind user would have had no way to know it applied.
//
// ⚠️ HONEST LIMITS. Source-text scan, no simulator. It proves the snapshot is taken, that it is
// taken BEFORE the overwrite, and that the label does not name one writer. It cannot prove the
// restored patch sounds like the one that was lost (that is `undoSoundPrompt`'s job and
// unchanged), and it cannot prove a user finds an arrow that only appears once there is
// something to undo. NEEDS-FOUNDER-VERIFY: dial a sound, tap Randomize, tap the arrow above it
// — is the dialled sound back?
//
// ⚠️ AND IT DOES NOT GUARD THE OTHER SEVEN. `currentPatch` is assigned wholesale in several
// more places (preset load, project open, genre change); none of them is covered by one slot
// and none should be — a one-step history that silently points at a patch from before a preset
// load is worse than no history. This file is about the two controls that sit together in one
// panel and read as a pair.
//
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest

final class RandomizeIsUndoableTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let randomizeDeclaration = "private var randomizeButton: some View"
    private static let snapshot = "patchBeforeSoundChange"

    /// Randomize stores the live patch before it replaces it.
    func testRandomizeSnapshotsBeforeItOverwrites() throws {
        let source = try codeLines(Self.studio)
        let body = try window(source, from: Self.randomizeDeclaration)

        guard let snap = body.firstIndex(where: { $0.contains("\(Self.snapshot) = currentPatch") }) else {
            XCTFail("""
                `randomizeButton` no longer stores the live patch before overwriting it. The \
                button replaces `currentPatch` with a random factory character plus four \
                jittered fields; without the snapshot a hand-dialled sound is gone on one \
                accidental tap, and the Undo arrow one row above stays disabled while looking \
                like it applies. Restore `\(Self.snapshot) = currentPatch` as the first \
                statement rather than adding a confirmation dialog — a prompt grows the \
                presentation chain the black-screen law forbids growing, and it can only warn.
                """)
            return
        }

        // ⛔ ORDER, NOT MERE PRESENCE — the same trap the project-open guard documents. A
        // snapshot written AFTER `currentPatch = p` stores the random patch, so Undo would
        // "restore" what the user just wanted to get away from, and the assertion above would
        // still pass. `currentPatch = p` is the overwrite in this body.
        let overwrite = body.firstIndex { $0.contains("currentPatch = p") }
        XCTAssertNotNil(overwrite, """
            `randomizeButton` no longer assigns `currentPatch = p`, so this guard cannot tell \
            whether the snapshot still happens before the overwrite. If the button was \
            restructured, rewrite this assertion with it rather than leaving it to pass on a \
            shape it no longer describes.
            """)
        if let overwrite {
            XCTAssertLessThan(snap, overwrite, """
                `randomizeButton` snapshots AFTER it overwrites `currentPatch`, so the undo \
                point holds the random patch instead of the one the user had. That is worse \
                than no undo: the arrow appears, the user taps it, and nothing they recognise \
                comes back. Move the snapshot above the assignment.
                """)
        }
    }

    /// The undo affordance does not name one of the two writers.
    ///
    /// ⚠️ Asserted as a NEGATIVE — the label must not say "shaping" — rather than pinning the
    /// exact replacement string. The wording is a copy decision that may well be improved; what
    /// must not come back is a label that describes only the prompt while the arrow also undoes
    /// a randomize. Pinning the exact sentence would make every rewording a red for no reason,
    /// which is how a guard gets deleted instead of updated.
    func testTheUndoLabelDoesNotNameOnlyThePrompt() throws {
        let source = try codeLines(Self.studio)
        guard let label = source.first(where: {
            $0.contains(".accessibilityLabel(") && $0.contains("Undo")
        }) else {
            throw XCTSkip("""
                No accessibility label mentioning "Undo" is left in EchoelStudioView — if the \
                undo affordance moved or was renamed, rewrite this guard with it rather than \
                letting it pass vacuously
                """)
        }
        let text = label.trimmingCharacters(in: .whitespaces)
        XCTAssertFalse(label.contains("shaping"), """
            The undo button's VoiceOver label names the sound PROMPT only: \(text) Since \
            `randomizeButton` also writes `\(Self.snapshot)`, that same arrow undoes a \
            randomize — and a blind user hearing "shaping" after tapping Randomize has no way \
            to know it applies. Name the shared action, not one of its two writers.
            """)
    }

    // MARK: - Reading the source

    /// Lines from `declaration` to the closing brace at the declaration's own indentation.
    ///
    /// Structural rather than a line count or a naming convention — both of those shapes have
    /// already failed in this bundle; `CoachingTextScalesTests`,
    /// `LockCueDoesNotShoveTheControlsTests` and `OpeningAProjectRescuesTheLiveTakeTests` carry
    /// the same helper and the reasoning at length.
    ///
    /// ⚠️ Accepted limit: a multi-line string literal containing a line that is exactly the
    /// declaration's indentation plus `}` would end the window early. The member inspected here
    /// contains none.
    private func window(_ source: [String], from declaration: String) throws -> ArraySlice<String> {
        guard let start = source.firstIndex(where: { $0.contains(declaration) }) else {
            throw XCTSkip("""
                `\(declaration)` is gone from EchoelStudioView — if the Sound panel was \
                restructured this test should be rewritten with it, not left to pass vacuously
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

    /// Lines of `path` that are not whole-line comments. Load-bearing here for a reason that
    /// does occur in this file: the ⭐ block above `randomizeButton` and the ⛔ block above the
    /// accessibility label both quote the very strings these assertions look for, so an
    /// unfiltered scan could find the fix in the paragraph explaining it and pass on a source
    /// that had lost it.
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
