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

    /// Phase damping the Rings look applies before squaring its field. Interpolated
    /// INTO the Metal shader source (`MetalBioView.shaderSource`) rather than
    /// duplicated there, so this constant and the shader cannot drift apart — the
    /// first version of this fix mirrored the number in a comment and a test, which
    /// is a guard that passes while the shader says something else.
    /// 0.5 × 2 (the fold) = 1.0, i.e. the squared field lands exactly on the cap.
    public static let ringsPhaseDamping: Double = 0.5

    /// The SAME value as a string, because it is interpolated into Metal source that
    /// is compiled at RUNTIME. Interpolating the `Double` directly would emit
    /// whatever Swift's description produces; a hand-written literal is exact and
    /// cannot become locale-dependent, and a bad literal here would fail as a shader
    /// COMPILE error on device (a black visual), not at build time — so
    /// `FlashGuardTests` asserts the two agree.
    public static let ringsPhaseDampingLiteral = "0.5"

    /// The rate a visual FIELD actually flashes at — which is NOT always the rate
    /// its phase is integrated at, and that gap shipped a WCAG violation.
    ///
    /// THE LAW, stated precisely (the loose version cost a re-review): only a
    /// **non-monotone** operation on a phase-bearing quantity adds flashes, because
    /// only a non-monotone map can create new extrema. Those are:
    ///   • squaring a BIPOLAR signal — `sin²x = ½(1 − cos 2x)`, rate ×2
    ///   • `abs()` of a bipolar signal — folds identically, rate ×2
    ///   • a PRODUCT of two phase-bearing factors — adds a sum sideband at f₁+f₂
    /// Monotone maps do NOT add flashes, however nonlinear they look: `pow` on a
    /// non-negative field, `clamp`, `smoothstep`, an S-curve. They change the SHAPE
    /// of each flash (and can make it harsher), never the count per second.
    ///
    /// This is what `MetalBioView`'s Rings look got wrong: it fed the full 2.5 Hz
    /// capped phase into a squared bipolar field and so reached 5 Hz, while every
    /// frequency clamp in the codebase correctly read "2.5 ≤ 3, safe". Clamping the
    /// input is necessary and not sufficient once a fold follows it.
    ///
    /// - Parameters:
    ///   - phaseRateHz: the rate the phase is advanced at (already clamped).
    ///   - phaseMultiplier: the multiplier on the shared phase of the style's
    ///     FASTEST term — for a product of two phase-bearing factors that is the
    ///     SUM of their multipliers, not either one alone.
    ///   - folds: true when a non-monotone map (bipolar square, `abs`) is applied.
    /// - Returns: an UPPER BOUND on the field's flash rate in Hz — the fastest
    ///   component, not the highest-energy one. Non-finite input returns
    ///   `.infinity` so a caller asserting `<= maxFlashHz` FAILS CLOSED; this is a
    ///   value to check, not a frequency to use (contrast `safeFrequency`, which
    ///   returns 0 because its result is rendered).
    ///
    /// Use it when adding or retuning a style: the result must be `<= maxFlashHz`.
    ///
    /// KNOWN LIMIT — do not mistake this for a complete model: it describes ONE
    /// oscillator. It cannot express two ADDITIVE oscillators at different phases
    /// (e.g. a field plus a separate heartbeat bloom), where a pixel sees the UNION
    /// of both flash counts. Check those by hand.
    public static func effectiveFieldHz(phaseRateHz: Double,
                                       phaseMultiplier: Double,
                                       folds: Bool) -> Double {
        guard phaseRateHz.isFinite, phaseMultiplier.isFinite else { return .infinity }
        let base = Swift.abs(phaseRateHz) * Swift.abs(phaseMultiplier)
        return folds ? base * 2 : base
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
