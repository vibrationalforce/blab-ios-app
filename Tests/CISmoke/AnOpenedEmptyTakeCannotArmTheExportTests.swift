// AnOpenedEmptyTakeCannotArmTheExportTests.swift
// Echoel — #622: opening a take with zero notes must not arm the composed-only chrome.
//
// WHAT THIS GUARDS (Ultra-Audit 2026-08-19, MIDI Rank 1 — founder: "Midi Export geht
// nicht"). `open(_:)` set `hasComposed = true` UNCONDITIONALLY while `Project.notes`
// can decode empty (lossy decode drops unreadable notes). The pianokeys export tile
// enables on `hasComposed` alone, and `exportMIDI()`'s empty guard returns silently —
// so an opened empty take produced a bright tile whose tap did literally nothing,
// forever. The trap self-propagated: Save is `hasComposed`-gated too and writes
// `pianoRoll.notes`, so the empty take could be saved under a real name and re-opened.
// The fix makes open()'s flag honest: `hasComposed = !pianoRoll.notes.isEmpty` — the
// same second condition the autosave guard has carried since #204, applied at the
// third writer. The first-run explainer (rendered while `!hasComposed`) then returns
// and TELLS the player what to do, instead of a control that eats the tap.
//
// KIND (§1): SOURCE-TEXT SCAN throughout — proves the writers' shape, never device
// behaviour. That an opened empty take actually shows the explainer is a device probe.
//
// GRADING (#433, parent = the commit before #622): claim 1 is FORWARD (the honest
// spelling is written by this commit; parent has 0). Claim 2 is red on the parent for
// its named reason (three unconditional writers there, two here). Claims 3–5 are
// COUNTERWEIGHTS, green on both trees — they pin the three premises that make the fix
// mean anything (the export guard, its breadcrumb, the autosave law).
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED TRAGEND (2 of 5
// verdicts flip raw vs stripped on the worktree): the #622 comment quotes BOTH the old
// spelling (`hasComposed = true`) and the autosave guard verbatim, so the ==2 count
// and the ==1 autosave count are inflated raw — exactly the class codeOnly exists for.
//
// ⚠️ #364: a FOURTH `hasComposed = true` writer is not forbidden forever — a new
// composed-path that provably always loads notes may add one, updating the count here
// in the same commit; the failure message says so. What is forbidden silently is
// re-flattening open()'s honest spelling.

import Foundation
import XCTest

final class AnOpenedEmptyTakeCannotArmTheExportTests: XCTestCase {

    private func studioLines() throws -> [String] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent(
            "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present at \(path.path)")
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// 1 — open()'s flag is the honest spelling.
    func testOpenSetsTheFlagFromTheNotes() throws {
        let lines = try studioLines()
        XCTAssertEqual(lines.filter { $0.contains("hasComposed = !pianoRoll.notes.isEmpty") }.count,
                       1, """
            open()'s honest `hasComposed = !pianoRoll.notes.isEmpty` is gone (or \
            duplicated). Re-flattening it to `= true` re-arms the pianokeys export tile \
            for a take with zero notes — the tap then does literally nothing (#622, \
            Ultra-Audit MIDI Rank 1), and Save re-propagates the empty take.
            """)
    }

    /// 2 — exactly TWO unconditional writers remain (generate + the unreachable
    /// importMIDI, which always follows a successful import).
    func testTheUnconditionalWritersAreCounted() throws {
        let lines = try studioLines()
        XCTAssertEqual(lines.filter { $0.contains("hasComposed = true") }.count, 2, """
            the number of unconditional `hasComposed = true` writers changed. Two are \
            sanctioned: generate() (always loads the bars it just composed) and \
            importMIDI() (follows a successful import). A NEW writer must decide \
            honesty consciously — if it can run with an empty roll, it needs the \
            `!pianoRoll.notes.isEmpty` condition (the #204 autosave law); if it \
            provably cannot, update this count in the same commit and say why there.
            """)
    }

    /// 3–5 — COUNTERWEIGHTS (green on both trees): the premises the fix rests on.
    func testTheExportGuardAndItsWitnessesSurvive() throws {
        let lines = try studioLines()
        XCTAssertEqual(lines.filter { $0.contains("guard !arrangedNotes.isEmpty") }.count, 1, """
            exportMIDI()'s empty guard is gone — without it an empty roll writes a \
            zero-note MIDI file, trading the silent no-op for a silent broken file.
            """)
        XCTAssertEqual(lines.filter { $0.contains("MIDI export skipped: no notes in the roll") }.count,
                       1, """
            the skip breadcrumb is gone — it is the ONE diag-log line that names this \
            failure branch on a founder device (the Ultra-Audit's confirmation signal).
            """)
        XCTAssertEqual(lines.filter { $0.contains("guard hasComposed, !pianoRoll.notes.isEmpty") }.count,
                       1, """
            the autosave two-condition guard is gone — it is the precedent (#204) this \
            fix cites, and without it an empty take autosaves over a real one.
            """)
    }
}
