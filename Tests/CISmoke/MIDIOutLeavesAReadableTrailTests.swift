// MIDIOutLeavesAReadableTrailTests.swift
// Echoel — #715. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ THE ONE FACT THIS FILE EXISTS FOR. `log.log` reaches `os_log` and an in-memory ring that
// `ProfessionalLogger`'s own doc calls "write-only today". The file the founder exports —
// `echoel_diag.log` — is written by `EchoelCrashLog.breadcrumb` and by NOTHING else. So a
// subsystem whose only instrumentation is `log.log` is, from a device, silent: he can send a
// log covering the exact minute a feature misbehaved and it will not name that feature once.
//
// #650 discovered this in the monitoring path AFTER five separate slices of instrumentation had
// each added a `log.audio` line nobody could read. #713 then shipped two MIDI-out switches into
// a file with the same shape — nine `log.log` lines, zero breadcrumbs — and #715 closed it
// before it cost a round trip rather than after.
//
// ⚠️ STATE CHANGES ONLY, and claim 3 is what keeps it that way. `breadcrumb` does `Date()` plus
// a `write(2)`. On the note path — reached from the clock timer — that is file I/O at note rate,
// which is the audio-thread ban in everything but name. The call sites are port lifecycle and
// preference edges, all on the main actor.
//
// ⚠️ WHAT THIS FILE CANNOT REACH: it cannot construct `MIDIOutput` (`@MainActor`, and CoreMIDI
// is absent in a test host), cannot prove a line reaches the file, and cannot prove the founder
// can read it. It reads SOURCE TEXT. Weaker than a device run, stronger than nothing — and the
// device half is exactly what #650 had to be told by a screen recording.

import Foundation
import XCTest
@testable import Echoelmusic

final class MIDIOutLeavesAReadableTrailTests: XCTestCase {

    private static let engine = "Sources/Echoelmusic/Audio/MIDIOutput.swift"

    /// Claim 1 — the two-sink helper exists and writes BOTH sinks. One without the other is the
    /// defect: `os_log` alone is unreadable from a device, a breadcrumb alone loses the category.
    func testTheHelperWritesBothSinks() throws {
        let code = try codeOf(Self.engine)
        XCTAssertTrue(code.contains("private func logOutcome("), """
            `MIDIOutput` has no `logOutcome` any more. If it was renamed, re-anchor this file; if \
            it was removed, MIDI out is back to writing only to a sink nobody can export.
            """)
        XCTAssertTrue(code.contains("EchoelCrashLog.breadcrumb(\"midiout: \\(message)\")"), """
            `logOutcome` no longer writes a breadcrumb, so nothing about MIDI out reaches \
            `echoel_diag.log`. That is the #650 hole exactly: instrumentation that exists, looks \
            thorough, and cannot be read from the device it describes.
            """)
        XCTAssertTrue(code.contains("log.log(level, category: .system,"), """
            `logOutcome` no longer writes to `os_log`. The breadcrumb file is flat; the category \
            is what makes a live Console session filterable. Keep both (#416: one message, two \
            sinks, deliberately different prefixes).
            """)
    }

    /// Claim 2 — every state-change exit goes through the helper, so none can go quiet again.
    /// The list is the port lifecycle plus the preference edge; a new exit must join it.
    func testEveryStateChangeExitUsesTheHelper() throws {
        let code = try codeOf(Self.engine)
        let calls = code.components(separatedBy: "logOutcome(").count - 1
        // Declaration + 7 call sites. Asserted as a FLOOR, not an equality: a new exit that also
        // reports is correct work and must not turn this red (#364).
        XCTAssertGreaterThanOrEqual(calls, 8, """
            Only \\(calls) mentions of `logOutcome` in \\(Self.engine) — at least one state-change \
            exit stopped reporting. The exits that must: the three port-creation failures, the \
            ready line, the re-enable on an open port, the preference edge, and the \
            platform-unavailable no-op.
            """)
    }

    /// ⭐ Claim 3 — the COUNTERWEIGHT, and the one that matters most. A breadcrumb is a `write(2)`.
    /// The moment one lands on the note or clock path it is file I/O at note rate, on a path the
    /// audio-thread rules exist to keep clean. Goes red the day somebody adds one there.
    func testNoBreadcrumbOnTheSendPath() throws {
        let lines = try codeOf(Self.engine)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        // The send primitives and the note/clock entry points: a breadcrumb inside any of their
        // bodies would fire per event. Approximated by proximity, which is honest about being an
        // approximation: any `logOutcome`/`breadcrumb` within a `func send`/`noteOn`/`noteOff`/
        // `sendClock` body is caught by the indentation walk below.
        let hot = ["func send(", "func noteOn(", "func noteOff(", "func sendExpression(",
                   "func pulseClock(", "func sendClock("]
        var offenders: [String] = []
        for (index, line) in lines.enumerated() where hot.contains(where: { line.contains($0) }) {
            let indent = line.prefix { $0 == " " }.count
            var cursor = index + 1
            while cursor < lines.count {
                let body = lines[cursor]
                let trimmed = body.trimmingCharacters(in: .whitespaces)
                if trimmed == "}" && body.prefix(while: { $0 == " " }).count == indent { break }
                if body.contains("logOutcome(") || body.contains("EchoelCrashLog.breadcrumb(") {
                    offenders.append(trimmed)
                }
                cursor += 1
            }
        }

        XCTAssertTrue(offenders.isEmpty, """
            A breadcrumb sits on an event path: \\(offenders.joined(separator: " | ")).

            `EchoelCrashLog.breadcrumb` does `Date()` plus a `write(2)`. On the note or clock path \
            that is file I/O per event, from a timer — the audio-thread ban in everything but \
            name. Report state CHANGES only: port lifecycle and preference edges.
            """)
    }

    // MARK: - Helpers

    private func codeOf(_ path: String) throws -> String {
        SourceText.codeOnly(try String(contentsOf: try repoRoot().appendingPathComponent(path),
                                       encoding: .utf8))
    }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than reporting \
                a green this file did not earn.
                """)
        }
        return root
    }
}
