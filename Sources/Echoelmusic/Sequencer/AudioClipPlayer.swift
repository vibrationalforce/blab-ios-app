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
    /// The format the node is CONNECTED with — scheduling a buffer in any other
    /// format raises an NSException inside AVAudioPlayerNode (audio-review
    /// MEDIUM: load of a 44.1 kHz file after a 48 kHz one, or mono after stereo).
    @ObservationIgnored private var attachedFormat: AVAudioFormat?
    /// Cancellation token for the async Beats pre-render: every play()/stop()
    /// bumps it, so a stale render finishing late can never hijack the node.
    @ObservationIgnored private var playGeneration: UInt64 = 0

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
        attachedFormat = file.processingFormat
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
        // Format truth: if the node is already connected in a DIFFERENT format
        // than the new file's, re-wire through the engine first (the attach
        // pauses/restarts safely, same as the initial attach path).
        if attached, let engine, let current = attachedFormat,
           !current.isEqual(f.processingFormat) {
            engine.detachPlayerNode(node, timePitch: timePitch)
            attached = false
        }
        // Attach now that we have a concrete format (if an engine is set).
        if let engine, !attached {
            engine.attachPlayerNode(node, through: timePitch, format: f.processingFormat)
            attachedFormat = f.processingFormat
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
        playGeneration &+= 1
        // Warp rate + character are control-plane parameter sets (no render-thread work).
        // Set them BEFORE scheduling so the very first buffer is stretched. The Echoel
        // stretch engine picks the plan: rate (1.0 = no tempo change) + whether pitch is
        // held (Clean) or rides the tempo (Tape — pitch = 1200·log₂(rate) on the same
        // spectral node, zero graph change). This PREVIEW consumer can additionally
        // pre-render Beats offline (WSOLA); other modes it can't execute render Clean.
        let plan = StretchPlan.resolve(mode: region.stretchMode, warpEnabled: region.warpEnabled,
                                       nativeBPM: region.nativeBPM, projectBPM: projectBPM,
                                       capabilities: StretchMode.previewCapabilities)
        let sr = f.processingFormat.sampleRate
        let total = f.length
        let startFrame = region.startFrame(sampleRate: sr, totalFrames: total)
        let frameCount = AVAudioFrameCount(region.frameCount(sampleRate: sr, totalFrames: total))
        // Beats gates (audio-review): sub-frame regions pass through WSOLA anyway
        // (≤ one analysis frame), and very long renders would stack ~130 MB of
        // transient Float copies against the 200 MB law — both fall back to the
        // spectral path (pitch still held; Clean-equivalent, honest per plan doc).
        // 1.5 M output frames ≈ 31 s @ 48 kHz → ~55-60 MB stereo transient peak.
        let wsolaFrame = WSOLAStretcher().frameSize
        let beatsPreRender = plan.mode == .beats && plan.rate != 1.0
            && Int(frameCount) > wsolaFrame
            && Double(frameCount) / plan.rate < 1_500_000
        // Beats plays an ALREADY-stretched buffer → the spectral node must be neutral.
        timePitch.rate = beatsPreRender ? 1 : Float(plan.rate)
        timePitch.pitch = plan.preservesPitch ? 0 : Float(StretchPlan.tapePitchCents(forRate: plan.rate))
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
        // Beats (#54 Slice 2b): the audition path has no realtime constraint, so
        // WSOLA renders OFFLINE off the main thread (a long clip would otherwise
        // stall the UI for seconds), then the finished buffer schedules at rate 1
        // (tempo already stretched, pitch already held). Fades are baked BEFORE
        // the stretch, so their musical position scales with the clip — honest
        // preview limitation, documented. A stale render (user re-tapped/stopped
        // meanwhile) is dropped by the generation token.
        if beatsPreRender, let channels = buffer.floatChannelData {
            let n = Int(buffer.frameLength)
            let chCount = Int(buffer.format.channelCount)
            let inputs: [[Float]] = (0..<chCount).map {
                Array(UnsafeBufferPointer(start: channels[$0], count: n))
            }
            let rate = Float(plan.rate)
            let generation = playGeneration
            // Silence the node NOW (audio-review LOW): a clip still auditioning
            // would otherwise keep sounding through the render window — and snap
            // to rate 1 audibly, since the neutral write above already landed.
            node.stop()
            isPlaying = true    // pending: the button reads "playing" while it renders
            Task.detached(priority: .userInitiated) { [weak self] in
                let stretcher = WSOLAStretcher()
                let rendered = inputs.map { stretcher.stretch($0, rate: rate) }
                await self?.scheduleStretched(rendered, region: region, generation: generation)
            }
            return
        }
        node.stop()
        let options: AVAudioPlayerNodeBufferOptions = region.loop ? [.loops, .interrupts] : [.interrupts]
        // Generation-guarded (code-review LOW): a stopped/replaced buffer's
        // completion also fires — un-guarded it could land AFTER a newer play
        // and clear isPlaying while audio sounds (Stop button dead). The async
        // Beats render window widens exactly this race.
        let scheduledGeneration = playGeneration
        node.scheduleBuffer(buffer, at: nil, options: options, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            if !region.loop {
                Task { @MainActor in
                    if self.playGeneration == scheduledGeneration { self.isPlaying = false }
                }
            }
        }
        node.volume = min(2, max(0, region.gain))
        node.play()
        isPlaying = true
    }

    /// Schedule a finished offline Beats render. MainActor: rebuilds the PCM
    /// buffer in the file's own processing format (no cross-actor AVAudioFormat)
    /// and drops stale renders via the generation token.
    private func scheduleStretched(_ rendered: [[Float]], region: AudioClipRegion,
                                   generation: UInt64) {
        guard generation == playGeneration, attached, let f = file,
              let first = rendered.first, !first.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: f.processingFormat,
                                            frameCapacity: AVAudioFrameCount(first.count)) else {
            if generation == playGeneration { isPlaying = false }
            return
        }
        buffer.frameLength = AVAudioFrameCount(first.count)
        if let dst = buffer.floatChannelData {
            let chCount = Int(buffer.format.channelCount)
            for ch in 0..<chCount {
                // Mono renders fan out to every channel; extra channels are ignored.
                let src = rendered[Swift.min(ch, rendered.count - 1)]
                src.withUnsafeBufferPointer { sb in
                    guard let base = sb.baseAddress else { return }
                    dst[ch].update(from: base, count: Swift.min(first.count, src.count))
                }
            }
        }
        node.stop()
        let options: AVAudioPlayerNodeBufferOptions = region.loop ? [.loops, .interrupts] : [.interrupts]
        // Same generation guard as the direct path (see play()).
        let scheduledGeneration = playGeneration
        node.scheduleBuffer(buffer, at: nil, options: options, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            if !region.loop {
                Task { @MainActor in
                    if self.playGeneration == scheduledGeneration { self.isPlaying = false }
                }
            }
        }
        node.volume = min(2, max(0, region.gain))
        node.play()
        isPlaying = true
    }

    public func stop() {
        playGeneration &+= 1     // invalidates any in-flight Beats render
        if node.isPlaying || isPlaying { node.stop() }
        isPlaying = false
    }

    /// Detach from the engine (e.g. on teardown).
    public func detach() {
        stop()
        if attached, let engine {
            engine.detachPlayerNode(node, timePitch: timePitch)
            attached = false
            attachedFormat = nil
        }
    }
}
#endif
