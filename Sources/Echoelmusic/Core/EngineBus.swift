//
//  EngineBus.swift
//  Echoelmusic
//
//  Central typed pub/sub for biofeedback samples, controller events
//  (MPE + air CCs), and discrete bio events. Hybrid isolation model:
//
//    Control plane (latest snapshots for SwiftUI observation):
//        @MainActor @Observable, single-source-of-truth for views.
//
//    Data plane (audio-thread consumers, ≤120 Hz bio producers):
//        Lock-free SPSCQueue per topic, allocation-free at the
//        consumer side.
//
//  Publishers run at sub-kHz rates (Oura ≤4 Hz, HealthKit ≤1 Hz,
//  CoreMIDI ≤sub-kHz) and may dual-update both planes safely.
//  Audio-thread *consumers* only read from the queues — they never
//  publish through this surface.
//

import Foundation
#if canImport(Observation)
import Observation
#endif

// MARK: - Continuous biosignal frame

/// One snapshot of a bio source's normalized, low-rate channels.
/// All values are normalized per master prompt §2 except where noted.
public struct BioSampleFrame: Sendable, Equatable {

    /// `CFAbsoluteTime` (seconds since the 2001 reference date, i.e.
    /// `CFAbsoluteTimeGetCurrent()` / `Date.timeIntervalSinceReferenceDate`) at
    /// which this frame was RECEIVED by its publisher — NOT mach_absolute_time, and
    /// NOT the underlying measurement time. Every publisher stamps this same clock at
    /// receipt (see the freshness contract at `freshBio`/`usableBio` below) so the
    /// age comparison is valid across BLE / rPPG / HealthKit / Demo sources.
    public let timestamp: TimeInterval

    /// Heart rate in BPM. Range [40..200], unclamped here.
    public let heartRateBPM: Float

    /// HRV (rMSSD) normalized to [0..1]. `0` means **not measured**, not "minimum
    /// variability" — a Watch before its first SDNN sample, a camera before it locks.
    /// Anything that DISPLAYS this must render 0 as "—" (see `BioStripView`); anything
    /// that MODULATES with it should read `hrvForSound` instead.
    public let hrvNormalized: Float

    /// `hrvNormalized` for MODULATION targets: unmeasured (0) becomes a neutral 0.5.
    ///
    /// Why this exists as one property instead of a ternary at each call site: 0 is not
    /// a neutral value in any of the HRV mappings, it is an EXTREME. Feeding a literal 0
    /// asserts "minimum variability" — it darkens timbre, and in `BioComposer` it reads
    /// as maximum sympathetic load and composes a busier, more agitated take precisely
    /// when the app knows nothing about the body. That is a worse fabrication than the
    /// placeholder this convention replaced. The rule was first written inline at two
    /// synth voices and drifted immediately — a review sweep found it missing at every
    /// other value-mapping consumer. Keeping it in one place is what stops that again.
    ///
    /// **Applies to VALUE mappings only.** Where 0 already means "no contribution",
    /// the raw value is the CORRECT one and substituting 0.5 would invent a permanent
    /// half-depth offset out of nothing. Two such places:
    /// - `BioComposer.hrvHumanize` — guards `span > 0`, so no HRV means it touches
    ///   nothing. Verified: it is a discrete op the user invokes by name, and a
    ///   neutral 0.5 there would present seeded jitter AS their variability.
    /// - `FXModulation.offset` / `VisualModulation`, but **only on the unipolar
    ///   branch** (`signal·depth·span`), which is also why `contributions` feeds
    ///   signal 0 for a missing frame.
    ///
    /// The bipolar branch is `(signal·2−1)·depth·span·0.5`, where signal 0 is the FULL
    /// NEGATIVE excursion — so a bipolar route on a channel the body never reported used
    /// to apply a permanent maximal offset. Both halves of that are now CLOSED, and
    /// neither was fixed here, deliberately:
    ///
    /// - A missing frame never reached the audio: `FXBioModulator` treated a bio route
    ///   with no frame as contributing nothing, so the base value stood. It DID reach
    ///   the ~10 Hz `contributions` readout, which showed that excursion for a route
    ///   contributing nothing; fixed by forcing the offset to 0.
    /// - A frame present but carrying a STRUCTURAL zero DID reach the audio, because
    ///   `ModSource.rawValue` reads the RAW fields and `FXModRoute` defaults to
    ///   `bipolar: true`. It was not a corner case: the FX view's "add route" button
    ///   always creates a `.bio(.coherence)` route, and `coherence` is 0 on every source
    ///   without beat-to-beat RR — so every bio route reachable from the UI hit this on
    ///   HealthKit. Fixed by `ModSource.isMeasured(in:)`, which the FX driver and the FX
    ///   readout gate on. (`VisualModulation` gates on it too, but that core has no
    ///   caller yet — it is a guard for when the visual path is wired, not a fix anyone
    ///   has seen.)
    ///
    /// Neither fix routes `ModSource.rawValue` through this property, and that is the
    /// point: a neutral 0.5 substitution would invent a permanent half-depth offset for
    /// every UNIPOLAR route to fix one polarity. Skipping is the honest form — it is
    /// exactly "no contribution", and on every channel whose sentinel normalizes to 0 it
    /// already equals the unipolar result.
    ///
    /// The gate's own boundary is FADED, not stepped: `FXRouteFade` holds a route's last
    /// real offset and eases it out over ~0.25 s when its channel stops being measured
    /// (the camera's ~4 s dropout grace is the live case — it republishes
    /// `breathRate: 0` while still holding a continuous `breathPhase`). What remains is
    /// NOT this gate's doing and is not closed: no `EchoelFXChain` stage smooths its own
    /// parameters, so every control-rate write is a staircase — a 10 Hz bio carrier
    /// steps cutoff 10× a second regardless of any boundary. That needs chain-side
    /// parameter smoothing, the way `EchoelDelay` already smooths its read tap.
    ///
    /// This is deliberately NOT the fully honest form. The honest form is "do not apply
    /// the HRV mapping at all when there is no HRV" — depth to zero rather than value to
    /// the middle — which needs an optional or a `hasHRV` flag threaded through every
    /// mapping. Until then: the DISPLAY must never state an unmeasured value, and the
    /// instrument must still play.
    public var hrvForSound: Float { hasMeasuredHRV ? Swift.min(hrvNormalized, 1) : 0.5 }

    /// Whether this frame carries a REAL beat-to-beat variability reading.
    ///
    /// ⭐ NAMED because a SECOND reader appeared and would otherwise have written the
    /// comparison a third time (#416). `hrvForSound` collapses "unmeasured" and "measured"
    /// into one number by design — that is its whole job — so any surface that wants to
    /// SAY which of the two it is has to ask separately. Two of these four channels
    /// (`hasMeasuredHeartRate`, `hasMeasuredBreath`) already had a name; two carried a
    /// bare `> 0` inline, and the asymmetry was invisible while the accessors had no
    /// second consumer.
    ///
    /// ⚠️ `> 0` and not `!= 0`: `hrvNormalized` is documented as a 0…1 control value and
    /// every producer derives it through `HRVNormalization.normalize`, which cannot emit
    /// a negative. A negative here would be a corrupt frame, and calling that "measured"
    /// is the failure direction this family exists to avoid.
    public var hasMeasuredHRV: Bool { hrvNormalized > 0 }

    /// Whether this frame carries a REAL pulse, as opposed to the structural zero a
    /// publisher emits before it locks (#245, and the hoist #244 asked for).
    ///
    /// `heartRateBPM > 0` was written out at four call sites, and `ModulationMatrix` asked in
    /// as many words for them to be hoisted here. This is that hoist — but only **two** of the
    /// four were converted (`BioModulationMap`, `ModulationMatrix`), and this comment claimed
    /// all four until #244 checked. The other two take a loose scalar, not a frame:
    /// `BioTempoDirector.targetTempo(heartRateBPM:coherence:)` and
    /// `PolySynthVoice.applyEntrainment(neutralCoherence:heartRateBPM:motionEnergy:)` — this
    /// property is simply out of reach from there, and both say so at the literal.
    ///
    /// ⛔ Do NOT "finish" the hoist by widening those two signatures to take a `BioSampleFrame`.
    /// `applyEntrainment` is render-adjacent; handing it a frame moves a struct read onto that
    /// path to buy a spelling. The scalar boundary is the deliberate end of the hoist.
    ///
    /// The consumer it was missing at is the OSC egress, which sent `/bio/heart/bpm 0` to other
    /// people's gear as if it were a reading (#245).
    ///
    /// ⛔ NOT a general "is this frame usable" flag. Freshness is a separate axis and lives
    /// on the bus (`freshBio(maxAge:)`); a frame can carry a real pulse and still be too old
    /// to act on. And on its own it does not answer HRV or coherence: both are derived from
    /// the beat SERIES, so a locked pulse can sit next to a 0 for either of them — HRV for
    /// about three beats, coherence until `HRVCoherence.minIntervals` = 16 RR intervals have
    /// accumulated (on a camera session, possibly never: its RR series comes from a fixed
    /// 10 s peak window). Those two carry their own sentinels.
    ///
    /// ⚠️ WHICH DOES NOT MEAN "use the sentinel INSTEAD of this" — the earlier wording said
    /// exactly that, and it would tell a reader to undo the egress gate deliberately built on
    /// top of it. `OSCSender.bioMessages` requires this AND the sentinel, because a non-zero
    /// HRV beside `bpm == 0` is not a reading but a publisher bug, and forwarding it puts an
    /// invented number on someone else's lighting desk. Value-gating ALONE stays correct for
    /// in-app modulation (`ModSource.isMeasured`), where a malformed frame costs nothing.
    public var hasMeasuredHeartRate: Bool { heartRateBPM > 0 }

    /// Heart rate NORMALISED for MODULATION targets: unmeasured becomes a neutral `0.5`.
    ///
    /// The third member of the `hrvForSound` / `coherenceForSound` family, and it was
    /// missing for the same reason those two were: the rule was written INLINE at the
    /// consumers instead of here. Both sound producers spelled
    /// `clampUnit((frame.heartRateBPM - 40) / 160)` — which is `0.0` when the publisher
    /// has not locked a pulse, i.e. the BOTTOM of the scale, not the middle.
    /// `EchoelDDSP.applyBioReactive` DECLARES its own neutral for this argument
    /// (`heartRate: Float = 0.5`) and maps it as
    /// `(1.0 + (heartRate - 0.5) * 0.5).clamped(to: 0.75...1.25)` — so a take without a
    /// lock ran the patch's vibrato depth AND rate 25 % low, permanently, and was
    /// indistinguishable from a real 40 BPM heart. On this app's acquisition record
    /// (#304/#410/#415: fragile, ~19–32 s to lock, drops out) that is the COMMON state,
    /// not an edge case.
    ///
    /// The scale endpoints are 40 BPM → 0 and **200 BPM → 1**. (`applyBioReactive`'s own
    /// parameter doc says "0=40bpm, 1=180bpm" and is wrong; the sentinel-branch comment
    /// forty lines below it says 200, which matches this arithmetic.)
    ///
    /// ⛔ A MEASURED 40 BPM still reads `0.0`, deliberately — this neutral covers the
    /// ABSENCE of a reading, never a low one. And note 120 BPM normalises to exactly
    /// `0.5`, so "neutral" and "120 BPM" are the same number here by construction.
    ///
    /// ⛔ NOT for the light/space egress. `ArtNetSender` keeps its own RAW copy of this
    /// arithmetic (twice) on purpose: those are output renders for a console the
    /// operator also drives, and `coherenceForSound` records that they need a deliberate
    /// EchoelLux decision, not this mechanical swap. Hoisting the FORMULA for them is a
    /// separate slice; do not "finish" it by pointing them at this property, which would
    /// silently give a dark console a mid-scale dimmer.
    /// ⚠️ Non-finite is treated as ABSENT, symmetrically with `breathPhaseForSound`, and
    /// the two halves fail differently without it: NaN already returned the neutral for
    /// free (`hasMeasuredHeartRate` is `heartRateBPM > 0`, false for NaN), but `+inf`
    /// passes that gate and `clamped(to:)` lands it on `1.0` — the TOP of the scale, from
    /// a frame that measured nothing. Same class as the `0.0` this property removes, just
    /// at the other end, so the guard is explicit rather than inherited from a comparison.
    public var heartRateForSound: Float {
        guard hasMeasuredHeartRate, heartRateBPM.isFinite else { return 0.5 }
        return ((heartRateBPM - 40) / 160).clamped(to: 0...1)
    }

    /// Raw HRV as RMSSD in **milliseconds** — the un-normalized, instrument-grade
    /// value for display, logging, and OSC. `0` means the source does not provide
    /// a real RMSSD (e.g. HealthKit, which exposes SDNN only); UI should then fall
    /// back to `hrvNormalized`. Never synthesize an inaccurate ms from the
    /// normalized value for a real sensor.
    public let hrvRMSSDms: Float

    /// SDNN in **milliseconds** — standard deviation of NN intervals (overall
    /// variability). `0` = not available from this source.
    public let hrvSDNNms: Float

    /// pNN50 as a **percentage** [0…100] — successive |RR differences| > 50 ms.
    /// `0` may mean "not available" or a genuine 0 %; pair with `hrvRMSSDms > 0`
    /// to know a real sensor is present.
    public let hrvPNN50: Float

    /// Breathing rate in breaths/min. `0` = the source derives no respiration.
    public let breathRate: Float

    /// Physiologically plausible respiration window (breaths/min). You cannot breathe
    /// zero times a minute, so a value outside this band is an absence, not a reading.
    public static let plausibleBreathRate: ClosedRange<Float> = 3...40

    /// Whether this frame carries a REAL respiration measurement.
    ///
    /// The gate is `breathRate`, deliberately, even for consumers that read `breathPhase`:
    /// `breathPhase` has NO unknown sentinel — 0 is a meaningful position (exhale start)
    /// — so it cannot answer this question about itself. Publishers encode "no breath" by
    /// leaving `breathRate` at 0 (`PolarH10BioPublisher`, `FaceExpressionBioPublisher`,
    /// and `CameraRPPGBioPublisher` below its confidence threshold), and the HealthKit
    /// path leaves `breathPhase` at the engine's 0.5 placeholder. Anything DISPLAYING a
    /// breath value must gate on this; a 0.50 rendered next to honest "—" neighbours
    /// reads as the most confident number on the panel.
    public var hasMeasuredBreath: Bool { Self.plausibleBreathRate.contains(breathRate) }

    /// Breath phase, [0..1]. 0 = exhale start, 0.5 = inhale start.
    ///
    /// ⚠️ THE CONTRACT IS A SAWTOOTH PHASE; THE CAMERA DOES NOT HONOUR IT. `BioEventGraph`
    /// reads it as one (wrap 1→0 = exhale onset, upward 0.5 crossing = inhale onset), but
    /// `CameraRPPGBioPublisher` writes `RespirationEstimator.amplitude` here, and that is a
    /// SINE-SHAPED POSITION rather than a monotone ramp, so the wrap detector cannot fire.
    /// On the one egress-allowed breath source `/echoelmusic/bio/breath/phase` therefore does
    /// not carry what this line promises. Pre-existing, tracked separately — recorded here
    /// because #245's decision NOT to gate the phase on its own value rests on "0 is a real
    /// position", and that reasoning must stay checkable.
    ///
    /// ⛔ THIS BLOCK SAID "an ENVELOPE (1 = inhale peak, 0.5 = no clear oscillation)" UNTIL
    /// #1135, AND THAT ONE WORD MADE THE REPAIR LOOK FOUR TIMES BIGGER THAN IT IS. Measured
    /// against `RespirationEstimator.ingest` with its shipped time constants (trend 8 s,
    /// smooth 0.8 s, env 6 s), driven by a clean 6/min respiratory sinus arrhythmia:
    ///
    ///   amplitude = 0.5 + 0.5 · clamp(smooth / (env · 1.4), −1, 1)
    ///
    /// `smooth` is the SIGNED band-passed pulse; `env` is the envelope and it sits in the
    /// DENOMINATOR as a normaliser, so what comes out is the oscillation divided by its own
    /// envelope — never the envelope itself. Measured over ten cycles: span [0.000, 1.000],
    /// mean exactly 0.5000, and it passes 0.5 **exactly twice per breath cycle** (up and down;
    /// 2.000 at a 0.1 s tick, 1.99 at the 1 s publish tick). The true envelope `env` stayed
    /// near-constant over the same span — 2.02…2.41 at 0.1 s, 1.90…2.26 at 1 s — and an
    /// envelope cannot span [0,1] once per breath, which is the cheapest way to see the word
    /// was wrong. ⚠️ Both ticks are quoted on purpose: the first draft of this block carried
    /// the 1 s figures beside a guard that drives 0.1 s, i.e. a number measured on one grid
    /// standing in for another — the same defect one scale down.
    ///
    /// ⭐ WHY THE CORRECTION CHANGES THE PLAN AND NOT JUST THE PROSE. An envelope would carry
    /// no phase at all, so honouring this contract would mean deriving one from scratch. A
    /// normalised sine DOES carry the phase — it merely carries it in the wrong SHAPE — and
    /// the estimator already holds both terms a sawtooth needs: `lastCrossT` (the upward
    /// zero-crossing of the band-passed pulse) and `periodEMA` (the smoothed cycle length).
    /// The repair is a re-anchoring of held values, not a new estimator.
    ///
    /// ⛔ AND THE FIRST VERSION OF THIS PARAGRAPH GOT THE ANCHOR WRONG BY A QUARTER CYCLE
    /// (#1135 → #1138). It called `lastCrossT` "inhale onset", offered
    /// `((t − lastCrossT) / periodEMA + 0.5) mod 1`, and argued that because the camera reads
    /// **0.5073** at that crossing, "source and contract already AGREE on 0.5 = inhale start".
    /// Two different 0.5s. The contract's 0.5 is a LABEL (inhale start); the camera's 0.5 is
    /// the MIDPOINT of its own range, which a rising sine passes halfway UP the inhale. A
    /// numeric coincidence was read as an agreement — the cheapest kind of wrong, because it
    /// looks like corroboration.
    ///
    /// Measured on the shipped filter chain at a 0.02 s tick, phases counted from the upward
    /// crossing (`T` = one cycle):
    ///
    ///   lungs FULL  (amplitude 1.0) — plateau 0.156…0.304, centre **0.230**
    ///   lungs EMPTY (amplitude 0.0) — plateau 0.656…0.804, centre **0.730**
    ///
    /// This contract puts 0 at exhale start (= lungs full) and 0.5 at inhale start (= lungs
    /// empty), so the correct re-anchoring is
    ///
    ///   φ = ((t − lastCrossT) / periodEMA + 0.770) mod 1
    ///
    /// and at the crossing itself φ = 0.770, not 0.5. The shipped figure was off by 0.270 of
    /// a cycle — **97°, or 2.7 s at 6 breaths/min**, which on a breath is not a detail.
    ///
    /// ⚠️ TWO HONESTY NOTES ON THOSE NUMBERS. (1) 0.770 is EMPIRICAL, not the geometric 0.75:
    /// the ~0.02 offset is `smoothTau` (0.8 s) lagging the high-passed signal. Anyone porting
    /// this re-derives it against the filters of the day rather than quoting it. (2) The whole
    /// mapping rests on `RespirationEstimator.amplitude`'s own assertion that 1 = inhale peak
    /// (lungs full). That is the file's claim about respiratory sinus arrhythmia, not something
    /// measured against a real breath here. If it is ever checked on a body and found inverted,
    /// this offset moves by half a cycle and so does every consumer.
    ///
    /// ⚠️ AND `amplitude` IS A SOFT-CLIPPED SINE, NOT A CLEAN ONE: `norm` saturates at ±1
    /// because of the `/1.4`, so it sits flat at each end for **14.8 %** of the cycle. Span,
    /// mean and the two 0.5-crossings above are unaffected. For the picture this is a feature —
    /// the widest frame is HELD for a moment at full lungs rather than touched instantaneously.
    ///
    /// ⚠️ CONSEQUENCE FOR ANY CONSUMER THAT APPLIES A SYMMETRIC HUMP. `sin(π · x)` is written
    /// for a ramp. Fed this sine it peaks at MID-breath and falls to zero at BOTH lung
    /// extremes, so the picture swells twice per breath. That conclusion was right when it was
    /// first written down; only its stated reason was wrong. Both are recorded so the next
    /// session can check the claim instead of inheriting it.
    ///
    /// ⛔ ONE FIELD, TWO PHYSICAL QUANTITIES — AND THE CONSUMERS ARE SPLIT (#1146, measured).
    /// Task #30 stood as "the camera writes a sine where this contract promises a sawtooth,
    /// so honour the contract". Converting the stored value is the WRONG repair, and the
    /// reason is in the consumer list, not in the contract:
    ///
    ///   · LEVEL readers want lung VOLUME and are correct today — `MetalBioView` (the
    ///     picture's `spread`, made raw by #1135 precisely so full lungs = widest),
    ///     `SpectralDonutView`, `ArtNetSender`'s DMX byte, the two synth voices' breath swell.
    ///   · POSITION readers want cycle PHASE and are wrong today — `ADMOSCSender` maps it to
    ///     azimuth ±180°, `BioPhaser` treats it as a phase, and `BioEventGraph`'s
    ///     `BreathPhaseDetector` looks for a 1→0 WRAP.
    ///
    /// The event detector is the sharpest evidence, because it is measurable rather than a
    /// matter of taste: its exhale rule is `previous > 0.8 && phase < 0.2` in ONE sample. This
    /// value falls back down SMOOTHLY (it is a sine, not a ramp), and at ~1 Hz publishing on a
    /// 10 s breath it moves ~0.2 per sample — so **`.breathExhaleOnset` can essentially never
    /// fire**. Its inhale rule (upward crossing of 0.5) does fire once per breath, but at
    /// MID-inhale, not at the onset its name promises.
    ///
    /// ⚠️ SO THE REPAIR IS A SECOND, DERIVED VALUE — never a change to this one. A sawtooth
    /// here would invert the picture the founder is being asked to confirm, silently, in the
    /// same field. The estimator already holds both terms a cycle position needs (`lastCrossT`
    /// and `periodEMA`), so the derivation is cheap; what it is NOT is free, because
    /// `BioEventGraph` is in the protected Rausch triad (READ-ONLY without an explicit founder
    /// ask), and its detector would have to move with it.
    ///
    /// ⚠️ AND THIS IS WHAT BLOCKS RSA (task #29), not the founder's eye. Respiratory sinus
    /// arrhythmia needs to tell INHALE from EXHALE. A normalised sine is symmetric about
    /// mid-breath — rising and falling look identical to a consumer reading only the value —
    /// so the sign of the RSA term cannot be derived from this field at all. DEAD-END #1132
    /// named a smoothing-constant blocker; this one sits upstream of it and is harder.
    public let breathPhase: Float

    /// `breathPhase` for MODULATION targets: unmeasured becomes a neutral `0.5`.
    ///
    /// The fourth member of the family, and the one with the widest blast radius,
    /// because `breathPhase` has NO unknown sentinel of its own (see `hasMeasuredBreath`
    /// above — `0` is a meaningful position, exhale start). So the gate must be
    /// `breathRate`, exactly as it is for every DISPLAY consumer.
    ///
    /// What the raw read cost: `EchoelDDSP.applyBioReactive` declares
    /// `breathPhase: Float = 0.5` as its neutral and maps it as
    /// `breathSwell = 0.5 - 0.5 * cos(phase * 2π)`, then
    /// `amplitude *= (1 - swellDepth + swellDepth * breathSwell)`. At the declared
    /// neutral 0.5 that multiplier is exactly 1.0 — the patch's own amplitude. At the
    /// raw `0` it is `1 - swellDepth`, i.e. **0.90 (−0.92 dB)** on the `.natural`
    /// profile and 0.82 on `.harmonicSeries`. And `0` is what THREE of the four
    /// publishers write when they have no respiration: `PolarH10BioPublisher` and
    /// `FaceExpressionBioPublisher` write the literal `breathPhase: 0` always (neither
    /// derives breathing at all), and `CameraRPPGBioPublisher` writes
    /// `measuredBreath ? Float(resp.amplitude) : 0`. So the shipped BLE strap — a fully
    /// wired, real source — ran the whole instrument permanently a decibel under its
    /// patch, indistinguishable from a performer frozen at full exhale.
    /// (`HealthKitBioPublisher` passes the engine's 0.5 placeholder through and was
    /// already neutral by accident.)
    ///
    /// ⚠️ Gating on `breathRate` also means the camera's pulse-hold republish — which
    /// carries `breathRate: 0` while forwarding a held `breathPhase` — now reads neutral
    /// instead of continuing the swell. That is deliberate and CONSISTENT with the
    /// boundary the FX side already draws (`FXBioModulator` eases the breath channel out
    /// on exactly this condition); a swell driven by a frozen phase is not a breath.
    ///
    /// ⚠️ Non-finite is treated as absent, not clamped to the lower bound: `clamped(to:)`
    /// maps NaN to `0`, which is the −0.92 dB extreme, i.e. the very value this property
    /// exists to stop being the fallback.
    /// `hasMeasuredBreath` AND the source actually derives a waveform (#1140).
    ///
    /// Use this — not `hasMeasuredBreath` — wherever the PHASE itself is asserted outward:
    /// an OSC address, an immersive object position, a lighting value. `hasMeasuredBreath`
    /// stays correct for the RATE, which HealthKit genuinely measures. Two measurements, two
    /// gates; conflating them is what let a constant 0.5 leave the device as a position.
    ///
    /// ⚠️ It is deliberately NOT used by the PICTURE. `breathPhaseForSound` already returns
    /// 0.5 when unmeasured, and HealthKit's frozen value IS 0.5, so the rendered result is
    /// identical either way — gating there would add a branch and change nothing. Said here
    /// so the next reader does not "complete" the change and think they fixed something.
    public var hasMeasuredBreathWaveform: Bool {
        hasMeasuredBreath && source.providesBreathWaveform
    }

    public var breathPhaseForSound: Float {
        guard hasMeasuredBreath, breathPhase.isFinite else { return 0.5 }
        return breathPhase.clamped(to: 0...1)
    }

    /// Coherence score, [0..1]. Real frequency-domain HRV coherence
    /// (`HRVCoherence`, Lomb–Scargle / Welch over the RR series) on sources that
    /// deliver beat-to-beat RR — BLE/Polar (`.ble`) and camera (`.cameraPPG`).
    /// `0` where the source has no real RR (HealthKit gives averaged HR + SDNN
    /// only). The demo/`.fallback` source carries a simulated value. Treat `0`
    /// as "not available", not as "incoherent".
    public let coherence: Float

    /// `coherence` for MODULATION targets: unmeasured (0) becomes a neutral 0.5.
    ///
    /// The twin of `hrvForSound`, and it exists for the same reason: this rule had
    /// been written inline three times over — a private helper in one synth voice, a
    /// bare ternary in the other, a held-body variant in the studio view — and was
    /// missing at the sound and visual consumers. That is the exact drift `hrvForSound`
    /// was created to stop, left half-finished. (The sweep is NOT complete: the light
    /// and space egress — `ArtNetSender`'s dimmer, `ADMOSCSender`'s distance — still
    /// read raw. Those are output renders for a console the operator also drives, so
    /// they need a deliberate EchoelLux/spatial decision, not this mechanical swap.)
    /// Coherence bites harder than HRV because more mappings
    /// read it as "calmness": a literal 0 muffles the filter to 200 Hz, picks the
    /// least-consonant chord voicing, and pins the composer to a sparse frozen take.
    /// The first two copies are now deleted; the studio one deliberately stays (it can
    /// fall back to a held body's real coherence, which is better than this 0.5).
    ///
    /// The VALUE-mappings-only caveat on `hrvForSound` applies here unchanged.
    public var coherenceForSound: Float { hasMeasuredCoherence ? Swift.min(coherence, 1) : 0.5 }

    /// Whether this frame carries a REAL coherence reading. The twin of `hasMeasuredHRV`,
    /// named in the same slice and for the same reason (#416): the four always-on sound
    /// channels now have FOUR named gates instead of two names and two inline `> 0`s, so a
    /// surface that has to say "measured" or "neutral" asks the frame instead of restating
    /// the comparison. `HealthKitBioPublisher` is the live case that makes this a real
    /// distinction rather than a formality — it publishes no coherence at all.
    public var hasMeasuredCoherence: Bool { coherence > 0 }

    /// Motion energy, [0..1]. Aggregate from CoreMotion.
    public let motionEnergy: Float

    /// Facial-EXPRESSION control channels, all [0..1], all default `0` when the
    /// source does not track the face (every current publisher writes `0`, like
    /// `motionEnergy`). These are movement/expression used as a CONTROL signal —
    /// NEVER an inferred emotion (EU AI Act framing; see `FaceExpressionMapping`).

    /// Smile expression as a control value, [0..1]. `0` = not tracked / neutral.
    public let faceSmile: Float

    /// Brow-raise expression as a control value, [0..1]. `0` = not tracked / neutral.
    public let faceBrowRaise: Float

    /// Jaw-open expression as a control value, [0..1]. `0` = not tracked / neutral.
    public let faceJawOpen: Float

    /// Where the frame originated.
    public let source: BioSource

    public init(
        timestamp: TimeInterval,
        heartRateBPM: Float,
        hrvNormalized: Float,
        breathRate: Float,
        breathPhase: Float,
        coherence: Float,
        motionEnergy: Float,
        source: BioSource,
        hrvRMSSDms: Float = 0,
        hrvSDNNms: Float = 0,
        hrvPNN50: Float = 0,
        faceSmile: Float = 0,
        faceBrowRaise: Float = 0,
        faceJawOpen: Float = 0
    ) {
        self.timestamp = timestamp
        self.heartRateBPM = heartRateBPM
        self.hrvNormalized = hrvNormalized
        self.breathRate = breathRate
        self.breathPhase = breathPhase
        self.coherence = coherence
        self.motionEnergy = motionEnergy
        self.source = source
        self.hrvRMSSDms = hrvRMSSDms
        self.hrvSDNNms = hrvSDNNms
        self.hrvPNN50 = hrvPNN50
        self.faceSmile = faceSmile
        self.faceBrowRaise = faceBrowRaise
        self.faceJawOpen = faceJawOpen
    }
}

/// Origin of a bio frame.
public enum BioSource: UInt8, Sendable, Equatable {
    case fallback = 0
    case healthKit = 1
    case oura = 2
    case ble = 3
    case watch = 4
    case cameraPPG = 5
    /// Front-camera facial-EXPRESSION tracking (ARKit blendShapes → smile/brow/jaw
    /// control channels). Appended at the END so persisted raw values stay stable.
    /// It carries NO pulse — expression/movement used as a control signal, never an
    /// inferred emotion or a heart measurement.
    case faceCam = 6

    /// Whether this source delivers beat-to-beat RR intervals accurate enough
    /// for time-domain HRV (RMSSD). Only a BLE Heart-Rate-Service chest strap
    /// (0x180D, e.g. Polar H10) qualifies: wrist/camera PPG smooths or gaps the
    /// RR series and Apple Watch carries ~4–5 s latency, so their "HRV" is an
    /// estimate, not a measurement (research §A1). Consumers gate HRV-driven
    /// modulation on this so a strap-only route stays silent on weak sources.
    public var providesTrustedHRV: Bool { self == .ble }

    /// Whether this source derives a breath WAVEFORM, as opposed to only a breath RATE.
    ///
    /// ⛔ #1140 — ONE GATE WAS COVERING TWO DIFFERENT MEASUREMENTS. `hasMeasuredBreath` asks
    /// about `breathRate`, and the comment on `OSCSender`'s breath pair explains why: the
    /// phase cannot answer the question about ITSELF, because 0 is a meaningful position.
    /// That reasoning is right for the camera and blind to a source that has a real rate and
    /// no waveform at all. `HealthKitBioPublisher` is exactly that: it reads a genuine
    /// respiratory rate from HealthKit (`processBreathRateSamples`, 2…60/min) while
    /// `EchoelBioEngine.breathPhase` never leaves its 0.5 default — nothing writes it outside
    /// `startFallbackMode`, which runs ONLY in the `else` branch when HealthKit is
    /// unavailable. So on a Watch the gate opens and every phase consumer reads a constant.
    ///
    /// ⚠️ WHAT THAT COSTS, and it is worst on the path that argues hardest against it:
    /// `ADMOSCSender` sends `(0.5 · 2 − 1) · 180` = **azimuth 0°**, asserting the object is
    /// dead centre front, permanently, as a measurement — in a file whose own comment says
    /// "this arm's whole rule is that it asserts only what was measured". `ArtNetSender` parks
    /// its breath channel at byte 127 for the same reason.
    ///
    /// ⚠️ THE DEMO GENERATOR COUNTS AS YES, and that is not an oversight. `.fallback` is
    /// synthetic — `isSynthetic` says so on the wire (#639) — but it does produce a MOVING
    /// waveform, so a phase consumer fed by it is reading something real about the signal it
    /// was handed. This predicate asks "is there a waveform", not "is it a body". The two
    /// questions have separate answers and separate properties on purpose.
    public var providesBreathWaveform: Bool { self == .cameraPPG || self == .fallback }

    /// Whether this frame's numbers were GENERATED rather than measured — the demo
    /// generator (`BioSimulator`), which the founder uses to show the instrument with no
    /// body attached. Every surface that draws a bio number has to answer this question,
    /// and until #639 every one of them answered it by spelling `source == .fallback`
    /// inline: sixteen occurrences under `Sources/` at the time this property was added.
    ///
    /// ⭐ #416 — ONE DEFINITION PER DECISION, AND THE MIGRATION IS DONE (#677). Sixteen inline
    /// spellings at #639, eleven left by 2026-08-21, zero now: the only `== .fallback` under
    /// `Sources/` is the line below, and `OneSpellingOfWhoseBodyItIsTests` keeps it that way.
    /// Ask this property. If you genuinely need `.fallback` SPECIFICALLY — the narrower
    /// question, not "any synthetic source" — that is legitimate: use a `switch` or `if case`,
    /// which the guard does not match, and say at the site why the narrow question is right.
    ///
    /// ⛔ THIS BLOCK SAID "NOT YET MIGRATED" AND KEPT SAYING IT AFTER #677 FINISHED THE JOB.
    /// It is the definition site — the first thing a session reads before deciding whether to
    /// hand-write the comparison — and it explicitly LICENSED leaving hand-written spellings
    /// alone. A session trusting it would have written `== .fallback` and met a red gate whose
    /// message contradicts the doc two lines above the property it names. The repo's recurring
    /// "a note that declares a live state dead" failure, at the one place it costs most.
    ///
    /// ⚠️ It answers "is this a body", NOT "which sensor". A per-source disclosure is a
    /// different, larger question — on the wire it would also be a different address (#639).
    public var isSynthetic: Bool { self == .fallback }

    /// How long a reading from this source stays musically usable. Live optical/
    /// electrical sources (BLE strap, camera rPPG) expire fast — a lifted finger or
    /// a dropped strap must NOT keep driving sound off a frozen value. But Apple
    /// Watch / HealthKit HR is latent AND sporadic (Apple writes resting HR only
    /// every few minutes); a reading from a minute ago is still your current heart
    /// rate, so a 5 s gate discards it and the wrist never "feels" connected. Give
    /// each source a window matched to how it actually arrives. Staleness is still
    /// enforced — a truly stalled Watch eventually expires.
    public var freshnessWindow: TimeInterval {
        switch self {
        case .ble, .cameraPPG: return 6      // live, near beat-to-beat
        case .faceCam: return 6              // live front-camera expression, same cadence
        case .watch, .healthKit: return 90   // latent + sporadic, valid at rest
        case .oura: return 600               // periodic readiness/HRV
        case .fallback: return 5
        }
    }

    /// How far in the FUTURE a timestamp may sit and still be believed.
    ///
    /// Every freshness check in this repo is two-sided: `age <= window` rejects a frozen
    /// reading, and `age >= -futureSkewTolerance` rejects a timestamp from ahead of now.
    /// The second half is not paranoia — `CFAbsoluteTimeGetCurrent()` is a WALL clock, so a
    /// system time correction (NTP step, manual change, a device waking with a drifted RTC)
    /// can move `now` backwards under a frame that was stamped correctly. One second absorbs
    /// that without letting a genuinely bogus far-future stamp drive sound.
    ///
    /// ⭐ IT IS A CONSTANT BECAUSE IT WAS SIX LITERALS (#545). The same `-1` was written at
    /// `EngineBus.freshBio` / `.usableBio` / `.freshMusical`, `AlwaysOnBioChannel`,
    /// `ColabPayload.live(at:)` and `BioFeedbackManager` — one decision, six places to edit,
    /// and nothing that notices when a retune leaves five behind (#416).
    ///
    /// ⛔ AND `ColabPayload` ALREADY CLAIMED TO ASK IT: its doc block said the tolerance is
    /// "asked the same way rather than minted a second time (#416/#426)" — seven lines above
    /// the line that minted it. A claim and its own refutation inside one declaration (#425).
    /// That is the reason this constant lives on `BioSource` and not somewhere neutral: the
    /// comment that pointed readers at `EngineBus.usableBio()` was right about WHERE the
    /// decision belongs and wrong only about whether it had been made there yet.
    ///
    /// ⚠️ NOT the same quantity as `freshnessWindow`, which is per-source and ranges 5…600 s.
    /// This one is a property of the CLOCK, identical for every source, and applies to peer
    /// payloads (`ColabPayload`) that carry no `BioSource` at all.
    public static let futureSkewTolerance: TimeInterval = 1
}

// MARK: - External controller event (MPE + air dimensions)

/// One event from MIDI/MPE/Network-MIDI external controllers.
public struct ControllerEvent: Sendable, Equatable {

    public enum Kind: UInt8, Sendable, Equatable {
        case noteOn
        case noteOff
        case pitchBend
        case channelPressure
        case slide          // CC74 (MPE timbre)
        case airCC          // CC 21..31 (master prompt §3 air dimensions)
    }

    public let timestamp: TimeInterval

    public let kind: Kind

    /// MPE member channel 2..15, or 1 for master/global.
    public let channel: UInt8

    /// MIDI note 0..127 (0 for non-note events).
    public let note: UInt8

    /// Normalized value. Range depends on kind: pitch bend in [-1..1],
    /// pressure / slide / airCC in [0..1].
    public let value: Float

    /// For `.airCC`: source CC number (21..31). 0 otherwise.
    public let auxCC: UInt8

    public init(
        timestamp: TimeInterval,
        kind: Kind,
        channel: UInt8,
        note: UInt8,
        value: Float,
        auxCC: UInt8
    ) {
        self.timestamp = timestamp
        self.kind = kind
        self.channel = channel
        self.note = note
        self.value = value
        self.auxCC = auxCC
    }
}

// MARK: - Discrete bio event (from BioEventGraph, see SKILL.md)

/// One discrete event emitted by `BioEventGraph`.
public struct BioEvent: Sendable, Equatable {

    public enum Kind: UInt8, Sendable, Equatable {
        case heartbeat
        case breathInhaleOnset
        case breathExhaleOnset
        case motionPeak
        case coherenceShift
        case eegBurst
    }

    public let timestamp: TimeInterval

    public let kind: Kind

    /// Detector confidence, [0..1].
    public let confidence: Float

    /// Kind-specific scalar (e.g., inter-beat interval ms for `.heartbeat`,
    /// band power for `.eegBurst`).
    public let aux: Float

    /// Which bio source this event was DERIVED FROM — the provenance the network
    /// egress gate needs (#186, App Store 5.1.3).
    ///
    /// `nil` means UNSTAMPED, and the gate treats that as "do not send". Fail-closed is
    /// the only safe default here: a permissive one would let a future producer leak by
    /// forgetting a line, which is exactly how the gap this fixes came to exist.
    ///
    /// It is optional-with-a-default rather than required for a hard reason:
    /// `BioEventGraph` constructs four of the five `BioEvent`s in this repo and is a
    /// PROTECTED Rausch component (READ-ONLY without founder approval). A required
    /// parameter would force edits inside it. So the graph keeps producing unstamped
    /// events — it does not know the provenance anyway, it only sees channel values —
    /// and whoever DOES know stamps them at the publish boundary via `stamped(source:)`.
    public let source: BioSource?

    public init(
        timestamp: TimeInterval,
        kind: Kind,
        confidence: Float,
        aux: Float,
        source: BioSource? = nil
    ) {
        self.timestamp = timestamp
        self.kind = kind
        self.confidence = confidence
        self.aux = aux
        self.source = source
    }

    /// This event with its provenance recorded. Non-mutating so the protected graph's
    /// output can be stamped by its caller without the graph knowing about sources.
    public func stamped(source: BioSource) -> BioEvent {
        BioEvent(timestamp: timestamp, kind: kind, confidence: confidence,
                 aux: aux, source: source)
    }
}

// MARK: - EngineBus

/// Single source of truth for bio, controller, and event signal routing
/// between modules. See master prompt §1 — modules consume/produce here,
/// never directly couple to each other.
@MainActor
@Observable
public final class EngineBus {

    // MARK: - Latest snapshots (control plane, @MainActor)

    public private(set) var latestBio: BioSampleFrame?

    /// The freshest bio frame, but only if it arrived within `maxAge` seconds of
    /// now — else `nil`. `BioSampleFrame.timestamp` is on the
    /// `timeIntervalSinceReferenceDate` clock (CFAbsoluteTimeGetCurrent), shared by
    /// every publisher (BLE, rPPG, HealthKit, Demo), so the comparison is valid
    /// across sources. This is the single guard that stops a frozen reading — a
    /// dropped BLE strap, a lifted finger, a stalled Watch — from being treated as a
    /// live body signal (music kept playing on a dead HR, the strip stayed green).
    /// Default 5 s tolerates HealthKit's ~4–5 s Watch latency; pass a tighter window
    /// (e.g. 3 s) for low-latency BLE/rPPG UI.
    public func freshBio(maxAge: TimeInterval = 5) -> BioSampleFrame? {
        guard let f = latestBio,
              CFAbsoluteTimeGetCurrent() - f.timestamp <= maxAge,
              CFAbsoluteTimeGetCurrent() - f.timestamp
                >= -BioSource.futureSkewTolerance else { return nil }
        return f
    }

    /// The freshest frame still within ITS OWN source's usefulness window — the
    /// "is there a usable body signal right now?" question the composer asks. A
    /// camera/BLE reading expires in 6 s (live), a Watch/HealthKit reading stays
    /// usable for 90 s (latent + sporadic, but valid at rest), so wrist HR actually
    /// drives the music instead of being discarded the instant it's a few seconds
    /// old. Still guards against a frozen/stalled source (each window is finite).
    public func usableBio() -> BioSampleFrame? {
        guard let f = latestBio else { return nil }
        let age = CFAbsoluteTimeGetCurrent() - f.timestamp
        guard age <= f.source.freshnessWindow,
              age >= -BioSource.futureSkewTolerance else { return nil }
        return f
    }

    /// ⚠️ #951 — THE FIRST EVENT OF A BATCH, not the latest of one. The notification that
    /// carries this is coalesced (see `notifyScheduled`), so a burst of N updates it once,
    /// with e₁. Nothing in `Sources/` reads it — the declaration, the one write and two tests
    /// are its whole surface — and a burst always drained against e₁ anyway, so this is a
    /// clarification rather than a change. Do not build a "latest value" on it without
    /// removing the coalescing first.
    public private(set) var latestControllerEvent: ControllerEvent?

    public private(set) var latestBioEvent: BioEvent?

    /// LOW-frequency run state of the bio-generative instrument (Start/Stop, set by
    /// the studio's start/stop paths). Lets the chrome mirror — today `PlaybackToggleButton`
    /// in `EchoelStudioView.startControlRow` (⛔ "TransportBar's pulse button" until #1107;
    /// #456 dissolved that bar) — follow the instrument state without coupling to the studio view — modules
    /// couple only via the bus. `private(set)` + mutator so no future module can
    /// turn it into a high-frequency churn source — it must stay Start/Stop-only
    /// (any body may read it under the freeze rule ONLY because of that).
    public private(set) var instrumentRunning = false

    /// Start/Stop-frequency ONLY — never call this per-frame/per-tick.
    public func setInstrumentRunning(_ running: Bool) {
        instrumentRunning = running
    }

    // MARK: - Latest MUSICAL snapshot (output stage: media subscribe to musical parameters)

    public private(set) var latestMusical: MusicalFrame?

    /// The freshest musical frame within `maxAge` seconds — the music-side mirror of
    /// `freshBio`, so renderers (visual/light/spatial) only react to LIVE musical
    /// state and never to a frozen frame after playback stops. Same shared clock.
    /// ⚠️ Asks `BioSource.futureSkewTolerance` although a `MusicalFrame` has no `BioSource`:
    /// the quantity is a property of the shared wall clock, not of a bio source (#545). The
    /// alternative — a second constant with the same value on the musical side — is the
    /// defect being removed here, not a tidier version of it.
    public func freshMusical(maxAge: TimeInterval = 2) -> MusicalFrame? {
        guard let f = latestMusical,
              CFAbsoluteTimeGetCurrent() - f.timestamp <= maxAge,
              CFAbsoluteTimeGetCurrent() - f.timestamp
                >= -BioSource.futureSkewTolerance else { return nil }
        return f
    }

    // MARK: - Lock-free queues (data plane, audio-thread consumers)

    @ObservationIgnored
    nonisolated(unsafe) public let bioFrames: SPSCQueue<BioSampleFrame>

    @ObservationIgnored
    nonisolated(unsafe) public let controllerEvents: SPSCQueue<ControllerEvent>

    @ObservationIgnored
    nonisolated(unsafe) public let bioEvents: SPSCQueue<BioEvent>

    /// Called on the main actor immediately after a `ControllerEvent` is enqueued, so the
    /// ONE consumer can drain right away instead of waiting for its next poll tick (#317).
    ///
    /// ⭐ WHY THIS EXISTS AT ALL — an external keyboard was 0–100 ms late, and the JITTER was
    /// worse than the latency. `controllerEvents` has exactly one consumer,
    /// `BioReactiveSynthVoice`, and it drained on a 100 ms `PollingLoop`. Where in that
    /// window a note landed decided how late it sounded, so the same phrase played back
    /// unevenly every time. Nothing was wrong with the parse or the queue; the note simply
    /// sat there.
    ///
    /// ⚠️ IT ALSO DECOUPLES MIDI FROM A HAZARD THAT HAD NOT FIRED YET — stated with the
    /// numbers, because the first version of this paragraph overstated it ~25× and review
    /// caught it. That 100 ms loop is the BIO loop, and `PollingRateCeiling` exists to slow
    /// bio loops down under thermal or battery pressure. It is NOT opted in today (the only
    /// `governedByBioCeiling: true` in `Sources/` is `OSCSender`), and the trigger is
    /// specifically **adding that argument to `BioReactiveSynthVoice`'s `loop.start`** — not
    /// "governing the bio loop" in general, which cannot reach this call site as written.
    /// The cost if it were added: `ResourceGovernor` only ever publishes the four tier
    /// values in `AdaptiveQuality` — 5, 10, 10, 15 Hz — so the worst SHIPPED ceiling is 5 Hz
    /// = 200 ms, twice nominal. `slowestInterval` (5 s) needs a ceiling below 0.2 Hz, which
    /// no tier produces. So: a real hazard, worth removing, but 200 ms and not seconds.
    /// With this hook the note no longer depends on that loop's rate at all.
    ///
    /// SINGLE-CONSUMER CONTRACT, UNCHANGED and the reason this is a single closure rather
    /// than a broadcast list: only the subscriber that owns the drain may set it, and it
    /// clears it on `stop()`. A second setter would be a second consumer stealing events —
    /// the exact failure `BioReactiveSynthVoice.applyBioFrame`'s doc comment warns about.
    /// The poll-tick drain STAYS as a backstop: an event enqueued while nothing is
    /// subscribed is still picked up when a subscriber arrives.
    @ObservationIgnored
    public var onControllerEventEnqueued: (@MainActor () -> Void)?

    /// ⭐ #951 — THE COALESCING GATE, and this file asked for it itself: `publish(controller:)`
    /// used to spawn a `Task { @MainActor }` PER EVENT, and its own doc named the repair a
    /// FOLLOW-UP ("coalesce the notification to once per batch — a pending flag here").
    ///
    /// It is the 10.76.48 shape: a high-rate source submitting one main-actor job per message
    /// starves the SwiftUI executor, and the symptom that cost device builds was an open
    /// `.menu` Picker that stopped responding. CLAUDE.md states the rule for a 30 fps camera;
    /// MIDI is the same shape from a source that can be faster — a fader bank or a wind
    /// controller on USB-MIDI, and #950 measured eleven CC streams whose events nothing even
    /// consumes feeding straight into it.
    ///
    /// ⚠️ THE LOCK IS NOT DECORATION AND IT IS NOT ON THE AUDIO THREAD. `publish(controller:)`
    /// is `nonisolated`, so this flag cannot live on the actor; the lock is the same
    /// `@unchecked`-style discipline `CameraRPPGBioPublisher.RGBSampleQueue` uses for exactly
    /// the same reason (a producer that must not hop per item). It is uncontended in practice
    /// — `MIDIInput` batches a packet burst into ONE main-actor turn (#30), so the production
    /// producer is already on the main actor — and it never runs inside a render block.
    ///
    /// ⚠️ CLEARED BEFORE THE HOOK, NEVER AFTER. Clearing after the drain would lose a wake-up:
    /// an event enqueued mid-drain finds the flag still set, schedules nothing, and waits for
    /// the 10 Hz backstop poll — the latency #317 removed. Clearing first can at worst schedule
    /// one redundant task, the harmless direction.
    ///
    /// ⚠️ AND THAT HAZARD IS DEFENSIVE, NOT LIVE — said plainly because the paragraph above
    /// reads like a bug being fixed. Nothing can publish mid-drain today: the sole production
    /// producer is `MIDIBusPublisher` on the main actor, and the hook
    /// (`BioReactiveSynthVoice.drainControllerEvents`) does not publish. The ordering costs
    /// nothing and survives a future consumer that echoes; it is a CHOICE, not a repair.
    /// Guard: `Tests/CISmoke/TheControllerNotifyIsCoalescedTests.swift` claim 4, which drives
    /// the mid-drain publish itself — the one interleaving that separates the two orderings.
    @ObservationIgnored
    nonisolated private let notifyLock = NSLock()
    @ObservationIgnored
    nonisolated(unsafe) private var notifyScheduled = false

    /// Release the gate. ⛔ #951b — THIS EXISTS BECAUSE THE FIRST VERSION PUT THESE THREE
    /// LINES INSIDE THE `Task { @MainActor }` BODY AND THE Xcode GATE REJECTED IT:
    /// *"instance method 'lock' is unavailable from asynchronous contexts; Use async-safe
    /// scoped locking instead."* `NSLock.lock()`/`unlock()` are `@available(*, noasync)`.
    /// The mandatory concurrency review and I both checked ISOLATION — which was fine, and
    /// the reviewer proved it against five precedents in this tree — and neither of us
    /// checked `noasync`. **A `nonisolated` member being reachable from a context is not the
    /// same question as its API being ALLOWED in that context**, and only the second one is
    /// what an `async` closure asks.
    ///
    /// ⚠️ AND THE WRAPPER IS NOT A LOOPHOLE, WHICH IS WHY IT IS THE FIX RATHER THAN A
    /// `withLock` this repo has no precedent for. `noasync` exists to stop a lock being held
    /// ACROSS A SUSPENSION POINT; a synchronous function cannot contain an `await`, so the
    /// critical section is structurally guaranteed not to span one. The rule is honoured
    /// here, not dodged.
    nonisolated private func clearNotifyScheduled() {
        notifyLock.lock()
        notifyScheduled = false
        notifyLock.unlock()
    }

    // MARK: - Init

    public init(
        bioCapacity: Int = 32,
        controllerCapacity: Int = 128,
        bioEventCapacity: Int = 64
    ) {
        self.bioFrames = SPSCQueue(capacity: bioCapacity)
        self.controllerEvents = SPSCQueue(capacity: controllerCapacity)
        self.bioEvents = SPSCQueue(capacity: bioEventCapacity)
    }

    // MARK: - Publishers (callable from any thread except audio render)

    /// Publish a bio frame. Enqueues to the lock-free queue (audio-side
    /// consumers see it immediately) and updates the @MainActor latest
    /// snapshot for SwiftUI observation.
    nonisolated public func publish(bio frame: BioSampleFrame) {
        bioFrames.enqueue(frame)
        Task { @MainActor [weak self] in
            self?.latestBio = frame
        }
    }

    /// Publish a controller event.
    ///
    /// The main-actor hop is the one that was already here for `latestControllerEvent`; the
    /// drain notification rides along inside it rather than adding a second (#317). That
    /// matters — a per-event `Task { @MainActor }` flood from a fast source is a shipped
    /// defect of this repo's own (#30, and again in `CameraRPPGBioPublisher`), so the rule is
    /// to reuse an existing hop, never to open one.
    ///
    /// ⭐ #951 — THAT FOLLOW-UP IS DONE, AND THIS PARAGRAPH IS THE REASON IT GOT FOUND. It
    /// used to end: "It is a Task PER EVENT … FOLLOW-UP, cheaper than #317 was: coalesce the
    /// notification to once per batch — a pending flag here". The paragraph was honest about
    /// being INHERITED, NOT VETTED, and it named its own repair; what it could not do was make
    /// anyone act on it. #950 walked into the same shape from the other end (eleven CC streams
    /// that nothing consumes, feeding one main-actor job each) and this was already written
    /// down waiting.
    ///
    /// The gate is `notifyScheduled` above: one wake-up per BATCH, cleared BEFORE the hook.
    /// The residual cost is now one job turn per batch instead of per event; the "much less
    /// dangerous than #30" reasoning (`MIDIInput` batches a packet burst into ONE main-actor
    /// turn, so this is a main→main hop rather than cross-actor contention) is unchanged and
    /// is why this was a follow-up rather than a fire.
    ///
    /// ⚠️ The rule one paragraph up still stands and is not weakened by this: REUSE an
    /// existing hop, never open one. #951 did not open a hop — it stopped opening N of them.
    nonisolated public func publish(controller event: ControllerEvent) {
        controllerEvents.enqueue(event)

        // #951 — one wake-up per BATCH, not per event. See `notifyScheduled` above for why
        // this is safe (the drain consumes the whole queue in order) and why the flag is
        // cleared before the hook rather than after (lost wake-ups).
        notifyLock.lock()
        let alreadyScheduled = notifyScheduled
        notifyScheduled = true
        notifyLock.unlock()
        guard !alreadyScheduled else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.clearNotifyScheduled()
            // ⚠️ #951 — THIS SNAPSHOT IS NOW THE FIRST EVENT OF A BATCH RATHER THAN EACH ONE
            // IN TURN, and that is a change nothing can observe: `latestControllerEvent` has
            // no production reader (the declaration, this write, and two tests), and the
            // paragraph below already recorded that a burst drains entirely against e₁
            // anyway. Said plainly so it is not rediscovered as a regression.
            self.latestControllerEvent = event
            // ⛔ THIS LINE'S ORIGINAL COMMENT CLAIMED AN ORDERING GUARANTEE THAT DOES NOT
            // EXIST, and it is corrected rather than deleted because it is the kind of
            // sentence a later session would build on. It said "AFTER the snapshot: a
            // consumer that reads `latestControllerEvent` inside its drain must see this
            // event". Both halves fail: NO consumer reads that snapshot (its only readers in
            // the repo are two tests), and the guarantee is undeliverable anyway — for a
            // burst of N events the FIRST task drains all N while the snapshot still holds
            // e₁, so e₂…e_N would be applied against a stale one.
            //
            // WHAT ACTUALLY KEEPS NOTES CORRECT, and it is worth knowing because
            // `MIDIInput` (#30) records that separate `Task { @MainActor }`s have no FIFO
            // guarantee — "a note-off could overtake its note-on → hung note": the drain
            // consumes the QUEUE, whose order the single producer preserves, and whichever
            // task runs first drains the whole backlog in order. Task ordering can only
            // perturb the snapshot, which nothing reads. That is the invariant; the
            // statement order below is incidental.
            self.onControllerEventEnqueued?()
        }
    }

    /// Publish a discrete bio event.
    ///
    /// SPSC CONTRACT (audited 2026-07-24). `bioEvents` is a single-producer /
    /// single-consumer lock-free queue. This method is `nonisolated` for call-site
    /// convenience, but the enqueue is race-free ONLY because every current caller
    /// publishes from `@MainActor` — `BioEventPublisher.tick` runs on its @MainActor
    /// poll, and `PolarH10BioPublisher.didUpdateValueFor` (a nonisolated BLE callback)
    /// hops to `Task { @MainActor }` before publishing — so all enqueues serialize on
    /// the main thread, and the SOLE consumer (`OSCSender.drainAndSendEvents`) also
    /// drains on @MainActor. A NEW caller MUST publish bio events from @MainActor too;
    /// enqueuing from a second thread would corrupt the lock-free head/tail. (The
    /// "two-producer SPSC race" audit flag was a FALSE POSITIVE: both producers are
    /// already @MainActor-serialized by construction — do not add a lock here.)
    nonisolated public func publish(bioEvent event: BioEvent) {
        bioEvents.enqueue(event)
        Task { @MainActor [weak self] in
            self?.latestBioEvent = event
        }
    }

    /// Publish the current musical state. Slow control-plane (UI-rate), so it only
    /// updates the @MainActor snapshot — no lock-free queue needed (renderers read it
    /// via `freshMusical`). Mirrors `publish(bio:)`.
    nonisolated public func publish(musical frame: MusicalFrame) {
        Task { @MainActor [weak self] in
            self?.latestMusical = frame
        }
    }
}
