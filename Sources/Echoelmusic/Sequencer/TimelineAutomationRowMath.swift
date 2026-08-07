// TimelineAutomationRowMath.swift
// Echoel — #472. The pure geometry + touch law of the timeline automation row,
// hoisted out of `Studio/TimelineAutomationRow.swift` so the LIVE half stopped living
// inside a file whose other 344 lines WERE an unmounted SwiftUI view. Past tense on
// purpose: #473 deleted that file (see the ⭐ block below). ⛔ The first version of this
// line stayed present-tense fifty lines above the block announcing the deletion.
//
// ⭐ WHY THE HOIST, said narrowly. Nothing here computes a different number than it
// did yesterday; this is a move. What it removes is a tripwire CLAUDE.md names by
// hand: `sameParameter` is read by `Core/TimelineStore.swift`, so a plausible
// "delete the doorless file" cleanup would have broken the store. Doorless is a
// property of a VIEW; deletable is a property of a FILE, and this repo keeps putting
// the two in one file. After this slice they are separate.
//
// It went NEXT TO `AutomationCanvasMath` rather than into `Core/` (where its one
// live consumer lives) because this type is not self-contained, and the count is
// stated rather than asserted: it forwards `tapSlopPoints` to and maps value→y
// through `AutomationCanvasMath` (`Sequencer/AutomationCanvasMath.swift`), it takes
// `AutomationPoint` (`Sequencer/AutomationLane.swift`), and it resolves parameter
// identity through `AutomationTarget` — which is in `Core/AutomationPlayer.swift`,
// NOT here. So two of three collaborators are in this directory and one is not; the
// placement follows the majority, it is not a clean sweep.
//
// ⛔ The first draft of this header, of the view file's header, and of the guard all
// said "next to the AutomationCanvasMath and AutomationTarget it composes with" —
// wrong in three files at once, and caught by looking the declaration up instead of
// trusting a sentence that read well. `AutomationTarget` sits beside the CONSUMER,
// which is a mildly better argument for `Core/` than the one recorded above; the
// tie-breaker is that the two GEOMETRY collaborators are the ones this file's
// arithmetic actually leans on, and `sameParameter` is a three-line forward.
//
// ⚠️ HONEST INVENTORY, because "pure core, kept" reads as "all of it is used" and
// that is false. Exactly ONE member has a production caller:
//   · `sameParameter`  — LIVE (`Core/TimelineStore.swift`, alias-aware lane lookup).
//   · `x(forTick:)` · `tick(forX:)` · `nearestPoint` · `hitPointID` ·
//     `displayPoints` · `touchRadius` · `tapSlopPoints` — ZERO callers in `Sources/`.
//     Their only one was the unmounted `TimelineAutomationRow` view, and #473 deleted
//     it, so what was "unreachable" is now "absent". The hoist neither helped nor
//     harmed that; it is what made the deletion possible without breaking the store.
//     ⛔ A RECIPE STOOD HERE AND IT FALSIFIED ITSELF: it quoted a `git grep` for the
//     view's name "= 0" — but the sentence quoting it CONTAINED the searched string, so
//     running it returned this line and read as a contradiction. Exactly the
//     `EchoelModalBank` trap CLAUDE.md records: a note that QUOTES a grep ages faster than
//     one that states a fact, because every comment written about the thing corrupts its own
//     evidence. Stated as a fact instead. To measure a caller count, ask about the CALL
//     form and exclude prose — e.g. `git grep -n "displayPoints(" -- Sources | grep -v '://'`.
// They are kept, not because they are used, but because deleting them is a SECOND
// decision and #470 paid for the rule the hard way: changing the arithmetic inside a
// move commit is how a "no behaviour change" claim stops being true. The tick↔px law
// is what a future timeline surface would need first — same standing as
// `WaveformReducer` after #132 Slice 5, and labelled here rather than discovered
// later.
//
// ⭐ THE VIEW HALF IS DELETED (#473) — and the sequencing is the lesson, not the deletion.
// This header used to say the opposite, at length, because #472 discovered mid-flight that
// the registered unblock ("hoist the pure core, THEN delete") was not the real blocker:
// FIVE source files cited that view in prose, two of them load-bearing for shipping code.
// #473 relocated all five FIRST and deleted the file second — 415 lines removed
// (`git show --stat`), of which the `struct TimelineAutomationRow: View` itself was 198 and
// the whole `#if canImport(SwiftUI)` half 344. ⛔ Four other artifacts attached the 415 to the
// VIEW; that is the #475 defect one cycle later, and the tree already carried 344 for the same
// object. A file size is not a view size. What moved where:
//   · `Core/PerTrackParameterKeyPath.swift` had a POINTER at the view's `DATA MODEL
//     (honest):` block. The block is now INLINED there — a pointer is only as durable as
//     the thing it points at, and that same line had already lost a `:11-16` line range
//     to #472. Two citation failures, two mechanisms, one file.
//   · `Studio/EchoelValueField.swift` — the ONE parameter control app-wide — cited the row
//     TWICE with TWO DISTINCT premises, and only ONE named `handleEnded` (the `REVERT —
//     one main-actor turn later` block, the premise the #377/#378 revert-on-cancel design
//     rests on; the other, `⚠️ HONEST LIMIT (unchanged):`, named the view without a member
//     for a different property). ⛔ The first version of that sentence attached "TWICE" to
//     one member, in four artifacts at once. Both are now stated as HISTORICAL evidence:
//     the SwiftUI claims are unchanged, the in-repo witness is gone, and the second block
//     gained the sharper reading — this file is now the only dependant left.
//   · `DSP/EchoelDDSP.swift` used the row's doorlessness as an `outputLevel` reachability
//     premise. "Zero instantiation sites" would have been silently falsified by a re-mount;
//     "deleted" cannot be, so that argument got STRONGER.
//   · `Core/AutomationPlayer.swift` carries a ⛔ retraction that named the row. It stays,
//     precisely because the code it corrects no longer exists to be re-read.
//   · `Sequencer/ClipAutomationEdit.swift` cited "TimelineAutomationRow's static helpers" —
//     already wrong since #472 moved them HERE, and pointing at nothing after #473.
// ⚠️ Cited by PHRASE throughout, never by line number: #472 retired a
// `TimelineAutomationRow:11-16` range for going stale, and minting fresh numbers while
// retiring old ones is the defect rather than the fix.

import Foundation

/// Pure geometry + touch law for the song-wide inline automation row.
/// x is song-absolute: `x = tick · pxPerTick` — the exact scale of the clip
/// grid (`pxPerTick = pointsPerBeat / TimelineTime.ticksPerBeat`), so curve and
/// clips stay aligned by construction at every zoom.
public enum TimelineAutomationRowMath {

    /// Same touch radius as the sheet canvas (A3).
    public static let touchRadius = 28.0
    /// A finished drag below this travel counts as a TAP (shared A3 law).
    public static var tapSlopPoints: Double { AutomationCanvasMath.tapSlopPoints }

    // MARK: Coordinate mapping (song-absolute)

    public static func x(forTick tick: Int, pxPerTick: Double) -> Double {
        guard pxPerTick > 0, pxPerTick.isFinite else { return 0 }
        return Double(max(0, tick)) * pxPerTick
    }

    /// x → song tick, clamped into [0, maxTick]. Degenerate scale → 0.
    public static func tick(forX x: Double, pxPerTick: Double, maxTick: Int) -> Int {
        guard pxPerTick > 0, pxPerTick.isFinite, x.isFinite, maxTick > 0 else { return 0 }
        return min(max(0, Int((x / pxPerTick).rounded())), maxTick)
    }

    // MARK: Hit-testing

    /// The keyframe nearest to a canvas location, with its screen distance —
    /// the caller applies `touchRadius`. nil for an empty lane. Height maps
    /// value→y via the tested AutomationCanvasMath law.
    public static func nearestPoint(toX x: Double, y: Double,
                                    points: [AutomationPoint],
                                    pxPerTick: Double, height: Double)
        -> (id: UUID, distance: Double)? {
        var best: (UUID, Double)?
        for p in points {
            let dx = Self.x(forTick: p.tick, pxPerTick: pxPerTick) - x
            let dy = AutomationCanvasMath.y(forValue: p.value, height: height) - y
            let d = (dx * dx + dy * dy).squareRoot()
            if best == nil || d < best!.1 { best = (p.id, d) }
        }
        return best.map { (id: $0.0, distance: $0.1) }
    }

    /// Classify a touch-down: the keyframe id to MOVE when the start lands
    /// within `touchRadius` of one, else nil (a tap-in-waiting that adds).
    /// Deterministic — the gesture calls it at touch-down AND again at release,
    /// so a cancelled @GestureState never strands a stale mode.
    public static func hitPointID(atX x: Double, y: Double,
                                  points: [AutomationPoint],
                                  pxPerTick: Double, height: Double) -> UUID? {
        guard let hit = nearestPoint(toX: x, y: y, points: points,
                                     pxPerTick: pxPerTick, height: height),
              hit.distance <= touchRadius else { return nil }
        return hit.id
    }

    // MARK: Drag preview

    /// The points array with ONE keyframe substituted at a preview tick/value —
    /// what the canvas renders mid-drag (the store commits only on release).
    /// Kept sorted so the curve evaluation stays correct while dragging.
    public static func displayPoints(_ points: [AutomationPoint], movingID: UUID?,
                                     toTick tick: Int, value: Double) -> [AutomationPoint] {
        guard let movingID else { return points }
        var out = points
        if let i = out.firstIndex(where: { $0.id == movingID }) {
            out[i].tick = max(0, tick)
            out[i].value = min(1, max(0, value))
        }
        return out.sorted { $0.tick < $1.tick }
    }

    // MARK: Parameter identity

    /// Alias-aware parameter equality: a legacy enum rawValue ("masterLevel")
    /// and its registry keyPath ("master.amp.level") name the SAME lane — the
    /// law AutomationPlayer's layerValue already applies at playback.
    ///
    /// ⭐ THE ONE MEMBER WITH A PRODUCTION CALLER (`Core/TimelineStore.swift`), which
    /// is why this whole type outlives the view it was named after. Note what it is
    /// NOT: a string comparison with a fallback. `AutomationTarget.forParameter`
    /// returning nil on the LEFT means "no known alias", so an unrecognised pair is
    /// unequal even when both sides are unrecognised — deliberate, because two
    /// unknown free keyPaths that differ textually are two different lanes. The
    /// `a == b` fast path above is what makes an unknown key equal to ITSELF.
    public static func sameParameter(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard let ta = AutomationTarget.forParameter(a) else { return false }
        return ta == AutomationTarget.forParameter(b)
    }
}
