//
//  FlashGuard.swift
//  Echoelmusic — Studio (visual safety)
//
//  WCAG 2.3.1 epilepsy safety as a pure, reusable primitive. Bio-reactive
//  visuals must never strobe: nothing may flash more than 3 times per second,
//  and a "general flash" is a luminance swing ≥10% of max where the darker
//  state is below 0.80 relative luminance (W3C). This type encodes those rules
//  so every visual clamps the same way, and honors Reduce Motion by stopping
//  oscillation entirely.
//
//  Pure value type — no platform import, trivially unit-testable.
//

import Foundation

public enum FlashGuard {

    /// WCAG 2.3.1 hard limit: at most three flashes per second.
    public static let maxFlashHz: Double = 3.0

    /// A general flash needs a relative-luminance change of at least this
    /// fraction of the maximum (W3C: 10%).
    public static let luminanceDeltaThreshold: Double = 0.10

    /// …and only when the darker of the two states is below this relative
    /// luminance (W3C: 0.80). Two bright states swinging do not count.
    public static let darkStateThreshold: Double = 0.80

    /// Clamps an oscillation frequency (Hz) to the WCAG-safe range. Returns 0
    /// when Reduce Motion is on, so the caller renders a still frame.
    public static func safeFrequency(_ hz: Double, reduceMotion: Bool = false) -> Double {
        guard !reduceMotion else { return 0 }
        guard hz.isFinite else { return 0 }
        return Swift.max(0, Swift.min(hz, maxFlashHz))
    }

    /// The rate a visual FIELD actually flashes at — which is NOT always the rate
    /// its phase is integrated at, and that gap shipped a violation.
    ///
    /// A style whose visible field is the SQUARED amplitude (energy ∝ amplitude²,
    /// the physically correct quantity for interference fringes) oscillates at
    /// TWICE its phase rate, because `sin²(x) = ½(1 − cos 2x)`. `MetalBioView`'s
    /// Rings look fed the full 2.5 Hz capped phase into a squared field and so
    /// reached 5 Hz, while every frequency clamp in the codebase correctly read
    /// "2.5 ≤ 3, safe". Clamping the input is necessary and not sufficient — the
    /// NONLINEARITY has to be counted too.
    ///
    /// - Parameters:
    ///   - phaseRateHz: the rate the phase is advanced at (already clamped).
    ///   - phaseMultiplier: what the style multiplies the shared phase by.
    ///   - squared: true when the rendered field is amplitude², not amplitude.
    /// - Returns: the dominant temporal frequency of the rendered field, in Hz.
    ///            Non-finite input yields 0 (a still frame is always safe).
    ///
    /// Use it when adding or retuning a style: the result must be `<= maxFlashHz`.
    public static func effectiveFieldHz(phaseRateHz: Double,
                                       phaseMultiplier: Double,
                                       squared: Bool) -> Double {
        guard phaseRateHz.isFinite, phaseMultiplier.isFinite else { return 0 }
        let base = Swift.abs(phaseRateHz) * Swift.abs(phaseMultiplier)
        return squared ? base * 2 : base
    }

    /// Whether a transition between two relative luminances [0,1] counts as a
    /// WCAG "general flash" (such a pair repeating >3×/s is the seizure risk).
    public static func isFlash(from a: Double, to b: Double) -> Bool {
        let lo = Swift.min(a, b)
        let hi = Swift.max(a, b)
        return (hi - lo) >= luminanceDeltaThreshold && lo < darkStateThreshold
    }

    /// Slew-limits a luminance step so a value stream can never strobe: the move
    /// from `previous` toward `target` is capped to `maxDelta` per step.
    public static func limitedLuminance(from previous: Double, to target: Double,
                                        maxDelta: Double = luminanceDeltaThreshold) -> Double {
        let delta = target - previous
        if delta > maxDelta { return previous + maxDelta }
        if delta < -maxDelta { return previous - maxDelta }
        return target
    }

    /// The next dimmer value a lighting sender emits, given its slew anchor.
    /// The ONE flash-safe decision shared by ArtNet and sACN (so both fixture
    /// protocols get an identical, testable guarantee):
    ///   • blackout        → 0 (an instant cut is a single edge, not a strobe)
    ///   • no history (lastDimmer < 0) → the target (nothing to ramp from)
    ///   • otherwise       → the target, slew-limited to `maxDelta`/tick.
    /// `lastDimmer` is the anchor to update with the return value.
    public static func slewedDimmer(from lastDimmer: Float, to mastered: Float,
                                    blackout: Bool, maxDelta: Double = 0.08) -> Float {
        if blackout { return 0 }
        if lastDimmer < 0 { return mastered }
        return Float(limitedLuminance(from: Double(lastDimmer), to: Double(mastered),
                                      maxDelta: maxDelta))
    }
}
