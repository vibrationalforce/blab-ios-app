// LoopExporter.swift
// Echoel — "Loop → .wav", the whole output of the app. Live-capture path (chosen
// over offline-bounce for zero crash risk): play the generated loop once, capture
// the master mix through the already-installed RetroCapture tap, then run it
// through SingleExport for a clean, LUFS-normalised .wav. Reuses fully-wired audio
// infrastructure — no new render code on the audio thread.

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

    /// A short tail (seconds) recorded past the loop so reverb/delay tails aren't
    /// chopped at the boundary.
    private let tailSeconds: Double = 0.4

    public init() {}

    /// Render the current loop to a `.wav`. Plays the transport for one loop
    /// length, captures the master, and exports. Returns the file URL on success.
    @discardableResult
    public func exportWav(engine: AudioEngine, beatPlayer: BeatPlayer, bars: Int) async -> URL? {
        guard status != .capturing, status != .rendering else { return nil }

        let bpm = beatPlayer.pattern.tempo
        let seconds = StudioCalculator(bpm: bpm).loopSeconds(bars: max(1, bars))
        guard seconds > 0 else { status = .failed("Invalid loop length"); return nil }

        // 1. Play the loop from the top so the capture starts on a bar.
        status = .capturing
        beatPlayer.pattern.stop()
        beatPlayer.pattern.play()
        engine.retroCapture.startRecording()

        // 2. Record exactly one loop (+ a tail for reverb/delay).
        try? await Task.sleep(for: .seconds(seconds + tailSeconds))

        let cafURL: URL? = await withCheckedContinuation { continuation in
            engine.retroCapture.stopRecording { url in continuation.resume(returning: url) }
        }
        guard let cafURL else {
            status = .failed("Capture failed")
            return nil
        }

        // 3. Normalise + write a lossless .wav.
        status = .rendering
        engine.singleExport.reset()
        engine.singleExport.outputFormat = .wav
        engine.singleExport.targetLUFS = -14
        await engine.singleExport.export(sourceURL: cafURL)

        if let url = engine.singleExport.exportState.exportedURL {
            status = .done(url)
            return url
        } else {
            status = .failed("Export failed")
            return nil
        }
    }

    /// Retroactive capture — "die Stelle war gut → behalten": keep the last `bars`
    /// of what ALREADY played from the always-on ring buffer (no transport restart),
    /// then normalise + write a .wav. The cut is exactly `bars` long, so it loops at
    /// tempo. Returns the file URL on success.
    @discardableResult
    public func exportRecentLoop(engine: AudioEngine, beatPlayer: BeatPlayer, bars: Int) async -> URL? {
        guard status != .capturing, status != .rendering else { return nil }

        let bpm = beatPlayer.pattern.tempo
        let seconds = StudioCalculator(bpm: bpm).loopSeconds(bars: max(1, bars))
        guard seconds > 0 else { status = .failed("Invalid loop length"); return nil }

        // 1. Snapshot exactly the last `seconds` of master output (already played).
        status = .capturing
        guard let cafURL = engine.retroCapture.captureRecent(seconds: seconds) else {
            status = .failed("Nothing to capture yet")
            return nil
        }

        // 2. Normalise + write a lossless .wav (same path as the planned export).
        status = .rendering
        engine.singleExport.reset()
        engine.singleExport.outputFormat = .wav
        engine.singleExport.targetLUFS = -14
        await engine.singleExport.export(sourceURL: cafURL)

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
