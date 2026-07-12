// NoteTransform.swift
// Echoel — one-gesture note transforms ("Ableton 20" track A2): Strum and
// Humanize as PURE functions over a selection of notes. FL Studio ships these
// as tool panels, Live 12 as Transform-tab tools; Echoel collapses each to one
// gesture on the roll selection / BioComposer output. Deterministic (seeded,
// order-independent), so a transformed take is reproducible and the functions
// are fully unit-testable. Applied at edit time — never in the render path.

import Foundation

public enum NoteTransform {

    // MARK: Strum

    /// Fan the notes of each chord out in time (guitar-strum feel). Notes that
    /// share a `startTick` form a chord; the k-th strummed note of an n-note
    /// chord is delayed by `k × spreadTicks / (n−1)` (the first stays put, the
    /// last lands `spreadTicks` late). `upward` strums low→high pitch (bass
    /// first, like a downstroke on guitar — the musical default), `false`
    /// strums high→low. `velocitySlope` −1…1 ramps velocity across the strum
    /// (last note × (1+slope), clamped) — a light negative slope reads natural.
    /// Every note keeps its ORIGINAL end tick (length shrinks as start moves),
    /// so the chord still releases together and the bar never overflows.
    /// Single notes and empty input pass through unchanged.
    public static func strum(_ notes: [Note], spreadTicks: Int,
                             velocitySlope: Double = 0,
                             upward: Bool = true) -> [Note] {
        let spread = max(0, spreadTicks)
        let slope = velocitySlope.isFinite ? min(1, max(-1, velocitySlope)) : 0
        guard spread > 0 || slope != 0 else { return notes }

        // Group into chords by exact start tick, remembering original order so
        // the result keeps the input's note order (stable for the UI).
        var byStart: [Int: [Note]] = [:]
        for n in notes { byStart[n.startTick, default: []].append(n) }

        var transformed: [UUID: Note] = [:]
        for (_, chord) in byStart where chord.count > 1 {
            let ordered = chord.sorted { upward ? $0.pitch < $1.pitch : $0.pitch > $1.pitch }
            let n = ordered.count
            for (k, note) in ordered.enumerated() {
                let f = Double(k) / Double(n - 1)                 // 0…1 across the strum
                var out = note
                let delay = Int((Double(spread) * f).rounded())
                let end = note.endTick
                out.startTick = note.startTick + delay
                out.lengthTicks = max(1, end - out.startTick)     // keep the release point
                let scale = 1 + slope * f
                out.velocity = min(1, max(0, Float(Double(note.velocity) * scale)))
                transformed[note.id] = out
            }
        }
        guard !transformed.isEmpty else { return notes }
        return notes.map { transformed[$0.id] ?? $0 }
    }

    // MARK: Humanize

    /// Bounded, deterministic timing + velocity variation on a selection —
    /// the edit-time sibling of `Humanizer` (which humanizes at MIDI export).
    /// Jitter is seeded per NOTE ID (stable UUID fold), so the result is
    /// independent of array order and identical across launches: same
    /// selection + same seed → the same "performance", always. Starts are
    /// clamped ≥0; velocities to [0…1]; lengths untouched.
    public static func humanize(_ notes: [Note], timingTicks: Int,
                                velocityJitter: Float, seed: UInt64) -> [Note] {
        let ticks = max(0, timingTicks)
        let jitter = min(max(velocityJitter.isFinite ? velocityJitter : 0, 0), 1)
        guard ticks > 0 || jitter > 0 else { return notes }
        return notes.map { note in
            var rng = SeededRNG(seed: seed ^ NoteOperators.fold(note.id))
            let t = rng.unit() * 2 - 1                            // −1…1
            let v = rng.unit() * 2 - 1
            var out = note
            out.startTick = max(0, note.startTick + Int((t * Float(ticks)).rounded()))
            out.velocity = min(1, max(0, note.velocity * (1 + v * jitter)))
            return out
        }
    }
}
