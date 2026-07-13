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
    /// Fade-in length in seconds (0 = hard start), clamped ≥ 0. The gain ramps
    /// 0→1 over this many seconds from the region start.
    public var fadeInSeconds: Double
    /// Fade-out length in seconds (0 = hard stop), clamped ≥ 0. The gain ramps
    /// 1→0 over this many seconds up to the region end.
    public var fadeOutSeconds: Double
    /// Warp/tempo-conform gate. When true AND `nativeBPM > 0`, an audio-clip player
    /// time-stretches the region (pitch-preserved, OFFLINE) to the project tempo.
    /// Default false → natural speed, bit-identical to a non-warped clip.
    public var warpEnabled: Bool
    /// The clip's own tempo in BPM. 0 = unknown (never warps, even if `warpEnabled`);
    /// otherwise clamped to `nativeBPMRange`. Detected via `TempoMatch.guessBars`/
    /// `nativeBPM` at import, or set by the user (a "Clip BPM" field).
    public var nativeBPM: Double

    /// Sane native-tempo bounds. Outside this a "BPM" is almost certainly a
    /// mis-detection; 0 is the sentinel for "unknown / no warp basis".
    public static let nativeBPMRange: ClosedRange<Double> = 20...400

    public init(startSeconds: Double = 0, endSeconds: Double = 1,
                loop: Bool = false, gain: Float = 1.0,
                fadeInSeconds: Double = 0, fadeOutSeconds: Double = 0,
                warpEnabled: Bool = false, nativeBPM: Double = 0) {
        let s = Swift.max(0, startSeconds.isFinite ? startSeconds : 0)
        self.startSeconds = s
        let e = endSeconds.isFinite ? endSeconds : s + 0.001
        self.endSeconds = Swift.max(s + 0.0001, e)
        self.loop = loop
        self.gain = Swift.min(2, Swift.max(0, gain.isFinite ? gain : 1))
        self.fadeInSeconds = Swift.max(0, fadeInSeconds.isFinite ? fadeInSeconds : 0)
        self.fadeOutSeconds = Swift.max(0, fadeOutSeconds.isFinite ? fadeOutSeconds : 0)
        self.warpEnabled = warpEnabled
        // 0 stays 0 (unknown); any real value clamps into the musical range.
        if nativeBPM.isFinite, nativeBPM > 0 {
            self.nativeBPM = Swift.min(Self.nativeBPMRange.upperBound,
                                       Swift.max(Self.nativeBPMRange.lowerBound, nativeBPM))
        } else {
            self.nativeBPM = 0
        }
    }

    private enum CodingKeys: String, CodingKey {
        case startSeconds, endSeconds, loop, gain, fadeInSeconds, fadeOutSeconds
        case warpEnabled, nativeBPM
    }

    /// Backward-compatible decode: regions saved before fades/warp load with none,
    /// and every field re-clamps through the same rules as `init` (never a
    /// decode failure, never a NaN/negative slips in).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            startSeconds: (try? c.decode(Double.self, forKey: .startSeconds)) ?? 0,
            endSeconds: (try? c.decode(Double.self, forKey: .endSeconds)) ?? 1,
            loop: (try? c.decode(Bool.self, forKey: .loop)) ?? false,
            gain: (try? c.decode(Float.self, forKey: .gain)) ?? 1,
            fadeInSeconds: (try? c.decode(Double.self, forKey: .fadeInSeconds)) ?? 0,
            fadeOutSeconds: (try? c.decode(Double.self, forKey: .fadeOutSeconds)) ?? 0,
            warpEnabled: (try? c.decode(Bool.self, forKey: .warpEnabled)) ?? false,
            nativeBPM: (try? c.decode(Double.self, forKey: .nativeBPM)) ?? 0)
    }

    /// Region length in seconds (always > 0).
    public var durationSeconds: Double { endSeconds - startSeconds }

    // MARK: Warp / tempo-conform (pure — the player renders this OFFLINE)

    /// The pitch-preserving time-stretch RATE to conform this region to `projectBPM`,
    /// or exactly `1.0` (no stretch) when warp is off, the native tempo is unknown, or
    /// the project tempo is non-positive. Delegates the clamped ratio to
    /// `TempoMatch.stretchRate` (musical range 0.25…4.0).
    public func effectiveStretchRate(projectBPM: Double) -> Double {
        guard warpEnabled, nativeBPM > 0, projectBPM > 0 else { return 1.0 }
        return TempoMatch.stretchRate(nativeBPM: nativeBPM, masterBPM: projectBPM)
    }

    /// The region's audible length after warping to `projectBPM`. A rate > 1 (project
    /// faster than the clip) plays faster → shorter output; rate < 1 stretches longer.
    /// Equals `durationSeconds` whenever the rate is 1.0.
    public func warpedDurationSeconds(projectBPM: Double) -> Double {
        let r = effectiveStretchRate(projectBPM: projectBPM)
        guard r > 0 else { return durationSeconds }
        return durationSeconds / r
    }

    // MARK: Fade envelope (pure — the player bakes this into the scheduled buffer)

    /// The fade gain [0…1] at `elapsed` seconds into the region: ramps 0→1 over
    /// `fadeInSeconds` at the start, 1→0 over `fadeOutSeconds` at the end, 1 in
    /// between. If the two fades would overlap (their sum exceeds the duration),
    /// the fade-in keeps its full length and the fade-out fills the remainder,
    /// so the multiplier always stays within [0,1]. Out-of-range elapsed clamps.
    public func fadeMultiplier(atElapsed elapsed: Double) -> Float {
        let dur = durationSeconds
        guard dur > 0 else { return 1 }
        let t = Swift.min(dur, Swift.max(0, elapsed.isFinite ? elapsed : 0))
        let fin = Swift.min(fadeInSeconds, dur)
        let fout = Swift.min(fadeOutSeconds, dur - fin)   // in wins if they'd overlap
        var g = 1.0
        if fin > 0, t < fin { g = t / fin }               // 0→1
        if fout > 0 {
            let outStart = dur - fout
            if t > outStart { g = Swift.min(g, (dur - t) / fout) }   // 1→0
        }
        return Float(Swift.min(1, Swift.max(0, g)))
    }

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
