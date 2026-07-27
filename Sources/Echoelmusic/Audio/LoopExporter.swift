// LoopExporter.swift
// Echoel — "Loop → .wav", the whole output of the app. Live-capture path (chosen
// over offline-bounce for zero crash risk): play the generated loop once, capture
// the master mix through the already-installed RetroCapture tap, then run it
// through SingleExport for a clean, LUFS-normalised .wav. Reuses fully-wired audio
// infrastructure — no new render code on the audio thread.
//
// DAW-GRID GUARANTEE (audit C6/C7, 2026-07-04): the written WAV is EXACTLY
// `bars` long and cut on a downbeat, so it loops seamlessly in Ableton/Logic/FL.
//   • C6 — the planned export used to write pre-roll + loop + 0.4 s tail (and the
//     LUFS gain was measured across that junk). Now: capture with ZERO pre-roll,
//     record the tail for natural decay, then SingleExport trims the output to the
//     exact bar-aligned loop window and normalises ONLY that window.
//   • C7 — "keep last" used to cut an arbitrary-phase window ending "now" (seam
//     click mid-phrase). Now: the window is snapped back to the last downbeat via
//     PatternEngine.lastBarStartAt.
//   • Both paths add a ~4 ms edge micro-fade against residual seam ticks.

import Foundation

@MainActor
@Observable
public final class LoopExporter {

    public enum Status: Equatable {
        case idle
        case capturing
        case rendering
        case done(URL)
        case failed(String)
    }

    public private(set) var status: Status = .idle

    /// A short tail (seconds) recorded past the loop so reverb/delay decay stays
    /// natural while the loop plays out — the trim then cuts the file back to the
    /// exact loop, so the tail never overhangs the DAW grid.
    private let tailSeconds: Double = 0.4

    /// Micro fade at the loop edges (seam-tick safety; inaudible as a dip).
    private let edgeFadeSeconds: Double = 0.004

    /// The retro ring holds 30 s at 48 kHz — the hard history limit for the
    /// "keep last" path (slightly conservative so rate drift can't bite).
    private let ringSeconds: Double = 29.5

    public init() {}

    /// Seconds since the transport's last downbeat — the phase offset that snaps
    /// a capture window back onto the bar grid. 0 when unknown (never played).
    private func secondsSinceBarStart(_ beatPlayer: BeatPlayer) -> Double {
        let stamp = beatPlayer.pattern.lastBarStartAt
        guard stamp > 0 else { return 0 }
        return max(0, CFAbsoluteTimeGetCurrent() - stamp)
    }

    /// Render the current loop to a `.wav`. Plays the transport for one loop
    /// length (+ decay tail), captures the master, then trims + normalises the
    /// exact bar-aligned loop. Returns the file URL on success.
    @discardableResult
    public func exportWav(engine: AudioEngine, beatPlayer: BeatPlayer, bars: Int, targetLUFS: Float?) async -> URL? {
        guard status != .capturing, status != .rendering else { return nil }

        let bpm = beatPlayer.pattern.tempo
        let calc = StudioCalculator(bpm: bpm)
        let seconds = calc.loopSeconds(bars: max(1, bars))
        guard seconds > 0 else { status = .failed("Invalid loop length"); return nil }

        // 1. Record live-only (NO 30 s pre-roll — C6) and play the loop from the top.
        status = .capturing
        beatPlayer.pattern.stop()
        engine.retroCapture.startRecording(preRoll: 0)
        beatPlayer.pattern.play(cause: .loopExport)

        // 2. Record one loop + the decay tail past its end.
        try? await Task.sleep(for: .seconds(seconds + tailSeconds))

        // Phase offset NOW (closest to the tap-off moment): we are `ago` past the
        // loop's final downbeat, so the exact loop is the `seconds` before it.
        // Sanity-cap at one bar — a stale stamp must never shift the cut wildly.
        let ago = min(secondsSinceBarStart(beatPlayer), calc.barSeconds)

        let cafURL: URL? = await withCheckedContinuation { continuation in
            engine.retroCapture.stopRecording { url in continuation.resume(returning: url) }
        }
        guard let cafURL else {
            status = .failed("Capture failed")
            return nil
        }

        // 3. Trim to the exact bar-aligned loop, normalise ONLY that window, write .wav.
        return await renderTrimmed(engine: engine, sourceURL: cafURL,
                                   loopSeconds: seconds, fromEnd: ago, targetLUFS: targetLUFS)
    }

    /// Retroactive capture — "die Stelle war gut → behalten": keep the last `bars`
    /// of what ALREADY played from the always-on ring buffer (no transport restart),
    /// snapped back to the last downbeat (C7) so the cut loops on the DAW grid.
    /// Returns the file URL on success.
    @discardableResult
    public func exportRecentLoop(engine: AudioEngine, beatPlayer: BeatPlayer, bars: Int, targetLUFS: Float?) async -> URL? {
        guard status != .capturing, status != .rendering else { return nil }

        let bpm = beatPlayer.pattern.tempo
        let calc = StudioCalculator(bpm: bpm)
        let seconds = calc.loopSeconds(bars: max(1, bars))
        guard seconds > 0 else { status = .failed("Invalid loop length"); return nil }
        guard seconds <= ringSeconds else {
            // The ring only holds ~30 s of history — an honest limit beats a
            // silently truncated, unloopable file.
            status = .failed("Loop exceeds the 30 s capture buffer — choose fewer bars")
            return nil
        }

        // 1. Window = loop + phase-to-downbeat, all ending "now". If the ring
        //    can't hold the snap margin, degrade to the unsnapped cut (better an
        //    exact-length loop off-phase than no loop at all).
        status = .capturing
        let ago = beatPlayer.pattern.isPlaying
            ? min(secondsSinceBarStart(beatPlayer), calc.barSeconds)
            : 0
        let window = min(seconds + ago, ringSeconds)
        let effectiveAgo = max(0, window - seconds)
        guard let cafURL = engine.retroCapture.captureRecent(seconds: window) else {
            status = .failed("Nothing to capture yet")
            return nil
        }

        // 2. Trim to the exact bar-aligned loop + normalise (same path as planned).
        return await renderTrimmed(engine: engine, sourceURL: cafURL,
                                   loopSeconds: seconds, fromEnd: effectiveAgo, targetLUFS: targetLUFS)
    }

    /// Shared tail: configure SingleExport for the bar-aligned loop window
    /// (trim + edge fades + LUFS on the window only) and run it.
    private func renderTrimmed(engine: AudioEngine, sourceURL: URL,
                               loopSeconds: Double, fromEnd: Double, targetLUFS: Float?) async -> URL? {
        status = .rendering
        engine.singleExport.reset()
        engine.singleExport.outputFormat = .wav
        engine.singleExport.targetLUFS = targetLUFS
        engine.singleExport.trimLengthSeconds = loopSeconds
        engine.singleExport.trimFromEndSeconds = fromEnd
        engine.singleExport.edgeFadeSeconds = edgeFadeSeconds
        await engine.singleExport.export(sourceURL: sourceURL)

        if let url = engine.singleExport.exportState.exportedURL {
            status = .done(url)
            return url
        } else {
            status = .failed("Export failed")
            return nil
        }
    }

    public func reset() { status = .idle }
}
