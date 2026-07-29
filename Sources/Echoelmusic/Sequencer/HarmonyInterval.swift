//
//  HarmonyInterval.swift
//  Echoelmusic — Sequencer (music theory)
//
//  THE ASK (founder 2026-07-29): *"Harmonizer mit 5th etc? Keine semitone Schritte sondern
//  sinnvolle harmonische."*
//
//  The harmonizer's two voices were two numeric fields in SEMITONES, −12…12, whole numbers.
//  That is 25 choices of which most are not harmony at all: ±1 and ±2 are a second, ±10 and
//  ±11 a seventh, ±6 the tritone. Held in PARALLEL under every note of a melody, those beat
//  rather than harmonise — they are the settings a musician reaches once, hears, and never
//  uses again. The fifteen below are the ones that work, and they say their own names.
//
//  ⚠️ WHAT THIS DELIBERATELY DOES *NOT* CLAIM, because the difference matters and the founder
//  may have meant the other thing. `EchoelHarmonizer` is an AUDIO effect: a delay-line pitch
//  shifter that multiplies the whole signal by one fixed ratio (`EchoelHarmonizer.ratio(for:)`).
//  It does not know which note is sounding, so it CANNOT be diatonic — a "third" cannot become
//  minor over a minor chord and major over a major one, the way a pitch-tracking harmonizer
//  (Eventide, Waves) does in scale mode. That would need pitch detection on the FX bus feeding
//  the shifter per note, which is a project, not a rename.
//
//  So the honest design is: name every interval, and spell out MAJOR or MINOR wherever the
//  interval has both forms, instead of hiding the choice behind a number. A fifth, a fourth and
//  an octave are the same in every mode and need no qualifier — which is exactly why "a fifth"
//  is the one a harmonizer is reached for first.
//
//  Pure value type, no import: the DSP keeps storing plain semitones (`Float`), so nothing about
//  the audio path or the saved format changes. That is not a coincidence — it is why this could
//  be one slice.
//

/// A musically useful parallel-harmony interval, in semitones.
///
/// The raw value IS the semitone shift, so `HarmonyInterval.fifthUp.rawValue == 7` and the
/// persisted `Float` needs no migration. Cases are declared in ascending order so a menu built
/// from `allCases` reads low → high without sorting.
public enum HarmonyInterval: Int, CaseIterable, Sendable, Identifiable, Hashable {
    case octaveDown = -12
    case majorSixthDown = -9
    case minorSixthDown = -8
    case fifthDown = -7
    case fourthDown = -5
    case majorThirdDown = -4
    case minorThirdDown = -3
    case unison = 0
    case minorThirdUp = 3
    case majorThirdUp = 4
    case fourthUp = 5
    case fifthUp = 7
    case minorSixthUp = 8
    case majorSixthUp = 9
    case octaveUp = 12

    public var id: Int { rawValue }

    /// The shift this interval asks the harmonizer for.
    public var semitones: Float { Float(rawValue) }

    /// Plain-language name. No abbreviations ("P5", "m3") and no theory notation — a performer
    /// picking a harmony voice on stage should not have to decode it.
    public var displayName: String {
        switch self {
        case .octaveDown:     return "Octave down"
        case .majorSixthDown: return "Major sixth down"
        case .minorSixthDown: return "Minor sixth down"
        case .fifthDown:      return "Fifth down"
        case .fourthDown:     return "Fourth down"
        case .majorThirdDown: return "Major third down"
        case .minorThirdDown: return "Minor third down"
        case .unison:         return "Unison — no shift"
        case .minorThirdUp:   return "Minor third up"
        case .majorThirdUp:   return "Major third up"
        case .fourthUp:       return "Fourth up"
        case .fifthUp:        return "Fifth up"
        case .minorSixthUp:   return "Minor sixth up"
        case .majorSixthUp:   return "Major sixth up"
        case .octaveUp:       return "Octave up"
        }
    }

    /// The curated interval for a stored semitone value, or `nil` when the stored value is not
    /// one of them.
    ///
    /// ⛔ IT RETURNS `nil` RATHER THAN SNAPPING, and that is the whole point of its existence.
    /// The old numeric field could save any whole number in −12…12, so a preset holding +6 (the
    /// tritone) or +10 exists in the wild. Snapping such a value to the nearest curated interval
    /// would re-voice a saved sound the moment its panel is merely OPENED — the #163/#170
    /// data-loss class, where nothing is lost and everything is quietly changed. The caller shows
    /// the stored value instead (see `choices(including:)`), and it changes only when the user
    /// picks something.
    public static func curated(forSemitones semitones: Float) -> HarmonyInterval? {
        // ⛔ BOTH halves of the guard are load-bearing, and the second is not obvious: `Int(Float)`
        // TRAPS on a non-finite value AND on any finite value outside `Int`'s range (1e30 is a
        // crash, not a large number). `FXPreset`'s decoder does not clamp this field, and this
        // function is called from a `Binding.get` on every body build — so a corrupt or tampered
        // preset would crash the app on merely OPENING the FX panel rather than displaying oddly.
        // 128 is the MIDI note span: nothing beyond it is a musical interval under any reading.
        guard semitones.isFinite, abs(semitones) <= 128 else { return nil }
        let whole = Int(semitones.rounded())
        // A fractional shift (a saved 4.5) is not "nearly a major third" — it is its own value.
        guard Float(whole) == semitones else { return nil }
        return HarmonyInterval(rawValue: whole)
    }

    /// The menu contents for a row currently holding `semitones`: every curated interval, and —
    /// only when the stored value is not one of them — the stored value itself, first.
    ///
    /// Same idiom as `FXModCarrier.choices(including:)`: a control must be able to display the
    /// state it is actually in, or it lies about it.
    public static func choices(includingSemitones semitones: Float) -> [HarmonyInterval?] {
        let base: [HarmonyInterval?] = allCases.map { $0 }
        return curated(forSemitones: semitones) == nil ? [nil] + base : base
    }

    /// Label for a stored value that is not a curated interval — shown so a legacy preset reads
    /// as what it is instead of silently appearing to be something else.
    ///
    /// Deliberately NOT localised and NOT `String(format:)`: it must round-trip visually with
    /// `EchoelValueField`, which shows raw decimals rather than locale-formatted numbers, and the
    /// two would otherwise disagree about the same number on the same screen.
    public static func customLabel(forSemitones semitones: Float) -> String {
        // Same two-part guard as `curated(forSemitones:)`, for the same reason: `Int(Float)` traps
        // on a finite out-of-range value too, and this runs while building the row.
        guard semitones.isFinite, abs(semitones) <= 128 else { return "— st" }
        let whole = Int(semitones.rounded())
        let body = Float(whole) == semitones ? "\(abs(whole))" : String(abs(semitones))
        let sign = semitones < 0 ? "−" : "+"
        return semitones == 0 ? "0 st" : "\(sign)\(body) st"
    }
}
