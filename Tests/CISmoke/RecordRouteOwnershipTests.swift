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
    /// GRADING AGAINST THE PARENT (§3), transcribed in Python against `git show HEAD:…` and
    /// the worktree, with `//` lines stripped exactly as `code(_:)` does:
    /// · the two per-guard assertions are **REGRESSIONS** — red on HEAD for precisely the
    ///   reason their names give: both exits really do `return` without releasing.
    /// · the count assertion is **NOT** a regression. It is red on HEAD only because this
    ///   commit raised the expected number from 2 to 4. Booking a pin update as a caught
    ///   defect is the flattering direction (#433) — it is a pin, and it is blunt on purpose.
    func testTheMicRecorderClaimsAndReleasesTheRoute() throws {
        let file = try code("Sources/Echoelmusic/MicrophoneManager.swift")
        XCTAssertTrue(slice(of: file, from: "func startRecording()", to: "\n    }\n")
            .contains("claimRecordRoute(.microphoneManager)"), """
        `MicrophoneManager.startRecording` no longer claims the route as an owner.
        """)
        // FIVE paths follow the claim: the two `guard … else { return }` exits inside the
        // `do` (#889), the placeholder-format refusal (#890), the start `catch`, and
        // `stopRecording`.
        XCTAssertEqual(file.components(separatedBy: "releaseRecordRoute(.microphoneManager)").count - 1, 5, """
        `MicrophoneManager` no longer releases the route on ALL FIVE paths that follow its \
        claim. Dropping the `catch` one is how a failed start leaves a stale owner that blocks \
        every later downgrade; dropping the `stopRecording` one restores the bare unconditional \
        `downgradeToPlaybackAfterRecording`, which cuts the input monitor's mic mid-performance \
        — the two halves of #299. Two more are the early `return`s inside the `do` (#889): a \
        `return` from a `do` never reaches its `catch`. The fifth is the placeholder-format \
        refusal (#890), and it is the only one of the five that is REACHABLE today.

        ⚠️ WHY A COUNT AND NOT A SHAPE. This is a blunt pin and it is chosen deliberately: the \
        alternative is parsing control flow out of source text, which this bundle has no \
        business doing. The count is allowed to CHANGE — if you add or remove an exit, change \
        it here and say which path in this message. What it forbids is changing the code and \
        NOT the message (#364/#655).

        ⛔ AND IT DID ITS JOB ONE COMMIT AFTER IT WAS WRITTEN. #889 raised this pin from 2 to \
        4 and wrote that very sentence; #890 then added a fifth release and did NOT come back \
        here, so this assertion was red on the pushed tree until the mandatory review caught \
        it. The lesson is not "remember the pin" — it is that a pin whose message names the \
        repair is what makes the miss a five-minute fix instead of a hunt.

        ⚠️ THE COUNT IS OF CALLS, NOT MENTIONS. `code(_:)` strips `//` lines first, so the \
        prose above and in `MicrophoneManager` does not inflate it.
        """)

        // #889: each early exit inside the `do` releases BEFORE it returns. Anchored on the two
        // log literals, which are the stable part of those blocks — a line window is unsound
        // here (this repo writes long comment blocks inside guard bodies).
        //
        // ⚠️ HIDDEN COUPLING, found by the audio-thread review of #889 and written down rather
        // than left to be rediscovered: `slice(…, to: "return")` is safe ONLY because `code(_:)`
        // strips full-line `//` comments first. The comment this commit added inside the first
        // guard contains the word "returns" ("never returns the session to `.playback`") ABOVE
        // the release call — on RAW text the window would close early and this assertion would
        // fail on a correct tree, the #408 trap. It passes on stripped text. If anyone ever puts
        // a non-comment string containing `return` into either guard body, re-anchor this on a
        // token that cannot appear in prose.
        for (anchor, what) in [("failed to create AVAudioEngine", "the engine-creation guard"),
                               ("failed to get microphone input format", "the input-format guard")] {
            let body = slice(of: file, from: anchor, to: "return")
            XCTAssertTrue(body.contains("releaseRecordRoute(.microphoneManager)"), """
            \(what) in `MicrophoneManager.startRecording` returns without releasing the record \
            route (#889). It sits INSIDE the `do`, so the `catch` below it never runs for this \
            path, and the owner set then never empties: every later monitoring-off finds a \
            non-empty set and never returns the session to `.playback`.

            Both guards are UNREACHABLE today — that is why this is a class fix and not a bug \
            fix, and why #299 was right about the live defect while its wording ("the one \
            reachable exit") was too strong. If you make either guard reachable, this claim is \
            the thing that stops the leak coming back silently.
            """)
        }
    }

    /// #900 — the throwing exit RELEASED its route (#299) and kept its GRAPH.
    ///
    /// GRADING (§3), driven in Python against parent and worktree before pushing: three
    /// REGRESSIONS, all three restating ONE absent repair. ⛔ #901 corrected the BUCKET: #900
    /// filed them as "ANCHOR ABSENCE, reported three times (#486)", and §3 defines anchor
    /// absence as *the extraction found nothing*. On the parent both anchors exist and the
    /// slice is 274 characters — the extraction SUCCEEDS, only the fix is missing. #486's
    /// spirit (one defect, not three findings) is right; the bucket was not, and §3 says
    /// getting your own grading wrong in the HARSH direction is the same defect as the
    /// generous one. The fourth claim is a COUNTERWEIGHT, green on both trees and the point of
    /// the file: it pins what the block must NOT do.
    ///
    /// KIND (§1): SOURCE-TEXT SCAN. Whether the memory is actually returned is an
    /// instruments-on-device question and is not claimed here.
    func testTheThrowingStartExitDropsItsHalfBuiltGraph() throws {
        let file = try code("Sources/Echoelmusic/MicrophoneManager.swift")
        // ⛔ #901 — THE `to:` ANCHOR WAS `"#if os("` AND THAT WAS A LATENT FALSE RED. A later
        // `#if os(...)` or `#if DEBUG` inserted between the breadcrumb and the nils closes the
        // window early: `body` is non-empty, so the isEmpty claim below stays green, and all
        // three nil claims go red saying the code dropped a line it still has — a red pointing
        // at the wrong repair (the #408/#898 window trap). The release call cannot be inserted
        // by accident and IS the end of the block.
        //
        // ⭐ AND THE ANCHOR CARRIES AN ORDERING GUARANTEE, which the old one held only by luck
        // and nobody had written down: ending here pins the three nils BEFORE
        // `releaseRecordRoute`. That order is load-bearing — the engine (with a realized input
        // node) is deallocated while the session is still `.playAndRecord`. The reverse order
        // takes the edges down after the route is gone, which is the neighbourhood of the
        // `isInputConnToConverter` family (#889). Whoever re-anchors this next must carry that
        // sentence with them.
        let body = slice(of: file, from: "mic: start FAILED",
                         to: "releaseRecordRoute(.microphoneManager)")
        XCTAssertFalse(body.isEmpty, """
        The `catch` in `MicrophoneManager.startRecording` no longer runs from the FAILED \
        breadcrumb to its record-route release — either the breadcrumb was reworded or the \
        release moved. Re-anchor this claim in the same commit (§4), and keep the window \
        ending AT the release so the nil-before-release order stays pinned.
        """)
        for ref in ["self.audioEngine = nil", "self.inputNode = nil", "self.complexDFT = nil"] {
            XCTAssertTrue(body.contains(ref), """
            The throwing start exit no longer drops `\(ref)`. #891 took the abort path away \
            from `stopRecording()`, which used to be the thing that cleaned up after a failed \
            start; without these three the FFT scratch buffer and a stopped engine live on \
            until the next start. This is a LIFETIME defect, not a crash path — the #877 TRAP \
            note in `stopRecording()` weighed this same state and calls it otherwise harmless, \
            and that honest severity is why the repair is three lines and not a redesign.
            """)
        }
        // COUNTERWEIGHT — green on both trees, and the reason the fix is three lines.
        // ⚠️ #364: this forbids a tap removal HERE, not everywhere. If a future change makes
        // the engine reachable in a RUNNING state at this point, the removal becomes correct
        // and this claim must move with it — say so in the message you replace this one with.
        XCTAssertFalse(body.contains("removeTap"), """
        The throwing start exit now reaches into `inputNode` to remove the tap. Only \
        `audioEngine.start()` can throw after the tap is installed, so the engine here is \
        never running — and `stopRecording()` removes the tap ONLY under `engine.isRunning` \
        for exactly that reason: touching `inputNode` on a dead engine is the \
        `isInputConnToConverter` family, seven device logs deep and still without a named \
        trigger. Dropping the reference is safe; reaching into the node is not.
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

    // MARK: - No bare upgrades anywhere (#825 — the exception is retired)

    /// ⛔ Until #825 this section was called "The one deliberate exception" and BLESSED the
    /// two grant-time upgrades in `MicrophoneManager.requestPermission`, on the argument
    /// that "an unowned raise is lowered again by the next release". That argument was
    /// measured false in the case that matters: grant once and never record, and NO
    /// claim/release cycle ever runs — the ownerless raise persists for the whole session,
    /// which kept the shared route record-capable while the user only played (the #824
    /// audit's amplifier finding). Permission is consent, not use; every real mic use
    /// claims for itself (`startRecording`, `setInputMonitoring`, `MultiTrackRecorder`).
    ///
    /// ⛔ The first version of the OLD test checked only `AudioEngine` and
    /// `MultiTrackRecorder` while its name claimed to cover everything — leaving out
    /// `MicrophoneManager`, the one file where a new bare upgrade is easiest to add. The
    /// repaired shape bounds ALL THREE files at zero.
    func testNoProductionFileCallsTheBareUpgrade() throws {
        for path in ["Sources/Echoelmusic/Audio/AudioEngine.swift",
                     "Sources/Echoelmusic/Audio/MultiTrackRecorder.swift",
                     "Sources/Echoelmusic/MicrophoneManager.swift"] {
            XCTAssertFalse(try code(path).contains("upgradeToPlayAndRecord()"), """
            \(path) calls `upgradeToPlayAndRecord()` directly again. Since #825 there is \
            NO sanctioned bare caller: an ownerless raise has no releaser by construction \
            (the owner set is never entered, so `releaseRecordRoute`'s empty-check can \
            never fire for it) and persists for the whole session. Claim through \
            `claimRecordRoute(_:)` with a release on every exit — and if this is a \
            deliberate redesign, pull the ⚠️ doc on `upgradeToPlayAndRecord` and the \
            SESSION_LOG #825 entry in the same commit (#456).
            """)
        }
    }

    // MARK: - #855: both category moves re-assert the chosen IO-buffer tier

    /// The founder's v10.79.425 log measured `buf=23.0` ms GRANTED on the built-in
    /// route against the 512-frame (10.7 ms) default: a category change renegotiates
    /// the IO buffer and the launch-time preference does not carry across it. Both
    /// transition methods must repeat the CURRENT tier after `setCategory`. This is
    /// not the #674 auto-drop trap — the tier itself stays the player's choice; only
    /// the already-chosen value is re-asserted to the new route.
    func testBothCategoryMovesReassertThePreferredBuffer() throws {
        let config = try code("Sources/Echoelmusic/Audio/AudioConfiguration.swift")
        for fn in ["static func upgradeToPlayAndRecord", "static func downgradeToPlaybackAfterRecording"] {
            guard let start = config.range(of: fn) else {
                XCTFail("`\(fn)` is gone — re-anchor this claim (§4).")
                continue
            }
            let body = String(config[start.lowerBound...].prefix(1_400))
            let cat = body.range(of: "setCategory(")
            let reassert = body.range(of: "setPreferredIOBufferDuration(")
            XCTAssertNotNil(cat, "`\(fn)` no longer changes the category in its first 1400 chars — re-anchor.")
            XCTAssertNotNil(reassert, """
                `\(fn)` no longer re-asserts the IO-buffer preference after its category \
                change (#855). The next monitoring session then runs on whatever the OS \
                renegotiates — the founder-measured 23 ms against a 10.7 ms choice.
                """)
            if let c = cat, let r = reassert {
                XCTAssertTrue(c.lowerBound < r.lowerBound, """
                    the re-assert in `\(fn)` sits BEFORE the category change — the OS \
                    renegotiates after it and the preference is lost again (#855).
                    """)
            }
        }
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
