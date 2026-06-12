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
