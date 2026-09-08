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

    /// Copy a user-picked IMAGE into `Media/Image` (V3 — stills land on video lanes
    /// as fixed-length clips; same contract as importVideo).
    public static func importImage(from source: URL) throws -> URL {
        try copyIn(source, subdirectory: "Media/Image", fallbackExt: "jpg")
    }

    /// Resolve a clip's `mediaRef` to an EXISTING file URL — nil for empty refs or
    /// truly vanished files. THE single resolver for every surface that turns a
    /// region into playable media (timeline audition, audio lanes, the Video
    /// Monitor; ⛔ "ArrangeTimelineView" stood in this list until #1107 — deleted by
    /// #121 Slice 4). Handles all conventions:
    /// 1. an absolute path that still exists (timeline imports, pre-update),
    /// 2. H6 re-rooting: an absolute path whose CONTAINER PREFIX died — an app
    ///    update/device migration changes the app-group container UUID, but the
    ///    file itself still sits under the same media subdirectory in the NEW
    ///    container. Re-resolve by file name against every media home, FIRST match
    ///    wins in the Audio→Video→Image order. (Import names are readable + only
    ///    per-directory-unique since O11, no longer globally-unique UUIDs; a full
    ///    name+extension clash across two homes is effectively unreachable because
    ///    the audio/video/image picker extension sets are disjoint — but do not
    ///    assume global filename uniqueness here.) Without this re-root, every
    ///    imported clip silently lost its audio/video on the first app update
    ///    (audit CRITICAL H6).
    /// 3. a bare file name against Documents/Videos (VisualRecorder captures).
    /// Side effect: probing creates the media home directories if missing (the
    /// same dirs import would create) — not a pure function by design.
    public static func resolveRef(_ ref: String?) -> URL? {
        guard let ref, !ref.isEmpty else { return nil }
        let fm = FileManager.default
        let url = URL(fileURLWithPath: ref)
        if fm.fileExists(atPath: url.path) { return url }
        let name = url.lastPathComponent
        guard !name.isEmpty else { return nil }
        for sub in ["Media/Audio", "Media/Video", "Media/Image"] {
            if let dir = directory(sub) {
                let candidate = dir.appendingPathComponent(name, isDirectory: false)
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let candidate = docs.appendingPathComponent("Videos", isDirectory: true)
                .appendingPathComponent(name, isDirectory: false)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Shared copy: resolve the media subdir, pick a READABLE collision-free name
    /// (O11 — the founder saw a raw UUID where a sample name belonged, because the
    /// old `<UUID>.<ext>` filename is what `BeatPlayer.sampleRefDisplayName` shows
    /// for an imported ref), copy the file in. Throws on no container / copy fail.
    private static func copyIn(_ source: URL, subdirectory: String, fallbackExt: String) throws -> URL {
        guard let dir = directory(subdirectory) else { throw MediaImportError.noContainer }
        let ext = source.pathExtension.isEmpty ? fallbackExt : source.pathExtension
        let base = source.deletingPathExtension().lastPathComponent
        let name = uniqueName(base: base, ext: ext, taken: { candidate in
            FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path)
        })
        let dest = dir.appendingPathComponent(name, isDirectory: false)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
        } catch {
            throw MediaImportError.copyFailed
        }
        return dest
    }

    /// A readable, filesystem-safe, collision-free filename for an imported media
    /// file (O11). Sanitizes the source base name (drops path separators + reserved
    /// characters, trims, caps length), keeps the extension, and disambiguates with
    /// a numeric suffix ONLY on an actual clash — so `sampleRefDisplayName` shows
    /// "MyLoop" (or "MyLoop-1") instead of a UUID. An empty/garbage base falls back
    /// to "sample". Pure (the filesystem check is injected) → unit-tested.
    static func uniqueName(base: String, ext: String, taken: (String) -> Bool) -> String {
        let cleaned = base
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = cleaned.isEmpty ? "sample" : String(cleaned.prefix(60))
        var candidate = "\(safe).\(ext)"
        var n = 1
        while taken(candidate) {
            candidate = "\(safe)-\(n).\(ext)"
            n += 1
        }
        return candidate
    }
}
