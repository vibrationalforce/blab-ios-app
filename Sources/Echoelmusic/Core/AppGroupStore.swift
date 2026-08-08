// AppGroupStore.swift
// Echoel — tiny Codable-JSON persistence into the App Group container
// (`group.com.echoelmusic`), so user-authored data (synth patches, clips)
// survives relaunch and is reachable from the AUv3 extension. Falls back to the
// app's Application Support directory when the App Group is unavailable (e.g.
// SwiftPM unit tests, Linux CI), so callers never have to special-case it.
//
// Pure Foundation, cross-platform. An ABSENT file stays silent — that is the ordinary
// "nothing saved yet" case. Everything that is actually a DATA-LOSS signal is logged via
// the `#if canImport(os)`-guarded EchoelLogger (cross-platform-safe — Linux degrades to a
// no-op): a present-but-undecodable read, and — since #514 — every failed write.
//
// ⛔ This paragraph used to read "write failures surface as false so callers decide how
// loud to be". That described an intention, not the code: measured across `Sources/`,
// 12 call sites take that `Bool` and ZERO look at it. The sentence made a silence that
// nobody had chosen look like a decision somebody had made — the most expensive kind of
// wrong comment in this repo, because it cannot be falsified by re-measuring a number.
// The `Bool` is unchanged and a caller may still escalate; the store no longer depends
// on one doing so.

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
    /// the shared `decodeLossyArray` directly; `AutomationState` (`AutomationPlayer`) got its
    /// own element-tolerant + field-tolerant decoder in #170.
    ///
    /// Two of the originally-listed sites were CLOSED BY REACHABILITY, not by a decoder, and
    /// the distinction is the point — writing a defensive decoder for a path nothing can
    /// write is the compile-time-vs-runtime confusion this repo keeps paying for:
    /// `Arrangement.sections` (`ArrangementStore` is instantiated and injected but has ZERO
    /// readers and ZERO writers since `ArrangementView` went with #121 Slice 4; it retires in
    /// Slice 5 — note its `init` DOES still read `song.json` every launch, so "zero readers"
    /// is true of the API, not of the file; the safety argument is the missing WRITER) and
    /// `[BioSessionSummary]` (`SessionRecorder`'s only consumer is the deliberately doorless
    /// `MeditationView`, so nothing calls `start`/`stop` → `save()` never runs; a naive grep
    /// for `recorder.start` also hits `RecordController` and `FloatingVisualWindow`, but
    /// those are a DIFFERENT recorder type each — do not read them as live callers and
    /// revert this). Neither can lose data today because neither is ever rewritten. If either surface
    /// is ever re-doored, its decoder must be hardened IN THE SAME SLICE — that is the moment
    /// the wipe becomes possible again, and a re-door is exactly when nobody is looking here.
    /// Do not read this doc as "persistence is handled".
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
    ///
    /// ⛔ #514 — A FAILED WRITE USED TO BE COMPLETELY SILENT, while a failed READ has been
    /// logged since the store existed. The header above states the intended design —
    /// *"write failures surface as false so callers decide how loud to be"* — and the other
    /// half of that contract was never built: MEASURED across `Sources/`, there are **12**
    /// `store.save(…)` call sites and **ZERO** inspect the `Bool`. Ten rely on
    /// `@discardableResult`, two write `_ =` explicitly. So the delegation was to nobody.
    ///
    /// ⭐ WHY THAT IS WORSE THAN THE READ CASE, not merely symmetrical. A failed read falls
    /// back to an empty document, which the user SEES. A failed write leaves the previous
    /// file intact and the in-memory list already updated — the library looks correct for
    /// the rest of the session and the loss only appears on the next launch, by which time
    /// nothing connects it to the save. The read path's own reason applies with more force:
    /// "without telemetry a user losing their whole song produces zero signal".
    ///
    /// ⚠️ LOGGING DOES NOT REPLACE THE CONTRACT — the `Bool` is unchanged and a caller may
    /// still escalate. This adds a telemetry FLOOR under a promise nobody kept; it does not
    /// decide how loud the UI should be, which is a founder-surface question (#515).
    ///
    /// ⭐ THE ENCODE BRANCH IS THE ONE THAT CHANGED SHAPE, and that is the substantive half.
    /// It was `try? encoder.encode(value)`, which THROWS THE ERROR AWAY — so even a caller
    /// who did check the `Bool` could not have told "the disk is full" from "a NaN got into
    /// your song". `JSONEncoder`'s default `nonConformingFloatEncodingStrategy` is `.throw`
    /// (#512), and `Project` carries `bpm`, `a4Hz`, a whole `SynthPatch` and every `Note`
    /// through exactly this encoder. #512 closed that hole for the ONE payload that crosses
    /// the network; here the same class costs a saved song instead of a stream, and the
    /// error's `codingPath` names the field — which is the whole reason to keep it.
    ///
    /// ⚠️ THE URL BRANCH CANNOT FIRE TODAY, said plainly rather than implied by a log line
    /// that will never print: `directory()` is declared `-> URL?` but every path assigns a
    /// non-optional `base` (App Group → Application Support → `temporaryDirectory`) and
    /// returns it, so `fileURL` is never `nil`. The branch is kept because the signature is
    /// Optional and a later change could make it real; it is logged for the same reason.
    @discardableResult
    public func save<T: Encodable>(_ value: T, name: String) -> Bool {
        guard let url = fileURL(name) else {
            log.log(.error, category: .system,
                    "AppGroupStore: cannot resolve a container URL for \(name).json — not saved")
            return false
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            log.log(.error, category: .system,
                    "AppGroupStore: \(name).json failed to ENCODE as \(T.self) — \(error)")
            return false
        }
        do {
            // .completeFileProtection — the App Group container is shared with the
            // AUv3/widget/watch processes; encrypt at rest so session/bio/state
            // files are unreadable while the device is locked.
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            log.log(.error, category: .system,
                    "AppGroupStore: \(name).json failed to WRITE — \(error)")
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
