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

@MainActor
@Observable
public final class SessionContext {

    // MARK: - Persistence keys

    private enum Key {
        static let artist = "echoel.artistName"
        static let keyRoot = "echoel.keyRoot"
        static let keyScale = "echoel.keyScale"
        static let a4Hz = "echoel.a4Hz"
    }

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
        self.artistName = (defaults.string(forKey: Key.artist)).flatMap { $0.isEmpty ? nil : $0 } ?? "Echoel"
        self.keyRoot = defaults.object(forKey: Key.keyRoot) as? Int ?? 0
        let scaleRaw = defaults.string(forKey: Key.keyScale) ?? Scale.minor.rawValue
        self.keyScale = Scale(rawValue: scaleRaw) ?? .minor
        let storedA4 = defaults.object(forKey: Key.a4Hz) as? Double ?? 440.0
        self.a4Hz = storedA4 > 0 ? storedA4 : 440.0
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
