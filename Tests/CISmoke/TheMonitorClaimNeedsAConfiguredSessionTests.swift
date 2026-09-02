// TheMonitorClaimNeedsAConfiguredSessionTests.swift
// Echoel — #975. Blocking bundle. **SOURCE-TEXT SCAN** (`Tests/CISmoke/CLAUDE.md` §1) over
// `Sources/Echoelmusic/Audio/AudioEngine.swift`, `AudioConfiguration.swift` and
// `MicrophoneManager.swift`, each through `SourceText.codeOnly`. Nothing here starts an engine:
// the failure this covers is an AVAudioSession throw at launch, which a bundle test cannot
// stage honestly.
//
// ⭐ WHAT WAS WRONG. `claimRecordRoute` has THREE call sites and only `MicrophoneManager`
// configured first — `if !AudioConfiguration.isSessionConfigured { try configureAudioSession() }`,
// two lines before making its claim. The input-monitoring path did not, and
// `isSessionConfigured` occurred ZERO times anywhere in that method.
// `MultiTrackRecorder.swift:132` was the third and was still unguarded; it is doorless (#204),
// so #975 NAMED it here and did not fix it.
//
// ⭐ #981 FIXED IT, and the thing that changed the call was measuring the RELEASE side instead
// of the claim side. Doorlessness is a good reason not to fix a bug a user can hit; it is not a
// reason to leave two of three siblings behaving one way and the third another, because the
// person who re-doors it has no reason to look. What the third site actually inherited: the
// claim raises the category regardless, but every release runs
// `downgradeToPlaybackAfterRecording()`, whose first statement is
// `guard isSessionConfigured else { … return }` — so a take on an unconfigured session raises
// `.playAndRecord` and can never lower it, with nobody holding it. Claim 7 below now asserts all
// THREE sites, so this sentence cannot go stale again without a red build.
//
// ⛔ #976 — AND #975 GAVE THE WRONG REASON FOR ITS OWN FIX, in every home it wrote one. It said
// this closes the 48 kHz / 44.1 kHz divergence behind the founder's `isInputConnToConverter`
// abort (v10.79.435). It cannot: `configureAudioSession()`'s rung 2/4 asks for
// `preferredSampleRate`, and that is `static let = 48000.0` — the DIVERGING rate. The block
// moves the moment the hardware is raised one line earlier and changes nothing about the
// mismatch; a founder log would print the same `on 3/5` line after it. What actually refuses
// that case is the pre-existing #958 rate guard further down the same method. Caught by a
// reviewer reading the constant, not by any check here.
//
// ⭐ WHAT THE BLOCK REALLY BUYS, measured at the consumer.
// `downgradeToPlaybackAfterRecording` opens with `recordingRouteNeeded = false` and then
// `guard isSessionConfigured else { … category left as-is; return }`
// (`AudioConfiguration.swift:625`). On a device whose launch configure threw, monitoring ON
// raises the category and monitoring OFF can NEVER lower it — the session sits on
// `.playAndRecord` with zero holders for the rest of the process, which is the A2DP → HFP
// call-quality degradation `AudioConfiguration.swift:451` already describes. This closes that
// permanently, on the first toggle. A real fix, for a reason nobody had written down.
//
// ⚠️ CLAIM 5 IS STILL WORTH ITS PLACE, WITH A CORRECTED LABEL. It pins that
// `upgradeToPlayAndRecord` sets the category and the buffer and never a sample rate. That is
// true and load-bearing — but it is #958's premise, not this block's. The day the upgrade sets
// a rate, #958's argument is what changes.
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
    private static let recorder = "Sources/Echoelmusic/Audio/MultiTrackRecorder.swift"

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
        // #976: hoisted — the loop re-read and re-stripped a 3,800-line file five times.
        let code = try source(Self.engine)
        for numbered in ["on 1/5 REFUSED", "on 2/5 REFUSED", "on 3/5 REFUSED",
                         "on 4/5 REFUSED", "on 5/5 REFUSED"] {
            XCTAssertEqual(occurrences(of: numbered, in: code), 0, """
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
        // ⚠️ #976: the terminator is ASSERTED, not defaulted. `?? rest.endIndex` would silently
        // turn the window into "rest of file" the day `upgradeToPlayAndRecord` becomes the last
        // 4-space `static func` here — and this file has other `setPreferredSampleRate` sites,
        // so the claim would go RED on correct code with a message about the wrong function.
        guard let end = rest.range(of: "\n    static func")?.lowerBound else {
            XCTFail("""
                `upgradeToPlayAndRecord` is now the last `static func` in AudioConfiguration, \
                so this window has no end and would swallow the rest of the file. Re-anchor \
                on the next declaration by name (#408).
                """)
            return
        }
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

    // MARK: - 7. #981: the THIRD claim site, and the premise that makes its repair matter

    /// ⭐ #981 CLOSED THE ASYMMETRY THIS FILE'S HEADER NAMED. `claimRecordRoute` has three call
    /// sites; two guarded and `MultiTrackRecorder` did not. The header said so and left it —
    /// correctly, at the time, because the recorder is doorless (#204). What changed the call is
    /// measuring the RELEASE side rather than the claim side: the claim raises the category
    /// through `upgradeToPlayAndRecord()` regardless, but every release runs
    /// `downgradeToPlaybackAfterRecording()`, whose first statement is
    /// `guard isSessionConfigured else { … return }`. A take started on an unconfigured session
    /// therefore raises `.playAndRecord` and can NEVER lower it — the session sits there with
    /// nobody holding it, the A2DP→HFP degradation `AudioConfiguration` names at that guard.
    ///
    /// ⚠️ It is still doorless, and that is stated rather than glossed: this fixes nothing a
    /// user can reach today. It fixes what the next person to open that door would inherit.
    ///
    /// ⭐ AND THE THIRD SITE REFUSES WHERE THE OTHER TWO RECONFIGURE — the needle below is
    /// deliberately the CHECK, not the repair. Both siblings may call `configureAudioSession()`
    /// because no engine is running when they do (`MicrophoneManager` before it builds its
    /// engine, `rearmInputMonitoring` after `masterEngine.stop()`). `MultiTrackRecorder` reaches
    /// this point with a RUNNING engine, and `configureAudioSession()` does
    /// `setPreferredSampleRate(48000)` and `setActive(true)` — changing the hardware rate under
    /// a running engine is the class behind the founder's `isInputConnToConverter` abort. So the
    /// third site sets its error and returns. Copying the sibling BODY here would have been
    /// pattern-matching; what the three must share is the CHECK, which is what this asserts.
    func testAllThreeClaimSitesCheckTheSessionFirst() throws {
        let sites = [
            (Self.mic, "AudioConfiguration.claimRecordRoute(.microphoneManager)"),
            (Self.engine, "AudioConfiguration.claimRecordRoute(.inputMonitoring)"),
            (Self.recorder, "AudioConfiguration.claimRecordRoute(.multiTrackRecorder)")
        ]
        for (path, claim) in sites {
            let code = try source(path)
            guard let claimAt = code.range(of: claim) else {
                XCTFail("""
                    \(path) no longer claims the record route with \(claim). If a site was \
                    removed, drop it from this list in the same commit — a guard that cannot \
                    find its anchor asserts nothing (#926).
                    """)
                continue
            }
            // The check must stand BEFORE the claim, and inside the same method — approximated
            // by "the nearest preceding occurrence", which is what the other claims in this file
            // use. A file-wide `contains` would pass on a check that lives in another method.
            let before = code[code.startIndex..<claimAt.lowerBound]
            guard let checkAt = before.range(of: "!AudioConfiguration.isSessionConfigured",
                                             options: .backwards) else {
                XCTFail("""
                    \(path) claims the record route without first checking \
                    `AudioConfiguration.isSessionConfigured`. The claim raises the category \
                    either way, but `downgradeToPlaybackAfterRecording()` returns early when the \
                    session was never configured — so the route goes UP and can never come back \
                    DOWN, with nobody holding it. That is the founder-visible A2DP→HFP \
                    degradation.
                    """)
                continue
            }
            XCTAssertTrue(checkAt.lowerBound < claimAt.lowerBound,
                          "\(path): the session check no longer precedes its claim.")
        }
    }

    /// COUNTERWEIGHT AND PREMISE for the claim above. The whole reason an unguarded claim is a
    /// defect is that the DOWNGRADE refuses on an unconfigured session. The day that guard goes,
    /// the argument above is stale and this file must be re-read rather than trusted (#631).
    func testTheDowngradeStillRefusesAnUnconfiguredSession() throws {
        let code = try source(Self.config)
        XCTAssertTrue(code.contains("guard isSessionConfigured else"), """
            `AudioConfiguration` no longer refuses to downgrade on an unconfigured session. \
            That refusal is the ENTIRE premise of the claim above: without it, claiming on an \
            unconfigured session would lower again normally and #981 would be unnecessary. \
            Re-read this file before trusting it.
            """)
    }

    /// #981's exit must be DISTINGUISHABLE. Reusing `engineNotReady` would have put a wrong
    /// label on a user-visible failure — the engine check runs earlier and had already passed.
    /// ⚠️ This asserts the case EXISTS and is USED, never that the recorder stays doorless
    /// (#364): re-dooring it is exactly the work this repair is for.
    func testTheRecorderNamesItsOwnSessionFailure() throws {
        let code = try source(Self.recorder)
        XCTAssertTrue(code.contains("case sessionNotConfigured"),
                      "the recorder lost its own error case for a never-configured session; "
                      + "`engineNotReady` is a different fact and its check runs earlier")
        XCTAssertTrue(code.contains("lastError = .sessionNotConfigured"),
                      "the case exists but nothing sets it — an error nobody can observe is "
                      + "the same as no error at all")
    }
}
