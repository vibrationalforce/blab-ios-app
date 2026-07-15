// AudioRegionPlayback.swift
// Echoel — the PURE media-time mapping for playing an audio region in the
// transport. TimelineScheduling already decides WHICH region a lane should play
// and WHEN it changes (onset/clear); this fills the audio-only gap: given the
// song-absolute tick, WHERE in the media file to start and HOW MANY sample frames
// to schedule so playback stops exactly at the region boundary.
//
// This is the brain of the (upcoming, device-verified) AudioLanePlayer: its three
// functions map onto AVAudioPlayerNode.scheduleSegment(startingFrame:frameCount:).
// No AVFoundation, no audio thread, no state — pure value math, unit-tested on
// every platform (incl. Linux CI). The thin AVFoundation executor lands separately
// so its real-time behaviour can be device-verified, not built blind.
//
// ⚠️ EXECUTOR CONTRACT — the helper is FILE-LENGTH-AGNOSTIC (it knows the musical
// span, not the media's real duration). A region trimmed/extended past its file's
// end yields a startFrame / frameCount beyond `AVAudioFile.length`. Before calling
// scheduleSegment, the executor MUST clamp against the real length:
//   • skip scheduling when `startFrame >= file.length` (nothing left to play);
//   • clamp `frameCount` to `min(frameCount, file.length - startFrame)`.
// Otherwise scheduleSegment reads past EOF (silence or an assert, not a clean stop).

import Foundation

public enum AudioRegionPlayback {

    /// The media-file position (seconds from the FILE's start) that should be
    /// sounding at song-absolute `tick`, for a region whose media starts at
    /// `contentOffsetSeconds`. `nil` when `tick` is outside the region's half-open
    /// span `[startTick, endTick)` — nothing to play. Never negative.
    public static func filePositionSeconds(for region: TimelineRegion,
                                           atTick tick: Int, bpm: Double) -> Double? {
        guard tick >= region.startTick, tick < region.endTick else { return nil }
        let elapsed = TimelineTime.seconds(fromTicks: tick - region.startTick, bpm: bpm)
        return max(0, region.contentOffsetSeconds + elapsed)
    }

    /// The sample FRAME in the media file to BEGIN playback at `tick` (floored, ≥ 0)
    /// — `AVAudioPlayerNode.scheduleSegment`'s `startingFrame`. `nil` when the tick is
    /// outside the region or the sample rate is non-positive.
    public static func startFrame(for region: TimelineRegion, atTick tick: Int,
                                  bpm: Double, sampleRate: Double) -> Int? {
        guard sampleRate > 0,
              let pos = filePositionSeconds(for: region, atTick: tick, bpm: bpm) else { return nil }
        return max(0, Int((pos * sampleRate).rounded(.down)))
    }

    /// The number of sample FRAMES from `tick` to the region's end (≥ 0) —
    /// `scheduleSegment`'s `frameCount`, so playback stops exactly at the region
    /// boundary. `0` when the tick is at/after the region end or the rate is
    /// non-positive. If `tick` precedes the region start it measures the whole region
    /// (defensive; the player only calls this once the region is active).
    public static func frameCount(for region: TimelineRegion, fromTick tick: Int,
                                  bpm: Double, sampleRate: Double) -> Int {
        guard sampleRate > 0, tick < region.endTick else { return 0 }
        let start = max(tick, region.startTick)
        let seconds = TimelineTime.seconds(fromTicks: region.endTick - start, bpm: bpm)
        return max(0, Int((seconds * sampleRate).rounded()))
    }
}
