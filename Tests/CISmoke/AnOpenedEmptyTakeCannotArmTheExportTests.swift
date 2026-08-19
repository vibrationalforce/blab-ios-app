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
// The fix makes the flag honest at every loader: open() and rebalanceTake() write
// `hasComposed = !pianoRoll.notes.isEmpty` (the #204 autosave condition), importMIDI
// writes `= !placed.isEmpty` (#622b), and only generate() stays unconditional. The
// first-run explainer (rendered while `!hasComposed`) then returns and TELLS the
// player what to do, instead of a control that eats the tap.
//
// KIND (§1): SOURCE-TEXT SCAN throughout — proves the writers' shape, never device
// behaviour. That an opened empty take actually shows the explainer is a device probe.
//
// GRADING (#433, re-graded at #622b against the pre-#622 parent): claims 1 and the
// importMIDI pin are FORWARD (#622/#622b write those spellings; parent has 0 of each).
// The unconditional count is red on the parent for its named reason (three writers
// there, one here). Claims 3-5 are COUNTERWEIGHTS, green on both trees — they pin the
// premises that make the fix mean anything (the export guard, its breadcrumb, the
// autosave law — whose justification now cites its OWN defence, not open()'s shape,
// because #622 retired the old premise: see the ⛔ at autosaveTake's doc).
//
// Stripper: delegates to `SourceText.codeOnly` (#453). RE-MEASURED at #622b, still
// TRAGEND (2 of 6 verdicts flip raw vs stripped on the worktree): the #622 comment
// quotes the old spelling (`hasComposed = true`) and the autosave guard verbatim, so
// those counts are inflated raw — exactly the class codeOnly exists for.
//
// ⚠️ #364: a SECOND unconditional writer is not forbidden forever — a new
// composed-path that provably always loads notes may add one, updating the count here
// in the same commit; the failure message says so. What is forbidden silently is
// re-flattening any loader's honest spelling.

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

    /// 1 — the honest spelling at BOTH note-loading paths: open() and (since #622b,
    /// review W1) rebalanceTake() — the fader-rebake restores a full arrangement and
    /// must refresh the snapshot flag, or a rawTake-recovered take stays grey while its
    /// notes sit ready to export.
    func testTheLoadersSetTheFlagFromTheNotes() throws {
        let lines = try studioLines()
        XCTAssertEqual(lines.filter { $0.contains("hasComposed = !pianoRoll.notes.isEmpty") }.count,
                       2, """
            the honest `hasComposed = !pianoRoll.notes.isEmpty` writers changed — there \
            are TWO: open() (#622, Ultra-Audit MIDI Rank 1: re-flattening it re-arms the \
            export tile over zero notes) and rebalanceTake() (#622b: without it the \
            fader-rebake leaves the flag stale-false over a restored arrangement, and \
            Play would destroy the recovery). A third loader takes the same spelling \
            and updates this count in the same commit.
            """)
    }

    /// 2 — exactly ONE unconditional writer remains: generate(), which always loads
    /// the bars it just composed. ⛔ #622b (review W3): importMIDI's sanction rested on
    /// a false premise — a SUCCESSFUL import of a drums-only SMF yields zero melodic
    /// notes (ch10 excluded), Rank 1 verbatim through the sanctioned writer. It is now
    /// `hasComposed = !placed.isEmpty` (pinned below).
    func testTheUnconditionalWritersAreCounted() throws {
        let lines = try studioLines()
        XCTAssertEqual(lines.filter { $0.contains("hasComposed = true") }.count, 1, """
            the number of unconditional `hasComposed = true` writers changed. ONE is \
            sanctioned: generate() (always loads the bars it just composed). A NEW \
            writer must decide honesty consciously — if it can run with an empty roll, \
            it needs an emptiness condition (the #204 autosave law); if it provably \
            cannot, update this count in the same commit and say why there.
            """)
        XCTAssertEqual(lines.filter { $0.contains("hasComposed = !placed.isEmpty") }.count, 1, """
            importMIDI's honest flag (`= !placed.isEmpty`, #622b) is gone — a drums-only \
            SMF imports successfully with zero melodic notes, and `= true` there arms \
            the chrome over an empty roll the day the import door is reopened.
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
