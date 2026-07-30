//
//  NoteNaming.swift
//  Echoelmusic
//
//  How the twelve pitch classes are SPELLED for a reader. Founder 2026-07-29:
//  "international für alle Kulturen und Hintergründe accessible" (#232 E).
//
//  This is not a translation table. It is a correctness fix: in German, Austrian and
//  Scandinavian notation the natural above A♯ is called **H**, and the name **B** is already
//  taken — it means B♭. Until this type existed, the Key picker in the permanent chrome
//  offered a German reader "B" for a pitch they would call H, on the one control that decides
//  the key of everything the app generates. Fixed-do solfège (Do Re Mi …) is the same table
//  again and is the normal reading in Romance-language countries and much of East Asia, so it
//  costs one more column and covers a large share of the remaining world.
//
//  ⚠️ DISPLAY ONLY. Two paths must never consult this type, and both are English by
//  construction rather than by discipline:
//    · `MusicalKey.shortName` stamps share-sheet FILENAMES. Two people with two settings have
//      to produce the same tag for the same key or a shared take stops matching itself. It
//      keeps its own ASCII table (sharps fold to "s") — see the note there.
//    · The MIDI export carries pitch NUMBERS. There is nothing to localise, and adding
//      anything would be a bug.
//  `Tests/CISmoke/NoteNamingTests.swift` pins both, in the blocking bundle.
//
//  ⚠️ SEQUENCER, NOT DSP. This file may not move into `DSP/`: that directory is compiled in
//  isolation and must not reach `Core`/`Sequencer` types.
//

import Foundation

/// The spelling system for pitch-class names, as a persisted user choice.
///
/// `RawValue` strings are STORED (`StudioDefaultKeys.noteNaming`). Renaming a case silently
/// resets every install that chose it — for a German user that means the wrong note names
/// come back without them touching anything. Add cases; do not rename them.
public enum NoteNaming: String, CaseIterable, Codable, Sendable {
    /// C D E F G A B — the international/Anglophone default and the app's interop spelling.
    case english
    /// C D E F G A **B(♭) H** — German, Austrian, Scandinavian, Czech, Polish, Hungarian.
    case german
    /// Do Re Mi Fa Sol La Si — FIXED-do. Romance languages, and standard across much of
    /// East Asia. Not movable-do: the syllable names the pitch, not the scale degree, which
    /// is why "Si" and not the English movable-do "Ti".
    case solfege

    /// Player-facing label for the setting row. Each names the pair that actually differs, so
    /// the choice is legible without knowing the word "solfège" or "Anglophone".
    public var displayName: String {
        switch self {
        case .english: return "A B C (International)"
        case .german:  return "A H C (Deutsch)"
        case .solfege: return "Do Re Mi (Solfège)"
        }
    }

    /// The twelve names, index = pitch class 0…11 (0 = C).
    ///
    /// Sharps use the typographic ♯ (U+266F), matching every surface that already renders it.
    /// The German column spells pitch class 10 as the FLAT "B" rather than "Ais", because that
    /// is what German charts print and it is the half of the convention that actually causes
    /// misreadings; pitch class 11 is "H".
    private var names: [String] {
        switch self {
        case .english:
            return ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        case .german:
            return ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "B", "H"]
        case .solfege:
            return ["Do", "Do♯", "Re", "Re♯", "Mi", "Fa", "Fa♯", "Sol", "Sol♯",
                    "La", "La♯", "Si"]
        }
    }

    /// The name for `pitchClass`, which may be ANY integer.
    ///
    /// Callers pass MIDI note numbers and the results of interval arithmetic, not pre-clamped
    /// indices, so this folds rather than traps. The fold is the two-step `((x % 12) + 12) % 12`
    /// and not the naive `x % 12`: Swift's remainder keeps the sign of the dividend, so a
    /// single `%` returns −1 for −13 and the subscript crashes the chrome. `Int.min` is handled
    /// by taking the remainder BEFORE negating anything — `-Int.min` would overflow.
    public func name(pitchClass: Int) -> String {
        let folded = ((pitchClass % 12) + 12) % 12
        return names[folded]
    }

    /// Decode a persisted raw value, falling back to `.english` for anything unrecognised —
    /// a value written by a future build, or a corrupted one. The app has to name notes
    /// somehow; failing to a working spelling is this repo's `decodeIfPresent` law applied to
    /// a raw-string preference.
    public init(stored raw: String?) {
        self = raw.flatMap(NoteNaming.init(rawValue:)) ?? .english
    }
}
