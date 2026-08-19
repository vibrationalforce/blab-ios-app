// TheDemoSourceWakesWhenTheSensorStopsTests.swift
// Echoel — #626 (Ultra-Audit 2026-08-19, finding B3, CRITICAL): the Demo bio source must
// not be permanently deaf after one real frame.
//
// WHAT THIS GUARDS. `BioSimulator.start(publishing:)` yields to a real publisher so two
// sources never fight over the bus. It asked that question of `bus.latestBio` — the raw
// SNAPSHOT, which is NEVER cleared. So a single frame from any real source (camera, BLE,
// HealthKit) parked the loop for the rest of the app session: sleep 2 s, see the same
// stale frame, sleep again, never publish. `BioSimulator` is reachable — it is the Demo
// entry in the Pulse source dropdown (`EchoelStudioView.startBioSource`) — so the
// observable defect was "use the camera once, then switch to Demo, and nothing ever moves
// again", with no error anywhere and a source label reading Demo.
//
// The fix routes the deferral through `bus.usableBio()`, which applies each source's OWN
// window (`BioSource.freshnessWindow`) and is the question the deferral always meant to
// ask: is a real signal arriving RIGHT NOW?
//
// KIND (§1): TWO KINDS.
//   · claims 1-3 are BEHAVIOURAL against the real `EngineBus`. They prove the PROPERTY the
//     fix leans on — that a stale live frame stops being usable while the raw snapshot
//     keeps returning it — and would hold under any renaming.
//   · claim 4 is a SOURCE-TEXT SCAN of the call site, because the loop is a detached
//     `Task` with `Task.sleep`; this bundle cannot drive it deterministically. That the
//     founder's Demo source actually starts ticking again is a DEVICE probe.
//
// GRADING (#433 / §3, against the pre-#626 parent):
//   · claims 1-3 are COUNTERWEIGHTS — green on both trees ONCE THEY AWAIT THE SNAPSHOT.
//     `usableBio()` and `latestBio` both predate this slice; the fix changes only WHO
//     calls which. Booking them as regressions would be the flattering-direction defect
//     §3 names. ⛔ #626b: as first shipped they were green on NEITHER tree — see
//     `publishAndSettle`. A guard graded "green on both trees" while red on both is the
//     #488 failure (a red gate riding a cycle), and it is worse than the mislabel §3 is
//     usually about, because a wrong LABEL still leaves a working test.
//   · claim 4 is a REGRESSION — red on the parent for the reason its name gives (the call
//     site read the raw snapshot there). NOT "FORWARD": §3 reserves that for an assertion
//     that could never have been red because the symbol did not exist. #625b carries the
//     retraction of exactly that mislabel.
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED **TRAGEND** — and for once
// that word is earned rather than guessed. Of the FOUR source-scan verdicts (claim 4's two
// assertions × two trees), ONE flips: on the worktree `bus.latestBio` occurs ZERO times
// stripped and TWICE raw, because the #626 comment quotes the old spelling to explain why
// it is wrong. Without `codeOnly` the absence claim would be RED on a correct tree — the
// exact class the stripper exists for. Claims 1-3 are behavioural and independent of both
// tree and stripper.
//
// ⛔ The two slices before this one (#623, #625) each ASSERTED "TRAGEND" from the shape of
// the diff and measured PROPHYLAKTISCH. The difference here is not better intuition: it is
// that a comment which quotes a needle in its FULL spelling inflates the count, while one
// that names it in prose ("the running state", `claimRecordRoute` without its argument)
// does not. Both prior headers carry that retraction.
//
// ⚠️ #364: deferring by a DIFFERENT mechanism is not forbidden — clearing `latestBio` on an
// explicit source switch would be faster and is named in the source comment as the larger
// change it is. What is forbidden silently is going back to the raw snapshot, which cannot
// expire.

import Foundation
import XCTest
@testable import Echoelmusic

@MainActor
final class TheDemoSourceWakesWhenTheSensorStopsTests: XCTestCase {

    private func frame(ageSeconds: TimeInterval, source: BioSource) -> BioSampleFrame {
        BioSampleFrame(timestamp: CFAbsoluteTimeGetCurrent() - ageSeconds,
                       heartRateBPM: 61, hrvNormalized: 0.42,
                       breathRate: 12, breathPhase: 0.25,
                       coherence: 0.7, motionEnergy: 0, source: source)
    }

    /// Publish and WAIT for the snapshot. ⛔ #626b (review CRITICAL 1): the first version
    /// of this file published and asserted synchronously, and all three behavioural
    /// methods were therefore RED ON BOTH TREES — `EngineBus.publish(bio:)` is
    /// `nonisolated` and assigns `latestBio` inside a `Task { @MainActor }`, which cannot
    /// run before a synchronous main-actor body finishes. The repo had already written
    /// this down twice (`BioEventSourceSwitchTests.step`, `EngineBusTests`), and the
    /// commit message claimed those three claims were "green on both trees". They were
    /// green nowhere. Worse, it made the ONE decisive assertion vacuous: with `latestBio`
    /// still nil, `usableBio()` returns nil at its FIRST guard and never reaches the age
    /// comparison the failure message names — it passed for the opposite of its reason.
    @discardableResult
    private func publishAndSettle(_ bus: EngineBus, _ f: BioSampleFrame,
                                  tries: Int = 100) async -> Bool {
        bus.publish(bio: f)
        for _ in 0..<tries {
            if bus.latestBio?.timestamp == f.timestamp { return true }
            await Task.yield()
        }
        XCTFail("""
            the frame stamped \(f.timestamp) never reached the bus snapshot — every \
            assertion below would be measuring nil rather than the frame it names.
            """)
        return false
    }

    /// 1 — COUNTERWEIGHT: a LIVE frame that just arrived is usable, so the simulator still
    /// yields. The fix must not turn the deferral off.
    func testAFreshCameraFrameStillSilencesTheSimulator() async {
        let bus = EngineBus()
        await publishAndSettle(bus, frame(ageSeconds: 0.5, source: .cameraPPG))
        XCTAssertNotNil(bus.usableBio(), """
            a camera frame half a second old is no longer usable — the Demo source would \
            then publish OVER a live sensor, which is the failure the deferral exists to \
            prevent. Check `BioSource.freshnessWindow` for `.cameraPPG` (6 s).
            """)
    }

    /// 2 — THE PROPERTY THE FIX RESTS ON: past its window the live frame stops being
    /// usable, while the raw snapshot keeps handing it out unchanged. That gap IS the bug.
    func testAStoppedCameraExpiresWhileTheSnapshotDoesNot() async {
        let bus = EngineBus()
        await publishAndSettle(bus, frame(ageSeconds: 30, source: .cameraPPG))
        XCTAssertNotNil(bus.latestBio, """
            `latestBio` no longer returns an aged frame — if the bus started CLEARING the \
            snapshot, #626's premise changed and this whole file should be re-read (that \
            would be the larger fix the source comment names).
            """)
        XCTAssertEqual(bus.latestBio?.source, .cameraPPG)
        XCTAssertNil(bus.usableBio(), """
            a 30-second-old camera frame is still reported usable. `usableBio()` is the \
            only thing that lets the Demo source ever wake up again after a real sensor \
            stops — without expiry the simulator is parked forever (#626/B3).
            """)
    }

    /// 3 — COUNTERWEIGHT: the window is PER SOURCE, and that is deliberate. A Watch
    /// reading of the same age is still usable, so Demo keeps yielding to a slow-but-live
    /// wrist instead of elbowing it aside.
    func testTheWindowIsPerSourceNotOneGlobalNumber() async {
        let bus = EngineBus()
        await publishAndSettle(bus, frame(ageSeconds: 30, source: .healthKit))
        XCTAssertNotNil(bus.usableBio(), """
            a 30-second-old Watch frame expired — HealthKit is latent and sporadic (90 s \
            window by design). Collapsing every source onto one short window would make \
            the Demo source talk over a live wrist, trading #626's bug for its mirror.
            """)
    }

    /// 4 — REGRESSION: the call site asks the freshness question, not the snapshot one.
    func testTheSimulatorDefersToAUsableFrameNotAStoredOne() throws {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("Sources/Echoelmusic/Bio/BioSimulator.swift")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present at \(path.path)")
        }
        let lines = SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        XCTAssertTrue(lines.contains { $0.contains("bus.usableBio()") }, """
            `BioSimulator` no longer defers through `usableBio()` (#626, Ultra-Audit B3). \
            The deferral asks "is a real publisher active?", and only a freshness-bounded \
            read can answer it — `latestBio` is a snapshot that is never cleared, so one \
            camera frame parks the Demo source for the whole app session.
            """)
        XCTAssertEqual(lines.filter { $0.contains("bus.latestBio") }.count, 0, """
            the raw `bus.latestBio` snapshot read is back in `BioSimulator`. That read \
            cannot expire, which is exactly B3: pick Demo after using the camera and no \
            frame is ever published again, with no error and a label saying Demo.
            """)
    }
}
