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
        }
    }

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

    /// e.g. "C Minor", "A Pentatonic Minor".
    public var name: String {
        "\(Self.noteNames[root]) \(scale.displayName)"
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
