// TimelineAudioSink.swift
// Echoelmusic — Sequencer
//
// A1 of the healing block (founder 2026-07-15 ultracode; audit wf_9c6f33b7
// verified CRITICAL: "Audio regions on the arrange timeline are SILENT during
// song playback — AudioLanePlayer is dead code, never instantiated"). This is
// the missing DEVICE half of `AudioRegionSink`: player nodes for one audio
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
// PERF-01 (multi-format lanes): AVAudioPlayerNode sample-rate-converts scheduled
// files but does NOT convert channel counts, and re-attaching a node PAUSES the
// whole engine (full-mix dropout). Pre-PERF-01 this sink held ONE node and
// re-attached whenever a region's file format differed from the connection —
// audible at EVERY boundary between (say) a 48 kHz mono mic take and a 44.1 kHz
// stereo loop, re-firing on every loop wrap. Now the sink keeps ONE NODE PER
// DISTINCT processingFormat, attached at PRIME time (transport parked — the
// pause is inaudible); a mid-song region switch just schedules on the format's
// own, already-attached node. A single-format lane behaves exactly as before
// (one node, same paths). Only a file format NEVER seen at prime (a region
// added live mid-song) still attaches mid-song — same cost as the old first
// attach, bounded, and the next prime absorbs it.
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

    /// A distinct connection format (channel layout + rate) → its own node.
    private struct FormatKey: Hashable {
        let channels: AVAudioChannelCount
        let rate: Double
    }

    /// One attached player node per distinct format this lane's media needs.
    private var nodes: [FormatKey: AVAudioPlayerNode] = [:]
    /// URLs whose file was already opened once → their format key, so a loop-wrap
    /// prime (which re-preloads every lane URL) is a pure no-op instead of
    /// re-opening files each round.
    private var knownURLs: [URL: FormatKey] = [:]
    private weak var engine: AudioEngine?
    /// The most recently loaded file (play() schedules from it). Single-slot —
    /// the transport plays one region per lane at a time.
    private var file: AVAudioFile?
    /// Last applied mixer values — a node attached AFTER a live edit (unseen
    /// format mid-song) must join at the lane's current level, not a stale one.
    private var gain: Float = 1
    private var pan: Float = 0

    init(engine: AudioEngine?) {
        self.engine = engine
    }

    /// Open `url` (if not seen before) and attach a node for ITS format. The
    /// attach pattern pauses the whole engine, so this belongs at PRIME time
    /// (before playback), never lazily at a mid-song onset (review HIGH 2).
    /// PERF-01: the coordinator now preloads EVERY distinct URL a lane will
    /// play, so every needed format has its node before the song runs.
    func preload(url: URL) {
        if let key = knownURLs[url], nodes[key] != nil { return }   // wrap re-prime: no-op
        _ = ensureLoaded(url)
    }

    func play(url: URL, fromSeconds: Double, lengthSeconds: Double, gain: Float) {
        guard lengthSeconds > 0 else { stop(); return }
        guard let node = ensureLoaded(url), let file else { return }
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
        stop()   // one region per lane: silence every node before the new segment
        node.scheduleSegment(file, startingFrame: startFrame, frameCount: frames, at: nil)
        setGain(gain)
        node.play()
    }

    func stop() {
        for node in nodes.values where node.isPlaying { node.stop() }
    }

    /// H4 live mixer: level/solo edits mid-region land on the nodes' mixer volume —
    /// control-plane only (AVAudioMixing downstream), no re-scheduling. Applied to
    /// every node (only one is audible at a time; a later format switch must not
    /// resurrect a stale level).
    func setGain(_ gain: Float) {
        let g = min(2, max(0, gain.isFinite ? gain : 0))   // non-finite ⇒ silent
        self.gain = g
        for node in nodes.values { node.volume = g }
    }

    /// H4 live mixer: the lane's stereo position (B2 pan finally reaches audio lanes).
    func setPan(_ pan: Float) {
        let p = max(-1, min(1, pan))
        self.pan = p
        for node in nodes.values { node.pan = p }
    }

    /// Release every engine node (lane removed). Detach mutates the graph without
    /// pausing (disconnect+detach only) — permitted for removal.
    func detach() {
        stop()
        if let engine {
            for node in nodes.values { engine.detachPlayerNode(node) }
        }
        nodes.removeAll()
        knownURLs.removeAll()
        file = nil
    }

    /// Open `url` if it isn't the loaded file, and return the ATTACHED node for
    /// its format — creating + attaching one on the format's first appearance
    /// (attach pauses the engine; by construction that happens at prime time,
    /// or mid-song only for a format never seen at prime — see header).
    /// Returns nil when the file can't be read.
    private func ensureLoaded(_ url: URL) -> AVAudioPlayerNode? {
        guard let engine else { return nil }
        if file == nil || file?.url != url {
            guard let f = try? AVAudioFile(forReading: url) else {
                log.log(.error, category: .audio,
                        "TimelineAudioSink: cannot read \(url.lastPathComponent)")
                stop()
                return nil
            }
            file = f
        }
        guard let file else { return nil }
        let format = file.processingFormat
        let key = FormatKey(channels: format.channelCount, rate: format.sampleRate)
        knownURLs[url] = key
        if let existing = nodes[key] { return existing }
        let node = AVAudioPlayerNode()
        engine.attachPlayerNode(node, format: format)
        node.volume = gain
        node.pan = pan
        nodes[key] = node
        return node
    }
}
#endif
