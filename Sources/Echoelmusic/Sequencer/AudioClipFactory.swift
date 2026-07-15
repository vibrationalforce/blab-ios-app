// AudioClipFactory.swift
// Echoelmusic — Sequencer
//
// PURE landing helper: turns an imported audio file (file reference + measured
// duration) into a Clip(kind:.audio) + a TimelineRegion sized to a musical bar
// grid, so the audio-import path drops a clip onto a lane through ONE tested seam.
// Mirrors VideoClipFactory. No AVFoundation, no file I/O here — the caller measures
// the duration on device (AVAsset) and passes it in. All logic is deterministic:
// no Date()/random/UUID() inside the math (callers pass fixed IDs in tests).

import Foundation

public enum AudioClipFactory {

    /// Number of beats per bar assumed by the bar/tempo heuristics (4/4).
    public static let beatsPerBar = TimelineTime.beatsPerBar   // 4

    /// An `.audio` clip referencing `mediaRef`. The import path stores an
    /// ABSOLUTE path (into the App Group `Media/Audio` dir) so the timeline's
    /// resolver — `URL(fileURLWithPath:)` + `fileExists` — finds the file
    /// directly; do NOT switch this to a relative/last-path-component ref
    /// without also changing that resolver.
    public static func clip(name: String, mediaRef: String, colorIndex: Int = 0,
                            nativeDurationSeconds: Double? = nil) -> Clip {
        Clip(name: name, colorIndex: colorIndex, kind: .audio, mediaRef: mediaRef,
             nativeDurationSeconds: nativeDurationSeconds)
    }

    /// Best-guess bar length for an audio clip of `durationSeconds` at `bpm`,
    /// snapped to a power of two (1/2/4/8) via `TempoMatch.guessBars` so a
    /// well-cut loop lands on an integer-bar boundary with no manual entry.
    /// Falls back to `1` bar for non-positive / un-guessable inputs — a clip is
    /// never zero bars long.
    public static func guessBars(forDurationSeconds durationSeconds: Double,
                                 bpm: Double,
                                 candidates: [Int] = [1, 2, 4, 8]) -> Int {
        guard durationSeconds > 0, bpm > 0 else { return 1 }
        let guessed = TempoMatch.guessBars(durationSeconds: durationSeconds,
                                           masterBPM: bpm,
                                           beatsPerBar: beatsPerBar,
                                           candidates: candidates)
        return max(1, guessed ?? 1)
    }

    /// The implied native tempo (BPM) of an audio clip of `durationSeconds`,
    /// derived from its guessed integer-bar length. Falls back to `bpm` (treat
    /// the clip as already at the master tempo) when it can't be guessed —
    /// never returns 0, so callers can divide by it safely.
    public static func nativeBPM(forDurationSeconds durationSeconds: Double,
                                 bpm: Double) -> Double {
        guard durationSeconds > 0, bpm > 0 else { return max(bpm, 0) }
        let bars = guessBars(forDurationSeconds: durationSeconds, bpm: bpm)
        return TempoMatch.nativeBPM(durationSeconds: durationSeconds,
                                    bars: bars,
                                    beatsPerBar: beatsPerBar) ?? bpm
    }

    /// A region placing an audio clip of `durationSeconds` at `startTick` on
    /// `laneID`, sized to a whole number of bars. The bar count is derived from
    /// `durationSeconds` and the clip's own `nativeBPM` (rounded to the nearest
    /// bar, ≥ 1), so `lengthTicks == bars * TimelineTime.ticksPerBar` — the clip
    /// occupies an honest musical span on the grid. `contentOffsetSeconds` trims
    /// into the media (default 0 = from the top). `bpm` is accepted for signature
    /// parity with the caller/VideoClipFactory but does not affect the tick length
    /// (bars are a musical count, not a wall-clock one).
    public static func region(forDurationSeconds durationSeconds: Double,
                              bpm: Double,
                              laneID: UUID,
                              clipID: UUID,
                              startTick: Int,
                              nativeBPM: Double,
                              contentOffsetSeconds: Double = 0) -> TimelineRegion {
        let bars = barCount(forDurationSeconds: durationSeconds, nativeBPM: nativeBPM)
        let lengthTicks = bars * TimelineTime.ticksPerBar
        return TimelineRegion(laneID: laneID,
                              clipID: clipID,
                              startTick: max(0, startTick),
                              lengthTicks: lengthTicks,
                              contentOffsetSeconds: max(0, contentOffsetSeconds))
    }

    /// Whole-bar count for `durationSeconds` at `nativeBPM`, rounded to the
    /// nearest bar and floored at 1. Pure; guards non-positive inputs.
    static func barCount(forDurationSeconds durationSeconds: Double,
                         nativeBPM: Double) -> Int {
        guard durationSeconds > 0, nativeBPM > 0, beatsPerBar > 0 else { return 1 }
        let bars = durationSeconds * nativeBPM / (60.0 * Double(beatsPerBar))
        return max(1, Int(bars.rounded()))
    }
}
