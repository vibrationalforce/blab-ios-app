// OpeningAProjectRescuesTheLiveTakeTests.swift
// Echoel — opening a saved take must not silently destroy the live one. #357 (b).
//
// WHAT THIS GUARDS. `EchoelStudioView.open(_:)` is the single funnel for both doors that
// load a project — the Open list's rows and `onLoadShared` — and nearly every line of it
// overwrites the live take: style, key root, scale, FX character, loop length, patch, NOTES,
// tempo, concert pitch, tuning. There was no prompt on that path and no snapshot anywhere, so
// one tap in a library list threw away whatever the body had just played, with nothing to get
// it back from. ("EVERY line" is what this said first; the first statement in the function is
// a local `let`. Small, and corrected because the standard this file applies to the source is
// that a checkable sentence be checkable-true.)
//
// THE FIX IS A RESCUE, NOT A PROMPT, and the distinction is the whole point: all a
// `.confirmationDialog` could ever do is warn. `autosaveTake()`
// already existed, already wrote the live take into the ONE reserved library slot through the
// same `ProjectStore` the Save button uses, and was wired to exactly one trigger: a scene-phase
// departure. So it covered backgrounding and covered nothing the user did inside the app.
// (⛔ This paragraph also cited the black-screen law — "would add a modifier to a presentation
// chain (CLAUDE.md, 10.76.34) that must not grow". Struck: that law is about modifiers appended
// to `EchoelStudioView.body` itself, and the row calling `open(_:)` sits inside
// `.sheet(isPresented: $showOpen) { AnyView(openSheet) }`, type-erased before the body's
// aggregate type is formed. A dialog in there would have changed nothing. The same borrowed law
// was written into the randomize and preset-delete rationales; struck in all three. It made a
// correct decision unfalsifiable, which is how a wrong one gets through next time.)
//
// Calling it here costs no PRESENTATION — no modifier, no slot — and makes the action
// reversible instead of merely announced. It is not costless as such: the call is a synchronous
// encode of the whole library plus a protected write, on the main actor, now paid on every
// open. Fine for a gesture, weighed again by any third caller.
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
//
// ⚠️ THE LARGEST LIMIT IS NOT IN THIS FILE'S REACH AT ALL, and the first version of this
// header did not name it: what the slot stores is `pianoRoll.notes` — the SOUNDING bar, not
// the arrangement. A take is `loopBars` distinct bars (default eight) which the roll cycles;
// `Project` holds one flat `notes` array, and `pianoRoll.load(_:)` clears `arrangementBars` on
// the way back in. So the recovery returns one bar in eight, and no cycling. Hand-dialled FX
// is not in it either (only `fxCharacterRaw` is saved, and `open(_:)` re-stamps every chain
// from the character). None of that is new — manual Save has the identical hole, and
// persisting the raw bars is its own task — but the slice this file guards is the one that
// SELLS the slot as a way back, so the limit belongs beside the guard, not only in the source.
// NEEDS-FOUNDER-VERIFY: compose something, open a different take from the library, then open
// the Autosave row — is the first take back, and how much of it?
//
// SCOPE. The UX/a11y audit of 2026-08-01 listed four destructive paths; this slice takes only
// the one that can lose a whole session. Three of the four are now closed — this one, the two
// preset Deletes (they snapshot and offer "Undo delete of …" in the same overflow menu, pinned
// by `DeletingAPresetIsUndoableTests`) and "Randomize timbre" (it snapshots into
// `patchBeforeSoundChange`, pinned by `RandomizeIsUndoableTests`). STILL OPEN: the video
// library's delete is a 32×32 target 10 pt from Share with all three of a row's buttons
// carrying the same VoiceOver name.
//
// ⛔ THIS PARAGRAPH WENT STALE THE MOMENT THOSE SLICES SHIPPED, and it was found stale by a
// reviewer rather than by the commits that closed its items. It still described Randomize as
// having "no snapshot" and named the state by its old spelling `patchBeforePrompt`. That is
// the trap CLAUDE.md names outright: a session reading an open-items list believes the work is
// undone and redoes it — or "re-fixes" the name back. An open-items list is part of the change
// that closes one of its items.
//
// ⛔ THOSE ARE DESCRIBED HERE RATHER THAN CITED AS "#357", because the first version of this
// paragraph pointed at that number three times and it is not findable: the slice numbers in
// this repo live in a session task list, not in GitHub, and GitHub #357 is an unrelated closed
// `_redirects` PR. A follow-up promise whose tracker a reader cannot open is not a promise.
//
// ⚠️ AND `importMIDI` WAS LISTED HERE AS A FIFTH LIVE PATH, WHICH OVERSTATES IT. It does
// replace the take, but it has NO CALLER — `midiImportPresented` has no setter, a fact the
// source states about itself and CLAUDE.md repeats. Naming it beside three reachable controls
// invites the next session to spend a slice guarding a doorless function. It belongs to the
// class only if a door ever returns.
//
// WHICH TEST GOES RED ON THE PRE-FIX SOURCE (`e0add16`), per-assertion, re-derived against
// `git show`. Test 1 emits exactly ONE failure: `open(_:)` contained no `autosaveTake()` at
// all, so the presence check fails and `return`s — the gate and order assertions never run.
// Test 2 was already green and stays green: it pins an assumption the new caller now depends
// on, not the bug. Test 3 goes red too — the caption named one trigger.
//
// ⛔ THE FIRST VERSION OF THIS PARAGRAPH CONTRADICTED ITSELF INSIDE ONE SENTENCE: "Both tests
// go red … so all three assertions of the first test fail. The second test … was already green
// and stays green." Both halves cannot hold, and the "all three" half was false besides,
// because the presence check returns early. A paragraph whose whole job is to tell the next
// session whether this guard is falsifiable has to be right about which assertion fires.
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest

final class OpeningAProjectRescuesTheLiveTakeTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let openDeclaration = "private func open(_ p: Project)"
    private static let autosaveDeclaration = "private func autosaveTake()"
    /// Opening words only — the guard asserts what the rest of the sentence must still contain,
    /// so pinning the whole caption would make every rewording a red for no reason.
    private static let captionOpening = "Kept automatically"

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
                `open(_:)` no longer calls `autosaveTake()`. Nearly every line of that function \
                overwrites the live take — style, key, scale, patch, notes, tempo, concert \
                pitch — and both doors that load a project (the Open list and `onLoadShared`) \
                run through it. Without the rescue, one tap in a library list destroys \
                whatever the body just played with nothing to get it back from. Restore the \
                call rather than adding a confirmation dialog: a prompt can only warn, never \
                undo.
                """)
            return
        }

        // ⛔ THE NEAREST ENCLOSING CONDITION, NOT "SOMEWHERE AT OR BEFORE". Two earlier
        // versions of this check were weaker in different ways: `body[..<rescue]` excluded the
        // call's own line and failed against the very commit that introduced it (gate and call
        // are ONE line), and the `body[...rescue]` that replaced it would have passed with the
        // gate fully broken — e.g. `if p.id != Project.autosaveSlotID { logSomething() }` on
        // one line and a bare `autosaveTake()` on the next. Reading backwards to the nearest
        // `if` proves the call is INSIDE the gate. Same technique as
        // `LockCueDoesNotShoveTheControlsTests`, which reached it one slice earlier.
        // ⛔ AND THE POLARITY, NOT ONLY THE NAME. Asserting that the gate MENTIONS
        // `Project.autosaveSlotID` passes unchanged on `if p.id == Project.autosaveSlotID`,
        // which is the precise inversion this guard exists to prevent — the recovery row would
        // then be overwritten with the take being discarded and nothing else would. `!=` is
        // the cheapest proof of direction that does not pin the whole expression's spelling
        // (`Project.autosaveSlotID != p.id` passes too, and should).
        let gate = body[...rescue].last { $0.contains("if ") }
        let gateText = gate?.trimmingCharacters(in: .whitespaces) ?? "missing"
        let gated = gate?.contains("Project.autosaveSlotID") == true && gate?.contains("!=") == true
        XCTAssertTrue(gated, """
            `open(_:)` calls `autosaveTake()` outside the autosave-slot gate, or with the gate \
            inverted — its nearest enclosing condition is \(gateText), which must both name \
            `Project.autosaveSlotID` and exclude it with `!=`. There is exactly ONE autosave \
            slot and `ProjectStore.save` matches by id, so opening the autosave row would \
            overwrite \
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
            `autosaveTake()` lost its `hasComposed` guard. It is what keeps the rescue from \
            firing before anything has been composed at all — on a fresh launch the flag is \
            `false`, and writing a recovery point for a session that does not exist would put \
            an empty row in the library the first time the user opens anything. \
            (⛔ An earlier version of this message argued from "`hasComposed` is set `true` \
            unconditionally by `open(_:)` and never set back", which is true and is an \
            argument AGAINST this guard's reach, not for it: after the first open the flag is \
            permanently true and only the empty-roll half below still does any work. Right \
            assertion, wrong "so".)
            """)

        XCTAssertTrue(body.contains { $0.contains("pianoRoll.notes.isEmpty") }, """
            `autosaveTake()` lost its empty-roll guard. There is ONE recovery slot: writing \
            a take with no notes into it destroys the only thing the user could have gone \
            back to, silently and with no undo. Since #357(b) this guard also protects the \
            open path — opening any project while the roll is empty would otherwise clear the \
            recovery point as a side effect of loading.
            """)
    }

    /// The Autosave section's caption names BOTH triggers — the app-departure it was written
    /// for and the open this slice added.
    ///
    /// ⚠️ THIS IS THE PART OF THE SLICE THAT REACHES THE USER. The gate above exists, in its
    /// own words, to "keep the row meaning one thing" — and the only sentence that tells anyone
    /// what the row means said "Kept automatically when you leave the app." A user reading that
    /// after this change would believe the row holds their last backgrounding when it holds the
    /// state from just before their last OPEN. Wrong in the direction that matters: they would
    /// trust it for a recovery it cannot make. A trigger added without the sentence is a lying
    /// control, which is the class this file's own source polices elsewhere.
    ///
    /// ⚠️ Honest limit: this proves the caption NAMES the open, not that it reads well. It also
    /// cannot notice a THIRD trigger being added — no source scan can. What it can do is fail
    /// the moment someone shortens the sentence back.
    func testTheAutosaveCaptionNamesBothTriggers() throws {
        let source = try codeLines(Self.studio)
        // `codeLines` is load-bearing HERE in the way its own doc describes: the ⛔ block above
        // the caption quotes the old one-trigger sentence verbatim, so an unfiltered scan would
        // find "Kept automatically" in the paragraph explaining the fix and could pass on a
        // source whose actual caption had been reverted.
        guard let caption = source.first(where: { $0.contains(Self.captionOpening) }) else {
            XCTFail("""
                The Autosave section's caption no longer starts "\(Self.captionOpening)". It is \
                the one place a user learns what that row is; if it was reworded, reword this \
                guard with it rather than deleting the pin — the sentence has to keep naming \
                every trigger that writes the slot, and there are two.
                """)
            return
        }
        // Hoisted, not interpolated inline: long `+`/expression-bearing assert messages have
        // made this bundle's own gate red once on type-check cost (#287).
        let text = caption.trimmingCharacters(in: .whitespaces)
        XCTAssertTrue(caption.contains("open"), """
            The Autosave caption names only the app-departure trigger: \(text) \
            Since the rescue in `open(_:)` the slot is ALSO written every time the user opens a \
            project, and it holds the state from just before that open — not from the last time \
            they left the app. Say both, or the row promises a recovery it does not hold.
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

    /// Lines of `path` that are not whole-line comments.
    ///
    /// ⛔ THE FIRST VERSION SAID THIS WAS "required … for a reason that does occur: the
    /// rationale block INSIDE `open(_:)`'s window names `Project.autosaveSlotID` and
    /// `autosaveTake()` in prose". There is no such block. Every comment inside `open(_:)` is
    /// about the genre clamp, `loopBars`, tempo mirroring, `applyDelaySync` and `applyTuning`;
    /// the `///` paragraph that names both tokens sits ABOVE the declaration, and
    /// `window(_:from:)` starts AT the declaration, so it is outside the window whether
    /// comments are stripped or not. `LockCueDoesNotShoveTheControlsTests` carries a ⛔ making
    /// exactly this correction about exactly this helper — written one slice earlier, in this
    /// same bundle, and copied here without its lesson.
    ///
    /// The real reasons are narrower and do hold: a future comment line containing the literal
    /// declaration string would move `firstIndex` onto a comment and drag prose into the
    /// window, and a rationale comment placed INSIDE the member could satisfy a `contains`
    /// check with text rather than code.
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
