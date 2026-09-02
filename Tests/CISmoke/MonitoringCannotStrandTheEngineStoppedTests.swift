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
// GRADING (#433 / §3): claim 1 (the order, vs the pre-#625 parent `1d4153b`), claim 4
// (the exit guarantee, vs `79fbbc6`) and claims 5-6 (#628's pause-before-claim and its
// returning claim-failure, vs `8ded9cf`) are **REGRESSIONS** — each red on its own parent
// for the reason its name gives. Claim 5's second assertion (format read AFTER the claim)
// is a COUNTERWEIGHT, green on every tree. Claims 2-3 are COUNTERWEIGHTS, green on both trees: they pin that
// there is still exactly ONE claim site and ONE running-state read inside this method,
// because the order check is meaningless if either is duplicated.
//
// ⛔ The first version called claim 1 "the single FORWARD assertion … RED on the parent
// for its named reason" — a sentence that refutes itself, because §3 defines FORWARD as
// an assertion that **could never have been red** (it drives a symbol the commit creates,
// so the file does not even compile there). Red-for-its-named-reason is the definition of
// REGRESSION. The error ran in the CONSERVATIVE direction — it understated the guard —
// but §3 is the taxonomy this directory grades by, and the flattering direction is only
// half the rule. ⚠️ The same mislabel is in the #622 and #623 headers; it is corrected
// there as each is next touched rather than in a sweep that would edit files this slice
// has no other business in.
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED **PROPHYLAKTISCH**
// (0 of 13 verdicts flip raw vs stripped, on EITHER tree — the denominator is every
// `XCTAssert`/`XCTFail` from `engineLines()` to the end of the file, re-derivable in
// one command. #623b paid for hand-counting this twice; the RULE is the durable part,
// the digit is not.)
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

    /// 5 — REGRESSION (#628, founder screenshot "Monitoring could not start — try again"):
    /// the engine is stopped before the session claim, and the format read after it.
    ///
    /// ⛔ #976 — THIS CLAIM HAD BEEN FAILING ON A CORRECT TREE, and neither needle could ever
    /// match again. It looked for `if wasRunning { masterEngine.pause() }` — #823 turned that
    /// into `stop()` on this path, and said so in a comment right above the line — and for
    /// `let inFmt = input.inputFormat(forBus: 0)`, which is **zero occurrences file-wide**;
    /// the declaration is `var inFmt`. So the `guard` fell through to `XCTFail` on every run
    /// that reached it. That is the #367 defect in the blocking bundle: a guard must be able
    /// to fail for the reason it NAMES, and this one could only fail for a reason about
    /// itself. Found by a reviewer looking at the neighbouring pin, not by the suite — which
    /// is the #445 point: a per-test verdict does not reliably reach the job log.
    ///
    /// ⚠️ THE LAW IS UNCHANGED AND THAT IS WHY THIS IS A RE-ANCHOR AND NOT A DELETION: whatever
    /// pauses-or-stops the engine must do so BEFORE the claim, and the input format must be
    /// read AFTER it. Only the spellings moved.
    func testTheEngineIsPausedBeforeTheSessionClaim() throws {
        let w = Array(try monitorOnSpan(try engineLines()))
        guard let pause = w.firstIndex(where: { $0.contains("if wasRunning { masterEngine.stop() }") }),
              let claim = w.firstIndex(where: { $0.contains("claimRecordRoute(.inputMonitoring)") }),
              let fmt = w.firstIndex(where: { $0.contains("inFmt = input.inputFormat(forBus: 0)") })
        else {
            return XCTFail("""
                the monitoring ON path lost one of: the pause line, the \
                `claimRecordRoute(.inputMonitoring)` call, or the \
                `let inFmt = input.inputFormat(forBus: 0)` read. All three carry #628's \
                ordering; if the method was restructured, re-anchor in the same commit.
                """)
        }
        XCTAssertLessThan(pause, claim, """
            the engine is no longer paused BEFORE the session claim (#628). `inputNode`'s \
            format is only meaningful once the session is active in a record-capable \
            category, and a RUNNING engine straddling a category change is exactly the \
            state where `inputFormat(forBus: 0)` reads 0 Hz — which lands in the format \
            guard whose message then blamed the microphone for a session problem. Every \
            sibling graph-mutating site in this file pauses before it touches anything.
            """)
        // COUNTERWEIGHT — green on both trees: the format read stays AFTER the claim.
        XCTAssertLessThan(claim, fmt, """
            the input format is read BEFORE the session claim — it cannot be valid there, \
            because the session is still `.playback` and the input node has no hardware.
            """)
    }

    /// 6 — REGRESSION (#628): a throwing claim RETURNS instead of falling through into a
    /// format read that cannot succeed, so a session failure is no longer reported to the
    /// user as a microphone problem.
    func testAFailedClaimDoesNotFallThroughIntoTheFormatRead() throws {
        let w = Array(try monitorOnSpan(try engineLines()))
        guard let claim = w.firstIndex(where: { $0.contains("claimRecordRoute(.inputMonitoring)") }),
              let fmt = w.firstIndex(where: { $0.contains("let inFmt = input.inputFormat(forBus: 0)") }),
              claim < fmt
        else { throw XCTSkip("claim/format anchors gone — reported by claim 5") }
        let between = w[claim ..< fmt]
        XCTAssertTrue(between.contains { $0.contains("return false") }, """
            the failing-claim branch no longer returns (#628). Falling through sends a \
            session-upgrade failure into the format guard, whose message blamed the \
            MICROPHONE — the wrong diagnosis on the founder's screen and in the diag log.
            """)
        XCTAssertTrue(between.contains { $0.contains("restoreEngineIfStranded(") }, """
            the failing-claim exit does not restore a stopped engine. It is a \
            category-changing exit like every other one in this method (#625b), and it \
            now returns EARLY — so it needs the guarantee more, not less.
            """)
    }

    /// TWO unique anchors → the span between them (#621b: a fixed window ages as the law
    /// comments around it grow, and #625 added ~20 lines of them right here).
    private func monitorOnSpan(_ lines: [String]) throws -> ArraySlice<String> {
        let start = "func setInputMonitoring(_ on: Bool) -> Bool"
        let end = "isInputMonitoring = true"   // #625b: structural, not a log string
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

    /// 4 — REGRESSION (#625b, review 2a+2b): the EXIT GUARANTEE. The order fix alone
    /// covered the ON path's MAIN exit and left two doors open — the ON path's
    /// format-guard exit, which does no graph work and simply returned, and the OFF path,
    /// which mutates the same session category with no running-state handling at all.
    /// Either could return with the whole app silent. File-wide on purpose: the OFF
    /// branch sits outside the ON span the other claims use.
    func testEveryCategoryChangingExitRestoresAStoppedEngine() throws {
        let lines = try engineLines()
        // ⛔ #631: this asserted THREE and the tree has FOUR — the assertion was RED from
        // #628 until #631, invisibly, because the blocking bundle's per-test verdicts do not
        // reliably reach the job log (#445). #628 added a third caller (the failed session
        // claim) and moved neither this count nor `RecordRouteOwnershipTests`'. The failure
        // message below had ALREADY written the rule — "a new exit … needs its own call and
        // this count updated in the same commit" — so this is not a missing rule, it is a
        // rule the author of the new exit did not read. That is the argument for the count
        // being here at all.
        // ⛔ #958b: FOUR again, red inside the commit that made it wrong — #958 added the
        // rate-guard exit and moved neither this count nor `RecordRouteOwnershipTests`'. Same
        // pair, same mechanism, one cycle after the #631 note above wrote the rule down.
        // ⛔ #976: FIVE, AND THE COMMIT THAT MADE IT SIX WAS #975 — the THIRD time in this
        // file, after #631 (three→four) and #958b (four again). The new exit is the ON path's
        // SESSION-CONFIGURE guard: `at: "session never configured"`. And this time the local
        // checker did not help either — `scripts/count-pins.py` printed 0 RED across the whole
        // commit, because it reads two syntactic shapes and this pin is a third
        // (`lines.filter { $0.contains(…) }.count`, not `occurrences(of:)`). A tool that says
        // "a clean run is never a census" in its own footer said exactly that, and I read the
        // number instead of the footer.
        // ⛔ #982: AND #976 RAISED THE NUMBER IN THE ASSERTION AND LEFT ITS OWN MESSAGE
        // SAYING "FIVE occurrences … the declaration plus FOUR callers" — beside a pin of 6,
        // ever since (no number here: a commit distance is a date, #818). The failure message
        // is a THIRD home of the same count (#456), and
        // it is the home a reader sees FIRST, because it only ever prints when the pin breaks:
        // whoever next re-counts would have been told the wrong expectation by the guard that
        // caught them. A repair goes into every home, and a message that states a number is a
        // home. Both words corrected here; the enumeration below always listed five callers.
        XCTAssertEqual(lines.filter { $0.contains("restoreEngineIfStranded(") }.count, 6, """
            the exit-guarantee call sites changed. SIX occurrences are expected in \
            STRIPPED source: the declaration plus FIVE callers — the ON path's failed \
            session claim (#628: the claim used to only log and fall through into a format \
            read that cannot succeed), the ON path's format-guard exit (review 2a: that exit \
            does no graph work, so it returned with the music dead while the only visible \
            line blamed microphone permission), the ON path's RATE guard (#958: the \
            session cannot meet the master graph's rate, so the monitor refuses rather \
            than connecting a converter onto the input edge and aborting), the ON path's \
            SESSION-CONFIGURE guard (#975: the claim was being made on a session that was \
            never configured, whose lowering path is jammed by `guard isSessionConfigured`) \
            and the OFF \
            path (review 2b: \
            `releaseRecordRoute` lowers the category the same way, and it sits on the \
            recovery hot path `start()` → `rearmInputMonitoring` → OFF). A new exit that \
            mutates the session category needs its own call and this count updated in the \
            same commit.
            """)
        XCTAssertTrue(lines.contains { $0.contains("restartOrDegrade(after: exit)") }, """
            the exit guarantee no longer hands over to `restartOrDegrade` — that is the \
            file's ONE honest handover: it restarts, and if even that fails it raises \
            `degraded` so `AudioDegradedRow` owns the silence instead of nobody owning \
            it. A bare `try? masterEngine.start()` here would trade a reported failure \
            for an unreported one.
            """)
    }
}
