//
//  BioHaptics.swift
//  Echoelmusic — Studio (eyes-free performance feedback)
//
//  Pure mapping from transport + bio state to haptic-cue parameters. This is
//  the testable kernel; the side-effecting CoreHaptics engine consumes
//  `HapticCue` values and plays them — the same split the codebase uses
//  elsewhere (e.g. ADMOSCSender's pure `admMessages` vs the UDP sender).
//  That engine is `HapticEngine.swift`, in this directory, and it ships.
//
//  ⛔ THIS SENTENCE FILED THE ENGINE AS FUTURE WORK (#552). The file it was
//  waiting for was written in the same batch; `HapticController` plays `beat()`
//  cues through it on every quarter-note once the user arms haptics. `beat()`
//  is therefore LIVE; `breathPulse()` below is the half with no production
//  caller — see the warning at `HapticController.breath(phase:coherence:)`
//  for why its 0,1-s default makes the obvious wiring site the wrong one.
//
//  Why eyes-free haptics (research §A5): on stage the performer barely looks at
//  the screen, so transport and bio state need a non-visual channel. CoreHaptics
//  exposes two knobs — `intensity` (how strong) and `sharpness` (how crisp:
//  high = urgent/click, low = soft/calm) — both in [0,1]. We map:
//    • beat ticks → transient taps (downbeat/accent strong+sharp, off-beat soft),
//    • bio state → a continuous cue whose intensity swells with the breath and
//      whose sharpness EASES as coherence rises (calm = soft, per Apple's
//      sharpness semantics).
//
//  Pure value types, no allocation, no platform import — safe to evaluate on the
//  control plane and trivially unit-testable on any platform.
//

import Foundation

// MARK: - Haptic cue

/// One haptic event description, independent of CoreHaptics types so it stays
/// pure and testable. The engine layer translates this into a CHHapticEvent.
public struct HapticCue: Equatable, Sendable {

    public enum Kind: Sendable, Equatable {
        /// A momentary tap (CoreHaptics `.hapticTransient`); `duration` ignored.
        case transient
        /// A sustained vibration (CoreHaptics `.hapticContinuous`) of `duration` s.
        case continuous
    }

    public let kind: Kind
    /// Strength, [0..1].
    public let intensity: Float
    /// Crispness, [0..1]. High = sharp/urgent, low = soft/calm.
    public let sharpness: Float
    /// Seconds, for `.continuous`; 0 for `.transient`.
    public let duration: Float

    public init(kind: Kind, intensity: Float, sharpness: Float, duration: Float = 0) {
        self.kind = kind
        self.intensity = BioNormalizer.clamp01(intensity)
        self.sharpness = BioNormalizer.clamp01(sharpness)
        self.duration = Swift.max(0, duration)
    }
}

// MARK: - Mapping

public enum BioHaptics {

    /// Transient tap for a sequencer step. The down-beat (step 0 of the bar) is
    /// the strongest and sharpest landmark; an accented step is full strength but
    /// a touch less sharp than the down-beat; ordinary off-beats are soft and
    /// dull so the bar's pulse is felt, not buzzed.
    ///
    /// - Parameters:
    ///   - isDownbeat: true on the first step of the bar.
    ///   - accent: true on an accented (but non-down) step.
    public static func beat(isDownbeat: Bool, accent: Bool = false) -> HapticCue {
        let intensity: Float
        let sharpness: Float
        if isDownbeat {
            intensity = 1.0; sharpness = 0.9
        } else if accent {
            intensity = 0.85; sharpness = 0.7
        } else {
            intensity = 0.45; sharpness = 0.35
        }
        return HapticCue(kind: .transient, intensity: intensity, sharpness: sharpness)
    }

    /// Continuous bio cue. Intensity swells with the breath (a raised-cosine of
    /// the [0..1] breath phase: 0 at the start of inhale, peak mid-cycle, back to
    /// 0 — a gentle, eyes-free "breathe with me"). Sharpness eases toward 0 as
    /// coherence rises, so a settled, coherent state feels soft rather than buzzy.
    ///
    /// - Parameters:
    ///   - breathPhase: respiratory phase in [0..1].
    ///   - coherence: coherence in [0..1].
    ///   - duration: cue length in seconds (one control tick's worth).
    public static func breathPulse(breathPhase: Float, coherence: Float, duration: Float = 0.1) -> HapticCue {
        let phase = BioNormalizer.clamp01(breathPhase)
        // Raised cosine: 0 at phase 0 and 1, 1 at phase 0.5. Computed in Double
        // (like BioNormalizer.tanhf) to avoid a cos(Float) overload ambiguity.
        let swell = Float(0.5 * (1 - Foundation.cos(2 * Double.pi * Double(phase))))
        let sharpness = BioNormalizer.clamp01(1 - coherence)
        return HapticCue(kind: .continuous, intensity: swell, sharpness: sharpness, duration: duration)
    }
}
