#if canImport(AVFoundation)
import AVFoundation
import Accelerate
import Observation
import os.log

/// Always-on audio capture with retroactive pre-roll ring buffer.
///
/// Lifecycle:
///   1. `install(on:)` — installs tap on mainMixerNode, ring buffer fills continuously.
///   2. `startRecording()` — prepends last 30s pre-roll, then begins writing live audio.
///   3. `stopRecording(completion:)` — closes file, calls completion with URL.
@MainActor @Observable
final class RetroCapture {

    // MARK: - Observable state

    private(set) var isRecording = false
    private(set) var recordingSeconds = 0
    private(set) var lastURL: URL?

    /// Set when the tap could not write a buffer to disk — a full volume, a revoked
    /// container, a closed file. Cleared once a recording actually STARTS (not when one
    /// is merely attempted: the file/format/pre-roll steps ahead of it can throw, and
    /// those failures are reported by `startRecording` itself, not through this latch).
    ///
    /// WHY THIS EXISTS AT ALL. The write error used to be caught and logged and NOTHING
    /// else: `isRecording` stayed true, the REC pill kept counting, and the take was
    /// quietly short or empty. That is the lying-control class — the same failure as a
    /// record button armed over a renderer that is not capturing. A performer must find
    /// out during the take, not when opening the file afterwards.
    private(set) var writeFailed = false

    /// Downsampled waveform for UI display — 200 RMS values spanning last 30s.
    /// Updated every 500ms via waveformTimer.
    private(set) var waveformSamples: [Float] = Array(repeating: 0, count: 200)

    // MARK: - Ring buffer (always-on pre-roll: 30s stereo @ 48kHz ≈ 11MB)

    private let preRollSeconds: Int = 30
    private let waveformResolution: Int = 200       // display points
    private let ringCapacity: Int

    /// The ACTUAL sample rate the tap captures at (= mixer/hardware rate, which iOS may
    /// grant as 44.1 kHz even though we request 48 kHz — e.g. once the rPPG camera route
    /// is active). Set in `install(on:)` from the tap's real format. ALL seconds↔frames
    /// math and every output-file format use this, NOT a hardcoded 48000 — otherwise the
    /// captured audio plays back pitch-shifted ("viel höher") and mistimed ("unruhig").
    /// MainActor-only (the audio-thread tap callback indexes the ring by frame and never
    /// reads this). Ring is sized for the 48 kHz max so a lower rate just yields >30 s.
    private var captureSampleRate: Double = 48000
    nonisolated(unsafe) private let ring: UnsafeMutablePointer<Float>
    nonisolated(unsafe) private let ringWriteFrame: UnsafeMutablePointer<Int64>

    // MARK: - Recording

    nonisolated(unsafe) private let activeFile: UnsafeMutablePointer<AVAudioFile?>
    nonisolated(unsafe) private let isActive: UnsafeMutablePointer<Bool>

    /// Raised by the tap on the FIRST failed write, read by the 2 Hz waveform timer.
    ///
    /// A plain `Bool` cell, matching `isActive` next to it, because the traffic here is
    /// one writer (the tap) and one reader (the main actor) exchanging a latch that only
    /// ever goes false→true within a take. A torn read is not expressible for a Bool and
    /// a late read costs at most half a second.
    ///
    /// The tap sets it and then STOPS attempting writes. That is the point: without it,
    /// a disk that filled mid-take produced one failed write, one `String(describing:)`,
    /// one `localizedDescription` (a bundle lookup) and one log allocation PER BUFFER —
    /// ~12 times a second for the rest of the take, on the tap thread, while the take was
    /// already lost. Error handling that gets more expensive the longer the error lasts
    /// is a load source, not a diagnostic.
    nonisolated(unsafe) private let writeFailure: UnsafeMutablePointer<Bool>

    private var timer: Timer?
    private var waveformTimer: Timer?

    /// The node we installed the tap on. Held weakly so deinit can remove the tap
    /// before deallocating the pointers the tap callback dereferences (use-after-free
    /// guard). nonisolated(unsafe) so the nonisolated deinit may read it.
    nonisolated(unsafe) private weak var tappedNode: AVAudioNode?

    // MARK: - Init / deinit

    init() {
        let sr = 48000
        ringCapacity = sr * preRollSeconds      // frames per channel
        let totalFloats = ringCapacity * 2      // interleaved stereo

        ring = .allocate(capacity: totalFloats)
        ring.initialize(repeating: 0, count: totalFloats)

        ringWriteFrame = .allocate(capacity: 1)
        ringWriteFrame.initialize(to: 0)

        activeFile = .allocate(capacity: 1)
        activeFile.initialize(to: nil)

        isActive = .allocate(capacity: 1)
        isActive.initialize(to: false)

        writeFailure = .allocate(capacity: 1)
        writeFailure.initialize(to: false)
    }

    deinit {
        // Stop the tap callback BEFORE freeing the buffers/flags it dereferences.
        // removeTap(onBus:) is synchronous — no callback fires after it returns — so
        // ordering it ahead of the deallocations closes the use-after-free window.
        isActive.pointee = false
        tappedNode?.removeTap(onBus: 0)
        ring.deallocate()
        ringWriteFrame.deallocate()
        activeFile.deallocate()
        isActive.deallocate()
        writeFailure.deallocate()
    }

    // MARK: - Tap installation

    /// Call once after AVAudioEngine has started. Removes any existing tap first.
    func install(on engine: AVAudioEngine) {
        let node = engine.mainMixerNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            log.log(.error, category: .audio, "RetroCapture: invalid format — tap not installed")
            return
        }

        node.removeTap(onBus: 0)    // idempotent — removes previous tap if any
        tappedNode = node           // weak ref so deinit can remove the tap
        captureSampleRate = format.sampleRate   // real capture rate for all frame math + file format

        // Capture raw pointers only — never capture self on audio-thread callback
        let ringPtr   = ring
        let writePtr  = ringWriteFrame
        let filePtr   = activeFile
        let activePtr = isActive
        let failPtr   = writeFailure
        let cap       = ringCapacity

        node.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let chCount    = Int(buffer.format.channelCount)
            var frame      = Int(writePtr.pointee)

            // --- always fill ring buffer (pre-roll) ---
            for f in 0..<frameCount {
                let slot = (frame % cap) * 2
                ringPtr[slot]     = channelData[0][f]
                ringPtr[slot + 1] = chCount > 1 ? channelData[1][f] : channelData[0][f]
                frame &+= 1
            }
            writePtr.pointee = Int64(frame)

            // --- if recording: write to disk file ---
            //
            // The ring above ALWAYS fills, whatever happens here — the pre-roll must
            // survive a failed take so the next attempt still has its 30 s of history.
            //
            // `failPtr` short-circuits after the first failure, and that is the fix, not
            // a micro-optimisation. Previously a full volume produced a failed write plus
            // a `localizedDescription` (a bundle lookup) plus a log allocation on EVERY
            // buffer — ~12 times a second, on the tap thread, for the rest of a take that
            // was already lost. Error handling whose cost grows with the error's duration
            // is a load source. One line, once, then quiet.
            guard activePtr.pointee, !failPtr.pointee, let file = filePtr.pointee else { return }
            do {
                try file.write(from: buffer)
            } catch {
                // Raise the latch BEFORE logging: the log call is the expensive part and
                // the flag is what stops the next buffer from repeating it.
                failPtr.pointee = true
                log.log(.error, category: .audio,
                        "RetroCapture write failed — recording stops writing: \(error.localizedDescription)")
            }
        }

        log.log(.info, category: .audio,
                "RetroCapture tap installed — \(Int(format.sampleRate))Hz \(format.channelCount)ch, \(preRollSeconds)s ring")

        // Start waveform refresh at 2Hz for UI display
        waveformTimer?.invalidate()
        waveformTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateWaveform() }
        }
    }

    // MARK: - Waveform

    private func updateWaveform() {
        // The 2 Hz timer is how a failed write reaches the user DURING a take (the other
        // lift is in `stopRecording`, for a failure in the last half-second). Adding a
        // dedicated timer for a flag that flips at most once would be worse than half a
        // second of latency on a take that is already lost.
        //
        // Deliberately NOT gated on `isRecording`: the latch can only be raised while the
        // tap was armed, so that term added nothing and only created a window where a
        // late failure went unreported.
        //
        // Written only on the false→true transition — `waveformSamples` below is written
        // every tick, but `@Observable` tracks per keypath, so a view reading ONLY
        // `writeFailed` does not become a 2 Hz observer. Anything reading
        // `waveformSamples` from a floating/overlay view WOULD (freeze law).
        if writeFailure.pointee, !writeFailed {
            writeFailed = true
        }
        let totalFrames = ringCapacity
        let endFrame   = Int(ringWriteFrame.pointee)
        let startFrame = max(0, endFrame - totalFrames)
        let framesPerBin = totalFrames / waveformResolution
        guard framesPerBin > 0 else { return }

        var samples = [Float](repeating: 0, count: waveformResolution)
        for bin in 0..<waveformResolution {
            var sum: Float = 0
            for f in 0..<framesPerBin {
                let frame = startFrame + bin * framesPerBin + f
                let slot  = (frame % ringCapacity) * 2
                let l = ring[slot], r = ring[slot + 1]
                sum += l * l + r * r
            }
            samples[bin] = sqrt(sum / Float(framesPerBin * 2))
        }
        waveformSamples = samples
    }

    // MARK: - Recording control

    /// Begin a new recording: prepend the last `preRoll` seconds from the ring
    /// buffer (default: the full 30 s — "retro" capture), then enable the live tap
    /// write. Pass `preRoll: 0` for a live-only file that starts NOW — the loop
    /// exporter needs this (audit C6: the loop WAV silently began with 30 s of
    /// stale audio, and the LUFS normalisation measured that junk too).
    func startRecording(preRoll requestedPreRoll: Int? = nil) {
        guard !isRecording else { return }

        do {
            let url = try makeRecordingURL()
            guard let format = AVAudioFormat(standardFormatWithSampleRate: captureSampleRate, channels: 2) else {
                log.log(.error, category: .audio, "RetroCapture: cannot create recording format")
                return
            }
            let file = try AVAudioFile(forWriting: url,
                                       settings: format.settings,
                                       commonFormat: .pcmFormatFloat32,
                                       interleaved: false)

            // Write pre-roll BEFORE enabling live tap — file begins `preRoll`s in the past
            let preRoll = min(max(requestedPreRoll ?? preRollSeconds, 0), preRollSeconds)
            if preRoll > 0 {
                try writePreRollToFile(file, format: format, seconds: preRoll)
            }

            // Clear the latch BEFORE arming, so the first armed buffer starts from a
            // known-false state. ⛔ The first version of this comment justified the order
            // with a race that cannot happen — the tap tests `activePtr.pointee` first
            // and that is still false here, so no buffer can reach the write path yet.
            // The ordering is kept anyway, as defence for the day someone moves the arm
            // earlier; the wrong reason is removed because it is what a future edit would
            // have reasoned from.
            writeFailure.pointee = false
            writeFailed          = false

            activeFile.pointee = file
            isActive.pointee   = true
            isRecording        = true
            recordingSeconds   = 0
            lastURL            = url

            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.recordingSeconds += 1 }
            }

            log.log(.info, category: .audio,
                    "RetroCapture recording started (+\(preRoll)s pre-roll) → \(url.lastPathComponent)")

        } catch {
            log.log(.error, category: .audio, "RetroCapture: failed to start — \(error.localizedDescription)")
        }
    }

    /// Deinterleave ring buffer data and write to file in 8192-frame chunks.
    /// Must be called BEFORE activating the live tap to preserve correct chronological order.
    private func writePreRollToFile(_ file: AVAudioFile, format: AVAudioFormat, seconds: Int) throws {
        // This writer deinterleaves the STEREO ring buffer (L,R,L,R) into channels 0 AND 1.
        // `floatChannelData?[1]` is raw pointer indexing, NOT bounds-checked — a mono format
        // would make [1] a garbage pointer and corrupt memory. Guard the invariant explicitly
        // so a future caller passing a mono format fails loudly instead of scribbling memory.
        guard format.channelCount >= 2 else {
            throw NSError(domain: "RetroCapture", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "pre-roll writer requires a stereo (2-channel) format"])
        }
        let totalFrames = min(Int(Double(seconds) * captureSampleRate), ringCapacity)
        let endFrame   = Int(ringWriteFrame.pointee)
        let startFrame = max(0, endFrame - totalFrames)
        let chunkSize  = 8192
        var written    = 0

        while written < totalFrames {
            let frames = min(chunkSize, totalFrames - written)
            guard let pcmBuf = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(frames)) else {
                written += frames; continue
            }
            pcmBuf.frameLength = AVAudioFrameCount(frames)

            guard let ch0 = pcmBuf.floatChannelData?[0],
                  let ch1 = pcmBuf.floatChannelData?[1] else {
                written += frames; continue
            }

            // Deinterleave from ring buffer (L, R, L, R, …)
            for f in 0..<frames {
                let src = ((startFrame + written + f) % ringCapacity) * 2
                ch0[f] = ring[src]
                ch1[f] = ring[src + 1]
            }

            try file.write(from: pcmBuf)
            written += frames
        }
    }

    /// Stop recording. Calls completion on main thread with the file URL.
    func stopRecording(completion: ((URL) -> Void)? = nil) {
        guard isRecording else { return }

        isActive.pointee  = false
        timer?.invalidate()
        timer = nil

        // Lift the latch HERE too, not only from the 2 Hz tick. Without this, a write
        // that failed in the last half-second of a take is never surfaced at all: stop
        // clears `isRecording`, the next tick finds nothing to report, and the caller
        // exports a truncated file as if it were good. Short takes are exactly the ones
        // a full volume produces, so this is the common case, not the corner.
        if writeFailure.pointee { writeFailed = true }

        // Close file off the audio callback path
        let closedFile = activeFile.pointee
        activeFile.pointee = nil
        isRecording = false

        if let url = lastURL {
            let dur = recordingSeconds
            log.log(.info, category: .audio, "RetroCapture stopped — \(dur)s saved to \(url.lastPathComponent)")
            completion?(url)
        }
        _ = closedFile  // ARC releases AVAudioFile here, flushing buffers
    }

    // MARK: - Pre-roll snapshot (for external preview / waveform display)

    /// Returns the last `seconds` of ring buffer audio as interleaved stereo floats.
    /// Use for waveform preview. Recording already prepends pre-roll via writePreRollToFile().
    func snapshotPreRoll(seconds: Int = 30) -> [Float] {
        let frames  = min(Int(Double(seconds) * captureSampleRate), ringCapacity)
        let endFrame = Int(ringWriteFrame.pointee)
        let startFrame = max(0, endFrame - frames)
        var out = [Float](repeating: 0, count: frames * 2)

        for f in 0..<frames {
            let src = ((startFrame + f) % ringCapacity) * 2
            let dst = f * 2
            out[dst]     = ring[src]
            out[dst + 1] = ring[src + 1]
        }
        return out
    }

    // MARK: - Retroactive snapshot to file ("keep what just played")

    /// Write the most recent `seconds` of the always-on ring buffer to a temp CAF —
    /// WITHOUT touching the live transport or starting a recording. This is the
    /// retroactive "die Stelle war gut → behalten" path: grab exactly what was just
    /// heard (already including reverb/delay tails). Returns the file URL, or nil.
    func captureRecent(seconds: Double) -> URL? {
        let frames = min(max(Int(seconds * captureSampleRate), 0), ringCapacity)
        guard frames > 0 else { return nil }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: captureSampleRate, channels: 2) else {
            log.log(.error, category: .audio, "RetroCapture.captureRecent: cannot create format")
            return nil
        }
        do {
            let url = try makeRecordingURL()
            let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            let endFrame = Int(ringWriteFrame.pointee)
            let startFrame = max(0, endFrame - frames)
            let chunkSize = 8192
            var written = 0
            while written < frames {
                let n = min(chunkSize, frames - written)
                guard let buf = AVAudioPCMBuffer(pcmFormat: format,
                                                 frameCapacity: AVAudioFrameCount(n)) else { written += n; continue }
                buf.frameLength = AVAudioFrameCount(n)
                guard let ch0 = buf.floatChannelData?[0], let ch1 = buf.floatChannelData?[1] else {
                    written += n; continue
                }
                for f in 0..<n {
                    let src = ((startFrame + written + f) % ringCapacity) * 2
                    ch0[f] = ring[src]
                    ch1[f] = ring[src + 1]
                }
                try file.write(from: buf)
                written += n
            }
            log.log(.info, category: .audio, "RetroCapture.captureRecent — \(frames) frames → \(url.lastPathComponent)")
            return url
        } catch {
            log.log(.error, category: .audio, "RetroCapture.captureRecent failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    private func makeRecordingURL() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ts = Int(Date().timeIntervalSince1970)
        return dir.appendingPathComponent("echoel_\(ts).caf")
    }
}
#endif
