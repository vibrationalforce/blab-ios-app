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
// Stretch (Slice B): a region placed warped renders through a per-format warp
// chain (player → AVAudioUnitTimePitch → master) — Clean holds pitch, Tape lets
// it ride the tempo — while UNWARPED regions keep the plain, uncolored node
// (the spectral unit is not bit-transparent even at rate 1.0). Warp chains
// attach at prime time via `preload(url:warped:)`.
// Honest limits (documented, later cycles): per-clip fades from the audio
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
    /// Slice B: one warp chain (player → AVAudioUnitTimePitch → master) per format
    /// that this lane plays WARPED. Kept SEPARATE from the plain nodes on purpose:
    /// the spectral node is not bit-transparent even at rate 1.0 (overlap-add
    /// latency, faint coloration — see AudioClipPlayer), so unwarped timeline
    /// audio must keep its plain, uncolored path. Attached at PRIME time via
    /// `preload(url:warped:)`; a warped region whose format was never primed
    /// still attaches mid-song — same bounded cost as the plain unseen-format
    /// path, absorbed by the next prime.
    private var warpChains: [FormatKey: (player: AVAudioPlayerNode,
                                         timePitch: AVAudioUnitTimePitch)] = [:]
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

    // MARK: Beats-Executor (prime-time offline WSOLA per region)

    private struct BeatsKey: Hashable {
        let url: URL
        /// Rate + window start quantized to 1/1000 so prime and play resolve the
        /// same entry (audio-review V3b: fromSeconds IS part of the key, so two
        /// same-file/same-rate regions with different trims each keep their own
        /// window instead of ping-ponging one entry every loop wrap).
        let rateMilli: Int
        let fromMilli: Int
        init(url: URL, rate: Double, fromSeconds: Double) {
            self.url = url
            self.rateMilli = Int((rate * 1000).rounded())
            self.fromMilli = Int((fromSeconds * 1000).rounded())
        }
    }
    /// Rendered windows: the OUTPUT buffer (already stretched, plays at rate 1 on
    /// the plain node) plus the prepared media length (audio-review V6: play()
    /// requires the length to match too — a region trimmed after prime falls back
    /// to Clean instead of overplaying the cached tail).
    private var beatsBuffers: [BeatsKey: (lengthSeconds: Double, buffer: AVAudioPCMBuffer)] = [:]
    /// The node-connection format per URL, captured in `ensureLoaded` (audio-review
    /// V1/V2: the rebuild must use the SOURCE file's processingFormat — never the
    /// shared single-slot `file`, which may point at another URL by the time the
    /// detached render lands, and never `standardFormatWithSampleRate`, which can
    /// drop a channel layout the node connection carries → scheduleBuffer NSException).
    private var urlFormats: [URL: AVAudioFormat] = [:]
    /// Matches AudioClipPlayer's preview cap (~31 s @48 k output, ~60 MB stereo
    /// transient): a longer Beats region is not pre-rendered and plays Clean.
    private static let beatsMaxOutputFrames = 1_500_000

    init(engine: AudioEngine?) {
        self.engine = engine
    }

    /// Open `url` (if not seen before) and attach a node for ITS format. The
    /// attach pattern pauses the whole engine, so this belongs at PRIME time
    /// (before playback), never lazily at a mid-song onset (review HIGH 2).
    /// PERF-01: the coordinator now preloads EVERY distinct URL a lane will
    /// play, so every needed format has its node before the song runs.
    func preload(url: URL, warped: Bool) {
        if let key = knownURLs[url], nodes[key] != nil,
           !warped || warpChains[key] != nil { return }   // wrap re-prime: no-op
        guard ensureLoaded(url) != nil else { return }
        // Slice B: this URL plays warped somewhere on the lane — attach its warp
        // chain now, while the transport is parked (the attach pause is inaudible).
        if warped, let key = knownURLs[url] {
            _ = ensureWarpChain(for: key)
        }
    }

    /// Beats-Executor: offline-render the media window through the coherent
    /// multichannel WSOLA at prime time (transport parked; the render itself is
    /// detached so prime never blocks on DSP). play() schedules the READY buffer
    /// at rate 1 on the plain node; not-ready / mismatched windows fall back to
    /// the Clean chain — honest, never silent. Idempotent per (url, rate, window).
    /// Renders in flight (audio-review V3: a loop-wrap re-prime before the render
    /// lands must not re-read + re-render the same window).
    private var beatsInFlight: Set<BeatsKey> = []

    func prepareBeats(url: URL, fromSeconds: Double, lengthSeconds: Double, rate: Double) {
        guard rate.isFinite, rate > 0, rate != 1.0, lengthSeconds > 0 else { return }
        let key = BeatsKey(url: url, rate: rate, fromSeconds: fromSeconds)
        // Idempotent per WINDOW: same start AND same length (code-review HIGH 2 —
        // a region lengthened after prime must re-render, or its cached tail
        // would exhaust into silence forever). In-flight windows are not re-spawned.
        if let existing = beatsBuffers[key],
           abs(existing.lengthSeconds - lengthSeconds) < 0.001 { return }
        if beatsInFlight.contains(key) { return }
        // Attach the plain node + capture the CONNECTION format NOW (audio-review
        // V1/V2): the async completion must never derive it from the shared
        // single-slot `file`, which may point at another URL by then.
        guard ensureLoaded(url) != nil else { return }
        beatsInFlight.insert(key)
        Task.detached(priority: .userInitiated) { [weak self] in
            // Audio-review V3: open + read on a FRESH handle OFF the main actor —
            // prime also fires at loop wrap / relocate-while-playing, where a
            // synchronous main-actor decode would delay the transport step.
            var inputs: [[Float]] = []
            if let f = try? AVAudioFile(forReading: url) {
                let sr = f.processingFormat.sampleRate
                let startFrame = AVAudioFramePosition((max(0, fromSeconds) * sr).rounded())
                if sr > 0, startFrame < f.length {
                    let frames = AVAudioFrameCount(min(Double(f.length - startFrame),
                                                       (lengthSeconds * sr).rounded()))
                    if frames > 0, Int(Double(frames) / rate) <= Self.beatsMaxOutputFrames,
                       let raw = AVAudioPCMBuffer(pcmFormat: f.processingFormat,
                                                  frameCapacity: frames) {
                        f.framePosition = startFrame
                        if (try? f.read(into: raw, frameCount: frames)) != nil,
                           let data = raw.floatChannelData {
                            let n = Int(raw.frameLength)
                            inputs = (0..<Int(raw.format.channelCount)).map {
                                Array(UnsafeBufferPointer(start: data[$0], count: n))
                            }
                        }
                    }
                }
            }
            let rendered = inputs.isEmpty
                ? []
                : WSOLAStretcher().stretchMultichannel(inputs, rate: Float(rate))
            await self?.storeBeats(key: key, lengthSeconds: lengthSeconds, channels: rendered)
        }
    }

    /// Rebuild the rendered channels as a PCM buffer in the URL's NODE-CONNECTION
    /// format (captured in `ensureLoaded` — audio-review V1/V2) and cache it.
    /// Main actor — the cache is control-plane state. Empty channels = the read/
    /// cap/render failed off-main: clear the in-flight marker, log, play Clean.
    private func storeBeats(key: BeatsKey, lengthSeconds: Double, channels: [[Float]]) {
        beatsInFlight.remove(key)
        guard knownURLs[key.url] != nil, let fmt = urlFormats[key.url] else { return }
        guard let first = channels.first, !first.isEmpty,
              channels.count == Int(fmt.channelCount),
              let out = AVAudioPCMBuffer(pcmFormat: fmt,
                                         frameCapacity: AVAudioFrameCount(first.count)),
              let dst = out.floatChannelData else {
            // Symmetric logging (code-review LOW 7): every skip explains a Clean play.
            log.log(.info, category: .audio,
                    "Beats pre-render unavailable (read/cap/format) — region plays Clean")
            return
        }
        for (c, channel) in channels.enumerated() {
            channel.withUnsafeBufferPointer { src in
                guard let s = src.baseAddress else { return }
                dst[c].update(from: s, count: channel.count)
            }
        }
        out.frameLength = AVAudioFrameCount(first.count)
        // Audio-review V4: a tempo edit changes the rate — evict this URL's
        // other-rate entries (only one rate can be current), bounding the cache.
        for k in beatsBuffers.keys where k.url == key.url && k.rateMilli != key.rateMilli {
            beatsBuffers[k] = nil
        }
        beatsBuffers[key] = (lengthSeconds: lengthSeconds, buffer: out)
    }

    func play(url: URL, fromSeconds: Double, lengthSeconds: Double, gain: Float,
              stretch: StretchPlan) {
        guard lengthSeconds > 0 else { stop(); return }
        guard let plainNode = ensureLoaded(url), let file else { return }
        // Beats-Executor: a prepared region onset schedules the READY stretched
        // buffer at rate 1 on the plain node (no spectral coloration). Only the
        // exact prepared window qualifies (onset entry, |Δ| < 1 ms) — a mid-region
        // entry (seek / unmute restart) falls through to the Clean chain below
        // (honest; the next onset is transient-locked again).
        if stretch.rate != 1.0, stretch.mode == .beats,
           let entry = beatsBuffers[BeatsKey(url: url, rate: stretch.rate, fromSeconds: fromSeconds)],
           abs(entry.lengthSeconds - lengthSeconds) < 0.001,
           plainNode.engine?.isRunning == true {
            stop()
            plainNode.scheduleBuffer(entry.buffer, at: nil)
            setGain(gain)
            plainNode.play()
            return
        }
        // Slice B: rate ≠ 1.0 renders through the warp chain (rate 1.0 tape ≡
        // clean by design — tapePitchCents(1) = 0 — so the plain path is honest).
        // Unwarped playback stays on the plain node: bit-identical to pre-Slice-B.
        let node: AVAudioPlayerNode
        if stretch.rate != 1.0, let key = knownURLs[url],
           let chain = ensureWarpChain(for: key) {
            chain.timePitch.rate = Float(stretch.rate)
            chain.timePitch.pitch = stretch.preservesPitch
                ? 0
                : Float(StretchPlan.tapePitchCents(forRate: stretch.rate))
            node = chain.player
        } else {
            node = plainNode
        }
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
        for chain in warpChains.values where chain.player.isPlaying { chain.player.stop() }
    }

    /// H4 live mixer: level/solo edits mid-region land on the nodes' mixer volume —
    /// control-plane only (AVAudioMixing downstream), no re-scheduling. Applied to
    /// every node (only one is audible at a time; a later format switch must not
    /// resurrect a stale level).
    func setGain(_ gain: Float) {
        let g = min(2, max(0, gain.isFinite ? gain : 0))   // non-finite ⇒ silent
        self.gain = g
        for node in nodes.values { node.volume = g }
        for chain in warpChains.values { chain.player.volume = g }
    }

    /// H4 live mixer: the lane's stereo position (B2 pan finally reaches audio lanes).
    func setPan(_ pan: Float) {
        let p = max(-1, min(1, pan))
        self.pan = p
        for node in nodes.values { node.pan = p }
        for chain in warpChains.values { chain.player.pan = p }
    }

    /// Release every engine node (lane removed). Detach mutates the graph without
    /// pausing (disconnect+detach only) — permitted for removal.
    func detach() {
        stop()
        if let engine {
            for node in nodes.values { engine.detachPlayerNode(node) }
            for chain in warpChains.values {
                engine.detachPlayerNode(chain.player, timePitch: chain.timePitch)
            }
        }
        nodes.removeAll()
        warpChains.removeAll()
        knownURLs.removeAll()
        beatsBuffers.removeAll()
        beatsInFlight.removeAll()
        urlFormats.removeAll()
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
        // Audio-review V1/V2: remember the exact connection format per URL — the
        // Beats rebuild must use it (never the shared `file` slot at completion time).
        urlFormats[url] = format
        if let existing = nodes[key] { return existing }
        let node = AVAudioPlayerNode()
        engine.attachPlayerNode(node, format: format)
        node.volume = gain
        node.pan = pan
        nodes[key] = node
        return node
    }

    /// Slice B: the ATTACHED warp chain (player → timePitch → master) for `key`,
    /// creating + attaching one on first need. By construction that happens at
    /// prime time (`preload(url:warped:)`); mid-song only for a region warped
    /// live after the last prime — bounded, like the plain unseen-format path.
    /// The player joins at the lane's CURRENT mixer state (a chain attached
    /// after a live edit must not resurrect a stale level — same rule as
    /// `ensureLoaded`). Returns nil when no engine is available.
    private func ensureWarpChain(for key: FormatKey)
        -> (player: AVAudioPlayerNode, timePitch: AVAudioUnitTimePitch)? {
        if let existing = warpChains[key] { return existing }
        guard let engine, let file else { return nil }
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        engine.attachPlayerNode(player, through: timePitch, format: file.processingFormat)
        player.volume = gain
        player.pan = pan
        let chain = (player: player, timePitch: timePitch)
        warpChains[key] = chain
        return chain
    }
}
#endif
