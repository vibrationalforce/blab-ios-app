// TheMonitorClaimNeedsAConfiguredSessionTests.swift
// Echoel — #975. Blocking bundle. **SOURCE-TEXT SCAN** (`Tests/CISmoke/CLAUDE.md` §1) over
// `Sources/Echoelmusic/Audio/AudioEngine.swift`, `AudioConfiguration.swift` and
// `MicrophoneManager.swift`, each through `SourceText.codeOnly`. Nothing here starts an engine:
// the failure this covers is an AVAudioSession throw at launch, which a bundle test cannot
// stage honestly.
//
// ⭐ WHAT WAS WRONG, and it is the founder's own `isInputConnToConverter` abort (v10.79.435,
// build 2553). `claimRecordRoute` has TWO callers. `MicrophoneManager` guards its claim —
// `if !AudioConfiguration.isSessionConfigured { try configureAudioSession() }` — two lines
// before making it. The input-monitoring path did not, and nothing between its entry and the
// abort read the flag: measured, `isSessionConfigured` occurred ZERO times anywhere in that
// method.
//
// ⛔ WHY THAT IS A HOLE AND NOT A TIDINESS POINT. `claimRecordRoute` →
// `upgradeToPlayAndRecord()` sets the CATEGORY and re-asserts the BUFFER, and never sets a
// preferred SAMPLE RATE — it relies on `configureAudioSession()` having done that at its rung
// 2/4. So when the launch configure throws at rung 1/4 (`setCategory`),
// `setPreferredSampleRate` never runs, `setupMasterEngine()` builds the output at the untouched
// 44.1 kHz anyway, and the claim then moves the hardware to its record default of 48 kHz. That
// is the founder's `on 3/5` line verbatim — `edge 48000.0 Hz/1 ch, session 48000.0 Hz/1 ch,
// out 44100.0 Hz/2 ch`. One rung later the engine restarts with the monitor chain, AVAudioEngine
// has to bridge 48k → 44.1k inside the input connection, and the assert fires.
//
// ⚠️ THE CAUSAL HALF IS INFERRED AND IS NOT CLAIMED ANYWHERE THIS SHIPS. That the launch
// configure THREW on his device cannot be read from his log: build 2553 predates #958, so the
// `session: configure FAILED` line did not exist yet, and `configure 1/4` followed by silence
// is equally the signature of a death INSIDE `setCategory`. What is proven from source is
// narrower and enough to act on: a record-route claim on a session that was never configured
// runs at a rate nobody chose, whatever made it unconfigured.
// NEEDS-FOUNDER-VERIFY: does the next log carry `session: configure FAILED — …`?
//
// ⚠️ CLAIM 5 IS THE PREMISE, NOT A DETAIL. It pins that `upgradeToPlayAndRecord` still does not
// set a preferred sample rate. The day it does, this fix's REASON evaporates and the paragraphs
// above become false — the guard is what makes that a red build instead of a silent rot (#631).
//
// ⚠️ NOT DEVICE-VERIFIED and cannot be from here. What is proven is that the claim is now
// preceded by the configure, and that a second failure REFUSES instead of falling through.
//
// DRIVEN (Python transcription of `SourceText.codeOnly` plus each predicate, against
// `git show <rev>:<each file>`):
//
//   | tree              | RED | of |
//   |-------------------|-----|----|
//   | 1e81876 (#974)    | 3   | 6  |
//   | worktree (#975)   | 0   | 6  |
//
// Claims 4-6 (the counterweights) are GREEN on both trees, which is what a counterweight should
// be (#367).
//
// AND EACH CLAIM WAS SHOWN TO FAIL FOR ITS OWN REASON, by mutating the worktree BY LINE INDEX
// (#967/#972: a mutation needs a unique anchor exactly like a guard does):
//
//   the guard block is deleted                          → c1 + c2 + c3
//   the guard is moved BELOW the claim                  → c2
//   the refusal is numbered `on 1/5 REFUSED`            → c3
//   MicrophoneManager loses its own guard               → c4
//   `setPreferredSampleRate` added to the upgrade       → c5
//   the claim call is duplicated                        → c6
//
// ⚠️ THE FIRST MUTATION SPILLS ACROSS THREE CLAIMS AND THAT IS CORRECT, not a weakness worth
// hiding: c1, c2 and c3 describe three properties of ONE nine-line block — that it exists, that
// it stands before the claim, and that its failure exit refuses by name. Deleting the block
// removes all three, which is exactly what the parent tree looks like (3 RED of 6). The
// mutations that matter for separation are the four that change one property each, and those
// land on one claim apiece.

import XCTest
@testable import Echoelmusic

final class TheMonitorClaimNeedsAConfiguredSessionTests: XCTestCase {

    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"
    private static let config = "Sources/Echoelmusic/Audio/AudioConfiguration.swift"
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

    /// The monitor-engage region: from the `on 1/5` rung to the `on 2/5` rung. Structural, not a
    /// character count (#408) — a fixed window would be spent by the next comment block, and
    /// this file's comment blocks are long.
    private func claimRegion(_ code: String) throws -> String {
        let open = "logMonitorOutcome(\"on 1/5: stopping engine + claiming record route\""
        let close = "logMonitorOutcome(\"on 2/5: attaching monitor nodes\""
        XCTAssertEqual(occurrences(of: open, in: code), 1, """
            The `on 1/5` rung is no longer unique — this window cannot anchor on it. Re-anchor \
            before trusting any claim below (#408); a needle that cannot match makes every \
            assertion after it vacuously true (#926).
            """)
        XCTAssertEqual(occurrences(of: close, in: code), 1, """
            The `on 2/5` rung is no longer unique — the window has no end. Re-anchor (#408).
            """)
        guard let start = code.range(of: open), let end = code.range(of: close),
              start.upperBound < end.lowerBound else {
            XCTFail("`on 1/5` no longer stands before `on 2/5` — the ladder was reordered.")
            return ""
        }
        return String(code[start.upperBound..<end.lowerBound])
    }

    // MARK: - 1. The monitor path ensures the session is configured at all

    func testTheMonitorPathChecksTheSessionWasConfigured() throws {
        let region = try claimRegion(try source(Self.engine))
        XCTAssertEqual(occurrences(of: "AudioConfiguration.isSessionConfigured", in: region), 1, """
            The input-monitoring path no longer reads `isSessionConfigured` before claiming the \
            record route. `MicrophoneManager` guards its identical claim; this is the caller \
            that did not, and the v10.79.435 `isInputConnToConverter` abort ran down it. A \
            claim on an unconfigured session raises the hardware to its record default while \
            the output graph stays on whatever rate it was built with (#975).
            """)
    }

    // MARK: - 2. …and it does so BEFORE the claim, not after

    func testTheConfigureStandsBeforeTheClaim() throws {
        let region = try claimRegion(try source(Self.engine))
        guard let check = region.range(of: "AudioConfiguration.isSessionConfigured"),
              let claim = region.range(of: "AudioConfiguration.claimRecordRoute(.inputMonitoring)")
        else {
            XCTFail("""
                The guard or the claim is gone from the `on 1/5` → `on 2/5` window. Both must \
                be here and in this order: a configure AFTER the claim cannot prevent the \
                rate divergence, because the claim is what moves the hardware (#975).
                """)
            return
        }
        XCTAssertTrue(check.lowerBound < claim.lowerBound, """
            The session check now stands AFTER the record-route claim. By then the hardware has \
            already been raised to its record default and the graph is already mismatched — \
            the order is the whole fix, not a style point (#975).
            """)
    }

    // MARK: - 3. A second failure REFUSES; it does not fall into the same hole

    func testASecondConfigureFailureRefusesUnnumbered() throws {
        let region = try claimRegion(try source(Self.engine))
        XCTAssertEqual(occurrences(of: "on REFUSED — the session was never configured", in: region),
                       1, """
            The refusal line is gone or reworded. If the configure throws HERE too, monitoring \
            must say so and stop; falling through repeats the original defect one level down.
            """)
        // ⚠️ POSITIVE-then-shape, not a bare `XCTAssertFalse(contains("on 1/5 REFUSED"))`: a
        // negative assertion is true whenever its needle cannot match (#926). The needle above
        // proves the line EXISTS; this proves the family is still four rungs plus terminators
        // with no NUMBERED refusal among them — `diag-ladder`'s c3 grammar is explicit that a
        // numbered terminator is indistinguishable from a rung in a log.
        for numbered in ["on 1/5 REFUSED", "on 2/5 REFUSED", "on 3/5 REFUSED",
                         "on 4/5 REFUSED", "on 5/5 REFUSED"] {
            XCTAssertEqual(occurrences(of: numbered, in: try source(Self.engine)), 0, """
                `\(numbered)` numbers a terminator. Once a number is present the form that \
                walks on and the form that returns are the SAME STRING in a log, so the tool \
                cannot tell a refusal from a rung (c3 of the `diag-ladder` grammar).
                """)
        }
    }

    // MARK: - 4. COUNTERWEIGHT: the pattern this reuses is still there

    /// Green on both trees. #975 adds no new mechanism — it copies `MicrophoneManager`'s guard
    /// to the sibling caller. If the original goes, this stops being a reuse and becomes an
    /// invention, and the header's argument stops holding.
    func testTheMicrophoneManagerStillGuardsItsOwnClaim() throws {
        let code = try source(Self.mic)
        guard let check = code.range(of: "!AudioConfiguration.isSessionConfigured"),
              let claim = code.range(of: "AudioConfiguration.claimRecordRoute(.microphoneManager)")
        else {
            XCTFail("""
                `MicrophoneManager` no longer guards its record-route claim on a configured \
                session. That guard is the pattern #975 copied to the monitoring path; if it \
                was removed deliberately, the monitoring copy needs the same decision.
                """)
            return
        }
        XCTAssertTrue(check.lowerBound < claim.lowerBound,
                      "`MicrophoneManager`'s session check no longer precedes its claim.")
    }

    // MARK: - 5. COUNTERWEIGHT AND PREMISE: the upgrade still sets no sample rate

    /// Green on both trees, and the sharpest claim in the file. The ENTIRE argument for #975 is
    /// that raising the category does not carry a rate with it. The day `upgradeToPlayAndRecord`
    /// sets one, the divergence closes at its source and every paragraph above is stale — a
    /// red build is how that gets noticed instead of rotting (#631).
    func testTheRouteUpgradeStillSetsNoSampleRate() throws {
        let code = try source(Self.config)
        guard let upgrade = code.range(of: "static func upgradeToPlayAndRecord") else {
            XCTFail("`upgradeToPlayAndRecord` is gone — re-anchor claim 5 (#408).")
            return
        }
        let rest = code[upgrade.upperBound...]
        let end = rest.range(of: "\n    static func")?.lowerBound ?? rest.endIndex
        XCTAssertEqual(occurrences(of: "setPreferredSampleRate", in: String(rest[..<end])), 0, """
            `upgradeToPlayAndRecord` now sets a preferred sample rate. That is a GOOD change and \
            this claim is not forbidding it (#364) — but it closes the divergence at its source, \
            so in the SAME commit correct the reason given for #975 in this file's header, in \
            `AudioEngine`'s guard comment, and in `SESSION_LOG`, and decide whether the guard \
            above is still earning its place.
            """)
    }

    // MARK: - 6. COUNTERWEIGHT: the claim and its rung are unmoved

    /// Green on both trees. #975 inserts a check; it must not have renamed a rung or dropped
    /// the claim's own failure handling on the way (#631/#650: a renamed logged string rots
    /// silently).
    func testTheRungAndTheClaimAreUnchanged() throws {
        let code = try source(Self.engine)
        for needle in ["logMonitorOutcome(\"on 1/5: stopping engine + claiming record route\"",
                       "AudioConfiguration.claimRecordRoute(.inputMonitoring)",
                       "logMonitorOutcome(\"session upgrade failed"] {
            XCTAssertEqual(occurrences(of: needle, in: code), 1, """
                `\(needle)…` no longer occurs exactly once. #975 inserts a check before the \
                claim and changes nothing else on this path; a moved rung or a lost failure \
                branch means something rode in on it.
                """)
        }
    }
}
