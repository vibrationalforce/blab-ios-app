// WaveformReducer.swift
// Echoel — pure waveform reduction (Stage 2 core). Research-validated pro
// rendering: per pixel-column keep MIN and MAX (visual extremes survive) plus
// RMS (the inner "body" layer). Never draw raw PCM. Pure Foundation —
// Linux-CI-testable.
//
// ⛔ TEST-ONLY SINCE 2026-07-28 (#132 Slice 5). This header used to end "the
// AVAudioFile reader + disk cache build on this" — both were deleted that day
// (`Audio/WaveformCache.swift`, `Studio/WaveformView.swift`), so `WaveformReducer`
// and `WaveformBucket` now have ZERO consumers in `Sources/`; the only reference
// left in the repo is `Tests/EchoelmusicTests/WaveformReducerTests.swift`.
//
// KEPT ON PURPOSE, not overlooked: it is a pure, tested, dependency-free core, and
// the sampler/file waveform browser that would consume it again is still on the map
// (`docs/dev/VISION_REALITY_2026-07.md`). Deleting it is a separate decision from
// deleting the DAW view stack, and this note exists so the next pass finds a parked
// core rather than an orphan with no explanation — which is exactly what made the
// deleted `FileWaveformView` a defect instead of a parked feature.

import Foundation

/// One display bucket: the extremes + energy of `bucketSize` samples.
public struct WaveformBucket: Codable, Sendable, Equatable {
    public var min: Float
    public var max: Float
    public var rms: Float
    public init(min: Float, max: Float, rms: Float) {
        self.min = min; self.max = max; self.rms = rms
    }
}

public enum WaveformReducer {

    /// Reduce mono samples into min/max/RMS buckets of `bucketSize` samples
    /// (last bucket may cover fewer). Empty input → empty output; bucketSize
    /// is clamped ≥ 1. No allocation beyond the result; O(n).
    public static func reduce(_ samples: [Float], bucketSize: Int) -> [WaveformBucket] {
        guard !samples.isEmpty else { return [] }
        let size = Swift.max(1, bucketSize)
        var out: [WaveformBucket] = []
        out.reserveCapacity((samples.count + size - 1) / size)
        var i = 0
        while i < samples.count {
            let end = Swift.min(i + size, samples.count)
            var lo = samples[i], hi = samples[i]
            var sumSq: Double = 0
            for j in i..<end {
                let s = samples[j]
                if s < lo { lo = s }
                if s > hi { hi = s }
                sumSq += Double(s) * Double(s)
            }
            let rms = Float((sumSq / Double(end - i)).squareRoot())
            out.append(WaveformBucket(min: lo, max: hi, rms: rms))
            i = end
        }
        return out
    }

    /// Fold stereo to the display channel: per sample keep the value with the
    /// larger magnitude (extremes of EITHER channel stay visible).
    public static func foldStereo(left: [Float], right: [Float]) -> [Float] {
        let n = Swift.min(left.count, right.count)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            out[i] = abs(left[i]) >= abs(right[i]) ? left[i] : right[i]
        }
        return out
    }

    /// Re-reduce an existing bucket tier to a coarser one (mip chain: fine tier
    /// is computed from samples once; coarse tiers derive cheaply from it).
    public static func downsample(_ buckets: [WaveformBucket], factor: Int) -> [WaveformBucket] {
        guard !buckets.isEmpty else { return [] }
        let f = Swift.max(1, factor)
        var out: [WaveformBucket] = []
        out.reserveCapacity((buckets.count + f - 1) / f)
        var i = 0
        while i < buckets.count {
            let end = Swift.min(i + f, buckets.count)
            var lo = buckets[i].min, hi = buckets[i].max
            var sumSq: Double = 0
            for j in i..<end {
                lo = Swift.min(lo, buckets[j].min)
                hi = Swift.max(hi, buckets[j].max)
                sumSq += Double(buckets[j].rms) * Double(buckets[j].rms)
            }
            let rms = Float((sumSq / Double(end - i)).squareRoot())
            out.append(WaveformBucket(min: lo, max: hi, rms: rms))
            i = end
        }
        return out
    }
}
