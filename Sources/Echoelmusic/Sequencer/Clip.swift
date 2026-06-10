// Clip.swift
// Echoel — launchable session clips: a saved drum pattern and/or melody that can
// be fired into the live transport (Ableton-session style). Pure value types, so
// clips persist as JSON and round-trip cleanly.

import Foundation

/// A saved drum grid (steps + accents), shaped like PatternEngine's state.
public struct DrumPattern: Codable, Sendable, Equatable {
    public var steps: [[Bool]]
    public var accents: [[Bool]]
    public init(steps: [[Bool]], accents: [[Bool]]) {
        self.steps = steps
        self.accents = accents
    }
}

/// A saved melodic phrase (absolute-pitch notes from the piano roll).
public struct MelodyClip: Codable, Sendable, Equatable {
    public var notes: [Note]
    public init(notes: [Note]) { self.notes = notes }
}

/// A launchable cell: a drum pattern and/or a melody, with a name + color.
public struct Clip: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var colorIndex: Int
    public var drums: DrumPattern?
    public var melody: MelodyClip?

    public init(
        id: UUID = UUID(),
        name: String,
        colorIndex: Int = 0,
        drums: DrumPattern? = nil,
        melody: MelodyClip? = nil
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.drums = drums
        self.melody = melody
    }

    /// True if the clip carries no content.
    public var isEmpty: Bool {
        (drums?.steps.flatMap { $0 }.contains(true) ?? false) == false
            && (melody?.notes.isEmpty ?? true)
    }
}
