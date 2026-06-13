// Note.swift
// Echoel — the one note model shared by the piano roll, melody clips, and MIDI
// export. A note has a pitch, a start step, a length in steps (≥1, so it can
// sustain across step boundaries → legato), and a per-note velocity.
//
// Step resolution matches the sequencer grid (16th notes). Sub-step timing is
// out of scope for v1; a note starts on a step boundary and ends `lengthSteps`
// later. See PLAN: "B1.1 — deep piano roll".

import Foundation

/// A single melodic note on the step grid.
///
/// `startStep` is the 0-based step it begins on; `lengthSteps` is how many steps
/// it sounds for (clamped to ≥1). `velocity` is normalized [0...1] and is carried
/// straight into `ControllerEvent.value` when the note is triggered.
public struct Note: Codable, Sendable, Equatable, Identifiable {

    public var id: UUID
    public var pitch: Int
    public var startStep: Int
    public var lengthSteps: Int
    public var velocity: Float

    public init(
        id: UUID = UUID(),
        pitch: Int,
        startStep: Int,
        lengthSteps: Int = 1,
        velocity: Float = 0.8
    ) {
        self.id = id
        self.pitch = min(max(pitch, 0), 127)   // defensive: keep MIDI in range
        self.startStep = startStep
        self.lengthSteps = max(1, lengthSteps)
        self.velocity = min(max(velocity, 0), 1)
    }

    /// Exclusive end step: the first step at which the note is no longer held.
    public var endStep: Int { startStep + lengthSteps }

    /// True if this note is sounding during `step` (start inclusive, end exclusive).
    public func covers(step: Int) -> Bool {
        step >= startStep && step < endStep
    }
}
