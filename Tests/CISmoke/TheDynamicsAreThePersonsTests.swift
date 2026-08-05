// TheDynamicsAreThePersonsTests.swift
// Echoel — #403 Slice 3. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS PROTECTS. The founder's ask is that two people rendering the same preset do
// not get the same song. An inventory of every body read in the LIVE composer (2026-08-05,
// `scratchpads/PLAN_SIGNATURE_TILT_REMAINDER.md`) found exactly ONE quantity read as a
// magnitude rather than as a gate: the section velocity. Everything else — density, register,
// rhythm — is threshold-driven (`>= 0.5`, `> 0.6`, `> 0.62`, `> 0.68`, `> 0.7`, `> 0.82`,
// `darkness > 0.6`), which sorts performers into two or three buckets and is the opposite of
// individual.
//
// And that one continuous quantity was driven by coherence ALONE: `makeComposerInput` feeds
// `Input.breathDepth` the expression `0.3 + 0.5 * coherence`, not a measured breath. So two
// bodies at the same coherence played at identical velocities. This slice gives the person a
// say in it.
//
// ⚠️ WHAT THIS FILE CANNOT PROVE, said plainly because the epic's headline invites the
// opposite. It shows that two learned fingerprints produce DIFFERENT velocities and that an
// unlearned one changes nothing. Whether the difference is audible — let alone whether a take
// "sounds like you" — is a device listen, and no assertion here should be quoted as more.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheDynamicsAreThePersonsTests: XCTestCase {

    // MARK: - The golden law: an unlearned performer changes nothing

    func testAnUnlearnedSignatureContributesExactlyZero() {
        // The whole safety story of the epic, and the same one `SignatureIsThePersonNotTheMoment`
        // pins for the seed salt: a user who has never been measured must render bit-identically
        // to before the feature existed. Not "almost" — the tilt is exactly 0, and
        // `StudioCalculator.tilted` returns its input unchanged for a zero tilt.
        XCTAssertEqual(PerformerSignature.unknown.dynamicTilt, 0, """
            An unmeasured body now tilts the dynamics. Every take on every fresh install \
            changes, and the epic's one safety guarantee is gone.
            """)
    }

    func testAZeroTiltLeavesTheVelocityUntouched() {
        // The other half of the same guarantee, at the point of use rather than at the source:
        // even if a future signature returned 0 for a different reason, the composer's call
        // must be a no-op. `tilted` documents this ("a zero tilt returns its input"), and this
        // asserts the COMPOSER's window and value, not the function's own contract.
        for depth in stride(from: 0.0, through: 1.0, by: 0.05) {
            let plain = min(max(0.34 + 0.22 * depth, 0), 1)
            let tilted = StudioCalculator.tilted(plain,
                                                 within: BioComposer.padVelocityWindow,
                                                 by: 0)
            XCTAssertEqual(tilted, plain, accuracy: 1e-12, """
                A zero tilt moved the velocity at breathDepth \(depth).
                """)
        }
    }

    // MARK: - The tilt does what it is for

    func testTwoDifferentBodiesArePlayedAtDifferentLevels() {
        // The ask, reduced to the one thing a test can check: same preset, same moment, two
        // fingerprints ⇒ two velocities. Fixed `breathDepth` on purpose — the point is that
        // the PERSON differs while the MOMENT does not, which is the distinction that makes
        // the tilt legitimate rather than a second opinion about the same measurement.
        let moment = min(max(0.34 + 0.22 * 0.6, 0), 1)
        let quiet = StudioCalculator.tilted(moment, within: BioComposer.padVelocityWindow, by: -1)
        let strong = StudioCalculator.tilted(moment, within: BioComposer.padVelocityWindow, by: 1)
        XCTAssertNotEqual(quiet, strong, """
            Two opposite fingerprints produce the same velocity. The one continuous dimension \
            in the composer is back to being a function of coherence alone.
            """)
        XCTAssertLessThan(quiet, moment, "A negative tilt must play softer than the untilted take.")
        XCTAssertGreaterThan(strong, moment, "A positive tilt must play stronger.")
    }

    func testTheVelocityNeverLeavesItsWindow() {
        // ⚠️ SWEPT, NOT SAMPLED, and the reason is the same one `ThePaceIsTiltedInsideTheGenre`
        // gives: a refactor to "offset then clamp" passes every hand-written case and then
        // saturates a whole population onto the window's edge. The bound here is meant to be
        // STRUCTURAL — a fraction of the remaining headroom — so it must hold everywhere.
        let w = BioComposer.padVelocityWindow
        for depthStep in 0...20 {
            let depth = Double(depthStep) / 20
            let plain = min(max(0.34 + 0.22 * depth, 0), 1)
            for tiltStep in -10...10 {
                let tilt = Double(tiltStep) / 10
                let v = StudioCalculator.tilted(plain, within: w, by: tilt)
                XCTAssertGreaterThanOrEqual(v, w.lowerBound, """
                    Velocity \(v) fell below the window at depth \(depth), tilt \(tilt).
                    """)
                XCTAssertLessThanOrEqual(v, w.upperBound, """
                    Velocity \(v) rose above the window at depth \(depth), tilt \(tilt).
                    """)
            }
        }
    }

    // MARK: - The driver

    func testTheTiltRampsInInsteadOfLandingOnTheFirstSample() {
        // `blend` sets the mean OUTRIGHT from the first sample, so without the ramp one
        // artefact in the first take would move the dynamics of the whole session at full
        // magnitude. `tempoTilt` documents this at length; the copy must not drop it.
        var one = PerformerSignature.unknown
        one = one.observing(Self.frame(hrv: 0.7, at: Self.moment(0)))
        XCTAssertEqual(one.hrvCount, 1, """
            The frame was not accepted at all, so what follows would be asserting on an \
            unlearned signature rather than on the ramp.
            """)
        let first = abs(one.dynamicTilt)
        XCTAssertGreaterThan(first, 0, "One accepted HRV observation must start the tilt.")
        XCTAssertLessThan(first, 1, """
            A single observation already reaches full magnitude — the ramp is gone and one \
            artefact owns the dynamics of the session.
            """)
    }

    func testBothEndsOfTheSpanSaturateRatherThanRunAway() {
        // A position among people, not a clinical number — the same honest behaviour
        // `habitualSpan` chose for the heart. Outside the span the tilt stops moving; it does
        // not keep growing and it never leaves −1…1.
        var low = PerformerSignature.unknown
        var high = PerformerSignature.unknown
        for n in 0..<PerformerSignature.confidentAfter {
            low = low.observing(Self.frame(hrv: 0.01, at: Self.moment(n)))
            high = high.observing(Self.frame(hrv: 0.99, at: Self.moment(n)))
        }
        XCTAssertEqual(low.hrvCount, PerformerSignature.confidentAfter, """
            Not every frame was accepted — the rate limit or the timestamp guard swallowed \
            some, so this is not the fully-ramped case it claims to test.
            """)
        XCTAssertGreaterThanOrEqual(low.dynamicTilt, -1)
        XCTAssertLessThanOrEqual(high.dynamicTilt, 1)
        XCTAssertLessThan(low.dynamicTilt, 0, "A habitually low-variability body tilts down.")
        XCTAssertGreaterThan(high.dynamicTilt, 0, "A habitually high-variability body tilts up.")
    }

    // MARK: - The wiring

    func testTheComposerAsksTheSignatureForIt() throws {
        // A pure core with no caller is the same defect with more steps — the lesson this repo
        // has already paid for. Two halves: the composer's velocity site must READ the tilt,
        // and the app must SUPPLY it from the signature.
        //
        // ⚠️ BOTH SCANS STRIP COMMENTS FIRST (the #367 trap). Neither doc block quotes these
        // exact strings TODAY, so this changes nothing today — and that is precisely when it
        // is worth doing, because the failure mode is silent: a later session that deletes the
        // call and explains the deletion in prose containing the same phrase leaves this guard
        // green over the removed feature. A source scan must look at code, not at the file.
        let composer = Self.codeOnly(try Self.read("Sources/Echoelmusic/Sequencer/BioComposer.swift"))
        XCTAssertTrue(composer.contains("within: Self.padVelocityWindow"), """
            The pad velocity no longer goes through the tilt. The one continuous body-driven \
            quantity is a function of coherence alone again.
            """)
        let studio = Self.codeOnly(try Self.read("Sources/Echoelmusic/Studio/EchoelStudioView.swift"))
        XCTAssertTrue(studio.contains("signatureDynamicTilt: performerSignature.dynamicTilt"), """
            The composer input no longer carries the performer's dynamic tilt, so the field \
            defaults to 0 and the feature is silently off.
            """)
    }

    // MARK: - Helpers

    /// ⚠️ THE TIMESTAMP IS NOT DECORATION, and the first version of this file got it wrong in
    /// a way that would have made the blocking bundle green on a broken premise rather than
    /// red: it passed `0` for every frame. `observing` guards `now > 0` (a frame with no
    /// usable timestamp teaches nothing) and enforces `minimumObservationInterval` = 30 s
    /// between accepted observations, so eight frames at t=0 fold in ZERO of them and
    /// `hrvCount` stays 0 — the ramp tests would have been asserting on `unknown`. Callers
    /// here therefore space their frames by `PerformerSignature.minimumObservationInterval`.
    ///
    /// `.cameraPPG` because `mayTeach` refuses `.fallback` (the simulator): a demo session
    /// must not write the PERSON's handwriting. The channel under test is HRV, so the frame
    /// carries a heart rate too — that is what a real rPPG frame looks like, and it keeps
    /// this file honest about which count the ramp actually reads.
    private static func frame(hrv: Float, at t: TimeInterval) -> BioSampleFrame {
        BioSampleFrame(timestamp: t,
                       heartRateBPM: 70,
                       hrvNormalized: hrv,
                       breathRate: 0,
                       breathPhase: 0.25,
                       coherence: 0.5,
                       motionEnergy: 0,
                       source: .cameraPPG)
    }

    /// The nth accepted observation time — `observing` needs strictly increasing timestamps
    /// at least `minimumObservationInterval` apart, and `> 0` for the first one.
    private static func moment(_ n: Int) -> TimeInterval {
        PerformerSignature.minimumObservationInterval * TimeInterval(n + 1)
    }

    /// Everything before the first `//` on each line. Crude on purpose — a string literal
    /// containing `//` would be truncated — and adequate here, because both scans look for
    /// Swift argument labels that never appear inside a literal in these two files.
    private static func codeOnly(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            guard let slashes = line.range(of: "//") else { return String(line) }
            return String(line[line.startIndex..<slashes.lowerBound])
        }.joined(separator: "\n")
    }

    private static func read(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(relativePath) not reachable from \(#filePath) — tree not co-located.")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
