// OneGoodTickIsNotABodyTests.swift
// Echoel — #566, cycle C2 of the 2026-08-13 handover.
//
// THE FLAP, MEASURED RATHER THAN ASSUMED. The founder's 2026-08-12 device log shows `body=`
// flipping 0↔1 seven times in three minutes with a finger held on the lens. `body=` is
// `bus.usableBio() != nil`, so each flip is the bus gaining or losing a publishable frame.
// The publish gate was INSTANTANEOUS — `shouldPublish(bpm:confidence:autoStrength:)` evaluated
// per tick — so one trustworthy sample inside a bad stretch opened the bus and the next bad
// one closed it. That half is fixed here: `BioTrustLatch` requires the evidence to hold.
//
// ⛔ AND THE OTHER HALF CANNOT BE FIXED BY HYSTERESIS, WHICH IS THE MORE USEFUL FINDING.
// `usableBio()` expires a camera frame at `BioSource.cameraPPG.freshnessWindow` = 6 s against
// the frame's OWN timestamp, and the publisher's dropout hold re-emits the last good frame
// WITHOUT re-stamping it — deliberately, with the reason written at the call site (a re-stamped
// hold is indistinguishable from a live reading, which strips every consumer of its own
// staleness policy). So no latch, at any release length, can keep `body=1` through more than
// six seconds of real dropout. Seven flips in three minutes therefore means at least seven
// dropouts LONGER than six seconds, and that is a signal-quality fact — exposure drift, motion
// artifact — which is exactly what C3 exists to instrument. Claim 4 pins the 6 s ceiling so
// this reasoning is executable rather than a paragraph someone has to re-derive.
//
// ⚠️ THE LIMIT, PER ASSERTION:
//   · claims 1–3 are END-TO-END BEHAVIOUR over `BioTrustLatch`, a pure Foundation-only value
//     type with an injected clock. They drive the shipped logic.
//   · claim 4 is END-TO-END too, but over a different subject — the two constants that set the
//     structural ceiling (`freshnessWindow`, `bioHoldTicks`). It is a counterweight, and it is
//     the one that goes red the day someone "fixes" the flap by widening a window instead of
//     fixing the signal.
//   · claim 5 is a SOURCE SCAN: the latch must actually be in the publish path. The publisher
//     is `@MainActor` and owns a live `AVCaptureSession`, so no test here can drive its loop;
//     `shouldPublish`'s own doc block already records that its wiring is unpinned, and this is
//     the smallest honest instrument for the same question.
//   · DEVICE PROBE, open — and it is C2's real acceptance line: a 3-minute finger-held log
//     with at most one `body=` transition. Nothing here can stand in for it, and per the
//     finding above the expected outcome is FEWER flips, not necessarily one.
//
// ⚠️ HONEST GRADING, transcribed in Python against the parent (`1cd54ef`) and this tree. The
// file does NOT compile against the parent — `BioTrustLatch` does not exist there and claims
// 1–3 name it — so per §3 no assertion has a verdict on that tree; the grading is by
// hand-transcription of the logic, stated as such rather than implied green:
//   · ONE ABSENCE, REPORTED ONCE (#486): the missing type is a single fact.
//   · claims 1–3 are FORWARD guards over logic this commit creates. Booking them as
//     regressions would be the flattering direction (#433).
//   · claims 4 and 5 are COUNTERWEIGHTS. Claim 4 is green on BOTH trees — both constants are
//     unchanged by this cycle, which is the point: the cycle did not move a window, and the
//     assertion says so. Claim 5 is red on the parent for the same one absence.
//   · STRIPPER: PROPHYLAKTISCH, 0 of 2 verdicts flip — measured, not assumed. Claim 5's two
//     needles (`BioTrustLatch()` and `bioTrust.step(`) appear in `CameraRPPGBioPublisher.swift`
//     in code on this tree and nowhere at all on the parent, in prose or otherwise, so
//     stripping changes no verdict on either tree. It is kept because the file's comments
//     DISCUSS the latch at length, and the day someone writes `bioTrust.step(` inside an
//     explanatory block the raw scan would start passing on prose.

import Foundation
import XCTest
@testable import Echoelmusic

final class OneGoodTickIsNotABodyTests: XCTestCase {

    private static let publisher = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"

    // MARK: - claim 1 (END-TO-END) — a single good tick does not open the bus

    /// The blip, driven. The publish loop steps this once per second, so "one good tick" is one
    /// second of evidence inside an otherwise bad stretch — the exact shape that produced a
    /// 0→1→0 in the device log.
    func testASingleTrustworthyTickNeverEngages() {
        var latch = BioTrustLatch()
        var t = 0.0
        for i in 0..<30 {
            let good = (i == 7) || (i == 19)          // two isolated good seconds
            let engaged = latch.step(trustworthy: good, now: t)
            XCTAssertFalse(engaged, """
                The latch engaged at t=\(t)s on isolated evidence. One trustworthy sample \
                inside a bad stretch is what the peak counter produces when it briefly \
                self-agrees; admitting it opens the bus for one publish and closes it again, \
                which is a `body=` flip in the log and a bio↔idle jump in the visual.
                """)
            t += 1
        }
    }

    // MARK: - claim 2 (END-TO-END) — sustained evidence does engage, and on time

    func testSustainedEvidenceEngagesAfterTheEngageWindow() {
        var latch = BioTrustLatch(engageSeconds: 3, releaseSeconds: 5)
        XCTAssertFalse(latch.step(trustworthy: true, now: 0), "engaged instantly at t=0")
        XCTAssertFalse(latch.step(trustworthy: true, now: 1), "engaged after 1 s, needs 3")
        XCTAssertFalse(latch.step(trustworthy: true, now: 2.999), """
            engaged before the window elapsed — the boundary must be `>=`, and just under it \
            must still be closed, or "3 seconds" means "the third sample" and the behaviour \
            depends on the caller's tick rate rather than on time.
            """)
        XCTAssertTrue(latch.step(trustworthy: true, now: 3), "did not engage at exactly 3 s")
        XCTAssertTrue(latch.isEngaged)
    }

    // MARK: - claim 3 (END-TO-END) — a dip does not release, and the run restarts

    /// Two properties in one case because they are one behaviour: the latch is RUN-based, so a
    /// dip shorter than the release window changes nothing AND a dip that interrupts a pending
    /// release restarts it. An integrating latch would release on accumulated bad time and
    /// would drop a signal that is mostly fine.
    func testADipShorterThanTheReleaseWindowKeepsTheBody() {
        var latch = BioTrustLatch(engageSeconds: 3, releaseSeconds: 5)
        for t in stride(from: 0.0, through: 3.0, by: 1.0) { latch.step(trustworthy: true, now: t) }
        XCTAssertTrue(latch.isEngaged, "precondition: the latch must be engaged before the dip")

        for t in stride(from: 4.0, through: 7.0, by: 1.0) {          // 4 s of bad, needs 5
            XCTAssertTrue(latch.step(trustworthy: false, now: t), """
                released after \(t - 3) s of dropout; the window is 5 s. Releasing early is \
                what a flap IS — the reading comes back a moment later and the bus reopens.
                """)
        }
        XCTAssertTrue(latch.step(trustworthy: true, now: 8), "a recovering signal must stay engaged")
        // The pending release is now cancelled, so the NEXT bad run starts from scratch.
        for t in stride(from: 9.0, through: 12.0, by: 1.0) {
            XCTAssertTrue(latch.step(trustworthy: false, now: t), """
                released at t=\(t) — only \(t - 9) s into a FRESH bad run. The recovery at \
                t=8 must have cancelled the earlier pending release; if bad time accumulates \
                across a good sample the latch is an integrator, not hysteresis.
                """)
        }
        XCTAssertFalse(latch.step(trustworthy: false, now: 14), """
            did not release after a full 5 s of sustained dropout. The latch must let go — \
            holding forever would assert a body that is genuinely gone, which is the failure \
            `EngineBus.freshBio`'s whole existence is about.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT, END-TO-END) — the 6 s ceiling is untouched

    /// This cycle changed a DECISION, not a WINDOW, and this is where that is enforced. The
    /// tempting "fix" for the remaining flips is to widen the freshness window or the hold so
    /// a held frame outlives the dropout — which would make a stale reading look live to every
    /// consumer on the bus (synth, OSC, ADM-OSC, Art-Net, the visual). If either number moves,
    /// this goes red and says what the change actually costs.
    ///
    /// `@MainActor` on the method, following `CameraRPPGTrustTests`'s precedent exactly:
    /// `bioHoldTicks` is a `static let` on a `@MainActor` class, and Xcode's toolchain isolates
    /// such a property even though it is immutable (CLAUDE.md's build-error table records this
    /// — SwiftPM and Xcode disagree about SE-0434 inference, and the gate that matters here is
    /// Xcode's). Claims 1–3 touch only the pure latch and stay unisolated.
    ///
    /// ⚠️ THE THIRD ASSERTION HAS AN UNGATED TWIN and that is deliberate, not a #416 slip.
    /// `CameraRPPGTrustTests.testDropoutHoldFitsInsideTheCameraFreshnessWindow` makes the same
    /// hold < window comparison — but it lives in `Tests/EchoelmusicTests`, which NO gate
    /// compiles (#208), so the relation has never actually been enforced anywhere. This is the
    /// first place it runs. If #208 is fixed, delete one of the two rather than letting both
    /// drift.
    @MainActor
    func testTheStructuralCeilingIsUnchanged() {
        XCTAssertEqual(BioSource.cameraPPG.freshnessWindow, 6, accuracy: 1e-9, """
            The camera's freshness window moved. That number is the REAL ceiling on how long \
            `body=1` can survive a dropout, because the publisher's hold re-emits the last \
            good frame with its ORIGINAL timestamp. Widening it does not make the signal \
            better; it makes a stale reading indistinguishable from a live one for longer.
            """)
        let holdSeconds = Double(CameraRPPGBioPublisher.bioHoldTicks) / 10.0
        XCTAssertEqual(holdSeconds, 4, accuracy: 1e-9, """
            The dropout hold is now \(holdSeconds) s. It is deliberately SHORTER than every \
            consumer's freshness gate — the comment at its declaration says so — so that a \
            held frame expires by itself instead of a consumer having to expire it. #566 left \
            it alone on purpose: moving it from 4 s to 5 s would buy one second of an already \
            6-second-bounded window while changing the visual's bio↔idle behaviour, which no \
            test in this repo can verify.
            """)
        XCTAssertLessThan(holdSeconds, BioSource.cameraPPG.freshnessWindow, """
            The hold outlives the freshness window, so the publisher re-emits frames that \
            `usableBio()` has already discarded — work that reaches no consumer, and a hold \
            that silently stopped holding anything.
            """)
    }

    // MARK: - claim 5 (SOURCE SCAN) — the latch is actually in the publish path

    /// `shouldPublish`'s own doc block records the gap this closes for its sibling: "no test
    /// asserts that the publish loop actually CALLS this". The predicate was pinned and the
    /// wiring was not. A pure latch nobody steps is a doorless core, and this repo has a
    /// register full of those.
    func testTheLatchIsWiredIntoThePublishGate() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent(Self.publisher)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return XCTFail("""
                \(Self.publisher) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        let code = SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
        XCTAssertTrue(code.contains("BioTrustLatch()"), """
            The publisher no longer holds a `BioTrustLatch`. The type is pure and fully \
            tested above, which proves the LOGIC and nothing about the app — an unstepped \
            latch changes no behaviour at all.
            """)
        XCTAssertTrue(code.contains("bioTrust.step("), """
            Nothing steps the latch. A latch that is never fed stays disengaged forever, so \
            this failure means the camera path publishes NO bio at all — the loudest possible \
            regression and the one a source scan can actually see.
            """)
    }
}
