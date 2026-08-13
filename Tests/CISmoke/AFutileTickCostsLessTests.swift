// AFutileTickCostsLessTests.swift
// Echoel — #577. While iOS holds the camera, the publish loop stops waking up ten times a second.
//
// THE DEVICE EVIDENCE, same v10.79.388/2505 log as #576, same 220 s backgrounded stretch:
// **2 200 main-actor wake-ups to drain an empty queue.** Every one of those iterations is
// provably futile — the capture session is interrupted so nothing is queued, the analyzer is
// fed nothing, and the publish path bails one line in on
// `inboundRateEMA >= minMeasurableInboundHz`. #576 stopped that stretch from WRITING 140 log
// lines; this is the half that stops it from waking the main actor. At `heldTickSeconds` the
// same stretch costs 440 wake-ups.
//
// ⚠️ WHAT THIS DELIBERATELY DOES **NOT** DO, because it is the tempting bigger fix and it is
// the one that could lose bio silently: it does not stop the camera on backgrounding. That
// would be more correct (the session stays reserved today, so no other app can use the camera
// while Echoel is in the background) and it is registered as needing device verification —
// but a stop/restart pair that fails to restart is exactly the class of regression #566 cost
// two builds. Slowing a loop cannot lose a frame that iOS is not delivering.
//
// ⚠️ THE LIMIT, PER ASSERTION (§1): claims 1 and 4 are END-TO-END over two shipped `static
// let`s; claims 2–3 are SOURCE-TEXT SCANS, because the publish loop is a `private` `Task`
// inside a `@MainActor` class driving a real `AVCaptureSession` that no bundle can run.
// DEVICE PROBE, open and NOT covered: whether a backgrounded stretch actually costs less
// battery, and whether resume still feels immediate. That is the founder's next log.
//
// ⚠️ HONEST GRADING (§3), hand-transcribed in Python against the parent (`e9917a9`) and this
// tree — no local toolchain (§0). The file names two symbols this commit creates, so it does
// not compile against the parent and NO assertion has a verdict there; claims 1–3 are FORWARD
// guards, reported as such (#433), one absence reported once (#486). Claim 5 is the
// COUNTERWEIGHT and the reason the file exists beyond three positive scans.
//   · STRIPPER: **PROPHYLAKTISCH (0 of 4 flip)** — measured raw vs. stripped on both trees.

import Foundation
import XCTest
#if canImport(AVFoundation) && canImport(Observation)
@testable import Echoelmusic
#endif

final class AFutileTickCostsLessTests: XCTestCase {

    private static let publisherPath = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"

    #if canImport(AVFoundation) && canImport(Observation)

    // MARK: - claim 1 (END-TO-END) — the backoff is real, bounded, and the right way round

    /// Pinned as RELATIONS and CEILINGS, never as 0.1 and 0.5 (#364): both numbers are a
    /// judgement a later cycle may legitimately retune, and a guard that freezes them would be
    /// deleted along with the law it carries.
    func testTheHeldPeriodIsSlowerButStillResponsive() {
        XCTAssertGreaterThan(CameraRPPGBioPublisher.heldTickSeconds,
                             CameraRPPGBioPublisher.activeTickSeconds, """
            The held period is not slower than the active one, so the backoff saves nothing. \
            If the two were ever equal the whole change would be inert while still looking \
            present in source — the shape claims 2–3 cannot detect.
            """)
        XCTAssertGreaterThan(CameraRPPGBioPublisher.activeTickSeconds, 0, """
            A zero or negative active period would spin the main actor as fast as the runtime \
            allows — the opposite of this change, and a freeze rather than a saving.
            """)
        XCTAssertLessThanOrEqual(CameraRPPGBioPublisher.heldTickSeconds, 2.0, """
            The held period exceeds two seconds. Resume latency is bounded by this number, and \
            past a couple of seconds a returning user waits on the loop rather than on the \
            analyzer. The saving is already 5× at half a second; there is nothing to buy above \
            it and a real cost.
            """)
    }

    // MARK: - claim 4 (END-TO-END) — the rate maths and the period cannot drift apart

    /// The subtle one, and the reason `tickSeconds` is a variable rather than a branch at the
    /// `sleep`. `inboundRateEMA` was fed `count * 10.0`, where `10.0` is the reciprocal of a
    /// 100 ms period. Make the period variable and leave the literal, and a backed-off tick
    /// reports FIVE TIMES the frames it actually carried — into `inboundRateEMA`, which is
    /// what the publish gate and the stall watchdog both trust.
    func testTheActivePeriodIsStillTheReciprocalTheRateMathsAssumed() {
        XCTAssertEqual(1.0 / CameraRPPGBioPublisher.activeTickSeconds, 10.0, accuracy: 1e-9, """
            The active period is no longer 100 ms. That is allowed — but `inboundRateEMA`'s \
            old literal `* 10.0` was this reciprocal, and every `tick % N` constant in the \
            publish loop is expressed against it: `% 10` is the ~1 Hz publish, `% 20` the ~2 s \
            diagnostic, `stallTicks >= 60` the ~6 s watchdog. Changing it silently re-times \
            all four. If it moved on purpose, move those with it in the same commit.
            """)
    }

    #endif

    // MARK: - claim 2 (SOURCE SCAN) — the loop actually sleeps for the variable

    func testTheSleepFollowsTheVariablePeriod() throws {
        let src = try source(Self.publisherPath)
        XCTAssertTrue(src.contains("try? await Task.sleep(for: .milliseconds(Int(tickSeconds * 1000)))"), """
            The publish loop no longer sleeps for `tickSeconds`. With a literal back in place \
            the backoff is dead code: `tickSeconds` would still be assigned, still be read by \
            the rate maths, and change nothing — green on every other assertion here.
            """)
        XCTAssertTrue(src.contains("Double(drained.count) / tickSeconds * 0.1"), """
            The inbound-rate EMA no longer divides by the actual period. If the `* 10.0` \
            literal came back, a backed-off tick overstates the inbound flow fivefold on the \
            first tick after frames return — and `inboundRateEMA` is the publish gate's \
            freshness test.
            """)
    }

    // MARK: - claim 3 (SOURCE SCAN) — assigned before the early exits, and gated on both terms

    func testThePeriodIsChosenBeforeTheFirstEarlyExit() throws {
        let src = try source(Self.publisherPath)
        let assign = "tickSeconds = (self.heldQuiet && self.capture.isInterrupted)"
        XCTAssertEqual(src.components(separatedBy: assign).count - 1, 1, """
            The period is not chosen by the two-term test exactly once.
            BOTH terms are load-bearing and they fail differently. Without `heldQuiet` the loop \
            would back off during any interruption, including the first six seconds when the \
            ladder is still deciding. Without `isInterrupted` a REAL stall — the hold ends but \
            frames still do not arrive — would be diagnosed on a stretched ~30 s watchdog \
            instead of ~6 s, because `heldQuiet` only clears when frames RETURN.
            """)
        // Position, not just presence: after the stall ladder that owns `heldQuiet`, before
        // the first `continue`. At the bottom of the loop it would be skipped on every early
        // exit — and the early exits are the common path.
        guard let assignAt = src.range(of: assign)?.lowerBound,
              let exitAt = src.range(of: "guard self.inboundRateEMA >= Self.minMeasurableInboundHz")?.lowerBound,
              let ladderAt = src.range(of: "if !self.heldQuiet {")?.lowerBound else {
            XCTFail("one of the three anchors is gone — re-anchor this ordering scan (#454)")
            return
        }
        XCTAssertTrue(ladderAt < assignAt, """
            The period is chosen BEFORE the stall ladder sets `heldQuiet`, so it always reads \
            the previous tick's state and the backoff engages one iteration late for ever.
            """)
        XCTAssertTrue(assignAt < exitAt, """
            The period is chosen AFTER the first `continue` in the loop body. Every early exit \
            then skips it, so the loop keeps whatever period it had — and since the early exit \
            is the common path while nothing is arriving, the backoff would almost never take \
            effect. This ordering is the whole change; presence alone proves nothing.
            """)
    }

    // MARK: - claim 5 (COUNTERWEIGHT) — nothing was bought by doing less

    /// Green on both trees. Every assertion above is equally satisfied by a publisher that
    /// stopped draining, stopped feeding the analyzer, or stopped recovering — all of which
    /// would "save battery" and lose the instrument.
    func testTheLoopStillDrainsFeedsAndRecovers() throws {
        let src = try source(Self.publisherPath)
        for (needle, why) in [
            "let drained = self.sampleQueue.drain()": "the queue is no longer drained",
            "self.analyzer.processExtractedRGB(": "the analyzer is no longer fed",
            "self.capture.recoverFromStall()": "the real-stall recovery ladder is gone",
            "if self.capture.isInterrupted {": "the wait-instead-of-thrash branch is gone"
        ] {
            XCTAssertTrue(src.contains(needle), """
                \(why) — `\(needle)` is absent. #577 was allowed to change the loop's PERIOD \
                while iOS holds the camera, nothing else. A quieter loop that has stopped \
                measuring is not an optimisation.
                """)
        }
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct FutileAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw FutileAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
