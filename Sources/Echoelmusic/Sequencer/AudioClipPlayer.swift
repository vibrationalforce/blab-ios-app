// AudioClipPlayer.swift
// Echoelmusic — Sequencer
//
// Plays an audio file as a CLIP: loads it, trims to an AudioClipRegion (the tested
// frame math), and schedules the trimmed segment on its own AVAudioPlayerNode —
// one-shot or looping. The node is attached additively into the master mix (like
// any voice), so a clip never touches the master OUTPUT path. Control-plane only:
// AVAudioPlayerNode does its own rendering; we add no work to the audio render path.

#if canImport(AVFoundation)
import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
public final class AudioClipPlayer {

    /// Whether a clip is currently scheduled/playing.
    public private(set) var isPlaying = false
    /// The loaded file's URL (nil = nothing loaded).
    public private(set) var loadedURL: URL?
    /// The loaded file's natural length in seconds (0 = nothing loaded).
    public private(set) var durationSeconds: Double = 0

    @ObservationIgnored public let node = AVAudioPlayerNode()
    /// Warp #54: pitch-preserving stretch node (Apple spectral phase-vocoder). Always
    /// in the chain `node → timePitch → masterMixer`; `rate` is set per play (1.0 =
    /// no tempo change), so no graph re-wire ever happens mid-audition. NOTE: the
    /// spectral node is NOT bit-transparent even at rate 1.0 — it carries the phase-
    /// vocoder's inherent overlap-add latency and can add faint coloration; acceptable
    /// on this preview AUDITION path (not the master/timeline). Device-verify that a
    /// warp-OFF preview still sounds clean; if it colours audibly, route warp-off clips
    /// through the plain single-node `attachPlayerNode(_:format:)` instead.
    @ObservationIgnored public let timePitch = AVAudioUnitTimePitch()
    @ObservationIgnored private weak var engine: AudioEngine?
    @ObservationIgnored private var file: AVAudioFile?
    @ObservationIgnored private var attached = false

    public init() {}

    /// Attach the player node (through the warp node) into the master mix. Call once,
    /// before/after engine start (the attach pauses/restarts safely). Idempotent.
    public func attach(to engine: AudioEngine) {
        self.engine = engine
        guard !attached, let file else {
            // Defer the real attach until a file (hence a format) is known.
            self.engine = engine
            return
        }
        engine.attachPlayerNode(node, through: timePitch, format: file.processingFormat)
        attached = true
    }

    /// Load an audio file (any AVAudioFile-supported type). Returns false on failure.
    @discardableResult
    public func load(url: URL) -> Bool {
        stop()
        guard let f = try? AVAudioFile(forReading: url) else {
            log.log(.error, category: .audio, "AudioClipPlayer: cannot read \(url.lastPathComponent)")
            return false
        }
        file = f
        loadedURL = url
        let sr = f.processingFormat.sampleRate
        durationSeconds = sr > 0 ? Double(f.length) / sr : 0
        // Attach now that we have a concrete format (if an engine is set).
        if let engine, !attached {
            engine.attachPlayerNode(node, through: timePitch, format: f.processingFormat)
            attached = true
        }
        return true
    }

    /// Play the loaded file trimmed to `region` (one-shot, or looping if set).
    /// When `region` is warp-enabled with a native BPM, the clip is time-stretched to
    /// `projectBPM` (pitch preserved) via the always-in-chain `timePitch` node — the
    /// tested `region.effectiveStretchRate(projectBPM:)` picks the rate. `projectBPM`
    /// ≤ 0 (or warp off) plays at native tempo (rate 1.0, transparent).
    public func play(region: AudioClipRegion, projectBPM: Double = 0) {
        guard let f = file, attached else { return }
        // Warp rate is a control-plane parameter set (no render-thread work). Set it
        // BEFORE scheduling so the very first buffer is stretched. rate 1.0 = no tempo
        // change (the node stays in-chain; see the `timePitch` note re: warp-off audition).
        timePitch.rate = Float(region.effectiveStretchRate(projectBPM: projectBPM))
        timePitch.pitch = 0
        let sr = f.processingFormat.sampleRate
        let total = f.length
        let startFrame = region.startFrame(sampleRate: sr, totalFrames: total)
        let frameCount = AVAudioFrameCount(region.frameCount(sampleRate: sr, totalFrames: total))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: frameCount) else { return }
        do {
            f.framePosition = startFrame
            try f.read(into: buffer, frameCount: frameCount)
        } catch {
            log.log(.error, category: .audio, "AudioClipPlayer: read failed: \(error)")
            return
        }
        // Bake the fade envelope into the buffer — one control-plane pass BEFORE
        // scheduling, so no work reaches the render thread. Skipped for a looping
        // region: fades belong to the clip's edges, not every loop iteration.
        // Only the fade EDGES are touched; the unity middle is left untouched
        // (no wasted ×1.0 pass over the whole clip).
        if !region.loop, region.fadeInSeconds > 0 || region.fadeOutSeconds > 0,
           let channels = buffer.floatChannelData {
            let n = Int(buffer.frameLength)
            let chCount = Int(buffer.format.channelCount)
            let dur = region.durationSeconds
            let fin = Swift.min(region.fadeInSeconds, dur)
            let fout = Swift.min(region.fadeOutSeconds, dur - fin)
            let finFrames = Swift.min(n, Int((fin * sr).rounded(.up)))
            let outStart = Swift.max(finFrames, n - Swift.min(n, Int((fout * sr).rounded(.up))))
            for i in 0..<finFrames {
                let g = region.fadeMultiplier(atElapsed: Double(i) / sr)
                for ch in 0..<chCount { channels[ch][i] *= g }
            }
            for i in outStart..<n {
                let g = region.fadeMultiplier(atElapsed: Double(i) / sr)
                for ch in 0..<chCount { channels[ch][i] *= g }
            }
        }
        node.stop()
        let options: AVAudioPlayerNodeBufferOptions = region.loop ? [.loops, .interrupts] : [.interrupts]
        node.scheduleBuffer(buffer, at: nil, options: options, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            if !region.loop {
                Task { @MainActor in self.isPlaying = false }
            }
        }
        node.volume = min(2, max(0, region.gain))
        node.play()
        isPlaying = true
    }

    public func stop() {
        if node.isPlaying || isPlaying { node.stop() }
        isPlaying = false
    }

    /// Detach from the engine (e.g. on teardown).
    public func detach() {
        stop()
        if attached, let engine { engine.detachPlayerNode(node, timePitch: timePitch); attached = false }
    }
}
#endif
