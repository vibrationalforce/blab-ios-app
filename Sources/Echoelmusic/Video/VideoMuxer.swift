#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// P3 · Video — combines a silent video file (from `VisualRecorder`) with an audio
/// file (the last N seconds of the master mix, from RetroCapture's ring buffer via
/// `AudioEngine.captureRecentMixAudio`) into one shareable `.mp4`. Both windows END
/// at stop time but can differ in length (the video is the whole session, the audio
/// is only the ring window), so the two tracks are END-aligned — the last
/// `min(video, audio)` seconds of each — via `VideoMuxAlignment`. (Start-aligning at
/// t=0 desynced any recording longer than the audio ring: video HEAD over audio TAIL.)
///
/// Uses only high-level, robust APIs (`AVMutableComposition` + the iOS-18
/// `AVAssetExportSession.export(to:as:)`), so there is no hand-rolled sample
/// interleaving to get wrong.
enum VideoMuxer {

    /// Mux `video` (H.264, no audio) with `audio` (LPCM) → a new `.mp4` with AAC
    /// audio. Returns nil on failure (caller should fall back to the video-only file).
    static func mux(video videoURL: URL, audio audioURL: URL) async -> URL? {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let composition = AVMutableComposition()

        do {
            guard let vSource = try await videoAsset.loadTracks(withMediaType: .video).first,
                  let aSource = try await audioAsset.loadTracks(withMediaType: .audio).first,
                  let vTrack = composition.addMutableTrack(withMediaType: .video,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid),
                  let aTrack = composition.addMutableTrack(withMediaType: .audio,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid) else {
                log.log(.error, category: .video, "VideoMuxer: missing source track")
                return nil
            }

            let vDur = try await videoAsset.load(.duration)
            let aDur = try await audioAsset.load(.duration)
            // END-align: take the last min(v,a) seconds of EACH track (the tested rule
            // in VideoMuxAlignment). Validate via the pure helper — `.seconds` is NaN
            // for an indefinite/invalid CMTime, which its isFinite guard rejects, so
            // this also subsumes the old `duration.isValid` check. The ranges below are
            // then built with EXACT CMTime arithmetic (no Double round-trip), so neither
            // start nor duration can round past a source track's real length.
            guard VideoMuxAlignment.endAligned(videoDuration: vDur.seconds,
                                               audioDuration: aDur.seconds) != nil else {
                log.log(.error, category: .video, "VideoMuxer: zero/invalid duration")
                return nil
            }
            let duration = CMTimeMinimum(vDur, aDur)                 // exact shorter length
            let vRange = CMTimeRange(start: CMTimeSubtract(vDur, duration), duration: duration)
            let aRange = CMTimeRange(start: CMTimeSubtract(aDur, duration), duration: duration)
            try vTrack.insertTimeRange(vRange, of: vSource, at: .zero)
            try aTrack.insertTimeRange(aRange, of: aSource, at: .zero)
            // Preserve the source video orientation (identity for our raw-buffer capture).
            vTrack.preferredTransform = try await vSource.load(.preferredTransform)
        } catch {
            log.log(.error, category: .video, "VideoMuxer compose failed: \(error.localizedDescription)")
            return nil
        }

        guard let export = AVAssetExportSession(asset: composition,
                                                presetName: AVAssetExportPresetHighestQuality) else {
            log.log(.error, category: .video, "VideoMuxer: cannot create export session")
            return nil
        }

        // Persist the FINAL A/V clip in the durable library (Documents/Videos) —
        // the Video window lists this folder, so a finished recording survives
        // relaunch instead of dying in tmp. Temp only as a fallback.
        let outURL = (try? VideoRecorder.makeOutputURL())
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("echoel_visual_\(Int(Date().timeIntervalSince1970)).mp4")
        do {
            // iOS-18 async export (the completion-handler `exportAsynchronously` is
            // deprecated → would break the -warnings-as-errors build).
            try await export.export(to: outURL, as: .mp4)
            return outURL
        } catch {
            log.log(.error, category: .video, "VideoMuxer export failed: \(error.localizedDescription)")
            return nil
        }
    }
}
#endif
