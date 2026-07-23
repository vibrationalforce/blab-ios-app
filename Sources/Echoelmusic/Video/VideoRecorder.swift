#if canImport(AVFoundation)
import AVFoundation
import CoreVideo
#if canImport(Observation)
import Observation
#endif

/// P3 · Video — the capture SINK. Writes a stream of `CVPixelBuffer` frames
/// (the same 32BGRA buffers `CameraCapture.onFrame` already produces, and the
/// buffers a future bio-visual compositor will render) to an H.264 `.mp4` on
/// disk, ready for trim + share.
///
/// Deliberately narrow (founder decision 2026-07-01): capture → file. Trim,
/// bio-overlay and AAC audio-mux land in follow-up cycles. Video-only for now.
///
/// Threading (forward-safe by design): `ingest(_:at:)` is `nonisolated` and does
/// the AVAssetWriter append **synchronously on the caller's capture queue** — no
/// cross-queue transfer of the (non-Sendable) pixel buffer, and crucially NO
/// per-frame `Task { @MainActor }` hop (the executor-starving anti-pattern from
/// 10.76.48). Writer state is guarded by an `NSLock` so the @MainActor control
/// path (start/stop) and the capture-queue ingress never race; the observable
/// state (`recordState`) only crosses to main on transitions, never per frame.
/// The UI clock is read via `recordedSeconds()` from a leaf view (freeze rule).
///
/// Usage:
///   let rec = VideoRecorder()
///   rec.startRecording()
///   camera.onFrame = { buffer in rec.ingest(buffer, at: <capture PTS as CMTime>) }
///   let url = await rec.stopRecording()   // → finished .mp4, or nil on failure
@MainActor @Observable
final class VideoRecorder {

    // MARK: - State

    enum RecordState: Equatable {
        case idle
        case recording
        case finishing
        case done(URL)
        case error(String)

        var isRecording: Bool { self == .recording }
        var finishedURL: URL? {
            if case .done(let url) = self { return url }
            return nil
        }
    }

    private(set) var recordState: RecordState = .idle

    // MARK: - Writer state (guarded by `lock`, touched from any queue)

    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored nonisolated(unsafe) private var armed = false
    @ObservationIgnored nonisolated(unsafe) private var writer: AVAssetWriter?
    @ObservationIgnored nonisolated(unsafe) private var videoInput: AVAssetWriterInput?
    @ObservationIgnored nonisolated(unsafe) private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    @ObservationIgnored nonisolated(unsafe) private var sessionStartTime: CMTime?
    @ObservationIgnored nonisolated(unsafe) private var lastPresentationTime: CMTime = .zero
    @ObservationIgnored nonisolated(unsafe) private var outputURL: URL?
    @ObservationIgnored nonisolated(unsafe) private var elapsed: Double = 0

    // MARK: - Control (main actor)

    /// Arm the recorder. The writer itself is built when the first frame arrives
    /// (so its dimensions match the real capture). Frames ingested before this,
    /// or after `stopRecording`, are dropped.
    func startRecording() {
        // Re-armable from any TERMINAL state (.idle / .done / .error) — only reject
        // while a capture is still active (.recording / .finishing). The old guard
        // required exactly `.idle`, but a finished capture leaves `.done(url)`, so a
        // SECOND start was silently dropped → "kann ich das danach nicht mehr machen".
        // The finished file's URL is consumed via `stopRecording()`'s return value,
        // not by observing `.done`, so overwriting that state here loses nothing.
        guard recordState != .recording, recordState != .finishing else { return }
        lock.lock()
        armed = true
        writer = nil; videoInput = nil; adaptor = nil
        sessionStartTime = nil; lastPresentationTime = .zero
        outputURL = nil; elapsed = 0
        lock.unlock()
        recordState = .recording
        log.log(.info, category: .video, "VideoRecorder: armed")
    }

    /// Finish writing and return the finished file URL (nil on failure / if not
    /// recording, or if no frame was ever captured).
    @discardableResult
    func stopRecording() async -> URL? {
        guard recordState == .recording else { return nil }
        recordState = .finishing

        // Close the ingress and snapshot the writer under the lock. Any in-flight
        // append holds the lock, so it completes before we disarm; any later
        // ingest re-checks `armed` under the lock and bails. The lock/unlock lives in
        // a SYNCHRONOUS helper — NSLock.lock()/unlock() are unavailable in an async
        // context (they must not be held across a suspension).
        let snapshot = disarmAndSnapshot()
        let writer = snapshot.writer
        let elapsedSnapshot = snapshot.elapsed
        let url = snapshot.url

        guard let writer, let input = snapshot.input else {
            // Armed but no frame ever arrived — nothing to finalize.
            recordState = .idle
            return nil
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }

        if writer.status == .completed, let url {
            recordState = .done(url)
            log.log(.info, category: .video, "VideoRecorder: wrote \(url.lastPathComponent) (\(String(format: "%.1f", elapsedSnapshot))s)")
            return url
        } else {
            let message = writer.error?.localizedDescription ?? "unknown writer error"
            recordState = .error(message)
            log.log(.error, category: .video, "VideoRecorder finish failed: \(message)")
            return nil
        }
    }

    func reset() {
        guard recordState != .recording, recordState != .finishing else { return }
        recordState = .idle
    }

    /// Synchronous, lock-guarded snapshot for `stopRecording` — disarms the ingress
    /// and returns the writer state. Kept sync (nonisolated) because NSLock.lock()/
    /// unlock() are banned inside an async function.
    private nonisolated func disarmAndSnapshot()
        -> (writer: AVAssetWriter?, input: AVAssetWriterInput?, url: URL?, elapsed: Double) {
        lock.lock(); defer { lock.unlock() }
        armed = false
        return (writer, videoInput, outputURL, elapsed)
    }

    /// Seconds written so far. Read from a leaf view (poll / TimelineView) so the
    /// live clock never churns a parent body.
    nonisolated func recordedSeconds() -> Double {
        lock.lock(); defer { lock.unlock() }
        return elapsed
    }

    // MARK: - Ingress (capture queue — nonisolated, synchronous, no main hop)

    /// Append one captured frame. First call lazily builds the writer from the
    /// buffer's own dimensions and opens the session. Safe to call from the
    /// capture delegate queue. No-op unless armed.
    nonisolated func ingest(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        lock.lock()
        defer { lock.unlock() }
        guard armed else { return }

        if writer == nil {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            do {
                try setUpWriterLocked(width: width, height: height, firstFrameTime: time)
            } catch {
                armed = false
                let message = error.localizedDescription
                log.log(.error, category: .video, "VideoRecorder setup failed: \(message)")
                Task { @MainActor [weak self] in self?.recordState = .error(message) }
                return
            }
        }

        guard let input = videoInput, let adaptor, let start = sessionStartTime else { return }
        // Drop frames the encoder can't keep up with rather than block capture.
        guard input.isReadyForMoreMediaData else { return }
        // Non-monotonic timestamps would fail the append — skip them.
        guard time >= lastPresentationTime else { return }

        if adaptor.append(pixelBuffer, withPresentationTime: time) {
            lastPresentationTime = time
            elapsed = max(0, CMTimeGetSeconds(CMTimeSubtract(time, start)))
        }
    }

    // MARK: - Writer setup (called with `lock` held)

    private nonisolated func setUpWriterLocked(width: Int, height: Int, firstFrameTime: CMTime) throws {
        guard width > 0, height > 0 else { throw RecorderError.invalidDimensions }
        let url = try Self.makeOutputURL()

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings = Self.videoSettings(width: width, height: height,
                                          bitRate: Self.recommendedBitRate(width: width, height: height))
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                           sourcePixelBufferAttributes: attributes)

        guard writer.canAdd(input) else { throw RecorderError.cannotAddInput }
        writer.add(input)

        guard writer.startWriting() else {
            throw writer.error ?? RecorderError.cannotStartWriting
        }
        writer.startSession(atSourceTime: firstFrameTime)

        self.writer = writer
        self.videoInput = input
        self.adaptor = adaptor
        self.sessionStartTime = firstFrameTime
        self.lastPresentationTime = firstFrameTime
        self.outputURL = url
        log.log(.info, category: .video, "VideoRecorder: writing \(width)x\(height) → \(url.lastPathComponent)")
    }

    // MARK: - Pure helpers (unit-testable without a device)

    /// H.264 writer settings for the given frame size + target bitrate.
    nonisolated static func videoSettings(width: Int, height: Int, bitRate: Int) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30,
                // Declare the nominal source rate (matches the 30-frame GOP, = 1s at 30 fps):
                // gives the encoder's rate-control an anchor and stamps the frame rate an NLE
                // (DaVinci Resolve etc.) reads on ingest, instead of leaving it undeclared.
                AVVideoExpectedSourceFrameRateKey: 30,
            ],
        ]
    }

    /// Bitrate heuristic: ~4 bits per pixel-frame, clamped to a sane 2–20 Mbps
    /// so tiny previews aren't wasteful and 1080p isn't starved.
    nonisolated static func recommendedBitRate(width: Int, height: Int) -> Int {
        let pixels = max(0, width) * max(0, height)
        let raw = pixels * 4
        return min(max(raw, 2_000_000), 20_000_000)
    }

    /// Unique output URL under Documents/Videos (created if missing).
    nonisolated static func makeOutputURL() throws -> URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw RecorderError.noDocumentsDirectory
        }
        let dir = docs.appendingPathComponent("Videos", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Collision-proof: a 1-second-resolution stamp alone lets a rapid re-record
        // reuse the same filename → AVAssetWriter fails to .error and no video saves.
        // Keep the epoch prefix for human sortability, add a UUID suffix for uniqueness.
        let stamp = "\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8))"
        return dir.appendingPathComponent("echoel_\(stamp).mp4")
    }

    // MARK: - Errors

    enum RecorderError: LocalizedError {
        case invalidDimensions, cannotAddInput, cannotStartWriting, noDocumentsDirectory

        var errorDescription: String? {
            switch self {
            case .invalidDimensions:    return "Capture frame has invalid dimensions"
            case .cannotAddInput:       return "Cannot add the video input to the writer"
            case .cannotStartWriting:   return "The video writer could not start"
            case .noDocumentsDirectory: return "Cannot locate the documents directory"
            }
        }
    }
}
#endif
