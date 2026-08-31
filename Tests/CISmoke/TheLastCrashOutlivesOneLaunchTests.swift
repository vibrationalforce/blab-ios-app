// TheLastCrashOutlivesOneLaunchTests.swift
// Echoel — #916 + #917. A crashed run used to live for exactly ONE launch, and the
// recovery screen showed the wrong one.
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
//     be a second definition of one decision (#416); the two retention claims check only that
//     it ASKS that function, by driving one case from each of its two arms.
//   · it does NOT check that the file is really written. `begin()` touches the real Documents
//     container; no test in this bundle can reach it. The pure half (`crashToRetain`,
//     `diagnosticsExport`) is driven end to end, and the impure half is pinned by READING the
//     source for the two facts that make the write survivable: it happens after the crash
//     handlers are installed, and it has a reachable door.
//
// ⭐ THE LOAD-BEARING CLAIMS ARE THE TWO DOOR ONES — `testTheRetainedCrashHasAReachableDoor`
// and `testTheRecoveryScreenUsesTheComposedText`, named rather than numbered because a
// position in a list is a date. A retained file that no surface renders
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
// ⚠️ HONEST GRADING (#433/#464) — against the REAL parent, `fdca482`, which already carries
// #916 and #916b. ⛔ THE FIRST DRAFT OF THIS BLOCK WAS GRADED AGAINST THE PRE-#916 TREE while
// calling it "the parent", and every error ran in the flattering direction: it claimed 4
// regressions where 2 were counterweights (the parent's Diagnostics row ALREADY calls
// `diagnosticsExport()`), claimed "the whole file is absent from the parent" when the file
// exists there, listed seven new symbols when five of them are the parent's, and its four
// categories summed to 38 against a stated total of 37. §0 defines the parent as
// `git show <parent>:<path>` — measured that way this time.
//
// The file still does not compile against `fdca482`: it names `recoveryExport` in code, which
// #917 creates. So NO assertion has a verdict there. That is not "green there".
// Hand-transcribed over all 38 checks — 33 `XCTAssert*` + 5 `XCTUnwrap` bindings, counted with
//   grep -cE '^ +XCTAssert' <file>                     → 33
//   grep -cE '^ +let .* = try XCTUnwrap\(' <file>       → 5
// (both anchored at line start so they cannot match this header quoting them — ⛔ the previous
// recipe, a bare `grep -cE "try XCTUnwrap\("`, returned 8 against a prose number of 7, i.e. an
// executable command contradicting the sentence beside it):
//   · REGRESSIONS: 4 — `testTheRecoveryScreenUsesTheComposedText` (2: the parent's SafeModeView
//     reads `previousSession` raw) and `testTheAutoSurfacedSheetUsesTheSameComposition` (2: the
//     parent's auto-surface passes `prev`). Each is red there for the reason its name gives.
//   · ANCHOR ABSENCE: 0. The one assertion that would have been an absence — an ordering pin on
//     `retainedCrashAtLaunch` — was DELETED in #917b, see the retraction further down.
//   · FORWARD guards: 6 — the four `recoveryExport` behaviour methods. They drive a symbol #917
//     creates and could never have been red.
//   · COUNTERWEIGHTS: 27 — every `crashToRetain` / `shouldReplaceRetained` /
//     `diagnosticsExport(current:retainedCrash:)` check, the retention-ordering method, and the
//     two Diagnostics-row door checks. Green on both trees, and per §343 that is the content.
//   · Plus 1 fixture sanity check (`oversized.count > budget`), about the fixture, not the code.
//   4 + 6 + 27 + 1 = 38.
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

    // MARK: - 6. Safe Mode shows the run worth sharing, not the recovery launch (#917)

    func testTheRecoveryScreenAddsTheOlderCrashWhenTheLastRunCarriesNoMarker() {
        let recoveryRun = banner + "1785340621.000  ui branch: SAFE MODE recovery screen\n"
        let older = "1785000000.000  " + EchoelCrashLog.crashMarker + " SIGABRT (abort)\n"
        let out = EchoelCrashLog.recoveryExport(previous: recoveryRun, retainedCrash: older)

        XCTAssertTrue(out.hasPrefix(recoveryRun), "the run just before us still comes first")
        XCTAssertTrue(out.contains(EchoelCrashLog.retainedCrashHeader), """
            THE DOCUMENTED, FOUNDER-OBSERVED CASE: once the self-healing net catches every \
            other launch the device alternates "Safe Mode or black screen", and on a \
            safe-mode launch the run immediately before it is the RECOVERY launch — short, \
            markerless, useless. The screen that says "share this with the developer" was \
            handing over exactly that run while the real abort sat in the retained file.
            """)
    }

    func testTheRecoveryScreenDoesNotPrintTheSameRunTwice() {
        let crashedRun = banner + started + crashed
        XCTAssertEqual(EchoelCrashLog.recoveryExport(previous: crashedRun, retainedCrash: crashedRun),
                       crashedRun, """
            A marked run must come back untouched. Appending anything under a heading that \
            calls it an EARLIER run would invent a second occurrence of one crash. \
            ⛔ This message used to say "`begin()` has just retained the very run this screen \
            is showing" — a state the shipped code cannot produce, and flatly contradicted by \
            the deleted ordering claim twenty lines above it (#425, inside one file). What the \
            assertion really drives is the gate's FIRST clause, and that is worth driving: it \
            is the whole reason duplication is impossible.
            """)
    }

    func testTheRecoveryScreenAddsNothingWhenTheKeptLogHasNoMarkerEither() {
        let plain = banner + started
        XCTAssertEqual(EchoelCrashLog.recoveryExport(previous: plain, retainedCrash: plain),
                       plain, """
            COUNTERWEIGHT: the gate is not "append whenever something is kept". Two markerless \
            logs stacked under a crash heading would claim a crash that neither of them \
            recorded. ⛔ The simpler gate `!looksLikeUnseenCrash(previous)` was rejected for \
            the opposite failure — it would have HIDDEN a retained SIGABRT behind a markerless \
            arm-2 run (reboot, battery, Xcode stop), i.e. in the one case worth showing it.
            """)
    }

    // ⛔ A CLAIM STOOD HERE AND WAS DELETED, NOT REPAIRED (#917b).
    // `testTheLaunchSnapshotIsTakenBeforeThisLaunchCanOverwriteIt` pinned that
    // `retainedCrashAtLaunch = lastCrashLog()` precedes the retention block, and its message
    // said the non-duplication property rested on that order. A review disproved it by case
    // analysis: a retained log is a textual slice of some run, so a marker in the slice
    // implies the marker was in that run, and `recoveryExport`'s gate then declines on its
    // FIRST clause. In every reachable state the composed text is byte-identical whichever
    // side of the block the snapshot is taken. The assertion therefore could not fail for the
    // reason its name gave (#367's mirror case) — and it WOULD have failed for a correct edit:
    // binding the read to a local and reusing it reddens a needle anchored on the call
    // spelling (#364). Non-duplication is pinned where it actually lives, by
    // `testTheRecoveryScreenDoesNotPrintTheSameRunTwice` below.

    func testTheRecoveryScreenUsesTheComposedText() throws {
        let view = SourceText.codeOnly(try read("Sources/Echoelmusic/Studio/SafeModeView.swift"))
        XCTAssertTrue(view.contains("EchoelCrashLog.recoveryExport()"), """
            The recovery screen must render the composed text. Reading `previousSession` \
            directly puts it back to showing whatever ran last — which, on the alternating \
            safe-mode launches this exists for, is the recovery screen itself.
            """)
        XCTAssertFalse(view.contains("priorLog = EchoelCrashLog.previousSession\n"), """
            And it must not go back to the raw value. ⛔ TWO DRAFTS OF THIS NEEDLE WERE TOO \
            WIDE AND A DRIVEN MUTANT PROVED IT: anchored on `= EchoelCrashLog.previousSession` \
            it also matched an unrelated new line such as \
            `let raw = EchoelCrashLog.previousSession.count`, i.e. it reddened on an ordinary \
            correct edit — #364, and the draft's own message claimed the opposite. The needle \
            names THIS PROPERTY's assignment AND ends at the line break, so a correct future \
            line such as `= EchoelCrashLog.previousSessionDigest` cannot trip it either — a \
            third narrowing, after a review pointed out that the second was still a PREFIX \
            while its message claimed exactness. Comments cannot trip it: the scan runs on \
            `SourceText.codeOnly`.
            """)
    }

    func testAnUnreadablePreviousSessionStillLeadsWithText() {
        let older = "1785000000.000  " + EchoelCrashLog.crashMarker + " SIGABRT (abort)\n"
        let out = EchoelCrashLog.recoveryExport(previous: "", retainedCrash: older)
        XCTAssertTrue(out.hasPrefix(EchoelCrashLog.retainedCrashHeader), """
            `previousSession` can be empty — file protection, or the COMPUTED `fileURL` \
            resolving to a different container between two launches. Composed naively the \
            text then OPENS with two blank lines and no build banner, on the screen that \
            insists elsewhere the first line must name the build. Lead with the heading; the \
            retained run carries its own launch line directly beneath it.
            """)
        XCTAssertFalse(out.hasPrefix("\n"), "an export must not begin with blank lines")
    }

    func testTheAutoSurfacedSheetUsesTheSameComposition() throws {
        let view = SourceText.codeOnly(try read("Sources/Echoelmusic/Studio/EchoelStudioView.swift"))
        XCTAssertFalse(view.contains("DiagReport(text: prev)"), """
            The AUTO-SURFACED sheet is the more commonly reached of the two crash surfaces, \
            and #917's argument applies to it word for word: a markerless arm-2 death \
            (reboot, battery, watchdog) surfaced a run with nothing to triage while a real \
            abort sat retained one manual tap away. Fixing only the Safe Mode screen would \
            have left the slice's own reasoning half-applied, with nothing saying why.
            """)
        XCTAssertTrue(view.contains("DiagReport(text: EchoelCrashLog.recoveryExport())"), """
            COUNTERWEIGHT to the line above: it must use the SAME composition, not some \
            second spelling of "previous run plus retained crash" (#416). `recoveryExport` \
            returns `previous` untouched whenever it carries its own marker, so the ordinary \
            crash path through this sheet is unchanged.
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
