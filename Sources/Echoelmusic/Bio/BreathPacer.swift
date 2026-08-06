//
//  BreathPacer.swift
//  Echoelmusic — Bio
//
//  Paces a breathing guide. The single best-evidenced HRV intervention is slow
//  resonance breathing (~6 breaths/min / ~0.1 Hz, exhale longer than inhale —
//  Lehrer & Gevirtz), which is the DEFAULT pattern. The pacer is driven by a pure
//  `BreathPattern` (see BreathPattern.swift), so it can also pace opt-in hold-based
//  techniques (Box, 4-7-8) without changing this transport.
//
//  SAFETY (this guide must never be able to harm):
//    • Never FORCES anything — it only suggests; the user breathes voluntarily.
//    • Holds (when a hold pattern is chosen) are hard-bounded inside `BreathPattern`
//      so the guide can never instruct a long/strained breath-hold.
//    • Resonance (no-hold) is the default; the UI must keep it preselected, never
//      auto-select a hold pattern, and show `BreathPattern.holdContraindications`
//      (with acknowledgement) BEFORE any hold session. `contraindications` here is
//      the gentler no-hold card for resonance/coherent.
//    • This is self-observation, not therapy or diagnosis.
//
//  Pure, deterministic advance (no timers inside): the host ticks `tick(_:)` from
//  its existing loop. `guidance` is a smooth raised-cosine on active phases and flat
//  on holds (BreathPattern), never a hard sawtooth.
//

import Foundation
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class BreathPacer {

    // MARK: Safe rate bounds (breaths per minute)
    // `nonisolated` so pure, non-MainActor models (e.g. ResonanceFinder) can read
    // these immutable bounds without crossing actor isolation.

    /// ⛔ THIS CONSTANT DOES NOT DO WHAT ITS DOC CLAIMED, and the claim was a SAFETY one, which
    /// is why the correction is here rather than in a scratchpad. It read: "we do not push below
    /// it so the guide can never drive an unsafely slow pace." The guide already does: the
    /// curated set ships Box at 3.75/min and 4-7-8 at 3.158/min, both below this floor, and
    /// neither is clamped by it — `BreathPacer.tick` paces `pattern.cycleSeconds`, and the only
    /// readers of these bounds are `ResonanceFinder`'s sweep (`minRate`/`maxRate`) and nothing
    /// at all (`defaultRate`). `RecordAnchor` already recorded that they "constrain NOTHING";
    /// nobody had reconciled that with the safety wording sitting on the constant itself.
    ///
    /// What actually keeps the guide safe is the PER-SEGMENT clamping in `BreathPattern.init`
    /// (`maxActiveSeconds` 15, `maxHoldFullSeconds` 8, `maxHoldEmptySeconds` 6) plus the
    /// hold-acknowledgement gate — a slow CYCLE built from gentle segments is not the hazard;
    /// a long single breath or a long hold is, and those are the ones that are bounded.
    ///
    /// So these two are the RESONANCE-SEARCH sweep bounds and nothing more. Whether the curated
    /// set should be constrained by a rate floor at all is a founder question (#450), not a
    /// number to quietly widen here. Do not restore the old sentence.
    public nonisolated static let minRate = 5.0
    public nonisolated static let maxRate = 12.0
    /// ~0.1 Hz — the canonical resonance / coherence pace.
    public nonisolated static let defaultRate = 6.0

    // MARK: State

    public private(set) var isRunning = false

    /// The breathing pattern being paced. Defaults to resonance (the recommended,
    /// Grade-A, no-hold technique). Changing it restarts the cycle cleanly so a
    /// switch never lands the user mid-breath.
    public var pattern: BreathPattern = .resonance {
        didSet {
            cycleTime = 0
            recompute()
        }
    }

    /// Seconds elapsed within the current pattern cycle.
    private var cycleTime = 0.0

    /// Guidance amplitude [0,1] for the visual: 1 = lungs full (inhale peak),
    /// 0 = empty (exhale end / empty hold). Smooth, no hard edges.
    public private(set) var guidance = 0.0

    /// What to show the user now: "Breathe in" / "Breathe out" / "Hold".
    public private(set) var instruction = BreathSegmentKind.inhale.instruction

    /// The current segment kind, so the UI can style holds distinctly.
    public private(set) var phaseKind: BreathSegmentKind = .inhale

    public init() { recompute() }

    // MARK: Transport (user-initiated; never auto-starts)

    public func start() { isRunning = true }
    public func stop() { isRunning = false }

    public func reset() {
        cycleTime = 0
        recompute()
    }

    /// Advance the guide by `dt` seconds. No-op while stopped. Pure given state.
    public func tick(_ dt: Double) {
        guard isRunning, dt > 0, dt.isFinite else { return }
        cycleTime += dt
        let cyc = pattern.cycleSeconds
        if cyc > 0 { cycleTime = cycleTime.truncatingRemainder(dividingBy: cyc) }
        recompute()
    }

    // MARK: Curve

    private func recompute() {
        let s = pattern.sample(atCycleTime: cycleTime)
        guidance = s.amplitude
        instruction = s.instruction
        phaseKind = s.kind
    }

    // MARK: Safety copy (shown by the UI before a NO-HOLD session)

    /// Plain, non-medical cautions for resonance/coherent (no-hold) breathing. Hold
    /// patterns use `BreathPattern.holdContraindications` instead. Shown BEFORE a
    /// session — the guide is for self-observation, not therapy. No diagnostic or
    /// therapeutic claims.
    public static let contraindications: [String] = [
        "Breathe gently — never strain or hold your breath.",
        "Stop if you feel dizzy or short of breath.",
        "If you have asthma/COPD, a heart condition, a panic/anxiety disorder, "
            + "or are pregnant, check with a healthcare provider first.",
        "This is for self-observation, not medical diagnosis or treatment."
    ]
}
