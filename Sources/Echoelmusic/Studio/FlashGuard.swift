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
}
