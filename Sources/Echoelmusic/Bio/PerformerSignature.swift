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
    /// legitimate rather than double-counting. The LIVE heart rate already sets the tempo —
    /// but `genreTempo` octave-folds it, and for a body whose octave overshoots the window's
    /// ceiling it returns one of the two BOUNDS. Walked over contemplation (44…66): 68, 70,
    /// 72, 74 and 76 all become 66; 78 through 88 all become 44. Roughly half of ordinary
    /// resting hearts land on two numbers, non-monotonically. The tilt is applied AFTER that
    /// fold and restores what the fold erased. (⛔ The first version of this paragraph said
    /// "41 % … collapses onto the floor" — that is `genreTempo`'s description of the bug
    /// #237 FIXED, quoted in the present tense. See `StudioCalculator.tilted` for the walk.)
    ///
    /// 50…90 BPM is the span the mapping opens across, chosen as the ordinary waking resting
    /// range rather than the physiological extremes: anchoring on 30…200 would compress every
    /// real performer into the middle few percent and make the whole feature inaudible. A
    /// trained endurance athlete at 45 and a habitually fast heart at 95 both saturate, which
    /// is the honest behaviour — the tilt is a position among people, not a measurement.
    public var tempoTilt: Double {
        guard heartRateCount > 0 else { return 0 }
        let bpm = Double(heartRateBPM)
        guard bpm.isFinite, bpm > 0 else { return 0 }
        let span = PerformerSignature.restingSpan
        let unit = (bpm - span.lowerBound) / (span.upperBound - span.lowerBound)
        return Swift.min(Swift.max(unit, 0), 1) * 2 - 1
    }

    /// The resting-heart-rate span `tempoTilt` opens across. See its doc for why it is the
    /// ordinary waking range and not the physiological one.
    public static let restingSpan: ClosedRange<Double> = 50...90

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
