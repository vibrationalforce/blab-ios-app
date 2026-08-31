//  CoherenceTrend.swift
//  Echoel — the producer for a bio→sound branch that has been unreachable since it was written.
//
//  WHY THIS EXISTS. `EchoelDDSP.applyBioReactive` takes a `coherenceTrend` in −1…1 and uses it
//  for the rising/falling SPECTRAL MORPH: below a 0.10 deadband it releases to the patch shape,
//  above it it morphs toward `.natural` (rising) or `.metallic` (falling), capped at 0.30.
//  Every `…BioParams(` construction site in `Sources/` passed the literal `coherenceTrend: 0`,
//  so `trendMag` was exactly 0 on every frame the shipped app could produce and the entire
//  else-branch was dead code (#496 measured it; the note at the consumer says in as many words
//  "deriving one from the coherence history is a real slice — this branch is what it will
//  drive"). This is that slice.
//
//  ⚠️ NO WELLBEING VALENCE. The consumer's own comment states the rule and it binds this file
//  too: rising coherence is an ENGINEERING mapping. No user-facing copy may call the rising
//  sound "purer", "calmer", "better" or "healthier". This type produces a signed number; it
//  says nothing about a person.
//
//  WHERE IT RUNS. `PolySynthVoice` and `BioReactiveSynthVoice` build their bio params on the
//  MAIN ACTOR and hand them to the render thread through a lock-free SPSC queue; only
//  `applyBioReactive` is on the audio thread. So this type has NO audio-thread obligations —
//  it may use `exp`, it holds `Optional`s, and it is a plain `struct` each voice owns one of.
//  Two independent trackers over the same frame sequence produce the same output, which is why
//  this is not put on the bus: no new field on `BioSampleFrame`, so the six frame construction
//  sites, the OSC egress and the wire contract are all untouched by this slice.
//
//  ⚠️ THE SCALE IS AN ESTIMATE AND IS NAMED SO IT CAN BE ARGUED WITH. `fullScaleRisePerSecond`
//  says how fast coherence must climb to reach |trend| = 1. Coherence moves slowly and the
//  frames arrive at ~1 Hz (CLAUDE.md: the POLL is 10 Hz, the APPLY rate is ~1 Hz), so a value
//  chosen for a 10 Hz stream would be off by an order of magnitude. 0.05/s means a climb of
//  0.05 coherence per second is "as fast as this mapping cares about"; a typical slow rise of
//  ~0.02/s lands near 0.4, i.e. just past the deadband, morph ≈ 0.10 of the 0.30 cap. That is
//  deliberately subtle. NEEDS-FOUNDER-VERIFY: run a session, let coherence climb and fall, and
//  say whether the timbre shift is audible-but-not-distracting. The number is the one thing
//  here that cannot be settled in the repo.
//
//  ⚠️ RESET IS THE SAFETY PROPERTY, not a convenience. FOUR situations would otherwise mint a
//  spurious trend: unmeasured→measured (the neutral 0.5 placeholder jumping to a real reading),
//  a SOURCE SWITCH (any sensor hand-over, not only demo→body), a long gap (a paused session
//  resuming), and a non-positive interval (a duplicate or out-of-order stamp — held, not reset,
//  so a late frame cannot become the baseline). Each is handled below and each has a claim.
//
//  ⛔ THIS PARAGRAPH LISTED THE SOURCE SWITCH BEFORE THE CODE HAD IT, and so did CLAUDE.md — for
//  the whole of #813. Both named three safeguards, counted the absent switch among them and left
//  the present dt ≤ 0 hold out. #920 built the missing one instead of retracting the sentence,
//  because the artefact is real and measured (see the guard at the switch below). The lesson is
//  not "keep the doc in sync": it is that a safety list is the one kind of prose whose items must
//  each be pointed at a line of code when written, because a wrong entry there reads as coverage.

import Foundation

/// Derives a signed coherence trend (−1 falling … 0 stable … +1 rising) from a sequence of
/// coherence readings. Pure and deterministic: the same frame sequence always yields the same
/// values, with no clock of its own — the caller supplies the timestamp.
public struct CoherenceTrend: Sendable, Equatable {

    /// Coherence units per second that map to |trend| = 1. See the file header: this is the
    /// one number here that needs an ear, not an argument.
    public static let fullScaleRisePerSecond: Float = 0.05

    /// Smoothing time constant. A single coherence sample is noisy and the consumer rebuilds a
    /// spectral buffer whenever the morph changes, so the raw per-frame slope must not reach it.
    /// 4 s ≈ four frames at the ~1 Hz apply rate.
    public static let smoothingSeconds: Float = 4

    /// A gap longer than this is treated as a NEW run rather than a slope. Six seconds is the
    /// freshness window the bio surfaces already use for "this reading is stale".
    public static let newRunAfterSeconds: TimeInterval = 6

    private var lastCoherence: Float?
    private var lastTimestamp: TimeInterval?
    /// The source the history belongs to. A trend is a statement about ONE sensor's readings;
    /// see the sensor-change guard in `update` for why crossing sensors is not one.
    private var lastSource: BioSource?
    private var smoothed: Float = 0

    /// The current trend, −1…1. Zero until two measured readings have arrived.
    public private(set) var value: Float = 0

    public init() {}

    /// Forget the history. The next measured reading starts a new run and produces 0.
    public mutating func reset() {
        lastCoherence = nil
        lastTimestamp = nil
        lastSource = nil
        smoothed = 0
        value = 0
    }

    /// Feed one frame's coherence.
    ///
    /// - Parameters:
    ///   - coherence: the RAW coherence (`frame.coherence`), not the neutral-substituted
    ///     `coherenceForSound`. Substituting a neutral for an unmeasured channel is right for a
    ///     level and wrong for a derivative — the substitution itself would read as a movement.
    ///   - measured: whether this frame measured coherence at all. The house test is
    ///     `frame.coherence > 0` (`BioModulationMap.isMeasured(.coherence, in:)`); it is passed
    ///     in rather than re-derived so a caller with a better answer can give one.
    ///   - source: which sensor produced this reading. It has NO default on purpose
    ///     (#431/#440/#443: a defaulted argument no call site writes appears in no diff, and
    ///     this one exists precisely so every caller has to answer the question).
    ///   - timestamp: the frame's own stamp, in the bus's `CFAbsoluteTime` seconds.
    /// - Returns: the updated trend, the same value as `value`.
    @discardableResult
    public mutating func update(coherence: Float,
                                measured: Bool,
                                source: BioSource,
                                at timestamp: TimeInterval) -> Float {
        guard measured, coherence.isFinite, timestamp.isFinite else {
            reset()
            return 0
        }
        // ⛔ A SENSOR CHANGE IS NOT A BODY CHANGE, and until #920 nothing said so. Measured on
        // the real constants: a hand-over from a camera reading 0.20 to a strap reading 0.75 two
        // seconds later mints a trend of **0.393** — nearly four times the consumer's 0.10
        // deadband, and LARGER than a genuine strong rise (0.221 for a real 0.05/s climb). The
        // player would hear the spectral morph swing because they changed sensor, not because
        // their body did. Treated exactly like the first frame of a new run: take the baseline,
        // report nothing.
        //
        // ⚠️ THE GAP GUARD BELOW DOES NOT COVER THIS. It fires only after `newRunAfterSeconds`;
        // a hand-over INSIDE that window — the simulator, HealthKit, a strap already connected —
        // is well under it, and that is exactly the case that produced 0.393.
        //
        // ⛔ CLAUDE.md CLAIMED THIS RESET EXISTED BEFORE IT DID. Its bio table listed the three
        // resets as "ungemessen→gemessen, Quellenwechsel, langes Loch" while the built third one
        // was the duplicate/out-of-order stamp hold. The doc named a safeguard that was absent
        // and omitted one that was present — #920 built the missing one rather than retracting
        // it, because the artefact it prevents is real and measured.
        guard source == lastSource else {
            lastSource = source
            lastCoherence = coherence
            lastTimestamp = timestamp
            smoothed = 0
            value = 0
            return 0
        }
        // ⛔ THIS WAS A `defer` FOR ONE REVIEW PASS AND THAT WAS A REAL BUG. A `defer` here
        // stores the new reading on EVERY return path below — including the `dt <= 0` one. An
        // OUT-OF-ORDER frame (an older stamp) would then become the new baseline, and the next
        // frame's dt would be measured from that older moment: an inflated interval, so a real
        // slope reads as a slower one. Exact duplicates are excluded upstream by the voices'
        // `frame.timestamp != lastTimestamp` check, but out-of-order is not, and a producer that
        // relies on its caller's deduplication is the shape this repo keeps paying for. Each
        // path now stores explicitly, and the hold path stores nothing.
        guard let previous = lastCoherence, let previousStamp = lastTimestamp else {
            // First measured reading of a run: a single point has no slope.
            lastCoherence = coherence
            lastTimestamp = timestamp
            smoothed = 0
            value = 0
            return 0
        }
        let dt = timestamp - previousStamp
        guard dt > 0 else {
            // A duplicate or out-of-order frame. Hold the current value AND the baseline: the
            // older reading must not become the anchor the next real frame is measured from.
            return value
        }
        guard dt <= Self.newRunAfterSeconds else {
            // The session paused. The difference across the gap is not a slope.
            lastCoherence = coherence
            lastTimestamp = timestamp
            smoothed = 0
            value = 0
            return 0
        }
        let perSecond = (coherence - previous) / Float(dt)
        // ⚠️ `clamped(to:)` MAPS NaN TO THE LOWER BOUND, which in a SIGNED range means a NaN
        // becomes −1 — a full-scale FALLING trend, not a neutral 0. That is right for the unit
        // ranges the helper was written for and a landmine here. It cannot fire today: the
        // `isFinite` guard at the top rejects a bad reading, `previous` is only ever stored from
        // a finite one, and `dt` is bounded above by `newRunAfterSeconds` and below by the
        // `dt > 0` guard, so this division is finite by construction. It is written down because
        // the day someone relaxes the entry guard, the failure is silent and points the wrong way.
        let normalized = (perSecond / Self.fullScaleRisePerSecond).clamped(to: -1...1)
        // One-pole smoothing, RATE-BASED so an irregular frame interval does not change the
        // effective time constant (the house rule for slews).
        let alpha = 1 - exp(-Float(dt) / Self.smoothingSeconds)
        smoothed += alpha * (normalized - smoothed)
        value = smoothed.clamped(to: -1...1)
        lastCoherence = coherence
        lastTimestamp = timestamp
        return value
    }
}
