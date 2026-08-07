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

    /// Map a paint-lane unit [0…1] to an occurrence PERIOD: the bar draws the 1:N
    /// ratio, so the inverse recovers N (top = 1:1 = every loop, half = 1:2, …). The
    /// caller still passes the result through `NoteOperators`, whose init clamps it to
    /// `periodRange` — this is only the unit→period law.
    ///
    /// It lives HERE, next to `velocity(forY:laneHeight:)`, because that is the one
    /// producer of the unit it consumes: Y → unit → period is one chain, and both ends
    /// were already pure. Hoisted out of the doorless note editor (#470) so the law
    /// survives the view; it is not a new decision and the arithmetic is unchanged.
    ///
    /// ⚠️ Three edges, stated rather than smoothed. All are pre-existing and none is reachable
    /// from the live producer, which clamps to 0…1 — they are written down because the next
    /// caller may not clamp:
    ///   · the `> 0.02` floor is a STEP, not a taper: 0.0201 maps to 50, 0.02 to 64.
    ///     Anything at or below it reads as "the sparsest the range allows".
    ///   · NaN and −∞ fail the comparison and therefore take that same floor branch —
    ///     NaN-safe by argument order, the law `clamped(to:)` exists for.
    ///   · ⛔ +∞ does NOT. It passes the guard, and `Int((1/∞).rounded())` is **0** — below
    ///     `periodRange`. So does any unit above 2. Today `NoteOperators`' init clamps that
    ///     back to 1, so the shipped chain is safe; this function ALONE is not, and the first
    ///     draft of its own doc claimed otherwise ("a non-finite unit … yields the floor
    ///     branch"). Left as-is on purpose: #470 is a hoist, and changing the arithmetic in a
    ///     move commit is how a "no behaviour change" claim stops being true.
    public static func occurrencePeriod(forUnit unit: Double) -> Int {
        guard unit > 0.02 else { return NoteOperators.periodRange.upperBound }
        return Int((1.0 / unit).rounded())
    }

    /// The note whose velocity a lane drag at `step` should paint: the TOPMOST
    /// (last-drawn) note covering that step, matching `classify`'s topmost-wins
    /// rule, or nil if the column is empty. #58 Slice 4.
    public static func noteToPaint(atStep step: Int, notes: [Note]) -> UUID? {
        notes.last(where: { $0.covers(step: step) })?.id
    }

    /// IDs of every note whose drawn rectangle overlaps the marquee rectangle
    /// (given by any two opposite corners). Half-open cell geometry matches
    /// `classify`: a note spans x ∈ [startStep·stepW, endStep·stepW) and y ∈
    /// [(highPitch−pitch)·rowH, +rowH). #58 Slice 5 (marquee select). Empty on
    /// degenerate geometry. Order follows `notes` (draw order).
    public static func notesInRect(
        x0: Double, y0: Double, x1: Double, y1: Double,
        notes: [Note], stepW: Double, rowH: Double, highPitch: Int
    ) -> [UUID] {
        guard stepW > 0, rowH > 0 else { return [] }
        let loX = Swift.min(x0, x1), hiX = Swift.max(x0, x1)
        let loY = Swift.min(y0, y1), hiY = Swift.max(y0, y1)
        return notes.compactMap { n in
            let nx0 = Double(n.startStep) * stepW
            let nx1 = Double(n.endStep) * stepW
            let ny0 = Double(highPitch - n.pitch) * rowH
            let ny1 = ny0 + rowH
            // Standard AABB overlap (touching edges don't count → half-open).
            let hit = nx0 < hiX && nx1 > loX && ny0 < hiY && ny1 > loY
            return hit ? n.id : nil
        }
    }

    /// Clamp a group-move delta so EVERY selected note stays in range while the
    /// group keeps its shape (ONE delta for all, not per-note clamping which would
    /// compress the group against an edge). #58 Slice 5b. Empty selection → (0,0).
    public static func clampedGroupDelta(
        dPitch: Int, dStep: Int, selected: [Note],
        lowPitch: Int, highPitch: Int, stepCount: Int
    ) -> (dPitch: Int, dStep: Int) {
        guard !selected.isEmpty else { return (0, 0) }
        // Pitch: low ≤ pitch+dPitch ≤ high for all → dPitch ∈ [low−minPitch, high−maxPitch].
        let minPitch = selected.map(\.pitch).min() ?? lowPitch
        let maxPitch = selected.map(\.pitch).max() ?? highPitch
        let cdP = Swift.max(lowPitch - minPitch, Swift.min(dPitch, highPitch - maxPitch))
        // Step: 0 ≤ start+dStep ≤ stepCount−len for all → intersect each note's window.
        var loD = Int.min, hiD = Int.max
        for n in selected {
            loD = Swift.max(loD, -n.startStep)
            hiD = Swift.min(hiD, (stepCount - n.lengthSteps) - n.startStep)
        }
        let cdS = Swift.max(loD, Swift.min(dStep, hiD))
        return (cdP, cdS)
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
