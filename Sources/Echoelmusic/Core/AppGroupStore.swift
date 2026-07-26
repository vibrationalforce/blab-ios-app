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

    /// Decode a TOP-LEVEL JSON array ELEMENT-tolerantly: one malformed element becomes `nil`
    /// instead of failing the whole file.
    ///
    /// WHY THIS EXISTS — the library-wipe. Every store that persists a top-level array did
    /// `load([X].self, name:) ?? []`, and `Codable`'s array decode is all-or-nothing: ONE
    /// element the field-level `decodeIfPresent` guards cannot absorb (a renamed enum case, a
    /// wrong-typed value, a half-written file) threw, `load` returned nil, and the store fell
    /// back to EMPTY. The next save then wrote that empty array back over the file — so a
    /// single bad patch destroyed the user's entire sound library, permanently, with the only
    /// trace being one log line. `TimelineDocument` already got this treatment for
    /// lanes/regions/automation.
    ///
    /// THE CLASS IS NOT CLOSED. This defends the five stores that go through `AppGroupStore`
    /// with a top-level array; `SignalRouter` (the patchbay, `UserDefaults`-backed) now calls
    /// the shared `decodeLossyArray` directly. Still open, same shape, tracked as task #170:
    /// `AutomationState` (`AutomationPlayer`) — a corrupt lane wipes every drawn curve AND
    /// flips `enabled` off; `Arrangement.sections` — a bare `try?` that turns a throw into
    /// total silent loss before persisting it back; and `[BioSessionSummary]`
    /// (`SessionRecorder`). Do not read this doc as "persistence is handled".
    ///
    /// Returns `nil` only when the file is absent, unreadable, or is not a JSON array at all —
    /// i.e. exactly the cases where "nothing usable is saved" is the truth. A present-but-
    /// partly-corrupt array returns the array with holes.
    ///
    /// CALLERS MUST DECIDE WHAT A HOLE MEANS, and the two answers are not interchangeable:
    /// for an unordered LIBRARY (patches, projects, presets) drop it with `.compactMap { $0 }`;
    /// for a POSITIONAL grid (`ClipStore`'s 8 slots, where index IS the slot) keep the `nil`
    /// in place — compacting there would shift every later clip into the wrong slot and break
    /// the count check, turning one corrupt clip into all eight lost.
    public func loadLossyArray<T: Decodable>(_ type: T.Type, name: String) -> [T?]? {
        guard let url = fileURL(name) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil } // absent = normal
        // Both failure modes (partly-corrupt, not-an-array) are logged inside
        // `decodeLossyArray` under this label — no second log line here.
        return decodeLossyArray(type, from: data, label: "AppGroupStore: \(name).json")
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

    /// TEST SEAM (`internal`, like every other seam in this repo — deliberately NOT behind
    /// `#if DEBUG`: the symbol is already unreachable outside the module, and the guard would
    /// only add a way for a Release `build-for-testing` to stop compiling the test file):
    /// write RAW bytes under `name`, bypassing `Encodable`.
    ///
    /// Needed because the failure this store now defends against — a file whose elements do
    /// not all decode — cannot be produced by `save`, which can only ever write well-formed
    /// JSON for the current schema. Without this, a test could only assert that valid data
    /// stays valid, which is precisely the unfalsifiable shape to avoid.
    /// Writes with the SAME options as `save` so the seam reproduces real on-disk conditions
    /// (`.completeFileProtection` included) rather than an easier variant of them.
    @discardableResult
    internal func saveRawForTests(_ data: Data, name: String) -> Bool {
        guard let url = fileURL(name) else { return false }
        return (try? data.write(to: url, options: [.atomic, .completeFileProtection])) != nil
    }

    /// Delete the file stored under `name` (no-op if absent).
    public func delete(name: String) {
        guard let url = fileURL(name) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
