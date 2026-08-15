//
//  AutoAttune.swift
//  Echoelmusic — Sequencer
//
//  #608 Scheibe 1 (Founder 2026-08-15): the decision core of the OPTIONAL Auto mode —
//  „vibe catchen, sanft intervenieren, Kohärenz herstellen". It maps the body state the
//  composer ALREADY derives (`BioComposer.musicalState` — the one definition, #416; no
//  second formula is minted here) to gentle steering targets for the mood dials
//  (darkness · liveliness · tension), applied through `WeatherMood.blend` at the ONE
//  choke point where the weather influence already lands (`makeComposerInput`).
//
//  ⚠️ INVARIANTS, load-bearing — a refactor that breaks any of these converts a
//  structural guarantee into convention (#398 double-writer class):
//  · NO timer, NO bus subscription, NO SwiftUI, NO @Observable, NO @MainActor. This
//    type is a pure value; it can only run where `makeComposerInput` runs, so a
//    re-seed flood is impossible by construction — there is no loop to mis-rate.
//    ⚠️ #608b PRECISION (the first version said "cadence is STRUCTURALLY the evolve
//    tick", which was a half-truth): `makeComposerInput` is also reached by the
//    read-only variation audition and by every debounced dial edit. The fold
//    therefore ages this type's hold state ONLY on `advanceEvolution` calls — a
//    real take (the evolve tick, or a user-triggered regenerate). Auditions steer
//    with the current policy but never advance it.
//  · NO tempo. Auto mode owns zero tempo code in any state; the only sanctioned
//    bio→clock path is the Flow-Servo (T1/T2). `AutoModeStartsOffAndOwnsNoTempoTests`
//    scans this file for tempo calls and must stay at zero hits.
//  · IDENTITY when off/neutral/paused: a `Steer` with `intensity == 0` — or a target
//    equal to its base — is byte-identical through `WeatherMood.blend` (the Golden
//    law the weather feature already earned; this type inherits it by reuse).
//
//  ⚠️ VALENCE RED LINE (EngineBus EU-AI-Act framing, PerformerSignature „not a
//  statement about the human being"): `calm` and `arousal` here are CONTROL SIGNALS
//  derived from HRV-coherence and cardiac drive — never an emotion estimate, never a
//  mood-of-the-person claim, and no user-facing copy may present them as one.
//
//  GENTLENESS, as numbers (argue with them here, not at call sites): a target may sit
//  at most `maxTargetDelta` (0.15) from its base, the blend intensity is fixed at
//  `steerIntensity` (0.3) — a CONSTANT capped offset of at most 0.045, recomputed
//  each take from the user's pristine dials. ⚠️ #608b: it does NOT accumulate across
//  ticks (nothing writes back to the stored mood; the first version's "ONE evolve
//  tick moves a dial by at most 0.045" implied later ticks move further — they never
//  do). Whether 0.045 is AUDIBLE is a founder device probe, registered open; if it
//  is not, slice 2's candidate is a slew carried in `State`, not a bigger constant.
//  Policy changes carry hysteresis (enter/exit bands ≥ 0.15 apart) and a minimum
//  hold of one full advanceEvolution call, so a single-window threshold crossing
//  can never whipsaw the steering between OPPOSING policies. Entering a policy FROM
//  `neutral` is exempt from the hold (#608b): leaving rest is an entry, not a
//  reversal — a body that is already clearly settled when the toggle turns on
//  steers on the FIRST consult, not the second.
//
//  The composer switches character at `darkness > 0.6` (and reads `romance > 0.5`,
//  which this type deliberately never steers). Targets are clamped to the SAME SIDE
//  of the darkness switch as their base: with intensity < 1 the blended value lies
//  strictly between base and target, so the steered darkness can never cross the
//  literal and flip the take's character as a side effect.
//

import Foundation

/// Pure decision core for the optional Auto mode. See the file header for the
/// invariants; see `AutoModeRow` (EchoelStudioView) for the door.
public enum AutoAttune {

    /// The steering policy, with hysteresis. `neutral` steers nothing (identity).
    public enum Policy: String, Sendable, Equatable {
        /// Body is neither settled nor driving — Auto mode listens and does not steer.
        case neutral
        /// Sustained high coherence: soften — tension and liveliness ease down,
        /// timbre may sit slightly darker/warmer.
        case settled
        /// Sustained sympathetic drive: enliven — liveliness up, a touch more
        /// tension, slightly brighter.
        case energetic
    }

    /// Carried across evolve ticks by the caller (`@State` in EchoelStudioView).
    public struct State: Sendable, Equatable {
        public var policy: Policy
        /// Completed evolve ticks spent in `policy`. A policy must have held at
        /// least one full tick before it may reverse (the minimum-hold law).
        public var ticksInPolicy: Int
        /// Per-parameter session pause (the "user gesture wins" registry). Slice 1
        /// carries the registry; slice 4 wires the gesture signals that set it.
        /// A paused parameter's target is pinned to its base — identity through
        /// the blend — for the rest of the session.
        public var pausedDarkness: Bool
        public var pausedLiveliness: Bool
        public var pausedTension: Bool

        public init(policy: Policy = .neutral, ticksInPolicy: Int = 0,
                    pausedDarkness: Bool = false, pausedLiveliness: Bool = false,
                    pausedTension: Bool = false) {
            self.policy = policy
            self.ticksInPolicy = ticksInPolicy
            self.pausedDarkness = pausedDarkness
            self.pausedLiveliness = pausedLiveliness
            self.pausedTension = pausedTension
        }
    }

    /// One tick's steering: absolute targets plus the blend intensity. Intensity 0
    /// (or target == base) is the exact identity through `WeatherMood.blend`.
    public struct Steer: Sendable, Equatable {
        public var darknessTarget: Float
        public var livelinessTarget: Float
        public var tensionTarget: Float
        public var intensity: Float
    }

    // MARK: - The numbers (one definition each)

    /// Hysteresis bands — enter and exit are ≥ 0.15 apart on purpose: the value in
    /// between keeps the PREVIOUS policy, so jitter around one threshold cannot
    /// oscillate the steering.
    public static let enterCalm: Float = 0.65
    public static let exitCalm: Float = 0.50
    public static let enterArousal: Float = 0.65
    public static let exitArousal: Float = 0.50
    /// A target may differ from its base by at most this much.
    public static let maxTargetDelta: Float = 0.15
    /// Fixed blend intensity while steering — the user's dialled character always
    /// dominates (mirrors the weather block's "the body still dominates" contract).
    public static let steerIntensity: Float = 0.3
    /// The composer's character switch (`darkness > 0.6` in BioComposer). Targets
    /// never cross it from their base's side.
    public static let composerDarknessSwitch: Float = 0.6

    // MARK: - Decision

    /// Map body state to steering. `calm`/`arousal` are `BioComposer.musicalState`
    /// outputs (reused verbatim by the caller — never recomputed here or elsewhere).
    /// Bases are the mood values the blend would start from (post-weather, so Auto
    /// steers on top of the same stack the user hears).
    ///
    /// Non-finite input returns the identity steer and leaves `previous` untouched:
    /// a frozen or broken signal must neither steer nor advance the hold counters.
    public static func decide(calm: Float, arousal: Float,
                              baseDarkness: Float, baseLiveliness: Float,
                              baseTension: Float,
                              previous: State) -> (steer: Steer, state: State) {
        let identity = Steer(darknessTarget: baseDarkness,
                             livelinessTarget: baseLiveliness,
                             tensionTarget: baseTension,
                             intensity: 0)
        guard calm.isFinite, arousal.isFinite,
              baseDarkness.isFinite, baseLiveliness.isFinite, baseTension.isFinite
        else { return (identity, previous) }

        // Hysteresis: where does the body point THIS tick, seen from the previous policy?
        let desired: Policy
        switch previous.policy {
        case .neutral:
            if calm > Self.enterCalm { desired = .settled }
            else if arousal > Self.enterArousal { desired = .energetic }
            else { desired = .neutral }
        case .settled:
            if calm < Self.exitCalm {
                desired = arousal > Self.enterArousal ? .energetic : .neutral
            } else { desired = .settled }
        case .energetic:
            if arousal < Self.exitArousal {
                desired = calm > Self.enterCalm ? .settled : .neutral
            } else { desired = .energetic }
        }

        // Minimum hold: a policy entered on the previous tick (ticksInPolicy 0) may
        // not reverse yet — the steering moves in bars, not in single readings.
        // Leaving `neutral` is exempt (#608b): that is an ENTRY, not a reversal —
        // without the exemption a body that is already settled when Auto turns on
        // waits a full extra consult for no stated reason (review finding 4).
        var next = previous
        if desired != previous.policy && previous.ticksInPolicy < 1
            && previous.policy != .neutral {
            next.ticksInPolicy += 1
            return (steer(for: previous.policy, state: previous,
                          baseDarkness: baseDarkness, baseLiveliness: baseLiveliness,
                          baseTension: baseTension), next)
        }
        if desired == previous.policy {
            next.ticksInPolicy += 1
        } else {
            next.policy = desired
            next.ticksInPolicy = 0
        }
        return (steer(for: next.policy, state: next,
                      baseDarkness: baseDarkness, baseLiveliness: baseLiveliness,
                      baseTension: baseTension), next)
    }

    /// Targets per policy — deltas, then the caps: ±`maxTargetDelta`, [0…1], and
    /// darkness stays on its base's side of the composer switch.
    private static func steer(for policy: Policy, state: State,
                              baseDarkness: Float, baseLiveliness: Float,
                              baseTension: Float) -> Steer {
        let dD: Float, dL: Float, dT: Float
        switch policy {
        case .neutral:
            return Steer(darknessTarget: baseDarkness, livelinessTarget: baseLiveliness,
                         tensionTarget: baseTension, intensity: 0)
        case .settled:
            // Soften: ease tension and density, sit a touch warmer/darker.
            dD = 0.10; dL = -0.15; dT = -0.15
        case .energetic:
            // Enliven: more motion, a touch more bite, slightly brighter.
            dD = -0.05; dL = 0.15; dT = 0.10
        }
        var dark = target(baseDarkness, delta: dD)
        // Same-side clamp against the composer's `darkness > 0.6` switch. With
        // intensity < 1 the blend lands strictly between base and target, so a
        // target ON the switch value cannot carry the blended result across it.
        if baseDarkness <= Self.composerDarknessSwitch {
            dark = Swift.min(dark, Self.composerDarknessSwitch)
        } else {
            dark = Swift.max(dark, Self.composerDarknessSwitch)
        }
        return Steer(
            darknessTarget: state.pausedDarkness ? baseDarkness : dark,
            livelinessTarget: state.pausedLiveliness ? baseLiveliness
                                                     : target(baseLiveliness, delta: dL),
            tensionTarget: state.pausedTension ? baseTension
                                               : target(baseTension, delta: dT),
            intensity: Self.steerIntensity)
    }

    private static func target(_ base: Float, delta: Float) -> Float {
        let capped = Swift.min(Swift.max(delta, -Self.maxTargetDelta), Self.maxTargetDelta)
        return (base + capped).clamped(to: 0...1)
    }
}
