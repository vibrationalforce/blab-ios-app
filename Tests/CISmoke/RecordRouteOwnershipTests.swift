// RecordRouteOwnershipTests.swift
// Echoel — #299. Blocking bundle.
//
// ⭐ THE DEFECT IN ONE SENTENCE: three features could raise the SHARED audio session to
// `.playAndRecord` and only ONE of them ever lowered it again — and that one lowered it
// unconditionally, including out from under the other two.
//
// Why that is not a tidiness issue. `AudioConfiguration.configureAudioSession`'s own doc says
// the app's default is `.playback` for one reason: `.playAndRecord` signals "I need the mic",
// which makes iOS route a connected Bluetooth headset to HFP — the 8/16 kHz MONO CALL CODEC —
// for the WHOLE SYSTEM. Every parallel app (Spotify, Apple Music, a video call) suddenly plays
// through that tinny mono route. Before #299, switching input monitoring off, or finishing one
// `MultiTrackRecorder` take, left the system there until Echoel was force-quit. The founder's
// standing rule is "Echoel must not degrade the sound of other apps running in parallel"; this
// was the file that exists to enforce it, failing to.
//
// ⚠️ THESE ARE SOURCE-TEXT TESTS, NOT RUNTIME ONES, AND THAT IS DELIBERATE. Exercising
// `claimRecordRoute` for real would mutate the simulator's process-wide `AVAudioSession` —
// a test that reconfigures shared hardware state is exactly the kind that goes flaky in CI and
// then gets deleted. What can be pinned honestly is the WIRING: every claim has a matching
// release on every exit path. Say so rather than implying a runtime proof.

import Foundation
import XCTest
@testable import Echoelmusic

@MainActor
final class RecordRouteOwnershipTests: XCTestCase {

    // MARK: - The owner set itself

    /// The enum is the whole point: a Set is idempotent in BOTH directions, so a double claim
    /// and a double release are harmless. A refcount was rejected precisely because
    /// `setInputMonitoring` has failure paths that return AFTER the upgrade — one unbalanced
    /// increment there and the route leaks forever with nothing to notice it.
    func testEveryMicFeatureHasItsOwnOwnerCase() {
        XCTAssertEqual(Set(AudioConfiguration.RecordRouteOwner.allCases.map(\.rawValue)),
                       ["inputMonitoring", "microphoneManager", "multiTrackRecorder"], """
        the owner set no longer names exactly the three features that can raise the record \
        route. If a fourth mic feature was added it needs a case here AND a release on every \
        one of its exit paths — otherwise it raises the shared session and never lowers it, \
        which is the #299 defect returning under a new name.
        """)
    }

    /// The set must START empty, or the first release would lower a route nobody raised.
    ///
    /// ⚠️ Asserted against the DECLARATION, not against the live set. It is process-wide static
    /// state, so a runtime emptiness check passes or fails on test ORDER the moment any future
    /// test claims the route — and a blocking test that fails by ordering is one that gets
    /// deleted rather than fixed. (#299 shipped a `recordRouteHolders` accessor to make that
    /// runtime check possible; nothing used it, for this reason, so the Nachlese deleted it.)
    func testTheOwnerSetStartsEmpty() throws {
        XCTAssertTrue(try code("Sources/Echoelmusic/Audio/AudioConfiguration.swift")
            .contains("private static var recordRouteOwners: Set<RecordRouteOwner> = []"), """
        the owner set no longer starts empty (or was renamed). A non-empty initial value means \
        the first `releaseRecordRoute` finds a leftover holder and refuses to lower the route — \
        the leak this whole slice removes, reintroduced at the declaration.
        """)
    }

    // MARK: - Every claim has a release

    /// ⭐ THE ACTUAL REGRESSION GUARD. Before #299 there were FIVE upgrade call sites across
    /// three features and exactly ONE downgrade. (An earlier version of this line said
    /// "3 claims : 1 release" — that counted FEATURES and quietly dropped the two
    /// permission-grant sites it discusses elsewhere as the exception.)
    func testInputMonitoringClaimsAndReleasesTheRoute() throws {
        let body = try slice(of: code("Sources/Echoelmusic/Audio/AudioEngine.swift"),
                             from: "func setInputMonitoring(", to: "\n    }")
        XCTAssertFalse(body.isEmpty, "`setInputMonitoring` is gone from AudioEngine.swift")
        XCTAssertTrue(body.contains("claimRecordRoute(.inputMonitoring)"), """
        input monitoring raises the session with a bare `upgradeToPlayAndRecord` again. It then \
        owns nothing, so the next release by any other feature lowers the route out from under \
        a live monitor.
        """)
        // FOUR exits after the claim: the failed claim itself, the format guard, the
        // engine-restart failure, and OFF.
        // ⛔ #631: this said THREE and had been RED since #628 added the failed-claim exit —
        // unnoticed because the bundle's per-test verdicts do not reliably reach the job log
        // (#445), so a red assertion here rides along looking exactly like the standing #396
        // failure. Its twin in `MonitoringCannotStrandTheEngineStoppedTests` was red for the
        // same commit and the same reason.
        XCTAssertEqual(body.components(separatedBy: "releaseRecordRoute(.inputMonitoring)").count - 1, 4, """
        input monitoring no longer releases the route on all FOUR paths that follow its claim \
        (the claim itself failing, no valid input format, engine restart failed, monitoring \
        switched off). A missing one \
        leaves every other app's Bluetooth headset on the HFP mono call codec until Echoel is \
        force-quit — silently, because nothing in Echoel sounds wrong.
        """)
    }

    /// ⛔ THIS TEST HAD NO COUNT ASSERTION AND IT WAS THE ONE FILE THAT NEEDED IT. #299 shipped
    /// with a claim in `startRecording`'s `do` block and NO release in its `catch` — the single
    /// reachable exit — so a failed engine start (or a failed session upgrade, which throws into
    /// the same catch) stranded `.microphoneManager` in the owner set forever. `contains` was
    /// satisfied by the `stopRecording` release and reported the file as balanced.
    func testTheMicRecorderClaimsAndReleasesTheRoute() throws {
        let file = try code("Sources/Echoelmusic/MicrophoneManager.swift")
        XCTAssertTrue(slice(of: file, from: "func startRecording()", to: "\n    }\n")
            .contains("claimRecordRoute(.microphoneManager)"), """
        `MicrophoneManager.startRecording` no longer claims the route as an owner.
        """)
        // The start `catch` plus `stopRecording`.
        XCTAssertEqual(file.components(separatedBy: "releaseRecordRoute(.microphoneManager)").count - 1, 2, """
        `MicrophoneManager` no longer releases the route on BOTH paths that follow its claim \
        (the `startRecording` catch, and `stopRecording`). Dropping the catch is how a failed \
        start leaves a stale owner that blocks every later downgrade; dropping the stop one \
        restores the bare unconditional `downgradeToPlaybackAfterRecording`, which cuts the \
        input monitor's mic mid-performance — the two halves of #299, one on each side.
        """)
    }

    func testTheMultiTrackRecorderClaimsAndReleasesTheRoute() throws {
        let file = try code("Sources/Echoelmusic/Audio/MultiTrackRecorder.swift")
        XCTAssertTrue(file.contains("claimRecordRoute(.multiTrackRecorder)"), """
        `MultiTrackRecorder` no longer claims the route as an owner.
        """)
        // Two failure paths plus stopRecording.
        XCTAssertEqual(file.components(separatedBy: "releaseRecordRoute(.multiTrackRecorder)").count - 1, 3, """
        `MultiTrackRecorder` no longer releases the route on all THREE paths that follow its \
        claim (invalid input format, file creation failed, stopRecording). Before #299 it \
        released on NONE of them: one take put the whole system on `.playAndRecord` for good.
        """)
    }

    // MARK: - The one deliberate exception

    /// `requestPermission` upgrades on the permission GRANT, before any recording exists to own
    /// it. That is left as a bare upgrade on purpose — and it is safe precisely because an
    /// unowned raise is lowered again by the next release, instead of persisting.
    ///
    /// ⛔ The first version checked only `AudioEngine` and `MultiTrackRecorder` while its name
    /// claimed to cover everything — leaving out `MicrophoneManager`, the ONE file where a new
    /// bare upgrade is both easiest to add and most harmful, because it already contains two
    /// legitimate ones. Bounding it to exactly TWO there is the assertion that matters.
    func testTheOnlyRemainingBareUpgradesAreThePermissionGrant() throws {
        for path in ["Sources/Echoelmusic/Audio/AudioEngine.swift",
                     "Sources/Echoelmusic/Audio/MultiTrackRecorder.swift"] {
            XCTAssertFalse(try code(path).contains("upgradeToPlayAndRecord()"), """
            \(path) calls `upgradeToPlayAndRecord()` directly again. Only \
            `MicrophoneManager.requestPermission` may — everywhere else the raise must be \
            owned, or it cannot be handed back.
            """)
        }
        let mic = try code("Sources/Echoelmusic/MicrophoneManager.swift")
        XCTAssertEqual(mic.components(separatedBy: "upgradeToPlayAndRecord()").count - 1, 2, """
        `MicrophoneManager` has a number of bare `upgradeToPlayAndRecord()` calls other than \
        the two permission-grant sites (iOS 17+ and the older callback). A third one would \
        raise the shared session with no owner from a path that is not "permission just \
        granted" — the raise it cannot hand back.
        """)
    }

    // MARK: - Helpers

    private func slice(of text: String, from: String, to: String) -> String {
        guard let start = text.range(of: from) else { return "" }
        let rest = text[start.upperBound...]
        guard let end = rest.range(of: to) else { return "" }
        return String(rest[..<end.lowerBound])
    }

    /// Source text with `//` comment lines stripped, so a claim mentioned in prose cannot
    /// satisfy an assertion about a call.
    private func code(_ path: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
            source tree not present — these are source-text tests, so they SKIP rather than \
            reporting a green they did not earn.
            """)
        }
        let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}
