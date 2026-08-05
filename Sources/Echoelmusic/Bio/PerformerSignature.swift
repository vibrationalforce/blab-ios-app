// PerformerSignature.swift
// Echoel — #403 Slice 1. "Zwei User, gleiches Preset, verschiedene Songs."
//
// ⭐ WHAT THIS IS. A slowly-learned, on-device fingerprint of the PERSON at the instrument:
// where their heart rests, how much variability they carry, how they breathe, how coherent
// they usually are. It folds into the composer's STRUCTURE seed, so the same preset opens on
// a different harmonic skeleton for a different body — while the DETAIL seed stays the
// MOMENT, so the same person still gets a fresh take every render.
//
// ⚠️ WHAT IT IS NOT, and this matters more than what it is:
//
// 1. **It is not a statement about the human being.** It is a musical handwriting. Nothing
//    here is a health reading, a score, or a diagnosis, and nothing derived from it may ever
//    be phrased as one (`CLAUDE.md`: bio is a modulation source, never wellness).
// 2. **This app never transmits it.** No cloud half, no comparison between users, and it is
//    deliberately kept out of the shared App Group — which matters for a specific reason: that
//    container is readable by an extension, and a HealthKit-derived value there would sit one
//    refactor away from real 5.1.3 egress.
//    ⛔ THE FIRST VERSION SAID "it never leaves the device", FLATLY, AND THAT IS NOT TRUE OF
//    ANY `UserDefaults` VALUE. The suite persists to `Library/Preferences`, which iCloud and
//    encrypted local backups include — while the HealthKit store itself is excluded from
//    them. So this file creates a backup channel the underlying readings do not have. That is
//    a deliberate, stated trade (a `UserDefaults` suite cannot be marked
//    `isExcludedFromBackup`; a plain file could), not an oversight — but the absolute
//    sentence would have been quoted into a privacy claim, which is exactly how #158/#184 got
//    expensive.
// 3. **It is not "more randomness".** An empty signature contributes EXACTLY ZERO: `seedSalt`
//    returns 0 and the caller's XOR is then a no-op, so a user who has never been measured
//    renders bit-identically to before this file existed. That is the whole safety story of
//    this slice, and `SignatureIsThePersonNotTheMomentTests` pins it.
//
// ⚠️ HOW FAR SLICE 1's CLAIM GOES. This changes WHICH skeleton a body opens on. On the genre
// a fresh install opens with (`.selfObservation`: three chords, four sustained chord tones,
// no lead — the 2026-08-05 device log, quoted in §1d of
// `scratchpads/PLAN_PERFORMER_SIGNATURE.md`, shows `5 notes` on all nine takes) the skeleton
// has very little room to differ, so the audible effect there is small by construction. That
// is not a defect in this file; it is why that plan re-weighted Slice 2 (character offsets)
// as the slice that actually reaches the contemplative middle of the brand. Do not claim
// "sounds like you" on the strength of this file alone.

import Foundation

/// The persisted, slowly-learned fingerprint of one performer's body.
///
/// Every channel carries its OWN running mean and its OWN count, because sources disagree
/// about what they can measure: camera rPPG reports heart rate long before it reports HRV,
/// Apple Watch delivers HRV sporadically, and several sources derive no respiration at all.
/// A single shared count would let one channel's silence dilute another channel's evidence.
public struct PerformerSignature: Codable, Equatable, Sendable {

    /// 1 = the shape as of 2026-08-05 (#403 Slice 1). Same stamp shape as `TrackFX`: written
    /// by the synthesized encoder, never assigned, so a future migration reads it as a local
    /// inside `init(from:)` rather than trusting this constant.
    public static let currentSchemaVersion = 1

    public private(set) var schemaVersion: Int = PerformerSignature.currentSchemaVersion

    /// Running mean resting-ish heart rate in BPM, and how many observations built it.
    public private(set) var heartRateBPM: Float
    public private(set) var heartRateCount: Int

    /// Running mean of `hrvNormalized` ([0…1]), and its own count.
    public private(set) var hrvNormalized: Float
    public private(set) var hrvCount: Int

    /// Running mean coherence ([0…1]), and its own count.
    public private(set) var coherence: Float
    public private(set) var coherenceCount: Int

    /// Running mean breathing rate in breaths/min, and its own count.
    public private(set) var breathRate: Float
    public private(set) var breathCount: Int

    /// Whether ANY of the frames that taught this fingerprint came from a source whose values
    /// may not leave the device (`BioEgressPolicy.allowsEgress == false`: HealthKit, Watch,
    /// Oura). Sticky — once true it never clears, because the mean it influenced never
    /// un-mixes.
    ///
    /// ⚠️ WHY IT IS RECORDED NOW, WHEN NOTHING READS IT YET. `observing` blends every accepted
    /// source into the same four running means, and after the blend the `BioSource` is gone —
    /// so `BioEgressPolicy.allowsEgress(_:)`, which takes exactly that, can no longer be
    /// asked. That is harmless while the value stays where it is, and stops being harmless at
    /// the two places already planned: Slice 3 wants to SAY something about it in the UI, and
    /// `ColabPayload.BioPeek` already ships live vitals to a peer behind that very gate, so
    /// "share your handwriting" is a natural next ask. Adding this field later would leave the
    /// answer permanently unknowable for every install that had already learned. Same shape
    /// and same reason as `BioVitals.egressAllowed`, which carries provenance across a
    /// serialisation boundary for exactly this case.
    public private(set) var taughtByRestrictedSource: Bool

    /// `frame.timestamp` (CFAbsoluteTime at receipt) of the last accepted observation.
    ///
    /// Persisted deliberately. The rate limit is what makes an observation cost TIME rather
    /// than a tap: every control edit recomposes, so without it a busy ten minutes would count
    /// as dozens of independent pieces of evidence about the person. If the stamp were held in
    /// memory only, ten relaunches in a minute would stack ten observations and re-open exactly
    /// that hole.
    ///
    /// ⛔ IT DOES NOT MAKE A SESSION HARMLESS, and the first version of this doc said it did
    /// ("so that ONE long session … cannot dominate"). That belongs to `saturation`, which now
    /// carries the corrected arithmetic — and even there the honest verb is "throttles", not
    /// "bounds".
    public private(set) var lastObservation: TimeInterval

    /// The empty signature: contributes nothing, and is what a fresh install carries.
    public static let unknown = PerformerSignature()

    public init() {
        self.heartRateBPM = 0
        self.heartRateCount = 0
        self.hrvNormalized = 0
        self.hrvCount = 0
        self.coherence = 0
        self.coherenceCount = 0
        self.breathRate = 0
        self.breathCount = 0
        self.taughtByRestrictedSource = false
        self.lastObservation = 0
    }

    /// Defensive decoder (the `decodeIfPresent` law, #163/#189): a signature is derived data
    /// that can always be re-learned, so a partially-readable payload degrades to whatever
    /// fields survived rather than throwing the whole fingerprint away.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = PerformerSignature.currentSchemaVersion
        self.heartRateBPM = try c.decodeIfPresent(Float.self, forKey: .heartRateBPM) ?? 0
        // ⚠️ THE COUNTS ARE SANITISED, NOT JUST DEFAULTED. A "defensive decoder" that only
        // handles ABSENCE is half a decoder: a negative count makes `blend`'s weight 1 (the
        // channel stops smoothing and jumps to each new sample), and a count near `Int.max`
        // makes the `+= 1` in `observing` TRAP. Neither can come from our own encoder — both
        // can come from a corrupted or hand-edited preferences plist, which is exactly the
        // input a defensive decoder exists for. Same shape as `TrackFX`'s `finite(_:_:)`.
        self.heartRateCount = try c.decodeIfPresent(Int.self, forKey: .heartRateCount) ?? 0
        self.hrvNormalized = try c.decodeIfPresent(Float.self, forKey: .hrvNormalized) ?? 0
        self.hrvCount = try c.decodeIfPresent(Int.self, forKey: .hrvCount) ?? 0
        self.coherence = try c.decodeIfPresent(Float.self, forKey: .coherence) ?? 0
        self.coherenceCount = try c.decodeIfPresent(Int.self, forKey: .coherenceCount) ?? 0
        self.breathRate = try c.decodeIfPresent(Float.self, forKey: .breathRate) ?? 0
        self.breathCount = try c.decodeIfPresent(Int.self, forKey: .breathCount) ?? 0
        // On a payload that predates the field, an already-taught fingerprint defaults to
        // RESTRICTED and an empty one does not. Both halves are deliberate: an old fingerprint
        // might have been taught by HealthKit and there is no way left to find out, so the
        // conservative answer is the restricted one — guessing `false` would silently declare
        // unknown provenance to be safe provenance. But a payload that taught nothing has no
        // provenance to be unsure about, and marking it restricted would make a decoded empty
        // signature differ from `.unknown` for no reason a reader could explain.
        // Reads the RAW counts deliberately: a negative one is not evidence of anything, and
        // `sane` below maps it to 0, so both agree that nothing was taught on that channel.
        let taughtAnything = self.heartRateCount > 0 || self.hrvCount > 0
            || self.coherenceCount > 0 || self.breathCount > 0
        self.taughtByRestrictedSource =
            try c.decodeIfPresent(Bool.self, forKey: .taughtByRestrictedSource) ?? taughtAnything
        self.heartRateCount = PerformerSignature.sane(self.heartRateCount)
        self.hrvCount = PerformerSignature.sane(self.hrvCount)
        self.coherenceCount = PerformerSignature.sane(self.coherenceCount)
        self.breathCount = PerformerSignature.sane(self.breathCount)
        self.lastObservation = try c.decodeIfPresent(TimeInterval.self,
                                                     forKey: .lastObservation) ?? 0
    }

    // MARK: - Learning

    /// How many observations it takes before a channel stops moving quickly. Past this the
    /// running mean behaves as an exponential average with α = 1/`saturation`.
    ///
    /// ⛔ THE FIRST VERSION SAID 64 AND CLAIMED "without letting one unusual afternoon redraw
    /// the handwriting". Review did the arithmetic and the claim did not survive it: at one
    /// accepted observation per ~30–45 s, a 45-minute sitting yields 60–90 observations — it
    /// SATURATES the mean on its own. A hundred frames at 120 BPM would have pulled a settled
    /// 60 to ≈107.6. The test that appeared to guard this fed exactly ONE outlier, so it
    /// proved a much weaker statement than its name promised.
    ///
    /// 256 is chosen so the window is roughly two to four HOURS of playing rather than one
    /// sitting. And the honest statement of what this constant does, which the old one
    /// overstated: **it throttles, it does not bound.** A performer who plays for a whole day
    /// in an unusual state will move their handwriting, and should — it is still their body.
    /// What is prevented is a single half-hour deciding it outright.
    public static let saturation = 256

    /// The minimum spacing between two accepted observations, in seconds.
    ///
    /// Sized to the composer's own re-seed cadence (~25–30 s) rather than to the ~1 Hz bio
    /// rate: the thing being throttled is not frames, it is TAKES. Every control tap
    /// recomposes, and without this a busy ten minutes of tweaking would count as dozens of
    /// separate pieces of evidence about the person.
    public static let minimumObservationInterval: TimeInterval = 30

    /// Fold one measured body state into the fingerprint, or return `self` unchanged.
    ///
    /// Returns `self` unchanged in four cases, and a reader who lands here should see all
    /// four: the source may not teach at all (`mayTeach` — the simulator), the frame carries
    /// no usable timestamp (`now > 0`), it arrived inside the rate-limit window, or every
    /// channel it carries was unmeasured. None of them consumes the window. **Zero means "not measured" for HRV,
    /// coherence and breath rate** — that convention is the bus's, not this file's
    /// (`BioSampleFrame.hrvNormalized` documents it, and `hrvForSound` exists because 0 is an
    /// EXTREME rather than a neutral value). Averaging an unmeasured 0 in would drag every
    /// mean toward a body nobody has.
    public func observing(_ frame: BioSampleFrame) -> PerformerSignature {
        guard PerformerSignature.mayTeach(frame.source) else { return self }
        let now = frame.timestamp
        // `now < lastObservation` = the clock moved backwards (a device time change, a
        // restored backup). Treat it as elapsed rather than as a window that never ends;
        // refusing forever would freeze the fingerprint for good.
        let spaced = now - lastObservation >= PerformerSignature.minimumObservationInterval
            || now < lastObservation
        guard now > 0, spaced else { return self }

        var next = self
        var accepted = false
        if let hr = PerformerSignature.measured(frame.heartRateBPM, upTo: 300) {
            next.heartRateBPM = PerformerSignature.blend(next.heartRateBPM,
                                                         hr, count: next.heartRateCount)
            next.heartRateCount += 1
            accepted = true
        }
        if let hrv = PerformerSignature.measured(frame.hrvNormalized, upTo: 1) {
            next.hrvNormalized = PerformerSignature.blend(next.hrvNormalized,
                                                          hrv, count: next.hrvCount)
            next.hrvCount += 1
            accepted = true
        }
        if let coh = PerformerSignature.measured(frame.coherence, upTo: 1) {
            next.coherence = PerformerSignature.blend(next.coherence,
                                                      coh, count: next.coherenceCount)
            next.coherenceCount += 1
            accepted = true
        }
        // ⚠️ BREATH IS THE ONE CHANNEL WHERE `> 0` IS THE WRONG GATE, and the doc above cites
        // the bus as its authority — so it has to use the bus's OWN answer. `BioSampleFrame`
        // defines `plausibleBreathRate = 3...40` precisely because "you cannot breathe zero
        // times a minute, so a value outside this band is an absence, not a reading". A
        // settling `RespirationEstimator` emitting 1.2 breaths/min is finite and positive and
        // would otherwise be learned as this person's respiration for good.
        if frame.hasMeasuredBreath, let br = PerformerSignature.measured(frame.breathRate, upTo: 60) {
            next.breathRate = PerformerSignature.blend(next.breathRate,
                                                       br, count: next.breathCount)
            next.breathCount += 1
            accepted = true
        }
        // A frame that measured NOTHING must not consume the window — otherwise a source
        // that emits empty frames every few seconds would keep the real body permanently
        // outside the rate limit and the fingerprint would never learn anything.
        guard accepted else { return self }
        if !BioEgressPolicy.allowsEgress(frame.source) { next.taughtByRestrictedSource = true }
        next.lastObservation = now
        return next
    }

    /// Whether frames from this source may teach a PERSON's fingerprint.
    ///
    /// ⚠️ `.fallback` is the SIMULATOR (`BioSimulator` is its only producer), and it emits
    /// perfectly plausible numbers — a resting rate, a coherence, a breath. Letting them in
    /// would build a handwriting out of a synthetic body and then present it as "this is how
    /// you sound", which is the one failure the plan's Vision-Keeper seat named outright:
    /// randomness is not a body. It matters in practice and not only in principle — the
    /// founder's own 2026-08-05 device session ran with `bio simulation starting`.
    ///
    /// This is a policy of THIS file (what may teach an identity), deliberately not a general
    /// property of `BioSource` — every other consumer is right to treat a simulated frame as
    /// a frame. A simulated session still plays, still sounds bio-reactive, and still
    /// composes; it just does not get to decide who the performer is.
    private static func mayTeach(_ source: BioSource) -> Bool {
        switch source {
        case .fallback: return false
        case .healthKit, .oura, .ble, .watch, .cameraPPG, .faceCam: return true
        }
    }

    /// Clamp a decoded observation count into a range where the arithmetic is defined:
    /// non-negative (so `blend`'s weight stays ≤ 1) and far enough below `Int.max` that
    /// `observing`'s `+= 1` can never overflow.
    private static func sane(_ count: Int) -> Int {
        Swift.max(0, Swift.min(count, 1_000_000))
    }

    /// A value counts as a MEASUREMENT only when it is finite and above zero — the same
    /// `> 0` rule the composer applies to heart rate and coherence (`measured(_:)` in
    /// `EchoelStudioView`), for the same reason: zero is the sentinel the sources emit.
    private static func measured(_ v: Float, upTo hi: Float) -> Float? {
        guard v.isFinite, v > 0 else { return nil }
        return Swift.min(v, hi)
    }

    /// Running mean with a saturating weight: 1/(n+1) until `saturation`, then a constant
    /// 1/`saturation`.
    private static func blend(_ mean: Float, _ sample: Float, count: Int) -> Float {
        let n = Swift.max(0, Swift.min(count, PerformerSignature.saturation - 1))
        let weight = 1 / Float(n + 1)
        return mean + (sample - mean) * weight
    }

    // MARK: - The seam

    /// `true` once ANY channel has been measured at least once.
    ///
    /// This is the honest answer to "does this install know a body?", and Slice 3 is the
    /// slice that is allowed to SAY it in the UI. Until then it exists so callers can tell
    /// "no signature" from "a signature that happens to be near zero".
    public var hasBody: Bool {
        heartRateCount > 0 || hrvCount > 0 || coherenceCount > 0 || breathCount > 0
    }

    /// Where this performer sits between the calmest and the busiest resting heart — −1 …
    /// +1, and exactly `0` until a heart rate has been learned.
    ///
    /// ⭐ WHAT IT IS FOR (#403 Slice 2): `StudioCalculator.tilted` nudges the genre-folded
    /// tempo by this, so the same preset opens at a different pace for a different body.
    ///
    /// ⚠️ IT IS NOT A SECOND OPINION ABOUT THE MOMENT, and the distinction is what makes it
    /// legitimate rather than double-counting: this is the HABITUAL rate, the live mapping is
    /// THIS MINUTE's. The full argument (including what the tilt costs) lives on
    /// `StudioCalculator.tilted` — read it there rather than trusting a summary here; two
    /// earlier versions of the summary were wrong, one of them about which genre it measured.
    ///
    /// ⚠️ IT RAMPS IN OVER `confidentAfter` OBSERVATIONS, and that is not decoration. `blend`
    /// uses weight `1/(n+1)`, so at `count == 0` the mean is set OUTRIGHT to the first sample:
    /// without the ramp a single startle or finger-pressure artefact ~30 s into a fresh
    /// install's first take would jump the target by the full 0.35·headroom — inside the
    /// 8 BPM/tick limiter on the calm windows, so it would land in ONE tick, mid-take. The
    /// file header calls this a slowly-learned fingerprint; `saturation` only damps samples
    /// 2…n, so the ramp is what makes that true of the first one too. It preserves the golden
    /// law by construction: `count == 0` still gives exactly 0.
    ///
    /// ⚠️ AND THE SPAN IS NAMED FOR WHAT IT MEASURES. It was called `restingSpan` for one
    /// commit and that was wrong: `heartRateBPM` is a running mean over every accepted frame
    /// — the person PLAYING, standing, engaged — not a resting measurement. Anchoring a
    /// resting range on a playing mean biases every performer upward. 50…90 stays (a trained
    /// endurance athlete at 45 and a habitually fast heart at 95 both saturate, which is the
    /// honest behaviour — this is a position among people, not a clinical number), but the
    /// name no longer claims a measurement nobody takes.
    public var tempoTilt: Double {
        guard heartRateCount > 0 else { return 0 }
        let bpm = Double(heartRateBPM)
        guard bpm.isFinite, bpm > 0 else { return 0 }
        let span = PerformerSignature.habitualSpan
        // Mirrors `StudioCalculator.tilted`'s own degenerate-window guard. `habitualSpan` is
        // a constant today, so this cannot fire — it is here because `tempoTilt` is PUBLIC
        // and a future consumer would not have that function's guard downstream to catch a
        // 0/0 for it.
        guard span.upperBound > span.lowerBound else { return 0 }
        let unit = (bpm - span.lowerBound) / (span.upperBound - span.lowerBound)
        let position = unit.clamped(to: 0...1) * 2 - 1
        let ramp = Double(Swift.min(heartRateCount, PerformerSignature.confidentAfter))
            / Double(PerformerSignature.confidentAfter)
        return position * ramp
    }

    /// Where this performer sits between the least and the most variable habitual body —
    /// −1 … +1, and exactly `0` until an HRV has been learned. #403 Slice 3.
    ///
    /// ⭐ WHAT IT IS FOR. `BioComposer.composeHarmonic` reads it to set how far the composed
    /// bass LINE is lifted over the pad. A body that habitually sits low or high on
    /// variability carries more or less bottom, by ≈1 dB.
    ///
    /// ⛔ Two qualifiers the first version dropped, both from the review of the same commit.
    /// (a) It is the bass LINE at `padOctave − 1`, not "the low end": the felt sub an octave
    /// below is `SubBassVoice`, which discards velocity by design, so that band does not move.
    /// (b) "Same level" is only true because the default-on loudness servo is holding the
    /// master; with the user on "No target" the lift is a level change as well as a balance
    /// change. Neither breaks the design — both were stated more strongly than the code
    /// supports.
    ///
    /// ⛔ IT WAS A LEVEL TILT FOR ONE COMMIT AND THAT VERSION WAS ERASED DOWNSTREAM BY
    /// DESIGN. The inventory behind it was right that the section VELOCITY is the one
    /// continuously-read body quantity in the live composer. (An earlier version of this
    /// paragraph listed the six gate values with their comparison operators; a review found
    /// three of the operators wrong. They are gone rather than re-guessed — read the gates in
    /// `BioComposer` if you need them, not a copy here. ⛔ And a second review found the
    /// SUPERLATIVE wrong too: voice-leading strictness/spread, the chord-journey coherence and
    /// `effectiveTension` are all live continuous body reads. Velocity may have been the best
    /// pick; it was not the only one.) What that inventory did not look at is what happens
    /// after the composer — and the reasons first written here were themselves part wrong,
    /// which is why the full arithmetic now lives at `BioComposer.composeHarmonic`'s velocity
    /// site rather than in two paraphrases. In short: velocity is overwhelmingly but not
    /// purely level (it also moves the per-note filter brightness), and the default-on
    /// loudness servo has a 0.4 dB dead zone that Slice 3's ±0.3–0.4 dB offset sat inside. So
    /// the level tilt was neither erased nor reliable — it was INDETERMINATE.
    ///
    /// **The general lesson, because it is not about this parameter:** before making a
    /// fingerprint out of a quantity, follow it to the speaker — and compute the SIZE of the
    /// effect against the size of whatever stage you think removes it. "A servo will cancel
    /// this" is not an argument until the offset is compared with the servo's dead zone; the
    /// first version of this doc asserted the cancellation without ever doing that
    /// subtraction. Level belongs to the master (and the app gives the user a control for
    /// it); BALANCE belongs to the composer, and a RATIO is untouched by a gain servo, by the
    /// static master trim and by the chain's linear EQ.
    ///
    /// ⚠️ THE COLLAPSE IT ANSWERS IS STILL THE ONE `tempoTilt` EXISTS FOR. The composer's
    /// dynamics driver is `Input.breathDepth`, which `makeComposerInput` feeds
    /// `0.3 + 0.5 * coherence` — NOT the measured breath. Coherence is precisely the input
    /// that pulls every performer toward the same take as it rises (it also scales `calm`,
    /// `settle`, `busy` and the tempo pull toward 72), so without a per-person term the
    /// weighting of every take is a function of coherence alone.
    ///
    /// ⚠️ WHY HRV AND NOT BREATH, given that the parameter is named for breath. `observing`
    /// only counts a channel it actually receives, and breath is the least reliably delivered
    /// of the four (see #343 on the respiration estimator). HRV is supplied by camera rPPG,
    /// HealthKit and the BLE strap alike, so this tilt reaches a real user. The musical
    /// framing is a handwriting and nothing more: how variable a body habitually is, mapped to
    /// how strongly the take is played. It is NOT a statement about the person — the file
    /// header's law — and no copy may phrase it as one.
    ///
    /// ⚠️ ITS SPAN IS ITS OWN, and stated rather than borrowed. `hrvNormalized` is already
    /// 0…1, so unlike `tempoTilt` there is no unit conversion — but the useful part of that
    /// range is not the whole of it. `habitualHRVSpan` is 0.2…0.7: below 0.2 and above 0.7 a
    /// performer saturates, which is the same honest behaviour `habitualSpan` chose for the
    /// heart (a position among people, not a clinical number).
    ///
    /// Ramps in over `confidentAfter` for the same reason `tempoTilt` does, and returns
    /// exactly 0 at `hrvCount == 0` so a never-measured user renders bit-identically.
    public var dynamicTilt: Double {
        guard hrvCount > 0 else { return 0 }
        let hrv = Double(hrvNormalized)
        // ⛔ `hrv > 0` WAS MISSING FOR ONE COMMIT, under a comment claiming this mirrors
        // `tempoTilt` — which guards `bpm > 0` for exactly this reason. The decoder sanitises
        // the COUNTS, not the values, so a corrupt or hand-edited store carrying
        // `{hrvCount: 5, hrvNormalized: 0}` produced a maximal NEGATIVE tilt out of a value
        // the whole repo defines as "not measured" (`BioSampleFrame.hrvNormalized`). A partial
        // mirror described as a full one is the failure this file's header warns about.
        guard hrv.isFinite, hrv > 0 else { return 0 }
        let span = PerformerSignature.habitualHRVSpan
        // Same degenerate-window guard as `tempoTilt`, for the same reason: this is PUBLIC and
        // a future consumer may not have `StudioCalculator.tilted` downstream to catch a 0/0.
        guard span.upperBound > span.lowerBound else { return 0 }
        let unit = (hrv - span.lowerBound) / (span.upperBound - span.lowerBound)
        let position = unit.clamped(to: 0...1) * 2 - 1
        let ramp = Double(Swift.min(hrvCount, PerformerSignature.confidentAfter))
            / Double(PerformerSignature.confidentAfter)
        return position * ramp
    }

    /// The habitual-heart-rate span `tempoTilt` opens across — see its doc for why the name
    /// says "habitual" and not "resting".
    public static let habitualSpan: ClosedRange<Double> = 50...90

    /// The habitual-HRV span `dynamicTilt` opens across. Narrower than the full 0…1 on
    /// purpose: `hrvNormalized` is a normalised index, and both tails are sparsely populated,
    /// so opening the tilt across the whole range would leave almost every real performer
    /// bunched near the middle with no audible difference between them.
    public static let habitualHRVSpan: ClosedRange<Double> = 0.2...0.7

    /// How many accepted heart-rate observations before `tempoTilt` reaches its full
    /// magnitude. Eight is roughly four minutes of playing at the 30 s rate limit — long
    /// enough that no single artefact owns the pace, short enough to be there within one
    /// session.
    public static let confidentAfter = 8

    /// The value the composer XORs into its STRUCTURE seed — `0` when nothing was ever
    /// measured, which makes the caller's fold a no-op.
    ///
    /// ⚠️ THE QUANTISATION IS THE POINT, and it is the one thing here that must not be
    /// "improved" into finer resolution. `EchoelStudioView.bioSeed` folds the LIVE body at up
    /// to five decimal places, because it wants a different number every time the body moves
    /// — that is the MOMENT. This function wants the opposite: a number that stays the same
    /// across sessions while the running means drift by fractions. So heart rate lands in
    /// whole BPM, HRV in 0.02 steps, coherence in 0.05 steps, breathing in half a breath per
    /// minute. Two takes an hour apart keep the same skeleton; two different people do not.
    ///
    /// A channel that was never measured contributes NOTHING rather than a zero bucket —
    /// otherwise "no HRV source" and "HRV that averages near zero" would be the same person.
    public var seedSalt: UInt64 {
        guard hasBody else { return 0 }
        var s: UInt64 = 0x243F6A8885A308D3
        func fold(_ bucket: UInt64, _ odd: UInt64) {
            s = (s ^ bucket) &* odd
        }
        if heartRateCount > 0 {
            fold(PerformerSignature.bucket(heartRateBPM, step: 1, upTo: 300),
                 0xC2B2AE3D27D4EB4F)
        }
        if hrvCount > 0 {
            fold(PerformerSignature.bucket(hrvNormalized, step: 0.02, upTo: 1),
                 0x165667B19E3779F9)
        }
        if coherenceCount > 0 {
            fold(PerformerSignature.bucket(coherence, step: 0.05, upTo: 1),
                 0x27D4EB2F165667C5)
        }
        if breathCount > 0 {
            fold(PerformerSignature.bucket(breathRate, step: 0.5, upTo: 60),
                 0x9E3779B97F4A7C15)
        }
        // 0 is the caller's "no signature" sentinel, so a real fingerprint may never produce
        // it — the same guard `bioSeed` ends with, for the same reason.
        return s == 0 ? 1 : s
    }

    /// Quantise into a bucket index. Non-finite and negative values fold to 0 rather than
    /// trapping: `UInt64(Float.nan)` is a crash, and every bio channel can legitimately
    /// carry NaN from a dropped rPPG lock.
    private static func bucket(_ v: Float, step: Float, upTo hi: Float) -> UInt64 {
        guard v.isFinite, v > 0, step > 0 else { return 0 }
        let clamped = Swift.min(v, hi)
        return UInt64((clamped / step).rounded())
    }

    // MARK: - Persistence (on-device only)

    /// The defaults key. Deliberately in the app's OWN suite, never the App Group.
    public static let storageKey = "bio.performerSignature"

    /// Read the stored fingerprint, or `.unknown` when there is none or it cannot be read.
    public static func load(from defaults: UserDefaults) -> PerformerSignature {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(PerformerSignature.self, from: data)
        else { return .unknown }
        return decoded
    }

    /// Persist. Silent on failure by design — a fingerprint that cannot be written is a lost
    /// nuance, not a reason to interrupt a performance.
    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: PerformerSignature.storageKey)
    }
}
