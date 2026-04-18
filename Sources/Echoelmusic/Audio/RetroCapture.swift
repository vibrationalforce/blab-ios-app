#if canImport(AVFoundation)
import AVFoundation
import Accelerate
import Observation
import os.log

/// Always-on audio capture with retroactive pre-roll ring buffer.
///
/// Lifecycle:
///   1. `install(on:)` — installs tap on mainMixerNode, ring buffer fills continuously.
///   2. `startRecording()` — begins writing to disk from this moment forward.
///   3. `stopRecording(completion:)` — closes file, calls completion with URL.
///
/// Phase 2: `startRecording()` will prepend the 30-second pre-roll to the file.
@MainActor @Observable
final class RetroCapture {

    // MARK: - Observable state

    private(set) var isRecording = false
    private(set) var recordingSeconds = 0
    private(set) var lastURL: URL?

    // MARK: - Ring buffer (always-on pre-roll: 30s stereo @ 48kHz ≈ 11MB)

    private let preRollSeconds: Int = 30
    private let ringCapacity: Int                        // frames (2ch interleaved, so *2 floats)
    nonisolated(unsafe) private let ring: UnsafeMutablePointer<Float>
    nonisolated(unsafe) private let ringWriteFrame: UnsafeMutablePointer<Int64>  // atomic-width

    // MARK: - Recording

    nonisolated(unsafe) private let activeFile: UnsafeMutablePointer<AVAudioFile?>
    nonisolated(unsafe) private let isActive: UnsafeMutablePointer<Bool>

    private var timer: Timer?

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
    }

    deinit {
        ring.deallocate()
        ringWriteFrame.deallocate()
        activeFile.deallocate()
        isActive.deallocate()
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

        // Capture raw pointers only — never capture self on audio-thread callback
        let ringPtr   = ring
        let writePtr  = ringWriteFrame
        let filePtr   = activeFile
        let activePtr = isActive
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
            guard activePtr.pointee, let file = filePtr.pointee else { return }
            do { try file.write(from: buffer) }
            catch { log.log(.error, category: .audio, "RetroCapture write error: \(error.localizedDescription)") }
        }

        log.log(.info, category: .audio,
                "RetroCapture tap installed — \(Int(format.sampleRate))Hz \(format.channelCount)ch, \(preRollSeconds)s ring")
    }

    // MARK: - Recording control

    /// Begin writing to a new timestamped CAF file in Documents/Recordings/.
    func startRecording() {
        guard !isRecording else { return }

        do {
            let url = try makeRecordingURL()
            // Format must match the tap format — derive from Documents path convention
            // File format: 32-bit float PCM, 48kHz, stereo (matches tap)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else {
                log.log(.error, category: .audio, "RetroCapture: cannot create recording format")
                return
            }
            let file = try AVAudioFile(forWriting: url,
                                       settings: format.settings,
                                       commonFormat: .pcmFormatFloat32,
                                       interleaved: false)
            activeFile.pointee = file
            isActive.pointee   = true
            isRecording        = true
            recordingSeconds   = 0
            lastURL            = url

            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.recordingSeconds += 1 }
            }

            log.log(.info, category: .audio, "RetroCapture recording started → \(url.lastPathComponent)")

        } catch {
            log.log(.error, category: .audio, "RetroCapture: failed to start — \(error.localizedDescription)")
        }
    }

    /// Stop recording. Calls completion on main thread with the file URL.
    func stopRecording(completion: ((URL) -> Void)? = nil) {
        guard isRecording else { return }

        isActive.pointee  = false
        timer?.invalidate()
        timer = nil

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

    // MARK: - Pre-roll snapshot (Phase 2 hook)

    /// Returns the last `seconds` of captured audio as a PCM buffer.
    /// Phase 2: called by startRecording() to prepend pre-roll to the recording.
    func snapshotPreRoll(seconds: Int = 30) -> [Float] {
        let frames  = min(seconds * 48000, ringCapacity)
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
