// VideoMuxAlignment.swift
// Pure end-alignment math for `VideoMuxer` (P3 · Video). Extracted so the tricky
// sync logic is unit-tested without CoreMedia (runs on every gate, incl. Linux).
//
// Foundation-free by design: no import, so it compiles on any platform the test
// suite runs on. `VideoMuxer` (which IS AVFoundation-guarded) consumes these
// Double seconds and builds the CMTimeRanges.

/// How to lay a silent video track and an audio track into one composition so they
/// stay in sync.
///
/// The recordings both END at stop time: the video is the whole session, the audio
/// is only the last N seconds of the master mix (RetroCapture's ring). Laying both at
/// t=0 and trimming to the shorter (the old behavior) desynced them by `videoDur -
/// audioDur` — the video played its HEAD while the audio played its TAIL, and any
/// footage past the audio window was effectively dropped. Because both share the same
/// end instant, the fix is to take the LAST `min(video, audio)` seconds of EACH track.
struct VideoMuxAlignment: Equatable {
    /// Offset into the video track where the kept window starts (`videoDur - duration`).
    let videoStartSeconds: Double
    /// Offset into the audio track where the kept window starts (`audioDur - duration`).
    let audioStartSeconds: Double
    /// Length of the kept, end-aligned window = `min(videoDur, audioDur)`.
    let durationSeconds: Double

    /// End-align the two tracks. Returns `nil` when either duration is non-finite or
    /// non-positive (nothing muxable — caller falls back to the video-only file).
    static func endAligned(videoDuration v: Double, audioDuration a: Double) -> VideoMuxAlignment? {
        guard v.isFinite, a.isFinite, v > 0, a > 0 else { return nil }
        let duration = Swift.min(v, a)
        return VideoMuxAlignment(videoStartSeconds: v - duration,
                                 audioStartSeconds: a - duration,
                                 durationSeconds: duration)
    }

    /// LOOP-mode cut (founder 2026-07-24: "Video Mitschnitt ebenfalls im Loop Takt
    /// genau geschnitten?"). Carves an EXACT loop — a whole number of bars,
    /// `loopSeconds` = bars × `StudioCalculator.barSeconds` — out of BOTH tracks so the
    /// exported clip is the same length as the rendered audio loop and loops seamlessly.
    /// Both recordings END at stop time, so the window is the `loopSeconds` immediately
    /// before the last downbeat; `secondsSinceBarStart` (the same value the audio bounce
    /// feeds `StudioCalculator.loopTrimWindow`) phase-aligns the cut to that downbeat, so
    /// the muxed clip starts on beat 1. Returns `nil` when either track is too short to
    /// hold one aligned loop (caller falls back to `endAligned`) or on non-finite /
    /// non-positive input. Same law as `loopTrimWindow`, applied to each track's own end.
    static func loopAligned(videoDuration v: Double, audioDuration a: Double,
                            loopSeconds: Double,
                            secondsSinceBarStart: Double = 0) -> VideoMuxAlignment? {
        guard v.isFinite, a.isFinite, v > 0, a > 0,
              loopSeconds.isFinite, loopSeconds > 0 else { return nil }
        let ago = secondsSinceBarStart.isFinite ? Swift.max(0, secondsSinceBarStart) : 0
        let vStart = v - ago - loopSeconds
        let aStart = a - ago - loopSeconds
        guard vStart >= 0, aStart >= 0 else { return nil }
        return VideoMuxAlignment(videoStartSeconds: vStart,
                                 audioStartSeconds: aStart,
                                 durationSeconds: loopSeconds)
    }
}
