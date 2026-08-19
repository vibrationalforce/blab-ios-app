// MonitoringCannotStrandTheEngineStoppedTests.swift
// Echoel — #625: turning live monitoring ON must never leave the whole engine stopped.
//
// WHAT THIS GUARDS (founder device report 2026-08-19, verbatim: "Es funktioniert gar
// nichts und killt den restlichen Sound auch" — monitoring produced no sound AND took
// the music with it). `setInputMonitoring(true)` raises the audio session by calling
// `AudioConfiguration.claimRecordRoute(.inputMonitoring)`, which ends in
// `setCategory(.playAndRecord)` + `setActive(true, options: .notifyOthersOnDeactivation)`.
// iOS may STOP a running `AVAudioEngine` underneath that re-activation. The engine's
// running state was read TWELVE LINES BELOW that call, so in exactly that case
// `wasRunning` latched false — and the restart at the bottom of the branch is guarded
// `if wasRunning`. Nothing ever started the engine again: the monitor chain was wired
// onto a stopped engine, `isInputMonitoring` was set true, and the method returned
// SUCCESS. Total silence, music included, nothing logged.
//
// #611 does NOT cover it. Its rollback is for `start()` THROWING on the
// `wasRunning == true` path; here the flag was already false, so no start was attempted
// and no catch could fire. Two adjacent repairs, two different failure modes — do not
// let one be deleted as redundant with the other.
//
// THE FIX IS AN ORDERING, which is why this guard is an ORDER check and not a presence
// check (#367): the read moved ABOVE the claim. Every token involved already existed on
// the parent, so every COUNT here is green on both trees — only the order discriminates.
// A presence-only guard would have been green on the broken tree.
//
// KIND (§1): SOURCE-TEXT SCAN. `AudioEngine` is `@MainActor` and its monitor path needs
// a live `AVAudioSession` + `AVAudioEngine` on device hardware, so this bundle cannot
// drive it (the `AutosaveSlotTests` limit, same shape). That the founder's music keeps
// playing when he arms the monitor is a DEVICE probe and nothing here can stand in for
// it — this pins the one line whose position caused it.
//
// GRADING (#433, against the pre-#625 parent `1d4153b`): claim 1 (the order) is the
// single FORWARD assertion and is RED on the parent for its named reason — the read sat
// below the claim there. Claims 2-3 are COUNTERWEIGHTS, green on both trees: they pin
// that there is still exactly ONE claim site and ONE running-state read inside this
// method, because the order check is meaningless if either is duplicated (two reads and
// the check would pass on whichever pair happened to be ordered correctly).
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED **PROPHYLAKTISCH**
// (0 of 8 verdicts flip raw vs stripped, on EITHER tree).
//
// ⛔ The first version of this header claimed "TRAGEND (2 of 4)" and reasoned it from
// the fact that the #625 comment discusses both needles in prose. It does — but as
// `claimRecordRoute` and "the running state", never as `claimRecordRoute(.inputMonitoring)`
// or `let wasRunning = masterEngine.isRunning`, so neither full needle matches and no
// count is inflated. **This is the SECOND consecutive slice where I asserted TRAGEND
// without measuring it** (#623 did the same, one slice earlier, and its header carries
// the same retraction). Recording the repeat rather than only the fact: the tempting
// shortcut is that a comment which TALKS ABOUT a needle must contain it, and prose
// almost always names a symbol in shorter form than the assertion does. The rule that
// survives: the stripper column is read off the transcription, never argued from the
// diff.
//
// ⚠️ #364: restructuring is not forbidden. Claiming the route somewhere else entirely,
// or replacing the pause/start dance with `restartOrDegrade`, is legal — move the
// needles in the same commit. What is forbidden silently is putting the running-state
// read back below the session claim.

import Foundation
import XCTest

final class MonitoringCannotStrandTheEngineStoppedTests: XCTestCase {

    private func engineLines() throws -> [String] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent(
            "Sources/Echoelmusic/Audio/AudioEngine.swift")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present at \(path.path)")
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// TWO unique anchors → the span between them (#621b: a fixed window ages as the law
    /// comments around it grow, and #625 added ~20 lines of them right here).
    private func monitorOnSpan(_ lines: [String]) throws -> ArraySlice<String> {
        let start = "func setInputMonitoring(_ on: Bool) -> Bool"
        let end = "log.audio(\"Input monitoring ON (gain"
        let s = lines.indices.filter { lines[$0].contains(start) }
        XCTAssertEqual(s.count, 1, """
            `\(start)` is no longer unique in AudioEngine — re-anchor before trusting \
            this check (#408).
            """)
        let e = lines.indices.filter { lines[$0].contains(end) }
        XCTAssertEqual(e.count, 1, """
            end anchor `\(end)…` is no longer unique in AudioEngine — re-anchor (#408).
            """)
        guard let si = s.first, let ei = e.first, si < ei else {
            throw XCTSkip("the setInputMonitoring ON span is gone — reported by the anchors above")
        }
        return lines[si ... ei]
    }

    /// 1 — THE ORDER. The running-state read must come BEFORE the session claim.
    func testTheRunningStateIsReadBeforeTheSessionClaim() throws {
        let w = Array(try monitorOnSpan(try engineLines()))
        guard let read = w.firstIndex(where: { $0.contains("let wasRunning = masterEngine.isRunning") }),
              let claim = w.firstIndex(where: { $0.contains("claimRecordRoute(.inputMonitoring)") })
        else {
            return XCTFail("""
                the monitoring ON path no longer contains both a \
                `let wasRunning = masterEngine.isRunning` read and a \
                `claimRecordRoute(.inputMonitoring)` call — counted separately below; if \
                the route claim moved out of this method on purpose, re-anchor this file \
                in the same commit.
                """)
        }
        XCTAssertLessThan(read, claim, """
            the engine's running state is read AFTER the session claim again — that IS \
            #625, the founder's "es killt den restlichen Sound auch". The claim ends in \
            setCategory(.playAndRecord) + setActive(true), which can STOP a running \
            AVAudioEngine; read afterwards, `wasRunning` latches false, the `if \
            wasRunning` restart at the end of this branch never fires, and the method \
            returns SUCCESS with the whole engine — music included — stopped and nothing \
            logged. #611's rollback cannot catch it: that one only fires when `start()` \
            THROWS on the wasRunning == true path.
            """)
    }

    /// 2-3 — COUNTERWEIGHTS (green on both trees): the order above only means something
    /// while each of these appears exactly once inside the ON path.
    func testTheOrderCheckHasExactlyOneOfEachToOrder() throws {
        let w = try monitorOnSpan(try engineLines())
        XCTAssertEqual(w.filter { $0.contains("claimRecordRoute(.inputMonitoring)") }.count, 1, """
            the monitoring ON path claims the record route more than once (or not at \
            all). The order check above compares against the FIRST claim, so a second \
            one could sit above the running-state read and pass while the real claim \
            still stops the engine unobserved.
            """)
        XCTAssertEqual(w.filter { $0.contains("let wasRunning = masterEngine.isRunning") }.count, 1, """
            the monitoring ON path reads the engine's running state more than once (or \
            not at all). Two reads make the order check vacuous — it would pass on \
            whichever pair happened to be ordered correctly while the read that actually \
            feeds the `if wasRunning` restart still sat below the claim.
            """)
    }
}
