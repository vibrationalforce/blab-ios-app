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
//  ⚠️ SEQUENCER, NOT DSP — and the REASON matters, because the one I first wrote here was
//  retired three weeks ago. `DSP/` is no longer compiled in isolation: the AUv3 extension
//  target that mandated it was removed 2026-07-24, and `project.yml` says so in its own
//  words. `DSP/` stays Foundation-only by HYGIENE now, not by a build constraint. The
//  placement is still right and this file still may not move there — but do not repeat the
//  dead justification to defend it.
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
    /// C D E F G A **B(♭) H** — German-speaking and Central/Northern European practice.
    ///
    /// Deliberately not a country list: Sweden moved to B for pitch class 11 in music
    /// education in the 1990s and H only persists there in practice, so naming Sweden would
    /// be a claim a Swedish reader could falsify.
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

    // The twelve names, index = pitch class 0…11 (0 = C).
    //
    // Sharps use the typographic ♯ (U+266F), matching every surface that already renders it.
    //
    // ⚠️ THE GERMAN COLUMN IS DELIBERATELY MIXED, and the first version of this comment only
    // owned up to half of it. Pitch class 10 is the FLAT-derived "B" (not "Ais") and 11 is
    // "H" — that pair is the actual German convention and the one that causes misreadings.
    // Pitch classes 1/3/6/8 keep the INTERNATIONAL "C♯ D♯ F♯ G♯" rather than the German
    // "Cis Dis Fis Gis". That is a product decision, not the convention: the sharps read
    // fine to a German musician while "Cis" would read as a foreign spelling to everyone
    // else on the same picker, and the B/H pair is where the semitone error actually lived.
    //
    // `static let` and not a computed `var`: `name(pitchClass:)` is called inside the touch
    // surface's grid rebuild, degrees × 3 bands per pass, and a computed array would allocate
    // twelve fresh Strings every call. Layout path, never the audio thread — so this is a
    // waste rather than a rule break, which is exactly the kind that survives unnoticed.
    private static let englishNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯",
                                       "G", "G♯", "A", "A♯", "B"]
    private static let germanNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯",
                                      "G", "G♯", "A", "B", "H"]
    private static let solfegeNames = ["Do", "Do♯", "Re", "Re♯", "Mi", "Fa", "Fa♯",
                                       "Sol", "Sol♯", "La", "La♯", "Si"]

    private var names: [String] {
        switch self {
        case .english: return Self.englishNames
        case .german:  return Self.germanNames
        case .solfege: return Self.solfegeNames
        }
    }

    /// The name for `pitchClass`, which may be ANY integer.
    ///
    /// Callers pass MIDI note numbers and the results of interval arithmetic, not pre-clamped
    /// indices, so this folds rather than traps. The fold is the two-step `((x % 12) + 12) % 12`
    /// and not the naive `x % 12`: Swift's remainder keeps the sign of the dividend, so a
    /// single `%` returns −1 for −13 and the subscript crashes the chrome.
    ///
    /// `Int.min` is safe, but NOT for the reason an earlier version of this comment gave (it
    /// claimed something was being negated; nothing here is). `%` by a POSITIVE divisor cannot
    /// overflow — the only trapping remainder in Swift is `Int.min % -1` — and the intermediate
    /// `(x % 12) + 12` is bounded to 1…23, so the addition cannot overflow either.
    public func name(pitchClass: Int) -> String {
        let folded = ((pitchClass % 12) + 12) % 12
        return names[folded]
    }

    /// The name as VoiceOver should SAY it: the same spelling, with the typographic sharp
    /// expanded, because a screen reader announces "♯" as nothing useful.
    ///
    /// Derived from `name(pitchClass:)` rather than kept as a fourth table, so a sighted and a
    /// blind user cannot end up hearing and seeing different systems — which is exactly what
    /// happened before this existed: the play surface's spoken root was its own hard-coded
    /// English array, ten lines from the labels, and it kept saying "B" for the pitch the
    /// labels had already started calling H.
    public func spokenName(pitchClass: Int) -> String {
        name(pitchClass: pitchClass).replacingOccurrences(of: "♯", with: " sharp")
    }

    /// Decode a persisted raw value, falling back to `.english` for anything unrecognised —
    /// a value written by a future build, or a corrupted one. The app has to name notes
    /// somehow; failing to a working spelling is this repo's `decodeIfPresent` law applied to
    /// a raw-string preference.
    public init(stored raw: String?) {
        self = raw.flatMap(NoteNaming.init(rawValue:)) ?? .english
    }
}
