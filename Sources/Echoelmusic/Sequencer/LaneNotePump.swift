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

    /// The loop content (one bar's notes; step-grid derived from tick source of truth).
    private var notes: [Note] = []
    /// Currently-sounding notes: id → (pitch, exclusive endStep). Kept so a pitch is
    /// released only when no surviving note still holds it, and so a content swap
    /// mid-loop doesn't cut a ringing note.
    private var active: [UUID: ActiveNote] = [:]

    private struct ActiveNote: Equatable { let pitch: Int; let endStep: Int }

    public init(stepCount: Int = 16) {
        self.stepCount = max(1, stepCount)
    }

    /// True when the pump has neither content nor sounding notes (idle slot).
    public var isEmpty: Bool { notes.isEmpty && active.isEmpty }

    /// The pitches currently sounding (test/inspection helper).
    public var soundingPitches: Set<Int> { Set(active.values.map(\.pitch)) }

    /// Replace the loop content. Sounding notes keep ringing until their own release
    /// step — the seamless-swap feel of the primary roll (no `allNotesOff` cut).
    public mutating func load(_ notes: [Note]) {
        self.notes = notes
    }

    /// Advance to `step` (0-based; wraps into the bar). Returns note-offs FIRST, then
    /// note-ons, so a same-pitch retrigger releases before it re-attacks. Pitch de-dup:
    /// a pitch is released only when no surviving active note still holds it.
    public mutating func step(_ step: Int) -> [Event] {
        let s = ((step % stepCount) % stepCount + stepCount) % stepCount
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
        return offs
    }
}
