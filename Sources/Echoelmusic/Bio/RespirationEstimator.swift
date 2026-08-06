//
//  RespirationEstimator.swift
//  Echoelmusic — Bio
//
//  Estimates breathing from the heart-rate signal the rPPG camera already produces,
//  via Respiratory Sinus Arrhythmia (RSA): breathing modulates heart rate — inhale
//  speeds it up, exhale slows it down — so the instantaneous-HR series oscillates at
//  the breathing frequency (~0.1–0.4 Hz). We band-pass that oscillation, normalize it
//  to a [0,1] amplitude (1 = inhale peak / lungs full) for the breath ball, and read
//  the breathing rate from its cycle length. This makes the guide TRUE biofeedback:
//  the ball follows the body's MEASURED breath instead of a fixed metronome.
//
//  Pure, deterministic value type: feed instantaneous HR samples (bpm) with their
//  timestamps via `ingest(heartRate:at:)`; read `amplitude` / `ratePerMinute` /
//  `confidence`. Time-aware EMAs make it robust to the irregular sample spacing of an
//  IBI stream. No allocation, no timers, no I/O — host-loop friendly.
//
//  This is self-observation, not a medical respiration monitor.
//

import Foundation

public struct RespirationEstimator {

    // MARK: Tuning (seconds)
    /// High-pass: removes the slow HR baseline so only the respiratory swing remains.
    private static let trendTau = 8.0
    /// Low-pass: keeps the respiration band, drops beat-to-beat jitter.
    private static let smoothTau = 0.8
    /// Envelope decay used to normalize the swing to [0,1].
    private static let envTau = 6.0
    /// Subtracted from the measured staleness to pay for the delay between the beat that marks
    /// a breath cycle and that beat reaching `ingest`. See `age(to:)` and the grace comment
    /// below — without it the pull turns a pipeline delay into apparent staleness at the fast
    /// end of the supported band.
    ///
    /// DERIVED FROM THE THREE PIPELINE TERMS, measured from the LAST BEAT (which is where the
    /// host's `age(to:)` clock effectively starts): a peak needs two later samples to be
    /// confirmed (`CameraAnalyzer`'s `val > window[i+1] && val > window[i+2]`), the peak scan
    /// is throttled to every 4th frame, and the publish drain runs at ~1 Hz. At 15 fps that is
    /// 0.13 + 0.27 + 1.0 ≈ 1.40 s; at 7.5 fps — the low end `CameraAnalyzer` documents for
    /// this device range — the two frame-counted terms double to 1.80 s. This is the 7.5 fps
    /// figure, so the slower device is covered rather than the faster one.
    ///
    /// ⚠️ IT IS A BUDGET, NOT AN EXACT SUM, and the "≈" is carrying two known errors in
    /// opposite directions. The frame terms overcount by one frame (a peak at frame k is
    /// confirmable at k+2 and the next `peakTick % 4 == 0` scan is at most k+5, so five frames,
    /// not 2+4 = 6), and the capture hop is missing entirely (`sampleQueue.push` stamps
    /// `systemUptime` and the 100 ms loop drains it on the next tick, ≤0.1 s). They roughly
    /// cancel. Both errors are in the safe direction for an ALLOWANCE — an overpaid allowance
    /// only widens the stale window slightly — but the line reads like three exact terms, and
    /// this file has already paid for one budget that read exact and was not.
    ///
    /// ⛔ A FOURTH TERM WAS IN THE FIRST VERSION AND DOES NOT BELONG: "the crossing is stamped
    /// at a beat (≈1 s at rest)". That quantisation is real, but it is already inside
    /// `lastBeat − lastCrossT`, so adding it to a lag measured FROM the last beat counts it
    /// twice — and it applied identically before the pull, so it is not part of the delta the
    /// pull introduced. That mistake put the constant at 2.5 s and the comment opened with
    /// "THE ALLOWANCE IS NOT PADDING", which was then exactly what the extra second was.
    /// The correction narrows the case as well as the number: with the three real terms the
    /// worst phase at 28 breaths/min reads 0.4378 at 15 fps — no defect — and 0.3725 at 7.5 fps,
    /// under the 0.4 gate. This is a slow-device defect, and saying so is the point.
    ///
    /// ⛔ THOSE TWO NUMBERS WERE 0.457 / 0.394 UNTIL #424 AND ARE NOT THE SAME MEASUREMENT ANY
    /// MORE. Widening the acceptance band changes which crossings feed `periodEMA` at 28/min,
    /// which changes `grace`, which changes this confidence — so every 28–30/min figure in this
    /// file moved with that commit even though nothing in THIS constant was touched. The
    /// conclusion is unchanged (15 fps clears the gate, 7.5 fps does not) and the margin got
    /// slightly thinner, which is the direction that matters for a slow-device claim.
    ///
    /// Two tests in `ResonanceBreathingNeedsMoreThanOneWindowTests` bracket this constant and
    /// nothing else does: `…FastBreathers…` goes red below ≈0.87 s, `…AgesWithTheClock…` above
    /// ≈15.0 s. 1.8 therefore sits ≈0.93 s above the floor and ≈13.2 s below the ceiling —
    /// deliberately close to the floor, because every second of allowance is a second the
    /// estimator keeps claiming a rate it can no longer see.
    ///
    /// ⛔ THE FLOOR READ ≈0.74 s (MARGIN ≈1.06 s) UNTIL #424 AND NEITHER FIGURE WAS RE-DERIVED
    /// WHEN THE ACCEPTANCE BAND MOVED. The lower bracket is measured at 28/min, which is close
    /// enough to the band edge that `bandTolerance` changes which crossings feed `periodEMA`;
    /// the ceiling is measured at 6/min and did not move at all. So a constant documented as
    /// bracketed "from both sides" had one of its two brackets silently invalidated by an edit
    /// to a DIFFERENT constant twenty lines below. The margin is now ≈0.93 s — still comfortable,
    /// and worth re-measuring after any change to either band.
    private static let pullLagAllowance = 1.8

    // MARK: Respiration band (breaths/min)
    /// The band this estimator ADVERTISES and REPORTS in.
    ///
    /// ⛔ THIS LINE ENDED "`ratePerMinute` never leaves it" AND THAT WAS ONLY TRUE WHILE THE
    /// CLAMP EXISTED — the sentence survived the commit that removed the clamp, sitting on the
    /// public constants, which is the first thing anyone reads about the band.
    ///
    /// ⛔ AND EVERY NUMBER THAT REPLACED IT WAS A 60 bpm NUMBER FOR ONE COMMIT — quoted as a
    /// property of the estimator, in the paragraph whose whole job is to say the band claim is not
    /// exact. That is the same one-fixture error the `bandTolerance` doc below spends four
    /// paragraphs retracting, committed one screen away from it and on the same day. **A bound
    /// measured at one pulse is quoted with that pulse or it is not quoted.**
    ///
    /// ⛔ AND THE PULSE-QUALIFIED REPLACEMENT WAS STILL WRONG BY ~19× — the third try at this one
    /// paragraph, and the reason is worth more than the number. "up to 0.074/min above `maxRate`"
    /// was the worst value at the two pulses I happened to sweep (60 and 90). The report is not
    /// bounded by those measurements at all: **it is bounded by the ACCEPT band**, which is
    /// `[minRate / bandTolerance, maxRate * bandTolerance]` = `[3.774, 31.8]` at the shipped
    /// tolerance. Swept over the pulse axis (37…110), a body breathing exactly `maxRate` reports
    /// up to **+1.42/min above it** (pulse 63; 8 of 74 pulses exceed +0.074), and a body at
    /// `minRate` reports down to **3.793** (pulse 38, 0.21 under). So:
    ///
    /// **`minRate`/`maxRate` are the band this estimator TARGETS, not a range the output obeys.
    /// A consumer that gates on the exact bounds is gating on the wrong numbers — use the accept
    /// band, or accept a fraction outside.** `HealthWritePolicy.respiratoryRange` (4…40) is the
    /// one that matters today, and its low end is exactly where the excursion is; see the ⛔ on
    /// the health path below.
    public static let minRate = 4.0
    public static let maxRate = 30.0

    /// ⭐ ACCEPT WIDER THAN YOU REPORT (#424). A candidate period is accepted if its implied
    /// rate falls in `[minRate / bandTolerance, maxRate * bandTolerance]`. The reported rate is
    /// the raw EMA and is NOT clamped back — see the second ⛔ below for why that mattered.
    ///
    /// Until #424 there was ONE band doing both jobs, and a measurement whose jitter put it a
    /// hair outside was discarded entirely — no period, no crossing count, no rate. That is not
    /// conservative at the edges, it is blind: swept over all 360 whole-degree phases with 60 s
    /// takes at a resting pulse, `ratePerMinute` stayed 0 at **240 of 360 phases at 4/min** and
    /// **61 of 360 at 30/min** — the estimator's own advertised limits.
    ///
    /// ⛔ "AT EVERY RATE STRICTLY INSIDE THE BAND THE BEHAVIOUR IS BIT-IDENTICAL" IS WHAT THIS
    /// LINE SAID FOR ONE COMMIT, AND IT IS FALSE AS A UNIVERSAL. Swept at 0.25/min steps, the
    /// reported rate moves at 4.0–4.75 and at 20.5–30: near an edge a breath cycle's JITTER can
    /// push an interior rate's implied period outside the old band, so the repair reaches inward
    /// from both ends. What is true is the narrower claim the tests actually pin: at 5, 6, 10,
    /// 15 and 20/min — the rates the product targets — the sweep is bit-identical, and where it
    /// does move it moves the right way. Worst |error| over 360 phases, before → after: 4.25/min
    /// 0.4226 → 0.3661 · 24/min 4.9626 → 2.2217. Of the 43 rates that change, 36 improve, 6 are
    /// bit-identical in worst error (4.5 · 4.75 · 20.5 · 20.75 · 21.0 · 21.25 — the REPORT moves
    /// at 27–70 phases each but the extreme does not) and ONE is worse: 21.5/min, by 0.0108/min.
    /// So: an edge repair that reaches inward, not a retune — and stating it as "nothing else
    /// changed" was the kind of claim this file exists to retract.
    ///
    /// ⛔ THAT 0.0108 READ "0.0044" IN FOUR PLACES AT ONCE (here, the test header, `CLAUDE.md`,
    /// the commit body) BECAUSE I SAMPLED 90 PHASES AND CALLED IT A SWEEP. In the same paragraph
    /// that retracts an under-swept claim. Every |error| figure in this file is over all 360.
    /// ⛔ AND THE RETRACTION FIXED THREE OF THE FOUR SITES IT NAMES: `TheBandEdgeIsMeasurableTests`
    /// still read 0.0044 for another commit. A correction that lists its own blast radius has to
    /// be applied at every entry on the list, in the commit that writes the list.
    ///
    /// ⚠️ THE LOW EDGE IS THE WORSE ONE and was found only by sweeping it. The review that
    /// raised this named 30/min; 4/min is four times worse and nobody had looked. When a bound
    /// turns out to be wrong at one end, measure the other end before writing the fix.
    ///
    /// ⚠️ WIDENING THIS DOES NOT LET NOISE IN, and it is worth knowing why before touching it:
    /// the band is not the noise filter. `envConf` is — a hand with no respiratory swing has no
    /// envelope, so `confidence` stays far under the publish gate no matter what the band says.
    /// `TheBandEdgeIsMeasurableTests.testAStillHandStillPublishesNothing` holds that, and it is
    /// the test to read before changing this constant.
    ///
    /// ⛔ IT SHIPPED AT 1.2 FOR ONE COMMIT, WITH THE JUSTIFICATION "roughly one jittered beat of
    /// slack at either end". That sentence described neither end — at a 60 bpm pulse one beat is
    /// 1 s, and 1.2 buys +3.0 beats at the slow end and −0.33 at the fast one. Worse, it was
    /// ~180× more slack than the repair needs at a 60 bpm pulse, and the surplus was not free.
    ///
    /// ⛔ AND THEN 1.02 WAS FITTED TO THAT ONE PULSE. The replacement claimed "the smallest
    /// tolerance that removes the silence at BOTH edges is 1.00111, so 1.02 is the minimum with
    /// ~18× margin". Both halves are properties of the FIXTURE, not of the estimator. The whole
    /// sweep ran at `meanBPM: 60`, and 60 is a DEGENERATE pulse at the low edge: 4/min is exactly
    /// 15 beats per breath cycle there, so the crossing lands on the boundary period dead-on and
    /// an infinitesimal tolerance clears it. **Sixteen of the 66 integer pulses in 45…110 need
    /// more than 1.02**, and at those pulses 1.02 removed NONE of the silence — 19 of 360 phases
    /// still silent at pulse 46, 21 at 50, 27 at 62, 32 at 70, 44 at 90, exactly as before #424.
    ///
    /// **Lesson, and it is the sibling of the one three paragraphs up:** that one says "when a
    /// bound is wrong at one END, measure the other END". This one says measure the other AXIS.
    /// A phase sweep at a single pulse is a sample, however many phases it has.
    ///
    /// ⛔ TWO CLAIMS IN THE PARAGRAPH ABOVE WERE THEMSELVES WRONG AND ARE STRUCK. (1) "The
    /// published fix worked at 60 bpm and 110 bpm (the two degenerate pulses) and nowhere else."
    /// 110 is NOT degenerate — 4/min is 27.5 beats per cycle there; its requirement (1.0182)
    /// merely happens to sit just under 1.02. And "nowhere else" is off by 33: of the 49 integer
    /// pulses in 45…110 with pre-#424 low-edge silence, 1.02 removed it at 33 and left 16.
    /// (2) "The requirement is ≈ 1 + 1/(2N), i.e. **1 + 2/pulse**." That is the WORST CASE, not
    /// the requirement — it is attained only when N's fractional part is 0.5. Measured against
    /// the formula: pulse 45 (N = 11.25) needs **1.0** where the formula says 1.0444; pulse 55
    /// (13.75) needs 1.0185 against 1.0364; pulse 84 (21, degenerate) and 100 (25, degenerate)
    /// need 1.0. The formula is a safe upper bound and is quoted as one from here on.
    ///
    /// ⛔ AND THE MECHANISM WAS STATED BACKWARDS IN THE TEST FILE THAT DEFENDS THE PULSE SET.
    /// A degenerate pulse is not the SAFE case, it is the knife-edge one: the crossing lands on
    /// the boundary period exactly, so pre-#424 it went silent at two thirds of all phases
    /// (60 → 240 of 360, 84 → 223, 100 → 214) and any ε > 0 clears it. `TheBandHolds…Tests`
    /// called those three "degenerate … zero silence even pre-#424" and used them as the control
    /// against cherry-picking. Both halves false, and the control did not exist.
    ///
    /// ⭐ SO THE SHIPPED VALUE IS DERIVED FROM A MEASURED FLOOR PLUS MARGIN. The floor is the
    /// per-pulse requirement at 4/min, bisected over 360 phases: 1.0595 at pulse 34, 1.0532 at
    /// 38, 1.0481 at 42, 1.0439 at 46, and 1.0674 at pulse 30. **1.06 covers every pulse from
    /// 31 up**; 30 would need 1.0674 and is outside what this constant can buy. The high edge
    /// never binds — its worst requirement over 45…110 is 1.0127, at pulse 61.
    ///
    /// ⛔ AN EARLIER DRAFT CALLED THIS "a WINDOW" WITH AN UPPER WALL AT 1.067, MEASURED AS THE
    /// POINT WHERE THE 4/min REPORT DROPS FROM 3.99993 TO 3.8197. That wall is a property of the
    /// 60 bpm FIXTURE, not of measurement quality: it is where a 60 bpm pulse starts accepting
    /// the 16-beat quantisation of its own 15 s cycle — the same slow neighbour the fix
    /// deliberately admits at every non-degenerate pulse, and which is already admitted at 1.055
    /// (pulse 42's lowest report is 3.8120 at 1.055 and unchanged at 1.068, 1.08 and 1.1). Naming
    /// a fixture artefact as one side of a window made the choice look better-determined than it
    /// is. There is one measured wall, at the bottom, and the value sits above it with margin.
    ///
    /// ⭐ AND THAT MARGIN IS WHY 1.055 WAS RAISED TO 1.06 IN THE FOURTH ROUND. 1.055 cleared the
    /// binding requirement (1.0532 at pulse 38) by **0.0018** — 0.17 %, inside the noise of a
    /// re-derivation on a slightly different generator — and it did NOT cover pulse 34. 1.06
    /// covers every pulse ≥ 31 with 0.0005 to spare over the worst one. Measured cost of the
    /// raise: **none.** Worst |error| at 5, 6, 10, 15, 20, 4.25, 21.5 and 24/min is bit-identical;
    /// the 4/min report at pulses 42, 60 and 90 is bit-identical (3.81204 / 3.99993 / 3.91234);
    /// health-writable counts are identical (214 / 120 / 210 of 360); the 3.5/min out-of-band body
    /// publishes at the same 61 phases with the same 37 in `respiratoryRange` and never on the
    /// rail; the stale window is identical (22.687 s at 3.5/min); and the still-hand confidence is
    /// unchanged. It buys margin and four bpm of bradycardia for nothing measurable.
    ///
    /// ⭐ AND THE REAL ARGUMENT FOR THE WIDER VALUE IS NOT THE SILENCE, IT IS THE BIAS — found
    /// only by measuring the pulse axis, and the strongest thing in this doc. The narrow band was
    /// a ONE-SIDED filter at the low edge: of the two quantised periods a 4/min cycle can land on,
    /// it accepted only the one that runs FAST and threw the slow one away. So the surviving
    /// population was skewed high. Mean report on a body breathing exactly 4.0/min, over all 360
    /// phases, 1.02 → 1.06: pulse 42 **+0.259 → +0.050**, 46 +0.239 → +0.049, 62 +0.190 → +0.046,
    /// 90 +0.152 → +0.042. A factor of 4–5 on the error carried by the whole published
    /// population, at every pulse except the degenerate fixture. The silence was the symptom that
    /// made someone look; the bias is what was wrong.
    ///
    /// ⛔ THAT FACTOR IS THE CONSUMER-PATH ONE AND WAS QUOTED TO JUSTIFY A HEALTH-PATH TRADE.
    /// The ⛔ below defends losing ~40 % of the health-writable samples with "each ~5× closer to
    /// the truth". Wrong population: what reaches Apple Health is the `≥ 4.0` subset, and
    /// `HealthWritePolicy` truncates at almost exactly the mean of the corrected distribution, so
    /// the surviving samples keep most of the old high bias. Mean bias of the WRITTEN subset,
    /// 1.02 → 1.06: pulse 42 +0.2592 → **+0.1522** (1.70×), 46 +0.2393 → +0.1430 (1.67×),
    /// 62 +0.1904 → +0.1212 (1.57×), 90 +0.1524 → +0.1093 (1.39×). **On the health path the
    /// improvement is 1.4–1.7×, not 5×** — still an improvement, and still a defensible trade,
    /// but the number that defends it has to be measured on the population that pays for it.
    ///
    /// ⚠️ The cost axes do not move AT THE FIXTURE PULSE between 1.02 and 1.06 — checked before
    /// choosing, not after: the out-of-band 3.5/min body publishes at 61 phases with 37 landing in
    /// `HealthWritePolicy.respiratoryRange` (the 37 is identical to pre-#424; the 61 is NOT — that
    /// is the widened band answering more often, and the first version of this line let one
    /// "identical" cover both), the stale window is 22.687 s (identical), every interior
    /// worst-error is identical to the last digit, and the still-hand counterweight is unchanged
    /// under 1.0, 1.02, 1.055 and 1.06 alike. What DOES move is the silence: zero at 4/min and
    /// 30/min at every pulse from 37 to 118, and the worst 4/min error at pulse 46 falls
    /// 0.7696 → 0.3877.
    ///
    /// ⛔ ONE COST DOES MOVE, AND IT ONLY EXISTS OFF THE FIXTURE — so the paragraph above would
    /// have hidden it if it had been left saying "the cost axes do not move". Because the report
    /// now lands slightly UNDER 4.0 at those pulses, and `HealthWritePolicy` DROPS rather than
    /// clamps, the number of health-writable samples on a 4/min body falls with the tolerance:
    /// pulse 42 **344 → 214** of 360, 46 341 → 217, 62 333 → 219, 90 316 → 210. Fewer samples,
    /// each ~1.7× closer to the truth on the written population (see the ⛔ above — the "~5×" this
    /// sentence carried for one commit was the consumer-path figure, measured on a different
    /// population than the one paying the cost) — a trade, and a defensible one, but it is a trade
    /// and it is written down. The clean end-state is the follow-up already named two ⛔s down
    /// (widen `respiratoryRange` or round at the writer); until then this is the honest reading.
    ///
    /// ⛔ AND THE SURPLUS BOUGHT A FABRICATION. Paired with the rate clamp the first version
    /// also shipped, a body breathing BELOW the band read as a confident rail: at 3.5 breaths/min
    /// the estimator published at 360 of 360 phases with `ratePerMinute` exactly 4.000 at 358 of
    /// them, where before #424 it published at 37 and never at the boundary. That value is not a
    /// measurement, and `HealthWritePolicy.respiratoryRange` (4...40) CONTAINS it — so a
    /// saturated number would have been written to Apple Health as a respiratory sample, and
    /// learned into `PerformerSignature`. The clamp is gone (the reported rate is now the raw
    /// EMA) and the tolerance is small enough that the accept floor sits at 3.774/min. The lesson
    /// is not "clamps are bad": it is that a saturating output on a measurement path invents data
    /// at the rail, and the reach of that invention is exactly this constant.
    ///
    /// ⛔ AND REMOVING THE CLAMP MOVED THE HEALTH-PATH PROBLEM RATHER THAN ENDING IT — the first
    /// version of this ⛔ claimed the range claim "survives in practice", which is not what the
    /// downstream code does. `HealthWritePolicy.values(for:)` DROPS an out-of-range respiratory
    /// value (`respiratoryRange.contains(br) ? br : nil`); it does not clamp. At a body breathing
    /// exactly `minRate` the report lands below 4.0 — by 0.000075 at 240 of 360 phases AT THE
    /// 60 bpm FIXTURE, and by up to 0.21 off it (3.793 at pulse 38) — so those
    /// measurements are silently discarded on the write path — at the very rate this whole fix
    /// is named after. That is the RIGHT trade (a dropped sample beats an invented one) and it
    /// is a decision, not a side effect: if the edge should reach Apple Health, widen
    /// `respiratoryRange` or round at the writer, deliberately and in its own slice.
    ///
    /// ⚠️ IT DOES STILL COST SOMETHING, AND THE COST IS STALE-WINDOW, NOT ACCURACY. Accepting a
    /// period the old band rejected also keeps `lastCrossT` and `periodEMA` alive on bodies just
    /// outside the band, so a published rate survives longer after the beats stop. Longest
    /// survival past the last beat, bisected over all 360 phases: at 3.5 breaths/min 19.776 s
    /// before → 40.857 s at the shipped-for-one-commit 1.2 → 22.687 s at 1.06 (and the same
    /// 22.687 at 1.055); at 4.0/min 32.390 → 36.360 → 36.360 s. That is the
    /// second reason the tolerance is not 1.2 — the freshness term is what bounds this, and a
    /// wide band hands it a longer expected period to be patient with. (⛔ The first version
    /// wrote 20.0 / 39.0 / 22.5 and 32.5 / 36.5 / 36.5, four of them the fine value rounded UP
    /// to a 0.5 grid, one rounded DOWN, and 39.0 reproducible under no convention at all. The
    /// grid was my search step, not a measurement. ⛔ AND THE "BISECTED" REPLACEMENT WROTE
    /// **22.4** WHERE THE FULL 360-PHASE BISECTION GIVES **22.687** — measured over 90 phases and
    /// written down as if it were the sweep, in the same parenthesis that retracts a grid-rounded
    /// number. Worse, 22.687 rounds DOWN to 22.5 on a 0.5 grid, so the value the retraction called
    /// wrong was the correct grid rounding and the "correction" moved further from the truth.
    /// The numbers above are the full sweep, three digits: 19.776 / 40.857 / 22.687 and
    /// 32.390 / 36.360 / 36.360.)
    private static let bandTolerance = 1.06

    // MARK: State
    private var lastT: Double?
    private var trend = 0.0          // slow HR baseline (EMA)
    private var smooth = 0.0         // band-passed respiration signal
    private var prevSmooth = 0.0
    private var env = 0.0            // |smooth| envelope (normalization)
    private var lastCrossT: Double?  // last upward zero-crossing time
    private var periodEMA = 0.0      // smoothed respiration period (s)
    private var crossingCount = 0

    // MARK: Outputs
    /// Breath amplitude [0,1] — 1 = inhale peak (lungs full). 0.5 when no clear
    /// respiratory oscillation is present (drives the ball to mid-rest).
    public private(set) var amplitude = 0.5
    /// Estimated breathing rate (breaths/min); 0 until a cycle has been measured.
    public private(set) var ratePerMinute = 0.0
    /// How clear the respiratory oscillation is [0,1] — the UI should only trust the
    /// measured ball above a threshold and otherwise fall back to the paced guide.
    public private(set) var confidence = 0.0

    public init() {}

    /// Feed one instantaneous heart-rate sample (bpm) at time `t` (seconds).
    /// Out-of-range or non-finite samples and time gaps are ignored safely.
    public mutating func ingest(heartRate hr: Double, at t: Double) {
        guard hr.isFinite, hr > 20, hr < 240, t.isFinite else { return }

        guard let last = lastT else {       // first sample seeds the baseline
            lastT = t; trend = hr; smooth = 0; prevSmooth = 0
            return
        }
        let dt = t - last
        guard dt > 0 else { return }
        lastT = t
        guard dt < 5 else { return }        // long gap: skip this step (keep state)

        // High-pass: subtract the slow baseline.
        let aTrend = 1 - exp(-dt / Self.trendTau)
        trend += aTrend * (hr - trend)
        let hp = hr - trend

        // Low-pass the high-passed signal → respiration band.
        let aSmooth = 1 - exp(-dt / Self.smoothTau)
        prevSmooth = smooth
        smooth += aSmooth * (hp - smooth)

        // Decaying envelope of |smooth| for normalization.
        let aEnv = 1 - exp(-dt / Self.envTau)
        env += aEnv * (abs(smooth) - env)
        let e = Swift.max(env, 1e-6)

        // Normalized amplitude [0,1]; 0.5 with no oscillation. 1.4 ≈ peak/mean-abs
        // of a sine, so a clean breath swings roughly the full range.
        let norm = Swift.max(-1.0, Swift.min(1.0, smooth / (e * 1.4)))
        amplitude = 0.5 + 0.5 * norm

        // Upward zero-crossing marks one respiration cycle → rate.
        if prevSmooth <= 0, smooth > 0 {
            if let lc = lastCrossT {
                let period = t - lc
                let r = period > 0 ? 60.0 / period : 0
                // Accept into a band wider than the one we report in — see `bandTolerance`.
                if r >= Self.minRate / Self.bandTolerance, r <= Self.maxRate * Self.bandTolerance {
                    periodEMA = periodEMA == 0 ? period : periodEMA + 0.3 * (period - periodEMA)
                    // ⛔ DO NOT CLAMP THIS. The first version of #424 clamped to
                    // [minRate, maxRate] to keep the reported range identical, and that turned
                    // the boundary into a rail that INVENTS a measurement — see the second ⛔ on
                    // `bandTolerance`. The report is the raw EMA, so the only thing bounding it is
                    // the ACCEPT band on the line above: `[3.774, 31.8]`. It leaves the ADVERTISED
                    // band in both directions, and by more than a hair at some pulses — measured
                    // worst +1.42/min over `maxRate` (pulse 63) and 0.21 under `minRate`
                    // (pulse 38). ⛔ This comment said "+0.074 … depending on the pulse" for one
                    // commit: a two-pulse measurement wearing a pulse-axis qualifier, which is
                    // worse than an unqualified one because it reads as swept. The bounds live on
                    // `minRate`; the tests are `TheBandEdgeIsMeasurableTests` +
                    // `TheBandHoldsAtEveryRestingPulseTests`.
                    if periodEMA > 0 { ratePerMinute = 60.0 / periodEMA }
                    crossingCount += 1
                }
            }
            lastCrossT = t
        }

        refreshConfidence(at: t)
    }

    /// Age `confidence` forward to `t` WITHOUT feeding a beat.
    ///
    /// ⭐ THE STALENESS TERMS ONLY RUN WHEN A BEAT ARRIVES, and that is not the same thing as
    /// "when time passes". `ingest` is the only writer of `confidence`, so a host that keeps
    /// publishing while the beat supply dries up freezes the last value indefinitely — the
    /// very latch the freshness term and the envelope veto were written to prevent, reached by
    /// a path neither of them can see.
    ///
    /// It is a real device state, not a thought experiment: `CameraAnalyzer` returns early
    /// without touching `rrIntervals`/`beatTimes` when it finds fewer than three peaks, while
    /// `fallbackBPM` keeps `estimatedBPM` and `bpmConfidence` alive off the autocorrelation.
    /// The analyzer names that case itself ("peaks<3 with a strong acf → rounded waveform").
    /// So the publisher goes on emitting bio frames at ~1 Hz with ZERO beats reaching here,
    /// and a confidence of 1.0 earned a minute ago keeps certifying a breathing rate.
    ///
    /// Hence the pull: the host ages on every publish that carries a live measurement, and
    /// staleness becomes a function of the clock rather than of the supply. Nothing else moves
    /// — the filters, the envelope and the cycle count are untouched, so a beat that arrives
    /// later behaves exactly as before.
    ///
    /// ⚠️ "Every publish" is deliberately NOT what the caller does, and the first version of
    /// this line said it did. THREE paths through `CameraRPPGBioPublisher`'s 1 Hz block skip
    /// the ageing, and a future reader deciding "can this estimator go stale?" needs all three:
    /// (1) the `shouldPublish` else-branch re-emits the last good frame for up to
    /// `bioHoldTicks` — bounded, and it carries the held frame's OWN timestamp, so
    /// timestamp-dedup consumers treat it as a no-op; (2) the `inboundRateEMA` guard `continue`s
    /// past the whole block; (3) the `guard tick % 10 == 0, let bus = self.bus` at the top of
    /// the block — `bus` is `weak`, so a released `EngineBus` also `continue`s. (2) and (3) are
    /// benign for the same reason: a claim that is never emitted cannot go stale.
    /// ⛔ The first version named only (1); the commit that corrected it named only (1) and (2)
    /// while its own summary bullet read "named two of three". An exhaustiveness claim has to be
    /// counted against the source each time it is edited, not extended by one.
    ///
    /// ⚠️ Nor can it be stated flatly that ageing never RAISES confidence — it holds for the
    /// case that matters and fails in two corners. (1) A fresh estimator with `lastT == nil`
    /// passes the guard trivially and lands on ~3.3e-7 instead of 0: `env` is 0, so `envConf`
    /// is the 1e-6 floor over 1.5. Six orders of magnitude below the 0.4 gate, and a rate of 0
    /// blocks it anyway. (2) `age(to:)` does NOT advance `lastT`, so a caller that ages
    /// backwards after ageing forwards re-evaluates at the earlier time and comes back up.
    /// The shipped caller passes monotonic `systemUptime`, so neither is reachable today.
    ///
    /// `t` must be on the same clock as `ingest` (the camera path uses
    /// `ProcessInfo.processInfo.systemUptime`). Ageing to a time before the last beat is
    /// refused rather than clamped: it means the caller mixed clocks, and silently accepting
    /// it would hide that.
    public mutating func age(to t: Double) {
        guard t.isFinite, t >= (lastT ?? t) else { return }
        refreshConfidence(at: t)
    }

    /// The confidence expression, evaluated at time `t`. Split out of `ingest` so `age(to:)`
    /// can run it without a sample; the arithmetic is unchanged.
    private mutating func refreshConfidence(at t: Double) {
        let e = Swift.max(env, 1e-6)

        // Confidence: meaningful swing AND a few consistent cycles seen — but read the veto
        // below before trusting that sentence: past four crossings the count term is dead and
        // the expression is `envConf * freshness` exactly.
        let envConf = Swift.min(1.0, e / 1.5)                 // ~1.5 bpm RSA = decent
        // ⭐ THE ENVELOPE VETOES THE COUNT, so the whole expression obeys one stated
        // invariant: `confidence <= envConf * freshness`. We may never claim more certainty
        // than the size of the swing supports, however many cycles we have counted.
        //
        // Without it the freshness term below is INERT against the failure that actually
        // ends a long take. Freshness keys on `lastCrossT`, so it only fires when the
        // crossings STOP — a flat heart rate. But a fingertip that drifts, or a hand that
        // relaxes, does not produce a flat trace: it produces a small noisy one, which keeps
        // manufacturing crossings inside the 4…30/min band. Then `crossingCount` goes on
        // rising, `lastCrossT` stays fresh, and confidence sits on the 0.5 floor while the
        // swing that justified it is gone. Simulated on the shipped constants — 60 s of clean
        // 6/min RSA followed by 90 s of a 0.15 bpm wobble — confidence held at 0.524 (gate
        // OPEN) with an envelope of 0.071, publishing a fabricated 11.9 breaths/min. With the
        // veto the same series ends at 0.048 and the gate closes.
        //
        // ⚠️ IT COSTS THE SHALLOWEST BREATHERS, and that is a deliberate trade, not an
        // oversight. Measured on 60 s of clean 6/min: an RSA swing of ±1.2 bpm (2.6 bpm
        // peak-to-peak) reads 0.448 (still measured), ±1.0 (2.1 p-p) reads 0.373 — below the
        // 0.4 gate, where the old blend would have said 0.686. The gate closes below ±1.07 at
        // phase 0 and ±1.28 at the worst phase. Such a body falls back to the paced guide
        // instead of driving the ball. That is the designed fallback; narrating a rate read
        // out of noise is not, and is the worse failure of the two.
        //
        // ⛔ The ± matters and the first version of this note omitted it. RSA is conventionally
        // quoted PEAK-TO-PEAK, so a bare "1.0 bpm" understates the cost by a factor of two to
        // anyone applying the convention. At the 6/min resonance rate — where the whole point
        // is that RSA is MAXIMISED — a healthy adult sits far above 2.6 bpm p-p, which is why
        // the trade is defensible on signal grounds and not merely on principle.
        //
        // ⚠️ AND IT DOES NOT YET DO THIS ON THE DEVICE. `CameraAnalyzer` takes peak times at
        // whole-sample resolution (no sub-sample interpolation) and the camera runs at
        // 7.5–15 fps, so every interval is quantised to one frame period — 1.6 bpm RMS at
        // 15 fps and 3.2 at 7.5 (peaks of ±4/±8), against the 1.5 bpm scale this floor is set
        // to. A still hand can therefore clear the gate on quantisation alone. (⛔ The first
        // version quoted only the PEAK and called it "several times" the floor. A floor
        // responds to the RMS, and the honest ratio is 1.1–2.2×, not 3–5×. Right direction,
        // overstated — and overstating the case for a fix is how a fix gets scoped wrong.)
        // The invariant here is right and strictly better than the old blend, but "separates a
        // shallow breather from noise" only becomes true of the shipped path once peak timing
        // is sub-sample — and #421 has since measured that naive 3-point parabolic
        // interpolation is WORSE than whole-sample at this signal's SNR, so that is not a
        // one-line change either. Do not quote this comment as evidence that it already works.
        let countConf = Swift.min(Swift.min(1.0, Double(crossingCount) / 4.0), envConf)

        // ⭐ FRESHNESS — a reported rate is only as good as the last cycle that produced it.
        //
        // `crossingCount` is monotonic and `ratePerMinute` holds its last value forever, so
        // without this term `countConf` pins at 1.0 after four cycles and `confidence`
        // acquires a permanent floor of 0.5 — above every consumer gate in this repo
        // (`CameraRPPGBioPublisher` uses 0.4). The estimator would go on certifying a rate
        // long after the breathing that produced it stopped.
        //
        // This was HARMLESS while the estimator was rebuilt on every publish: state could not
        // outlive one 10 s window. #343 made it live for a whole take, and in doing so turned
        // a bounded staleness into a latch. Measured on a 60 s 6/min series followed by a
        // perfectly flat heart rate: confidence settled at exactly 0.500 and never moved, so
        // "6.0 breaths/min, measured" was published indefinitely with no breathing at all.
        //
        // It is HALF the answer. Freshness catches the take that ends in a flat trace; the
        // envelope veto above catches the take that ends in a noisy one, where crossings keep
        // arriving and nothing here ever goes stale. Neither substitutes for the other.
        //
        // Grace is 1.5 expected periods (a real cycle always lands inside that), then a linear
        // fade to zero over the same span. The pipeline lag is SUBTRACTED FROM THE MEASURED
        // STALENESS rather than added to the grace — see below. Before the FIRST crossing there
        // is nothing to be stale about and the term is inert, which is why a fresh estimator
        // still behaves exactly as it did. The fallback period is the slowest supported rate:
        // with no measured period yet, assuming the shortest one would expire a slow breather.
        //
        // ⭐ THE ALLOWANCE PAYS FOR A DELAY THIS TERM CANNOT SEE. While the estimator was only
        // refreshed from inside `ingest`, the since-crossing age was measured at a BEAT time.
        // `age(to:)` moved the evaluation to wall-clock now, which adds the camera pipeline
        // between the beat and this call. That is measurement latency, not staleness, and
        // charging it to the breather is wrong. Swept over all 360 whole-degree breathing
        // phases at a 2.5 s lag: at 28 breaths/min the worst phase read confidence 0.2582
        // WITHOUT the allowance — under the publisher's 0.4 gate, so a fast breather's own
        // measurement flickered off — and 0.4871 with it. (Pre-#424 those were 0.2837 and the
        // same 0.4871; the no-allowance case moved because the acceptance band did, the
        // allowance case did not move at all.) The cost at the other end is
        // negligible because the envelope veto dominates there: the 60 s-then-flat series that
        // `testAMeasuredRateExpiresWhenTheBreathingStops` drives ends at 0.0054 instead of
        // 0.0019, both far under the gate.
        //
        // ⛔ SUBTRACT FROM THE MEASURED AGE, DO NOT ADD TO `grace` — the first version added it
        // and the difference is not cosmetic, because `grace` appears TWICE: once as the flat
        // window and once as the fade denominator. Adding a constant there therefore also
        // STRETCHES the fade, which nothing about a fixed measurement lag justifies.
        //
        // The exact statement is analytic, not measured: subtracting A shifts the whole
        // freshness curve later by EXACTLY A at every rate, while adding A to a grace that
        // appears twice shifts it by A and then scales the fade by (1 + A/grace) — so the two
        // forms agree only where the fade has not started. At 6/min the flat window ends
        // 15 s after the crossing either way; the 0.4 crossing is what separates them. Time
        // from the last crossing to `confidence < 0.4`, PHASE 0, this file's own generator,
        // before / added 2.5 / subtracted 1.8: 6/min 24.00 → 28.00 → 25.80 s · 15/min
        // 9.06 → 12.83 → 10.86 s · 28/min 4.44 → 8.04 → 6.24 s. Subtracting buys the identical
        // fast-end protection (0.4871 at every phase — the same number to four decimals) for a
        // smaller extension of the stale window at every rate.
        //
        // ⚠️ THE 28/min ROW MOVED WITH #424 (it read 4.53 → 8.14 → 6.34 on the narrower
        // acceptance band); the 6 and 15/min rows are unchanged to three decimals, because
        // neither rate has a crossing anywhere near a band edge. The SHAPE of the comparison —
        // subtracting extends the stale window less than adding, at every rate — is what the
        // paragraph argues, and it survives the shift intact.
        //
        // ⛔ AND THE PHASE HAD TO BE NAMED. (Everything in this ⛔ and the next one is quoted on
        // the PRE-#424 acceptance band, because both are about what an earlier draft of this
        // comment claimed — restating them on today's band would make the retraction unreadable
        // against the drafts it retracts.) The first version of that table wrote 24.1 / 28.1 /
        // 25.9 for the 6/min row and 4.7 / 8.4 / 6.5 for the 28/min row, with no phase given.
        // The 28/min row reproduces only near phase 19–20°, the 15/min row near 2°, and the
        // 6/min row reproduces at NO phase at all — the achievable "before" values jump
        // 24.001 → 24.247 and 24.1 falls in the gap. Three lines above, this same paragraph
        // retracts a figure for exactly this reason ("when a table has two minima, name which
        // one"). A phase-free table is the same defect with more digits.
        //
        // ⛔ AND THE FIRST VERSION MISREAD ITS OWN RETRACTION. It said "an earlier draft quoted
        // 0.313 off a 180-phase sweep". No phase set produces 0.313 here: 180 phases give
        // 0.2841 and 360 give 0.2837. The 0.313 was the confidence at the phase with the worst
        // FRESHNESS, read out of the wrong column of my own table — so the cautionary example
        // in a paragraph about hand-picked figures was itself a number nobody could reproduce.
        // The lesson is narrower than "sweep": when a table has two minima, name which one.
        //
        // ⚠️ ABOVE 28.7/min A GROWING SHARE OF PHASES STILL FAILS THE GATE, and the first
        // version blamed Nyquist for it. That was written from ONE phase and the sweep refutes
        // it: at 30 breaths/min the measured rate WAS ~30 at 244 of 360 phases, 0 at 61, ~10 at
        // 53, and one phase each at 10.3 and 18.8 — the modal answer is the RIGHT one. So the
        // residual is a CONFIDENCE problem of the same lag/freshness kind, not a sampling
        // limit, and neither this allowance nor a larger one closes it (29/min worst phase at
        // the same 2.5 s lag: 0.000 before, 0.1685 with subtract-1.8, 0.2572 with subtract-2.5,
        // 0.3134 under the previous commit's add-2.5 — all under the gate).
        //
        // ⭐ ONE OF THE TWO CAUSES UNDER THAT HISTOGRAM IS NOW FIXED and this paragraph would
        // otherwise send the next reader after it again. It listed two, both "registered on the
        // board, not fixed here": `lastCrossT` is quantised to a beat (#423, still open), and
        // `r <= Self.maxRate` REJECTED a crossing whose jitter put it a hair over 30/min instead
        // of accepting the measurement into a wider band than it reports — at every one of those
        // 61 phases, EVERY crossing was rejected with r = 30.000000…x, so that cause was
        // measured, not inferred. #424 did exactly that widening, and the same sweep now reads
        // ~30 at 358 of 360 phases with NO zeros — the 61-strong zero bucket and the 53-strong
        // half-rate bucket are both gone, and only the two stragglers at 10.3 and 18.8 survive
        // (which is why they are worth naming). The confidence residual above 28.7/min is NOT
        // fixed; the 29/min column is measured on today's band and still sits under the gate.
        //
        // ⛔ THE HISTOGRAM ABOVE READ "244 / 61 / 54" FOR ONE COMMIT AND SUMMED TO 359. The
        // ~10 bucket is 53; the two stragglers at 10.3 and 18.8 belonged to no named bucket and
        // were silently dropped. A partial reading, quoted inside the paragraph that retracts a
        // partial reading — the same shape, one level down. If a partition is offered as
        // evidence, its parts have to add up to the sweep.
        let expectedPeriod = periodEMA > 0 ? periodEMA : 60.0 / Self.minRate
        let grace = expectedPeriod * 1.5
        // NAMED FOR WHAT IT IS: the raw age of the crossing, versus the age this term is
        // allowed to CHARGE the breather after the pipeline's own delay is paid off. The
        // earlier `sinceCross` held the raw value and then held the reduced one, which is
        // exactly the stale-name trap this repo has already paid for once (#373/#374).
        let rawSinceCross = lastCrossT.map { t - $0 } ?? 0
        let chargeableSince = Swift.max(0.0, rawSinceCross - Self.pullLagAllowance)
        let freshness = chargeableSince <= grace
            ? 1.0
            : Swift.max(0.0, 1.0 - (chargeableSince - grace) / grace)

        confidence = Swift.max(0.0, Swift.min(1.0, 0.5 * envConf + 0.5 * countConf)) * freshness
    }

    /// Clear all state (e.g. when the camera signal drops or a session restarts).
    public mutating func reset() { self = RespirationEstimator() }
}
