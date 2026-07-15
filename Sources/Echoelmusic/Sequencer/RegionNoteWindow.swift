// RegionNoteWindow.swift
// Echoelmusic — Sequencer
//
// PURE windowing core for MIDI regions on the arrange timeline (M1a of the
// clip-pro healing block, founder 2026-07-15: "Midi Clip und Audio Clip verhalten
// sich nicht wie von einer professionellen Software erwartet").
//
// The audited defect chain (workflow wf_9c6f33b7-6ff, all claims verified REAL):
// TimelineRegionPlayer loaded a clip's WHOLE melody flat — no windowing by the
// region's length, no trim offset, so only bar 1 ever played, split/front-trim
// hid nothing, and multi-bar takes folded onto themselves. This enum is the pure
// mathematics that fixes it; the player wiring (M1b/M1c) consumes it:
//
//   clip.melody.notes ── windowed(offset, length) ──▶ region-relative notes
//                        └─ barSlices(regionLength) ─▶ per-bar note sets for the
//                           existing bar-cycling `loadArrangement` mechanic.
//
// Contracts (pro-DAW semantics, pinned by RegionNoteWindowTests):
//  • A note SOUNDS iff its START lies inside the window [offset, offset+length).
//    A note starting before the trim-in never sounds (its tail does not leak in).
//  • Sustains are clipped at the REGION end (the block edge is a hard stop) but
//    NOT at bar lines inside the region (a cross-bar sustain keeps its length;
//    its noteOff simply falls in a later bar).
//  • All returned times are REBASED (region-relative, then bar-relative for
//    slices) so consumers never see song-absolute or clip-absolute ticks.
//
// Foundation-only and deterministic — unit-tested on Linux CI without any device.

import Foundation

public enum RegionNoteWindow {

    /// Window `notes` (clip-relative ticks) to a region's visible content:
    /// keep notes starting in `[offsetTicks, offsetTicks + lengthTicks)`, rebase
    /// them to region-relative time, and clip sustains at the region end.
    /// Negative inputs clamp safely; a degenerate window returns [].
    public static func windowed(notes: [Note], offsetTicks: Int, lengthTicks: Int) -> [Note] {
        let offset = Swift.max(0, offsetTicks)
        guard lengthTicks > 0 else { return [] }
        let end = offset + lengthTicks
        return notes.compactMap { n in
            guard n.startTick >= offset, n.startTick < end else { return nil }
            var rebased = n
            rebased.startTick = n.startTick - offset
            // Hard stop at the block edge — a sustain must not outlive its region.
            let maxLen = lengthTicks - rebased.startTick
            rebased.lengthTicks = Swift.max(1, Swift.min(n.lengthTicks, maxLen))
            return rebased
        }
    }

    /// Slice REGION-RELATIVE notes (the output of `windowed`) into per-bar note
    /// sets for the bar-cycling arrangement loader: slice `b` holds the notes
    /// starting in bar `b`, rebased to bar-relative ticks. The slice count is the
    /// region's spanned bars (`ceil(regionLengthTicks / ticksPerBar)`, min 1) —
    /// empty bars yield empty slices so the cycle length stays honest. Cross-bar
    /// sustains stay in their START bar with their full length (see contract).
    public static func barSlices(notes: [Note], regionLengthTicks: Int) -> [[Note]] {
        let perBar = TimelineTime.ticksPerBar
        let bars = Swift.max(1, (Swift.max(1, regionLengthTicks) + perBar - 1) / perBar)
        var slices = Array(repeating: [Note](), count: bars)
        for n in notes {
            let bar = n.startTick / perBar
            guard bar >= 0, bar < bars else { continue }
            var rebased = n
            rebased.startTick = n.startTick - bar * perBar
            slices[bar].append(rebased)
        }
        return slices
    }

    /// The MIDI twin of a region's `contentOffsetSeconds`: the trim-in converted
    /// to ticks at `bpm` (rounded), clamped to ≥0. Degenerate bpm ⇒ 0 — a clip
    /// with no meaningful tempo cannot be trim-windowed, only fully shown.
    public static func offsetTicks(contentOffsetSeconds: Double, bpm: Double) -> Int {
        guard bpm > 0, contentOffsetSeconds.isFinite, contentOffsetSeconds > 0 else { return 0 }
        return TimelineTime.ticks(fromSeconds: contentOffsetSeconds, bpm: bpm)
    }
}
