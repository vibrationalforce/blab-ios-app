// TheRunThatCausedSafeModeReachesTheExportTests.swift
// Echoel — #955/#955b. Blocking bundle. **END-TO-END BEHAVIOUR** for claims 1–9 and 11–12
// (`Tests/CISmoke/CLAUDE.md` §1): every one drives the real `EchoelCrashLog` statics, which are pure,
// `public`-reachable and Foundation-only, over logs built from the SHIPPED marker constants
// rather than hand-typed strings. Claim 10 is the one SOURCE-TEXT SCAN and says so.
//
// ⭐ THE DEFECT IS A FOUNDER-LOG FINDING, not a theory. The v10.79.433 export opens with
//
//     LaunchGuard: SAFE MODE (prior launch did not confirm healthy) — unconfirmed streak 3
//
// — two earlier launches never confirmed healthy — and carries NOTHING from either of them.
// That is not an oversight in the export; it is the exact COMPLEMENT of what retention keeps.
// `looksLikeUnseenCrash` has two arms: an explicit `CRASH` marker, or "reached Start and did
// not end backgrounded". **A launch that dies before `startup 4/4` cannot satisfy the second
// arm** — the user has not tapped Start, the app has not finished starting — and satisfies
// the first only if a handler got a marker written first. So the runs that CAUSE Safe Mode
// are precisely the runs nothing keeps, and the counter's own evidence is the one thing
// missing from the file the founder actually shares.
//
// ⚠️ THE DESIGN DECISION THIS FILE PINS IS A NON-CHANGE. `looksLikeUnseenCrash` is NOT
// widened, and claim 6 is what stops a later slice from "simplifying" it that way. That
// predicate has a SECOND consumer — `EchoelStudioView`'s auto-surfacing crash sheet — so
// widening it changes two features at once, one of them a sheet that opens in the founder's
// face unasked. #955 adds evidence to an export he chooses to share and opens nothing.
//
// ⚠️ HONEST GRADING (§3), EPOCH 1 — #955. **23 assertions at the time** (counted in Python over lines whose first
// token is `XCTAssert`, written out rather than looped — a loop hides its own arithmetic
// and has cost a grading in this bundle three times; my own first draft of this header
// said 17). This file names `unconfirmedRunToAttach`,
// `withUnconfirmedRun`, `unconfirmedRunHeader`, `trimToBudget`, `confirmedHealthyMarker`,
// `recoveryScreenClearedMarker` and `launchLinePrefix` — **ALL created by this same commit**,
// so **the file does not compile against the parent and NO assertion has a verdict there**
// (#488: do not read that as "green on its own tree"). It was hand-transcribed instead —
// every predicate reimplemented in Python and driven over the nine logs below, against the
// parent, which has no attach path at all and therefore answers "nothing attached" to all
// nine. **0 red on the worktree.**
//   · That makes claims 1 and 9 the FIX (the run is attached, under a header), and claims
//     2–8 and 10 COUNTERWEIGHTS in the strict #343 sense: they pin the four refusals and the
//     budget rule that make the attach mean something rather than fill every export.
//   · Booking "nine logs newly answered" as nine catches would be the flattering direction —
//     it is ONE capability that did not exist, reported many times (#486).
//
// ⚠️ EPOCH 2 — #955b, the same day. The mandatory reviewer found the gate REFUSING the
// founder's own Safe-Mode run: `armForRiskyStartup()` re-raises the counter AFTER a confirm
// or a clear, so #955's two order-blind `contains` checks refused "Safe Mode → Continue →
// died in the risky startup" — the exact sequence in his v10.79.433 export
// (`counter cleared` → `user left SAFE MODE` → `re-arming`). Claims 11 and 12 are new,
// `counterEndedSettled(in:)` replaces the two checks, and claims 2 and 4 carry the qualifier
// #955 stated as unconditional fact.
//   · **30 assertion sites** (Python, lines whose first token is `XCTAssert`; was 23).
//   · Transcribed both gates over ten logs: the two re-armed runs flip **nil → ATTACH**
//     (2 red on #955's logic, and they are the blocker); the eight counterweights answer
//     identically on both, including the `re-arm not needed` sibling that claim 12 exists for.
//   · `counterEndedSettled` and `rearmMarker` are created by this commit, so once again the
//     file does not compile against its parent and #488 applies unchanged.
//
// ⚠️ STRIPPER (§2): `SourceText.codeOnly` runs in claim 10 only. **PROPHYLACTIC — 0 of 3
// verdicts flip**, measured raw vs. stripped: no doc block in `EchoelmusicApp.swift` quotes
// the three constant NAMES today. It stays because these files document what they forbid,
// and that is exactly where a raw scan starts reading an explanation as the code.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheRunThatCausedSafeModeReachesTheExportTests: XCTestCase {

    // MARK: - logs built from the SHIPPED constants, never hand-typed (#416)

    private var launch: String { EchoelCrashLog.launchLinePrefix + "10.79.433 (2551)" }

    private func run(_ lines: String...) -> String {
        ([launch] + lines).joined(separator: "\n")
    }

    private var confirmedStudio: String {
        EchoelCrashLog.confirmedHealthyMarker + " (studio) — streak 1"
    }
    private var confirmedOnboarding: String {
        EchoelCrashLog.confirmedHealthyMarker + " (onboarding) — streak 1"
    }
    private var backgrounded: String {
        EchoelCrashLog.sceneTransition(from: "inactive", to: EchoelCrashLog.backgroundPhase)
    }

    /// claim 1 (THE FIX) — a launch that started and never confirmed healthy is attached.
    /// This is the founder's streak, reproduced: startup rungs, then nothing.
    func testARunThatNeverConfirmedHealthyIsAttached() {
        let died = run("startup 1/4: audio session + graph",
                       "startup 2/4: attaching voices")
        let attached = EchoelCrashLog.unconfirmedRunToAttach(from: died)
        XCTAssertNotNil(attached, """
            A run that launched, climbed part of the startup ladder and never reached \
            `\(EchoelCrashLog.confirmedHealthyMarker)` is not attached to the export. That is \
            exactly the run that raises LaunchGuard's counter, and the founder's v10.79.433 \
            export reported `unconfirmed streak 3` with no evidence of any of them.
            """)
        XCTAssertEqual(attached, died, """
            The attached text is not the run itself. Under the budget nothing may be cut — \
            the trim rule is claim 8's subject, not this one's.
            """)
    }

    /// claim 2 (COUNTERWEIGHT) — a run that reached the studio UI and survived is NOT
    /// attached. It reset the counter; attaching it would put a healthy run in every export.
    ///
    /// ⚠️ THE REFUSAL IS CONDITIONAL, and #955 stated it here as unconditional. A confirm only
    /// settles the counter when nothing RE-RAISES it afterwards — see claim 11. This fixture
    /// carries no re-arm line, which is why it still reads as settled.
    func testAHealthyStudioRunIsNotAttached() {
        XCTAssertNil(EchoelCrashLog.unconfirmedRunToAttach(
            from: run("startup 4/4: core ready — instrument live", confirmedStudio)), """
            A run that confirmed healthy is being attached. It contributed nothing to any \
            streak, so it explains nothing and would appear in every export forever.
            """)
    }

    /// claim 3 (COUNTERWEIGHT) — **and the one that catches a needle matching only half.**
    /// #915 deliberately made the studio and onboarding confirm lines DISJOINT (one used to
    /// be a strict superstring of the other). `confirmedHealthyMarker` is their common
    /// prefix; a marker that accidentally carried `(studio)` would silently attach every
    /// fresh-install run that confirmed on onboarding instead.
    func testAHealthyOnboardingRunIsNotAttachedEither() {
        XCTAssertNil(EchoelCrashLog.unconfirmedRunToAttach(
            from: run(confirmedOnboarding)), """
            A run that confirmed healthy on ONBOARDING is being attached. The confirm marker \
            has narrowed to one of the two disjoint spellings (#915) — a fresh install now \
            reports a failure it did not have.
            """)
        XCTAssertTrue(confirmedStudio.hasPrefix(EchoelCrashLog.confirmedHealthyMarker)
                      && confirmedOnboarding.hasPrefix(EchoelCrashLog.confirmedHealthyMarker), """
            The two confirm lines no longer share `confirmedHealthyMarker` as a prefix, so \
            the marker cannot mean "a UI was reached" any more. Re-derive it from both \
            writers in `EchoelmusicApp` before changing either.
            """)
        XCTAssertFalse(confirmedStudio.contains(confirmedOnboarding)
                       || confirmedOnboarding.contains(confirmedStudio), """
            The studio and onboarding confirm lines are no longer disjoint — one contains the \
            other, the exact defect #915 repaired.
            """)
    }

    /// claim 4 (COUNTERWEIGHT) — a Safe-Mode run that CLEARS the counter and stops there never
    /// contributes to a streak. Attaching it would explain nothing and would nest the
    /// recovery screen's own log inside the next export.
    ///
    /// ⚠️ "AND STOPS THERE" IS THE WHOLE QUALIFIER, and #955 did not have it: tapping Continue
    /// re-arms the counter on the SAME run, which is the founder's own sequence and is claim
    /// 11's subject. This fixture ends at the clear line.
    func testASafeModeRecoveryRunIsNotAttached() {
        XCTAssertNil(EchoelCrashLog.unconfirmedRunToAttach(
            from: run(EchoelCrashLog.recoveryScreenClearedMarker + " (one-shot)")), """
            A run that cleared the counter on the recovery screen is being attached. It \
            raised no streak — it ENDED one — so it is not evidence for anything.
            """)
    }

    /// claim 5 (COUNTERWEIGHT) — a clean exit is not a failure. Same subtraction
    /// `looksLikeUnseenCrash`'s own second arm already makes (`ACleanExitIsNotACrashTests`).
    func testARunThatEndedInTheBackgroundIsNotAttached() {
        XCTAssertNil(EchoelCrashLog.unconfirmedRunToAttach(
            from: run("startup 1/4: audio session + graph", backgrounded)), """
            A run that ended in the background is being attached. The user put the app away \
            before startup finished; that is an exit, not a death, and treating it as one \
            would attach a previous run to a large share of ordinary exports.
            """)
    }

    /// claim 6 (COUNTERWEIGHT) — **the non-change this file exists to pin.** A run retention
    /// already keeps must NOT be attached a second time, and the way that is achieved is by
    /// READING `looksLikeUnseenCrash`, never by widening it (it also drives the
    /// auto-surfacing crash sheet).
    func testARetainedCrashIsNotAttachedTwice() {
        let crashed = run("startup 2/4: attaching voices",
                          EchoelCrashLog.crashMarker + " SIGABRT (abort)")
        XCTAssertNotNil(EchoelCrashLog.crashToRetain(from: crashed), """
            Retention no longer keeps a marked crash — that is a bigger regression than this \
            slice's subject, and claim 6 below would then pass vacuously (#367).
            """)
        XCTAssertNil(EchoelCrashLog.unconfirmedRunToAttach(from: crashed), """
            A run that retention ALREADY keeps is also being attached, so it appears twice in \
            one export under two different headers. The gate is a read of \
            `looksLikeUnseenCrash`; if that predicate were widened instead, the auto-surfacing \
            crash sheet in `EchoelStudioView` would change too — two features from one edit.
            """)
    }

    /// claim 7 (COUNTERWEIGHT) — no vacuous attach. Without the launch-line test an empty or
    /// unreadable previous file passes every NEGATIVE check by vacuity and is attached as
    /// nothing under a header that promises evidence.
    func testAnEmptyOrHeaderlessPreviousRunIsNotAttached() {
        XCTAssertNil(EchoelCrashLog.unconfirmedRunToAttach(from: ""), """
            An empty previous session is being attached. `previousSession` is "" whenever the \
            file could not be read — file protection, or the computed `fileURL` landing in a \
            different container between two launches.
            """)
        XCTAssertNil(EchoelCrashLog.unconfirmedRunToAttach(from: "some text with no banner"), """
            A text with no launch line is being attached. Without that test every negative \
            check above is satisfied by vacuity.
            """)
    }

    /// claim 8 (COUNTERWEIGHT) — the budget rule is SHARED with retention (`trimToBudget`,
    /// one definition, #416) and it keeps the launch line, marks the cut, and keeps the tail.
    /// The head matters because a retained run is read days later on a different build, and
    /// triage step 1 is "is the fix I am verifying IN this build?".
    func testAnOversizedRunKeepsItsLaunchLineAndItsTail() {
        let filler = String(repeating: "x", count: EchoelCrashLog.retainedCrashCharacterBudget)
        let tail = "startup 2/4: attaching voices"
        let big = run(filler, tail)
        let attached = EchoelCrashLog.unconfirmedRunToAttach(from: big)
        let text = attached
        XCTAssertNotNil(attached, "an oversized unconfirmed run is not attached at all.")
        XCTAssertTrue(text?.hasPrefix(launch) ?? false, """
            The trimmed run lost its launch line. A crash that cannot be dated to a build is \
            the one thing triage cannot start from — the defect #916's first draft shipped.
            """)
        XCTAssertTrue(text?.contains(EchoelCrashLog.retainedCrashTrimMarker) ?? false, """
            The trimmed run does not say that its middle was cut, so a reader cannot tell a \
            short run from a truncated one.
            """)
        XCTAssertTrue(text?.hasSuffix(tail) ?? false, """
            The trimmed run lost its TAIL. The end is where the death is; a head-only slice \
            keeps the least useful part.
            """)
        XCTAssertLessThanOrEqual(text?.count ?? .max,
                                 EchoelCrashLog.retainedCrashCharacterBudget, """
            The trimmed run is over budget. The export already carries the current run and a \
            retained crash; a third unbounded block is what the share sheet cannot afford.
            """)
    }

    /// claim 9 (THE FIX, composition) — the attach is labelled, and it is a no-op when there
    /// is nothing to attach. An export that grows a blank header on every launch is worse
    /// than one that grows nothing.
    func testTheAttachIsLabelledAndOtherwiseANoOp() {
        let base = "current run"
        XCTAssertEqual(EchoelCrashLog.withUnconfirmedRun(base, unconfirmedRun: nil), base, """
            Composing with nothing changed the export. Every ordinary launch would carry a \
            header promising evidence that is not there.
            """)
        XCTAssertEqual(EchoelCrashLog.withUnconfirmedRun(base, unconfirmedRun: ""), base,
                       "An EMPTY attach still changed the export — same defect, one case over.")
        let composed = EchoelCrashLog.withUnconfirmedRun(base, unconfirmedRun: "earlier run")
        XCTAssertTrue(composed.hasPrefix(base), """
            The current run is no longer first. `diagnosticsExport`'s own rule is that the \
            FIRST line names the build in hand; an attach that leads would break triage step 1.
            """)
        XCTAssertTrue(composed.contains(EchoelCrashLog.unconfirmedRunHeader), """
            The attached run carries no header, so a reader cannot tell where the current run \
            ends and an earlier one begins — two runs read as one timeline.
            """)
    }

    /// claim 10 (SOURCE-TEXT SCAN, 5 assertions — written out, because the loop below hides
    /// three of them) — the WRITERS use the constants. This is the
    /// #650 protection and the only reason the reader can be trusted: those three lines are
    /// emitted in `EchoelmusicApp` and read here, two files apart, and a marker only one side
    /// spells right fails SILENTLY — the attach simply never happens and nothing goes red.
    func testTheWritersSpellTheMarkersOnce() throws {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let app = SourceText.codeOnly(
            try String(contentsOf: root.appendingPathComponent(
                "Sources/Echoelmusic/EchoelmusicApp.swift"), encoding: .utf8))

        for (needle, what) in [
            ("EchoelCrashLog.confirmedHealthyMarker", "the two confirm lines"),
            ("EchoelCrashLog.recoveryScreenClearedMarker", "the recovery-screen clear line"),
            ("EchoelCrashLog.rearmMarker", "the re-arm line (#955b)")
        ] {
            XCTAssertTrue(app.contains(needle), """
                \(what) no longer use `\(needle)`. A raw literal there and the constant here \
                are two spellings of one decision (#416): the reader stops matching, the \
                attach silently stops happening, and no test goes red. #650 is this repo's \
                paid-for instance of exactly that.
                """)
        }
        XCTAssertEqual(app.components(separatedBy: "EchoelCrashLog.confirmedHealthyMarker").count - 1,
                       2, """
            There are no longer exactly TWO confirm writers. #915 split them on purpose \
            (studio and onboarding, disjoint); if one was deleted the launch counter now has \
            a path that reaches a UI and never resets, and every later export attaches a run \
            that was fine.
            """)
        XCTAssertEqual(app.components(separatedBy: "EchoelCrashLog.rearmMarker").count - 1, 1, """
            There is no longer exactly ONE re-arm writer. That line is what `counterEndedSettled` \
            reads to tell "Safe Mode → Continue → died" apart from "Safe Mode → Continue → fine"; \
            without it in the log the gate falls back to refusing the founder's own sequence, \
            which is the #955b blocker returning by the back door.
            """)
    }

    /// claim 11 (THE #955b FIX, END-TO-END) — **a confirm or a clear does not settle the
    /// counter if something RE-RAISES it afterwards.** This is the founder's own v10.79.433
    /// sequence: the recovery screen clears the counter, he taps Continue, `armForRiskyStartup()`
    /// puts it back to 1 — and if that startup then dies, the run DID leave a streak behind.
    /// #955 asked `previous.contains(confirmedHealthyMarker)` and refused exactly this run, so
    /// the founder would have met a Safe-Mode screen and an export that stayed silent about it.
    func testAReArmedRunIsAttachedEvenThoughItSettledTheCounterEarlier() {
        let continuedFromSafeMode = run(
            EchoelCrashLog.recoveryScreenClearedMarker + " (one-shot)",
            "user left SAFE MODE",
            EchoelCrashLog.rearmMarker + " — streak was 0 before the risky startup",
            "startup 2/4: attaching voices")
        XCTAssertNotNil(EchoelCrashLog.unconfirmedRunToAttach(from: continuedFromSafeMode), """
            The Safe-Mode → Continue → died run is not attached. `armForRiskyStartup()` raised \
            the counter AFTER the clear line, so this run is precisely what the NEXT Safe-Mode \
            screen will be complaining about — and it is the sequence in the founder's own log.
            """)
        let confirmedThenReArmed = run(
            confirmedOnboarding,
            EchoelCrashLog.rearmMarker + " — streak was 0 before the risky startup",
            "startup 1/4: audio session + graph")
        XCTAssertNotNil(EchoelCrashLog.unconfirmedRunToAttach(from: confirmedThenReArmed), """
            A run that confirmed healthy on onboarding and was then RE-ARMED is not attached. \
            The confirm reset the counter; the re-arm put it back. Only the LAST counter line \
            decides whether the run left a streak (`counterEndedSettled`).
            """)
        XCTAssertFalse(EchoelCrashLog.counterEndedSettled(in: continuedFromSafeMode), """
            `counterEndedSettled` says this run ended settled. It ends with a re-arm, so the \
            helper has gone order-blind again — the exact shape of the #955b blocker.
            """)
        XCTAssertTrue(EchoelCrashLog.counterEndedSettled(in: run(confirmedStudio)), """
            A run whose last counter line is a confirm no longer reads as settled, so every \
            healthy launch would now be attached to every export.
            """)
    }

    /// claim 12 (COUNTERWEIGHT, and the reason the marker is spelled `re-arming`) — the SAME
    /// branch writes `"LaunchGuard: re-arm not needed — streak already N"` when the counter is
    /// NOT 0. A marker of `"LaunchGuard: re-arm"` would match BOTH, and the "not needed" case
    /// is a run whose counter was never settled in the first place. The `-ing` is load-bearing;
    /// this is #915's disjointness lesson applied to a second pair of lines.
    func testTheReArmMarkerDoesNotMatchTheReArmNotNeededLine() {
        let notNeeded = "LaunchGuard: re-arm not needed — streak already 2"
        XCTAssertFalse(notNeeded.contains(EchoelCrashLog.rearmMarker), """
            `rearmMarker` now matches the "re-arm not needed" line too. Both spellings live in \
            one `if/else` in `EchoelmusicApp`; a marker matching both cannot tell a raise from \
            a no-op, and `counterEndedSettled` would read a settled run as re-raised.
            """)
        XCTAssertTrue(EchoelCrashLog.rearmMarker.hasPrefix("LaunchGuard:"), """
            `rearmMarker` lost the `LaunchGuard:` shape. `LaunchGuardSmokeTests` accepts this \
            constant as a breadcrumb precisely because it writes that shape into the exported \
            log; without it a reader can no longer find the state change by the same word.
            """)
    }
}
