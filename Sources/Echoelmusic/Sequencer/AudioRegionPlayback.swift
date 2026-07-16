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

    /// H13/A2: the audition window for a REGION tap — pro-DAW behavior: hear the
    /// region's OWN windowed content (`contentOffsetSeconds`, the audio-media
    /// authority; the tick offset is MIDI's twin) for the region's length, not
    /// the whole file from 0. `nil` = don't audition: while the transport plays,
    /// the lane sink is already sounding this lane and a second node would
    /// double-sound/phase (audit hazard) — and nil-while-playing also guarantees
    /// the audition sink's one-time lazy attach (which pauses the engine) can
    /// only ever happen while the transport is stopped, where it is inaudible.
    public static func auditionWindow(for region: TimelineRegion, bpm: Double,
                                      transportPlaying: Bool)
        -> (fromSeconds: Double, lengthSeconds: Double)? {
        guard !transportPlaying, bpm > 0, region.lengthTicks > 0 else { return nil }
        return (max(0, region.contentOffsetSeconds),
                TimelineTime.seconds(fromTicks: region.lengthTicks, bpm: bpm))
    }

    /// CLIP-4: the trim window the audio-clip EDIT door seeds from a PLACED
    /// region — the region's own media window in FILE seconds (start =
    /// `contentOffsetSeconds`, the audio-media authority; end = start + the
    /// region's musical length at `bpm`). The door then shows the clip's real
    /// waveform with THIS window selected instead of a blank importer. `nil`
    /// when the mapping is impossible (non-positive bpm / empty region) — the
    /// door falls back to the whole file.
    public static func editWindow(for region: TimelineRegion, bpm: Double)
        -> (startSeconds: Double, endSeconds: Double)? {
        guard bpm > 0, region.lengthTicks > 0 else { return nil }
        let start = max(0, region.contentOffsetSeconds)
        return (start, start + TimelineTime.seconds(fromTicks: region.lengthTicks, bpm: bpm))
    }

    /// CLIP-4 write-back: the EDIT door's trimmed FILE window → the placed
    /// region's media fields (content offset in seconds + musical length in
    /// ticks at `bpm`, min one tick). The region's song position (startTick)
    /// is NOT part of this — trimming the media never moves the clip in the
    /// song. `nil` when the window is empty/inverted or bpm can't map — the
    /// caller leaves the region untouched (never destroy on bad input).
    public static func regionTrim(startSeconds: Double, endSeconds: Double, bpm: Double)
        -> (contentOffsetSeconds: Double, lengthTicks: Int)? {
        guard bpm > 0 else { return nil }
        let start = max(0, startSeconds)
        guard endSeconds > start else { return nil }
        return (start, max(1, TimelineTime.ticks(fromSeconds: endSeconds - start, bpm: bpm)))
    }

    /// Task #54 Warp — the ONE effective-rate truth for a placed region: the
    /// pitch-preserving stretch rate the audio player applies so the media
    /// conforms to the project tempo. Exactly `1.0` unless the placement opts in
    /// (`warpEnabled`) AND the media's native tempo is known (`clipNativeBPM > 0`)
    /// AND the project tempo is valid. Ratio + musical clamp (0.25…4.0) delegate
    /// to `TempoMatch` — agrees with `AudioClipRegion.effectiveStretchRate` by
    /// construction (cross-checked in AudioWarpMathTests).
    public static func effectiveStretchRate(warpEnabled: Bool, clipNativeBPM: Double,
                                            projectBPM: Double) -> Double {
        guard warpEnabled, clipNativeBPM > 0, projectBPM > 0 else { return 1.0 }
        return TempoMatch.stretchRate(nativeBPM: clipNativeBPM, masterBPM: projectBPM)
    }

    /// A degenerate rate (≤ 0, NaN, ∞) must never corrupt the media mapping —
    /// treat it as unwarped. Callers pass `effectiveStretchRate(...)`, which is
    /// already clamped; this guard is defense in depth for direct calls.
    private static func sanitizedRate(_ rate: Double) -> Double {
        (rate.isFinite && rate > 0) ? rate : 1.0
    }

    /// The media-file position (seconds from the FILE's start) that should be
    /// sounding at song-absolute `tick`, for a region whose media starts at
    /// `contentOffsetSeconds`. `nil` when `tick` is outside the region's half-open
    /// span `[startTick, endTick)` — nothing to play. Never negative.
    /// `stretchRate` (#54, default 1 = today's behavior): a warped region consumes
    /// media `rate×` as fast as song time passes, so the elapsed SONG seconds are
    /// scaled into MEDIA seconds before the offset is applied.
    public static func filePositionSeconds(for region: TimelineRegion,
                                           atTick tick: Int, bpm: Double,
                                           stretchRate: Double = 1.0) -> Double? {
        guard tick >= region.startTick, tick < region.endTick else { return nil }
        let elapsed = TimelineTime.seconds(fromTicks: tick - region.startTick, bpm: bpm)
        return max(0, region.contentOffsetSeconds + elapsed * sanitizedRate(stretchRate))
    }

    /// The sample FRAME in the media file to BEGIN playback at `tick` (floored, ≥ 0)
    /// — `AVAudioPlayerNode.scheduleSegment`'s `startingFrame`. `nil` when the tick is
    /// outside the region or the sample rate is non-positive. Rate-aware via
    /// `filePositionSeconds` (#54).
    public static func startFrame(for region: TimelineRegion, atTick tick: Int,
                                  bpm: Double, sampleRate: Double,
                                  stretchRate: Double = 1.0) -> Int? {
        guard sampleRate > 0,
              let pos = filePositionSeconds(for: region, atTick: tick, bpm: bpm,
                                            stretchRate: stretchRate) else { return nil }
        return max(0, Int((pos * sampleRate).rounded(.down)))
    }

    /// The number of SOURCE sample FRAMES from `tick` to the region's end (≥ 0) —
    /// `scheduleSegment`'s `frameCount`, so playback stops exactly at the region
    /// boundary. `0` when the tick is at/after the region end or the rate is
    /// non-positive. If `tick` precedes the region start it measures the whole region
    /// (defensive; the player only calls this once the region is active).
    /// `stretchRate` (#54, default 1): the remaining SONG seconds consume
    /// `songSeconds × rate` media seconds — the identity `source = output × rate`
    /// cross-checked against `WarpedClipPlan` in tests.
    public static func frameCount(for region: TimelineRegion, fromTick tick: Int,
                                  bpm: Double, sampleRate: Double,
                                  stretchRate: Double = 1.0) -> Int {
        guard sampleRate > 0, tick < region.endTick else { return 0 }
        let start = max(tick, region.startTick)
        let seconds = TimelineTime.seconds(fromTicks: region.endTick - start, bpm: bpm)
        return max(0, Int((seconds * sanitizedRate(stretchRate) * sampleRate).rounded()))
    }
}
