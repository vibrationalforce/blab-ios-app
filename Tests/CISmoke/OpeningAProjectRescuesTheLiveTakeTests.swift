// OpeningAProjectRescuesTheLiveTakeTests.swift
// Echoel — opening a saved take must not silently destroy the live one. #357 (b).
//
// WHAT THIS GUARDS. `EchoelStudioView.open(_:)` is the single funnel for both doors that
// load a project — the Open list's rows and `onLoadShared` — and every line of it overwrites
// the live take: style, key root, scale, FX character, loop length, patch, NOTES, tempo,
// concert pitch, tuning. There was no prompt on that path and no snapshot anywhere, so one
// tap in a library list threw away whatever the body had just played, with nothing to get it
// back from.
//
// THE FIX IS A RESCUE, NOT A PROMPT, and the distinction is the whole point. A
// `.confirmationDialog` would add a modifier to a presentation chain the black-screen law
// (CLAUDE.md, 10.76.34) says must not grow — and all it could ever do is warn. `autosaveTake()`
// already existed, already wrote the live take into the ONE reserved library slot through the
// same `ProjectStore` the Save button uses, and was wired to exactly one trigger: a scene-phase
// departure. So it covered backgrounding and covered nothing the user did inside the app.
// Calling it here costs no UI and makes the action reversible instead of merely announced.
//
// ⚠️ THE GATE IS NOT DECORATION. There is exactly one autosave slot, matched by a fixed id in
// `ProjectStore.save`. Opening the autosave row would therefore first overwrite that row with
// the state the user is discarding. The open would still succeed — `p` is a value copy, read
// before anything is written — but the recovery row would then hold the discarded take, so a
// second tap would undo the recovery. Skipping the write for that one id keeps the row meaning
// one thing. This file asserts the gate, not just the call.
//
// ⚠️ AND THE ORDER IS ASSERTED, because a rescue written after the first assignment rescues
// nothing. `style = openStyle` is the first mutation in the function; the call has to sit
// above it. An assertion that only proved the call EXISTS somewhere in the body would pass on
// a version that saved the already-overwritten state — a green nobody earned.
//
// ⚠️ HONEST LIMITS. Source-text scan, no simulator. It proves the call is present, gated and
// ordered; it cannot prove the written take actually recalls the session, and it cannot prove
// a user finds the Autosave section. And this is a recovery POINT, not an undo stack: one
// slot, so opening twice leaves only the state from just before the second open.
// NEEDS-FOUNDER-VERIFY: compose something, open a different take from the library, then open
// the Autosave row — is the first take back?
//
// SCOPE. #357 lists four destructive paths; this slice takes only (b), the one that can lose
// a whole session. (a) delete-without-confirm, (c) randomize-without-snapshot and (d) the
// video library's delete button stay open in #357. `importMIDI` replaces the take too and is
// NOT in that audit — noted here so the next reader does not mistake this file for coverage
// of the class.
//
// Both tests go red on the pre-fix source (`e0add16`), verified by re-deriving every assertion
// against `git show`: `open(_:)` contained no `autosaveTake()` at all, so all three assertions
// of the first test fail. The second test — the guard inside `autosaveTake()` itself — was
// already green and stays green: it is a pin on an assumption this new caller now depends on,
// not a description of the bug.
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest

final class OpeningAProjectRescuesTheLiveTakeTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let openDeclaration = "private func open(_ p: Project)"
    private static let autosaveDeclaration = "private func autosaveTake()"

    /// The live take is written to the recovery slot before anything is overwritten.
    func testOpeningRescuesTheLiveTakeFirst() throws {
        let source = try codeLines(Self.studio)
        let body = try window(source, from: Self.openDeclaration)

        // ⛔ `XCTFail` then `return`, NOT `return XCTFail(…)`. Both compile — `XCTFail` is
        // `Void` — but the second reads as if the failure were the return value, and this
        // bundle has no local compiler to settle a second-guess. Also NOT `XCTSkip`: the
        // declaration is present (the window resolved), so a missing call is a real red, not
        // an absent tree.
        guard let rescue = body.firstIndex(where: { $0.contains("autosaveTake()") }) else {
            XCTFail("""
                `open(_:)` no longer calls `autosaveTake()`. Every line of that function \
                overwrites the live take — style, key, scale, patch, notes, tempo, concert \
                pitch — and both doors that load a project (the Open list and `onLoadShared`) \
                run through it. Without the rescue, one tap in a library list destroys \
                whatever the body just played with nothing to get it back from. Restore the \
                call rather than adding a confirmation dialog: a prompt grows the presentation \
                chain the black-screen law forbids growing, and it can only warn, never undo.
                """)
            return
        }

        // ⛔ `...rescue`, NOT `..<rescue`. The first version excluded the call's own line —
        // and the gate and the call sit on ONE line (`if p.id != … { autosaveTake() }`), so
        // the assertion failed against the very commit that introduced it. Inclusive covers
        // both spellings: gate-on-the-same-line and gate-on-the-line-above.
        XCTAssertTrue(body[...rescue].contains { $0.contains("Project.autosaveSlotID") }, """
            `open(_:)` calls `autosaveTake()` without first excluding \
            `Project.autosaveSlotID`. There is exactly ONE autosave slot and \
            `ProjectStore.save` matches by id, so opening the autosave row would overwrite \
            that row with the state the user is discarding before restoring it. The open \
            itself still works — `p` is a value copy — but the recovery row would then hold \
            the discarded take, and a second tap would undo the recovery. Gate the rescue on \
            `p.id != Project.autosaveSlotID`.
            """)

        // ⛔ ORDER, NOT MERE PRESENCE. A rescue below the first assignment saves the state
        // that has already been destroyed, and the assertion above would still pass on it.
        // `style = openStyle` is the first mutation in the function.
        let firstMutation = body.firstIndex { $0.contains("style = openStyle") }
        XCTAssertNotNil(firstMutation, """
            `open(_:)` no longer assigns `style = openStyle`. This guard uses that line as the \
            first mutation, so it can no longer prove the rescue runs BEFORE the take is \
            overwritten. Point the check at whatever the new first mutation is, in the same \
            commit — do not delete it, or the ordering stops being checked at all.
            """)
        if let firstMutation {
            XCTAssertLessThan(rescue, firstMutation, """
                `open(_:)` calls `autosaveTake()` AFTER it has already begun overwriting the \
                live take. A recovery point written at that moment records the destroyed \
                state, which is worse than no recovery point: it looks like a rescue and \
                restores nothing. The call belongs above the first assignment.
                """)
        }
    }

    /// The rescue must not be able to write an EMPTY take over a good recovery point.
    ///
    /// ⚠️ Not a duplicate of anything in `autosaveTake()`'s own doc — that comment explains
    /// why the guard exists for the scene-phase caller. This slice adds a SECOND caller that
    /// fires far more often, so the guard now protects a case its author did not have: opening
    /// a project while the roll is empty would otherwise replace a good recovery point with
    /// nothing, and there is only one slot to lose.
    func testTheRescueRefusesToStoreAnEmptyTake() throws {
        let source = try codeLines(Self.studio)
        let body = try window(source, from: Self.autosaveDeclaration)

        XCTAssertTrue(body.contains { $0.contains("guard hasComposed") }, """
            `autosaveTake()` lost its `hasComposed` guard. `hasComposed` is set `true` \
            unconditionally by `open(_:)` and is never set back to `false`, so without this \
            the rescue would fire on a state that was never composed.
            """)

        XCTAssertTrue(body.contains { $0.contains("pianoRoll.notes.isEmpty") }, """
            `autosaveTake()` lost its empty-roll guard. There is ONE recovery slot: writing \
            a take with no notes into it destroys the only thing the user could have gone \
            back to, silently and with no undo. Since #357(b) this guard also protects the \
            open path — opening any project while the roll is empty would otherwise clear the \
            recovery point as a side effect of loading.
            """)
    }

    // MARK: - Reading the source

    /// Lines from `declaration` to the closing brace at the declaration's own indentation.
    ///
    /// Structural rather than a line count or a naming convention — both of those shapes have
    /// already failed in this bundle; `CoachingTextScalesTests` and
    /// `LockCueDoesNotShoveTheControlsTests` carry the same helper and the reasoning at length.
    ///
    /// ⚠️ Accepted limit: a multi-line string literal containing a line that is exactly the
    /// declaration's indentation plus `}` would end the window early. Neither member inspected
    /// here contains one.
    private func window(_ source: [String], from declaration: String) throws -> ArraySlice<String> {
        guard let start = source.firstIndex(where: { $0.contains(declaration) }) else {
            throw XCTSkip("""
                `\(declaration)` is gone from EchoelStudioView — if the load path was \
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
                reformatted or the member restructured, and reading on would inspect the \
                wrong lines. Rewrite this guard with the new shape rather than letting it \
                report on a window it cannot delimit
                """)
        }
        return source[start...end]
    }

    /// Lines of `path` that are not whole-line comments. Required here for a reason that does
    /// occur: the rationale block INSIDE `open(_:)`'s window names `Project.autosaveSlotID`
    /// and `autosaveTake()` in prose, so an unfiltered scan would find the rescue in the
    /// paragraph explaining it and pass on a body that no longer calls it.
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
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let probe = root.appendingPathComponent(Self.studio)
        guard FileManager.default.fileExists(atPath: probe.path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
