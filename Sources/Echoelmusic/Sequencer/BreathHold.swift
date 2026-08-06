// BreathHold.swift
// Echoel — #434. The state `bioNormalized` deliberately does not have.
//
// WHAT THIS IS FOR. `bioNormalized` (Sequencer/RecordAnchor.swift) blends a heart term and a
// breath term into ONE arousal value for a bio automation lane. Since #433 it drops the breath
// term entirely when there is no measurement — correct, because a BLE-strap frame carries
// `breathRate: 0` and folding that in as calm was a fabricated number (#215's argument, one
// path over).
//
// ⚠️ AND #433 PAID FOR THAT WITH A STEP, measured by its reviewer and written into its own doc
// rather than hidden: the value now JUMPS by |hr − br| / 2 the instant a measurement appears or
// vanishes. At 120 bpm and the paced 6/min resonance rate that is **0.4286**, i.e. 43 % of the
// lane's range. The dropout is real: `CameraRPPGBioPublisher` gates breath on a hard
// `confidence >= 0.4` and its pulse-HOLD republish zeroes `breathRate` outright.
//
// ⛔ THAT 0.4286 IS NOT THE WORST CASE AND IS NOT "worst at the rate the product aims at" — the
// first draft of this file claimed both, in four places at once. The step is |hr − br| / 2, so
// its maximum is **0.5**, reached when the two normalised terms sit on opposite rails (50 bpm
// with ≥24/min, or 120 bpm with ≤3/min). And 120 bpm normally comes with 18–24/min, where the
// step is 0.143 → 0.000; paced 6/min breathing normally comes with 55–75 bpm, where it is
// 0.036–0.107. 0.4286 is a corner a body rarely occupies. It stays as the headline because it
// is the number the fix is measured against, not because it is typical.
//
// ⭐ THE FIX IS HOLDING, NOT SMOOTHING, and #433's doc already said so before this file existed.
// Low-passing the arousal value would invent intermediate arousal no body produced. Holding the
// last MEASURED breath rate and fading its INFLUENCE is different: every number that reaches the
// lane is one a body actually breathed, and only the weight moves. Stated as the property that
// actually makes it honest — the reviewer's formulation, sharper than the first draft's: the
// output stays inside the convex hull of `{hr, (hr+br)/2}` at every instant, because
// `hr + w·(br − hr)/2` is a convex combination with weights `((2−w)/2, w/2)`. A rate LIMITER on
// the output has no such property: during its slew it emits a value no `(hr, br)` pair produces,
// and on a recorded lane that value is indistinguishable from a measurement.
//
// ⭐ IT IS CONTINUOUS IN BOTH DIRECTIONS, and the obvious version is not. An age-only weight
// (1 while fresh, ramping to 0 when stale) removes the step on DROPOUT and leaves it on
// RE-ACQUISITION — the weight snaps back to 1 the moment a frame arrives. So a resumed run
// climbs from the weight the hold ALREADY had (`resumeWeight`), never from 0 or 1.
// `testResumingMidReleaseDoesNotStep` is the assertion that would catch the naive version.
//
// ⭐ THE HORIZON IS CHAINED, NOT CHOSEN — and the first draft's two constants (2 s / 4 s) were
// BOTH wrong, in different ways, which is why this reads as a derivation and not as a pair of
// numbers:
//   ⛔ The first draft justified them against "a 10 s analysis window". There is no 10 s breath
//     window. The only 10 s in the chain is `CameraAnalyzer.detectPeaks`' PULSE peak-detector
//     span; `RespirationEstimator` is recursive (trend/smooth/envelope time constants plus a
//     per-crossing period EMA) and its own validity law is period-SCALED, not fixed. The ceiling
//     was derived against a window belonging to a different signal.
//   ⛔ And "two seconds absorbs two consecutive missed frames" was arithmetic that does not
//     survive being written out: two missed frames at the shipped ~1 Hz cadence is a **3 s**
//     gap, and the break test is `gap > grace`. 2.0 absorbed ONE.
//   ⭐ The horizon is now the SOURCE'S OWN freshness window (`BioSource.freshnessWindow`),
//     handed in with each measurement, split in half: full weight for the first half, a linear
//     fade to zero across the second. That makes ONE invariant carry both ends —
//     **the breath term's influence expires exactly when the bus stops trusting the frame it
//     came from** — and it is a real chain to a constant that already decides this question,
//     not a fresh number (#426's form). It also removes a REGRESSION the fixed pair had and
//     nobody had noticed: `HealthKitBioPublisher` publishes a real breath rate once per new
//     reading, minutes apart, inside a 90 s window. Under 2 s + 4 s a wrist breath rate reached
//     the lane at weight 0 for ~83 of its 90 usable seconds — silently disabled, the exact
//     "lying control" class this repo keeps paying for. Under the chain it is full weight for
//     45 s and fades out precisely as the frame expires.
//   Consequences at the two live windows: camera/BLE (6 s) → 3 s grace + 3 s fade, so two
//   missed frames at ~1 Hz still move nothing and the weight travels at most 1/3 per second;
//   HealthKit/Watch (90 s) → 45 s + 45 s.
//
// ⚠️ WHAT THIS CANNOT SHOW, and it is the same limit #433 stated: nothing here proves any of it
// is heard or recorded. `RecordController.onStep` opens with `guard armed else { return }`,
// `arm()` has zero callers in `Sources/`, and #204 records the controller as doorless. The
// repair is worth making BECAUSE the path is dormant — the same arithmetic behind a door would
// need a device listen, not a test.
//
// ⚠️ ONE ARTIFACT IS KNOWN, MEASURED AND NOT FIXED HERE: a PERIODICALLY flickering source
// produces a smooth triangle rather than a decaying envelope — an oscillation in the breathing
// band (a 7 s flicker is 0.14 Hz), which on a recorded lane is harder to recognise as a fault
// than the square wave it replaces.
//
// ⛔ AND THE FIX THIS PARAGRAPH USED TO NAME WAS A NO-OP. It read: "`up` may climb while a gap
// is still open … Freezing `up` outside the grace window is the candidate fix." The artifact is
// real; that cause is not, and freezing `up` provably changes nothing on any input. #444 is the
// slice that went to implement it and measured instead:
//
//   A restart needs `now − lastMeasuredAt > graceSeconds`, and `graceSeconds == horizon / 2`.
//   `runStartedAt` is only ever assigned at a measurement, so `runStartedAt <= lastMeasuredAt`.
//   Hence at any restart `elapsed = now − runStartedAt >= now − lastMeasuredAt > half`, so
//   `up = resumeWeight + elapsed / half > 1`, so `min(up, down) == down`. Freezing `up` at
//   `lastMeasuredAt + half` still gives `elapsed >= half`, so still `up >= 1` — the SAME branch
//   of the `min`. Inside grace the freeze is inactive by construction. Measured as well as
//   argued: 6 000 randomised traces over the three live windows produced 61 769 restarts, the
//   smallest `up` at any of them was 1.000224, and the difference against the frozen variant was
//   exactly 0 at every sample. `Tests/CISmoke/TheGapClimbCannotChangeTheResumeTests.swift`.
//
//   What `up` actually does is carry the ramp DURING a run; what it cannot do is influence the
//   value a run restarts FROM. The triangle is the fade itself: `down` falls at
//   `1/releaseSeconds`, the resumed ramp climbs at the same rate, so a source flickering slower
//   than the horizon traces a symmetric triangle whose peaks all reach 1. Making those peaks
//   decay — a source that keeps dropping out earning less trust each time — means changing the
//   RAMP RATE on re-acquisition. That is a behaviour policy, not a typo, so it still does not
//   ride along; `testTheRampRateDoesNotRememberEarlierDropouts` is there to make it a red test
//   rather than a side effect.
//
// ⭐ THE LESSON, and it is why this correction is worth more than the artifact: a registered
// follow-up with a NAMED cause is the most expensive kind of wrong note in this repo (#167). The
// next session cannot argue with it — it implements it, measures nothing, and ships a diff that
// looks like a fix.
//
// PURE value type. Foundation only. No clock of its own — every timestamp is handed in, which
// is what makes the whole thing testable without a simulator.

import Foundation

/// Carries the last MEASURED breath rate across a dropout and reports how much of it should
/// still count, so `bioNormalized` can leave the "we have breath" branch at the value it
/// entered with instead of stepping.
///
/// Feed every frame through `observe` — a frame WITHOUT a breath measurement is fed as `nil`,
/// which is not the same as feeding `0` (that is the fabricated calm #433 removed). Then read
/// `rate` and `weight(at:)` and hand both to `bioNormalized(bpm:heldBreathRate:blend:)`.
///
/// ⚠️ `observe` takes the FRAME's timestamp; `weight(at:)` takes the reading clock — see
/// `weight(at:)`. They are the same clock (`CFAbsoluteTimeGetCurrent`) but not the same instant,
/// and conflating them is the defect this type shipped with for one draft.
public struct BreathHold: Sendable, Equatable {

    /// Floor for the influence horizon, so a source that reports a zero or negative window
    /// cannot divide by zero or hand a stale rate unlimited weight. One second is below every
    /// window `BioSource` declares (the smallest is `.fallback`'s 5 s), so on the shipped
    /// sources this never binds — it exists for the argument, not for a case.
    public static let minimumHorizon: TimeInterval = 1.0

    /// The last breath rate that was actually MEASURED. Never a fabricated value: it only
    /// changes when `observe` is handed a non-nil, finite rate.
    public private(set) var rate: Double = 0

    /// The influence horizon of the last measurement — its source's own freshness window,
    /// floored. Zero until something has been measured.
    public private(set) var horizon: TimeInterval = 0

    /// How long a measurement counts at FULL weight, and how long the fade to zero then takes.
    /// Both are half the horizon; see the file header for why that split is the whole design.
    public var graceSeconds: TimeInterval { horizon * 0.5 }
    public var releaseSeconds: TimeInterval { horizon * 0.5 }

    private var lastMeasuredAt: TimeInterval = -.infinity
    private var runStartedAt: TimeInterval = -.infinity
    private var resumeWeight: Double = 0

    public init() {}

    /// Record one frame.
    ///
    /// - Parameters:
    ///   - measured: the breath rate if this frame HAS one, `nil` if it does not. The caller
    ///     owns that decision — this type deliberately does not know what "a plausible breath
    ///     rate" means, because `BioSampleFrame.plausibleBreathRate` is the repo's single
    ///     answer to that question and a second copy here would be the #416 defect.
    ///     ⚠️ The cost of that delegation, stated rather than left to be discovered: a finite
    ///     but ABSURD value (say 1e6) is accepted here and overwrites both `rate` and the
    ///     timestamp. `bioNormalized` then drops the term — so the lane is safe — but a good
    ///     held rate is gone with no way back. Today's only caller cannot do it; a second one
    ///     could.
    ///   - now: the frame's timestamp in seconds. A frame that is not strictly newer than the
    ///     last measurement is ignored — the bus already dedups on `frame.timestamp`, and a
    ///     repeated stamp must not be able to hand a stale value full weight.
    ///   - window: how long this frame's SOURCE stays usable (`BioSource.freshnessWindow`).
    ///     This is the influence horizon; see the file header.
    public mutating func observe(measured: Double?, at now: TimeInterval, usableFor window: TimeInterval) {
        guard now.isFinite else { return }

        // ⛔ A BACKWARDS CLOCK STEP USED TO LATCH THIS TYPE FOREVER, and the first draft's doc
        // reasoned about re-ordered stamps in a way that made it read as covered. These
        // timestamps ride `CFAbsoluteTimeGetCurrent` — wall clock, which an NTP correction or a
        // user can move backwards. `lastMeasuredAt` then sits in the future, the guard below
        // rejects EVERY later frame, `rate` never updates again, and `weight` returns a
        // partial, permanent weight on a rate nobody is breathing any more. That is the
        // fabricated-number failure #433 removed, arriving through the back door. Starting over
        // loses the hold, which costs one fade — the honest price.
        if now < lastMeasuredAt { self = BreathHold() }

        guard let measured, measured.isFinite, window.isFinite else { return }
        guard now > lastMeasuredAt else { return }

        // A gap longer than the grace window ENDS the run. Restarting the climb from the weight
        // we currently hold — not from 0 or 1 — is what makes re-acquisition continuous.
        //
        // ⛔ THE FIRST DRAFT MADE AN EXCEPTION FOR THE VERY FIRST MEASUREMENT (`… : 1`) and
        // argued that a ramp needs a previous value to be continuous with. BOTH reviewers found
        // that inverted, independently, and they were right: at the LANE level there IS a
        // previous value. `usableBio()` gates on freshness, not on breath, so a take that starts
        // while rPPG is still acquiring (~19 s per #415) records heart-only samples first — and
        // then jumped by the full 0.4286 the instant breath first locked. Measured on 1 Hz
        // frames at 120 bpm / 6 per min, eight heart-only frames then breath: **0.4286** with
        // the exception, **0.1071** without it. The evidence that had justified it came from a
        // fixture whose array STARTED at the first measured frame, so it could not see the cost
        // it was used to dismiss. `weight(at:)` already returns 0 before anything is measured,
        // so deleting the exception is deleting the ternary — the general rule was right all
        // along. The honest price: a take that begins exactly at the first measurement
        // under-weights breath for one fade.
        if now - lastMeasuredAt > graceSeconds {
            resumeWeight = weight(at: now)
            runStartedAt = now
        }
        horizon = Swift.max(Self.minimumHorizon, window)
        rate = measured
        lastMeasuredAt = now
    }

    /// How much of `rate` should count at `now`, in 0…1.
    ///
    /// 1 means "blend the breath term exactly as `bioNormalized` always did"; 0 means "the
    /// heart term stands alone", which is what #433 established for an unmeasured body. Every
    /// value between is a fade of a REAL measurement's influence, never an invented rate.
    ///
    /// ⚠️ READ THIS ON THE CALLER'S CLOCK, NOT ON `frame.timestamp` — the defect the first draft
    /// shipped with, and the one that made the whole slice a no-op on its main case. A frame's
    /// timestamp is the age of the newest real measurement, and it STOPS ADVANCING exactly when
    /// the fade is needed: `CameraRPPGBioPublisher`'s pulse-HOLD republish deliberately carries
    /// `held.timestamp` (its own comment says consumers that dedupe on it see a no-op) while
    /// `EngineBus.usableBio()` keeps that frozen frame alive against the WALL clock. Reading the
    /// weight at the frame stamp therefore pinned it at 1 for the entire hold and then dropped
    /// it to 0 in a single lane sample — the full step, in the case the fade exists for.
    ///
    /// ⚠️ And what the per-second bound describes is this function, not the recording. The
    /// weight moves at most `1/releaseSeconds` per second; the lane records that ramp SAMPLED at
    /// the transport step rate, so between two adjacent keyframes it can move by a whole sample
    /// period's worth. The bound is on the signal, not on the difference between two rows.
    public func weight(at now: TimeInterval) -> Double {
        guard now.isFinite, runStartedAt.isFinite, lastMeasuredAt.isFinite, horizon > 0 else { return 0 }

        let half = horizon * 0.5
        let age = now - lastMeasuredAt
        let down: Double
        if age <= half {
            down = 1
        } else if age >= horizon {
            down = 0
        } else {
            down = 1 - (age - half) / half
        }

        let elapsed = now - runStartedAt
        let up = resumeWeight + (elapsed > 0 ? elapsed : 0) / half

        // `clamped(to:)` (Core/FloatingPointClamp.swift) rather than a local helper: the first
        // draft wrote a fourth private copy of this clamp, in a file whose own docs cite #416
        // twice. It also diverged — the copy mapped +∞ to 0 where the canonical one maps it to
        // 1. Unreachable behind the guards above, and exactly the kind of quiet fork that is
        // reachable later.
        return Swift.min(up, down).clamped(to: 0...1)
    }
}
