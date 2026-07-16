// RollHitTest.swift
// Echoel — the pure hit-test behind the piano-roll editing station (#58,
// founder 2026-07-16: die MIDI/MPE-Station ist "noch sehr rudimentär"). The
// single canvas DragGesture branches on where the drag STARTS: on a note's body
// (→ move), on a note's right edge (→ resize), or on empty grid (→ create/
// select). This is that classifier, factored out as Foundation-only geometry so
// every boundary is unit-tested on CI without a SwiftUI host — the same law as
// AutomationCanvasMath. Slice 1 of PLAN_58: no view change yet, just the core
// that move + resize + create will all share.

import Foundation

/// Where a piano-roll drag began, resolved against the notes and the canvas
/// geometry. `.empty` also carries the grid cell so create/select needs no
/// second computation.
public enum RollHit: Equatable, Sendable {
    /// No note under the point — the grid cell (pitch, step) to create/select in.
    case empty(pitch: Int, step: Int)
    /// The body of an existing note — a move target.
    case body(id: UUID)
    /// The right edge of an existing note — a resize (length) target.
    case rightEdge(id: UUID)
}

public enum RollHitTest {

    /// Classify a point in canvas coordinates (x = time L→R, y = pitch TOP high →
    /// BOTTOM low, matching `PianoRollView.yForPitch`). Notes are tested topmost-
    /// first so an overlapping note nearest the front wins; within a hit note, the
    /// last `edgeSlop` points of its drawn width read as the resize edge (but never
    /// more than half the note, so a 1-step note stays draggable as a body). A miss
    /// falls through to the clamped grid cell.
    ///
    /// - Parameters:
    ///   - x, y: point in canvas space (points).
    ///   - notes: the roll's notes; later entries are treated as visually on top.
    ///   - stepW, rowH: cell size in points (must be > 0; guarded).
    ///   - highPitch, lowPitch: inclusive pitch range of the top and bottom rows.
    ///   - stepCount: number of step columns (grid width in cells).
    ///   - edgeSlop: width in points of the right-edge resize zone.
    public static func classify(
        x: Double, y: Double,
        notes: [Note],
        stepW: Double, rowH: Double,
        highPitch: Int, lowPitch: Int,
        stepCount: Int,
        edgeSlop: Double
    ) -> RollHit {
        let cell = emptyCell(x: x, y: y, stepW: stepW, rowH: rowH,
                             highPitch: highPitch, lowPitch: lowPitch,
                             stepCount: stepCount)
        guard stepW > 0, rowH > 0 else { return cell }

        // Topmost-first: the last-drawn note sits visually in front.
        for note in notes.reversed() {
            guard note.pitch <= highPitch, note.pitch >= lowPitch else { continue }
            let noteX = Double(note.startStep) * stepW
            let noteW = Double(note.lengthSteps) * stepW
            let noteY = Double(highPitch - note.pitch) * rowH
            let inX = x >= noteX && x < noteX + noteW
            let inY = y >= noteY && y < noteY + rowH
            guard inX, inY else { continue }
            // Edge zone = last `edgeSlop` points, capped at half the note so a
            // 1-step note keeps a graspable body.
            let slop = Swift.min(Swift.max(0, edgeSlop), noteW / 2)
            if slop > 0, x >= noteX + noteW - slop {
                return .rightEdge(id: note.id)
            }
            return .body(id: note.id)
        }
        return cell
    }

    /// Length in steps for a right-edge resize: the step under the finger becomes
    /// the note's LAST covered step, so length = fingerStep − startStep + 1, never
    /// below 1 (drag past the start collapses to a single step). #58 Slice 3. The
    /// caller still passes the result through `PianoRollModel.setLength`, which
    /// clamps the tail to the bar — this is just the finger→length law.
    public static func resizedLengthSteps(fingerStep: Int, startStep: Int) -> Int {
        Swift.max(1, fingerStep - startStep + 1)
    }

    /// Velocity (0…1) for a vertical position in the velocity lane: the TOP of the
    /// lane is full velocity, the bottom is silent (the natural "taller bar = louder"
    /// reading). Clamped, and safe on a zero-height lane. #58 Slice 4.
    public static func velocity(forY y: Double, laneHeight: Double) -> Float {
        guard laneHeight > 0 else { return 0 }
        return Float(Swift.max(0, Swift.min(1, 1 - y / laneHeight)))
    }

    /// The note whose velocity a lane drag at `step` should paint: the TOPMOST
    /// (last-drawn) note covering that step, matching `classify`'s topmost-wins
    /// rule, or nil if the column is empty. #58 Slice 4.
    public static func noteToPaint(atStep step: Int, notes: [Note]) -> UUID? {
        notes.last(where: { $0.covers(step: step) })?.id
    }

    /// The clamped grid cell under a point — the `.empty` payload and the public
    /// helper the view uses for create/select geometry.
    public static func emptyCell(
        x: Double, y: Double,
        stepW: Double, rowH: Double,
        highPitch: Int, lowPitch: Int,
        stepCount: Int
    ) -> RollHit {
        guard stepW > 0, rowH > 0, stepCount > 0, highPitch >= lowPitch else {
            return .empty(pitch: lowPitch, step: 0)
        }
        let rawStep = Int((x / stepW).rounded(.down))
        let step = Swift.min(Swift.max(rawStep, 0), stepCount - 1)
        let rawRow = Int((y / rowH).rounded(.down))
        let pitch = Swift.min(Swift.max(highPitch - rawRow, lowPitch), highPitch)
        return .empty(pitch: pitch, step: step)
    }
}
