// MelodyBarEdit.swift
// Echoelmusic — Sequencer
//
// PURE bar-splice core for the clip-scoped MIDI editor (H11 of the clip-pro
// healing block, founder 2026-07-15: "Midi Clip und Audio Clip verhalten sich
// nicht wie von einer professionellen Software erwartet").
//
// The audited defect: the region's Edit door opened the app-wide SHARED piano
// roll (which the region player also clobbers at every region onset), so a
// clip's own notes were never edited. The fix edits a THROWAWAY roll loaded
// with ONE bar of the clip and splices that bar back — and because the roll is
// a single-bar instrument (foldToBar flattens multi-bar content), the splice
// is the multi-bar-safety gate: every note OUTSIDE the edited bar survives
// byte-identical, so a 4-bar clip can never be silently flattened to one bar.
//
// Sibling of RegionNoteWindow (same tick conventions: notes belong to the bar
// their START lies in; cross-bar sustains keep their full length — the roll's
// release mechanics handle them). Foundation-only, Linux-CI-tested.

import Foundation

public enum MelodyBarEdit {

    /// Bars a melody spans, by note extent (min 1; a note ENDING exactly on a
    /// bar line belongs to the bar before it).
    public static func barCount(of notes: [Note]) -> Int {
        let perBar = TimelineTime.ticksPerBar
        guard let maxEnd = notes.map(\.endTick).max(), maxEnd > 0 else { return 1 }
        return (maxEnd - 1) / perBar + 1
    }

    /// The notes STARTING in bar `bar`, rebased to bar-relative ticks — the
    /// editor's working set. Cross-bar sustains keep their full length.
    public static func slice(bar: Int, of notes: [Note]) -> [Note] {
        guard bar >= 0 else { return [] }
        let perBar = TimelineTime.ticksPerBar
        let lo = bar * perBar
        let hi = lo + perBar
        return notes.compactMap { n in
            guard n.startTick >= lo, n.startTick < hi else { return nil }
            var rebased = n
            rebased.startTick = n.startTick - lo
            return rebased
        }
    }

    /// Replace bar `bar` of `notes` with `edited` (bar-relative, the editor's
    /// output): every note starting OUTSIDE the bar is kept unchanged (the
    /// multi-bar-safety law — no silent flattening), the edited notes land at
    /// the bar's offset. An edited note whose start lies outside the bar
    /// window is dropped (the single-bar roll cannot author one; defensive).
    /// Result is ordered by (startTick, pitch) for deterministic persistence.
    public static func splice(bar: Int, edited: [Note], into notes: [Note]) -> [Note] {
        guard bar >= 0 else { return notes }
        let perBar = TimelineTime.ticksPerBar
        let lo = bar * perBar
        let hi = lo + perBar
        var out = notes.filter { !($0.startTick >= lo && $0.startTick < hi) }
        for n in edited {
            guard n.startTick >= 0, n.startTick < perBar else { continue }
            var placed = n
            placed.startTick = n.startTick + lo
            out.append(placed)
        }
        out.sort { ($0.startTick, $0.pitch) < ($1.startTick, $1.pitch) }
        return out
    }
}
