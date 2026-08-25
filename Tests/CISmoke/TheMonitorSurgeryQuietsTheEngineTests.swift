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
// SOURCE-TEXT SCANS (§1) — no AVAudioEngine runs in a test host; the "no more
// SIGABRT" fact itself is the founder's next device log. Comment lines stripped
// (#491: the retraction docs quote the old defense).
//
// #364: pause/stop-around-surgery is the law this file pins; a redesign that makes
// surgery safe another way must re-anchor these claims in the same commit and pull
// the #831 blocks in AudioEngine.swift plus the SESSION_LOG entry (#456).

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

    // MARK: - 2. The voice-tune rewire pauses around the surgery

    func testTheVoiceTuneRewirePausesAroundTheSurgery() {
        let code = engineCode()
        guard !code.isEmpty else { return }
        guard let fn = code.range(of: "func setVoiceTune") else {
            XCTFail("setVoiceTune is gone — re-anchor this claim (§4).")
            return
        }
        let window = String(code[fn.lowerBound...].prefix(1_600))
        guard let pause = window.range(of: "if wasRunning { masterEngine.pause() }"),
              let surgery = window.range(of: "disconnectNodeOutput(notchEQ)") else {
            XCTFail("""
                setVoiceTune lost its pause (or its surgery moved out of the window). \
                Rewiring the input-fed chain through the time-pitch node (converter \
                machinery) while the engine renders is an ObjC assert no Swift catch \
                sees — the v10.79.421 SIGABRT. The old "no start() to fail here" \
                defense is retracted by measurement; do not restore it.
                """)
            return
        }
        XCTAssertTrue(pause.lowerBound < surgery.lowerBound, """
            The pause comes AFTER the first disconnect — the surgery still races the \
            render.
            """)
        XCTAssertTrue(window.contains("restartOrDegrade(after: \"voice tune rewire\")"), """
            The rewire's restart-failure path is gone. The pause creates exactly the \
            start()-can-fail case the old doc said did not exist — without this \
            fallback a failed restart strands the whole app silent (#611).
            """)
    }
}
