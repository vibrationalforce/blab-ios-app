// TheStartRetryNamesWhichStepFailedTests.swift
// Echoel — #964. Blocking bundle. **SOURCE-TEXT SCAN** (`Tests/CISmoke/CLAUDE.md` §1) over
// `Sources/Echoelmusic/Audio/AudioEngine.swift` through `SourceText.codeOnly`. Nothing here
// starts an engine: the failures this covers are an `AVAudioEngine.start()` throw and an
// AVAudioSession reconfigure throw, neither of which a bundle test can stage honestly.
//
// ⭐ WHAT WAS WRONG. The retry path had its RUNGS and not its REASONS. Both failure messages
// went to `log.audio`, i.e. `os_log`, which the exported `echoel_diag.log` does not carry
// (#859 states that law; #862b's `session: configure FAILED` is the identical repair one
// call-site over). A founder log therefore read `start 1/2` → `start 2/2` → `start OK` with
// WHY the first attempt failed missing, and a run that degraded ended at `start 2/2` with no
// cause at all — the app raises a degraded banner and the exported log says nothing about it.
//
// ⛔ AND THE FINAL MESSAGE WAS FALSE IN ONE OF ITS TWO CASES. One `do` wrapped BOTH
// `configureAudioSession()` and the retry `start()`, so a session reconfigure that threw was
// reported as "Master engine start failed after retry" — while the retry had never been
// attempted. A triager reading that is sent to `start()` for a fault that never reached it:
// the #937 class, an instrument telling a triager the opposite of what it did.
//
// ⚠️ WHAT DID **NOT** CHANGE, and claims 5-6 are here to keep it that way: the two calls, and
// their order, are exactly as before. This slice adds lines to the exported log and splits one
// `do` so the log can name a step. It is not an audio-graph change, and it must not become one.
//
// ⚠️ NOT DEVICE-VERIFIED, and it cannot be from here. What is proven is that the reasons are
// WRITTEN to the breadcrumb sink; that a founder's next log carries them is a device fact.
// NEEDS-FOUNDER-VERIFY: a log that degrades now ends at `engine: start FAILED — …` naming the
// step, instead of at `engine: start 2/2` with nothing after it.
//
// DRIVEN (Python transcription of `SourceText.codeOnly` plus each predicate, against
// `git show <rev>:Sources/Echoelmusic/Audio/AudioEngine.swift`):
//
//   | tree              | RED | of |
//   |-------------------|-----|----|
//   | 91fe351 (#961)    | 4   | 6  |
//   | afd630a (#963)    | 4   | 6  |
//   | worktree (#964)   | 0   | 6  |
//
// Claims 5-6 (the counterweights) are GREEN on all three trees, which is what a counterweight
// should be — #961's header records the day one was written as a composite and went red on the
// parent for the WRONG reason (#367).
//
// AND EACH CLAIM WAS SHOWN TO FAIL FOR ITS OWN REASON, by mutating the worktree:
//
//   crumb moved below the reconfigure          → c1
//   the retry branch stops naming itself       → c2
//   cause crumbed after `degraded = true`      → c3
//   terminator numbered `start 2/2 FAILED`     → c3 + c4
//   the `start 2/2` rung renamed               → c5
//   a third `try masterEngine.start()` appears → c6
//
// The one spillover is a shared needle, not noise: claim 3 anchors on the same
// `logEngineLifecycle("start FAILED` literal that claim 4 inspects.

import XCTest
@testable import Echoelmusic

final class TheStartRetryNamesWhichStepFailedTests: XCTestCase {

    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"

    private func source() throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return SourceText.codeOnly(
            try String(contentsOf: root.appendingPathComponent(Self.engine), encoding: .utf8))
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// The retry region: from the `start 1/2` rung to the tap re-install that ends the
    /// `if !masterEngine.isRunning` block. Structural, not a character count (#408) — the
    /// neighbouring ladder claim's fixed 1200-char window was left with 235 characters of
    /// slack by this very slice, and was re-anchored the same way in the same commit.
    private func retryRegion(_ code: String) throws -> String {
        let anchor = "logEngineLifecycle(\"start 1/2: starting master engine\")"
        let start = try XCTUnwrap(code.range(of: anchor),
                                  "the `start 1/2` rung is gone — re-anchor this file (§4).")
        XCTAssertEqual(occurrences(of: "startMeterPollTimer()", in: code), 2, """
            `startMeterPollTimer()` no longer occurs exactly twice (call + declaration); this \
            window uses the CALL as its end. Re-anchor before trusting any claim below (#408).
            """)
        let rest = code[start.lowerBound...]
        let end = rest.range(of: "startMeterPollTimer()")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    // MARK: - 1. The first attempt's failure reaches the EXPORTED log

    func testTheFirstFailureIsCrumbedBeforeTheReconfigure() throws {
        let region = try retryRegion(try source())
        guard let crumb = region.range(of: "logEngineLifecycle(\"start: the first attempt failed"),
              let reconfigure = region.range(of: "try AudioConfiguration.configureAudioSession()") else {
            XCTFail("""
                The first start attempt's failure is no longer written to the breadcrumb sink \
                before the session is reconfigured. `log.audio` is `os_log` and the exported \
                `echoel_diag.log` does not carry it (#859), so the log would again show \
                `start 1/2` → `start 2/2` with the cause of the retry missing (#964).
                """)
            return
        }
        XCTAssertTrue(crumb.lowerBound < reconfigure.lowerBound, """
            The failure is crumbed AFTER the reconfigure. The reconfigure can itself throw or \
            abort, and then the reason for the retry is lost with it — a rung stands before the \
            call it describes, and so does the reason that caused it (#859/#964).
            """)
    }

    // MARK: - 2. The reconfigure and the retry can be told apart

    func testTheFailingStepIsNamed() throws {
        let region = try retryRegion(try source())
        for step in ["(\"the session reconfigure threw\", error)",
                     "(\"the retry threw\", error)"] {
            XCTAssertEqual(occurrences(of: step, in: region), 1, """
                `\(step)` is gone from the retry region. Both branches must be distinguishable: \
                one `do` around the reconfigure AND the retry reported a session fault as \
                "Master engine start failed after retry", sending a triager to `start()` for a \
                call that was never made (#937/#964).
                """)
        }
    }

    // MARK: - 3. The degrade is not silent in the exported log

    func testTheDegradeWritesItsCauseToTheExportedLog() throws {
        let region = try retryRegion(try source())
        guard let crumb = region.range(of: "logEngineLifecycle(\"start FAILED"),
              let degrade = region.range(of: "degraded = true") else {
            XCTFail("""
                The degrade path no longer names its cause in the exported log, or `degraded` \
                is no longer set here. A degraded banner with a silent log is the v428 triage \
                stall: the user sees a failure state and the file the founder exports has \
                nothing to say about it (#964).
                """)
            return
        }
        XCTAssertTrue(crumb.lowerBound < degrade.lowerBound, """
            The cause is crumbed after `degraded = true`. Everything between the two is \
            unreported if it dies, and this is the path that already knows it is failing.
            """)
    }

    // MARK: - 4. The terminator is UNNUMBERED

    func testTheTerminatorIsUnnumbered() throws {
        let region = try retryRegion(try source())
        guard let r = region.range(of: "logEngineLifecycle(\"start FAILED") else {
            XCTFail("the unnumbered `start FAILED` terminator is gone — re-anchor (§4).")
            return
        }
        let printed = String(region[r.lowerBound...].prefix(70))
        XCTAssertNil(printed.range(of: "[0-9]/[0-9]", options: .regularExpression), """
            The terminator has been numbered (e.g. `start 2/2 FAILED`). In `diag-ladder`'s \
            grammar only an UNNUMBERED terminator rescues a short ladder; a numbered skip that \
            RETURNS is the forbidden form, because a log cannot tell it apart from the numbered \
            skip that walks on. This one returns (#964).
            """)
    }

    // MARK: - 5. COUNTERWEIGHT — the `start 2/2` rung keeps its wording and its place

    /// Green on both trees on purpose. A guard pins that literal by equality elsewhere in this
    /// bundle (#631/#650: a renamed logged string reddens silently, at a distance), and #964's
    /// whole point was to add reasons WITHOUT touching the ladder.
    func testTheSecondRungIsUnchangedAndStillPrecedesTheRetry() throws {
        let region = try retryRegion(try source())
        let rung = "logEngineLifecycle(\"start 2/2: retry after session reconfigure\")"
        XCTAssertEqual(occurrences(of: rung, in: region), 1, """
            The `start 2/2` rung was renamed or removed. Its exact wording is pinned by \
            `TheEngineLifecycleSpeaksInTheDiagLogTests` too — this claim exists so the break \
            is reported next to the change that caused it (#964).
            """)
        guard let r = region.range(of: rung),
              let retry = region.range(of: "try masterEngine.start()",
                                       range: r.upperBound..<region.endIndex) else {
            XCTFail("no `try masterEngine.start()` after the `start 2/2` rung — the rung would " +
                    "then announce a retry that never happens (#859).")
            return
        }
        XCTAssertTrue(r.upperBound <= retry.lowerBound, "the rung no longer precedes the retry.")
    }

    // MARK: - 6. COUNTERWEIGHT — the calls and their order are unchanged

    /// This slice adds log lines and splits one `do`. If it ever starts adding, removing or
    /// reordering AVFAudio calls it has stopped being a logging change, and the review it needs
    /// is a different one.
    func testTheAudioCallsAndTheirOrderAreUntouched() throws {
        let region = try retryRegion(try source())
        XCTAssertEqual(occurrences(of: "try masterEngine.start()", in: region), 2, """
            The retry region no longer makes exactly two start attempts. #964 is a logging \
            change; changing how often the engine is started is not one (#964).
            """)
        XCTAssertEqual(occurrences(of: "try AudioConfiguration.configureAudioSession()",
                                   in: region), 1, """
            The retry region no longer reconfigures the session exactly once.
            """)
        guard let reconfigure = region.range(of: "try AudioConfiguration.configureAudioSession()"),
              let retry = region.range(of: "try masterEngine.start()",
                                       range: reconfigure.upperBound..<region.endIndex) else {
            XCTFail("the reconfigure no longer precedes the retry start — that IS the retry.")
            return
        }
        XCTAssertTrue(reconfigure.upperBound <= retry.lowerBound,
                      "the reconfigure no longer precedes the retry start.")
    }
}
