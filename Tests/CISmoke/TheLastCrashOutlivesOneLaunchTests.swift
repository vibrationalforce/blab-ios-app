// TheLastCrashOutlivesOneLaunchTests.swift
// Echoel — #916. A crashed run used to live for exactly ONE launch.
//
// THE FINDING, measured rather than assumed. `EchoelCrashLog.begin()` opens the diag file
// with `O_TRUNC`, so the file on disk holds exactly one run. The run that crashed survives
// only in `previousSession`, in memory, for the length of the launch that follows it:
//   · launch A crashes  → the file holds A, plus the signal handler's CRASH marker.
//   · launch B starts   → `previousSession` = A, and the file is truncated. A is now in RAM.
//   · launch C starts   → `previousSession` = B. A is gone from disk AND from memory.
// So the evidence exists for one launch. Seven device logs into the `isInputConnToConverter`
// family and still without a named trigger, that is an expensive default: a user who
// dismisses the auto-surfaced sheet — or whose crash was a background kill, which
// `looksLikeUnseenCrash` deliberately does NOT surface — loses it for good.
//
// WHAT THIS GUARDS, and what it deliberately does not:
//   · it does NOT re-decide what "ended badly" means. That is `looksLikeUnseenCrash`, and
//     `ACleanExitIsNotACrashTests` already pins its semantics. Re-asserting them here would
//     be a second definition of one decision (#416); claim 1 checks only that retention ASKS
//     that function, by driving one case from each of its two arms.
//   · it does NOT check that the file is really written. `begin()` touches the real Documents
//     container; no test in this bundle can reach it. The pure half (`crashToRetain`,
//     `diagnosticsExport`) is driven end to end, and the impure half is pinned by READING the
//     source for the two facts that make the write survivable: it happens after the crash
//     handlers are installed, and it has a reachable door.
//
// ⭐ THE DOOR CLAIM IS THE LOAD-BEARING ONE (claim 6). A retained file that no surface renders
// is not a feature, it is a file — the #454 shape, applied to a diag log. The one always-
// reachable door is the "Diagnostics" row under Save & Export, and before #916 it rendered
// `currentLog()`, i.e. THIS run only: after a crash it showed the recovery launch and not the
// crash. If someone reverts that call, retention goes silently invisible and every other
// claim in this file stays green.
//
// ⚠️ TWELVE PROSE HOMES / FOURTEEN MENTIONS CITE `currentLog()`, not seven.
// ⛔ The first draft of this header said SEVEN and called them all benign — measured with
// `git grep -n "currentLog()" -- Sources Tests memory` and wrong in the flattering direction,
// in a paragraph that advertised itself as "read, not guessed". The six it missed included
// the STRONGEST counter-example: `TheShareDoorReportsWhatItCannotSendTests` said, inside a
// guard-failure message in this same blocking bundle, "which is what that row renders".
// The homes split into two kinds:
//   · SEVEN mentions in six files state directly what the ROW renders (`PulseCue`,
//     `MusicStyle`, `MultipeerSession`, `AStalledAcquisitionSaysSoTests`,
//     `TheShareDoorReportsWhatItCannotSendTests`, and `memory/LEDGER_COUNTS.md` twice).
//     Those became FALSE with #916 and are corrected in the same push, as a separate commit
//     so each diff stays readable (#456).
//   · SEVEN mentions in six files reason about `currentLog()` itself — that it reads a whole
//     log into one String, or that `os_log`/the in-memory ring is not it. Those are facts
//     about that function and still hold; they are untouched on purpose. What #916 does owe
//     them is an acknowledgement that the COMBINED export got bigger, and that is written
//     down at `EchoelCrashLog.lastCrashLog()`.
//
// ⚠️ HONEST GRADING (#433/#464) — THIS FILE DOES NOT COMPILE AGAINST THE PARENT, so NO
// assertion here has a verdict there. That is not "green there". Hand-transcribed instead,
// over all 28 checks (23 `XCTAssert*` + 5 `XCTUnwrap`, counted, not estimated):
//   · REGRESSIONS: 2 — both in `testTheRetainedCrashHasAReachableDoor`. The presence check
//     for `diagnosticsExport()` and the absence check for
//     `DiagReport(text: EchoelCrashLog.currentLog())` are each red on the parent for exactly
//     the reason their names give. ⛔ The first draft called the absence check a
//     COUNTERWEIGHT; it is not — the parent contains that exact string, so it fails there.
//     Booking a regression as a counterweight is the flattering-direction defect §3 names.
//   · ANCHOR ABSENCE: 0 as a category — the whole file is absent from the parent, which is
//     the line above and must not be counted twice.
//   · FORWARD guards: 24 — every pure-function check drives a symbol this commit creates.
//   · COUNTERWEIGHTS: 1 in principle (`capture < install` in
//     `testTheRetentionRunsAfterTheCrashHandlersAreInstalled`, true on either tree) — but it
//     is unreachable on the parent, because the `XCTUnwrap` of the retention call above it
//     throws first. Stated as it is rather than booked as a clean counterweight.
//   · Plus 1 fixture sanity check (`oversized.count > budget`), which asserts about the test
//     fixture and not about the code.
//
// ⚠️ AND IT IS NOT COMPILE-VERIFIED BY THE CHEAP GATE. `Xcode Compile Check` builds `Sources/`
// alone, and `Package.swift` declares only `EchoelmusicTests`; `Tests/CISmoke` is compiled by
// the XcodeGen test target inside the pipeline that reports `failure` on every push (#396).
// A compile error in this file shows up only in that job's steps.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheLastCrashOutlivesOneLaunchTests: XCTestCase {

    // MARK: - Fixtures

    private var banner: String { "1785340620.000  launch v10.79.431 (2547)\n" }
    private var started: String { "1785340625.100  " + EchoelCrashLog.startTappedMarker + "\n" }
    private func scene(_ old: String, _ new: String) -> String {
        "1785340629.599  " + EchoelCrashLog.sceneTransition(from: old, to: new) + "\n"
    }
    private var crashed: String { "1785340631.000  " + EchoelCrashLog.crashMarker + " SIGABRT (abort)\n" }

    // MARK: - 1. Retention asks the existing question, it does not invent a new one

    func testACleanRunIsNotRetained() {
        let clean = banner + started + scene("active", EchoelCrashLog.backgroundPhase)
        XCTAssertNil(EchoelCrashLog.crashToRetain(from: clean), """
            A run that reached Start and then went to background is a CLEAN exit, and \
            `looksLikeUnseenCrash` says so. Retaining it would fill the retained slot with \
            the last ordinary session and overwrite a real crash that came before it — the \
            opposite of what #916 is for.
            """)
        XCTAssertNil(EchoelCrashLog.crashToRetain(from: banner), """
            A launch that never reached Start and never crashed carries nothing worth keeping.
            """)
    }

    func testACrashedRunIsRetained() {
        XCTAssertNotNil(EchoelCrashLog.crashToRetain(from: banner + started + crashed), """
            A log carrying the signal handler's CRASH marker is exactly the case #916 exists \
            for. If this is nil, retention has stopped asking `looksLikeUnseenCrash`.
            """)
        XCTAssertNotNil(EchoelCrashLog.crashToRetain(from: banner + started), """
            The second arm of `looksLikeUnseenCrash`: reached Start, never left the \
            foreground, no marker — a jetsam/watchdog death that beats the signal handler. \
            That arm is the ONLY evidence such a death leaves, so retention must honour it.
            """)
    }

    // MARK: - 2. The TAIL survives, not the head

    func testAnOversizedLogKeepsItsLaunchLineAndItsEnd() throws {
        let budget = EchoelCrashLog.retainedCrashCharacterBudget
        let launchLine = "1785340620.000  launch v10.79.431 (2547)\n"
        let early = "1785340620.500  UNIQUE-EARLY-MARKER first init step\n"
        let filler = String(repeating: "1785340621.000  init a: audio core\n",
                            count: (budget / 34) + 200)
        let tail = "1785340631.000  " + EchoelCrashLog.crashMarker + " UNIQUE-TAIL-MARKER\n"
        let oversized = launchLine + early + filler + tail
        XCTAssertGreaterThan(oversized.count, budget, "fixture must exceed the budget to test it")

        let kept = try XCTUnwrap(EchoelCrashLog.crashToRetain(from: oversized))

        XCTAssertEqual(kept.count, budget, """
            An oversized log must come out at exactly the budget, in CHARACTERS. \
            `String.suffix(_:)` and `String.count` count `Character`s, which is why the \
            constant is named `retainedCrashCharacterBudget` and not a byte budget — the FILE \
            on disk may well be larger once German or a marker glyph is in it.
            """)
        XCTAssertTrue(kept.hasPrefix(launchLine), """
            THE FIRST LINE OF THE CRASHED RUN MUST SURVIVE THE TRIM. It is the build banner, \
            and a retained crash is read days or weeks later on a different build — triage \
            step 1 is "is the fix you are verifying IN this build?". ⛔ The first draft of \
            #916 was a plain `suffix(budget)`, which cut exactly that line off exactly the \
            logs big enough to need trimming.
            """)
        XCTAssertTrue(kept.contains(EchoelCrashLog.retainedCrashTrimMarker), """
            A trimmed log must SAY it was trimmed. Without the marker the launch line sits \
            directly above a step from minutes later and reads as one continuous run.
            """)
        XCTAssertTrue(kept.contains("UNIQUE-TAIL-MARKER"), """
            THE END IS WHY THE FILE IS WORTH SAVING. The crash marker, the signal handler's \
            backtrace and the last rungs of whichever ladder was climbing all sit there.
            """)
        XCTAssertFalse(kept.contains("UNIQUE-EARLY-MARKER"), """
            The middle must actually have been dropped. If an early step survives, the budget \
            is not being applied and the retained file is unbounded — the exact concern two \
            other files already raise about `currentLog()` reading a whole log into one String.
            """)
    }

    func testAShortLogIsKeptWhole() throws {
        let short = banner + started + crashed
        let kept = try XCTUnwrap(EchoelCrashLog.crashToRetain(from: short))
        XCTAssertEqual(kept, short, """
            Below the budget nothing is cut. A trim that fires on every log would silently \
            drop the build banner from the one line triage reads first.
            """)
    }

    // MARK: - 3. The export composes, and the ordinary case is untouched

    func testWithNothingRetainedTheExportIsUnchanged() {
        let current = banner + started
        XCTAssertEqual(EchoelCrashLog.diagnosticsExport(current: current, retainedCrash: ""),
                       current, """
            BYTE-IDENTICAL, heading included — i.e. absent. Almost every export is this case, \
            and a heading for a section that is not there is noise in the artefact the \
            founder pastes.
            """)
    }

    func testTheExportStartsWithThisRunAndThenNamesTheRetainedCrash() {
        let current = banner + started
        let retained = "1785000000.000  " + EchoelCrashLog.crashMarker + " SIGABRT (abort)\n"
        let out = EchoelCrashLog.diagnosticsExport(current: current, retainedCrash: retained)

        XCTAssertTrue(out.hasPrefix(current), """
            THE ORDER IS NOT COSMETIC. The first line of a run names the build, and triage \
            step 1 is "is the fix you are verifying IN this build?". A pasted export has to \
            answer that in its first line, so this run comes first, exactly.
            """)
        XCTAssertTrue(out.contains(EchoelCrashLog.retainedCrashHeader), """
            Without the heading the two runs read as one, and a reader would date the crash \
            to the current session. The heading is a shared constant so the writer here and \
            any reader of a pasted log cannot spell it differently (#416).
            """)
        XCTAssertTrue(out.hasSuffix(retained), """
            The retained crash must arrive whole and last — nothing may be appended after it, \
            or the end of the log stops being the end of the crash.
            """)
    }

    // MARK: - 4. Source claims: the write is survivable, and it has a door

    func testTheRetentionRunsAfterTheCrashHandlersAreInstalled() throws {
        let src = SourceText.codeOnly(try read("Sources/Echoelmusic/Core/EchoelCrashLog.swift"))
        let capture = try XCTUnwrap(src.range(of: "previousSession = "),
                                    "the capture of the previous session moved or was renamed")
        let install = try XCTUnwrap(src.range(of: "installHandlers()"),
                                    "`installHandlers()` moved or was renamed")
        let retain = try XCTUnwrap(src.range(of: "crashToRetain(from: previousSession)"),
                                   "the retention call in `begin()` moved or was renamed")

        XCTAssertTrue(capture.lowerBound < install.lowerBound, """
            The previous session must be captured before anything else happens — it is read \
            from the file that the very next line truncates.
            """)
        XCTAssertTrue(install.lowerBound < retain.lowerBound, """
            THE PLACE IS PART OF THE DECISION, exactly like a ladder rung standing before its \
            call (#862b). Retention writes a file; if that fault is what kills the launch, \
            the crash handlers have to already be installed or the death is silent — and a \
            silent death inside the code that exists to preserve deaths is the worst possible \
            failure mode for this slice.
            """)
    }

    func testTheRetainedCrashHasAReachableDoor() throws {
        let view = SourceText.codeOnly(try read("Sources/Echoelmusic/Studio/EchoelStudioView.swift"))
        XCTAssertTrue(view.contains("DiagReport(text: EchoelCrashLog.diagnosticsExport())"), """
            A RETAINED FILE THAT NOTHING RENDERS IS NOT A FEATURE, IT IS A FILE — the #454 \
            shape applied to a diag log. The always-reachable "Diagnostics" row under Save & \
            Export is the one door that can still hand a crash over days later; before #916 \
            it rendered `currentLog()`, i.e. the RECOVERY launch and not the crash.
            """)
        XCTAssertFalse(view.contains("DiagReport(text: EchoelCrashLog.currentLog())"), """
            The row must not be reverted to this run only. ⛔ The first draft asserted \
            `count == 1` on the needle `DiagReport(text: EchoelCrashLog.` instead — which \
            would have gone RED on an ordinary, correct simplification: the auto-surface site \
            passes a local (`DiagReport(text: prev)`), and inlining it to \
            `EchoelCrashLog.previousSession` makes the count 2 while the door is still right. \
            A guard that reddens on correct work is the defect (#364), so the claim is now a \
            presence plus a targeted absence and counts nothing.
            """)
    }

    // MARK: - 5. A weak log must not evict a strong one

    func testAnUnmarkedRunCannotEvictARetainedCrash() {
        let marked = "1785000000.000  " + EchoelCrashLog.crashMarker + " SIGSEGV (bad memory access)\n"
        let unmarked = banner + started
        XCTAssertFalse(EchoelCrashLog.shouldReplaceRetained(candidate: unmarked, existing: marked), """
            THE SLOT HOLDS ONE FILE AND "NEWEST WINS" IS THE WRONG RULE ACROSS TWO STRENGTHS \
            OF EVIDENCE. `looksLikeUnseenCrash` has two arms and only the first needs a \
            marker; arm 2 ("reached Start, did not end in background") is also true of a \
            device reboot, a battery death or a run stopped from Xcode. Without this rule a \
            SIGSEGV retained WITH its backtrace is destroyed two launches later by a log that \
            has no marker, no backtrace and nothing to triage.
            """)
    }

    func testAMarkedCrashAlwaysWinsAndUnmarkedReplacesUnmarked() {
        let marked = "1785000000.000  " + EchoelCrashLog.crashMarker + " SIGABRT (abort)\n"
        XCTAssertTrue(EchoelCrashLog.shouldReplaceRetained(candidate: marked, existing: marked), """
            Newest crash wins among crashes — the founder iterates on builds, and the crash \
            worth reading is the one from the build in hand.
            """)
        XCTAssertTrue(EchoelCrashLog.shouldReplaceRetained(candidate: banner + started,
                                                           existing: banner + started), """
            COUNTERWEIGHT to the rule above: when neither side carries a marker the newest \
            still wins. The policy must protect a marked log, not freeze the slot forever \
            after the first unmarked one lands in it.
            """)
        XCTAssertTrue(EchoelCrashLog.shouldReplaceRetained(candidate: marked, existing: ""), """
            An empty slot always accepts — the first retention must not be refused.
            """)
    }

    // MARK: - Helpers

    private func read(_ relative: String) throws -> String {
        let url = try repoRoot().appendingPathComponent(relative)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`, two levels up).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                Sources/ is not reachable from this file's path — the checkout layout changed. \
                Skipping rather than failing: this guard reads source text, and an unreadable \
                tree is not evidence that the code is wrong.
                """)
        }
        return root
    }
}
