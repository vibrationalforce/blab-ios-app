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
                       "logEngineLifecycle(\"interruption ended — restarting\")",
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
                       "EchoelCrashLog.breadcrumb(\"mic: stop — releasing capture engine + route\")"] {
            XCTAssertEqual(occurrences(of: needle, in: mic), 1,
                           "`\(needle)` is gone — the mic capture chain falls diag-dark again (#859b).")
        }
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
    /// FIFTH `masterEngine.start()` in the file and the only one without a rung — and #858
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

    // MARK: - helpers (the house shape: strip comments, skip on no tree)

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
