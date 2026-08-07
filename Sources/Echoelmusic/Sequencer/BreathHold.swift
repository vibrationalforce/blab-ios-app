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
//     "lying control" class this repo keeps paying for.
//     ⛔ AND THE SENTENCE THAT FOLLOWED HERE OVERSTATED THE RESULT — in the same paragraph that
//     congratulates itself for catching an overstatement. It read "full weight for 45 s and
//     fades out precisely as the frame expires". It is a TRIANGLE, not a plateau: measured for
//     a wrist reading, `weight` at t = 0/5/15/30/45/60/90 s is 0.0 / 0.111 / 0.333 / 0.667 /
//     **1.0 / 0.667 / 0.0** — full weight is touched for ONE INSTANT at t = 45, and the mean
//     over the 90 s usable life is exactly **1/2**. And because HealthKit publishes once per new
//     reading, minutes apart (this paragraph's own words), every wrist reading restarts from
//     `resumeWeight == 0`, so that triangle is the NORMAL case, not an edge one. The regression
//     claim survives — half weight beats "0 for ~83 of 90 s" by a lot — but the wrist path was
//     still substantially under-weighted for a source whose whole point is that a reading from a
//     minute ago is still valid. ✅ FIXED IN #448 (mean 11/15); the derivation is the ATTACK RATE
//     note below, which also retracts the ungridded "0.4712" this paragraph used to carry.
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
//   `runStartedAt` is only ever ADVANCED at a measurement, and its one other assignment — the
//   backwards-clock `self = BreathHold()` below — sets it and `lastMeasuredAt` to −∞ TOGETHER,
//   so `runStartedAt <= lastMeasuredAt` survives both. Hence at any restart
//   `elapsed = now − runStartedAt >= now − lastMeasuredAt > half`, so
//   `up = resumeWeight + elapsed / half > 1`, so `min(up, down) == down`. Freezing `up` at
//   `lastMeasuredAt + half` still gives `elapsed >= half`, so still `up >= 1` — the SAME branch
//   of the `min`. Inside grace the freeze is inactive by construction. Measured as well as
//   argued: 6 000 randomised traces produced 61 769 restarts and the difference against the
//   frozen variant was exactly 0 at every sample. An independent adversarial re-run (mixed
//   windows inside one trace, 5 % backwards clock steps, `nil`/NaN measurements, negative
//   absolute times) found 102 921 restarts and a max difference of 0.0 over 1 287 552 samples.
//   `Tests/CISmoke/TheGapClimbCannotChangeTheResumeTests.swift`.
//   ⛔ Both sweeps also reported "the smallest `up` seen at a restart" (1.000224, then
//   1.0000009939619714) and the first draft quoted the first of those as if it were a MARGIN. It
//   is not a property of this code — it is a property of the random number generator. The restart
//   test is a STRICT inequality, so the infimum of `up` at a restart is exactly 1 and is never
//   attained; a denser sweep simply reports a smaller number, for ever. The theorem is the
//   load-bearing statement here. The sweeps only show it did not miss a case.
//   ⚠️ Coverage, stated rather than implied: `BioSource.freshnessWindow` declares FOUR distinct
//   values across six cases — 6 s (ble · cameraPPG · faceCam), 90 s (watch · healthKit), 600 s
//   (oura), 5 s (fallback). The sweeps drove 5 / 6 / 90, i.e. every value that has a producer in
//   `Sources/` today; `.oura`'s 600 has none. The proof does not depend on the window at all
//   (`half` cancels out of the comparison), so the untested value is a coverage note, not a hole.
//   ⚠️ "At any restart" is VACUOUS in exactly one case: at the FIRST measurement `horizon` is
//   still 0, so `weight(at:)` returns at its `horizon > 0` guard and `up` is never formed. The
//   conclusion is stronger there, not weaker — both variants return 0.
//
//   What `up` actually does is carry the ramp DURING a run; what it cannot do is influence the
//   value a run restarts FROM. The triangle is the fade itself: `down` falls at
//   `1/releaseSeconds`, and the resumed ramp USED TO climb at the same rate, so a source
//   flickering slower than the horizon traced a symmetric triangle whose peaks all reach 1.
//   ⛔ That equality is GONE for every window over 6 s as of #448 — the sentence above stood in
//   the present tense in the very file #448 edited, and it is the #444 lesson in its quietest
//   form: prose that survives a change is the prose nobody re-reads. On camera/BLE the triangle
//   is unchanged (3 s attack, 3 s release). On the WRIST the shape is now a SAWTOOTH: 3 s rise,
//   45 s fall. Making those peaks
//   decay — a source that keeps dropping out earning less trust each time — means changing the
//   RAMP RATE on re-acquisition. That is a behaviour policy, not a typo, so it still does not
//   ride along; `testTheRampRateDoesNotRememberEarlierDropouts` is there to make it a red test
//   rather than a side effect.
//
// ✅ ATTACK RATE == RELEASE RATE, AND NOTHING IN THIS FILE EVER DECIDED THAT — FIXED IN #448.
// This is the sentence that belongs where the withdrawn cause stood, and it is a stronger
// statement than the one it replaces. The triangle is not made by `up` climbing during a gap; it
// is made by the climb and the fade having the SAME slope. `down` falls at `1/half`. `up` used to
// climb at `elapsed / half` — also `1/half`, and only because `up` reused `half` as its divisor.
// The header above derives the SPLIT (grace = release = horizon/2, chained to the source's own
// freshness window, #426's form). It never derived the ATTACK: the re-acquisition rate arrived as
// a side effect of the one constant that was chosen for the expiry side.
//   The expensive consequence was the WRIST path. A 90 s horizon meant a 45 s attack, so a
//   HealthKit reading arriving minutes after the last one spent its entire usable life climbing
//   and then falling — the source whose whole premise is "a reading from a minute ago is still
//   your current rate" was the one this coupled hardest against. Camera/BLE was comparatively
//   unharmed because its 3 s attack is short against its ~1 Hz cadence.
//   ⭐ THE ANSWER WAS ALREADY IN THE FILE: 3 s is what camera/BLE — the only live source —
//   already attacks over. So `maximumAttack` generalises the LIVE path's behaviour instead of
//   inventing a number, and expressing it as `min(releaseSeconds, …)` keeps camera (3 s) and
//   `.fallback` (2.5 s) bit-identical AND keeps #444's `elapsed > half >= attack` precondition
//   true by construction.
//   ⛔ The first draft justified the 3 s differently — "three frames at the ~1 Hz apply rate,
//   the shortest ramp that reads as a ramp on the lane" — and that derivation is FALSE, on a
//   fact this same file states two hundred lines below (see `weight(at:)`). The ramp is not
//   sampled at frame arrivals: `RecordController.onStep` reads it as
//   `breathHold.weight(at: CFAbsoluteTimeGetCurrent())` on every TRANSPORT step, and
//   `BioAutomationRecorder.minTickInterval` defaults to exactly one step, so nothing is
//   decimated. `Transport.stepDuration(atTempo:)` is `60/bpm/4` over a 30…300 clamp, i.e. a lane
//   rate of 2–20 Hz — 8 Hz at the default 120 BPM, where a 3 s attack is ~24 keyframes and not
//   three. The number stands; the reason was a rationalisation reached for after the fact. The
//   honest one is the sentence above plus this: the attack is a SLEW LIMIT ON THE LANE, and a
//   slew limit has no business being derived from how long a sensor's reading stays fresh.
//   Measured over one full 90 s wrist life, weight sampled every 0.5 s: mean **0.4972 → 0.7293**.
//   The exact continuous means are cleaner and grid-free: **1/2 → 11/15**. Camera (6 s) and
//   `.fallback` (5 s): max |Δ| exactly **0** at every sample.
//   ⛔ The number this paragraph carried before was "mean weight 0.4712", quoted with no grid.
//   ⛔ AND THE FIRST RETRACTION OF IT WAS ITSELF FALSE, in the paragraph whose subject is false
//   numbers. It said "no sampling of the old shape lands on 0.4712 … it could not be reproduced
//   or refuted". It can: **0.4712 = 90/191 exactly** — this very 0.5 s grid, run to t = 95 s
//   instead of 90. The trace sums to 90 either way (everything past the horizon is 0), so the ten
//   extra zero samples pull the mean from 90/181 to 90/191. Swept step ∈ {0.05 … 5} × end ∈
//   [90, 130], that is the UNIQUE hit — an entirely ordinary "one life plus a little tail" grid.
//   So the old number was UNDER-SPECIFIED, not unreproducible, and it read low because its window
//   included ten samples of pure post-expiry silence. Calling it irrefutable was the same defect
//   one level up, and it was the load-bearing sentence of this paragraph. A measured number in
//   this repo carries its grid or it is not a measurement — and a retraction carries the search
//   that failed, or it is not a retraction.
//   ⛔ And the obvious-looking alternative is still REJECTED, not merely deferred — a decaying
//   envelope that lowers each successive peak so a repeatedly-dropping source earns less trust.
//   It fails on the same ground #433 used to delete the fabricated calm: the bus still trusts the
//   frame, so lowering its influence invents a distrust nothing measured, and on a recorded lane
//   the result is indistinguishable from a body that actually breathed less regularly. It also
//   makes the weight depend on history the caller cannot see, so two identical bodies read
//   differently. `testTheRampRateDoesNotRememberEarlierDropouts` exists to make that a red test
//   rather than a side effect of some later tidy-up — and #448 deliberately does not touch it:
//   a CEILING is not a memory.
//   ⚠️ What #448 does NOT fix: the flicker triangle. On camera/BLE the attack is unchanged, so a
//   source flickering slower than its horizon traces exactly the same shape. That artifact was
//   never the attack rate's fault at that window; it is the shape of `min(up, down)` itself.
//   ⚠️ AND #448 ADDS ONE, on the window it repairs — the first draft of this bullet said "camera
//   /BLE unchanged" and stopped there, which reads as "unchanged everywhere". On the WRIST the
//   flicker shape becomes a SAWTOOTH (3 s rise, 45 s fall), and a steep edge moves AC energy into
//   the breathing band. Measured by the review pass, share of AC energy in 0.05–0.5 Hz, old →
//   new: 60 s flicker period **1.28 % → 27.25 %** · 120 s 0.09 % → 2.98 % · 180 s 0.07 % → 1.88 %
//   · 300 s 0.06 % → 1.43 %. Amplitude is bit-identical at every period swept, and the worst
//   keyframe-to-keyframe move at the slowest legal tempo is 0.1667 weight units — i.e. ≤ 0.083
//   lane units after the `|hr − br|/2` scaling, an order of magnitude under the 0.4286 step #434
//   exists to remove, and exactly what camera/BLE already ships. So no step is reintroduced at
//   any legal tempo; the transient is real and is named here rather than covered by a
//   camera-scoped sentence.
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

    /// Ceiling on the ATTACK — how long re-acquisition takes to climb back to full weight.
    ///
    /// ⭐ THIS IS NOT A NEW NUMBER; IT IS THE LIVE PATH'S OWN ATTACK, GENERALISED (#448). Until
    /// this constant existed the attack was `releaseSeconds`, purely because `up` reused `half`
    /// as its divisor — the file header derives the SPLIT (grace = release = horizon/2, chained
    /// to `BioSource.freshnessWindow`) and never derives the attack at all. On camera/BLE that
    /// accident lands on 3 s, which is three frames at the ~1 Hz apply rate the bus actually
    /// runs at (`Tests/CISmoke/BioApplyRateIsTheDedupedRateTests`). Three is the smallest count
    /// that reads as a ramp rather than a step on a lane sampled at that rate: one sample IS the
    /// step, two gives a single midpoint. So the shipped live behaviour is the definition, and
    /// the ceiling stops a SLOW source from scaling that ramp up with its freshness window.
    ///
    /// ⚠️ It is expressed as a ceiling — `min(releaseSeconds, …)` — and that form is load-bearing
    /// twice over. It keeps camera (3 s) and `.fallback` (2.5 s) BIT-IDENTICAL, so every existing
    /// assertion in `TheGapClimbCannotChangeTheResumeTests` still measures what it measured. And
    /// it preserves #444's theorem by construction: that proof needs `elapsed > half >= attack`
    /// at every restart to conclude `up > 1`, which holds for any attack at or below the release.
    /// A bare constant larger than some source's release would break both.
    public static let maximumAttack: TimeInterval = 3.0

    /// How long a measurement counts at FULL weight, and how long the fade to zero then takes.
    /// Both are half the horizon; see the file header for why that split is the whole design.
    public var graceSeconds: TimeInterval { horizon * 0.5 }
    public var releaseSeconds: TimeInterval { horizon * 0.5 }

    /// How long re-acquisition takes to climb back to full weight — the release, capped.
    /// Deliberately NOT `releaseSeconds`: see `maximumAttack`.
    public var attackSeconds: TimeInterval { Swift.min(releaseSeconds, Self.maximumAttack) }

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

        // ⛔ AND THE ORDER OF THE NEXT TWO STATEMENTS WAS THE OTHER WAY ROUND, WHICH MADE A
        // NON-MEASUREMENT ABLE TO DESTROY THE HOLD (#447). The backwards-clock reset ran BEFORE
        // the `guard let measured`, so ANY frame with a stamp older than the last measurement
        // wiped the whole type — including the one frame the system produces on purpose with a
        // frozen stamp and no breath: `CameraRPPGBioPublisher`'s pulse-HOLD republish carries
        // `held.timestamp` ("do not re-stamp", its own comment) together with `breathRate: 0`.
        //
        // ⭐ THE TRIGGER IS NARROWER AND MORE SPECIFIC THAN "SOURCES INTERLEAVE", and getting
        // that right is what makes this a one-statement move instead of a redesign. EVERY real
        // measurement in this app stamps `CFAbsoluteTimeGetCurrent()` at RECEIPT — camera, BLE,
        // demo and HealthKit alike (`HealthKitBioPublisher` says so at its own `timestamp:`,
        // and #98c2 is why). So real measurements are monotone ACROSS sources; the hold
        // republish is the one stamp in the system that deliberately goes backwards. With one
        // source it is harmless, because the frozen stamp equals the last measurement. With a
        // SECOND source running — and `healthBio.startIfAlreadyAuthorized` runs at app level,
        // independent of the pill's camera/BLE/sim choice — a wrist frame advances
        // `lastMeasuredAt` past the frozen stamp, and the next hold republish resets everything.
        //
        // ⚠️ MEASURED, because "it resets" understates it: 20 s of camera breath, one HealthKit
        // frame, then hold republishes at 1 Hz — the weight went 1.0 → **0.0 in a single lane
        // sample** and stayed there, with `rate` and `horizon` wiped to 0 as well. Nothing can
        // recover until a new MEASURED frame arrives, and during a pulse dropout none does. That
        // is the full step #434 built this type to remove, in the exact case it was built for,
        // arriving through a guard written for a different problem.
        //
        // The NTP protection itself is unchanged and still needed: wall clock can move
        // backwards, `lastMeasuredAt` then sits in the future, the guard below rejects EVERY
        // later frame, `rate` never updates again, and `weight` returns a partial, permanent
        // weight on a rate nobody is breathing any more — the fabricated-number failure #433
        // removed, through the back door. It now fires only when a REAL measurement proves the
        // clock moved, which is the only moment it can do anything anyway: a nil frame cannot
        // advance state, so deferring the check costs nothing. Starting over still loses the
        // hold and still costs one fade — the honest price, now paid only for a real cause.
        //
        // ⚠️ WHAT THIS DOES NOT FIX, so nobody reads it as more than it is: two real
        // measurements from different sources can still arrive out of stamp order through a
        // publish race (both stamp receipt time, on different actors, microseconds apart). That
        // case still resets, and it still should — nothing here can tell it from a clock step.
        // Removing it needs per-source state (`BioEventPublisher`'s shape), which is a design
        // decision about which hold wins, not a reordering. Task #447 keeps that half.
        guard let measured, measured.isFinite, window.isFinite else { return }

        if now < lastMeasuredAt { self = BreathHold() }
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
    /// weight rises at most `1/attackSeconds` and falls at most `1/releaseSeconds` per second —
    /// two different bounds since #448, where they used to be one; the lane records that ramp SAMPLED at
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

        // ⭐ THE ATTACK IS NO LONGER `half` (#448). It used to be, purely because this line
        // reused the divisor the EXPIRY side had chosen — see `maximumAttack`. `attack <= half`
        // always, so #444's theorem (`elapsed > half >= attack` at every restart ⇒ `up > 1`) is
        // preserved, and the camera/BLE and `.fallback` traces are bit-identical.
        // ⛔ And the first draft of this line wrote `Swift.min(half, Self.maximumAttack)` INLINE,
        // twenty lines under a `maximumAttack` doc that reasons about the `min(releaseSeconds, …)`
        // form and a hundred under `attackSeconds`, which is that expression. Two definitions of
        // one quantity, in the file that cites #416 twice — and the expensive half is that three
        // of #448's six guards assert on the ACCESSOR, which the shipped path then never read.
        // Editing `attackSeconds` alone would have left them green.
        let attack = attackSeconds
        let elapsed = now - runStartedAt
        let up = resumeWeight + (elapsed > 0 ? elapsed : 0) / attack

        // `clamped(to:)` (Core/FloatingPointClamp.swift) rather than a local helper: the first
        // draft wrote a fourth private copy of this clamp, in a file whose own docs cite #416
        // twice. It also diverged — the copy mapped +∞ to 0 where the canonical one maps it to
        // 1. Unreachable behind the guards above, and exactly the kind of quiet fork that is
        // reachable later.
        return Swift.min(up, down).clamped(to: 0...1)
    }
}
