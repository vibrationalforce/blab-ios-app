// SmoothingStepsTheFrameGapNotThePollRateTests.swift
// Echoel — #336. A one-pole slew must be advanced by the time that actually passed between the
// two readings it slews between, not by the rate its poll happens to fire at. BLOCKING.
//
// ⭐ THE DEFECT, AND WHY IT IS THE THIRD OF ITS KIND. `ModulationEngine` fed
// `BioNormalizer.alpha` a constant `tickSeconds = 0.1`, documented as "matches the 100 ms
// polling loop". The poll IS 100 ms. The SMOOTHING is not advanced by the poll: `tick` returns
// early unless `frame.timestamp` changed, and every wired publisher sends at ~1 Hz — a fact
// CLAUDE.md states and `BioApplyRateIsTheDedupedRateTests` guards in this same bundle. So each
// `alpha` step covered about a second of wall clock while claiming a tenth of one, and a route
// asking for a 2 s slew took roughly 20 s to get there. Same family as #315 (60 Hz assumed,
// ~1 Hz delivered) and #332 (two one-poles, two constants). **Ten times is not a tuning
// difference; it is the difference between a slew and a fade-in nobody waits for.**
//
// ⭐ THE FIX IS STRUCTURAL, WHICH IS THE POINT (#337). The gap is measured from the two frames
// themselves — `BioSampleFrame.timestamp` already carries it. No clock is read, so the result is
// deterministic and drivable here; a `Date()` would have been both untestable AND wrong in a
// second way, because it would have made the slew depend on how long the main actor was busy.
//
// ⛔ HONEST LIMITS, and the first one decides how much this file may claim:
//   · **NO SHIPPED ROUTE IS SMOOTHED TODAY.** `ModRoute.smoothingTau` defaults to 0, the default
//     matrix is empty, and no writer outside the model exists in `Sources/`. So the branch this
//     guards is unreachable in the shipped app and the change is audibly a no-op. It is worth
//     guarding because #136 exists to give `ModRoute` a UI, and on the day that lands every slew
//     a user dials would otherwise have been ten times too slow with nothing on screen to say so.
//     Read a pass as "the arithmetic is right and wired", never as "a user heard it".
//   · The behavioural half drives `apply(_:)` directly, which is what the engine's own doc says
//     it is exposed for. It does NOT prove the polling loop delivers frames at the rate assumed
//     — that is the neighbouring guard's job, and duplicating it here would be a second opinion
//     that can drift from the first.

import Foundation
import XCTest
@testable import Echoelmusic

@MainActor
final class SmoothingStepsTheFrameGapNotThePollRateTests: XCTestCase {

    // MARK: - The pure gap

    /// The headline: a normal ~1 Hz cadence must be measured as ~1 s, not as the old 0.1.
    func testAnOrdinaryFrameGapIsMeasuredNotAssumed() {
        let gap = ModulationEngine.smoothingGap(previous: 1_000, current: 1_001)
        XCTAssertEqual(gap, 1.0, accuracy: 1e-6, """
        the smoothing gap is no longer read from the frames (#336).

        It got \(gap) s for two frames a second apart. 0.1 would be the shipped defect — the poll \
        interval standing in for the publisher cadence, which made every slew ten times too slow.
        """)
    }

    /// No previous frame is not a zero-length gap. Zero would drive `alpha` to 0 and freeze every
    /// smoothed route at its seed — a silence-shaped failure that reads as "never wired".
    func testTheFirstFrameFallsBackToTheNominalPeriodNotToZero() {
        let gap = ModulationEngine.smoothingGap(previous: -1, current: 5_000)
        XCTAssertEqual(gap, ModulationEngine.nominalFramePeriod, accuracy: 1e-6)
        XCTAssertGreaterThan(gap, 0, "a zero gap makes alpha 0 and freezes the route at its seed")
    }

    /// A backwards or duplicate timestamp degrades to the nominal period. `timestamp` is
    /// wall-clock derived and `Date()` does not advance monotonically.
    func testABackwardsOrDuplicateStampDoesNotProduceANonPositiveGap() {
        for (prev, now) in [(1_000.0, 999.0), (1_000.0, 1_000.0)] {
            let gap = ModulationEngine.smoothingGap(previous: prev, current: now)
            XCTAssertEqual(gap, ModulationEngine.nominalFramePeriod, accuracy: 1e-6,
                           "previous=\(prev) current=\(now) produced \(gap)")
        }
    }

    /// ⛔ THE CAP IS NOT BELT-AND-BRACES — #398 is why. Sanitising only NaN/±inf leaves a large
    /// FINITE gap intact, and an NTP or timezone step makes one reachable. That is the exact
    /// species of input that stalled the evolve loop for an hour there.
    func testAnEnormousFiniteGapIsCappedRatherThanObeyed() {
        let gap = ModulationEngine.smoothingGap(previous: 0, current: 3_600)
        XCTAssertEqual(gap, ModulationEngine.maxSmoothingGap, accuracy: 1e-6, """
        a one-hour clock step is being handed to `alpha` verbatim (#336/#398).

        It is bounded in effect — `alpha` clamps to 1 — but an unbounded number deciding a slew \
        is the shape of the bug, not its magnitude. Beyond the cap the previous value is history, \
        not a neighbour to slew from, so snapping to the new reading is the correct behaviour.
        """)
    }

    /// Non-finite at the boundary is an edge case in this repo, not an impossibility.
    func testNonFiniteStampsCannotProduceANonFiniteGap() {
        for prev in [Double.nan, .infinity, -.infinity, -1] {
            for now in [Double.nan, .infinity, -.infinity, 1_000] {
                let gap = ModulationEngine.smoothingGap(previous: prev, current: now)
                XCTAssertTrue(gap.isFinite, "previous=\(prev) current=\(now) → \(gap)")
                XCTAssertGreaterThan(gap, 0)
                XCTAssertLessThanOrEqual(gap, ModulationEngine.maxSmoothingGap)
            }
        }
    }

    // MARK: - It reaches a real slew

    /// ⭐ THE ONE THAT MAKES THE PURE FUNCTION WORTH HAVING. A correct core with no caller is the
    /// same defect with more steps. Two frames one second apart, a route asking for a 1 s slew:
    /// the output must land near the halfway point (`alpha = dt/(tau+dt) = 0.5`). Under the
    /// shipped constant it would have moved by 0.1/1.1 ≈ 9 %, which this asserts against by name.
    func testASecondApartFrameMovesASecondsWorthOfSlew() {
        let engine = Self.engine(tau: 1.0)
        engine.apply(Self.frame(at: 1_000, coherence: 0))   // seeds at 0
        engine.apply(Self.frame(at: 1_001, coherence: 1))   // one second later, full step
        let value = engine.lastOutputs[ModDestination(ModDestinationKey.tempo)] ?? 0
        XCTAssertEqual(value, 0.5, accuracy: 0.02, """
        the slew is not stepping with the measured gap (#336).

        Got \(value) after one second of a 1 s time constant. ~0.09 is the shipped defect (the \
        0.1 s poll interval used as dt); ~1.0 would mean the smoothing was skipped entirely.
        """)
    }

    /// The mirror: a route with `smoothingTau == 0` must remain bit-identical to the unsmoothed
    /// path, whatever the gap is. This is the property that keeps the change a no-op for every
    /// route that ships today.
    func testAnUnsmoothedRouteIsUntouchedByTheGap() {
        for gapSeconds in [0.1, 1.0, 60.0] {
            let engine = Self.engine(tau: 0)
            engine.apply(Self.frame(at: 1_000, coherence: 0.3))
            engine.apply(Self.frame(at: 1_000 + gapSeconds, coherence: 0.8))
            let value = engine.lastOutputs[ModDestination(ModDestinationKey.tempo)] ?? 0
            XCTAssertEqual(value, 0.8, accuracy: 1e-5,
                           "gap \(gapSeconds) s changed an UNSMOOTHED route's output to \(value)")
        }
    }

    /// `stop()` must forget the gap along with the smoothing state. Left standing, the first
    /// frame after a ten-minute pause would be measured against the far side of the pause — the
    /// same "one variable, two facts" defect `RegenSchedule` was extracted for in #398.
    func testStopForgetsTheGapAndNotOnlyTheSmoothedValue() {
        let engine = Self.engine(tau: 1.0)
        engine.apply(Self.frame(at: 1_000, coherence: 0))
        engine.stop()
        // A frame from far in the future. If the gap survived `stop`, this would be measured as
        // a (capped) 5 s jump; because it does not, the route re-seeds and reports its raw value.
        engine.apply(Self.frame(at: 2_000, coherence: 1))
        let value = engine.lastOutputs[ModDestination(ModDestinationKey.tempo)] ?? 0
        XCTAssertEqual(value, 1.0, accuracy: 1e-5, """
        `stop()` no longer clears the smoothing gap (#336). The route re-seeds at its first value \
        after a stop, so the first frame back must report that value, not a slew from one.
        """)
    }

    // MARK: - The wiring (scan)

    /// A source scan for the ABSENCE of the old shape, because the behavioural cases above pass
    /// as soon as the arithmetic is right — they cannot tell that no OTHER site still hands a
    /// poll constant to `alpha`.
    ///
    /// ⚠️ Follows the BINDING, not the physical line (the #413 lesson): the assertion is that no
    /// `alpha(` call in this file mentions a tick/poll constant, whichever line it sits on.
    func testNoPollConstantIsHandedToTheSmoothingAlpha() throws {
        let lines = try codeLines("Sources/Echoelmusic/Core/ModulationEngine.swift")
        let alphaCalls = lines.filter { $0.contains("BioNormalizer.alpha(") }
        XCTAssertEqual(alphaCalls.count, 1,
                       "expected exactly one smoothing `alpha` call, found \(alphaCalls.count)")
        for call in alphaCalls {
            XCTAssertFalse(call.contains("tickSeconds") || call.contains("pollInterval"), """
            the smoothing alpha is being fed a poll constant again (#336).

            The line found was:
            \(call)

            The poll rate and the frame cadence are two different facts; `smoothingGap` measures \
            the second one from the frames.
            """)
        }
        XCTAssertTrue(lines.contains { $0.contains("Self.smoothingGap(previous:") }, """
        `apply` no longer measures the gap. A correct `smoothingGap` with no caller is the same \
        defect with extra steps — the exact failure #403 Slice 0 is filed for in CLAUDE.md.
        """)
    }

    // MARK: - Fixtures

    /// One route, coherence → tempo, so the only variable in a case is the gap and the tau.
    private static func engine(tau: Float) -> ModulationEngine {
        let suite = UserDefaults(suiteName: "SmoothingGapTests-\(UUID().uuidString)")!
        let route = ModRoute(source: .coherence,
                             destination: ModDestination(ModDestinationKey.tempo),
                             smoothingTau: tau)
        return ModulationEngine(matrix: ModulationMatrix(routes: [route]), defaults: suite)
    }

    /// A frame whose ONLY moving part is `coherence` (the route's source) and `timestamp`.
    /// `hrvNormalized` is deliberately non-zero: 0 means "not measured" on this bus and a future
    /// guard could legitimately start skipping such frames.
    private static func frame(at t: TimeInterval, coherence: Float) -> BioSampleFrame {
        BioSampleFrame(timestamp: t, heartRateBPM: 70, hrvNormalized: 0.5,
                       breathRate: 6, breathPhase: 0.25, coherence: coherence,
                       motionEnergy: 0, source: .cameraPPG)
    }

    /// Non-empty lines with comments removed — DEFENSIVE, not load-bearing: the doc block above
    /// `smoothingGap` names `tickSeconds` verbatim while explaining why it is gone, so a scan
    /// that kept comments would fail on the very prose that documents the fix.
    private func codeLines(_ path: String) throws -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("source tree not present — this scan cannot report a green")
        }
        let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        var out: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if let r = line.range(of: "//") {
                let before = line[line.startIndex..<r.lowerBound]
                if before.filter({ $0 == "\"" }).count % 2 == 0 { line = String(before) }
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { out.append(trimmed) }
        }
        return out
    }
}
