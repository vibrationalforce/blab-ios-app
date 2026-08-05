// SessionContext.swift
// Echoel — the small, persisted source of truth for "whose session, in what key,
// at what tuning". BPM lives on the transport (BeatPlayer); this holds the three
// pieces that had no home: the artist name (username), the working key (Tonart)
// and the concert pitch (Kammerton, A4 in Hz). From these + the live tempo it
// builds the automatic session name that is stamped onto saved sessions and
// export filenames (see SessionNaming).
//
// Persisted in UserDefaults so the artist's identity, key and tuning survive a
// relaunch and are shared across the app.

import Foundation

/// The storage key strings, at FILE SCOPE and not nested in the class.
///
/// ⚠️ THE PLACEMENT IS THE POINT, not a style choice. `SessionContext` is `@MainActor`, and a
/// type nested inside it inherits that isolation — so `SoundReset`, which is a plain nonisolated
/// enum, could not read these through the class without either hopping actors or tripping the
/// "main actor-isolated static property cannot be accessed from outside the actor" error this
/// repo already has a row for in `CLAUDE.md`. Hoisting them out is the cheap fix; the exposure
/// below stays deliberately narrow.
private enum SessionStorageKey {
    static let artist = "echoel.artistName"
    static let keyRoot = "echoel.keyRoot"
    static let keyScale = "echoel.keyScale"
    static let a4Hz = "echoel.a4Hz"
}

@MainActor
@Observable
public final class SessionContext {

    // MARK: - Persistence keys

    private typealias Key = SessionStorageKey

    // MARK: - Factory values + the keys other code is allowed to know about

    /// The fresh-install values, named once. `init` reads through these rather than repeating
    /// the literals, so `resetMusicalIdentity()` cannot drift away from what a new install gets
    /// — the two used to be the same numbers written in two places, which is exactly how a
    /// "reset" quietly stops meaning "factory".
    ///
    /// `nonisolated` because `SoundReset` and its guard read them from outside the main actor;
    /// they are immutable value constants, so there is nothing for the isolation to protect.
    public nonisolated static let defaultKeyRoot = 0
    public nonisolated static let defaultKeyScale = Scale.minor
    public nonisolated static let defaultA4Hz = 440.0

    /// The two keys holding the working KEY. Exposed for `SoundReset`, which has to clear them:
    /// the alternative was a fifth site repeating `"echoel.keyRoot"` as a literal, and the
    /// storage names of this type are its own business.
    ///
    /// ⚠️ `artist` is deliberately NOT exposed. The artist name is the user's, not part of the
    /// instrument's sound, and nothing that clears settings should be able to reach it by
    /// accident. Widening this to "all keys" would make that reachable in one careless edit.
    public nonisolated static var keyStorageKeys: [String] {
        [SessionStorageKey.keyRoot, SessionStorageKey.keyScale]
    }

    /// The concert-pitch key, exposed for the same reason.
    public nonisolated static var a4StorageKey: String { SessionStorageKey.a4Hz }

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: - Fields

    /// Free-text username stamped on sessions/exports. Sanitised at naming time.
    public var artistName: String {
        didSet { defaults.set(artistName, forKey: Key.artist) }
    }

    /// Tonic pitch class 0…11 (C…B) of the working key.
    public var keyRoot: Int {
        didSet { defaults.set(keyRoot, forKey: Key.keyRoot) }
    }

    /// Scale of the working key.
    public var keyScale: Scale {
        didSet { defaults.set(keyScale.rawValue, forKey: Key.keyScale) }
    }

    /// Concert pitch (Kammerton): A4 in Hz. 440 standard; 432 a common variant.
    public var a4Hz: Double {
        didSet { defaults.set(a4Hz, forKey: Key.a4Hz) }
    }

    /// Optional locality token stamped after the date ("Hamburg"), set by the
    /// opt-in location namer (E2). TRANSIENT by design — resolved live per
    /// launch, never persisted (privacy: the only storage is the name string
    /// of a session the user chose to save). Empty = no place in the name.
    public var placeToken: String = ""

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Default artist = the brand mark "E~" (founder 2026-07-12: "Es soll am
        // Anfang ein E~"). Stored "Echoel" was OUR old default, not a user's
        // choice — migrate it to the mark; any other stored name is the user's.
        let storedArtist = defaults.string(forKey: Key.artist)
        switch storedArtist {
        case .none, .some(""), .some("Echoel"): self.artistName = "E~"
        case .some(let s):                      self.artistName = s
        }
        self.keyRoot = defaults.object(forKey: Key.keyRoot) as? Int ?? Self.defaultKeyRoot
        let scaleRaw = defaults.string(forKey: Key.keyScale) ?? Self.defaultKeyScale.rawValue
        self.keyScale = Scale(rawValue: scaleRaw) ?? Self.defaultKeyScale
        let storedA4 = defaults.object(forKey: Key.a4Hz) as? Double ?? Self.defaultA4Hz
        self.a4Hz = storedA4 > 0 ? storedA4 : Self.defaultA4Hz
    }

    // MARK: - Reset

    /// Put the working key and concert pitch back to their fresh-install values (#400).
    ///
    /// ⚠️ THIS EXISTS BECAUSE CLEARING THE KEYS IS NOT ENOUGH. These three are stored
    /// properties read once in `init`, so a live `SessionContext` goes on reporting the old A4
    /// after `SoundReset.clear` — and its own `didSet` would write that stale value straight
    /// back to `UserDefaults` on the next unrelated edit, undoing the reset. Assigning here is
    /// deliberately idempotent: each `didSet` re-persists the factory value, so the store ends
    /// up holding the same thing a fresh install would compute.
    ///
    /// `artistName` and `placeToken` are untouched on purpose — see `keyStorageKeys`.
    public func resetMusicalIdentity() {
        keyRoot = Self.defaultKeyRoot
        keyScale = Self.defaultKeyScale
        a4Hz = Self.defaultA4Hz
    }

    // MARK: - Derived

    /// The current working key (Tonart).
    public var key: MusicalKey {
        MusicalKey(root: keyRoot, scale: keyScale)
    }

    /// Adopt a generated key (e.g. from the composer) so the session name follows
    /// what was actually produced.
    public func adopt(key: MusicalKey) {
        keyRoot = key.root
        keyScale = key.scale
    }

    /// The automatic session name at a given tempo, e.g.
    /// `Echoel_2026-06-12_Cm_124bpm_A440` (with the opt-in place token:
    /// `Echoel_2026-07-10_Hamburg_Am_72bpm_A440`).
    public func sessionName(bpm: Double, date: Date = Date()) -> String {
        SessionNaming.stem(artist: artistName, date: date, key: key.shortName,
                           bpm: bpm, a4Hz: a4Hz, place: placeToken)
    }

    /// An export filename for a part, e.g.
    /// `Echoel_2026-06-12_Cm_124bpm_A440_Drums.mid`.
    public func fileName(part: String, bpm: Double, ext: String = "mid", date: Date = Date()) -> String {
        SessionNaming.fileName(artist: artistName, date: date, key: key.shortName,
                               bpm: bpm, a4Hz: a4Hz, part: part, ext: ext, place: placeToken)
    }
}
