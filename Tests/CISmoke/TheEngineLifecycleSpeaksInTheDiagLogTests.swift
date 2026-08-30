// TheEngineLifecycleSpeaksInTheDiagLogTests — pins #859, the sixth crash log's answer.
//
// THE FINDING (founder device log v10.79.428, build 2546): the isInputConnToConverter
// SIGABRT fired 24 s after a healthy launch with NO monitoring line in the log at all —
// no toggle, no `monitor: ON`, nothing. The stack came out of a Task continuation on the
// main queue (libswift_Concurrency + libdispatch), i.e. one of the ASYNC engine-lifecycle
// paths: interruption resume, route loss, media-services reset, or the de-bounced
// self-heal restart. Every one of those paths spoke ONLY os_log — which the exported
// diag file does not carry — so the log showed 24 seconds of silence before the crash.
// Three of six crash logs stalled on exactly this invisibility.
//
// #859 therefore extends the #854 breadcrumb discipline to the engine lifecycle:
// `logEngineLifecycle` writes `engine: …` into the SAME exported file as `monitor: …`,
// and every async restart path plus both ObjC-asserting `start()` attempts carry a rung.
// It also closes the one MEASURED hazard on such a path: the configuration-change
// watchdog read `masterEngine.inputNode` on EVERY change while running — the first
// access forces the I/O unit to grow an input bus, converter machinery a playback-only
// session cannot back — although the value is only used while monitoring is on.
//
// ⚠️ WHAT IS DELIBERATELY NOT PINNED (#364): the wording of any rung beyond its stable
// prefix, the 300 ms settle, maxRecoveryAttempts. Pinned is STRUCTURE: the shared file,
// a rung per path, rungs around both start attempts, and the inputNode gate ORDER.
//
// ⚠️ HONEST LIMIT (§1): source-text scans — no AVAudioEngine runs in a test host, and
// whether the next crash log actually names its path is the founder's next device log.
//
// ⭐ GRADING (§3), claims 1–5: FORWARD in full — every needle names #859 text created in
// the same commit; red at the parent by the one shared absence (#486). The ordering walks
// could never have a verdict there. Counterweights: the claim-4 gate needles are the ones
// TheMonitoringSurvivesEngineRecoveryTests claim 3 already holds green on both trees.
//
// ⭐ GRADING, claim 12 (#875): a COUNTERWEIGHT, green on both trees, and the flattering
// reading is available so it is refused here. It fixes nothing and instruments nothing —
// all five sites were ALREADY route-guarded when I read them, which is the finding. Its
// value is that the audit stops being a thing one session did once: a SIXTH site now goes
// red instead of joining four crash-adjacent hazards unreviewed. Note what it deliberately
// is NOT: a check of WHY each site is safe. The smarter version — look back N characters
// for the route claim — called 4 of 5 unguarded at a 260-character window, all four false.
// A count that admits its own blindness beats a scan that cries wolf (#665, #874).
//
// ⭐ GRADING, claims 10 and 11 + claim 8s three new rows (#862b), and the honest split
// here is UNFLATTERING, which is the point. Claim 10 is FORWARD (its five `on N/5`
// stages are created by this commit; 2 assertions red at the parent by absence). Claim
// 11 and the three overload rows added to claim 8 are COUNTERWEIGHTS — green on BOTH
// trees — because the rungs they pin already existed and #862 simply failed to guard
// them. Booking those four as regressions would say this commit fixed something it only
// FENCED. What they buy is real all the same: a cleanup slice can no longer delete four
// rungs on a green gate under a test whose name promises full coverage (#374).
//
// ⭐ GRADING, claims 8 and 9 (#862): FORWARD IN FULL, and saying so matters — every
// needle names a rung this same commit creates, so all six assertions are red at the
// parent by ABSENCE, none by regression. Booking them as regressions would be the
// flattering-direction defect §3 names. What they are NOT is padding: the absence they
// describe was real and shipped, and two independent audits of one device log found it.
// The anchor-uniqueness assertions inside claim 8 ARE counterweights — green on both.
//
// ⭐ GRADING, claim 7 (#860b): TWO REGRESSIONS — both helpers put `os_log` before the
// breadcrumb on the parent, red for exactly the reason the claim names. Claim 6's third
// case is red there by needle absence (the rung was renamed to say `engine.prepare()` in
// the same commit that added this line, so the old spelling is gone from BOTH trees —
// `dead-needles.py` confirms no guard still hunts it). The anchor-uniqueness assertion is
// a COUNTERWEIGHT: green on both trees today, and it exists because the header used to
// claim a check that the code did not perform.
//
// ⭐ GRADING, claim 6 (#860) — the strongest in this file, and transcribed against BOTH
// trees rather than reasoned: TWO REGRESSIONS (the interruption and route-lost rungs sit
// AFTER `masterEngine.pause()` on the parent, red for exactly the reason the claim's name
// gives — #367) and ONE FORWARD (the `prepare` rung is created by this commit, so it is
// red there by absence, not by order). All three green on the worktree.
//
// ⭐ GRADING, claims (c2)/(c3) + (d) (#907) — this slice REWRITES (c2), so the WHOLE method
// was driven on both trees, not just the changed lines (§3's delta-blindness warning).
// Against the parent (#906): THREE FORWARDS (the three unnumbered literals do not exist
// there, so (c2) is red by absence) and TWO REGRESSIONS — (c3) selects both of #906's
// numbered `… n/N SKIPPED` lines and fails, and (d)'s pin of 15 meets an actual 14. On the
// worktree all are green. Four negative drives were transcribed rather than reasoned: the
// emitter lifted out of its `else {}` (adjacency RED while the ordering claim stays GREEN —
// that is the hole (c2)'s new pin exists for), a trailing `// #907: was 1/2` comment (stays
// GREEN — the false red M2 would otherwise have caused), and an interpolated rung (fires the
// interpolation claim). ⚠️ (c3)'s `AudioEngine` half WAS a TRIPWIRE, not a counterweight:
// measured 3 selected lines in `AudioConfiguration` and ZERO in `AudioEngine`.
// ⭐ #913 CHANGED THAT — the tripwire fired as designed, in the good direction. The two new
// pre-rung exits are unnumbered `monitor:` skips, so (c3)'s `AudioEngine` half now selects
// TWO lines and both pass: it is a LIVE counterweight, not a tripwire. Do not re-quote the
// ZERO — the number was a measurement of a tree that no longer exists.
//
// ⛔ GRADING, claims (c3) + (c4) (#908) — AND THE FIRST DRAFT OF THIS BLOCK SAID (c3) WAS
// RETIRED. It is not. #908 taught `scripts/diag-ladder.py` a terminator, and I concluded the
// numbered spelling was safe; the review disproved it with a log: `on 4/5 SKIPPED` WALKS ON,
// so a log ending there is a death inside `installTap`, and the draft printed `⏹ ended`,
// exit 0. In a LOG the walks-on and the returning form are the same shape, so the tool
// rescues only UNNUMBERED terminators and (c3) is what keeps the ambiguous spelling out of
// `Sources/`. (c3) is graded: red on `da06482` (both numbered lines), green on the worktree;
// its `AudioEngine` half selected ZERO lines at the time and was a TRIPWIRE (see the ⭐
// above: #913 made it a live counterweight with two selected lines). Its
// interpolation half is a separate assertion and was nearly lost with it.
// (c4) is graded across THREE trees: `b0d6480` → BOTH session functions red, `da06482` →
// `downgradeToPlaybackAfterRecording` red, worktree → green; plus four mutants on the
// worktree (wrapped breadcrumb GREEN, trailing comment GREEN, `if … { return }` RED, silent
// `throw` RED) — its own first draft failed all four.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheEngineLifecycleSpeaksInTheDiagLogTests: XCTestCase {

    private static let enginePath = "Sources/Echoelmusic/Audio/AudioEngine.swift"
    private static let configPath = "Sources/Echoelmusic/Audio/AudioConfiguration.swift"

    // MARK: - 1: the helper writes the EXPORTED file, not only os_log

    func testTheLifecycleHelperWritesTheBreadcrumbFile() throws {
        let code = try code(Self.enginePath)
        XCTAssertEqual(occurrences(of: "EchoelCrashLog.breadcrumb(\"engine: \\(message)\")", in: code), 1, """
            `logEngineLifecycle` no longer writes the exported diag file — the async \
            lifecycle paths fall silent again, and the next start-shaped ObjC assert \
            is another 24 seconds of nothing before a crash (the v428 log).
            """)
    }

    // MARK: - 2: every async lifecycle path leaves a rung

    func testEveryLifecyclePathCarriesARung() throws {
        let code = try code(Self.enginePath)
        for needle in ["logEngineLifecycle(\"interrupted — pausing\")",
                       // ⚠️ #871: this needle used to read `…("interruption ended — restarting")`
                       // and the rung now carries an interpolated `(monitoring: …)` suffix on
                       // its own line, so both the closing paren AND the `logEngineLifecycle(`
                       // prefix stopped adjoining it. The #655/#656 shape — caught by this test
                       // before the commit instead of by a red run after it.
                       // Anchored on the QUOTED STRING alone, deliberately: the first draft of
                       // this repair spelled the line break and sixteen spaces into the needle,
                       // which would have gone red on a reformat that changed nothing. That the
                       // rung is written through `logEngineLifecycle` is claim 1's job, not
                       // this one's; here the guarantee is only that the path still speaks.
                       "\"interruption ended — restarting",
                       "logEngineLifecycle(\"interruption restart FAILED",
                       "logEngineLifecycle(\"media services reset — recovering\")",
                       "logEngineLifecycle(\"route lost — recovering",
                       "logEngineLifecycle(\"self-heal attempt",
                       "logEngineLifecycle(\"self-heal gave up",
                       "logEngineLifecycle(\"self-heal recovered"] {
            XCTAssertGreaterThanOrEqual(occurrences(of: needle, in: code), 1, """
                `\(needle)` is gone. Each async lifecycle path must speak in the \
                exported log (#859) — a silent path is the v428 triage stall again.
                """)
        }
    }

    // MARK: - 3: rungs around BOTH ObjC-asserting start attempts

    func testTheStartAttemptsAreLaddered() throws {
        let code = try code(Self.enginePath)
        guard let anchor = code.range(of: "logEngineLifecycle(\"start 1/2: starting master engine\")") else {
            XCTFail("the start 1/2 rung is gone — a start-shaped death reads as silence again (§4).")
            return
        }
        let window = String(code[anchor.lowerBound...].prefix(1_200))
        var cursor = window.startIndex
        for step in ["try masterEngine.start()",
                     "logEngineLifecycle(\"start 2/2: retry after session reconfigure\")",
                     "try masterEngine.start()"] {
            guard let r = window.range(of: step, range: cursor..<window.endIndex) else {
                XCTFail("""
                    start ladder broken at `\(step)` — both start attempts can die in \
                    the isInputConnToConverter ObjC assert that never reaches the \
                    catch; each needs its rung BEFORE the call (#859, the #854 shape).
                    """)
                return
            }
            cursor = r.upperBound
        }
    }

    // MARK: - 4: the watchdog reads inputNode only under the monitoring gate

    /// The measured hazard (#859): the first `inputNode` access on a RUNNING engine
    /// grows an input bus the playback-only session cannot back. The read must sit
    /// INSIDE `if self.isInputMonitoring`, and there must be no second unconditional
    /// read in the watchdog.
    func testTheWatchdogGatesTheInputNodeRead() throws {
        let code = try code(Self.enginePath)
        guard let fn = code.range(of: "private func registerConfigurationChangeWatchdog") else {
            XCTFail("the configuration-change watchdog is gone — re-anchor this claim (§4).")
            return
        }
        let body = String(code[fn.lowerBound...].prefix(4_000))
        guard let gate = body.range(of: "if self.isInputMonitoring {"),
              let read = body.range(of: "self.masterEngine.inputNode.inputFormat(forBus: 0)")
        else {
            XCTFail("""
                the monitoring gate or the inputNode read left the watchdog window — \
                re-measure the window before shrinking it, and keep the read gated: \
                unconditional, it grows an input bus under a playback-only session on \
                every configuration change (#859).
                """)
            return
        }
        XCTAssertTrue(gate.lowerBound < read.lowerBound, """
            The watchdog reads `inputNode` BEFORE checking `isInputMonitoring` again — \
            the #859 hazard is back: every configuration change while music plays \
            (monitoring off) touches input converter machinery the session cannot back.
            """)
        XCTAssertEqual(occurrences(of: "inputNode.inputFormat(forBus: 0)", in: body), 1,
                       "a second inputNode read appeared in the watchdog — gate it too.")
    }

    /// EVERY hazard site is counted, because claim 4 only covers ONE of them (#875).
    ///
    /// ⭐ THE AUDIT THIS PINS, done by reading all five on 2026-08-29, is the useful half —
    /// it eliminates a whole hypothesis for the `isInputConnToConverter` family rather than
    /// adding another instrument. `masterEngine.inputNode` appears FIVE times in code, and
    /// every one is behind a claimed record route or the monitoring gate:
    ///   · the config-change watchdog — inside `if self.isInputMonitoring` since #859, and
    ///     that specific ordering is claim 4's job, not this one's.
    ///   · the monitoring ON path — after `claimRecordRoute`, reading the format the claim
    ///     just made valid.
    ///   · the OFF path's `removeTap` and `disconnectNodeOutput` — both at `off 2/5` and
    ///     `off 3/5`, i.e. BEFORE `off 4/5: releasing record route`. Tearing the edges down
    ///     while the route is still held is the correct order; the reverse would be the
    ///     hazard.
    /// The two touches OUTSIDE this file are route-guarded too and are not counted here:
    /// `MicrophoneManager` calls `claimRecordRoute(.microphoneManager)` before its
    /// `inputNode = audioEngine.inputNode`, and `MultiTrackRecorder` claims before its read
    /// (and is doorless anyway, #204).
    ///
    /// ⛔ #901 — THOSE TWO WERE LINE NUMBERS (`:207`, `:218`) AND BOTH HAD DRIFTED, to 240
    /// and 265. Measured, not guessed: they were already wrong one commit before #900, so
    /// nothing recent moved them — they simply aged, silently, because nothing re-derives a
    /// line number. This repo's own rule covers it and is restated here because this is
    /// where it was broken: **a quoted PHRASE survives an insertion above it, a line number
    /// does not.** The ORDER claim itself was and stays correct.
    ///
    /// ⛔ WHY A COUNT AND NOT A "ROUTE CONTEXT" SCAN. I tried the smarter check first: for
    /// each site, look back N characters for `isInputMonitoring` or `claimRecordRoute`. At
    /// 260 characters it reported 4 of the 5 as unguarded — all four false, because the gate
    /// simply sits further back. A guard built on that window would cry wolf on correct code,
    /// which is the #665 defect and exactly what #874 had just removed from `doctor.py`. A
    /// count cannot say WHY a site is safe; it can say a SIXTH appeared, and that a human
    /// must then do what I did by hand.
    ///
    /// ⚠️ THIS FORBIDS NOTHING (#364). Extending the vocal chain may well need another input
    /// touch, and that is legitimate work — the red is a checklist, not an objection.
    func testEveryInputNodeSiteIsAccountedFor() throws {
        let code = try code(Self.enginePath)
        XCTAssertEqual(occurrences(of: "masterEngine.inputNode", in: code), 5, """
            The number of `masterEngine.inputNode` sites changed. Each one is a place where             the I/O unit can grow an input bus the session may not be able to back — the             `isInputConnToConverter` family, seven device logs deep and still without a named             trigger. If a site was ADDED: check it claims the record route (or sits under the             monitoring gate) BEFORE the touch, and add it to the audit list in this test's             doc. If one was REMOVED: drop it from that list in the same commit. Do not simply             change this number — the number is not the point, the audit behind it is.
            """)
    }

    /// THE TWO POSITIONAL MARKERS (#910) — the gap-splitters on the suspect path.
    ///
    /// ⭐ WHY THEY EXIST, measured while auditing the crash path for #909: in BOTH files the
    /// last rung before the first input touch covers THREE candidates at once.
    ///   · `AudioEngine`: after `on 1/5` the only breadcrumb writer is `claimRecordRoute`. On
    ///     the FIRST-owner path its last line is `session: raise 2/2 — setActive`, which by
    ///     the ladder's law stands BEFORE `setActive` — so `2/2` last means `setActive`, the
    ///     `inputNode` access, or `inputFormat`. On the SECOND-owner path (route already up)
    ///     `raise 1/2` and `2/2` never run and `session: raise SKIPPED` is last instead; the
    ///     marker still splits, and `SKIPPED` last would itself be a finding.
    ///   · `MicrophoneManager`: after `mic: start 2/3` come the node access, the
    ///     `outputFormat` read and `installTap`. That is the stronger half —
    ///     `installTap(format:)` raises an uncatchable ObjC exception on a format mismatch.
    ///
    /// ⚠️ THIS IS INSTRUMENTATION OF A HYPOTHESIS, NOT A MEASUREMENT OF THE CRASH. No founder
    /// log has ever ended in either stretch. Saying otherwise would repeat #860b, which read
    /// the ABSENCE of rungs as evidence.
    ///
    /// ⚠️ UNNUMBERED IS THE POINT. ⛔ But NOT for the reason the first draft gave ("every log
    /// already in the founder's hands would be re-read") — measurably false: no log in hand
    /// carries an `on N/5` line, and the `mic: start` ladder shipped in v429 into a log with no
    /// `mic:` lines. The real reason is that `total` is a completeness contract
    /// `scripts/diag-ladder.py` audits, and a positional marker is not a step of a
    /// fixed-length sequence. Driven: `--source` still reports `on` 1..5 and `mic: start` 1..3.
    ///
    /// ⚠️ THEY ARE POSITIONAL, NOT CONDITIONAL — #631's deletion at the `AudioEngine` site is
    /// the reason. That breadcrumb tested a hypothesis, #628 moved a `pause()` above it, and it
    /// then fired on every healthy toggle and read as confirmation of what it was built to
    /// falsify.
    ///
    /// ⭐ GRADING (§3), and writing it is what exposed the dead assertion below. Against the
    /// parent `cc4df74`: TWO FORWARDS (both markers absent, so existence fails). On the
    /// worktree: green. Mutants driven on the worktree: marker deleted RED · marker moved
    /// after the call RED · an `if` inserted BETWEEN marker and call RED · the marker's line
    /// wrapped in `if wasRunning { … }` RED (this one was GREEN in the first draft — the
    /// between-span sees only what follows the marker, so a branch AROUND it was invisible,
    /// which is #631 verbatim under a claim promising it could not happen) · the rung number
    /// APPENDED to the message RED (also GREEN in the first draft: it applied
    /// `carriesRungNumber` to the test's OWN literal, an assertion that could not fail on any
    /// tree — the sibling (c3) already does this correctly by extracting from the source line).
    func testTheSuspectPathIsSplitByTwoUnnumberedMarkers() throws {
        for (label, text, marker, rung, call) in [
            ("AudioEngine", try code(Self.enginePath),
             "on: touching the input node + reading its format",
             "on 1/5: stopping engine + claiming record route",
             "let input = masterEngine.inputNode"),
            ("MicrophoneManager", try code("Sources/Echoelmusic/MicrophoneManager.swift"),
             "mic: start — installing the tap now",
             "mic: start 2/3 — tapping input",
             "inputNode?.installTap(onBus: 0"),
        ] {
            XCTAssertEqual(occurrences(of: marker, in: text), 1, """
                the #910 marker `\(marker)` left `\(label)`. Without it the last rung before \
                the first input touch covers three AVFAudio calls at once, and a device log \
                localises the `isInputConnToConverter` crash to a stretch instead of a call.
                """)
            guard let r = text.range(of: rung), let m = text.range(of: marker),
                  let c = text.range(of: call) else {
                XCTFail("the rung, the marker or the call left `\(label)` — re-anchor (§4). "
                        + "The other file is still checked (#910 review, L8).")
                continue
            }
            XCTAssertTrue(r.lowerBound < m.lowerBound && m.lowerBound < c.lowerBound, """
                the #910 marker in `\(label)` no longer sits BETWEEN its rung and the call it \
                splits. Before the rung it says nothing new; after the call it describes a \
                step that already happened — the trailing-rung defect (#860/#878).
                """)

            // THE MARKER'S OWN LINE must BE the emitter — not a statement inside a branch that
            // happens to contain it. Without this, `if wasRunning { breadcrumb(…) }` passes
            // every other assertion here (#910 review, HIGH-1).
            let line = lineContaining(marker, in: text)
            XCTAssertTrue(line.hasPrefix("logMonitorOutcome(")
                          || line.hasPrefix("EchoelCrashLog.breadcrumb("), """
                the #910 marker in `\(label)` is no longer the whole statement on its line:
                \(line)
                A marker wrapped in a condition stops meaning "control reached here" — which \
                is exactly how #631's breadcrumb came to read as confirmation of its opposite.
                """)

            // Read the NUMBER off the source line, never off this file's own literal: applied
            // to `marker` the check is a tautology that no tree can fail (#910 review, M3).
            XCTAssertFalse(carriesRungNumber(line), """
                the #910 marker in `\(label)` was NUMBERED:
                \(line)
                That turns it into a rung, so `scripts/diag-ladder.py` grows the ladder by one \
                step and `total` stops describing the sequence it audits. If a real step is \
                wanted, renumber the WHOLE ladder deliberately and say so where logs are triaged.
                """)

            // POSITIONAL, NOT CONDITIONAL: nothing between the marker and the call may open a
            // branch. `#if` is NOT one — it is a platform guard, and `MicrophoneManager` wraps
            // route work in five of them, so a literal `"if "` scan would false-red on ordinary
            // work (#910 review, M5).
            for between in String(text[m.upperBound..<c.lowerBound])
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map({ $0.trimmingCharacters(in: .whitespaces) })
            where !between.hasPrefix("#") {
                for branch in ["if ", "guard ", "while "] where between.hasPrefix(branch)
                    || between.contains(" " + branch) {
                    XCTFail("""
                        a `\(branch.trimmingCharacters(in: .whitespaces))` appeared between \
                        the #910 marker in `\(label)` and the call it splits:
                        \(between)
                        The marker then no longer proves control reached the call.
                        """)
                }
            }
        }
    }

    /// AND THE SECOND FILE, added #909 — because "not counted here" was the whole gap.
    ///
    /// ⛔ THIS CLAIM IS THE SALVAGE OF A SLICE I THREW AWAY, and the reason is written above
    /// in this file already: the ⛔ paragraph on the previous claim records that a "look back
    /// N for `claimRecordRoute`" scan was TRIED and REJECTED as the #665 cry-wolf shape. #909
    /// built a variant of exactly that — a function-sized window asserting every `inputNode`
    /// touch sits after a breadcrumb — and the review killed it on four counts, of which two
    /// are worth remembering here: it was **member-kind-blind** (`init`, `deinit`, a computed
    /// property and a `subscript` open no window, so a `deinit { inputNode.removeTap(…) }`
    /// inherited the previous function's "already spoke" and passed — the
    /// `isInputConnToConverter` shape verbatim), and it was **branch-blind** (a
    /// `logMonitorOutcome` inside a `catch` that returns marked the function spoken, so
    /// deleting the only line on the reaching path left it GREEN). A COUNT has neither
    /// weakness: it cannot be fooled by where a member sits or by which branch runs.
    ///
    /// ⭐ THE AUDIT, done by reading all EIGHT uses on 2026-08-30 (nine occurrences — line
    /// `inputNode = audioEngine.inputNode` carries two):
    ///   · the stored property itself.
    ///   · `inputNode = audioEngine.inputNode` and the `outputFormat` read — both AFTER
    ///     `claimRecordRoute(.microphoneManager)` and after the `mic: start 2/3` rung.
    ///   · `installTap` — between rungs `2/3` and `3/3`, so a death there is localised.
    ///   · three `= nil` clears — Swift property writes, no AVFAudio call.
    ///   · `engine.inputNode.removeTap(onBus: 0)` — under `mic: stop 2/3`, and deliberately
    ///     guarded by `engine.isRunning`: touching `inputNode` on a stopped engine is the
    ///     hazard this file exists for.
    ///
    /// ⚠️ THIS FORBIDS NOTHING (#364), same as its sibling: the vocal chain may legitimately
    /// need another touch. The red is a checklist — audit the new site, extend the list above,
    /// then move the number.
    func testEveryMicrophoneInputSiteIsAccountedFor() throws {
        let mic = try code("Sources/Echoelmusic/MicrophoneManager.swift")
        XCTAssertEqual(occurrences(of: "inputNode", in: mic), 9, """
            The number of `inputNode` mentions in MicrophoneManager changed. This is the OTHER \
            engine that taps the input — its own `AVAudioEngine`, with its own category flip, \
            running while the master engine runs. A new site here is a new place the \
            `isInputConnToConverter` family can fire, seven device logs deep and still \
            without a named trigger. Audit the new site (is it after the record-route claim? \
            is it under a rung, so a death there is localised? is it guarded by \
            `engine.isRunning` if it touches a stopped graph?), add it to the list in this \
            test's doc, and only then change the number.
            """)
    }

    // MARK: - 5: the voice-timbre chain speaks too (#859b — reviewer L3)

    /// The last diag-dark input path: VoiceCaptureController → MicrophoneManager does
    /// a category flip + own engine + inputNode tap while the master engine runs, and
    /// wrote nothing. A silent NEXT crash log would have indicted it unseen.
    func testTheVoiceCaptureChainCarriesRungs() throws {
        let mic = try code("Sources/Echoelmusic/MicrophoneManager.swift")
        for needle in ["EchoelCrashLog.breadcrumb(\"mic: start 1/3 — claiming record route\")",
                       "EchoelCrashLog.breadcrumb(\"mic: start 2/3 — tapping input\")",
                       "EchoelCrashLog.breadcrumb(\"mic: start 3/3 — starting capture engine\")",
                       "EchoelCrashLog.breadcrumb(\"mic: start FAILED",
                       // #876: the teardown side had ONE rung for a multi-step tear-down.
                       // The wording of the old single rung ("mic: stop — releasing capture
                       // engine + route") is deliberately RETIRED here in the same commit
                       // that retires it in the source — a needle left behind for a string
                       // that no longer exists is a red on a correct tree (#655/#656).
                       // ⛔ Rung 1 is anchored on the QUOTED STRING alone, not on
                       // `EchoelCrashLog.breadcrumb(` + the literal. My first draft spelled
                       // the line break and twelve spaces of its wrapped call into the
                       // needle — a pattern that pins a FORMATTING choice and goes red on a
                       // reflow that changes nothing (the #871 mistake, made again here and
                       // caught before shipping). Rungs 2 and 3 fit on one line, so they
                       // keep the full call form.
                       "\"mic: stop 1/3 — stopping capture engine",
                       "EchoelCrashLog.breadcrumb(\"mic: stop 2/3 — removing input tap\")",
                       "EchoelCrashLog.breadcrumb(\"mic: stop 3/3 — releasing record route\")"] {
            XCTAssertEqual(occurrences(of: needle, in: mic), 1,
                           "`\(needle)` is gone — the mic capture chain falls diag-dark again (#859b).")
        }
        // #876 — ORDER, not wording (#364): the tap rung must stand BEFORE the
        // `inputNode` touch it describes. `inputNode` is the node the recurring
        // `isInputConnToConverter` abort is named after, so a rung on the far side of
        // it would read as "tap never removed" when the truth is "died removing it".
        if let rung = mic.range(of: "\"mic: stop 2/3 — removing input tap\""),
           let call = mic.range(of: "engine.inputNode.removeTap(onBus: 0)") {
            XCTAssertTrue(rung.lowerBound < call.lowerBound, """
                The mic teardown's tap rung sits AFTER `removeTap` again (#860/#876). \
                A death inside it is then silence, and the log reads as a path not taken.
                """)
        } else {
            XCTFail("the mic teardown's tap rung or its `removeTap` call is gone — re-anchor (§4).")
        }
        // #877 — the two ways rung 1 lied, both pinned so they cannot come back quietly.
        //
        // (a) THREE STATES, not a Bool. `engine?.isRunning == true` printed `false` for
        //     "no engine" AND for "engine stopped"; the first is the common case (the
        //     master stop tears the mic down every time, usually with no mic engine at
        //     all), so the no-op looked exactly like the interesting case.
        for token in ["\"engine: none\"", "\"engine: running\"", "\"engine: stopped\""] {
            XCTAssertEqual(occurrences(of: token, in: mic), 1,
                           "rung 1 no longer distinguishes \(token) — the teardown log stops "
                           + "telling a no-op apart from a real tear-down (#877).")
        }
        // (b) NO STRONG REFERENCE HELD ACROSS THE RUNG. #876 hoisted
        //     `let engine = audioEngine` to function scope so the rung could read the
        //     state; that extra reference moves the AVAudioEngine's DEALLOCATION past
        //     rung 3, while the prose above rung 1 tells the reader to attribute silence
        //     there to the route release. Reading the state INLINE keeps the release at
        //     `audioEngine = nil`, where the prose says it is.
        //
        //     ⚠️ This FORBIDS NOTHING about how the state is formatted (#364) — it pins
        //     that the branch still binds from the property, which is what fixes the
        //     lifetime. A future rewrite may change the wording freely.
        //     ⛔ AND THIS ASSERTION'S FIRST DRAFT WAS ITSELF THE #408 TRAP the sibling
        //     claim warns about: it counted the binding file-wide and demanded ONE, while
        //     `deinit` carries the SAME line. A green tree would have gone red. Simulated
        //     before shipping, which is the only reason it is anchored instead.
        XCTAssertEqual(occurrences(of: "    func stopRecording() {", in: mic), 1,
                       "`stopRecording()` is no longer unique in the file — the window below "
                       + "would open on the wrong function (#408).")
        guard let stopFn = mic.range(of: "    func stopRecording() {") else {
            XCTFail("`stopRecording()` is gone — re-anchor this claim (§4).")
            return
        }
        let teardown = String(mic[stopFn.lowerBound...].prefix(400))
        XCTAssertTrue(teardown.contains("if let engine = audioEngine, engine.isRunning {"), """
            The mic teardown no longer binds its engine from the property at the branch. \
            If a local was hoisted above rung 1 again, the engine's deallocation moves past \
            rung 3 and the ladder's own prose becomes wrong about what the silence after \
            3/3 means (#877).
            """)
        let voice = try code("Sources/Echoelmusic/Studio/VoiceCaptureController.swift")
        XCTAssertEqual(occurrences(of: "EchoelCrashLog.breadcrumb(\"voice: capture armed\")", in: voice), 1,
                       "the voice-timbre take no longer announces itself in the exported log.")
    }


    // MARK: - 6: a rung stands BEFORE its AVFAudio call, never after (#860)

    /// ⛔ THE DEFECT THIS PINS IS ONE #859 SHIPPED. Three rungs sat AFTER the graph call
    /// they described — `pause()` twice and `prepare()` once — so a death inside that call
    /// logged NOTHING: the witness stood on the far side of the event. Measured, not
    /// reasoned: the v429 device log (seventh crash of the isInputConnToConverter family)
    /// carried the launch rungs, proving the mechanism works, and then not ONE of the 22
    /// rungs before a SIGABRT out of a main-queue Task continuation.
    ///
    /// A ladder whose rungs trail their steps is worse than none — it reads as "this path
    /// was not taken" when the truth is "this path died mid-step".
    ///
    /// ⚠️ NOT PINNED (#364): the rung wording, beyond the prefix a sibling claim already
    /// owns. Pinned is ORDER only, which is the part that carries the law.
    func testEachRungStandsBeforeItsGraphCall() throws {
        let code = try code(Self.enginePath)
        // anchor, rung, graph call, window — uniqueness is ASSERTED below, not asserted
        // in prose: #860b, reviewer, found this comment claiming a check it did not do.
        let cases: [(String, String, String, Int)] = [
            ("onInterruptionBegan = { [weak self] in",
             "logEngineLifecycle(\"interrupted — pausing\")",
             "masterEngine.pause()", 700),
            ("onRouteDeviceLost = { [weak self] in",
             "logEngineLifecycle(\"route lost — recovering",
             "masterEngine.pause()", 900),
            ("    func start() {",
             "logEngineLifecycle(\"engine.prepare() — allocating graph resources\")",
             "masterEngine.prepare()", 900),
        ]
        for (anchor, rung, call, window) in cases {
            XCTAssertEqual(occurrences(of: anchor, in: code), 1, """
                `\(anchor)` is no longer unique in the file (#408). `range(of:)` takes the \
                FIRST match, so the window below would open on the wrong site and could \
                hand back a green for a function this claim never meant to inspect.
                """)
            guard let a = code.range(of: anchor) else {
                XCTFail("anchor `\(anchor)` is gone — re-anchor this claim (§4).")
                return
            }
            let body = String(code[a.lowerBound...].prefix(window))
            guard let r = body.range(of: rung), let c = body.range(of: call) else {
                XCTFail("""
                    `\(rung)` or `\(call)` left the window under `\(anchor)`. Re-measure \
                    the window before widening it — and keep the rung: without it a death \
                    inside `\(call)` is silence in the exported log (#860).
                    """)
                return
            }
            XCTAssertTrue(r.lowerBound < c.lowerBound, """
                The rung for `\(call)` sits AFTER the call again (#860). A pause/prepare \
                that raises the isInputConnToConverter ObjC assert then logs nothing, and \
                the next crash log reads as "path not taken" instead of naming the step.
                """)
        }
    }


    // MARK: - 7: the witness writes the DURABLE sink first (#860b)

    /// ⛔ THE LADDER HAD ITS OWN #860 DEFECT, one level down. Both helpers called the
    /// slow shared sink (`os_log`, which locks and can be throttled) BEFORE the durable
    /// unbuffered `write(2)`. A process dying between those two statements loses the rung
    /// and the path reads as never-taken — precisely what the ladder exists to prevent.
    ///
    /// ⚠️ Order only (#364): the message text, the prefixes and the level default are
    /// free to change.
    func testTheDurableSinkIsWrittenFirst() throws {
        let code = try code(Self.enginePath)
        for (fn, crumb, oslog) in [
            ("private func logEngineLifecycle", "EchoelCrashLog.breadcrumb(\"engine: ", "log.audio(\"Engine lifecycle: "),
            ("private func logMonitorOutcome", "EchoelCrashLog.breadcrumb(\"monitor: ", "log.audio(\"Input monitoring: "),
        ] {
            guard let a = code.range(of: fn) else {
                XCTFail("`\(fn)` is gone — re-anchor this claim (§4).")
                return
            }
            let body = String(code[a.lowerBound...].prefix(400))
            guard let c = body.range(of: crumb), let o = body.range(of: oslog) else {
                XCTFail("both sinks must stay in `\(fn)` — the exported log is the only one the founder sends.")
                return
            }
            XCTAssertTrue(c.lowerBound < o.lowerBound, """
                `\(fn)` writes os_log before the breadcrumb again (#860b). os_log locks in \
                the unified-logging subsystem; a death between the two statements loses the \
                rung, and a lost rung reads as a path never taken.
                """)
        }
    }


    // MARK: - 8: every graph-mutating entry point carries a rung (#862)

    /// ⛔ TWO INDEPENDENT AUDITS OF THE v429 LOG LANDED HERE. `restartOrDegrade` held the
    /// FIFTH `masterEngine.start()` in the file and one of the TWO without a rung (#862b
    /// retracts #862's "the only one" — the other is on the monitoring ON path, claim 10) — and #858
    /// established that the isInputConnToConverter assert fires INSIDE `start()` as an ObjC
    /// exception no Swift `catch` sees, so its own `do` block cannot report its death. Its
    /// five callers are all hot graph edits (pause → mutate → restart), and that whole
    /// family spoke only `log.audio`, which the exported diag file does not carry.
    ///
    /// ⚠️ PRESENCE only, not wording or argument (#364). What must not come back is a
    /// graph mutation the founder's log cannot see.
    func testEveryGraphMutationLeavesARung() throws {
        let code = try code(Self.enginePath)
        for (fn, rung) in [
            ("private func restartOrDegrade", "logEngineLifecycle(\"restart after "),
            ("func attachSourceNode", "logEngineLifecycle(\"graph: attach source node"),
            ("func detachSourceNode", "logEngineLifecycle(\"graph: detach source node"),
            ("func detachPlayerNode(_ node: AVAudioPlayerNode) {", "logEngineLifecycle(\"graph: detach player node"),
            ("func stop(reason: StopReason)", "logEngineLifecycle(\"stop ("),
            // ⛔ #862b (reviewer G) — THE THREE OVERLOADS #862 CREATED AND DID NOT PIN.
            // The method name says EVERY; the table held five of eight. A cleanup slice
            // could have deleted these three rungs on a green gate, under a test whose
            // name still promised full coverage — the #374 lying-name shape.
            ("func attachPlayerNode(_ node: AVAudioPlayerNode, format: AVAudioFormat) {",
             "logEngineLifecycle(\"graph: attach player node"),
            ("through timePitch: AVAudioUnitTimePitch,",
             "logEngineLifecycle(\"graph: attach player node + time-pitch"),
            ("func detachPlayerNode(_ node: AVAudioPlayerNode, timePitch: AVAudioUnitTimePitch) {",
             "logEngineLifecycle(\"graph: detach player node + time-pitch"),
        ] {
            XCTAssertEqual(occurrences(of: fn, in: code), 1,
                           "`\(fn)` is no longer unique — re-anchor this claim (#408, §4).")
            guard let a = code.range(of: fn) else {
                XCTFail("`\(fn)` is gone — re-anchor this claim (§4).")
                return
            }
            let body = String(code[a.lowerBound...].prefix(700))
            XCTAssertTrue(body.contains(rung), """
                `\(fn)` mutates the AVFAudio graph and no longer announces itself in the \
                exported diag file (#862). os_log does not reach that file — a death here \
                is 14 seconds of silence and a SIGABRT, which is the v429 log exactly.
                """)
        }
    }

    /// The rung must PRECEDE the start it describes — the #860 rule, applied to the
    /// fifth start().
    func testTheRestartRungPrecedesItsStart() throws {
        let code = try code(Self.enginePath)
        guard let a = code.range(of: "private func restartOrDegrade") else {
            XCTFail("`restartOrDegrade` is gone — re-anchor this claim (§4).")
            return
        }
        let body = String(code[a.lowerBound...].prefix(700))
        guard let r = body.range(of: "logEngineLifecycle(\"restart after "),
              let c = body.range(of: "try masterEngine.start()") else {
            XCTFail("the restart rung or its start() left the window — re-measure before widening it.")
            return
        }
        XCTAssertTrue(r.lowerBound < c.lowerBound, """
            The restart rung sits AFTER `try masterEngine.start()` — the #860 defect on the \
            one start() that had no witness at all. The assert this family raises is an ObjC \
            exception; the catch below never runs, so a rung behind the call writes nothing.
            """)
    }


    // MARK: - 10: the ON path is staged like the OFF path (#862b — reviewer E1/E2)

    /// ⛔ #862 CLAIMED `restartOrDegrade` HELD "THE ONLY" RUNGLESS `masterEngine.start()`.
    /// It held one of TWO. The other starts the engine with the input node freshly connected
    /// into `notchEQ` under a just-claimed record route — an input wired to a converter,
    /// which is the assert's own name — and its `catch` is the shape #858 proved cannot
    /// report an ObjC abort. Meanwhile the OFF branch already had five staged rungs and the
    /// ON branch had failure-only crumbs across ~15 AVFAudio calls.
    ///
    /// ⚠️ Stage NAMES are pinned, not their prose (#364). What must not come back is an ON
    /// path that collapses fifteen graph calls into one line.
    func testTheMonitorOnPathIsStaged() throws {
        let code = try code(Self.enginePath)
        // ⛔ #882 — THE FIRST TWO NEEDLES OF STEPS 4 AND 5 WERE PREFIXES, and that made this
        // claim collide with claim 16 in THIS FILE: #882 gave those two gated steps a second
        // emitter each (`on 4/5 SKIPPED` / `on 5/5 SKIPPED`, because a step that is skipped
        // must say so or the numbering lies), so `"on 4/5` now counts 2 while this claim
        // demanded 1. Two claims, one file, incompatible numbers — the suite could not go
        // green either way. Fixed by naming the TAKEN rung, which is what this claim was
        // always about: it exists to stop the ON path collapsing its ~15 AVFAudio calls into
        // one line. Loosening it to `GreaterThanOrEqual` would have stopped detecting exactly
        // that collapse, so it stays an equality on a sharper needle.
        for stage in ["logMonitorOutcome(\"on 1/5", "logMonitorOutcome(\"on 2/5",
                      "logMonitorOutcome(\"on 3/5",
                      "logMonitorOutcome(\"on 4/5: restarting",
                      "logMonitorOutcome(\"on 5/5: installing"] {
            XCTAssertEqual(occurrences(of: stage, in: code), 1, """
                `\(stage)…` is gone. The monitoring ON path must stage like its OFF twin \
                (#862b): a death among its ~15 AVFAudio calls otherwise collapses to the \
                one line before the branch.
                """)
        }
        // The `on 4/5` rung guards the SECOND rungless start() — it must precede it.
        guard let a = code.range(of: "logMonitorOutcome(\"on 4/5"),
              let b = code.range(of: "try masterEngine.start()", range: a.upperBound..<code.endIndex)
        else {
            XCTFail("the `on 4/5` rung or the start it guards is gone — re-anchor (§4).")
            return
        }
        XCTAssertTrue(a.lowerBound < b.lowerBound,
                      "the ON-path restart rung must precede its start() — the #860 rule.")
    }

    /// The eighth #862 rung — `start()`'s already-running half — had no claim at all.
    func testTheLiveStartBranchSpeaks() throws {
        let code = try code(Self.enginePath)
        XCTAssertEqual(occurrences(of: "logEngineLifecycle(\"start: re-arming taps", in: code), 1, """
            `start: re-arming taps…` is gone (#862b, reviewer G). Entering `start()` with the \
            engine already running skips all three rungs inside `if !masterEngine.isRunning` \
            and lands on live tap surgery — the branch was silent before this line.
            """)
    }

    // MARK: - helpers (the house shape: strip comments, skip on no tree)

    // MARK: - 13: the SESSION half of the ladder speaks too (#878)

    /// ⛔ THE HOLE THIS CLOSES. `AudioConfiguration` carried FIFTEEN AVAudioSession calls
    /// (comment-stripped count) and exactly ONE breadcrumb — `latencyBreadcrumb`, which is a
    /// measurement, not a rung. So every rung on the engine side that hands off to a category
    /// flip (`mic: stop 3/3 — releasing record route`, `on N/5`, `off N/5`) ended at the
    /// boundary and the next stretch was dark. A category move is the neighbourhood the
    /// `isInputConnToConverter` family lives in.
    ///
    /// ⚠️ THE LADDER IS DELIBERATELY NOT A CENSUS OF ALL FIFTEEN, and this claim does not
    /// pretend otherwise. It covers the THREE category-transition functions. The rest
    /// (`setLatencyMode`, `measureLatency`, the interruption handler) either repeat on a
    /// path the engine side already narrates or are measurements. A future session that
    /// wants full coverage is adding work, not fixing a defect — this forbids nothing (#364).
    func testTheSessionTransitionsCarryRungs() throws {
        let config = try code("Sources/Echoelmusic/Audio/AudioConfiguration.swift")

        // (a) Every rung exists exactly once.
        for rung in ["session: configure 1/4 — setCategory(",
                     "session: configure 2/4 — setPreferredSampleRate",
                     "session: configure 3/4 — setPreferredIOBufferDuration",
                     "session: configure 4/4 — setActive",
                     "session: raise 1/2 — setCategory(.playAndRecord)",
                     "session: raise 2/2 — setActive",
                     "session: lower 1/1 — setCategory(.playback)"] {
            XCTAssertEqual(occurrences(of: rung, in: config), 1,
                           "`\(rung)` is gone — the session half falls diag-dark again (#878).")
        }

        // (b) ORDER: a rung stands BEFORE the call it names, inside its OWN function window
        //     (the anchor is asserted unique first — #408).
        let ordered: [(fn: String, rung: String, call: String)] = [
            // #879 (reviewer): rung 1/4 had EXISTENCE but no ORDER, because its named call
            // is two-branched and no single needle fits both arms. Moving it below the
            // branch would have kept all sixteen assertions green while the rung described
            // a category that had already been set. The BRANCH KEYWORD is the stable
            // anchor — the rung must precede the `if`, so it covers both arms.
            ("static func configureAudioSession", "session: configure 1/4",
             "if recordingRouteNeeded {"),
            ("static func configureAudioSession", "session: configure 2/4",
             "setPreferredSampleRate(preferredSampleRate)"),
            ("static func configureAudioSession", "session: configure 3/4",
             "setPreferredIOBufferDuration(bufferDuration)"),
            ("static func configureAudioSession", "session: configure 4/4",
             "setActive(true, options: .notifyOthersOnDeactivation)"),
            ("static func upgradeToPlayAndRecord", "session: raise 1/2 — setCategory",
             "setCategory(.playAndRecord, mode: .default, options: recordOptions)"),
            ("static func upgradeToPlayAndRecord", "session: raise 2/2 — setActive",
             "setActive(true, options: .notifyOthersOnDeactivation)"),
            ("static func downgradeToPlaybackAfterRecording", "session: lower 1/1 — setCategory",
             "setCategory(.playback, mode: .default,"),
        ]
        for (fn, rung, call) in ordered {
            XCTAssertEqual(occurrences(of: fn, in: config), 1,
                           "`\(fn)` is no longer unique — the window would open elsewhere (#408).")
            guard let a = config.range(of: fn) else {
                XCTFail("`\(fn)` is gone — re-anchor this claim (§4).")
                return
            }
            let body = String(config[a.lowerBound...].prefix(1_800))
            guard let r = body.range(of: rung), let c = body.range(of: call) else {
                XCTFail("`\(rung)` or `\(call)` left the window under `\(fn)` — re-measure "
                        + "before widening it.")
                return
            }
            XCTAssertTrue(r.lowerBound < c.lowerBound, """
                The rung for `\(call)` sits AFTER the call again (#860/#878). A session move \
                that raises the ObjC assert then logs nothing, and the next crash log reads \
                as "path not taken" instead of naming the step.
                """)
        }

        // (c) AND THE MIRROR IMAGE, which is the part that is easy to get wrong: both
        //     transitions have a no-op guard, so the rung must sit AFTER it. Announcing a
        //     raise the guard then skips writes a step into the log that never happened —
        //     just as misleading as a trailing rung, and in the opposite direction.
        for (fn, noOpGuard, rung) in [
            ("static func upgradeToPlayAndRecord",
             "guard audioSession.category != .playAndRecord", "session: raise 1/2 — setCategory"),
            ("static func downgradeToPlaybackAfterRecording",
             "guard audioSession.category != .playback", "session: lower 1/1 — setCategory"),
        ] {
            guard let a = config.range(of: fn) else {
                XCTFail("`\(fn)` is gone — re-anchor (§4). A bare `return` here would have "
                        + "exited the whole test method and reported GREEN (#907 review).")
                return
            }
            let body = String(config[a.lowerBound...].prefix(1_800))
            guard let g = body.range(of: noOpGuard), let r = body.range(of: rung) else {
                XCTFail("the no-op guard or its rung left `\(fn)` — re-anchor (§4).")
                return
            }
            XCTAssertTrue(g.lowerBound < r.lowerBound, """
                `\(fn)` announces its session move BEFORE the guard that may skip it (#878). \
                The log then names a step the code did not take.
                """)
        }

        // (c2) #906 — A SKIPPED STEP SAYS SO. Both category moves had a guard that
        //      returned in SILENCE, and the ladder's own law reads silence between two rungs
        //      as a DEATH: `releaseRecordRoute` printed "holders none, lowering" and returned
        //      TRUE while nothing had been lowered. The law is not new — `AudioEngine` has
        //      carried `on 4/5 SKIPPED:` since #862b — it simply had not reached this file.
        //
        // ⛔ #907 — #906 WROTE THEM NUMBERED (`raise 1/2 SKIPPED`) AND THAT LIED IN THE OTHER
        //    DIRECTION. `diag-ladder.py`'s LOG mode kept the LAST `raise n/2` it saw and had
        //    NO NOTION OF A SKIP — it has one for UNNUMBERED lines since #908 — so a healthy
        //    SECOND claim ended its ladder at 1/2 and the tool called a two-owner run a
        //    DEATH — on exactly the path #888 exists to illuminate. Reproduced on a
        //    synthetic log both ways. The literals below are unnumbered now, and (c3) below
        //    keeps the numbered form out. (⛔ #908's first draft retired (c3), believing the
        //    tool had made it safe; the review disproved that with a walks-on log. Restored.)
        //
        // ⭐ THE THIRD TUPLE IS NEW IN #907 — AND IT IS NOT A NO-OP GUARD, which is why the
        //    wording around it says "a guard" rather than "the no-op guard" (#907 review, M1).
        //    The two category comparisons really do find nothing to do; this one can return
        //    while the category IS raised, so its message carries "category left as-is".
        //    It was left silent by #906 on two reasons that were both measurably wrong: it
        //    fires after a THROWN configure too, and only one of the three claim sites
        //    configures first — so the
        //    session can sit on `.playAndRecord` with nobody holding it while the log says
        //    "holders none, lowering".
        //
        // ⚠️ THE ORDERING HERE IS THE OPPOSITE OF (b)'s, and that is the point: a SKIPPED
        //    line stands INSIDE the guard, i.e. AFTER the guard text and BEFORE the real
        //    rung. #878 forbids announcing a step the guard then skips; announcing that it
        //    WAS skipped is the honest half of the same law.
        //
        // ⚠️ ORDER ALONE IS NOT ENOUGH — the #907 review named the hole: lift the emitter OUT
        //    of the `else { }` onto the statement right after the guard and `g < s < r` still
        //    holds, while the line now fires on EVERY successful move. So ADJACENCY is pinned
        //    too: the emitter must be followed immediately by the guard's own `return`, which
        //    is exactly what it cannot be outside the block.
        for (fn, noOpGuard, skipped, rung) in [
            ("static func upgradeToPlayAndRecord",
             "guard audioSession.category != .playAndRecord",
             "session: raise SKIPPED — category already .playAndRecord",
             "session: raise 1/2 — setCategory"),
            ("static func downgradeToPlaybackAfterRecording",
             "guard isSessionConfigured else",
             "session: lower SKIPPED — never configured; category left as-is",
             "session: lower 1/1 — setCategory"),
            ("static func downgradeToPlaybackAfterRecording",
             "guard audioSession.category != .playback",
             "session: lower SKIPPED — category already .playback",
             "session: lower 1/1 — setCategory"),
        ] {
            XCTAssertEqual(occurrences(of: skipped, in: config), 1, """
                a guard in `\(fn)` no longer says it skipped (#906/#907). It then returns \
                in silence while its caller has already written a line implying the move \
                happened — and by this ladder's own law (#859–#862b) the silence that \
                follows reads as a death inside the step, not as a step that never ran.
                """)
            let emitter = "EchoelCrashLog.breadcrumb(\"\(skipped)\")"
            guard let e = config.range(of: emitter) else {
                XCTFail("the SKIPPED emitter for `\(fn)` is gone — re-anchor (§4).")
                return
            }
            // ⚠️ INDENTATION IS DELIBERATELY NOT PART OF THE NEEDLE. A hard `"\n            "`
            //    would go RED the day the guard is nested one level deeper — a false red on a
            //    correct tree, which is the defect class this bundle exists to avoid (#665).
            //    Only "nothing but whitespace between the emitter and a `return`" is asserted.
            let afterEmitter = config[e.upperBound...].drop { $0.isWhitespace }
            XCTAssertTrue(afterEmitter.hasPrefix("return"), """
                the SKIPPED emitter in `\(fn)` is no longer the last statement before its \
                guard's `return` (#907 review). Outside the `else { }` block the same line \
                fires on every SUCCESSFUL move, so the log then claims a skip that did not \
                happen — the ordering claim below cannot see that, which is why this exists.
                """)
            guard let a = config.range(of: fn) else {
                XCTFail("`\(fn)` is gone — re-anchor (§4). A bare `return` here would have "
                        + "exited the whole test method, taking the remaining tuples, the "
                        + "(c4) claims and the (d) count pin with it, and reported GREEN.")
                return
            }
            let body = String(config[a.lowerBound...].prefix(1_800))
            guard let g = body.range(of: noOpGuard), let s = body.range(of: skipped),
                  let r = body.range(of: rung) else {
                XCTFail("the guard, its SKIPPED line or the real rung left `\(fn)` — "
                        + "re-anchor (§4).")
                return
            }
            XCTAssertTrue(g.lowerBound < s.lowerBound && s.lowerBound < r.lowerBound, """
                the SKIPPED line in `\(fn)` is no longer INSIDE the guard it belongs to. It \
                must sit after the guard and before the real rung: ahead of the guard it \
                announces a skip that may not happen, and after the rung it describes a step \
                that did.
                """)
        }

        // (c3) #907, RESTORED BY THE #908 REVIEW — a SKIPPED step that EXITS must not carry
        //      a rung number. #908's first draft retired this, on the reasoning that the tool
        //      had been taught to read the numbered form. That was wrong, and the review
        //      proved it with a log: `on 4/5 SKIPPED` in `AudioEngine` WALKS ON (`on 5/5:
        //      installing input tap` follows), so a log ending on that line is a death INSIDE
        //      `installTap` — the `isInputConnToConverter` region the ladder exists for — and
        //      the draft printed `⏹ ended`, exit 0, telling the reader not to look there.
        //
        // ⭐ THE REASON IT CANNOT BE FIXED IN THE TOOL: in a LOG, a numbered skip that WALKS ON
        //    and a numbered skip that RETURNS are the SAME SHAPE. Nothing in the line tells
        //    them apart, so the tool must read both as deaths — and this guard is what keeps
        //    the returning kind out of the source. `scripts/diag-ladder.py` now rescues only
        //    an UNNUMBERED terminator, which claims no step and therefore cannot be ambiguous.
        //    So the division of labour is: the TOOL learned `mic: start REFUSED` (mid-ladder,
        //    unnumbered — the case no wording could fix); this CLAIM keeps the ambiguous
        //    spelling out. Neither replaces the other.
        //
        // ⛔ GRADED: red on `da06482` (#906) — it selects both numbered lines — and green on
        //    the worktree. `AudioEngine`'s two legal `on 4/5 SKIPPED:` lines are NOT selected
        //    (their next line is `}`, and `setInputMonitoring` returns `Bool`). What
        //    protects those two lines is claim 12, which pins them PRESENT.
        // ⭐ #913: this half is no longer a tripwire — the two new unnumbered pre-rung skips
        //    (`on SKIPPED`, `off SKIPPED`) ARE selected here and pass, so `AudioEngine` is a
        //    live counterweight. The tripwire caught its first case, which is the outcome a
        //    tripwire is written for.
        for (path, text) in [("Audio/AudioConfiguration.swift", config),
                             ("Audio/AudioEngine.swift",
                              try code("Sources/Echoelmusic/Audio/AudioEngine.swift"))] {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            for (i, line) in lines.enumerated() where line.contains("SKIPPED") {
                let next = lines.dropFirst(i + 1)
                    .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                guard next.hasPrefix("return") || next.hasPrefix("throw") else { continue }

                // Read the MESSAGE, never the line: the stripper only drops lines that BEGIN
                // with `//`, so a trailing `// #907: was 1/2` survives and a raw-line scan
                // would redden a line carrying no number at all.
                guard let open = line.firstIndex(of: "\""),
                      let close = line.lastIndex(of: "\""), open < close else { continue }
                let message = String(line[line.index(after: open)..<close])
                XCTAssertFalse(message.contains("\\("), """
                    a SKIPPED breadcrumb in `\(path)` builds its rung number by interpolation:
                    \(line.trimmingCharacters(in: .whitespaces))
                    Neither this claim nor `scripts/diag-ladder.py` can read that — the tool's \
                    rung regex allows no interpolation in a prefix, so the rung vanishes from \
                    `--source` entirely and the ladder silently reports one emitter fewer.
                    """)
                XCTAssertFalse(carriesRungNumber(message), """
                    a SKIPPED step in `\(path)` is NUMBERED and then exits (#907/#908):
                    \(line.trimmingCharacters(in: .whitespaces))
                    In a LOG this is indistinguishable from a skip that WALKS ON, so \
                    `scripts/diag-ladder.py` must read it as a death — and it will, on a run \
                    that was healthy. Drop the number: an UNNUMBERED skip is a state line the \
                    tool rescues correctly. Numbering stays honest only where the ladder walks \
                    on past it (`on 4/5 SKIPPED`, with `on 5/5` following).
                    """)
            }
        }

        // (c4) #908 — AND THE CLASS BEHIND #906 AND #907 BOTH: a SILENT exit on a route
        //      transition. The #907 review named it — "nothing in the file detects a NEW
        //      silent return added to either function" — which is exactly how the
        //      `isSessionConfigured` gap survived a whole cycle. Every exit from the two
        //      session moves must ANNOUNCE itself. No number to go stale (#903).
        //
        // ⛔ ITS FIRST DRAFT WAS WRONG IN BOTH DIRECTIONS, mutation-driven by the #908 review:
        //    it FALSE-REDDENED a wrapped breadcrumb (the form written in the very file it
        //    scans, `route: release … FAILED (`), a widened `#if os(macOS) || os(watchOS)`,
        //    and a `return` inside a nested closure; and it stayed GREEN on `if x { return }`,
        //    on `else{return}` without inner spaces, on a trailing-comment `return`, and on a
        //    silent `throw` — the last a straight regression, since the claim it replaced
        //    covered `throw` explicitly. Both halves are rewritten below.
        //
        // ⭐ GRADED ACROSS THREE TREES: `b0d6480` → BOTH functions red, `da06482` (#906) →
        //    `downgradeToPlaybackAfterRecording` red, worktree → green. Plus four mutants
        //    driven on the worktree: wrapped breadcrumb GREEN, trailing comment GREEN,
        //    `if … { return }` RED, silent `throw` RED.
        for fn in ["static func upgradeToPlayAndRecord",
                   "static func downgradeToPlaybackAfterRecording"] {
            guard let a = config.range(of: fn) else {
                XCTFail("`\(fn)` is gone — re-anchor (§4). This `return` exits the whole test "
                        + "method, so the claims below it do not run either (#907 review).")
                return
            }
            // Bounded by the NEXT declaration, never by a character budget: a window that
            // overruns into the next function counted five exits where there are two.
            let rest = config[a.upperBound...]
            let end = rest.range(of: "\n    static func")?.lowerBound ?? rest.endIndex
            let body = String(rest[..<end])

            // Whitespace-squashed, so `else { return }`, `else{return}` and `if x { return }`
            // are one shape. `{throw` is here because both functions are `throws`.
            let squashed = body.split(whereSeparator: { $0.isWhitespace }).joined()
            for silent in ["{return", "{throw"] {
                XCTAssertFalse(squashed.contains(silent), """
                    `\(fn)` has a one-line silent exit (`\(silent)…`) — an exit on a route
                    transition that writes nothing (#908). Its caller has already written
                    `route: …`, so by this ladder's own law (#859–#862b) the silence that
                    follows reads as a death inside the step. Put a breadcrumb in the block
                    before the exit, unnumbered.
                    """)
            }

            let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let statement = trimmed.components(separatedBy: "//")[0]
                    .trimmingCharacters(in: .whitespaces)
                guard statement == "return" || statement.hasPrefix("return ")
                        || statement.hasPrefix("throw ") else { continue }

                // Walk back to the line that OPENS the enclosing block and look at the whole
                // block, not at one line: the announcing breadcrumb is often wrapped over two.
                var block: [String] = []
                var compileTimeOnly = false
                for previous in lines[..<i].reversed() {
                    let p = previous.trimmingCharacters(in: .whitespaces)
                    if p.isEmpty { continue }
                    if p.hasPrefix("#if os(macOS)") { compileTimeOnly = true; break }
                    if p.hasSuffix("{") { break }
                    block.append(p)
                }
                if compileTimeOnly { continue }

                XCTAssertTrue(block.contains { $0.contains("EchoelCrashLog.breadcrumb(") }, """
                    an exit in `\(fn)` is not announced (#908):
                    \(trimmed)
                    Nothing in its block writes a breadcrumb, so the log shows `route: …`
                    followed by silence and the next reader calls that a death. The
                    `#if os(macOS)` return is exempt — it is compile-time, so no iOS log can
                    ever show it.
                    """)
            }
        }

        // (d) The rung count is pinned so a rung added to a REPEATING path is visible. It is
        //     a checklist, not an objection. If this number moved, check the new site is a
        //     discrete lifecycle event and not something that runs per buffer — `breadcrumb`
        //     allocates and does an unbuffered `write(2)`.
        //
        // ⛔ #903 — THIS PIN WAS RED ON A CORRECT TREE FOR THIRTEEN COMMITS, and that is the
        // whole reason it exists. It said 8: seven transition rungs plus `latencyBreadcrumb`.
        // #888 then added THREE `route:` lines (one claim, two release) and did not come back
        // here — its commit message says "the tool still derives exactly 8 ladders", which is
        // `diag-ladder.py`'s ladder count, a DIFFERENT quantity that happens to share the
        // number. Measured: `bd38cc3~1` = 8, `bd38cc3`…#902's parent = 11, today = 12. Nothing
        // caught it because §5 holds — the pipeline reports `failure` on every push, so a
        // genuinely red guard is indistinguishable from the host dying (#655/#656).
        //
        // ⚠️ AND #902 WALKED PAST IT AGAIN. Its commit message claims "all eleven neighbouring
        // claims over this file drive GREEN on both trees". This is the TWELFTH, it is over
        // this file, and it counts the very line #902 added — the #453→#477 rule reproduced
        // exactly: a hand survey said eleven, and a guard selected a twelfth.
        //
        // ⭐ #906 — AND THE TOOL WRITTEN FOR THIS PIN CAUGHT ITS NEXT MOVE, ONE CYCLE LATER.
        // #906 added two SKIPPED lines; `python3 scripts/count-pins.py` printed
        // `pinned 12, actual 14` before the commit existed. The same drift went unseen for
        // thirteen commits when only CI was watching (#903). That is the whole argument for
        // the checker, in one line of output.
        //
        // ⭐ #907 — AND IT CAUGHT ITS OWN NEXT MOVE AGAIN, WHICH IS THE POINT OF A CHECKER
        // THAT RUNS LOCALLY: #907 gave the third silent return (`guard isSessionConfigured`)
        // a line, so the tool printed `pinned 14, actual 15` before the commit existed.
        //
        // TODAY'S ARITHMETIC: seven transition rungs + THREE `SKIPPED` state lines +
        // `latencyBreadcrumb` + one `route: claim` + THREE `route: release` outcomes = 15.
        XCTAssertEqual(occurrences(of: "EchoelCrashLog.breadcrumb(", in: config), 15, """
            The breadcrumb count in AudioConfiguration changed. Confirm the new site is a \
            discrete event (launch, route transition), never a per-buffer or tick-rate path, \
            then update this number and say why in the same commit. Today: seven transition \
            rungs + three SKIPPED state lines + latencyBreadcrumb + one route claim + three \
            route-release outcomes.
            """)
    }

    // MARK: - 14: the INPUT SWITCH reaches the exported log (#880)

    /// ⛔ THE GAP THIS CLOSES IS NOT A TRAILING RUNG — IT IS A MISSING EVENT. Every line in
    /// `AudioInputManager` went to `log.audio` (os_log), and os_log does not appear in the
    /// exported `echoel_diag.log`. A founder who switched to a headset mic and then hit the
    /// `isInputConnToConverter` abort handed over a log in which the switch never happened.
    /// `setPreferredInput` moves the hardware input under a possibly-running graph.
    func testTheInputSwitchIsInTheDiagLog() throws {
        let inputs = try code("Sources/Echoelmusic/Audio/AudioInputManager.swift")

        for rung in ["EchoelCrashLog.breadcrumb(\"input: select IGNORED — uid no longer available\")",
                     "EchoelCrashLog.breadcrumb(\"input: select FAILED ("] {
            XCTAssertEqual(occurrences(of: rung, in: inputs), 1,
                           "`\(rung)` is gone — an input switch stops reaching the exported log (#880).")
        }

        // ⚠️ THE OTHER TWO RUNGS ARE IN A DOORLESS FUNCTION, and they get their own message
        // because the one above would be FALSE for them (#367: fail for the reason stated).
        // `useSystemDefault()` has no caller in `Sources/`, so these can never fire today.
        // They are pinned anyway — the strings are the contract for the day it gets a door,
        // and dropping them would quietly make the two directions asymmetric.
        for dormant in ["EchoelCrashLog.breadcrumb(\"input: select → system default\")",
                        "EchoelCrashLog.breadcrumb(\"input: system default FAILED ("] {
            XCTAssertEqual(occurrences(of: dormant, in: inputs), 1,
                           "`\(dormant)` is gone. It could not fire anyway — `useSystemDefault()` "
                           + "is doorless — but it is the symmetric inverse of the select rung "
                           + "and the contract for the day that function gets a door (#880).")
        }

        // ⛔ The select rung is a WRAPPED concatenation, so it is anchored on the string
        // LITERAL alone — never on the call spelling plus its line break and indentation.
        // That mistake has now been made twice in this file's history (#871, #877): such a
        // needle pins a FORMATTING choice and goes red on a reflow that changes nothing.
        XCTAssertEqual(occurrences(of: "\"input: select → \"", in: inputs), 1,
                       "the select rung's literal is gone — an input switch stops naming "
                       + "the device it switched to (#880).")

        // ORDER: the rung stands BEFORE the call it names (#860).
        guard let rung = inputs.range(of: "\"input: select → \""),
              let call = inputs.range(of: "try session.setPreferredInput(port)") else {
            XCTFail("the select rung or its `setPreferredInput` call is gone — re-anchor (§4).")
            return
        }
        XCTAssertTrue(rung.lowerBound < call.lowerBound, """
            The select rung sits AFTER `setPreferredInput` (#860/#880). A death inside the \
            route move is then silence, and the log reads as "the user never switched".
            """)
        try assertNoUIDInAnyBreadcrumb(inputs)
    }

    /// ⚠️ PRIVACY, and it is a PREMISE this claim depends on rather than one it invents.
    /// Port NAMES already reach the exported file: `AudioConfiguration.latencyBreadcrumb`
    /// writes a `route:` field built from `routeLabel(portName:portType:)`. So #880 reusing
    /// that helper is consistent with the established discipline, not a new exposure. If
    /// those call sites ever go away, the argument for writing a port name into an input
    /// rung goes with them — hence the pin.
    ///
    /// The raw UID is a different matter and must NOT be written: it is opaque to a reader
    /// and can be MAC-derived for a Bluetooth device, so it adds risk and no information.
    func testTheInputRungsBorrowTheExistingRouteLabelAndNeverTheUID() throws {
        // ⛔ A PIN ON `routeLabel`'s TWO MAP SITES STOOD HERE AND IS DELETED, NOT KEPT:
        // `TheBluetoothCodecReachesTheScreenTests` already pins exactly that (#416). Two
        // homes for one decision means a later edit has two messages to reconcile, and this
        // was the newer and weaker of the pair. The premise it guarded — that port names
        // already reach the exported file — is verified in that test's home, not here.
        let inputs = try code("Sources/Echoelmusic/Audio/AudioInputManager.swift")
        XCTAssertEqual(occurrences(of: "AudioConfiguration.routeLabel(portName: port.portName,",
                                   in: inputs), 1, """
            The input rung no longer borrows `routeLabel` — a second spelling of the device \
            label is a second place to keep honest (#416), and it loses the Bluetooth marker.
            """)

        // ⛔ AND THIS IS THE HALF THE FIRST DRAFT DROPPED — a REOPENED #654, caught in
        // review. `latencyLine` writes `sanitisedRoute(route)`, never the raw label, because
        // a port name is externally controlled: `looksLikeUnseenCrash` is a bare
        // `contains(crashMarker)`, so an unmasked device name carrying that marker makes
        // every later launch open the crash sheet on a session that never crashed. The
        // existing guard for that hole only inspects the `sanitisedRoute` path — it would
        // have stayed GREEN while this new writer walked around it. THAT is why the pin is
        // here and not there: it guards the BYPASS, which the other test cannot see.
        XCTAssertEqual(occurrences(of: "AudioConfiguration.sanitisedRoute(", in: inputs), 3, """
            An input rung writes an externally controlled string without `sanitisedRoute` \
            (#654/#880) — the device label, or an OS `localizedDescription` that can carry \
            one. Unmasked, a device named after the crash marker forges a crash on every \
            later launch; a newline in it splits a rung across two lines, and `lastScenePhase` \
            parses this file line by line.
            """)
        try assertNoUIDInAnyBreadcrumb(inputs)
    }

    // MARK: - 16: a numbered step ALWAYS emits — taken or skipped (#882)

    /// ⛔ THE LADDER ITSELF WAS LYING ABOUT ITS OWN LENGTH, in the one path the founder was
    /// asked to exercise. Three of the monitoring ladder's rungs were CONDITIONAL:
    ///   · `on 4/5` ran only `if wasRunning`
    ///   · `on 5/5` ran only `if !monitorTapInstalled`
    ///   · `off 5/5` did not exist at all — a source comment said the restore "is" step 5,
    ///     but `restoreEngineIfStranded` writes NOTHING when it returns early, and its line
    ///     is written INSIDE the call rather than before it.
    /// So a perfectly healthy ON could log 1/5, 2/5, 3/5 and stop, and a normal OFF logged
    /// four rungs out of an announced five. By THIS LADDER'S OWN LAW — "silence between two
    /// rungs is a FINDING" — both read as a death. The numbering has to be honest or the law
    /// on top of it is worse than no ladder: it manufactures findings.
    ///
    /// ⚠️ The repair is NOT to make the rungs unconditional. Announcing a step the code then
    /// skips is the #878 mistake in the other direction. A skipped step says it was skipped.
    func testEveryNumberedMonitoringStepEmitsEitherWay() throws {
        let code = try code(Self.enginePath)

        // Every number 1…5 exists on both sides. Silence at N then means death at N.
        for n in 1...5 {
            XCTAssertTrue(code.contains("\"on \(n)/5"), """
                The monitoring ON ladder has no emitter for step \(n) of 5 (#882). A reader \
                counting rungs treats the gap as a death; make the step say it was skipped \
                rather than dropping its number.
                """)
            XCTAssertTrue(code.contains("\"off \(n)/5"), """
                The monitoring OFF ladder has no emitter for step \(n) of 5 (#882). This is \
                exactly how `off 5/5` went missing: a comment claimed a differently-named \
                line covered it, and that line is conditional AND written after its own call.
                """)
        }

        // The two conditional ON steps must carry BOTH an emitter for taken and for skipped.
        for step in ["on 4/5", "on 5/5"] {
            XCTAssertEqual(occurrences(of: "\"\(step)", in: code), 2, """
                `\(step)` no longer has both a taken and a SKIPPED emitter (#882). It is \
                gated (`wasRunning` / `!monitorTapInstalled`), so without the skip line a \
                healthy run looks like it died there.
                """)
        }
        for skip in ["on 4/5 SKIPPED", "on 5/5 SKIPPED"] {
            XCTAssertEqual(occurrences(of: skip, in: code), 1,
                           "the `\(skip)` line is gone — the gated step falls silent again (#882).")
        }

        // ORDER on the new OFF rung: it stands BEFORE the call it names (#862b).
        guard let rung = code.range(of: "\"off 5/5: restoring engine if stranded"),
              let call = code.range(of: "restoreEngineIfStranded(offWasRunning,") else {
            XCTFail("the `off 5/5` rung or its restore call is gone — re-anchor (§4).")
            return
        }
        XCTAssertTrue(rung.lowerBound < call.lowerBound, """
            The `off 5/5` rung sits AFTER the restore it names (#862b/#882). A death inside \
            the restart is then indistinguishable from a death in the route release above it.
            """)
    }

    /// No `breadcrumb` line in the given source may interpolate the input UID.
    private func assertNoUIDInAnyBreadcrumb(_ source: String) throws {
        for line in source.split(separator: "\n", omittingEmptySubsequences: false)
        where line.contains("EchoelCrashLog.breadcrumb") {
            XCTAssertFalse(line.contains("\\(id)"), """
                A breadcrumb writes the raw input UID: \(line.trimmingCharacters(in: .whitespaces)). \
                A UID is opaque to a reader and can be MAC-derived on Bluetooth — it adds risk \
                and no information. Write the device label through \
                `AudioConfiguration.routeLabel` instead (#880).
                """)
        }
    }

    // MARK: - 17: the record route says WHO holds the mic, and both release exits speak
    //
    // WHY THIS IS NOT COVERED BY CLAIM 13. Claim 13 pins the session-CATEGORY ladder
    // (`session: configure|raise|lower`), which speaks only when the category actually
    // moves. The first claim on the record route raises it and prints `session: raise`;
    // a SECOND claim raises nothing and, before #888, printed nothing at all. So the
    // exported log could not tell ONE mic owner from TWO — and two owners on the one HAL
    // input is exactly the shape `AudioEngine` names for the `isInputConnToConverter`
    // family. It is reachable today: voice capture (`microphoneManager`) can run while
    // `inputMonitoring` holds the route.
    //
    // ⚠️ STATE LINES, NOT A LADDER, and the distinction is load-bearing. `n/N` rungs are a
    // fixed sequence whose silence localises a death; these transitions have no length and
    // interleave between owners. `scripts/diag-ladder.py` only treats `n/N` as a rung, so
    // numbering these would invent a ladder a reader would then try to walk. Claim (d)
    // pins that they stay unnumbered.
    //
    // GRADING AGAINST THE PARENT (§3), transcribed in Python and driven against
    // `git show HEAD:…` and the worktree — booked in the HARSH direction on purpose:
    // (a), (b) and the sorted half of (d) are red on HEAD, and (c) fails there by ANCHOR
    // ABSENCE. That is ONE finding reported four times (#486), not four regressions: the
    // breadcrumbs do not exist on the parent, so no assertion there is red "for the reason
    // its name gives". Honestly, this is a FORWARD guard for a mechanism this same commit
    // creates. The single genuine COUNTERWEIGHT is the unnumbered half of (d) — green on
    // both trees, and the one assertion that constrains a future edit rather than this one.
    func testTheRecordRouteNamesItsHolders() throws {
        let config = try code(Self.configPath)

        // (a) Both transitions speak, and the owner is named on each.
        for needle in ["\"route: claim \\(owner.rawValue)",
                       "\"route: release \\(owner.rawValue)"] {
            XCTAssertTrue(config.contains(needle), """
                the record route no longer names \(needle.contains("claim") ? "claims" : "releases") \
                in the diag log (#888). Without the owner the line cannot answer the one question \
                it exists for: how many owners held the mic when it died.
                """)
        }

        // (b) BOTH release exits emit — the #882 law. The early return ("someone else still
        //     holds it") is the one that was silent, and a silent taken path makes a healthy
        //     release look identical to one that died inside the downgrade.
        // ⛔ #902 RAISED THIS FROM 2 TO 3, and the old count was RIGHT about exits and WRONG
        // about outcomes. There are two EXITS but three OUTCOMES: other owners remain · the
        // lowering worked · the lowering THREW. NINE of the TWELVE release call sites are
        // `try?` (⛔ #903: #902 wrote "eight of thirteen" here and in the source; measured,
        // `git grep -c "releaseRecordRoute(" -- Sources` = 14 hits = 12 sites + declaration +
        // one doc mention, of which 9 are `try?` and 3 are `do`/`catch`), so the third was
        // swallowed and shared the second's line — "lowering" followed
        // by silence, which is exactly the #882 defect this claim was written to prevent, one
        // level further in. If you add or remove an outcome, change this number AND name the
        // outcome in this message (#364/#655).
        XCTAssertEqual(occurrences(of: "\"route: release", in: config), 3, """
            `releaseRecordRoute` no longer emits on all THREE outcomes (#888/#882/#902): the \
            early return when other owners remain, the successful lowering, and the lowering \
            that threw. One line for two outcomes is how a taken branch goes dark.
            """)
        // ⛔ #903 — THE NEW LINE WALKED AROUND THIS FILE'S OWN SANITISER. `AudioInputManager`
        // wraps every `error.localizedDescription` it writes to a breadcrumb in
        // `sanitisedRoute(…)` (#654/#880) and is guarded for it here; #902 wrote an OS-supplied
        // string raw, 890 lines ABOVE the sanitiser's own declaration. The three hazards are
        // the same ones that policy enumerates: the substring `CRASH` makes every later launch
        // auto-open the crash sheet (`looksLikeUnseenCrash` is a `contains`), a newline splits
        // one line into two for every line-by-line parser of this log, and there is no length
        // bound while `currentLog()` reads the whole file into one `String`.
        XCTAssertTrue(config.contains("sanitisedRoute(error.localizedDescription)"), """
            the failed-lowering line writes an OS-supplied error string RAW (#903). Wrap it in \
            `sanitisedRoute(…)` like every other externally sourced breadcrumb: it masks the \
            crash marker, flattens newlines and bounds the length. A guard covering exactly \
            this hole exists for `AudioInputManager` and did not cover this file.
            """)
        XCTAssertTrue(config.contains("category still raised, nobody holds it"), """
            the failed-lowering line lost the half that makes it actionable (#902). The owner \
            set is already empty at that point, so nothing will retry until the next session \
            transition — a reader has to be told the category is up with NOBODY holding it, or \
            the line reads like an ordinary error. ⚠️ Its wording deliberately avoids "route \
            stays up": that phrase belongs to the early-return line and is pinned above, and a \
            second line carrying it would satisfy that claim while the early-return line had \
            lost its own words (#367).
            """)
        XCTAssertTrue(config.contains("route stays up"), """
            the early-return release line lost its outcome wording. "route stays up" is what \
            distinguishes it from the lowering line in a log read months later.
            """)

        // (c) ORDER (#862b): the claim rung stands BEFORE the call that can throw. The Set
        //     insert cannot fail; `upgradeToPlayAndRecord()` does AVAudioSession work.
        guard let rung = config.range(of: "\"route: claim"),
              let call = config.range(of: "try upgradeToPlayAndRecord()") else {
            XCTFail("""
                the claim rung or its upgrade call is gone — re-anchor this scan rather than \
                letting it pass (§4).
                """)
            return
        }
        XCTAssertTrue(rung.lowerBound < call.lowerBound, """
            the `route: claim` line now sits AFTER `upgradeToPlayAndRecord()`. A witness \
            behind the step it names sees nothing when that step dies, and the log then reads \
            as "route never claimed" instead of "claim died mid-upgrade" (#862b).
            """)

        // (d) The owner list is SORTED, and the lines stay unnumbered.
        XCTAssertTrue(config.contains(".sorted().joined(separator: \"+\")"), """
            the route owner list is no longer sorted (#888). `Set` has no order, so an \
            unsorted join prints the SAME state two different ways between runs and a reader \
            comparing logs sees a permutation as a state change.
            """)
        // (e) The release path reads the owner set ONCE and both the branch and the message
        //     derive from that snapshot (audio-thread review of #888, finding 3). Two reads
        //     of `nonisolated(unsafe)` storage would let the printed holders disagree with
        //     the branch actually taken — the log would LIE rather than crash. Unreachable
        //     today; pinned because "the line describes the branch" is the whole point.
        XCTAssertTrue(config.contains("let remaining = recordRouteOwners")
                      && config.contains("guard remaining.isEmpty else"), """
            `releaseRecordRoute` no longer takes ONE snapshot of the owner set for both its \
            branch and its breadcrumb (#888). Re-reading the shared static twice is how the \
            printed holders and the branch taken can drift apart. If the storage was made \
            properly isolated instead, that is a better fix — retire this claim in the same \
            commit rather than working around it (#364).
            """)

        for numbered in ["route: claim 1/", "route: release 1/"] {
            XCTAssertFalse(config.contains(numbered), """
                a `route:` line was numbered like a ladder rung (#888). These are state \
                transitions with no length; `scripts/diag-ladder.py` would then announce a \
                ladder that cannot be walked. If a real route LADDER is ever wanted, give it \
                its own prefix and update this claim in the same commit — this forbids the \
                numbering, not the work (#364).
                """)
        }
    }

    // MARK: - 18: the two PRE-RUNG exits of setInputMonitoring announce themselves (#913)

    /// ⭐ #906 gave the two SESSION moves a SKIPPED line and #907 unnumbered it. The MONITORING
    /// ladder still had two silent ones, and they are the more visible half: they sit at the
    /// very top of `setInputMonitoring`, so a call that finds monitoring already in the
    /// requested state returns success having written NOTHING. In a founder log that is
    /// indistinguishable from a death before rung 1 — this ladder's own law (#859) reads
    /// silence between rungs as a death, and what a reader sees is a toggle followed by no
    /// `monitor:` ladder at all.
    /// ⛔ #913 REVIEW, HIGH-2: the first draft said the ON path's neighbour is `route: claim …`
    /// "which is exactly where four device logs stopped". BOTH halves were false. `route:
    /// claim` is written inside `claimRecordRoute`, which this method reaches only AFTER rung
    /// `on 1/5` — so it cannot precede an exit that returns before rung 1. And it was
    /// introduced by #888, AFTER the last device log in hand (v10.79.429), so no log the
    /// founder has sent can contain it. The sentence was transplanted from
    /// `AudioConfiguration`, where it is true. The argument needs neither half.
    ///
    /// ⚠️ UNNUMBERED IS LOAD-BEARING, AND CORRECT ONLY HERE (#907/#908). `on 4/5 SKIPPED`
    /// walks on to `on 5/5`; a skip that RETURNS ends the ladder. Once a number is present
    /// those two are the SAME STRING in a log, so `scripts/diag-ladder.py` may treat only an
    /// UNNUMBERED terminal word as `⏹ ended`. These two exits precede EVERY rung of their
    /// ladder, so unnumbered is right. Do not relax this into "skips are unnumbered".
    ///
    /// ⚠️ WHAT THIS CLAIM DOES **NOT** SAY: nothing here proves the lines reach the exported
    /// file. That is claim 7's job (`logMonitorOutcome` writes the durable sink FIRST); this
    /// one only proves the two exits emit at all, unnumbered, before returning.
    func testTheMonitoringPreRungExitsSpeak() throws {
        let engine = try code(Self.enginePath)
        let exits: [(needle: String, what: String)] = [
            ("logMonitorOutcome(\"on SKIPPED", "the ON path's already-engaged no-op"),
            ("logMonitorOutcome(\"off SKIPPED", "the OFF path's never-engaged no-op")
        ]
        for site in exits {
            XCTAssertTrue(engine.contains(site.needle), """
                \(site.what) is silent again. It returns before rung 1, so the exported log \
                shows the caller's line and then nothing from this method — which the ladder \
                law reads as a DEATH. Emit an UNNUMBERED SKIPPED through \
                `logMonitorOutcome` before the `return`.
                """)
            let line = lineContaining(site.needle, in: engine)
            XCTAssertFalse(carriesRungNumber(line), """
                \(site.what) now carries a rung NUMBER: \(line)

                A numbered skip is ambiguous in a LOG — `on 4/5 SKIPPED` walks on, a skip \
                that returns ends the ladder, and both print the same string. \
                `scripts/diag-ladder.py` therefore keeps reading numbered skips as deaths. \
                Drop the number, or this exit turns a real death into `⏹ ended`.
                """)
        }
        // ⭐ ADJACENCY, not mere presence (#907 M2): a breadcrumb that drifted out of the
        // guard block would still satisfy the two assertions above while the exit went
        // silent again. `code(_:)` deletes whole-line comments, so the emitter really is
        // the next line after the `guard` in the stripped text.
        for (opener, needle) in [("guard !isInputMonitoring else {", "on SKIPPED"),
                                 ("guard isInputMonitoring else {", "off SKIPPED")] {
            // ⚠️ The block-opening form is unique only by ACCIDENT: `guard isInputMonitoring
            // else {` appears six times in this file, five of them one-liners. Converting any
            // of those five to a block would give `range(of:)` a second candidate and this
            // claim would silently start checking the WRONG guard. So the count is asserted
            // BEFORE the anchor is used — a re-target must be loud.
            let opens = occurrences(of: opener + "\n", in: engine)
            XCTAssertEqual(opens, 1, """
                `\(opener)` opens \(opens) blocks in AudioEngine.swift, expected exactly 1. \
                At 0 the anchor is gone and this claim proves nothing while reporting GREEN \
                (#454). Above 1 it silently targets whichever comes first, which may not be \
                the pre-rung exit at all. Re-anchor in the same commit.
                """)
            guard opens == 1, let g = engine.range(of: opener + "\n") else { continue }
            let next = String(engine[g.upperBound...].prefix(while: { $0 != "\n" }))
                .trimmingCharacters(in: .whitespaces)
            // ⛔ #913 REVIEW, HIGH-1: the first draft asserted `next.contains(needle)`, and an
            // `if masterEngine.isRunning { logMonitorOutcome("on SKIPPED …") }` INSIDE the
            // guard passed it while the exit stayed silent on the path that matters. That is
            // #631/#910 verbatim, and the repair already stood 1100 lines above in claim 6.
            // The line must BEGIN with the sink call — a condition in front of it is exactly
            // the failure this claim exists to catch, not a stylistic variation.
            XCTAssertTrue(next.hasPrefix("logMonitorOutcome("), """
                The line inside \(opener) does not BEGIN with `logMonitorOutcome(` — it is: \
                \(next)

                A conditional emitter is the failure mode here, not an edge case: wrapped in \
                an `if`, the breadcrumb is present in the file and absent from the log on \
                whichever path actually returns.
                """)
            XCTAssertTrue(next.contains(needle), """
                The `\(needle)` breadcrumb no longer stands immediately inside \(opener); \
                the next line is: \(next)

                A rung stands BEFORE its step and INSIDE the block it describes (#859). \
                Anything between the guard and its announcement can return first.
                """)
        }
    }

    /// True when the message carries a ladder rung NUMBER (`n/N`) — the shape
    /// `scripts/diag-ladder.py` walks. Digit-slash-digit, no regex: a spaced division
    /// (`a / b`) is deliberately not a match, and neither is a bare `/` in prose.
    /// The single trimmed source line that carries `needle` — so a claim can read what the
    /// code actually emits instead of the literal this test file wrote (#910 review, M3).
    private func lineContaining(_ needle: String, in text: String) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false)
        where line.contains(needle) {
            return line.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    private func carriesRungNumber(_ line: String) -> Bool {
        let c = Array(line)
        guard c.count > 2 else { return false }
        for i in 1..<(c.count - 1) where c[i] == "/" {
            if c[i - 1].isNumber && c[i + 1].isNumber { return true }
        }
        return false
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func code(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let text = try String(contentsOf: root.appendingPathComponent(relativePath),
                              encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}
