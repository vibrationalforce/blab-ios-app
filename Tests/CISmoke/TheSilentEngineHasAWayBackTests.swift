// TheSilentEngineHasAWayBackTests.swift
// Echoel — a promise in a doc comment is not an affordance. #585.
//
// WHAT THIS GUARDS. `AudioEngine` retries a stopped engine up to `maxRecoveryAttempts` times and
// then gives up, setting `degraded = true` and `lastAudioError`. Its declaration says why, in
// these words: *"so the UI can offer a 'tap to retry' affordance instead of silently showing
// 'stopped'"*.
//
// ⛔ THERE WAS NO SUCH AFFORDANCE, AND NO READER AT ALL. `git grep -n "degraded\|lastAudioError"`
// over `Sources/` and `Tests/` returned `AudioEngine.swift` and nothing else (three further hits
// are the English word in unrelated prose). The self-healing layer was complete right up to the
// last inch: it detects, it retries, it gives up honestly, it records the reason — and then hands
// that reason to nobody.
//
// What that costs is not a corner case. The trigger is cheap: a wobbling headphone plug produces
// `.oldDeviceUnavailable`, three failed recoveries, done. Everything else keeps running — the
// transport plays, the visual moves, the pulse reads, the meters tick. There is simply no sound,
// nothing anywhere says so, and the user's only working move is to relaunch the app. That is the
// exact experience the whole self-healing layer exists to remove.
//
// ⭐ AND THE SECOND HALF IS WHY THE ORDER OF THE TWO FIXES MATTERS. `handleInterruption`'s `.ended`
// branch calls `setActive(true)`, which can throw; that path logged the failure and returned,
// leaving a paused graph with nothing scheduled to rescue it. Routing it into the existing
// recovery hook fixes it — but ONLY once `degraded` has a reader. Without one, that change moves
// the silence from "no retry at all" to "three retries, then the same silence", which is not an
// improvement anyone can perceive. The affordance had to exist first, so both are in one slice.
//
// ⚠️ HONEST LIMITS.
//   · 9 tests, 13 assertions (`grep -c`, measured — several run inside `for` loops, so the 17
//     needles below outnumber the assertion statements). All are SOURCE-TEXT SCANS. The new
//     behaviour
//     is a SwiftUI view and an escaping closure inside a notification handler; neither is
//     reachable from a test bundle here. The pure part of this subsystem — `shouldSelfHeal` — is
//     already driven end to end by `AudioEngineSelfHealTests` and is untouched by this slice.
//   · DEVICE PROBE, open and NOT covered: whether the banner is legible, well placed and
//     reassuring rather than alarming at the moment audio dies. The state is deliberately awkward
//     to reach — unplug a headset mid-take, repeatedly, until recovery gives up.
//     NEEDS-FOUNDER-VERIFY.
//   · This guard does NOT prove the retry works. It proves a control exists, that it calls the
//     one method which clears the state, and that the state is still set where it was.
//
// ⭐ GRADING (§3). Driven needle by needle against the parent with the faithful stripper
// transcription (the one that KEEPS string contents — an earlier copy of it dropped them and
// produced confident numbers in both directions, see `TheWayOutSurvivesRotationTests`).
//   · TWO findings, not one, and they are independent: (a) `degraded` has no reader — **4 of 17
//     needles** red on the parent, all naming the file this commit creates or the mount it adds;
//     (b) the interruption-resume catch does not reach recovery — red on the parent via the
//     COUNT (1 call site there, 2 here), not via `contains`, because the hook already had its
//     original caller. Reported as two findings because either could have been fixed without the
//     other, which is the question #486 actually asks.
//   · The stripper is **TRAGEND (2 of 17 needles flip)** on this tree, and both flips are mine:
//     the leaf's own ⚠️ freeze-law comment NAMES `masterLevel` and `masterLevelR` as the values it
//     must not read, so the two negative needles find them raw and lose them only after comments
//     are blanked. Measured, not assumed.
//   · 12 needles are COUNTERWEIGHTS, green on both trees, and they carry the meaning (#343): the
//     give-up path still SETS both fields, `start()` still CLEARS them, the failing branch still
//     logs, and the leaf still touches no meter value. A "fix" that rendered a banner over state
//     nothing sets, or wired a Retry button to a method that no longer resets the counter, would
//     sail past a guard that only asserted the new view exists.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheSilentEngineHasAWayBackTests: XCTestCase {

    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"
    private static let config = "Sources/Echoelmusic/Audio/AudioConfiguration.swift"
    private static let row = "Sources/Echoelmusic/Studio/AudioDegradedRow.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - Finding (a): the state has a reader, and it is on screen

    func testTheDegradedStateHasAReaderOutsideTheEngine() throws {
        let src = try source(Self.row)
        XCTAssertTrue(src.contains("audioEngine.degraded"),
                      "Nothing outside `AudioEngine` read this flag for the whole of its life.")
        XCTAssertTrue(src.contains("audioEngine.lastAudioError"),
                      "The engine's own sentence names the CAUSE — that is the difference "
                      + "between a user who reseats a plug and one who reinstalls the app.")
    }

    func testTheRowIsMountedWhereTheStartButtonIs() throws {
        let src = try source(Self.studio)
        XCTAssertTrue(src.contains("AudioDegradedRow()"),
                      "A view nothing mounts is the doorless-surface defect, not a fix.")
    }

    func testTheRetryCallsTheOneMethodThatClearsTheState() throws {
        XCTAssertTrue(try source(Self.row).contains("audioEngine.start()"),
                      "`start()` is the retry — anything else leaves `degraded` latched.")
    }

    /// FREEZE LAW. The leaf may read exactly the two fields it renders. `AudioEngine` also
    /// publishes `masterLevel`/`masterLevelR` from the meter poll (~15 Hz); reading either here
    /// would make this view — and any menu open above it — rebuild at that rate.
    func testTheLeafReadsNoMeterValue() throws {
        let src = try source(Self.row)
        for hot in ["masterLevel", "masterLevelR", "audioEngine.isRunning"] {
            XCTAssertFalse(src.contains(hot), """
            `AudioDegradedRow` reads \(hot). That is a meter-rate value, and this view exists \
            precisely so a live audio object is never read from a body that hosts controls.
            """)
        }
    }

    /// The 14-modifier ceiling. A banner adds none; an alert would have been the 15th, which is
    /// the metadata-decoder SIGSEGV that ships as a black screen.
    func testTheRowAddsNoPresentationModifier() throws {
        let src = try source(Self.row)
        for modal in [".sheet(", ".fullScreenCover(", ".alert(", ".confirmationDialog(", ".popover("] {
            XCTAssertFalse(src.contains(modal),
                           "\(modal) here would grow the presentation chain this row avoided.")
        }
    }

    // MARK: - Finding (b): the interruption-resume failure reaches recovery

    func testAFailedResumeSchedulesARecoveryInsteadOfGivingUp() throws {
        let src = try source(Self.config)
        XCTAssertTrue(src.contains("onMediaServicesReset?()"),
                      "The `.ended` catch must hand off to the de-bounced restart path.")
        // Counted, because the hook has TWO call sites since this slice and a repair that
        // accidentally removed the original media-services one would still satisfy `contains`.
        let calls = src.components(separatedBy: "onMediaServicesReset?()").count - 1
        XCTAssertEqual(calls, 2, """
        Expected exactly two callers of the recovery hook: the media-services reset it is named \
        after, and the interruption-resume failure added by #585. Found \(calls).
        """)
    }

    /// COUNTERWEIGHT. The diagnostic must survive the fix — the log line is how a founder's
    /// `echoel_diag.log` shows that the resume was ATTEMPTED and refused.
    func testTheFailingResumeStillSaysSoInTheLog() throws {
        XCTAssertTrue(try source(Self.config)
            .contains("Failed to reactivate audio session:"),
            "Recovering from a failure must not delete the evidence that it happened.")
    }

    // MARK: - COUNTERWEIGHTS: the state this row renders must still be produced

    /// The give-up path is what makes the banner appear at all. If it stopped setting these, the
    /// row would be correct, mounted, and permanently invisible — green on every scan above.
    func testTheGiveUpPathStillRaisesTheState() throws {
        let src = try source(Self.engine)
        XCTAssertTrue(src.contains("degraded = true"))
        XCTAssertTrue(src.contains("and auto-recovery gave up."))
        XCTAssertTrue(src.contains("recoveryAttempts < Self.maxRecoveryAttempts"),
                      "The cap is what turns repeated failure into a reportable state.")
    }

    /// And the retry has to actually reset things, or the button clears a banner without fixing
    /// what it describes — worse than no button, because it looks like it worked.
    func testStartStillClearsEverythingTheRetryPromises() throws {
        let src = try source(Self.engine)
        for cleared in ["degraded = false", "lastAudioError = nil", "recoveryAttempts = 0"] {
            XCTAssertTrue(src.contains(cleared), """
            `start()` no longer performs `\(cleared)`, so the Retry button would dismiss the \
            banner without re-arming self-healing.
            """)
        }
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct DegradedAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DegradedAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
