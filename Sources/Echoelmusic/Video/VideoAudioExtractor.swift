// VideoAudioExtractor.swift
// Echoelmusic — Video
//
// The impure edge of "video sound" (Slice 1b): pull a video's audio track out to a
// standalone m4a so it can become a first-class AUDIO clip (→ AudioLanePlayer →
// masterMixer, inheriting the stretch engine — see scratchpads/PLAN_VIDEO_AUDIO.md).
// The timeline video MONITOR stays muted by design; the SOUND comes from this extracted
// audio on an audio lane. Placement is the pure `VideoAudioPairing`; this file only
// extracts. Protocol-fronted so the wiring can be exercised with a stub in tests.

import Foundation

/// Extracts a video's audio track to a standalone file. Returns `nil` when the asset
/// has NO audio track (a silent video → no paired clip). Throws on a real failure.
public protocol VideoAudioExtracting: Sendable {
    func extractAudio(from videoURL: URL, to destinationDirectory: URL) async throws -> URL?
}

#if canImport(AVFoundation)
import AVFoundation

public struct VideoAudioExtractor: VideoAudioExtracting {

    public enum ExtractError: Error, Equatable {
        case sessionUnavailable   // couldn't build an export session for the asset
    }

    public init() {}

    /// Export the first audio track of `videoURL` to an `.m4a` (AAC) under a fresh UUID
    /// name in `destinationDirectory`. Uses the iOS-18 async `export(to:as:)` — no
    /// deprecated `exportAsynchronously`/`outputURL` (the repo builds -warnings-as-errors).
    /// Silent video (no audio track) → `nil` (caller lands the video only).
    public func extractAudio(from videoURL: URL, to destinationDirectory: URL) async throws -> URL? {
        let asset = AVURLAsset(url: videoURL)
        // Modern async track load (not the deprecated synchronous `asset.tracks`).
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { return nil }   // silent video → nothing to pair

        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetAppleM4A) else {
            throw ExtractError.sessionUnavailable
        }
        let dest = destinationDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("m4a")
        // iOS 18 async throwing export (replaces exportAsynchronously + status polling).
        do {
            try await session.export(to: dest, as: .m4a)
        } catch {
            // A throw mid-export can leave a partial/zero-byte file — don't strand it.
            try? FileManager.default.removeItem(at: dest)
            throw error
        }
        return dest
    }
}
#endif
