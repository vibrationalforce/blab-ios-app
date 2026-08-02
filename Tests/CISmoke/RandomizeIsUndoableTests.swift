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
// THE FIX IS A SNAPSHOT, NOT A PROMPT, for the same reason the project-open rescue was: all a
// `.confirmationDialog` could ever do is warn, while one assignment makes the tap undoable
// instead of merely announced.
//
// ⛔ AND THE FIRST VERSION PROPPED THAT UP WITH A LAW THAT DOES NOT REACH THIS BUTTON — "would
// add a modifier to a presentation chain the black-screen law (CLAUDE.md, 10.76.34) says must
// not grow". That law is about modifiers appended to `EchoelStudioView.body` itself, the counted
// 14. `randomizeButton` lives in `soundPanel`, which reaches the body only through
// `dropdownContent: AnyView` and is type-erased before the body's aggregate type is formed; a
// dialog in here would have left the count at 14. The sentence was checkable and false, and a
// borrowed law is worse than no reason: the next session weighing a genuine dialog would have
// refused it on a rule that does not apply. Only the "a prompt warns, an assignment gives it
// back" half carries this decision, and it carries it alone.
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
// something to undo.
//
// ⚠️ AND THE PROTECTION IS ONE TAP DEEP — the limit worth stating out loud, because the button
// invites the opposite. One slot means Randomize → Randomize overwrites the snapshot with the
// FIRST random patch, so the hand-dialled sound this whole slice exists to protect is gone from
// the second tap on. On a control whose point is to be tapped until something sounds right, that
// is where a user will actually meet the hole. Deeper needs a stack, which is a separate
// decision (how deep, and does the prompt share it).
// NEEDS-FOUNDER-VERIFY, both halves: dial a sound, tap Randomize ONCE, tap the arrow above it —
// is the dialled sound back? Then dial again, tap Randomize TWICE, tap the arrow — it will hand
// back the first random patch, not the dialled one. Is that acceptable, or is a stack worth it?
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
                like it applies. Restore `\(Self.snapshot) = currentPatch` ABOVE the overwrite \
                — anywhere above it satisfies this guard, which checks order and not position \
                — rather than adding a confirmation dialog: a prompt can only warn, the \
                assignment gives the sound back.
                """)
            return
        }

        // ⛔ ORDER, NOT MERE PRESENCE — the same trap the project-open guard documents. A
        // snapshot written AFTER the overwrite stores the random patch, so Undo would "restore"
        // what the user just wanted to get away from, and the assertion above would still pass.
        // ⚠️ Matched as the WHOLE trimmed statement, not as a substring: bare `currentPatch = p`
        // is also a prefix of `currentPatch = previous` and `currentPatch = p.patch`, neither of
        // which is this body's overwrite. Latent today (both live elsewhere in the file, outside
        // the window) and cheap to close before a refactor moves one in.
        let overwrite = body.firstIndex {
            $0.trimmingCharacters(in: .whitespaces) == "currentPatch = p"
        }
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
        // ⛔ UNIQUENESS IS ASSERTED, NOT ASSUMED. The first version took `first(where:)` and the
        // commit message argued from "there is exactly one Undo label in the file" — true then,
        // and precisely the kind of fact that stops being true without anyone noticing. A second
        // "Undo …" label added ANYWHERE earlier in these 8000+ lines (a take undo, a mix undo)
        // would silently retarget this check, leaving the real arrow free to regress to
        // "shaping" while the guard stayed green. A skip on ambiguity says so instead.
        let labels = source.filter { $0.contains(".accessibilityLabel(") && $0.contains("Undo") }
        guard labels.count == 1, let label = labels.first else {
            throw XCTSkip("""
                Expected exactly one accessibility label mentioning "Undo" in EchoelStudioView, \
                found \(labels.count). This guard reads the sound-panel arrow by that \
                description alone; with none it has nothing to check, and with several it cannot \
                tell which is which. Anchor it to its own view or rewrite it — do not let it \
                report on whichever line happens to come first
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

    /// Lines of `path` that are not whole-line comments.
    ///
    /// ⛔ AND THE FIRST VERSION JUSTIFIED THIS WITH A MECHANISM THAT CANNOT FIRE — the THIRD
    /// time this exact false rationale has been written into this bundle, after
    /// `LockCueDoesNotShoveTheControlsTests` and `OpeningAProjectRescuesTheLiveTakeTests` each
    /// carried a ⛔ correcting it. It claimed "the ⭐ block above `randomizeButton` and the ⛔
    /// block above the accessibility label both quote the very strings these assertions look
    /// for". Neither does: the ⭐ block sits ABOVE the declaration, so it is outside the window
    /// whether comments are stripped or not, and the ⛔ block quotes "Undo the last shaping"
    /// without `.accessibilityLabel(`, so the finder could never have matched it.
    ///
    /// The real reasons are narrower and do hold: a future comment line containing the literal
    /// declaration string would move `firstIndex` onto a comment and drag prose into the window,
    /// and a rationale comment placed INSIDE the member could satisfy a `contains` check with
    /// text rather than code. Belt and braces — kept, but honestly labelled.
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
