#if canImport(AVFoundation)
import AVFoundation
import Foundation
#if canImport(Observation)
import Observation
#endif

/// Records the FINAL output mix to a temporary LPCM file so a `VisualRecorder`
/// video can be muxed with sound. Unlike `RetroCapture` (which taps `mainMixerNode`
/// with a 30 s pre-roll), this starts EXACTLY at record time — no pre-roll — so the
/// audio lines up with the video's first frame.
///
/// Tap point: `outputNode`. A node bus allows only ONE tap, and `mainMixerNode`
/// (RetroCapture) + `masterMixer` (the loudness meter) are already tapped; the
/// `outputNode` carries the same post-mix signal and is otherwise free.
///
/// The file is written in the tap node's OWN format (so `AVAudioFile.write(from:)`
/// can never fail a format mismatch); the muxer transcodes to AAC on export.
@MainActor @Observable
final class MixTapRecorder {

    private(set) var isRecording = false
    private(set) var lastURL: URL?

    // Touched on the tap thread via raw pointers ONLY (never `self`) — the proven
    // RetroCapture pattern. `activeFile` holds the open writer; `isActive` gates it.
    @ObservationIgnored nonisolated(unsafe) private let activeFile: UnsafeMutablePointer<AVAudioFile?>
    @ObservationIgnored nonisolated(unsafe) private let isActive: UnsafeMutablePointer<Bool>
    @ObservationIgnored private weak var tappedNode: AVAudioNode?

    init() {
        activeFile = .allocate(capacity: 1); activeFile.initialize(to: nil)
        isActive = .allocate(capacity: 1); isActive.initialize(to: false)
    }

    deinit {
        isActive.pointee = false
        activeFile.deinitialize(count: 1); activeFile.deallocate()
        isActive.deallocate()
    }

    /// Install the tap and begin writing. Returns false on invalid format / file
    /// error. Safe to call again while recording (no-op).
    @discardableResult
    func start(on engine: AVAudioEngine) -> Bool {
        guard !isRecording else { return true }
        let node = engine.outputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            log.log(.error, category: .audio, "MixTapRecorder: invalid output format — not started")
            return false
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("echoel_mixaudio_\(Int(Date().timeIntervalSince1970)).caf")
        let file: AVAudioFile
        do {
            // Write in the node's OWN format so the tapped buffer always matches the
            // file's processing format (no silent write-time mismatch drops).
            file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        } catch {
            log.log(.error, category: .audio, "MixTapRecorder: cannot open file — \(error.localizedDescription)")
            return false
        }

        node.removeTap(onBus: 0)          // defensive; outputNode should be untapped
        tappedNode = node
        let filePtr = activeFile
        let activePtr = isActive
        filePtr.pointee = file
        activePtr.pointee = true

        node.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, _ in
            guard activePtr.pointee, let f = filePtr.pointee else { return }
            do { try f.write(from: buffer) }
            catch { /* drop this buffer; keep recording */ }
        }

        isRecording = true
        lastURL = url
        log.log(.info, category: .audio, "MixTapRecorder started → \(url.lastPathComponent)")
        return true
    }

    /// Stop, remove the tap, close the file, return its URL (nil if not recording).
    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return nil }
        isActive.pointee = false          // gate the tap FIRST (in-flight write finishes)
        tappedNode?.removeTap(onBus: 0)
        tappedNode = nil
        activeFile.pointee = nil          // ARC releases the writer → file finalized
        isRecording = false
        log.log(.info, category: .audio, "MixTapRecorder stopped → \(lastURL?.lastPathComponent ?? "nil")")
        return lastURL
    }
}
#endif
