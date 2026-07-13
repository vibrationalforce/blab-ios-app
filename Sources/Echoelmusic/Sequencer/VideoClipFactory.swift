// VideoClipFactory.swift
// Echoelmusic — Sequencer
//
// PURE landing helper: turns a finished/imported video file (URL + measured duration)
// into a Clip(kind:.video) + a TimelineRegion sized to the current tempo, so both the
// capture path (VisualRecorder/CameraClipRecorder) and the PHPicker import path drop a
// video onto a lane through ONE tested seam. No AVFoundation, no file I/O here — the
// caller measures duration on device and passes it in.

import Foundation

public enum VideoClipFactory {

    /// A `.video` clip referencing `mediaRef` (store the file's last path component,
    /// matching how VideoLibraryPanel resolves Documents/Videos).
    public static func clip(name: String, mediaRef: String, colorIndex: Int = 0) -> Clip {
        Clip(name: name, colorIndex: colorIndex, kind: .video, mediaRef: mediaRef)
    }

    /// A region placing a video of `durationSeconds` (already trimmed) at `startTick`
    /// on `laneID`, sized to `bpm`. `contentOffsetSeconds` is the trim-in into the
    /// media (default 0 = from the top).
    public static func region(forDurationSeconds durationSeconds: Double,
                              bpm: Double,
                              laneID: UUID,
                              clipID: UUID,
                              startTick: Int,
                              contentOffsetSeconds: Double = 0) -> TimelineRegion {
        let trim = VideoRegionTrim(nativeDurationSeconds: durationSeconds,
                                   trimInSeconds: contentOffsetSeconds)
        return TimelineRegion(laneID: laneID, clipID: clipID,
                              startTick: max(0, startTick),
                              lengthTicks: trim.lengthTicks(atBPM: bpm),
                              contentOffsetSeconds: max(0, contentOffsetSeconds))
    }
}
