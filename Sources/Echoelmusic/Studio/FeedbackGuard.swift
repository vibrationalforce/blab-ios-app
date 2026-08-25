//
//  FeedbackGuard.swift
//  Echoelmusic — Studio (live voice safety)
//
//  Pure, testable heuristics for acoustic-feedback (howlround) suppression on the
//  live mic/vocoder path. This file is the BRAIN only — no audio DSP here:
//    • detect runaway level build-up  → recommend a gain duck (dB)
//    • find the ringing frequency bin  → recommend a notch
//
//  ⛔ WHAT THIS HEADER CLAIMED UNTIL 2026-07-31, AND WHAT IS ACTUALLY WIRED.
//  It said: "The audio cycle applies them: Apple's Voice-Processing I/O for system AEC (the
//  FaceTime echo canceller) + a notch biquad + the recommended duck in the FX chain."
//  At the #298 measurement ONE of those three was real; since #595 (2026-08-14) it is TWO.
//  Checked by grep over `Sources/`:
//    • the DUCK is live — `AudioEngine.updateFeedbackGuard()` calls `gainReductionDB` and
//      scales `monitorMixer.outputVolume`. It ducks the MIC MONITOR only, never the music, and
//      touches no audio thread and no tap. It runs on the MainActor from the **60 Hz** meter
//      poll, gated to every 4th tick (`monitorPollTick % 4 == 0`), i.e. ~15 Hz. ⛔ The first
//      version of this line called it "the ~15 Hz meter poll" — the poll is 60 Hz and the GATE
//      makes it 15. Anyone budgeting work onto that poll from this sentence would be off by 4×.
//    • the NOTCH is WIRED since #595 — `AudioEngine` taps the monitor input into
//      `MonitorTapWindow` (lock queue, zero actor hops in the tap), the same ~15 Hz guard
//      tick runs the FFT + `ringingBin` on the MainActor, and an `AVAudioUnitEQ` parametric
//      band sits in the MONITOR path only (input → notchEQ → monitorMixer — the music never
//      passes through it, the duck's exact scoping). It engages ONLY while the duck already
//      fires AND one bin dominates (×8), its gain is slewed via `slewedNotchGainDB` (never
//      stepped), and it holds ~2 s past the last detection so it cannot audibly pump.
//      ⛔ Until #595 this bullet stated the opposite (unwired, `ringingBin` with ZERO callers
//      in `Sources/` — NOT quoted verbatim here: the two-way guard scans this RAW header for
//      the old sentence, and a verbatim quote would re-trigger it, the #491 collision);
//      that was true for a year. The paired two-way guard
//      (`AudioInputDoorTests.testFeedbackGuardHeaderMatchesWhatIsActuallyWired`) forces this
//      sentence and the wiring to move together, in BOTH directions.
//    • the AEC is NOT wired — `setVoiceProcessingEnabled` appears NOWHERE in `Sources/`.
//      Deliberate: it changes the whole I/O character and is Council-gated (see
//      `scratchpads/PLAN_VOICE_STAGE_2026-08-14.md`, "NICHT bauen").
//  This mattered more than a stale comment usually does: it is the file a session reads to
//  decide whether feedback suppression still needs work, and as written it answered "already
//  done, three layers deep". Headphone/IEM monitoring remains the zero-feedback path; on a
//  speaker the defence is now duck (level) + notch (frequency), still no AEC.
//
//  All functions are allocation-free over caller-provided buffers, so the audio
//  thread can call them directly (Accelerate does the FFT upstream).
//

import Foundation

public enum FeedbackGuard {

    /// ONE spelling of the duck's default depth (#416). A caller that widens the
    /// authority — Megaphone Mode uses `defaultMaxReductionDB + megaphoneBoostDB`,
    /// so the guard can always undo more than the boost — derives from this
    /// constant instead of restating the 12.
    public static let defaultMaxReductionDB: Float = 12

    /// Recommended gain reduction in dB (0 = none) when the level is both ABOVE a
    /// ceiling and trending upward across the short RMS history — the signature of
    /// feedback building up. Pure: depends only on the passed history.
    ///
    /// - Parameters:
    ///   - rmsHistory: recent broadband RMS samples, oldest → newest (0…1).
    ///   - ceiling: level above which we start worrying (0…1).
    ///   - maxReductionDB: clamp on how much we duck in one step.
    public static func gainReductionDB(rmsHistory: [Float],
                                       ceiling: Float = 0.85,
                                       maxReductionDB: Float = defaultMaxReductionDB) -> Float {
        guard let last = rmsHistory.last, rmsHistory.count >= 3 else { return 0 }
        let first = rmsHistory.first ?? last
        // Rising trend: newest meaningfully louder than oldest in the window.
        let rising = last > first * 1.10 && last > 0.001
        guard rising, last > ceiling else { return 0 }
        // Duck proportional to how far over the ceiling we are (linear → dB).
        let over = min(1, (last - ceiling) / max(0.0001, 1 - ceiling))
        return min(maxReductionDB, over * maxReductionDB)
    }

    /// The index of a dominant, persistent peak in a magnitude spectrum — the
    /// likely ringing frequency to notch — or nil when nothing clearly dominates.
    ///
    /// - Parameters:
    ///   - magnitudes: linear FFT magnitudes (bin 0 = DC).
    ///   - dominanceRatio: peak must exceed the mean by at least this factor.
    public static func ringingBin(magnitudes: [Float], dominanceRatio: Float = 8) -> Int? {
        guard magnitudes.count > 2 else { return nil }
        var sum: Float = 0
        var peak: Float = 0
        var peakIdx = 0
        // Skip DC (bin 0).
        for i in 1..<magnitudes.count {
            let m = magnitudes[i]
            sum += m
            if m > peak { peak = m; peakIdx = i }
        }
        let count = Float(magnitudes.count - 1)
        guard count > 0 else { return nil }
        let mean = sum / count
        guard mean > 0, peak >= mean * dominanceRatio else { return nil }
        return peakIdx
    }

    /// Convert an FFT bin to its centre frequency in Hz.
    public static func binToHz(_ bin: Int, fftSize: Int, sampleRate: Double) -> Double {
        guard fftSize > 0 else { return 0 }
        return Double(bin) * sampleRate / Double(fftSize)
    }

    /// Rate-based slew for the monitor notch's gain in dB (#595): moves `current`
    /// toward `target` by at most `stepDB` per guard tick (~15 Hz), so engaging and
    /// releasing the notch are RAMPS, never steps — the slew law that governs every
    /// audible parameter jump in this repo. A non-finite `current` (a poisoned state
    /// variable) restarts from 0 rather than propagating; a non-finite `target` is
    /// treated as release (0). Pure, allocation-free.
    public static func slewedNotchGainDB(current: Float, target: Float,
                                         stepDB: Float = 4) -> Float {
        let cur = current.isFinite ? current : 0
        let tgt = target.isFinite ? target : 0
        let step = Swift.max(0.1, stepDB.isFinite ? stepDB : 4)
        if cur < tgt { return Swift.min(tgt, cur + step) }
        if cur > tgt { return Swift.max(tgt, cur - step) }
        return cur
    }
}
