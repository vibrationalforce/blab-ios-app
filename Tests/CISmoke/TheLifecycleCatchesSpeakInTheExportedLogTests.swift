// TheLifecycleCatchesSpeakInTheExportedLogTests.swift
// Echoel — #968. Blocking bundle. **SOURCE-TEXT SCAN** (`Tests/CISmoke/CLAUDE.md` §1) over the
// three files that own the audio graph's lifecycle: `AudioConfiguration.swift`,
// `AudioEngine.swift`, `MicrophoneManager.swift`, each through `SourceText.codeOnly`. Nothing
// here starts an engine — every failure covered below is an AVFAudio throw, which a bundle test
// cannot stage honestly.
//
// ⭐ WHAT IS NEW HERE IS THE QUESTION, NOT THE LAW. #862b and #964 each applied the #859 rule
// once, at the call site that had just bitten someone: a lifecycle step must speak in the file
// the founder EXPORTS, and `log.audio` is `os_log`, which `echoel_diag.log` does not carry. This
// slice asked the rule the other way round — *which lifecycle `catch` blocks on the audio path
// still speak only to os_log?* — and got six, in three files. Two of them are the expensive
// kind: after a failed reactivate (a phone call ends) and after a failed restart (a media-server
// reset), AUDIO IS DEAD, the app raises its degraded banner, and the exported log said nothing
// at all about why. That is the v428 triage stall reproduced on two more paths.
//
// ⚠️ THE SIX ARE NOT ONE KIND, and the wording is graded on purpose (claims 1-6 read the exact
// literals, so the grading is enforced, not described):
//   · the run did NOT recover → ALL-CAPS `FAILED`: `session: interruption FAILED`,
//     `session: media reset FAILED`, `engine: restart after … FAILED`, `mic: stop FAILED`.
//   · the run CONTINUES → lowercase detail, never a terminator: `session: lower — the buffer
//     re-assert was refused`, `engine: stop — the session refused to deactivate`. Writing
//     `FAILED` on those two would mark a healthy run as a finding — the #937 class, an
//     instrument telling a triager the opposite of what happened.
//
// ⛔ AND THIS PASSAGE SHIPPED WITH TWO FALSE SENTENCES, BOTH CORRECTED BY #970 IN THE COMMIT
// THAT MADE THE FIRST ONE TRUE. It said ALL-CAPS was used *"because `diag-ladder.py` reads that
// word as a finding"* and named all four sites. **`diag-ladder.py` reads a terminal word only
// after a KNOWN LADDER PREFIX**, and its eight are `mic: start` · `mic: stop` · `off` · `on` ·
// `session: configure` · `session: raise` · `start` · `startup`. Three of the four are none of
// those, so only `mic: stop FAILED` was machine-read — measured, not argued: a log holding a
// complete `session: configure` ladder plus the other three printed `✅ Every ladder that
// appears reached its last step`, exit 0. The source comment at `AudioConfiguration.swift:1008`
// said the honest thing the whole time; the always-read header said the opposite. #970 added
// `unowned_failures`, so the sentence is true NOW — and it is rewritten anyway, because a claim
// that happens to have become true is not the same as one that was checked.
// ⛔ The SECOND false sentence was the label. `mic: stop FAILED` does not leave AUDIO DEAD — the
// master engine plays on and the mic is off; what survives is a HELD RECORD ROUTE. It is
// ALL-CAPS all the same, while `engine: stop — the session refused to deactivate` leaves an
// equally wrong state and is lowercase. So "audio dead" was never the discriminator; "the run
// did not recover from this" is, and that is what the two bullets now say.
//
// ⭐ AND ONE OF THE SIX ONLY BECAME LEGIBLE ONE COMMIT EARLIER. `mic: stop FAILED` follows a
// COMPLETE `mic: stop` 1..3 ladder: the mic stopped while the RECORD ROUTE is still held, which
// is the state the `isInputConnToConverter` family lives in. Before #967 a non-benign terminator
// after the last rung still printed `✅ done`, so this line would have been written into a log
// that reported the run as clean. #967 made it a finding; #968 makes it exist.
//
// ⚠️ WHAT DID **NOT** CHANGE, and claims 7-8 are here to keep it that way: not one AVFAudio call
// was added, removed, reordered or re-argued, and the downgrade path still does NOT call
// `setActive(false)` — deactivating there is the shipped silence bug #855 exists to prevent.
// This slice adds lines to the exported log. It must not become an audio-graph change.
//
// ⚠️ NOT DEVICE-VERIFIED, and it cannot be from here. What is proven is that the six reasons are
// WRITTEN to the breadcrumb sink. NEEDS-FOUNDER-VERIFY: after a phone call that leaves Echoel
// silent, does the exported log now end at `session: interruption FAILED — could not
// reactivate (…)` or `engine: restart after interruption FAILED — …` instead of at a rung with
// nothing after it?
//
// DRIVEN (Python transcription of `SourceText.codeOnly` plus each predicate, against
// `git show <rev>:<each of the three files>`):
//
//   | tree              | RED | of |
//   |-------------------|-----|----|
//   | dcde4ba (#964)    | 6   | 8  |
//   | 7f7b303 (#967)    | 6   | 8  |
//   | 2e4eacf (#968)    | 0   | 8  |
//   | worktree (#970)   | 0   | 8  |
//
// ⚠️ #970's added crumb-uniqueness assertion does NOT move any count — re-driven on all four
// trees. On a parent it fires as "occurs zero times", i.e. the same fact claims 1-6 already
// name, so the guard still fails for its named reason (#367) rather than gaining a second one.
//
// Claims 7-8 (the counterweights) are GREEN on all three trees, which is what a counterweight
// should be — #961's header records the day one was written as a composite and went red on the
// parent for the WRONG reason (#367).
//
// AND EACH CLAIM WAS SHOWN TO FAIL FOR ITS OWN REASON, by mutating the worktree BY LINE INDEX
// (#967's lesson: a mutation needs a unique anchor exactly like a guard does — a `replace(…, 1)`
// against a repeated string lands on the wrong site, looks applied, and grades nothing):
//
//   downgrade crumb deleted                          → c1
//   interruption crumb moved below its os_log        → c2
//   media-reset crumb deleted                        → c3
//   stop crumb moved below its os_log                → c4
//   restart crumb loses `FAILED`                     → c5
//   mic crumb numbered `mic: stop 3/3 FAILED`        → c6
//   one `onMediaServicesReset?()` call site removed  → c7
//   `setActive(false)` added to the downgrade        → c8
//
// Eight mutations, eight single-claim reds, ZERO spillover — which is the useful half of the
// result, because it says each claim is anchored on something the others do not read.

import XCTest
@testable import Echoelmusic

final class TheLifecycleCatchesSpeakInTheExportedLogTests: XCTestCase {

    private static let config = "Sources/Echoelmusic/Audio/AudioConfiguration.swift"
    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"
    private static let mic = "Sources/Echoelmusic/MicrophoneManager.swift"

    private func source(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return SourceText.codeOnly(
            try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8))
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// The shared shape of claims 1-6: the breadcrumb exists, its os_log partner still exists,
    /// and the breadcrumb stands FIRST.
    ///
    /// ⚠️ The order is not cosmetic and it is not the #859 "rung before its call" rule either —
    /// this pair sits INSIDE a `catch`, so the failure has already happened. It is about the
    /// sink: `EchoelCrashLog.breadcrumb` is an unbuffered `write(2)` into the exported file,
    /// `log.audio` takes an os_log lock. If the process dies between them, the ordering decides
    /// whether the founder's file carries the reason or not.
    ///
    /// ⚠️ The os_log partner is asserted UNIQUE, so `range(of:)` cannot silently compare against
    /// a second copy elsewhere in the file (#408).
    private func assertCrumbLeadsItsOSLog(_ code: String,
                                          crumb: String,
                                          osLog: String,
                                          why: String,
                                          file: StaticString = #filePath,
                                          line: UInt = #line) {
        XCTAssertEqual(occurrences(of: osLog, in: code), 1, """
            `\(osLog)…` is no longer the single os_log line of this catch, so this claim can no \
            longer anchor on it. Re-anchor before trusting the verdict (#408) — a needle that \
            cannot match makes a negative assertion vacuously true (#926).
            """, file: file, line: line)
        // ⛔ #970 — THE UNIQUENESS WAS ASSERTED ON ONE SIDE ONLY. `range(of:)` returns the FIRST
        // hit, so a crumb literal duplicated into an earlier catch would let the order check
        // below pass on the wrong pair — the guard would read as green while the catch it names
        // is silent. All six are unique today; that is what makes this cheap to state and
        // pointless to omit.
        XCTAssertEqual(occurrences(of: crumb, in: code), 1, """
            `\(crumb)…` no longer occurs exactly once. The order check below compares the FIRST
            match, so a second copy makes it grade a pair this claim is not about (#408).
            """, file: file, line: line)
        guard let c = code.range(of: crumb), let o = code.range(of: osLog) else {
            XCTFail("""
                \(why)

                The line is gone from the exported log: `\(crumb)…` was not found. `log.audio` \
                is os_log and `echoel_diag.log` does not carry it (#859), so this failure would \
                again be invisible in the file the founder hands over.
                """, file: file, line: line)
            return
        }
        XCTAssertTrue(c.lowerBound < o.lowerBound, """
            \(why)

            The breadcrumb now stands AFTER its os_log partner. The breadcrumb is an unbuffered \
            write into the exported file; os_log takes a lock. Write the reason first, so a \
            process that dies between the two still leaves it behind (#859/#968).
            """, file: file, line: line)
    }

    // MARK: - 1. The downgrade says when the buffer re-assert was refused

    func testTheDowngradeSaysWhenTheBufferReAssertWasRefused() throws {
        assertCrumbLeadsItsOSLog(
            try source(Self.config),
            crumb: "EchoelCrashLog.breadcrumb(\"session: lower — the buffer re-assert was refused",
            osLog: "log.audio(\"IO-buffer re-assert refused on downgrade",
            why: """
                The downgrade no longer reports a refused IO-buffer re-assert in the exported \
                log. Audio CONTINUES here, so this is a detail and not a terminator — but #855 \
                shipped that re-assert because a refused one leaves the next monitoring session \
                on whatever duration the OS picks, the founder-measured 23 ms against a 10.7 ms \
                ask. A latency complaint with no line in the log is unanswerable.
                """)
    }

    // MARK: - 2. A failed interruption recovery is not silent

    func testTheFailedInterruptionRecoveryIsNotSilent() throws {
        assertCrumbLeadsItsOSLog(
            try source(Self.config),
            crumb: "EchoelCrashLog.breadcrumb(\"session: interruption FAILED — could not reactivate",
            osLog: "log.audio(\"Failed to reactivate audio session:",
            why: """
                AUDIO IS DEAD ON THIS PATH and the exported log says nothing about it. A phone \
                call ends, the session will not reactivate, and nothing comes back — the same \
                shape as the degrade #964 had to give a voice one call-site over.
                """)
    }

    // MARK: - 3. A failed media-services reset is not silent

    func testTheFailedMediaResetIsNotSilent() throws {
        assertCrumbLeadsItsOSLog(
            try source(Self.config),
            crumb: "EchoelCrashLog.breadcrumb(\"session: media reset FAILED — could not reconfigure",
            osLog: "log.audio(\"Failed to reconfigure audio after media services reset:",
            why: """
                Same class as claim 2: the media server restarted, the reconfigure threw, and \
                audio is dead with nothing in the file the founder exports.
                """)
    }

    // MARK: - 4. The stop says when the session would not deactivate

    func testTheStopSaysWhenTheSessionWouldNotDeactivate() throws {
        assertCrumbLeadsItsOSLog(
            try source(Self.engine),
            crumb: "logEngineLifecycle(\"stop — the session refused to deactivate",
            osLog: "log.audio(\"Failed to deactivate audio session:",
            why: """
                The stop CONTINUES here, so this is a lowercase detail — but the app now \
                believes it stopped while the session is still ACTIVE, and the next start \
                inherits that divergence. That is exactly the kind of state the \
                `isInputConnToConverter` aborts are read out of, and it left no trace.
                """)
    }

    // MARK: - 5. The restart-degrade names the context it failed in

    func testTheRestartDegradeNamesItsContext() throws {
        assertCrumbLeadsItsOSLog(
            try source(Self.engine),
            crumb: "logEngineLifecycle(\"restart after \\(context) FAILED",
            osLog: "log.audio(\"Engine restart after \\(context) failed",
            why: """
                THE MOST EXPENSIVE OF THE SIX. This is a DEGRADE with no exported line, on the \
                interruption / media-reset path, i.e. the commonest real-device failure. The \
                rung above it says `restart after <context> — starting master engine`; without \
                this the log shows that rung and then nothing — the #964 shape one path over.

                ⚠️ The needle carries the ALL-CAPS `FAILED` on purpose: `diag-ladder.py` reads \
                that word as a finding, and in lowercase the line still appears while the \
                triager's tool stops calling it one (#908/#914).
                """)
    }

    // MARK: - 6. The mic stop says when the record route stayed held

    func testTheMicStopSaysWhenTheRecordRouteWasHeld() throws {
        let code = try source(Self.mic)
        let crumb = "EchoelCrashLog.breadcrumb(\"mic: stop FAILED — the record route was not released"
        assertCrumbLeadsItsOSLog(
            code,
            crumb: crumb,
            osLog: "log.audio(\"Failed to downgrade audio session after recording:",
            why: """
                `mic: stop` reaches 3/3 and then this fails: the mic stopped while the RECORD \
                ROUTE is still held. Before #967 a non-benign terminator after a COMPLETE \
                ladder still read `✅ done`, so even once written this line would have landed in \
                a log the tool called clean. It is a finding now; it has to exist to be one.
                """)
        // ⚠️ POSITIVE, not `XCTAssertFalse(contains("mic: stop 3/3 FAILED"))`. A negative
        // assertion is true whenever its needle cannot match, so it grades nothing the day the
        // wording drifts (#926). What actually has to hold is that the terminator follows a
        // COMPLETE ladder — three numbered rungs, one each — because that is the case #967 had
        // to teach the tool to call a finding at all.
        for rung in ["mic: stop 1/3", "mic: stop 2/3", "mic: stop 3/3"] {
            XCTAssertEqual(occurrences(of: rung, in: code), 1, """
                `\(rung)` no longer occurs exactly once. The terminator above is only legible \
                as the end of a COMPLETE ladder; if the rungs are renamed or duplicated, \
                `diag-ladder.py` reads a different ladder than the one this claim describes \
                (#408 — re-anchor before trusting the verdict).
                """)
        }
        XCTAssertEqual(occurrences(of: "mic: stop ", in: code), 4, """
            The `mic: stop` family is no longer three rungs plus one terminator. A NUMBERED \
            terminator is the specific regression to avoid: once a number is present, the form \
            that walks on and the form that returns are the same string in a log, so a numbered \
            failure is indistinguishable from a rung (c3 of the `diag-ladder` grammar).
            """)
    }

    // MARK: - 7. COUNTERWEIGHT: not one AVFAudio call moved

    /// Green on every tree in the header table, deliberately. This slice adds log lines; the day
    /// it starts adding, removing or reordering an AVFAudio call it has stopped being that slice.
    func testTheGuardedCallsAreUnchanged() throws {
        let config = try source(Self.config)
        let engine = try source(Self.engine)
        let mic = try source(Self.mic)
        for (needle, count, code, name) in [
            ("setPreferredIOBufferDuration(", 5, config, "AudioConfiguration"),
            ("onInterruptionResume?()", 1, config, "AudioConfiguration"),
            ("onMediaServicesReset?()", 2, config, "AudioConfiguration"),
            ("setActive(false, options: .notifyOthersOnDeactivation)", 1, engine, "AudioEngine"),
            ("releaseRecordRoute(.microphoneManager)", 5, mic, "MicrophoneManager"),
        ] as [(String, Int, String, String)] {
            XCTAssertEqual(occurrences(of: needle, in: code), count, """
                `\(needle)` no longer occurs \(count)× in \(name). #968 adds lines to the \
                exported log and nothing else — a changed call count here means an audio-graph \
                change rode in on a logging slice, which is not reviewable as one.
                """)
        }
    }

    // MARK: - 8. COUNTERWEIGHT: the downgrade still does not deactivate the session

    /// Green on every tree, and the sharpest of the two: `lowerSessionAfterRecording` sits three
    /// lines from the buffer re-assert claim 1 covers, and a `setActive(false)` there is the
    /// shipped permanent-silence bug — the master output engine still needs the session live.
    func testTheDowngradeStillDoesNotDeactivateTheSession() throws {
        XCTAssertEqual(occurrences(of: "setActive(false", in: try source(Self.config)), 0, """
            `AudioConfiguration` deactivates the audio session again. It must never: the master \
            output engine still needs the session live, and deactivating on the downgrade is \
            exactly the silence bug the surrounding comment records. If a deactivate genuinely \
            belongs somewhere in this file now, that is a founder-visible audio-route change and \
            not a line a logging slice may carry (#855).
            """)
    }
}
