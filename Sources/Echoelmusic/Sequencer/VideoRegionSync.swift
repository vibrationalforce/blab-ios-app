// VideoRegionSync.swift
// Echoelmusic — Sequencer
//
// PURE, device-free playhead→source-time mapping for a video region on the arrange
// timeline. The device-side VideoLanePlayer (AVQueuePlayer) consumes this to
// seek/scrub in lockstep with the shared transport, so all timing logic is unit-
// tested without AVFoundation. Video plays REAL-TIME (1 source-second per transport-
// second at the region's tempo) — the same non-warped contract as AudioClipRegion;
// tempo-warped video is out of scope (a later concern).
//
// Time base: song-absolute 480-PPQ ticks (Timeline.swift). Source time is SECONDS
// into the media file, offset by the region's trim-in (contentOffsetSeconds) plus
// the elapsed region time converted at bpm.

import Foundation

/// What the video player should do for a region at a given playhead tick.
public enum VideoRegionPlayback: Equatable, Sendable {
    /// The playhead is outside the region — nothing to show on this lane.
    case inactive
    /// Seek/keep the player at `sourceSeconds` into the media and let it run.
    case play(sourceSeconds: Double)
    /// The region still spans the timeline but the media ran out of frames
    /// (source shorter than the placed span) — hold the last frame here.
    case exhausted(sourceSeconds: Double)
}

public enum VideoRegionSync {

    /// Resolve what a video region should be doing at song-absolute `playheadTick`.
    /// region trim-in = `contentOffsetSeconds`; elapsed region time is converted
    /// ticks→seconds at `bpm` and added, giving the absolute source seconds.
    /// `.inactive` outside `[startTick, endTick)`; `.exhausted` when the source time
    /// reaches/exceeds `nativeDurationSeconds` (media shorter than the placed span).
    public static func resolve(startTick: Int,
                               lengthTicks: Int,
                               contentOffsetSeconds: Double,
                               bpm: Double,
                               nativeDurationSeconds: Double,
                               playheadTick: Int) -> VideoRegionPlayback {
        let len = max(1, lengthTicks)
        let start = max(0, startTick)
        let end = start + len
        guard playheadTick >= start, playheadTick < end else { return .inactive }

        let elapsedTicks = playheadTick - start
        let elapsedSeconds = TimelineTime.seconds(fromTicks: elapsedTicks, bpm: bpm)
        let offset = max(0, contentOffsetSeconds.isFinite ? contentOffsetSeconds : 0)
        let rawSource = offset + max(0, elapsedSeconds)

        let dur = nativeDurationSeconds.isFinite ? nativeDurationSeconds : 0
        guard dur > 0 else {
            // Unknown/zero-length media: treat as a single held frame at the offset.
            return .exhausted(sourceSeconds: offset)
        }
        if rawSource >= dur {
            // Clamp to just inside the last frame's time so a seek lands on a frame.
            return .exhausted(sourceSeconds: min(rawSource, max(0, dur - 0.0001)))
        }
        return .play(sourceSeconds: rawSource)
    }

    /// Convenience: is the region active (showing anything) at `playheadTick`?
    public static func isActive(startTick: Int, lengthTicks: Int,
                                playheadTick: Int) -> Bool {
        let start = max(0, startTick)
        return playheadTick >= start && playheadTick < start + max(1, lengthTicks)
    }

    /// The source seconds a SCRUB to `playheadTick` should seek to, or `nil` when the
    /// region is inactive there. Scrubbing seeks with the player paused, so it uses
    /// the same map as playback (identical frame under the playhead).
    public static func scrubSourceSeconds(startTick: Int, lengthTicks: Int,
                                          contentOffsetSeconds: Double, bpm: Double,
                                          nativeDurationSeconds: Double,
                                          playheadTick: Int) -> Double? {
        switch resolve(startTick: startTick, lengthTicks: lengthTicks,
                       contentOffsetSeconds: contentOffsetSeconds, bpm: bpm,
                       nativeDurationSeconds: nativeDurationSeconds,
                       playheadTick: playheadTick) {
        case .inactive:            return nil
        case .play(let s):         return s
        case .exhausted(let s):    return s
        }
    }
}
