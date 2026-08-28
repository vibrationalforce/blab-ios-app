// TheMonitorSurgeryQuietsTheEngineTests — pins #831, the isInputConnToConverter fix.
//
// THE CRASH (founder device log v10.79.421, build 2539): `required condition is
// false: false == isInputConnToConverter` → SIGABRT, thrown SYNCHRONOUSLY out of a
// toggle's Binding set, ~2 s after "megaphone on". Two sites did graph surgery on
// the monitor chain while the engine RENDERED — the monitoring-OFF teardown
// (removeTap + three disconnects) and setVoiceTune's live rewire through the
// time-pitch node (converter machinery, the assert's exact subject) — while the
// file's own #628 block says every sibling site quiets the engine first. Whichever
// of the two the founder's finger hit, the root cause is shared and both are fixed:
// no monitor-chain surgery on a running engine.
//
// ⛔ #836 — AND THE THIRD DEVICE LOG (v10.79.424, 2542) PINNED THE REAL SITE. The
// assert survived #835 because the crash is not in the teardown at all: the OFF
// path disconnected every monitor node EXCEPT the input's own edge, released the
// record route (session → playback-only), and then restart()ed an engine whose
// graph still wired `input → notchEQ` — an input node with no input scope. #831's
// stop made that reachable on EVERY off-toggle (we always stop, so the restore
// always restarts). v421's crash was the live teardown (one AVFAudio stack shape);
// v422/v424's is the restart (another). Claim 3 pins the input-edge disconnect at
// both restart-preceding sites: the OFF teardown and the ON rollback.
//
// ⛔ #835 — THE PAUSE HALF OF #831 WAS FALSIFIED BY THE NEXT DEVICE LOG. v10.79.422
// (2540), the build WITH #831, crashed with the SAME assert, again out of a
// toggle's Binding set. Of the two sites only setVoiceTune still merely PAUSED —
// and #823 already measured that pause() keeps the built I/O unit (converter
// machinery included) alive. The measured-safe state is the stop the ON path uses,
// proven in the same log (`monitor: ON` = stop → connect input chain → start).
// Claim 2 therefore pins a STOP now; its first shipped form pinned the pause and
// was red-by-design the day this falsification landed.
//
// SOURCE-TEXT SCANS (§1) — no AVAudioEngine runs in a test host; the "no more
// SIGABRT" fact itself is the founder's next device log. Comment lines stripped
// (#491: the retraction docs quote the old defense).
//
// #364: stop-around-surgery is the law this file pins; a redesign that makes
// surgery safe another way must re-anchor these claims in the same commit and pull
// the #831/#835 blocks in AudioEngine.swift plus the SESSION_LOG entries (#456).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMonitorSurgeryQuietsTheEngineTests: XCTestCase {

    private func engineCode() -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Echoelmusic/Audio/AudioEngine.swift")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: AudioEngine.swift could not be read — fail, not skip (§4)")
            return ""
        }
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: - 1. The OFF teardown stops the engine BEFORE touching the graph

    func testTheOffTeardownStopsBeforeTheFirstGraphTouch() {
        let code = engineCode()
        guard !code.isEmpty else { return }
        // The OFF branch's guard is unique in the file (driven before shipping).
        guard let off = code.range(of: "guard isInputMonitoring else { return true }") else {
            XCTFail("The OFF branch's guard is gone — re-anchor this claim (§4).")
            return
        }
        let window = String(code[off.lowerBound...].prefix(900))
        guard let stop = window.range(of: "if offWasRunning { masterEngine.stop() }"),
              let tap = window.range(of: "removeTap(onBus: 0)") else {
            XCTFail("""
                The OFF teardown lost its stop (or its removeTap moved out of the \
                window). Tearing the monitor chain down under a running render is the \
                v10.79.421 SIGABRT (isInputConnToConverter) — re-anchor or restore.
                """)
            return
        }
        XCTAssertTrue(stop.lowerBound < tap.lowerBound, """
            The stop comes AFTER the first graph touch — the render can still race \
            the teardown, which is the v10.79.421 crash unfixed in a new order.
            """)
        XCTAssertTrue(code.contains("restoreEngineIfStranded(offWasRunning, at: \"input monitoring off\")"), """
            The OFF path no longer restores the engine it stopped — monitoring off \
            would leave the WHOLE app silent (the #611 stranded class). The stop at \
            the top and this restore are one mechanism; move them together.
            """)
    }

    // MARK: - 2. The voice-tune rewire STOPS around the surgery (#835)

    func testTheVoiceTuneRewireStopsAroundTheSurgery() {
        let code = engineCode()
        guard !code.isEmpty else { return }
        guard let fn = code.range(of: "func setVoiceTune") else {
            XCTFail("setVoiceTune is gone — re-anchor this claim (§4).")
            return
        }
        let window = String(code[fn.lowerBound...].prefix(1_600))
        guard let stop = window.range(of: "if wasRunning { masterEngine.stop() }"),
              let surgery = window.range(of: "disconnectNodeOutput(notchEQ)") else {
            XCTFail("""
                setVoiceTune lost its stop (or its surgery moved out of the window). \
                Rewiring the input-fed chain through the time-pitch node (converter \
                machinery) without releasing the I/O unit is the founder-measured \
                SIGABRT — TWICE: v10.79.421 with no quieting at all, and v10.79.422 \
                with a mere pause() (#835). Only a stop is measured safe; do not \
                restore either weaker form.
                """)
            return
        }
        XCTAssertTrue(stop.lowerBound < surgery.lowerBound, """
            The stop comes AFTER the first disconnect — the surgery still races the \
            live converter machinery.
            """)
        XCTAssertTrue(window.contains("restartOrDegrade(after: \"voice tune rewire\")"), """
            The rewire's restart-failure path is gone. The stop creates exactly the \
            start()-can-fail case the old doc said did not exist — without this \
            fallback a failed restart strands the whole app silent (#611).
            """)
    }

    // MARK: - 3. Every restart after a route release sees the launch-shape graph (#836)

    /// The OFF teardown and the ON rollback both release the record route and then
    /// restart. A restart whose graph still holds the input edge wires an input node
    /// under a playback-only session — the v10.79.424 assert. The disconnect must sit
    /// BEFORE the route release at both sites.
    func testTheInputEdgeIsGoneBeforeEveryPostReleaseRestart() {
        let code = engineCode()
        guard !code.isEmpty else { return }
        XCTAssertEqual(
            code.components(separatedBy: "disconnectNodeOutput(masterEngine.inputNode)").count - 1,
            2, """
            The input-edge disconnect count changed — TWO sites precede a restart \
            after releaseRecordRoute (the OFF teardown and the ON rollback). A third \
            restart-preceding site needs its own disconnect; a removed one restores \
            the v10.79.424 start-shaped SIGABRT (#836).
            """)
        guard let off = code.range(of: "guard isInputMonitoring else { return true }") else {
            XCTFail("The OFF branch's guard is gone — re-anchor this claim (§4).")
            return
        }
        // #854 widened this window (1_400 -> 1_900): the OFF branch gained four
        // step breadcrumbs and a reset() — the ladder that finally names the dying
        // step in a device log. The ORDER claim below is unchanged.
        let offWindow = String(code[off.lowerBound...].prefix(1_900))
        guard let edge = offWindow.range(of: "disconnectNodeOutput(masterEngine.inputNode)"),
              let release = offWindow.range(of: "releaseRecordRoute(.inputMonitoring)") else {
            XCTFail("""
                The OFF teardown lost the input-edge disconnect or its route release \
                moved out of the window. The restart after the release must see the \
                launch-shape graph (playback-only, no input edge) — the one shape \
                proven to start on every app launch (#836).
                """)
            return
        }
        XCTAssertTrue(edge.lowerBound < release.lowerBound, """
            The input edge outlives the route release — the restore's start() then \
            wires an input node with no input scope, the v10.79.424 assert.
            """)
    }

    // MARK: - 4. Every surgery step breadcrumbs itself, and the stop is followed by a reset (#854)

    /// The v10.79.425 log was the FOURTH device log of the isInputConnToConverter
    /// SIGABRT, and like the three before it, it could not name the dying step —
    /// the surgery paths ran several ObjC-asserting ops with no line between the
    /// last breadcrumb and the exception. This claim pins the ladder (a log line
    /// BEFORE each step) and the stop-then-reset pair (stop halts rendering;
    /// reset releases the engine's prepared converter state — hypothesis #4 on
    /// this assert, after #831's pause, #835's stop and #836's input edge).
    /// ⚠️ The ladder TEXTS are pinned loosely (contains, in order) — renaming a
    /// step label is free as long as a line still precedes each op.
    func testTheSurgeryStepsBreadcrumbAndTheStopIsFollowedByAReset() {
        let code = engineCode()
        guard !code.isEmpty else { return }
        // OFF branch: crumb -> stop -> reset -> crumb -> tap -> crumb -> edges.
        guard let off = code.range(of: "guard isInputMonitoring else { return true }") else {
            XCTFail("The OFF branch's guard is gone — re-anchor this claim (§4).")
            return
        }
        let offWindow = String(code[off.lowerBound...].prefix(1_900))
        var cursor = offWindow.startIndex
        for step in ["logMonitorOutcome(\"off 1/5",
                     "masterEngine.stop()",
                     "masterEngine.reset()",
                     "logMonitorOutcome(\"off 2/5",
                     "removeTap(onBus: 0)",
                     "logMonitorOutcome(\"off 3/5",
                     "disconnectNodeOutput(masterEngine.inputNode)",
                     "logMonitorOutcome(\"off 4/5",
                     "releaseRecordRoute(.inputMonitoring)"] {
            guard let r = offWindow.range(of: step, range: cursor..<offWindow.endIndex) else {
                XCTFail("""
                    OFF-teardown ladder broken at `\(step)` — either the step moved out \
                    of order, or its breadcrumb was dropped. Four founder device logs \
                    (v421/v422/v424/v425) could not name the dying step because these \
                    lines did not exist; keep a line BEFORE every ObjC-asserting op.
                    """)
                return
            }
            cursor = r.upperBound
        }
        // setVoiceTune: crumb -> stop -> reset -> crumb -> surgery.
        guard let fn = code.range(of: "func setVoiceTune") else {
            XCTFail("setVoiceTune is gone — re-anchor this claim (§4).")
            return
        }
        // #854b: window covers through the restart rung (the ladder's last
        // ObjC-asserting op); re-measure before shrinking.
        let tuneWindow = String(code[fn.lowerBound...].prefix(2_600))
        var tCursor = tuneWindow.startIndex
        for step in ["logMonitorOutcome(\"tune ",
                     "masterEngine.stop()",
                     "masterEngine.reset()",
                     "logMonitorOutcome(\"tune 2/4",
                     "disconnectNodeOutput(notchEQ)",
                     "logMonitorOutcome(\"tune 3/4",
                     "try masterEngine.start()"] {
            guard let r = tuneWindow.range(of: step, range: tCursor..<tuneWindow.endIndex) else {
                XCTFail("""
                    setVoiceTune ladder broken at `\(step)` — same crash family as the \
                    OFF teardown (#835 was this method's surgery), same requirement: a \
                    breadcrumb before every op, and reset() after the stop.
                    """)
                return
            }
            tCursor = r.upperBound
        }
    }
}
