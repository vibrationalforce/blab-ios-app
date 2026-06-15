// LoopCutter.swift
// Echoel — cut the one-bar generated material into a loop/stem of N bars
// (2 · 4 · 8 · 16 · 32) so it drops straight into a DAW arrangement. Pure value
// transforms on the drum grid ([[Bool]]) and the melody ([Note]) — no audio, no
// engine — so they run before the existing MIDIFileExporter and are fully tested.
//
// The sequencer grid is 16 steps == 1 bar (PatternEngine.stepCount), so a loop of
// `bars` bars is `bars * 16` steps.

import Foundation

/// Loop/stem length in bars, for cutting an export.
public enum LoopBarLength: Int, CaseIterable, Identifiable, Sendable {
    case one = 1, two = 2, four = 4, eight = 8, sixteen = 16, thirtyTwo = 32
    public var id: Int { rawValue }
    public var label: String { rawValue == 1 ? "1 bar" : "\(rawValue) bars" }
    /// Compact label for a segmented control (Takt count).
    public var shortLabel: String { "\(rawValue)" }
}

public enum LoopCutter {

    /// Steps per bar — must match PatternEngine.stepCount / BioComposer.stepCount.
    public static let stepsPerBar = 16

    /// Tile (repeat) a one-bar drum grid to exactly `bars` bars. Each track's 16
    /// source cells repeat across `bars * 16` cells. Works for both steps and
    /// accents grids. Empty/short rows are padded with `false`.
    public static func tile(grid: [[Bool]], bars: Int) -> [[Bool]] {
        let outLength = max(0, bars) * stepsPerBar
        return grid.map { row in
            guard !row.isEmpty else { return Array(repeating: false, count: outLength) }
            return (0..<outLength).map { row[$0 % row.count] }
        }
    }

    /// Repeat the melody across `bars` bars. A source pattern of `sourceBars`
    /// bars is tiled `bars / sourceBars` times, each copy offset by a whole
    /// number of bars. Notes are clipped so none crosses the loop's end, and each
    /// copy gets a fresh id. `sourceBars` defaults to 1 (the generator's bar).
    public static func tile(notes: [Note], bars: Int, sourceBars: Int = 1) -> [Note] {
        let src = max(1, sourceBars)
        let loopSteps = max(0, bars) * stepsPerBar
        let sourceSteps = src * stepsPerBar
        guard loopSteps > 0, sourceSteps > 0 else { return [] }

        let repeats = max(1, loopSteps / sourceSteps)
        var out: [Note] = []
        out.reserveCapacity(notes.count * repeats)

        for k in 0..<repeats {
            let offset = k * sourceSteps
            for note in notes {
                let start = note.startStep + offset
                guard start < loopSteps else { continue }
                // Clip the length so the note never crosses the loop boundary.
                let maxLen = loopSteps - start
                let length = min(note.lengthSteps, maxLen)
                out.append(Note(pitch: note.pitch, startStep: start,
                                lengthSteps: length, velocity: note.velocity))
            }
        }
        return out
    }
}
