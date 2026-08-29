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

import Foundation
import XCTest
@testable import Echoelmusic

final class TheEngineLifecycleSpeaksInTheDiagLogTests: XCTestCase {

    private static let enginePath = "Sources/Echoelmusic/Audio/AudioEngine.swift"

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
    /// `MicrophoneManager` claims at :207 and reads at :218, `MultiTrackRecorder` claims
    /// before its read (and is doorless anyway, #204).
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
        for stage in ["logMonitorOutcome(\"on 1/5", "logMonitorOutcome(\"on 2/5",
                      "logMonitorOutcome(\"on 3/5", "logMonitorOutcome(\"on 4/5",
                      "logMonitorOutcome(\"on 5/5"] {
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
            ("static func upgradeToPlayAndRecord", "session: raise 1/2",
             "setCategory(.playAndRecord, mode: .default, options: recordOptions)"),
            ("static func upgradeToPlayAndRecord", "session: raise 2/2",
             "setActive(true, options: .notifyOthersOnDeactivation)"),
            ("static func downgradeToPlaybackAfterRecording", "session: lower 1/1",
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
             "guard audioSession.category != .playAndRecord", "session: raise 1/2"),
            ("static func downgradeToPlaybackAfterRecording",
             "guard audioSession.category != .playback", "session: lower 1/1"),
        ] {
            guard let a = config.range(of: fn) else { return }
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

        // (d) The rung count is pinned so a rung added to a REPEATING path is visible. It is
        //     a checklist, not an objection: seven transition rungs plus `latencyBreadcrumb`,
        //     which is a measurement and not part of the ladder. If this number moved, check
        //     the new site is a discrete lifecycle event and not something that runs per
        //     buffer — `breadcrumb` allocates and does an unbuffered `write(2)`.
        XCTAssertEqual(occurrences(of: "EchoelCrashLog.breadcrumb(", in: config), 8, """
            The breadcrumb count in AudioConfiguration changed. Confirm the new site is a \
            discrete event (launch, route transition), never a per-buffer or tick-rate path, \
            then update this number and say why in the same commit.
            """)
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
