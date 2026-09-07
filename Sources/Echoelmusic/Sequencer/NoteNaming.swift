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
    /// Sa Re Ga Ma Pa Dha Ni — **Hindustani sargam**.
    ///
    /// ⛔ NOT "the reading across Hindustani AND Carnatic practice", which is what this said
    /// first and is a Hindustani table wearing a pan-Indian label. The bare abbreviations
    /// S R G M P D N are read in both, but Carnatic is a different system, not a spelling
    /// variant: it writes **Ri**, not Re; it marks variants with numeric swarasthāna
    /// suffixes (R1/R2/R3, G1/G2/G3, M1/M2, D1/D2/D3, N1/N2/N3), not by case; and it has
    /// SIXTEEN names over twelve positions with deliberate overlap — pitch class 2 is Ri2
    /// *or* Ga1, 3 is Ri3 *or* Ga2, 9 is Dha2 *or* Ni1, 10 is Dha3 *or* Ni2 — decided by the
    /// mēḷa, not by the pitch class. A flat twelve-entry column structurally cannot express
    /// that, so do not "add Carnatic" as a fifth case here.
    ///
    /// This matters concretely and this repo already knew it: `MusicalKey.charukeshi` and
    /// `.shanmukhapriya` are Carnatic mēḷas 26 and 56, and a Carnatic musician reads them
    /// `S R2 G2 M2 P D1 N2` — never as this table's spelling. Two commits ago the reviewer
    /// made `Scale.todi` say "Todi (Hindustani)" for exactly this collision; smoothing it
    /// over here would have undone that lesson in the same week.
    ///
    /// Added because the app grew a shelf it could not spell. #232 J put seven Indian scales
    /// in the key picker — Mārvā, Toḍī, Mālkauns, Cārukeśī and three more — and the play
    /// surface then labelled every one of their notes "D♯". Offering the material of a
    /// tradition while refusing its alphabet is a half-measure, and it is precisely the
    /// gap #232 F names.
    ///
    /// ⚠️ AND IT IS SPELLED AGAINST A FIXED Sa = C, WHICH SARGAM IS NOT. Sa is the tonic —
    /// wherever the drone is set — and the syllables name degrees relative to it, exactly the
    /// movable/fixed distinction this file already reasons about for `.solfege` two cases up
    /// and then failed to carry across. So in the key of D the play surface labels the tonic
    /// cell "Re", and the Key picker offers a root called "Ga♭", which is not a thing a
    /// player chooses. That is the same shape as the German B/H bug that created this type.
    /// It ships this way knowingly and it is written down rather than implied: making it
    /// movable changes `name(pitchClass:)`'s contract and every call site, so it is its own
    /// slice, not a silent widening of this one.
    ///
    /// ⚠️ THIS DOES NOT CLOSE #232 F, only its Hindustani third. F is "non-Western tunings
    /// carry Western note names", and the maqām half needs something this type cannot
    /// express — but NOT for the reason I first wrote here. I claimed an Arabic degree name
    /// "belongs to a maqām, not to a pitch class"; that is backwards. Yakāh, ʿUshayrān,
    /// Rāst, Dūkāh, Sīkāh, Nawā, Kirdān … name absolute positions of the general gamut
    /// (ṣullam), independent of maqām — Maqām Rāst is named AFTER its tonic note, not the
    /// other way round. The conclusion survives for two different reasons: the gamut is
    /// 24 quarter-tones, so Sīkāh sits a quarter-tone below E and has no pitch class in this
    /// type at all; and the names are register-specific (Rāst and Kirdān are an octave apart
    /// and differently named), so it is not a pitch-CLASS table in the first place.
    case sargam

    /// Player-facing label for the setting row. Each names the pair that actually differs, so
    /// the choice is legible without knowing the word "solfège" or "Anglophone".
    public var displayName: String {
        switch self {
        case .english: return "A B C (International)"
        case .german:  return "A H C (Deutsch)"
        case .solfege: return "Do Re Mi (Solfège)"
        case .sargam:  return "Sa Re Ga (Sargam)"
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

    // ⚠️ SARGAM DEPARTS FROM THE PRINTED CONVENTION, deliberately, and the reason is the
    // reason this whole epic exists.
    //
    // HINDUSTANI notation distinguishes the altered degrees by CASE: komal (flattened) Re is
    // written "re", śuddha Re is "Re"; tīvra Ma is "Ma'". That is what a musician reads on
    // paper.
    //
    // THE LOAD-BEARING REASON NOT TO USE IT IS VISUAL: a case-only difference is a
    // single-channel cue. It is invisible at a glance in a menu row and it is destroyed
    // outright by any all-caps or small-caps styling. On the one control whose purpose is to
    // stop a player reading the wrong note, that is disqualifying on its own.
    //
    // ⛔ THE SCREEN-READER HALF OF THIS ARGUMENT WAS OVERSTATED and is corrected rather than
    // deleted. I wrote that a case-only distinction "survives no screen reader". VoiceOver
    // says "re" and "Re" identically only under its DEFAULT Speech → Capital Letters setting;
    // a user can switch that to Speak Cap or Change Pitch, and braille output preserves case
    // exactly. So the visual argument decides this, not the audible one. (And the departure
    // was CHOSEN, not forced: the Carnatic convention R1/R2/R3 is neither case-only nor
    // unspeakable — it is simply a different system, see the case doc.)
    //
    // Marking komal with ♭ and tīvra with ♯ keeps every distinction visible AND speakable.
    // ♯ is already used by all three other columns; ♭ appears in NO other column, so
    // `spokenName` had to grow an arm for it — the commit body of the same change says as
    // much, and an earlier draft of this comment claimed both marks were shared. They are not.
    //
    // Same shape as the German column keeping international sharps instead of "Cis/Dis":
    // follow the convention where it serves the reader, depart where it defeats them — and
    // write down which was done.
    //
    // Sa and Pa carry no accidental in EITHER system because they are the *achal*
    // (immovable) swaras — a table that produced "Sa♯" would mean the column had been filled
    // mechanically from a Western one. Not "the drone degrees": the drone follows from being
    // achal, and it is not always Sa+Pa — rāgas that drop Pa are tuned Sa+Ma, including
    // Mālkauns and Mārvā, both added by this same epic.
    private static let sargamNames = ["Sa", "Re♭", "Re", "Ga♭", "Ga", "Ma", "Ma♯",
                                      "Pa", "Dha♭", "Dha", "Ni♭", "Ni"]

    // ⭐ #1060 — THE FLAT COLUMNS, because a sharp-only table spells a flat key wrong.
    //
    // In F major the seventh degree is B♭, and a table that can only say "A♯" prints the
    // right PITCH under the wrong NAME on the one surface where the column IS the note. Same
    // in every flat key: E♭ major, B♭ major, G minor, D minor, C minor.
    //
    // ⚠️ ONLY THE ALTERED FIVE MOVE. C, D, E, F, G, A and the German B/H are identical in
    // both directions, so these arrays are the sharp ones with five entries respelled —
    // written out in full rather than derived, because a derivation would be a lookup table
    // in disguise and would hide which five they are.
    //
    // ⚠️ THE GERMAN COLUMN KEEPS ITS EXISTING SHAPE, which is the same product decision the
    // comment above records: international accidentals (D♭ not "Des"), German B/H at pitch
    // classes 10 and 11. Note that German's 10 is ALREADY the flat spelling — "B" in German
    // IS B♭ — so the German column changes in four places, not five.
    //
    // ⚠️ SARGAM HAS NO FLAT COLUMN AND MUST NOT GET ONE. It is not a Western sharp/flat
    // system: `Re♭` there is komal Re, a degree of the rāga, not an enharmonic choice about
    // how to spell a pitch. Respelling it "on the flat side" would be applying a foreign
    // grammar to it — the exact thing the sargam comment above says the table must not do.
    private static let englishFlatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭",
                                           "G", "A♭", "A", "B♭", "B"]
    private static let germanFlatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭",
                                          "G", "A♭", "A", "B", "H"]
    private static let solfegeFlatNames = ["Do", "Re♭", "Re", "Mi♭", "Mi", "Fa", "Sol♭",
                                           "Sol", "La♭", "La", "Si♭", "Si"]

    private var flatNames: [String] {
        switch self {
        case .english: return Self.englishFlatNames
        case .german:  return Self.germanFlatNames
        case .solfege: return Self.solfegeFlatNames
        case .sargam:  return Self.sargamNames   // its ♭ marks are degrees, not spellings
        }
    }

    private var names: [String] {
        switch self {
        case .english: return Self.englishNames
        case .german:  return Self.germanNames
        case .solfege: return Self.solfegeNames
        case .sargam:  return Self.sargamNames
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
    ///
    /// `preferFlats` picks the spelling side, and it DEFAULTS TO FALSE on purpose even though
    /// this repo distrusts defaulted arguments (#431: one that no call site writes never shows
    /// up in a diff). Three call sites write it — the key's own `displayName` and the play
    /// grid's two label paths, all of which hold a `MusicalKey`. The two that do not are the
    /// spectrum readout and the ROOT PICKER, and for the picker sharps are not a fallback but
    /// the correct answer: it lists all twelve pitch classes with no key chosen yet, so there
    /// is no signature to follow. The default is therefore the right answer at both sites
    /// rather than an unexamined leftover.
    public func name(pitchClass: Int, preferFlats: Bool = false) -> String {
        let folded = ((pitchClass % 12) + 12) % 12
        return (preferFlats ? flatNames : names)[folded]
    }

    /// The name as VoiceOver should SAY it: the same spelling, with the typographic
    /// accidentals expanded, because a screen reader announces "♯" and "♭" as nothing useful.
    ///
    /// Derived from `name(pitchClass:)` rather than kept as its own table, so a sighted and a
    /// blind user cannot end up hearing and seeing different systems — which is exactly what
    /// happened before this existed: the play surface's spoken root was its own hard-coded
    /// English array, ten lines from the labels, and it kept saying "B" for the pitch the
    /// labels had already started calling H.
    ///
    /// ⚠️ THE FLAT ARM IS NOT DECORATION. Until sargam arrived no column contained ♭, so a
    /// sharp-only expansion was complete. It stopped being complete the moment komal degrees
    /// existed — and the failure would have been silent and cruel in the specific way this
    /// epic exists to prevent: an Indian player using VoiceOver would hear "Re" for both Re♭
    /// and Re, i.e. the same name for two different pitches, on the control that sets the
    /// key.
    ///
    /// ⛔ THE GUARD THIS PARAGRAPH PROMISED DID NOT EXIST when it was written. It said a
    /// fifth column introducing a new mark would "fail there rather than on someone's
    /// device" — but the test only knew ♯ and ♭: it asserted their absence and then rebuilt
    /// the expectation with exactly those two replacements, so a column spelling `Ma'`, `B♮`
    /// or `E𝄫` passed every assertion silently. The test now also requires the spoken form
    /// to be plain ASCII letters and spaces, which catches ANY unexpanded mark. The claim is
    /// true now; it was a promise before.
    public func spokenName(pitchClass: Int, preferFlats: Bool = false) -> String {
        name(pitchClass: pitchClass, preferFlats: preferFlats)
            .replacingOccurrences(of: "♯", with: " sharp")
            .replacingOccurrences(of: "♭", with: " flat")
    }

    /// Decode a persisted raw value, falling back to `.english` for anything unrecognised —
    /// a value written by a future build, or a corrupted one. The app has to name notes
    /// somehow; failing to a working spelling is this repo's `decodeIfPresent` law applied to
    /// a raw-string preference.
    public init(stored raw: String?) {
        self = raw.flatMap(NoteNaming.init(rawValue:)) ?? .english
    }
}
