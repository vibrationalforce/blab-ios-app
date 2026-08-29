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
// ⭐ GRADING (§3): FORWARD in full — every needle names #859 text created in the same
// commit; red at the parent by the one shared absence (#486). The ordering walks could
// never have a verdict there. Counterweights: the claim-4 gate needles are the ones
// TheMonitoringSurvivesEngineRecoveryTests claim 3 already holds green on both trees.

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
