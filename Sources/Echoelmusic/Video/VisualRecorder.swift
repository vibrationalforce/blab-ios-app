#if canImport(AVFoundation) && canImport(Metal)
import AVFoundation
import Metal
import CoreVideo
import CoreMedia
import QuartzCore
#if canImport(Observation)
import Observation
#endif
#if canImport(Photos)
import Photos
#endif

/// P3 · Video — records the bio-reactive Metal visual (the image the body drives)
/// to an H.264 `.mp4`. This is the on-brand video source: it does NOT touch the
/// low-res, bio-critical rPPG camera path, and there is no camera-session
/// conflict with a running pulse measurement.
///
/// How: from the Metal draw loop (main thread), after the shader has rendered the
/// frame into the drawable, `capture(from:in:device:)` blits that drawable texture
/// into a pooled BGRA `CVPixelBuffer` **inside the same command buffer** (so it
/// records this exact frame), then feeds the buffer to `VideoRecorder` on GPU
/// completion. `VideoRecorder.ingest` is lock-safe + nonisolated, so the
/// completion handler (a background GPU thread) can call it directly.
///
/// UI observes `video.recordState`.
@MainActor @Observable
final class VisualRecorder {

    /// The underlying file sink (H.264 mp4). Its `recordState` is the observable UI state.
    let video = VideoRecorder()

    @ObservationIgnored private var textureCache: CVMetalTextureCache?
    @ObservationIgnored private var pool: CVPixelBufferPool?
    @ObservationIgnored private var poolWidth = 0
    @ObservationIgnored private var poolHeight = 0

    var isRecording: Bool { video.recordState.isRecording }

    @ObservationIgnored private weak var audioEngine: AudioEngine?

    // MARK: - Control

    /// Start recording the visual. The master-mix audio is grabbed from the
    /// always-on ring buffer on `stop()` (last N seconds), so nothing to start here
    /// but remembering the engine to pull from.
    func start(audio: AudioEngine? = nil) {
        audioEngine = audio
        video.startRecording()
    }

    /// Finish the video, grab the matching tail of master-mix audio, and mux them.
    /// Returns the final .mp4 (video-only if there was no audio engine, nil only if
    /// the video itself failed).
    @discardableResult
    func stop() async -> URL? {
        let videoURL = await video.stopRecording()
        // Pull the last `duration` seconds of the mix NOW (ends ≈ the video's end →
        // best-effort alignment). Ring is ~30 s; longer videos get their last 30 s.
        let duration = video.recordedSeconds()
        let audioURL = duration > 0.2 ? audioEngine?.captureRecentMixAudio(seconds: duration) : nil
        audioEngine = nil
        // The captured mix audio is a temp intermediate. Once VideoMuxer has baked it
        // into the final .mp4 (or if we bail before muxing), delete it so temp audio
        // files don't accumulate in tmp. Runs at scope exit — AFTER the awaited mux
        // completes below — so it never pulls the file out from under the export.
        defer { if let audioURL { try? FileManager.default.removeItem(at: audioURL) } }
        guard let videoURL else { return nil }
        guard let audioURL else {
            Self.saveToPhotoLibrary(videoURL)
            return videoURL
        }
        if let muxed = await VideoMuxer.mux(video: videoURL, audio: audioURL) {
            // The muxed clip is the durable library entry (Documents/Videos) —
            // drop the silent intermediate so the Video window never lists a
            // soundless twin of every recording.
            try? FileManager.default.removeItem(at: videoURL)
            Self.saveToPhotoLibrary(muxed)
            return muxed
        }
        Self.saveToPhotoLibrary(videoURL)
        return videoURL   // mux failed → return at least the silent video
    }

    /// Every finished recording is ALSO added to the user's photo library, so it lands
    /// where they keep and share video; the app-private Documents/Videos copy stays the
    /// durable fallback either way. (The original 2026-07-17 reason was re-import onto a
    /// video LANE — those lanes were deleted with the video-cut surface, so only the
    /// keep-and-share half survives. The permission string says exactly that now.)
    /// Best-effort and add-only (`.addOnly` — the narrowest
    /// permission; denial just logs, nothing else changes, and the Documents copy
    /// is never deleted before Photos has copied the file, because stop() never
    /// deletes the FINAL url at all).
    private static func saveToPhotoLibrary(_ url: URL) {
        #if canImport(Photos) && !os(macOS)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                log.log(.info, category: .video,
                        "VisualRecorder: photo-library add not authorized — clip stays in-app only")
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                if !success {
                    log.log(.error, category: .video,
                            "VisualRecorder: photo-library save failed: \(error?.localizedDescription ?? "unknown")")
                }
            }
        }
        #endif
    }

    // MARK: - Frame tap (main thread, from the Metal draw loop)

    /// Blit the just-rendered `source` (the drawable texture) into a pooled pixel
    /// buffer within `commandBuffer`, then ingest it on GPU completion. No-op unless
    /// recording. Requires the source texture to be blit-readable — the renderer
    /// sets `framebufferOnly = false` while recording so the drawable qualifies.
    func capture(from source: MTLTexture, in commandBuffer: MTLCommandBuffer, device: MTLDevice) {
        guard video.recordState.isRecording else { return }
        // H.264 requires even dimensions; drawables are normally even — guard anyway.
        let w = source.width & ~1
        let h = source.height & ~1
        guard w > 0, h > 0 else { return }

        ensureResources(width: w, height: h, device: device)
        guard let cache = textureCache, let pool else { return }

        var pbOut: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pbOut) == kCVReturnSuccess,
              let pb = pbOut else { return }

        var cvTexOut: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pb, nil, .bgra8Unorm, w, h, 0, &cvTexOut)
        guard status == kCVReturnSuccess, let cvTex = cvTexOut,
              let dst = CVMetalTextureGetTexture(cvTex),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return }

        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: w, height: h, depth: 1),
                  to: dst, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()

        // Ferry recorder + buffer + timestamp through the @unchecked Sendable box so the
        // @Sendable GPU-completion closure captures ONLY that box. The timestamp is
        // sampled NOW (at capture), not in the async handler.
        // INVARIANT: the pooled `pb` must not be recycled until this handler runs — it
        // isn't, because each frame dequeues a fresh buffer and hands its only reference
        // to the box, which releases it after `ingest`.
        let box = FrameBox(sink: video, pb: pb,
                           pts: CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600))
        commandBuffer.addCompletedHandler { _ in
            box.sink.ingest(box.pb, at: box.pts)
        }
    }

    // MARK: - Resources

    private func ensureResources(width: Int, height: Int, device: MTLDevice) {
        if textureCache == nil {
            var cacheOut: CVMetalTextureCache?
            CVMetalTextureCacheCreate(nil, nil, device, nil, &cacheOut)
            textureCache = cacheOut
        }
        if pool == nil || poolWidth != width || poolHeight != height {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            var poolOut: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &poolOut)
            pool = poolOut
            poolWidth = width
            poolHeight = height
        }
    }

    /// Recorder + non-Sendable pixel buffer + timestamp ferried into the @Sendable
    /// GPU completion handler (same escape hatch as the RGB sample queue).
    private struct FrameBox: @unchecked Sendable {
        let sink: VideoRecorder
        let pb: CVPixelBuffer
        let pts: CMTime
    }
}
#endif
