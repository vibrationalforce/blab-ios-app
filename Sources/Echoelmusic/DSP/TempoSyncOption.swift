// TempoSyncOption.swift
// Echoel — the "studio calculator in the effects": pick an LFO/delay rate as a
// musical note division (1/4, dotted 1/8, 1/8 triplet …) and get the resolved
// rate in Hz / seconds at the current BPM, via StudioCalculator. Pure value type
// (Foundation only) so it is fully unit-tested and reusable from the AUv3 target.

import Foundation

/// A tempo-synced rate choice: a note division + feel, resolved against a BPM.
public struct TempoSyncOption: Identifiable, Sendable, Equatable, Hashable {
    public let division: NoteDivision
    public let modifier: NoteModifier

    public init(_ division: NoteDivision, _ modifier: NoteModifier = .straight) {
        self.division = division
        self.modifier = modifier
    }

    public var id: String { "\(division.rawValue)-\(modifier.rawValue)" }

    /// Compact label: "1/4", "1/8·" (dotted), "1/8T" (triplet).
    public var label: String {
        switch modifier {
        case .straight: return division.label
        case .dotted:   return division.label + "·"
        case .triplet:  return division.label + "T"
        }
    }

    /// Resolved LFO/repeat rate in Hz at `bpm`.
    public func hertz(bpm: Double) -> Double {
        StudioCalculator(bpm: bpm).hertz(division, modifier)
    }

    /// Resolved time in seconds at `bpm` (for delay time).
    public func seconds(bpm: Double) -> Double {
        StudioCalculator(bpm: bpm).seconds(division, modifier)
    }

    /// Resolved time in milliseconds at `bpm`.
    public func milliseconds(bpm: Double) -> Double {
        StudioCalculator(bpm: bpm).milliseconds(division, modifier)
    }

    /// The Hz rate clamped into an LFO's valid range (so a fast division at a
    /// high BPM never writes an out-of-range rate to the audio thread).
    public func clampedRate(bpm: Double, in range: ClosedRange<Float>) -> Float {
        Float(min(max(hertz(bpm: bpm), Double(range.lowerBound)), Double(range.upperBound)))
    }

    /// The seconds value clamped into a delay's valid time window.
    public func clampedSeconds(bpm: Double, in range: ClosedRange<Float>) -> Float {
        Float(min(max(seconds(bpm: bpm), Double(range.lowerBound)), Double(range.upperBound)))
    }

    /// Curated list for effect menus: 1/1 … 1/16, straight + dotted + triplet.
    public static let common: [TempoSyncOption] = {
        let divisions: [NoteDivision] = [.whole, .half, .quarter, .eighth, .sixteenth]
        var out: [TempoSyncOption] = []
        for d in divisions {
            out.append(TempoSyncOption(d, .straight))
            out.append(TempoSyncOption(d, .dotted))
            out.append(TempoSyncOption(d, .triplet))
        }
        return out
    }()
}
