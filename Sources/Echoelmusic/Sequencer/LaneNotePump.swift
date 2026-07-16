// LaneNotePump.swift
// Multi-Roll (B08) — the PURE per-lane note scheduler for SECONDARY timeline lanes.
//
// In multi-roll playback the PRIMARY lane keeps the full `PianoRollModel` (per-note
// operators, bio expression, wrap-ties, MPE, sub-bass reconcile). Every ADDITIONAL
// MIDI lane gets one of these lightweight pumps instead: it turns a loop of `Note`s
// into faithful note-on/off events per transport step, which the device layer applies
// to that lane's own rack voice (`LaneVoiceRack.voice(slot:)`). Deterministic,
// Foundation-only, no engine — unit-tested on every platform. Operators/bio on
// secondary lanes are a deliberate later refinement; this is the "tracks play
// simultaneously" foundation.

import Foundation

/// A minimal, pure step→note-event scheduler for ONE secondary lane. Holds the lane's
/// current loop content and the set of sounding notes so releases are correct across
/// the loop wrap. All timing is on the 16-step/bar grid via `Note.startStep`/`endStep`.
public struct LaneNotePump: Sendable, Equatable {

    /// One note event to apply to the lane's voice. `velocity == 0` ⇒ a note-off.
    public struct Event: Equatable, Sendable {
        public let pitch: Int
        public let velocity: Float
        public init(pitch: Int, velocity: Float) {
            self.pitch = pitch
            self.velocity = velocity
        }
        /// True for an attack, false for a release.
        public var isOn: Bool { velocity > 0 }
    }

    /// Steps per bar (16 on the 4/4 grid). Immutable per pump.
    public let stepCount: Int

    /// The CURRENT bar's notes (bars[barCursor]; step-grid, rebased 0..<stepCount).
    private var notes: [Note] = []
    /// M1c: the region's full loop content as region-relative BAR SLICES — bar i's
    /// notes rebased to the bar grid (`RegionNoteWindow.barSlices` output). The old
    /// single-`notes` model folded every bar of a multi-bar clip onto steps 0-15
    /// (CLIP-1: both bars sounded superimposed, repeating every bar).
    private var bars: [[Note]] = []
    /// Which bar slice is playing. Advances when the local step wraps to 0.
    private var barCursor: Int = 0
    /// nil until the first step() after a load — the onset step itself must not
    /// advance the cursor even when it lands on a bar boundary (s == 0).
    private var lastLocalStep: Int? = nil
    /// Currently-sounding notes: id → (pitch, exclusive endStep). Kept so a pitch is
    /// released only when no surviving note still holds it, and so a content swap
    /// mid-loop doesn't cut a ringing note.
    private var active: [UUID: ActiveNote] = [:]

    private struct ActiveNote: Equatable { let pitch: Int; let endStep: Int }

    public init(stepCount: Int = 16) {
        self.stepCount = max(1, stepCount)
    }

    /// True when the pump has neither content (in ANY bar) nor sounding notes.
    public var isEmpty: Bool { bars.allSatisfy(\.isEmpty) && active.isEmpty }

    /// The pitches currently sounding (test/inspection helper).
    public var soundingPitches: Set<Int> { Set(active.values.map(\.pitch)) }

    /// Replace the loop content with a SINGLE bar (legacy/simple callers). Sounding
    /// notes keep ringing until their own release step — the seamless-swap feel of
    /// the primary roll (no `allNotesOff` cut).
    public mutating func load(_ notes: [Note]) {
        load(bars: [notes], startBar: 0)
    }

    /// M1c: replace the loop content with region-relative bar slices, entering at
    /// `startBar` (mid-region prime/seek; folded into the region length). Sounding
    /// notes keep ringing until their own release step.
    public mutating func load(bars newBars: [[Note]], startBar: Int) {
        bars = newBars.isEmpty ? [[]] : newBars
        barCursor = ((startBar % bars.count) + bars.count) % bars.count
        notes = bars[barCursor]
        lastLocalStep = nil
    }

    /// Advance to `step` (0-based; wraps into the bar). Returns note-offs FIRST, then
    /// note-ons, so a same-pitch retrigger releases before it re-attacks. Pitch de-dup:
    /// a pitch is released only when no surviving active note still holds it.
    /// A wrap to step 0 (after the load's own onset step) advances the bar cursor —
    /// multi-bar regions play bar BY bar and loop over their full length.
    public mutating func step(_ step: Int) -> [Event] {
        let s = ((step % stepCount) % stepCount + stepCount) % stepCount
        if s == 0, lastLocalStep != nil, bars.count > 1 {
            barCursor = (barCursor + 1) % bars.count
            notes = bars[barCursor]
        }
        lastLocalStep = s
        var events: [Event] = []

        // Releases: active notes whose exclusive end lands on this step.
        let ending = active.filter { $0.value.endStep % stepCount == s }
        for id in ending.keys { active[id] = nil }
        for info in ending.values {
            if !active.values.contains(where: { $0.pitch == info.pitch }) {
                events.append(Event(pitch: info.pitch, velocity: 0))
            }
        }

        // Onsets: notes starting on this step. Silent notes (velocity 0) never attack.
        for note in notes where note.startStep % stepCount == s {
            let v = min(1, max(0, note.velocity))
            guard v > 0 else { continue }
            events.append(Event(pitch: note.pitch, velocity: v))
            active[note.id] = ActiveNote(pitch: note.pitch, endStep: note.endStep)
        }
        return events
    }

    /// Release everything and drop the content (slot clear / loop stop). Returns the
    /// note-offs the caller must apply so no voice is left hanging.
    public mutating func reset() -> [Event] {
        let offs = Set(active.values.map(\.pitch)).sorted().map { Event(pitch: $0, velocity: 0) }
        active.removeAll()
        notes.removeAll()
        bars.removeAll()
        barCursor = 0
        lastLocalStep = nil
        return offs
    }
}
