// WarpedClipPlan.swift
// Echoelmusic — Sequencer
//
// Pure value type that computes how a (optionally warped) audio clip lands on the
// timeline's sample grid: where it reads from the source file, how many source
// frames it consumes, how many output frames that produces after time-stretch, and
// the sample offset of its onset on the song timeline. Foundation-only and fully
// unit-testable (no AVFoundation, no engine) — the audio-clip player consumes this so
// its scheduling maths is verified without audio hardware.
//
// Delegates all tempo maths to `AudioClipRegion.effectiveStretchRate(projectBPM:)`
// (which itself clamps via `TempoMatch`) and `TimelineTime.seconds(fromTicks:bpm:)`.

import Foundation

/// The sample-accurate plan for placing one `AudioClipRegion` on the timeline grid.
///
/// A rate of exactly `1.0` (warp off, unknown native tempo, or non-positive project
/// tempo) short-circuits the stretch: `outputFrameCount == sourceFrameCount`, so a
/// non-warped clip is bit-length-identical to its trimmed source.
public struct WarpedClipPlan: Sendable, Equatable {

    /// The pitch-preserving time-stretch rate applied to the region: `> 1` plays the
    /// clip faster (shorter output), `< 1` stretches it longer, `1.0` = no stretch.
    /// Equals `region.effectiveStretchRate(projectBPM:)`.
    public let stretchRate: Double

    /// First frame read from the source file (`region.startSeconds * engineSampleRate`,
    /// rounded, clamped ≥ 0).
    public let sourceStartFrame: Int

    /// Number of source frames consumed by the region's trim
    /// (`region.durationSeconds * engineSampleRate`, rounded, clamped ≥ 0).
    public let sourceFrameCount: Int

    /// Number of output frames produced after warping (`sourceFrameCount / stretchRate`,
    /// rounded, clamped ≥ 0). Equals `sourceFrameCount` when `stretchRate == 1.0`.
    public let outputFrameCount: Int

    /// Sample offset of the region's onset on the song timeline
    /// (`TimelineTime.seconds(fromTicks:startTick,bpm:projectBPM) * engineSampleRate`,
    /// rounded, clamped ≥ 0). Monotonic non-decreasing in `startTick`.
    public let onsetSampleOffset: Int

    /// Compute the plan for `region` placed at `startTick`, rendered at `projectBPM`
    /// through an engine running at `engineSampleRate` Hz.
    ///
    /// - Parameters:
    ///   - region: the trimmed (optionally warped) audio region.
    ///   - startTick: song-absolute 480-PPQ onset tick (clamped ≥ 0).
    ///   - projectBPM: the transport tempo the clip conforms to.
    ///   - engineSampleRate: the audio engine's sample rate in Hz (must be > 0;
    ///     a non-positive rate yields an all-zero plan).
    public init(region: AudioClipRegion,
                startTick: Int,
                projectBPM: Double,
                engineSampleRate: Double) {

        let rate = region.effectiveStretchRate(projectBPM: projectBPM)
        self.stretchRate = rate

        guard engineSampleRate > 0, engineSampleRate.isFinite else {
            self.sourceStartFrame = 0
            self.sourceFrameCount = 0
            self.outputFrameCount = 0
            self.onsetSampleOffset = 0
            return
        }

        let startFrame = Int((region.startSeconds * engineSampleRate).rounded())
        self.sourceStartFrame = Swift.max(0, startFrame)

        let srcCount = Int((region.durationSeconds * engineSampleRate).rounded())
        let srcFrames = Swift.max(0, srcCount)
        self.sourceFrameCount = srcFrames

        if rate == 1.0 || rate <= 0 || !rate.isFinite {
            // No stretch (or a degenerate rate): output length == source length.
            self.outputFrameCount = srcFrames
        } else {
            let out = Int((Double(srcFrames) / rate).rounded())
            self.outputFrameCount = Swift.max(0, out)
        }

        let onsetSeconds = TimelineTime.seconds(fromTicks: Swift.max(0, startTick),
                                                bpm: projectBPM)
        let onsetFrame = Int((onsetSeconds * engineSampleRate).rounded())
        self.onsetSampleOffset = Swift.max(0, onsetFrame)
    }
}
