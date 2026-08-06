// TheGapClimbCannotChangeTheResumeTests.swift
// Echoel — #444. The guard over a registered fix that turned out to be a no-op.
//
// WHAT #434 LEFT BEHIND. `BreathHold` fades the influence of a held breath rate instead of
// dropping it in one step. Its own header registered one artifact as a follow-up slice, in these
// words: "`up` may climb while a gap is still open, so a PERIODICALLY flickering source produces
// a smooth triangle rather than a decaying envelope … Freezing `up` outside the grace window is
// the candidate fix."
//
// ⛔ THE ARTIFACT IS REAL. THE NAMED FIX IS PROVABLY INERT — it changes nothing, on any input,
// ever. That matters more than the artifact does, because this repo's own law (#167) is that a
// "do X instead" note with a wrong justification is worse than no note: the next session cannot
// argue with it, it just implements it and measures nothing.
//
//   The proof is three lines. A restart needs `now − lastMeasuredAt > graceSeconds`, and
//   `graceSeconds == horizon / 2 == half`. `runStartedAt` is only ever ADVANCED at a measurement,
//   and the one other assignment — the backwards-clock `self = BreathHold()` — sets it and
//   `lastMeasuredAt` to −∞ TOGETHER, so `runStartedAt <= lastMeasuredAt` survives both. Therefore
//   at any restart `elapsed = now − runStartedAt >= now − lastMeasuredAt > half`, so
//   `up = resumeWeight + elapsed / half > 0 + 1 = 1`, so `min(up, down) == down`. Freezing `up` at
//   `lastMeasuredAt + half` gives `elapsed >= half`, hence `up >= 1` — the SAME branch of the
//   `min`. And between restarts the freeze is inactive by construction, because inside grace
//   `now <= lastMeasuredAt + half` already.
//   (⚠️ "at any restart" is VACUOUS in exactly one case, which the first draft asserted as if it
//   were true there: at the FIRST measurement `horizon` is still 0, so `weight(at:)` returns at
//   its `horizon > 0` guard and `up` is never formed at all. The no-op conclusion is stronger
//   there, not weaker — both variants return 0 — but a proof text in this repo gets implemented
//   without being re-derived, so the gap is named rather than smoothed over.)
//
//   Measured as well as argued, because an algebraic claim about shipped code is still a claim:
//   6 000 randomised traces (bursts of 1–5 measurements separated by gaps drawn to straddle
//   `half`, over the windows 5 s / 6 s / 90 s) produced **61 769 restarts**, and the largest
//   difference between today's weight and the frozen variant over every sample of every trace was
//   **exactly 0**.
//   (⛔ That sweep also reported "the smallest `up` seen at a restart" — 1.000224 — and the first
//   draft quoted it here as though it were a MARGIN. It is a statistic about the random number
//   generator, not about this code. The restart test is a STRICT inequality, so the infimum of
//   `up` at a restart is exactly 1 and is never attained: a denser sweep reports a smaller number
//   for ever, and the number therefore says nothing. The theorem above is what carries the claim.)
//   (⚠️ Coverage: `BioSource.freshnessWindow` declares FOUR distinct values across six cases —
//   6 s, 90 s, 600 s (`.oura`), 5 s. The sweep drove the three that have a producer in `Sources/`
//   today. `half` cancels out of the restart comparison, so the window the sweep skipped is a
//   coverage note rather than a hole in the proof.)
//
// ⭐ SO WHAT IS THE TRIANGLE, THEN? ATTACK RATE == RELEASE RATE — and nothing in `BreathHold`
// ever decided that. `down` falls at `1/half`; `up` climbed at `elapsed / half`, i.e. also
// `1/half`, purely because `up` reused `half` as its divisor. The header of `BreathHold.swift`
// derives the SPLIT (grace = release = horizon/2, chained to `BioSource.freshnessWindow`); it
// never derived the ATTACK, which arrived as a side effect of the constant chosen for the expiry
// side.
//
// ⛔ THAT SLICE HAS LANDED (#448) AND THIS PARAGRAPH STOOD IN THE PRESENT TENSE AFTERWARDS —
// in the BLOCKING bundle, describing a pending slice that is done. `attackSeconds` is now
// `min(releaseSeconds, maximumAttack)` with `maximumAttack = 3.0`, so attack == release only for
// windows of 6 s or less. **Every assertion in THIS file is unaffected and measures exactly what
// it measured**, because every one of them drives `cameraWindow` (6 s), where `min(3, 3) = 3`;
// that bit-identity is asserted directly in `TheWristReadingIsNotUnderweightedTests`. The
// symmetric triangle below is therefore still the camera/BLE shape. On the WRIST it is now a
// sawtooth, and the artifact that creates is measured in the `BreathHold` header, not here.
//   ⛔ And the obvious-looking version of that slice — a decaying envelope, so a source that keeps
//   dropping out earns less trust each time — is rejected, not merely deferred. It fails on the
//   ground #433 used to delete the fabricated calm: the bus still trusts the frame, so lowering
//   its influence invents a distrust nothing measured, and on a recorded lane the result is
//   indistinguishable from a body that actually breathed less regularly. It would also make the
//   weight depend on history the caller cannot see, so two identical bodies read differently.
//   `testTheRampRateDoesNotRememberEarlierDropouts` is the counterweight that makes such a change
//   a deliberate red test rather than a silent side effect of a later tidy-up.
//
// ⚠️ WHICH OF THESE CAN ACTUALLY FAIL, stated up front because #367 is a law about a test's
// self-description too:
//   · `testEveryResumePointIsContinuous` is the reddenable one. It is the SWEPT form of
//     `TheBreathTermFadesInsteadOfStepping.testResumingMidReleaseDoesNotStep`, which pins the
//     same property at exactly one point (mid-release, 0.5). That is not a second copy of a live
//     claim (#416) — it is the generalisation, and it exists because the failure it guards
//     against is a REFACTOR of the resume rule, which a single hand-picked point survives. The
//     naive `resumeWeight = 1` turns it red at every sample in the release window.
//   · `testAFlickeringSourceTracesASymmetricTriangle` is red on any change to the fade shape —
//     but only since the trough assertion was fixed to measure past the horizon. As first
//     written it read `weights.min()` over the WHOLE trace, which the cold-start sample pins at
//     0 regardless of the fade, so a floored `down` (the exact defect its message describes)
//     left it green. See the ⛔ block at the assertion.
//   · `testTheRampRateDoesNotRememberEarlierDropouts` is GREEN on today's code and is meant to
//     be. Its job is the envelope policy above.
//
// ⚠️ AND THE LIMIT #434 AND #433 BOTH STATE, WHICH THIS FILE INHERITS UNCHANGED: nothing here
// proves any of it is heard or recorded. `RecordController.onStep` opens with
// `guard armed else { return }`, `arm()` has zero callers in `Sources/`, and #204 records the
// controller as doorless.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheGapClimbCannotChangeTheResumeTests: XCTestCase {

    private let paced = 6.0
    private let cameraWindow = BioSource.cameraPPG.freshnessWindow

    /// A hold brought to full weight the way a run of shipped ~1 Hz frames would, ending at
    /// `t = 9`.
    private func warmedHold() -> BreathHold {
        var hold = BreathHold()
        for i in 0..<10 { hold.observe(measured: paced, at: Double(i), usableFor: cameraWindow) }
        return hold
    }

    // MARK: - The reddenable one

    /// ⭐ SWEPT, NOT SAMPLED, and that is the whole point of the file.
    ///
    /// A returning measurement must resume the climb from the weight already held — at EVERY
    /// instant it could return, not at the one instant a hand-written test picked. The three
    /// regimes are all in the sweep on purpose: inside grace (nothing has decayed yet), inside
    /// the release (the interesting middle), and past the horizon (the held rate has fully
    /// expired and the correct resume is 0, not 1).
    func testEveryResumePointIsContinuous() {
        var worst = 0.0
        var worstAt = 0.0
        var checked = 0

        var offset = 0.05
        while offset <= 8.0 + 1e-9 {
            var hold = warmedHold()
            let at = 9.0 + offset
            let before = hold.weight(at: at)
            hold.observe(measured: paced, at: at, usableFor: cameraWindow)
            let after = hold.weight(at: at)
            let step = abs(after - before)
            if step > worst { worst = step; worstAt = offset }
            checked += 1
            offset += 0.05
        }

        XCTAssertGreaterThan(checked, 150, """
            Only \(checked) resume points were swept — the loop stopped early, so a green result \
            here says nothing about the population it claims to cover.
            """)
        XCTAssertEqual(worst, 0, accuracy: 1e-12, """
            Re-acquisition stepped the weight by \(worst) at a gap of \(worstAt) s. A returning \
            measurement must resume from the weight already held; snapping to 1 puts the #433 \
            step back on the re-acquisition edge, where no dropout test would ever see it.
            """)
    }

    // MARK: - What the artifact actually is

    /// The shape #434 registered, MEASURED. A source that emits one measurement every 7 s — a
    /// period longer than the 6 s camera horizon, so the weight fully expires between them —
    /// traces a triangle: up at `1/releaseSeconds`, down at `1/releaseSeconds`, peak 1, trough 0.
    ///
    /// The peaks reaching 1 are not a fault on their own: each of those measurements IS fresh,
    /// and full weight for a fresh measurement is the honest answer. What the registered slice
    /// was worried about is the resulting oscillation sitting in the breathing band — 7 s is
    /// 0.14 Hz — on a recorded lane, where it is harder to recognise as an artifact than the
    /// square wave it replaced. That worry is unchanged by this file; only the proposed fix is
    /// withdrawn.
    func testAFlickeringSourceTracesASymmetricTriangle() {
        var hold = BreathHold()
        var samples: [(t: Double, w: Double)] = []

        var t = 0.0
        while t <= 21.0 + 1e-9 {
            // A measurement every 7 s, sampled every 0.5 s.
            if abs(t.rounded() - t) < 1e-9, Int(t.rounded()) % 7 == 0 {
                hold.observe(measured: paced, at: t, usableFor: cameraWindow)
            }
            samples.append((t: t, w: hold.weight(at: t)))
            t += 0.5
        }

        let weights = samples.map { $0.w }
        let peak = weights.max() ?? -1

        // ⛔ THE TROUGH IS MEASURED FROM `t >= horizon`, NOT OVER THE WHOLE TRACE, and the
        // first draft got that wrong in a way its own message denied. `weights.min()` includes
        // `t = 0`, where the weight is 0 by COLD-START construction — the first measurement
        // takes the restart branch while `horizon` is still 0, so `weight(at:)` returns at its
        // `horizon > 0` guard. That one sample pinned the minimum at 0 forever, and the
        // assertion could not fail for the property it names. A reviewer proved it by flooring
        // `down` at 0.2 — the "rate stays alive past expiry" defect this message describes —
        // and the assertion stayed green; only the fall-slope check went red, i.e. the bug was
        // caught incidentally by a different claim. #367 in its quietest form: not a guard that
        // cannot fail, but a guard that cannot fail FOR ITS STATED REASON.
        let expired = samples.filter { $0.t >= hold.graceSeconds + hold.releaseSeconds }
        let trough = expired.map { $0.w }.min() ?? -1
        XCTAssertGreaterThan(expired.count, 20, """
            Only \(expired.count) samples fall past the horizon, so the trough below is measured \
            on too little of the expiry region to mean anything.
            """)
        // ⚠️ THE PEAK IS A CUSP, AND THIS ASSERTION ALSO DEPENDS ON THE SAMPLE GRID — said here
        // because the next person to change a number in the loop above needs it. After the
        // measurement at t = 7 the run restarts with `resumeWeight == 0`, so `up = elapsed / 3`
        // reaches 1 at exactly t = 10, which is the same instant `down` starts falling (`age`
        // hits `half`). Full weight is touched for ONE INSTANT, not held. The 0.5 s step happens
        // to land on t = 10.0; a step that misses the cusp (0.7 s, say) would report a peak below
        // 1 with the code completely unchanged. So this is a claim about the shape AND about the
        // grid — it is not "the weight spends time at 1".
        XCTAssertEqual(peak, 1, accuracy: 1e-12, """
            The flicker peak is \(peak), not 1. Every one of those measurements is fresh, so a \
            peak below full weight means re-acquisition is being penalised — which is the \
            envelope policy this file says is NOT in the code. (If you changed the 0.5 s sample \
            step, check the cusp note above first: the peak is an instant, not a plateau.)
            """)
        XCTAssertEqual(trough, 0, accuracy: 1e-12, """
            The flicker trough is \(trough), not 0. A gap longer than the source's own freshness \
            window must retire the held rate completely; anything above 0 keeps a rate alive \
            past the point the bus trusts the frame it came from.
            """)

        // Symmetry: rise and fall must both travel 1 / releaseSeconds per second.
        let release = hold.releaseSeconds
        XCTAssertEqual(release, cameraWindow * 0.5, accuracy: 1e-12, """
            The release window is \(release) s, not half the camera window — the slopes below \
            are then measured against the wrong horizon.
            """)

        let rise = slope(samples, from: 7.5, to: 9.5)
        let fall = slope(samples, from: 11.0, to: 13.0)
        XCTAssertEqual(rise, 1.0 / release, accuracy: 1e-9, """
            The rise slope is \(rise) per second, not \(1.0 / release). The ramp no longer \
            matches the fade, so the shape is not the triangle this file documents.
            """)
        XCTAssertEqual(fall, -1.0 / release, accuracy: 1e-9, """
            The fall slope is \(fall) per second, not \(-1.0 / release). Same reason.
            """)
    }

    private func slope(_ samples: [(t: Double, w: Double)], from: Double, to: Double) -> Double {
        var a: (t: Double, w: Double)?
        var b: (t: Double, w: Double)?
        for s in samples {
            if abs(s.t - from) < 1e-9 { a = s }
            if abs(s.t - to) < 1e-9 { b = s }
        }
        guard let lo = a, let hi = b, hi.t > lo.t else { return .nan }
        return (hi.w - lo.w) / (hi.t - lo.t)
    }

    // MARK: - The counterweight

    /// ⭐ GREEN TODAY, AND THAT IS ITS JOB. The re-acquisition ramp is memoryless: it climbs at
    /// `1/attackSeconds` from whatever weight was held, no matter how many dropouts came before.
    /// (It read `1/releaseSeconds` until #448 split the two; on this file's camera window the two
    /// are the same number, so the measurement is unchanged — only the name of the rate is.)
    /// A "decaying envelope" policy — the thing the #434 note wished for — is exactly a change to
    /// this property, so it should have to turn a test red on the way in rather than arriving as
    /// a side effect of a fade tweak.
    func testTheRampRateDoesNotRememberEarlierDropouts() {
        // One dropout, resumed mid-release.
        var once = warmedHold()
        let resume = 9.0 + once.graceSeconds + once.releaseSeconds / 2
        once.observe(measured: paced, at: resume, usableFor: cameraWindow)

        // Three dropouts, each resumed and re-warmed, ending at the same held weight.
        var thrice = warmedHold()
        var clock = 9.0
        for _ in 0..<3 {
            let back = clock + thrice.graceSeconds + thrice.releaseSeconds / 2
            thrice.observe(measured: paced, at: back, usableFor: cameraWindow)
            // Re-warm to full weight at the shipped cadence.
            clock = back
            for _ in 0..<6 {
                clock += 1.0
                thrice.observe(measured: paced, at: clock, usableFor: cameraWindow)
            }
        }
        let lastResume = clock + thrice.graceSeconds + thrice.releaseSeconds / 2
        thrice.observe(measured: paced, at: lastResume, usableFor: cameraWindow)

        XCTAssertEqual(once.weight(at: resume), thrice.weight(at: lastResume), accuracy: 1e-12, """
            The two holds resumed at different weights (\(once.weight(at: resume)) vs \
            \(thrice.weight(at: lastResume))), so the comparison below is not about the ramp.
            """)

        for step in stride(from: 0.5, through: 2.5, by: 0.5) {
            let a = once.weight(at: resume + step)
            let b = thrice.weight(at: lastResume + step)
            XCTAssertEqual(a, b, accuracy: 1e-12, """
                \(step) s after re-acquisition the once-dropped hold reads \(a) and the \
                thrice-dropped one \(b). The ramp has grown a memory of earlier dropouts — that \
                is the envelope policy, and it is a founder-visible behaviour change, not a \
                fade tweak.
                """)
        }
    }
}
