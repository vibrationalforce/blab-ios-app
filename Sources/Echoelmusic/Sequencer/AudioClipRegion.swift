// AudioClipRegion.swift
// Echoelmusic — Sequencer
//
// Pure value model for an audio clip's playback region: trim in/out, loop, and
// gain, with second↔frame conversion and the loop/playhead math an audio-clip
// player needs. Foundation-only and fully unit-testable (no AVFoundation, no
// engine) — the forthcoming AudioClipPlayer (AVAudioPlayerNode scheduleSegment +
// loop) consumes this so its timing logic is verified without audio hardware.

import Foundation

/// A trimmed, optionally-looping region of an audio file, with output gain.
public struct AudioClipRegion: Codable, Sendable, Equatable {

    /// Trim-in point (seconds from the file start), clamped ≥ 0.
    public var startSeconds: Double
    /// Trim-out point (seconds), always > `startSeconds`.
    public var endSeconds: Double
    /// Loop the region while the clip is active.
    public var loop: Bool
    /// Linear output gain (0…2), clamped.
    public var gain: Float

    public init(startSeconds: Double = 0, endSeconds: Double = 1,
                loop: Bool = false, gain: Float = 1.0) {
        let s = Swift.max(0, startSeconds.isFinite ? startSeconds : 0)
        self.startSeconds = s
        let e = endSeconds.isFinite ? endSeconds : s + 0.001
        self.endSeconds = Swift.max(s + 0.0001, e)
        self.loop = loop
        self.gain = Swift.min(2, Swift.max(0, gain.isFinite ? gain : 1))
    }

    /// Region length in seconds (always > 0).
    public var durationSeconds: Double { endSeconds - startSeconds }

    // MARK: Frame conversion (for AVAudioFile / scheduleSegment)

    /// First frame of the region at `sampleRate`, clamped to `[0, totalFrames)`.
    public func startFrame(sampleRate: Double, totalFrames: Int64) -> Int64 {
        guard sampleRate > 0, totalFrames > 0 else { return 0 }
        let f = Int64((startSeconds * sampleRate).rounded())
        return Swift.min(Swift.max(0, f), Swift.max(0, totalFrames - 1))
    }

    /// Number of frames in the region at `sampleRate`, clamped so
    /// `startFrame + frameCount <= totalFrames` (≥ 1).
    public func frameCount(sampleRate: Double, totalFrames: Int64) -> Int64 {
        guard sampleRate > 0, totalFrames > 0 else { return 0 }
        let start = startFrame(sampleRate: sampleRate, totalFrames: totalFrames)
        let want = Int64((durationSeconds * sampleRate).rounded())
        let avail = totalFrames - start
        return Swift.min(Swift.max(1, want), Swift.max(1, avail))
    }

    // MARK: Playhead math

    /// Map elapsed clip time to an absolute position in the FILE (seconds), or
    /// `nil` once a non-looping region has finished. For a looping region the
    /// position wraps within `[startSeconds, endSeconds)`.
    public func filePosition(atElapsed elapsed: Double) -> Double? {
        guard elapsed.isFinite, elapsed >= 0 else { return startSeconds }
        let dur = durationSeconds
        if loop {
            let phase = elapsed.truncatingRemainder(dividingBy: dur)
            return startSeconds + phase
        }
        if elapsed >= dur { return nil }    // one-shot finished
        return startSeconds + elapsed
    }

    /// Whether the clip is still sounding at `elapsed` seconds.
    public func isActive(atElapsed elapsed: Double) -> Bool {
        loop || (elapsed < durationSeconds)
    }
}
