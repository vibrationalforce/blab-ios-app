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
// Honest limits (documented, later cycles): gain is applied at region onsets
// only (the coordinator's KNOWN GAP — live mixer moves mid-region are H4);
// per-clip fades/warp from the audio editor are not consumed on the timeline
// yet (audit A5). A sink whose lane is deleted mid-session keeps its (stopped,
// idle) node attached — one node per removed lane, reclaimed on relaunch.

#if canImport(AVFoundation)
import AVFoundation
import Foundation

@MainActor
final class TimelineAudioSink: AudioRegionSink {

    private let node = AVAudioPlayerNode()
    private weak var engine: AudioEngine?
    private var file: AVAudioFile?
    private var attached = false

    init(engine: AudioEngine?) {
        self.engine = engine
    }

    func play(url: URL, fromSeconds: Double, lengthSeconds: Double, gain: Float) {
        guard lengthSeconds > 0, let engine else { stop(); return }
        if file == nil || file?.url != url {
            guard let f = try? AVAudioFile(forReading: url) else {
                log.log(.error, category: .audio,
                        "TimelineAudioSink: cannot read \(url.lastPathComponent)")
                stop()
                return
            }
            file = f
            if !attached {
                engine.attachPlayerNode(node, format: f.processingFormat)
                attached = true
            }
        }
        guard let file, attached else { return }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return }
        let startFrame = AVAudioFramePosition((max(0, fromSeconds) * sampleRate).rounded())
        guard startFrame < file.length else { stop(); return }   // trim-in past the media end
        let remaining = Double(file.length - startFrame)
        let wanted = (lengthSeconds * sampleRate).rounded()
        let frames = AVAudioFrameCount(min(remaining, wanted))
        guard frames > 0 else { stop(); return }
        node.stop()
        node.scheduleSegment(file, startingFrame: startFrame, frameCount: frames, at: nil)
        node.volume = min(2, max(0, gain))
        node.play()
    }

    func stop() {
        if node.isPlaying { node.stop() }
    }
}
#endif
