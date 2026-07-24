// AppGroupStore.swift
// Echoel — tiny Codable-JSON persistence into the App Group container
// (`group.com.echoelmusic`), so user-authored data (synth patches, clips)
// survives relaunch and is reachable from the AUv3 extension. Falls back to the
// app's Application Support directory when the App Group is unavailable (e.g.
// SwiftPM unit tests, Linux CI), so callers never have to special-case it.
//
// Pure Foundation, cross-platform. Absence/write failures surface as nil/false so
// callers decide how loud to be; the ONE exception is a present-but-undecodable read,
// which is logged as a data-loss signal via the `#if canImport(os)`-guarded EchoelLogger
// (cross-platform-safe — Linux degrades to a no-op).

import Foundation

/// Reads and writes small `Codable` values as JSON files, keyed by a filename.
public struct AppGroupStore: Sendable {

    /// App Group identifier — matches the `group.com.echoelmusic` entitlement.
    public static let appGroupID = "group.com.echoelmusic"

    /// Subdirectory inside the container where JSON files live.
    private let subdirectory: String

    public init(subdirectory: String = "Echoel") {
        self.subdirectory = subdirectory
    }

    // MARK: - Directory resolution

    /// The container directory, creating it if needed. Prefers the App Group;
    /// falls back to Application Support (or the temporary dir as a last resort).
    private func directory() -> URL? {
        let fm = FileManager.default
        let base: URL
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            base = group
        } else if let support = try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) {
            base = support
        } else {
            base = fm.temporaryDirectory
        }
        let dir = base.appendingPathComponent(subdirectory, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func fileURL(_ name: String) -> URL? {
        directory()?.appendingPathComponent("\(name).json", isDirectory: false)
    }

    // MARK: - Read / write

    /// Decode the value stored under `name`, or `nil` if absent/unreadable.
    ///
    /// An ABSENT file is the normal "nothing saved yet" case → silent `nil`. But a file
    /// that EXISTS and fails to decode is a data-loss SIGNAL — a schema change the
    /// defensive decoders couldn't absorb, or on-disk corruption — and is logged, never
    /// silent: the caller falls back to an empty document, so without telemetry a user
    /// losing their whole song produces zero signal. (`log`/EchoelLogger is
    /// `#if canImport(os)`-guarded, so this stays cross-platform.)
    public func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let url = fileURL(name) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil } // absent = normal
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            log.log(.error, category: .system,
                    "AppGroupStore: \(name).json present but failed to decode as \(T.self) — \(error)")
            return nil
        }
    }

    /// Encode and atomically write `value` under `name`. Returns success.
    @discardableResult
    public func save<T: Encodable>(_ value: T, name: String) -> Bool {
        guard let url = fileURL(name) else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return false }
        do {
            // .completeFileProtection — the App Group container is shared with the
            // AUv3/widget/watch processes; encrypt at rest so session/bio/state
            // files are unreadable while the device is locked.
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    /// Delete the file stored under `name` (no-op if absent).
    public func delete(name: String) {
        guard let url = fileURL(name) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
