// TuningReference.swift
// Echoel — concert-pitch (Kammerton) reference and note-frequency math, to two
// decimals. The reference A4 is user-settable (432.00 · 440.00 · 442.00 …) so
// generated material and any tuning readout match a professional session. Pure
// Foundation value type — fully unit-tested.

import Foundation

/// The tuning reference: A4 (concert pitch / Kammerton) in Hz, two-decimal.
public struct TuningReference: Sendable, Equatable, Codable {
    /// A4 frequency in Hz. Standard is 440.00; common alternates 432.00 / 442.00.
    public var a4Hz: Double

    public init(a4Hz: Double = 440.00) {
        self.a4Hz = a4Hz
    }

    /// Common selectable references (Hz).
    public static let presets: [Double] = [432.00, 438.00, 440.00, 442.00, 444.00]

    /// Equal-tempered frequency of a MIDI note (A4 = MIDI 69).
    public func frequency(forMIDINote midi: Int) -> Double {
        a4Hz * pow(2.0, Double(midi - 69) / 12.0)
    }

    /// The frequency rounded to two decimals (display).
    public func frequencyRounded(forMIDINote midi: Int) -> Double {
        (frequency(forMIDINote: midi) * 100).rounded() / 100
    }

    private static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Scientific-pitch name for a MIDI note (MIDI 60 = C4).
    public static func noteName(forMIDINote midi: Int) -> String {
        let pc = ((midi % 12) + 12) % 12
        let octave = midi / 12 - 1
        return "\(names[pc])\(octave)"
    }
}

/// Two-decimal display formatting for production values (BPM, Hz, ms).
public enum Precision {
    /// e.g. 120.00, 75.50, 440.00 — always two decimals, no thousands grouping.
    public static func two(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Rounds a value to two decimals (for storage of user-entered BPM/pitch).
    public static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
