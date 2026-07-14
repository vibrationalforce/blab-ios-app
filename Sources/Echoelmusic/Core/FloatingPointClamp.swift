//
//  FloatingPointClamp.swift
//  Echoelmusic — Core
//
//  NaN-safe clamp for floating-point values. Foundation-only (no AVFoundation),
//  so it compiles — and is unit-tested — on Linux CI, not just the iOS build.
//
//  WHY a dedicated FloatingPoint overload: the generic `Comparable.clamped(to:)`
//  (NumericExtensions.swift) is `min(max(self, lo), hi)`. Every comparison with
//  NaN is false, so `max(NaN, lo) == NaN` and `min(NaN, hi) == NaN` — a NaN passes
//  straight through the clamp. When that NaN reaches an audio parameter (synth
//  frequency, gain, a spectral-envelope coefficient) it produces NaN samples that
//  then poison filter/oscillator state, silencing the voice permanently. This
//  overload maps NaN to the range's lower bound (always finite and in-range), so
//  a bad bio value fails quiet instead of stuck-silent.
//
//  Overload resolution: for a concrete Float/Double, this FloatingPoint member is
//  more specialized than the Comparable one and is chosen automatically — every
//  existing `someFloat.clamped(to:)` call gains NaN-safety with no caller change.
//

import Foundation

extension FloatingPoint {
    /// Clamps to `range`, treating NaN as `range.lowerBound` (finite, in-range) so
    /// a NaN can never propagate downstream — critical on the bio → audio path.
    /// - Parameter range: The closed range to clamp into.
    /// - Returns: The clamped value; `range.lowerBound` when `self` is NaN.
    func clamped(to range: ClosedRange<Self>) -> Self {
        guard !isNaN else { return range.lowerBound }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
