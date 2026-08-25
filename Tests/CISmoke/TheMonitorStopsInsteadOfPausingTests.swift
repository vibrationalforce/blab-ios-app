// TheMonitorStopsInsteadOfPausingTests — pins the #823 live-input repair.
//
// THE FAILURE THIS GUARDS (founder device log v10.79.420, build 2538): four
// identical "input format unusable after the session claim (sampleRate 0.0,
// channels 2, engine stopped) — #628" lines over ~10 seconds. Persistent state,
// not a race. Root cause: `setInputMonitoring` PAUSED the engine before the
// session claim — but `pause()` keeps the I/O unit alive with the configuration
// it was BUILT with, and an engine started from the playback-only launch graph
// has no input scope on that unit. A category change under a paused unit does
// not rebuild it, so `inputFormat(forBus: 0)` returned the 0 Hz placeholder on
// every retry. `stop()` releases the prepared unit so the later `start()`
// rebuilds it against the record-capable session, input scope included.
//
// Three claims, all source-scans on the ONE method (no simulator here — a
// Linux container cannot run AVAudioEngine; the discriminating log lines in
// the code are what settles the hypothesis on the founder's next device log):
//  1. Between `func setInputMonitoring` and the session claim the engine is
//     STOPPED, never paused (comment lines stripped — the file deliberately
//     QUOTES the old pause in its retraction notes, #491).
//  2. The #823 session-format fallback exists and logs its own line, so the
//     next device log can prove which path fed the connect format.
//  3. The #628 bail line carries the SESSION's facts (`inputAvailable`,
//     tagged #628/#823), so "no input at all" and "node won't say so" are
//     distinguishable without a second probe.
//
// #364: this guard does NOT forbid future work on the method. If a later fix
// legitimately reorders the region, re-anchor the claims in the same commit —
// each failure message names the prose homes to pull along (#456):
// AudioEngine.swift's #823 block, scratchpads/SESSION_LOG.md #823 entry.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMonitorStopsInsteadOfPausingTests: XCTestCase {

    private func audioEngineSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Echoelmusic/Audio/AudioEngine.swift")
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: AudioEngine.swift could not be read — fail, not skip (§4)")
            return ""
        }
        return source
    }

    /// The region from `func setInputMonitoring` to the first session claim,
    /// with comment lines removed — the retraction notes QUOTE the old pause
    /// on purpose (#491), so a naive scan would hit its own history.
    private func preClaimCodeLines(in source: String) -> [String] {
        guard let start = source.range(of: "func setInputMonitoring") else { return [] }
        let tail = source[start.lowerBound...]
        guard let claim = tail.range(of: "claimRecordRoute(.inputMonitoring)") else { return [] }
        return tail[..<claim.lowerBound]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && !$0.isEmpty }
    }

    func testTheEngineIsStoppedNotPausedBeforeTheSessionClaim() throws {
        let source = try audioEngineSource()
        guard !source.isEmpty else { return }
        let lines = preClaimCodeLines(in: source)
        // Anti-vacuous (#808): an empty region means an anchor moved, not a clean file.
        XCTAssertFalse(lines.isEmpty,
                       "The setInputMonitoring → claimRecordRoute region scanned EMPTY — "
                       + "an anchor was renamed. Re-anchor this guard; do not let it pass vacuously.")
        XCTAssertTrue(lines.contains { $0.contains("masterEngine.stop()") },
                      "#823 is gone: nothing stops the engine before the session claim. "
                      + "pause() keeps the input-scope-less I/O unit alive — the 0 Hz "
                      + "placeholder failure (four identical #628 lines, v10.79.420) comes back. "
                      + "If this was deliberate, pull the #823 block in AudioEngine.swift and "
                      + "the SESSION_LOG #823 entry in the same commit (#456).")
        XCTAssertFalse(lines.contains { $0.contains("masterEngine.pause()") },
                       "A pause() is back on the pre-claim path of setInputMonitoring. "
                       + "That is the exact #823 regression: a paused I/O unit never "
                       + "rebuilds its input scope after the category change.")
    }

    func testTheSessionFallbackExistsAndLogsItsOwnLine() throws {
        let source = try audioEngineSource()
        guard !source.isEmpty else { return }
        guard let start = source.range(of: "var inFmt = input.inputFormat(forBus: 0)") else {
            XCTFail("The mutable inFmt read is gone from setInputMonitoring — #823's "
                    + "fallback needs it. If the read was renamed, re-anchor this guard "
                    + "in the same commit.")
            return
        }
        let window = String(source[start.lowerBound...].prefix(1_800))
        XCTAssertTrue(window.contains("AVAudioSession.sharedInstance()"),
                      "The #823 fallback no longer asks the SESSION for the hardware format.")
        XCTAssertTrue(window.contains("standardFormatWithSampleRate"),
                      "The #823 fallback must build the format from the session's own "
                      + "values — an invented constant raises an ObjC exception no Swift "
                      + "catch sees.")
        XCTAssertTrue(window.contains("session fallback") && window.contains("#823"),
                      "The fallback's discriminator log line is gone. Without it the "
                      + "founder's next device log cannot prove which path fed the "
                      + "connect format — the whole point of a labeled hypothesis.")
    }

    func testTheBailLineCarriesTheSessionFacts() throws {
        let source = try audioEngineSource()
        guard !source.isEmpty else { return }
        guard let start = source.range(of: "input format unusable after the session claim") else {
            XCTFail("The #628 bail line is gone from AudioEngine.swift. If the message "
                    + "was reworded, re-anchor this guard in the same commit.")
            return
        }
        let window = String(source[start.lowerBound...].prefix(600))
        XCTAssertTrue(window.contains("inputAvailable"),
                      "The bail line dropped the session's inputAvailable fact — the log "
                      + "can no longer tell 'no input at all' from 'node won't say so'.")
        XCTAssertTrue(window.contains("#628/#823"),
                      "The bail line lost its #628/#823 tag — a device log line without "
                      + "its issue tag cannot be routed by the next triage.")
    }
}
