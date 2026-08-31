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
//  ⭐ ONE RUN PER SOURCE — and this is the ledger's prescribed shape, not a new idea.
//  `scratchpads/HARNESS_LEDGER.md` records "DEAD-END: einen geteilten Detektor „bei
//  Quellenwechsel zurücksetzen"", and `Bio/BioEventPublisher.swift` carries the long version:
//  **sources do not take turns.** `stopBioSource()` stops camera/strap/demo but NOT
//  `HealthKitBioPublisher`, which `EchoelmusicApp` starts at first bio use and which keeps
//  publishing alongside whatever the player picked. So `bus.latestBio` INTERLEAVES.
//
//  ⛔ #813 AND #920 BOTH BUILT THE SHARED SHAPE THE LEDGER HAD ALREADY BURIED, and the cost was
//  live, not hypothetical: `HealthKitBioPublisher` publishes an honest `coherence: 0`, so
//  `isMeasured(.coherence,…)` is false for every wrist frame, so the single shared tracker
//  called `reset()` roughly every 4–5 s — on a ~1 Hz camera feed that is the whole history,
//  repeatedly, and the morph could rarely reach the consumer's 0.10 deadband at all. #920's
//  source-switch guard sat ON TOP of that and could not see it. Per-source state removes the
//  class instead of trading one artefact for another: each sensor's trajectory stays
//  continuous, an unmeasured wrist frame forgets only the WRIST, and a hand-over reports the
//  new sensor's own run, which has no history and is therefore silent — the #920 property,
//  obtained without a cross-source reset.
//
//  ⚠️ AN UNMEASURED OR CORRUPT FRAME HOLDS, IT DOES NOT ZERO. Returning 0 for a wrist frame
//  would make the morph flicker to neutral every few seconds even with per-source runs — the
//  same deafening one layer down. A frame that carries no coherence says nothing about the
//  trend, so the last reported value stands. Only that source's history is dropped.
//
//  ⚠️ RESET/HOLD IS THE SAFETY PROPERTY, not a convenience. The situations that would otherwise
//  mint a spurious trend, each handled below and each with a claim: an unmeasured stretch (the
//  neutral 0.5 placeholder jumping to a real reading), a NON-FINITE reading (`clamped(to:)`
//  maps NaN to the LOWER bound, so in a signed range a NaN becomes −1 — a full-scale FALLING
//  trend, the most extreme spurious value this type can produce), a long gap (a paused session
//  resuming), a non-positive interval (a duplicate or out-of-order stamp), and a sensor
//  hand-over. **No count is written here on purpose** (#818): the list grew twice in two days
//  and every number attached to it went stale, once inside the very commit that repaired it.

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

    /// One sensor's history. Never shared — see the header for the ledger entry that buried
    /// the shared shape twice.
    private struct Run: Sendable, Equatable {
        var lastCoherence: Float
        var lastTimestamp: TimeInterval
        var smoothed: Float
    }

    /// One `Run` per `BioSource`. A dictionary rather than an array because that is the shape
    /// `BioEventPublisher` already uses for exactly this problem (`[BioSource: BioEventGraph]`),
    /// and because it needs no assumption about which enum case is last. Bounded by
    /// `BioSource`'s case count; this type lives on the MAIN ACTOR, never the audio thread, so
    /// the allocation is not an audio-thread concern (see the header).
    private var runs: [BioSource: Run] = [:]

    /// The trend last REPORTED, −1…1 — the value of whichever source spoke most recently.
    /// Zero until some source has two measured readings.
    public private(set) var value: Float = 0

    public init() {}

    /// Forget every source's history. The next measured reading starts a new run and reports 0.
    public mutating func reset() {
        runs.removeAll()
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
    ///     this one exists precisely so every caller has to answer the question). It selects
    ///     the run; it is never compared against a previous frame's source.
    ///   - timestamp: the frame's own stamp, in the bus's `CFAbsoluteTime` seconds.
    /// - Returns: the trend now being reported, the same value as `value`.
    @discardableResult
    public mutating func update(coherence: Float,
                                measured: Bool,
                                source: BioSource,
                                at timestamp: TimeInterval) -> Float {
        guard measured, coherence.isFinite, timestamp.isFinite else {
            // Drop only THIS sensor's history — a wrist frame carrying no coherence says
            // nothing about the camera's trajectory — and HOLD the reported value. Returning 0
            // here is what made the interleaved wrist feed deafen the whole tracker.
            runs[source] = nil
            return value
        }
        guard var run = runs[source] else {
            // First measured reading this sensor has produced: one point has no slope. A
            // hand-over lands here, which is why no cross-source reset is needed.
            runs[source] = Run(lastCoherence: coherence, lastTimestamp: timestamp, smoothed: 0)
            value = 0
            return 0
        }
        let dt = timestamp - run.lastTimestamp
        // ⛔ THIS WAS A `defer` FOR ONE REVIEW PASS AND THAT WAS A REAL BUG. A `defer` stores the
        // new reading on EVERY return path — including the `dt <= 0` one. An OUT-OF-ORDER frame
        // (an older stamp) would then become this run's baseline, and the next frame's dt would
        // be measured from that older moment: an inflated interval, so a real slope reads as a
        // slower one. Exact duplicates are excluded upstream by the voices'
        // `frame.timestamp != lastTimestamp` check, but out-of-order is not, and a producer that
        // relies on its caller's deduplication is the shape this repo keeps paying for. Each
        // path stores explicitly, and the hold path stores nothing.
        guard dt > 0 else {
            // A duplicate or out-of-order frame. Hold the reported value AND this run's
            // baseline: the older reading must not become the anchor the next real frame is
            // measured from.
            return value
        }
        guard dt <= Self.newRunAfterSeconds else {
            // This sensor paused. The difference across the gap is not a slope.
            runs[source] = Run(lastCoherence: coherence, lastTimestamp: timestamp, smoothed: 0)
            value = 0
            return 0
        }
        let perSecond = (coherence - run.lastCoherence) / Float(dt)
        // ⚠️ `clamped(to:)` MAPS NaN TO THE LOWER BOUND, which in a SIGNED range means a NaN
        // becomes −1 — a full-scale FALLING trend, not a neutral 0. That is right for the unit
        // ranges the helper was written for and a landmine here. It cannot fire today: the
        // `isFinite` guard at the top rejects a bad reading, `lastCoherence` is only ever stored
        // from a finite one, and `dt` is bounded above by `newRunAfterSeconds` and below by the
        // `dt > 0` guard, so this division is finite by construction. It is written down because
        // the day someone relaxes the entry guard, the failure is silent and points the wrong way.
        let normalized = (perSecond / Self.fullScaleRisePerSecond).clamped(to: -1...1)
        // One-pole smoothing, RATE-BASED so an irregular frame interval does not change the
        // effective time constant (the house rule for slews).
        let alpha = 1 - exp(-Float(dt) / Self.smoothingSeconds)
        run.smoothed += alpha * (normalized - run.smoothed)
        run.lastCoherence = coherence
        run.lastTimestamp = timestamp
        runs[source] = run
        value = run.smoothed.clamped(to: -1...1)
        return value
    }
}
