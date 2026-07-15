// MediaLibrary.swift
// Echoel — durable home for IMPORTED media files (audio today; video next) inside
// the App Group container, so a timeline region's `mediaRef` survives relaunch and
// is reachable from the AUv3/widget processes (the same container AppGroupStore
// uses for JSON). Copying the picked file in is the ONE impure step of the import
// path; the placement math (AudioClipFactory + TimelineDocument.nextStartTick)
// stays pure and unit-tested. No logger dependency — failures throw so the calling
// surface decides how loud to be.

import Foundation

public enum MediaLibrary {

    public enum MediaImportError: Error, Equatable {
        case noContainer   // couldn't resolve any writable directory
        case copyFailed    // the file copy itself failed (permissions / disk)
    }

    /// App Group identifier — matches the `group.com.echoelmusic` entitlement
    /// (same value AppGroupStore uses; kept local so this helper stays standalone).
    static let appGroupID = "group.com.echoelmusic"

    /// Resolve (creating if needed) a media subdirectory. Prefers the App Group
    /// container; falls back to Application Support (unit tests / Linux CI) then
    /// the temporary dir, mirroring AppGroupStore so media and JSON co-locate.
    static func directory(_ sub: String) -> URL? {
        let fm = FileManager.default
        let base: URL
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            base = group
        } else if let support = try? fm.url(for: .applicationSupportDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: nil, create: true) {
            base = support
        } else {
            base = fm.temporaryDirectory
        }
        let dir = base.appendingPathComponent(sub, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
            catch { return nil }
        }
        return dir
    }

    /// Copy a user-picked audio file (already security-scope-accessed by the
    /// caller) into `Media/Audio` under a fresh unique name, preserving its
    /// extension. Returns the destination URL — its absolute path becomes the
    /// region's `mediaRef`. The caller owns start/stopAccessingSecurityScopedResource.
    public static func importAudio(from source: URL) throws -> URL {
        try copyIn(source, subdirectory: "Media/Audio", fallbackExt: "wav")
    }

    /// Copy a user-picked VIDEO file into `Media/Video` (same contract as
    /// importAudio). Its absolute path becomes the video region's `mediaRef`.
    public static func importVideo(from source: URL) throws -> URL {
        try copyIn(source, subdirectory: "Media/Video", fallbackExt: "mov")
    }

    /// Shared copy: resolve the media subdir, pick a fresh UUID name (preserving
    /// the source extension), copy the file in. Throws on no container / copy fail.
    private static func copyIn(_ source: URL, subdirectory: String, fallbackExt: String) throws -> URL {
        guard let dir = directory(subdirectory) else { throw MediaImportError.noContainer }
        let ext = source.pathExtension.isEmpty ? fallbackExt : source.pathExtension
        let dest = dir.appendingPathComponent("\(UUID().uuidString).\(ext)", isDirectory: false)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
        } catch {
            throw MediaImportError.copyFailed
        }
        return dest
    }
}
