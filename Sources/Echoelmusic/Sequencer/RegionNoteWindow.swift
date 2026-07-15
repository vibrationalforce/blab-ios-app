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

// MARK: - Arrangement load plan (pure)

/// How the piano roll should apply a REGION's bar slices at a region onset —
/// which bar sounds NOW, what is staged for the next bar line, and the phase
/// offset that keeps the roll's GLOBAL `playedBars` cycling region-relative.
///
/// Why this exists (M1b): the roll's bar-cycling stages
/// `arrangementBars[(playedBars + phaseOffset) % n]` at every bar line, and
/// `playedBars` is a global counter that has been running since Play. A region
/// loading at global bar G must therefore rotate its indexing by a phase offset —
/// AND the correct staging differs depending on whether the onset lands exactly
/// on the bar line (the roll's trigger(0) runs AFTER the timeline player in the
/// same tick, so anything staged would be consumed immediately) or mid-bar (the
/// staged bar is consumed at the NEXT bar line). Deterministic, exhaustively
/// tested — the wiring in PianoRollModel just applies the plan.
public struct ArrangementLoadPlan: Equatable, Sendable {
    /// Index into the bar slices that must sound from this step on.
    public let nowIndex: Int
    /// Index to stage as `pendingNotes` (consumed at the next trigger(0)), or nil
    /// when nothing may be staged (a step-0 onset would consume it this very tick).
    public let pendingIndex: Int?
    /// Value for the roll's `arrangementPhaseOffset` so every FOLLOWING bar line
    /// stages `(playedBars + offset) % n` region-relatively.
    public let phaseOffset: Int

    /// Compute the plan. `barCount` ≥ 1; `startBar` = the region-relative bar under
    /// the playhead now; `playedBars` = the roll's global bar counter at load time;
    /// `atStepZero` = the onset lands exactly on a bar line (trigger(0) still runs
    /// this tick, AFTER the load); `playing` = the transport is running.
    ///
    /// Derivation (pinned by tests):
    ///  • stopped        → now = sb, nothing staged, playedBars is reset by the
    ///    caller to 0 ⇒ offset = sb.
    ///  • playing, step0 → trigger(0) runs next in THIS tick: it must not find a
    ///    staged bar (it would replace `now` immediately), then it increments
    ///    playedBars to P+1 and stages (P+1+offset) which must be sb+1
    ///    ⇒ offset = sb − P.
    ///  • playing, mid-bar → playedBars was already incremented at this bar's own
    ///    step 0, so the NEXT trigger(0) first consumes the staged bar (must be
    ///    sb+1), then increments to P+1 and stages (P+1+offset) which must be
    ///    sb+2 ⇒ offset = sb + 1 − P.
    public static func plan(barCount: Int, startBar: Int, playedBars: Int,
                            atStepZero: Bool, playing: Bool) -> ArrangementLoadPlan {
        let n = Swift.max(1, barCount)
        func mod(_ x: Int) -> Int { ((x % n) + n) % n }
        let sb = mod(startBar)
        guard playing else {
            return ArrangementLoadPlan(nowIndex: sb, pendingIndex: nil, phaseOffset: sb)
        }
        if atStepZero {
            return ArrangementLoadPlan(nowIndex: sb, pendingIndex: nil,
                                       phaseOffset: mod(sb - playedBars))
        }
        return ArrangementLoadPlan(nowIndex: sb,
                                   pendingIndex: n > 1 ? mod(sb + 1) : nil,
                                   phaseOffset: mod(sb + 1 - playedBars))
    }
}
