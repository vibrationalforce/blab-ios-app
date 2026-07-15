// TimelineAudioSink.swift
// Echoelmusic — Sequencer
//
// A1 of the healing block (founder 2026-07-15 ultracode; audit wf_9c6f33b7
// verified CRITICAL: "Audio regions on the arrange timeline are SILENT during
// song playback — AudioLanePlayer is dead code, never instantiated"). This is
// the missing DEVICE half of `AudioRegionSink`: one AVAudioPlayerNode per audio
// lane, attached additively into the master mix (never the output path), driven
// by the tested `AudioLanePlayer` coordinator from the timeline transport.
//
// Streaming by design: `scheduleSegment(_:startingFrame:frameCount:at:)` plays
// straight from the file — no whole-region PCM buffer on the main actor (a
// 3-minute region would be ~70 MB against the 200 MB cap; AudioClipPlayer's
// bake-into-buffer path is right for short auditions/fades, wrong here).
// Control-plane only: scheduling happens on @MainActor; AVAudioPlayerNode does
// its own rendering and file I/O off our threads.
//
// Live mixer (H4): `setGain`/`setPan` land mid-region on the node's AVAudioMixing
// volume/pan — control-plane, no re-scheduling (the coordinator decides when a
// mute/unmute needs a real stop/restart instead).
// Honest limits (documented, later cycles): per-clip fades/warp from the audio
// editor are not consumed on the timeline yet (audit A5).

#if canImport(AVFoundation)
import AVFoundation
import Foundation

@MainActor
final class TimelineAudioSink: AudioRegionSink {

    private let node = AVAudioPlayerNode()
    private weak var engine: AudioEngine?
    private var file: AVAudioFile?
    private var attached = false
    /// The processingFormat the node is CONNECTED with. AVAudioPlayerNode
    /// sample-rate-converts scheduled files but does NOT convert channel counts —
    /// scheduling a mono file on a stereo-connected node (or vice versa) raises
    /// the `_outputFormat.channelCount` NSException. H13a made cross-format
    /// traffic normal (one shared audition sink for every region), so a format
    /// change must reconnect (review F2).
    private var connectedFormat: AVAudioFormat?

    init(engine: AudioEngine?) {
        self.engine = engine
    }

    /// Open `url` (if not already the loaded file) and attach the node. The attach
    /// pattern pauses the whole engine, so this belongs at PRIME time (before
    /// playback), never lazily at a mid-song onset (review HIGH 2).
    func preload(url: URL) {
        _ = ensureLoaded(url)
    }

    func play(url: URL, fromSeconds: Double, lengthSeconds: Double, gain: Float) {
        guard lengthSeconds > 0 else { stop(); return }
        guard ensureLoaded(url), let file else { return }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return }
        let startFrame = AVAudioFramePosition((max(0, fromSeconds) * sampleRate).rounded())
        guard startFrame < file.length else { stop(); return }   // trim-in past the media end
        let remaining = Double(file.length - startFrame)
        let wanted = (lengthSeconds * sampleRate).rounded()
        let frames = AVAudioFrameCount(min(remaining, wanted))
        guard frames > 0 else { stop(); return }
        // `play()` on a node whose engine is not running raises an NSException
        // (hard crash) — reachable through an audio-session interruption while the
        // transport keeps stepping (review MEDIUM 1). Degrade to silence instead;
        // the next region onset re-drives the lane once the engine is back.
        guard node.engine?.isRunning == true else { return }
        node.stop()
        node.scheduleSegment(file, startingFrame: startFrame, frameCount: frames, at: nil)
        setGain(gain)
        node.play()
    }

    func stop() {
        if node.isPlaying { node.stop() }
    }

    /// H4 live mixer: level/solo edits mid-region land on the node's mixer volume —
    /// control-plane only (AVAudioMixing downstream), no re-scheduling.
    func setGain(_ gain: Float) {
        node.volume = min(2, max(0, gain.isFinite ? gain : 0))   // non-finite ⇒ silent
    }

    /// H4 live mixer: the lane's stereo position (B2 pan finally reaches audio lanes).
    func setPan(_ pan: Float) {
        node.pan = max(-1, min(1, pan))
    }

    /// Release the engine node (lane removed). Detach mutates the graph without
    /// pausing (disconnect+detach only) — permitted for removal.
    func detach() {
        stop()
        if attached, let engine {
            engine.detachPlayerNode(node)
            attached = false
            connectedFormat = nil
        }
        file = nil
    }

    /// Open `url` if it isn't the loaded file, and attach the node on first load.
    /// A file whose processingFormat differs from the current connection re-attaches
    /// (detach mutates without pausing; attach pauses — by construction this only
    /// happens at prime time or while the transport is stopped, like the first attach).
    /// Returns false when the file can't be read.
    private func ensureLoaded(_ url: URL) -> Bool {
        guard let engine else { return false }
        if file == nil || file?.url != url {
            guard let f = try? AVAudioFile(forReading: url) else {
                log.log(.error, category: .audio,
                        "TimelineAudioSink: cannot read \(url.lastPathComponent)")
                stop()
                return false
            }
            file = f
            if attached, let connectedFormat,
               connectedFormat.channelCount != f.processingFormat.channelCount
                || connectedFormat.sampleRate != f.processingFormat.sampleRate {
                stop()
                engine.detachPlayerNode(node)
                attached = false
                self.connectedFormat = nil
            }
            if !attached {
                engine.attachPlayerNode(node, format: f.processingFormat)
                attached = true
                connectedFormat = f.processingFormat
            }
        }
        return file != nil
    }
}
#endif
