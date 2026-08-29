// TheBodyVoiceCountsAsAudibleTests.swift
// Echoel — a drone nobody is playing is still a performance. #586.
//
// WHAT THIS GUARDS. Two places decide whether the audio engine may keep running while the app is
// in the background, both answering App Store guideline 2.5.4 ("audio" background mode only while
// something audible needs it): the `scenePhase` → `.background` branch, and the transport's
// `background-idle` stop subscriber for an arrangement that ends while already backgrounded.
//
// ⛔ NEITHER KNEW ABOUT THE ARMED BODY VOICE. `BioReactiveSynthVoice` sounds a held tone whose
// colour follows the body and whose envelope breath opens and closes. It needs NO transport, NO
// pattern, NO poly note and NO recording — so every disjunct in both chains is false while it is
// droning, and the gate reads "idle". A glance at a message backgrounds the app and stops the
// engine mid-performance. It recovers on the way back, so the symptom is not silence-forever: it
// is a take that ends exactly where the user looked away, which reads as a broken instrument
// rather than as a lifecycle rule doing its job.
//
// The door is live and has been since #277 — `BreathVoiceRow`'s "Body voice" switch in the Bio
// panel, whose setter is the only production caller of `arm()`/`disarm()`. So this is reachable
// by one tap, not a corner.
//
// ⭐ `isArmed`, NOT `isPlayingNote`, AND THE CHOICE IS THE 2.5.4 QUESTION ITSELF. The voice also
// publishes `isPlayingNote` — "envelope currently open" — which looks like the stricter, more
// honest test and is the wrong one here: a breath-driven envelope CLOSES between breaths, so
// backgrounding during an exhale would stop the engine and the next inhale would find nothing to
// sound. The gaps are part of this instrument, not idleness. `isArmed` has the same shape as the
// held performer note already in the chain — audible work the user switched on with a labelled
// control and can switch off. Recorded here because it is the first question a reviewer asks, and
// because the opposite choice would have been defensible-looking and wrong.
//
// ⚠️ HONEST LIMITS.
//   · 6 tests, 10 assertion statements covering 16 needles (`grep -c`; two tests assert inside a
//     `for`, so needles outnumber statements). All SOURCE-TEXT SCANS: both chains are local
//     `let`s inside closures on a `View`, reachable from no test bundle. The voice itself is not
//     instantiated here — `arm()` opens a real envelope on a real DSP object, which is not
//     something a smoke test should do on a CI simulator.
//   · DEVICE PROBE, open and NOT covered: arm "Body voice", background the app, confirm the drone
//     continues and that the engine is NOT stopped (the diag log's `scene: idle audio engine
//     stopped (2.5.4)` line must be ABSENT). NEEDS-FOUNDER-VERIFY.
//   · This does not prove 2.5.4 compliance. It proves the gate now counts a source of sound it
//     did not count before, which is the direction compliance runs in: the rejection signature is
//     keeping the session alive while SILENT, and this adds a condition under which the app is
//     provably not silent.
//
// ⭐ GRADING (§3). Driven needle by needle against the parent with the faithful stripper.
//   · ONE finding, two sites: **3 of 16 needles** red on the parent — the two disjuncts and the
//     capture list one of them needs. Reported as one finding (#486).
//   · The stripper is **PROPHYLAKTISCH (0 of 16 needles flip)**, measured raw vs. stripped on
//     both trees rather than assumed — unlike the two guards two slices back, where it was
//     load-bearing because their own prose quoted the tokens their negative needles forbade.
//     Nothing here is a negative needle, which is exactly why it does not bite.
//   · 13 needles are COUNTERWEIGHTS, green on both trees, and they are the point (#343). The
//     dangerous repair here is not omission but WIDENING: dropping a disjunct, or replacing the
//     chain with something permissive, would also make the drone survive — and would keep the
//     engine alive when the app really is idle, which is the 2.5.4 rejection itself. So the other
//     disjuncts are pinned individually, at both sites.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBodyVoiceCountsAsAudibleTests: XCTestCase {

    private static let app = "Sources/Echoelmusic/EchoelmusicApp.swift"
    private static let voice = "Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - The finding, at both sites

    func testTheSceneChainCountsTheArmedBodyVoice() throws {
        XCTAssertTrue(try source(Self.app).contains("|| bioVoice.isArmed"), """
        The `scenePhase` → background gate does not count the armed body voice. Backgrounding \
        the app while it drones stops the engine as "idle" and ends the take.
        """)
    }

    func testTheTransportStopChainCountsItToo() throws {
        let src = try source(Self.app)
        XCTAssertTrue(src.contains("|| bioVoice?.isArmed == true"),
                      "The twin gate — an arrangement ending while already backgrounded — has "
                      + "the same blind spot and needs the same disjunct.")
        XCTAssertTrue(src.contains("weak polyVoice, weak bioVoice"),
                      "The subscriber must capture the voice weakly, like its three neighbours; "
                      + "a strong capture here would keep the voice alive past its owner.")
    }

    // MARK: - COUNTERWEIGHTS: the gate must not have been WIDENED

    /// The real hazard of editing a background-audio gate is not forgetting a source of sound —
    /// it is deleting a condition and calling the result a fix. Both chains must still name every
    /// disjunct they had, because a gate that is true too often is the 2.5.4 rejection signature
    /// ("plays silent audio to stay alive"), and nothing in this repo would notice.
    func testTheSceneChainStillNamesEveryOtherSourceOfSound() throws {
        let src = try source(Self.app)
        for disjunct in ["let audioNeeded = transport.isPlaying",
                         "|| beatPlayer.pattern.isPlaying",
                         "|| audioEngine.multiTrackRecorder.isRecording",
                         "|| microphoneManager.isRecording",
                         "|| audioEngine.isInputMonitoring",
                         "|| polyVoice.activeVoiceCount > 0"] {
            XCTAssertTrue(src.contains(disjunct), """
            The background gate lost `\(disjunct)`. Widening this chain is the 2.5.4 rejection \
            signature and is worse than the defect #586 fixed.
            """)
        }
    }

    /// The transport-stop subscriber has its own, SHORTER chain than the scene chain above,
    /// and it needs its own assertion for that reason. Given a message in #868: both of these
    /// were bare `XCTAssertTrue(src.contains(disjunct))`, so a maintainer who deleted a
    /// disjunct got a red with no name and no reason — the #367 shape, in the guard that
    /// protects a 2.5.4 gate.
    func testTheStopSubscriberStillNamesItsOwnSources() throws {
        let src = try source(Self.app)
        for disjunct in ["|| microphoneManager?.isRecording == true",
                         "|| (polyVoice?.activeVoiceCount ?? 0) > 0"] {
            XCTAssertTrue(src.contains(disjunct), """
            The transport-stop subscriber's background gate lost `\(disjunct)`. Widening this \
            chain is the 2.5.4 rejection signature; NARROWING it strands whatever the lost \
            disjunct represented. The mic one in particular is what keeps the engine alive \
            through a voice-timbre take — `VoiceCaptureController` names this test as the \
            reason its own cross-owner hazard is unreachable, so its header comment goes \
            stale in the same commit that removes this.
            """)
        }
    }

    // MARK: - COUNTERWEIGHTS: the flag must still mean what the gate assumes

    /// `isArmed` may only move through `arm()`/`disarm()`. If it became settable from anywhere,
    /// the gate would be reading a flag with no owner — and "the user switched this on" is the
    /// entire 2.5.4 argument for honouring it.
    func testTheFlagIsOwnedByArmAndDisarmAlone() throws {
        let src = try source(Self.voice)
        XCTAssertTrue(src.contains("public private(set) var isArmed = false"),
                      "A publicly settable arm flag would make the background gate readable by "
                      + "code that never produced a sound.")
        XCTAssertTrue(src.contains("isArmed = true"))
        XCTAssertTrue(src.contains("isArmed = false"))
    }

    /// And the door must still exist. A disjunct guarding a state nothing can enter is dead
    /// weight in a lifecycle gate — the shape this repo calls a doorless surface.
    func testTheBodyVoiceStillHasItsSwitch() throws {
        let src = try source(Self.studio)
        XCTAssertTrue(src.contains("set: { $0 ? voice.arm() : voice.disarm() }"),
                      "The \"Body voice\" toggle is the only production caller of arm/disarm.")
        XCTAssertTrue(src.contains("Text(\"Body voice\")"),
                      "The switch must stay labelled — an unlabelled background-audio source is "
                      + "one the user cannot turn off, which is a different 2.5.4 problem.")
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct BodyVoiceAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw BodyVoiceAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
