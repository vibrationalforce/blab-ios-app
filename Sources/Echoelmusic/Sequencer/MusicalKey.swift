// MusicalKey.swift
// Echoel — the musical key/scale model behind "set your own key (Tonart)" and the
// bio-generative composer. The composer only emits in-scale notes so heartbeat-
// driven melodies sound musical, not random. Pure value types (Codable, no audio,
// no SwiftUI) so the quantization + degree math is fully unit-tested.

import Foundation

/// A diatonic / common scale as semitone offsets from the root (within an octave).
public enum Scale: String, Codable, CaseIterable, Sendable {
    case major
    case minor              // natural minor (Aeolian)
    case dorian
    case phrygian
    case lydian
    case mixolydian
    case pentatonicMajor
    case pentatonicMinor
    case harmonicMinor
    case chromatic
    // Church mode completing the set (Ionian=major, Aeolian=minor already above).
    case locrian
    // Jazz — melodic minor + its most-used modes, and a bebop scale.
    case melodicMinor
    case lydianDominant
    case altered
    case bebopDominant
    // Blues — the two hexatonic blues scales.
    case bluesMinor
    case bluesMajor
    // Symmetric — dreamlike / cinematic tension.
    case wholeTone
    case diminishedWholeHalf
    case diminishedHalfWhole
    // World / exotic — flamenco/metal, Gypsy, Byzantine/Arabic colour.
    case phrygianDominant   // 5th mode of harmonic minor — Spanish/flamenco/metal
    case harmonicMajor      // major with ♭6
    case hungarianMinor     // Gypsy minor (♯4 over harmonic minor)
    case doubleHarmonic     // Byzantine / Arabic (Maqam Hijaz-kar)
    // Tonarten expansion (founder 2026-07-09, deep-research pass): every addition
    // below is a STANDARD, uncontested catalog definition (Neapolitan/klezmer/
    // Verdi/Scriabin literature, Japanese koto tunings, suspended pentatonics).
    // Deliberately NOT added: Ableton-proprietary "Bulgarian"/"Polymode" scale
    // names — no authoritative interval definition exists outside Live's binary,
    // and we do not ship guessed music theory (science-first rule).
    case neapolitanMinor    // harmonic minor with ♭2 — dark classical colour
    case neapolitanMajor    // major with ♭2+♭3 shape (melodic minor ♭2)
    case romanianMinor      // Ukrainian Dorian / Misheberak — Dorian ♯4, klezmer
    case persian            // ♭2 ♯3 ♭5 colour — Persian classical flavour
    case hirajoshi          // Japanese koto pentatonic (dark)
    case iwato              // Japanese koto pentatonic (floating/dissonant)
    case insen              // Japanese pentatonic (In scale family)
    case yo                 // Japanese folk pentatonic (bright, no semitones)
    case inSakura           // Japanese In / Sakura tuning
    case egyptian           // suspended pentatonic (no 3rd — open, ancient)
    case pelog              // Balinese pelog selisir, 12-TET approximation
    case enigmatic          // Verdi's scala enigmatica
    case prometheus         // Scriabin's mystic chord as a scale
    case augmented          // symmetric hexatonic (aug triads interleaved)
    case tritone            // symmetric two-triad hexatonic (Petrushka colour)
    case hungarianMajor     // ♯2 over Lydian dominant — Bartók/folk colour
    case bebopMajor         // major + ♭6 passing tone (8 notes)
    case majorLocrian       // major top / Locrian bottom — suspenseful
    // Gap-close vs. the Ableton Live 12 scale list (founder screenshots
    // 2026-07-12): the remaining entries there that have STANDARD catalog
    // definitions. Messiaen modes are mathematically defined (modes of limited
    // transposition; mode 1 = wholeTone, mode 2 = diminishedHalfWhole already
    // above). Still deliberately NOT added: "Pelog Tembung" — like the other
    // Ableton-proprietary approximations, no authoritative 12-TET definition
    // exists outside Live's binary (gamelan pelog is not 12-TET; our `pelog`
    // is the one selisir approximation the literature agrees on).
    case lydianAugmented    // 3rd mode of melodic minor — ♯4 ♯5 dream colour
    case spanishEightTone   // Phrygian + both 3rds — flamenco 8-tone
    case kumoi              // Japanese koto pentatonic (kumoijoshi, bright-dark)
    case messiaen3          // repeating 2-1-1 — 9 notes, augmented shimmer
    case messiaen4          // repeating 1-1-3-1 — 8 notes
    case messiaen5          // repeating 1-4-1 — 6 notes, stark
    case messiaen6          // repeating 2-2-1-1 — 8 notes
    case messiaen7          // repeating 1-1-1-2-1 — 10 notes, densest mode
    // Indian classical (#232 J). Six Japanese pentatonics, the Maqām family and a
    // Balinese approximation were already here; there was not ONE named Indian entry
    // — the single most conspicuous hole in a list of fifty.
    //
    // Seven of the ten Hindustani thāts were in fact already reachable, but only under
    // a Western name: Bilāval = major, Khamāj = mixolydian, Kāfī = dorian, Āsāvarī =
    // minor, Bhairavī = phrygian, Bhairav = doubleHarmonic, Kalyāṇ = lydian. Adding
    // aliases for those would put duplicate pitch sets in one picker, so what follows
    // is only what is genuinely ABSENT: the three remaining thāts, plus four rāgas whose
    // sets no existing entry produces. Checked against all fifty prior sets — no
    // collisions, and `MusicalKeyTests` asserts displayName/shortTag stay unique.
    //
    // ⚠️ THE HONEST LIMIT, and it is the same one the `pelog` note above states for
    // gamelan: a rāga IS NOT a pitch-class set. Ārohaṇa/avarohaṇa (the ascent and
    // descent differ), vādī/samvādī emphasis, characteristic phrases and time-of-day
    // convention are the rāga; and Hindustani śruti intonation is not 12-TET, so even
    // the pitches are an approximation. What this engine offers is the scale material,
    // named after the tradition it comes from — which is worth more than the silence it
    // replaces, but is not the thing itself. Do not let a later doc claim otherwise.
    //
    // ⚠️ AND THIS SLICE MAKES #232 F BIGGER, NOT SMALLER: these names are spelled in
    // Western notation, so Malkauns will label its notes "D♯", never "ga". Seven more
    // entries now sit on the wrong side of that gap.
    case marwa              // Mārvā thāt — Lydian ♭2 (the rāga itself drops Pa)
    case purvi              // Pūrvī thāt — ♭2 ♯4 ♭6, evening colour
    case todi               // Toḍī thāt — ♭2 ♭3 ♯4 ♭6
    case malkauns           // Rāga Mālkauns — pentatonic, no Re and no Pa
    case charukeshi         // Cārukeśī (Carnatic mēḷa 26) — major top, ♭6 ♭7 below
    case hamsadhwani        // Haṃsadhvani — pentatonic, no Ma and no Dha
    case shanmukhapriya     // Ṣaṇmukhapriyā (mēḷa 56) — ♭3 ♯4 ♭6 ♭7

    /// Ascending semitone offsets from the root, one octave.
    public var intervals: [Int] {
        switch self {
        case .major:           return [0, 2, 4, 5, 7, 9, 11]
        case .minor:           return [0, 2, 3, 5, 7, 8, 10]
        case .dorian:          return [0, 2, 3, 5, 7, 9, 10]
        case .phrygian:        return [0, 1, 3, 5, 7, 8, 10]
        case .lydian:          return [0, 2, 4, 6, 7, 9, 11]
        case .mixolydian:      return [0, 2, 4, 5, 7, 9, 10]
        case .pentatonicMajor: return [0, 2, 4, 7, 9]
        case .pentatonicMinor: return [0, 3, 5, 7, 10]
        case .harmonicMinor:   return [0, 2, 3, 5, 7, 8, 11]
        case .chromatic:       return [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
        case .locrian:             return [0, 1, 3, 5, 6, 8, 10]
        case .melodicMinor:        return [0, 2, 3, 5, 7, 9, 11]
        case .lydianDominant:      return [0, 2, 4, 6, 7, 9, 10]
        case .altered:             return [0, 1, 3, 4, 6, 8, 10]
        case .bebopDominant:       return [0, 2, 4, 5, 7, 9, 10, 11]
        case .bluesMinor:          return [0, 3, 5, 6, 7, 10]
        case .bluesMajor:          return [0, 2, 3, 4, 7, 9]
        case .wholeTone:           return [0, 2, 4, 6, 8, 10]
        case .diminishedWholeHalf: return [0, 2, 3, 5, 6, 8, 9, 11]
        case .diminishedHalfWhole: return [0, 1, 3, 4, 6, 7, 9, 10]
        case .phrygianDominant:    return [0, 1, 4, 5, 7, 8, 10]
        case .harmonicMajor:       return [0, 2, 4, 5, 7, 8, 11]
        case .hungarianMinor:      return [0, 2, 3, 6, 7, 8, 11]
        case .doubleHarmonic:      return [0, 1, 4, 5, 7, 8, 11]
        case .neapolitanMinor:     return [0, 1, 3, 5, 7, 8, 11]
        case .neapolitanMajor:     return [0, 1, 3, 5, 7, 9, 11]
        case .romanianMinor:       return [0, 2, 3, 6, 7, 9, 10]
        case .persian:             return [0, 1, 4, 5, 6, 8, 11]
        case .hirajoshi:           return [0, 2, 3, 7, 8]
        case .iwato:               return [0, 1, 5, 6, 10]
        case .insen:               return [0, 1, 5, 7, 10]
        case .yo:                  return [0, 2, 5, 7, 9]
        case .inSakura:            return [0, 1, 5, 7, 8]
        case .egyptian:            return [0, 2, 5, 7, 10]
        case .pelog:               return [0, 1, 3, 7, 8]
        case .enigmatic:           return [0, 1, 4, 6, 8, 10, 11]
        case .prometheus:          return [0, 2, 4, 6, 9, 10]
        case .augmented:           return [0, 3, 4, 7, 8, 11]
        case .tritone:             return [0, 1, 4, 6, 7, 10]
        case .hungarianMajor:      return [0, 3, 4, 6, 7, 9, 10]
        case .bebopMajor:          return [0, 2, 4, 5, 7, 8, 9, 11]
        case .majorLocrian:        return [0, 2, 4, 5, 6, 8, 10]
        case .lydianAugmented:     return [0, 2, 4, 6, 8, 9, 11]
        case .spanishEightTone:    return [0, 1, 3, 4, 5, 6, 8, 10]
        case .kumoi:               return [0, 2, 3, 7, 9]
        case .messiaen3:           return [0, 2, 3, 4, 6, 7, 8, 10, 11]
        case .messiaen4:           return [0, 1, 2, 5, 6, 7, 8, 11]
        case .messiaen5:           return [0, 1, 5, 6, 7, 11]
        case .messiaen6:           return [0, 2, 4, 5, 6, 8, 10, 11]
        case .messiaen7:           return [0, 1, 2, 3, 5, 6, 7, 8, 9, 11]
        // Sa is the root in every one of these; the comment gives the swaras so the
        // set can be checked against a rāga reference without translating twice.
        case .marwa:               return [0, 1, 4, 6, 7, 9, 11]   // S r G M♯ P D N
        case .purvi:               return [0, 1, 4, 6, 7, 8, 11]   // S r G M♯ P d N
        case .todi:                return [0, 1, 3, 6, 7, 8, 11]   // S r g M♯ P d N
        case .malkauns:            return [0, 3, 5, 8, 10]         // S g m d n
        case .charukeshi:          return [0, 2, 4, 5, 7, 8, 10]   // S R G m P d n
        case .hamsadhwani:         return [0, 2, 4, 7, 11]         // S R G P N
        case .shanmukhapriya:      return [0, 2, 3, 6, 7, 8, 10]   // S R g M♯ P d n
        }
    }

    /// True when the tonic triad is minor (the scale has a minor third and no major
    /// third) — used to tag the exported MIDI key-signature's major/minor byte so a DAW
    /// shows the right key. Ambiguous scales (chromatic, whole-tone: both thirds) report major.
    public var isMinorTonality: Bool { intervals.contains(3) && !intervals.contains(4) }

    /// Human label.
    public var displayName: String {
        switch self {
        case .major:           return "Major"
        case .minor:           return "Minor"
        case .dorian:          return "Dorian"
        case .phrygian:        return "Phrygian"
        case .lydian:          return "Lydian"
        case .mixolydian:      return "Mixolydian"
        case .pentatonicMajor: return "Pentatonic Major"
        case .pentatonicMinor: return "Pentatonic Minor"
        case .harmonicMinor:   return "Harmonic Minor"
        case .chromatic:       return "Chromatic"
        case .locrian:             return "Locrian"
        case .melodicMinor:        return "Melodic Minor"
        case .lydianDominant:      return "Lydian Dominant"
        case .altered:             return "Altered"
        case .bebopDominant:       return "Bebop Dominant"
        case .bluesMinor:          return "Blues Minor"
        case .bluesMajor:          return "Blues Major"
        case .wholeTone:           return "Whole Tone"
        case .diminishedWholeHalf: return "Diminished (W–H)"
        case .diminishedHalfWhole: return "Diminished (H–W)"
        case .phrygianDominant:    return "Phrygian Dominant"
        case .harmonicMajor:       return "Harmonic Major"
        case .hungarianMinor:      return "Hungarian Minor"
        case .doubleHarmonic:      return "Double Harmonic"
        case .neapolitanMinor:     return "Neapolitan Minor"
        case .neapolitanMajor:     return "Neapolitan Major"
        case .romanianMinor:       return "Romanian Minor"
        case .persian:             return "Persian"
        case .hirajoshi:           return "Hirajoshi"
        case .iwato:               return "Iwato"
        case .insen:               return "Insen"
        case .yo:                  return "Yo"
        case .inSakura:            return "In (Sakura)"
        case .egyptian:            return "Egyptian"
        case .pelog:               return "Pelog"
        case .enigmatic:           return "Enigmatic"
        case .prometheus:          return "Prometheus"
        case .augmented:           return "Augmented"
        case .tritone:             return "Tritone"
        case .hungarianMajor:      return "Hungarian Major"
        case .bebopMajor:          return "Bebop Major"
        case .majorLocrian:        return "Major Locrian"
        case .lydianAugmented:     return "Lydian Augmented"
        case .spanishEightTone:    return "Spanish 8-Tone"
        case .kumoi:               return "Kumoi"
        case .messiaen3:           return "Messiaen 3"
        case .messiaen4:           return "Messiaen 4"
        case .messiaen5:           return "Messiaen 5"
        case .messiaen6:           return "Messiaen 6"
        case .messiaen7:           return "Messiaen 7"
        // Bare names, no "Rāga …" prefix and no parenthetical: that is exactly how
        // Hirajoshi, Iwato, Insen, Yo, Kumoi and Pelog already stand in this list.
        // Decorating only the Indian entries would single them out in the one place
        // this slice exists to stop doing that.
        case .marwa:               return "Marwa"
        case .purvi:               return "Purvi"
        case .todi:                return "Todi"
        case .malkauns:            return "Malkauns"
        case .charukeshi:          return "Charukeshi"
        case .hamsadhwani:         return "Hamsadhwani"
        case .shanmukhapriya:      return "Shanmukhapriya"
        }
    }

    /// Short, filename-safe scale tag for session names, e.g. "m", "maj", "dor".
    public var shortTag: String {
        switch self {
        case .major:           return "maj"
        case .minor:           return "m"
        case .dorian:          return "dor"
        case .phrygian:        return "phr"
        case .lydian:          return "lyd"
        case .mixolydian:      return "mix"
        case .pentatonicMajor: return "pentM"
        case .pentatonicMinor: return "pentm"
        case .harmonicMinor:   return "harm"
        case .chromatic:       return "chr"
        case .locrian:             return "loc"
        case .melodicMinor:        return "melm"
        case .lydianDominant:      return "lydom"
        case .altered:             return "alt"
        case .bebopDominant:       return "bebop"
        case .bluesMinor:          return "blsm"
        case .bluesMajor:          return "blsM"
        case .wholeTone:           return "whole"
        case .diminishedWholeHalf: return "dimWH"
        case .diminishedHalfWhole: return "dimHW"
        case .phrygianDominant:    return "phrdom"
        case .harmonicMajor:       return "harmM"
        case .hungarianMinor:      return "hung"
        case .doubleHarmonic:      return "dblharm"
        case .neapolitanMinor:     return "neapm"
        case .neapolitanMajor:     return "neapM"
        case .romanianMinor:       return "rom"
        case .persian:             return "prs"
        case .hirajoshi:           return "hira"
        case .iwato:               return "iwato"
        case .insen:               return "insen"
        case .yo:                  return "yo"
        case .inSakura:            return "sakura"
        case .egyptian:            return "egy"
        case .pelog:               return "pelog"
        case .enigmatic:           return "enig"
        case .prometheus:          return "prom"
        case .augmented:           return "aug"
        case .tritone:             return "tri"
        case .hungarianMajor:      return "hungM"
        case .bebopMajor:          return "bebM"
        case .majorLocrian:        return "majloc"
        case .lydianAugmented:     return "lydaug"
        case .spanishEightTone:    return "span8"
        case .kumoi:               return "kumoi"
        case .messiaen3:           return "mes3"
        case .messiaen4:           return "mes4"
        case .messiaen5:           return "mes5"
        case .messiaen6:           return "mes6"
        case .messiaen7:           return "mes7"
        // ASCII only, no diacritics: this tag is stamped into share-sheet FILENAMES.
        // "Cārukeśī" would round-trip through a file system as anything from a
        // decomposed NFD form to a mangled one, and two devices would stop agreeing
        // on the name of the same take — the same reason `shortName` folds ♯ to "s".
        case .marwa:               return "marwa"
        case .purvi:               return "purvi"
        case .todi:                return "todi"
        case .malkauns:            return "malk"
        case .charukeshi:          return "charu"
        case .hamsadhwani:         return "hamsa"
        case .shanmukhapriya:      return "shanmu"
        }
    }
}

/// A musical key: a root pitch-class (0 = C … 11 = B) plus a scale.
public struct MusicalKey: Codable, Equatable, Sendable {

    /// Pitch class of the tonic, 0…11 (C…B). Always normalized into range.
    public var root: Int
    public var scale: Scale

    public init(root: Int = 0, scale: Scale = .minor) {
        self.root = ((root % 12) + 12) % 12
        self.scale = scale
    }

    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// e.g. "C Minor", "C♯ Minor", "A Pentatonic Minor". Uses the typographic sharp
    /// (♯) so the spelled-out Tonart matches the key picker, which already renders ♯ —
    /// the canonical `noteNames` array stays ASCII "#" for `shortName`'s filename-safe id
    /// path (sharps fold to "s").
    ///
    /// English. This is the INTEROP spelling and the default; a DISPLAY caller passes a
    /// naming (see below). Both exist because they are different jobs, and conflating them
    /// is how a shared take stops matching its own filename.
    public var name: String { name(naming: .english) }

    /// The spelled-out key in the reader's own note-name system (#232 E).
    ///
    /// ⚠️ THE SPLIT IS `name` = DISPLAY, `shortName` = FILENAME — and I got it wrong once, in
    /// the commit that introduced `NoteNaming`: I wrote that `name` had to stay English
    /// because it "stamps session names". It does not. The stamped name and every stem go
    /// through `shortName` (`SessionContext`); `name` had exactly ONE caller in the app, the
    /// readable session-name preview riding at the end of the same chrome strip as the Key
    /// picker. So with German selected the picker said H and the line beside it said B —
    /// the inconsistency the naming setting exists to remove, two controls apart.
    ///
    /// ⚠️ AND THE SPLIT IS NOT CLEAN IN THE CODEBASE, so do not "tidy" it on the strength of
    /// this comment: `EchoelStudioView` and `LiveColaboView` both render `shortName` as
    /// user-facing text ("Bm", "Csm"). That is pre-existing and it means someone could
    /// reasonably conclude `shortName` is a display property and localise it. It is not, and
    /// doing so would break share filenames across devices. `Tests/CISmoke/NoteNamingTests`
    /// pins that with the German setting actually applied.
    public func name(naming: NoteNaming) -> String {
        "\(naming.name(pitchClass: root)) \(scale.displayName)"
    }

    /// Compact, filename-safe key tag, e.g. "Cm", "Csm" (C# minor), "Amaj",
    /// "Ador". Sharps render as "s" so the tag is safe in a share-sheet filename.
    public var shortName: String {
        let root = Self.noteNames[self.root].replacingOccurrences(of: "#", with: "s")
        return root + scale.shortTag
    }

    /// The pitch classes (0…11) that belong to this key.
    public var pitchClasses: [Int] {
        scale.intervals.map { ((root + $0) % 12 + 12) % 12 }
    }

    /// True if a MIDI note's pitch class is in the key.
    public func contains(_ midi: Int) -> Bool {
        pitchClasses.contains(((midi % 12) + 12) % 12)
    }

    /// Snap an arbitrary MIDI note to the nearest in-key note. Searches outward
    /// from the note; on a tie the lower note wins (deterministic).
    public func quantize(_ midi: Int) -> Int {
        if contains(midi) { return midi }
        for distance in 1...6 {
            if contains(midi - distance) { return midi - distance }
            if contains(midi + distance) { return midi + distance }
        }
        return midi   // chromatic always matches at distance 0; unreachable otherwise
    }

    /// The `index`-th scale degree (0-based) at the given octave, as a MIDI note.
    /// Indices past the scale length wrap up octaves; negative indices wrap down.
    /// `octave` follows the convention MIDI 60 = C4, so `degree(0, octave: 4)`
    /// with root C returns 60.
    public func degree(_ index: Int, octave: Int) -> Int {
        let n = scale.intervals.count
        let octaveShift = Int(floor(Double(index) / Double(n)))
        let step = index - octaveShift * n
        let base = (octave + 1) * 12 + root
        return base + scale.intervals[step] + 12 * octaveShift
    }

    /// Number of notes per octave in this scale.
    public var degreesPerOctave: Int { scale.intervals.count }
}
