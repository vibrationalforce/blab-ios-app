// TimelineDragMath.swift
// Echoel — jitter audit #56 C4 ("stepless live preview vs snapped+clamped commit
// → jump at every release"): the PURE live-preview math for the three region
// gestures. During a drag the clip now previews at the SAME snapped/clamped
// position its release will commit, so letting go is a visual no-op instead of
// a half-grid-cell jump.
//
// Foundation-only, no SwiftUI, no store — pure value math, unit-tested on the
// macOS SwiftPM CI (the repo has no Linux build/test gate; Sequencer's other
// pure core, AutomationCanvasMath, uses Double — CGFloat here matches the view's
// point geometry). The view keeps its raw @GestureState finger deltas and
// derives the drawn delta through these functions in body (a few ops/frame,
// leaf-local).
//
// HONEST SCOPE (documented deltas from the commit path, all release-safe):
// • Neighbour-edge magnetism (snapWithEdges, ±8 pt) is now PREVIEWED too (#56 C6):
//   the PARENT lane row captures the neighbour edge ticks once (a user-rate value,
//   like `laneGates`) and passes them down, so the leaf magnetizes in-body without
//   ever touching the store during the drag (freeze-law honoured). The half-cell
//   grid jump AND the residual magnet pull at release are both gone. On a lane
//   change the caller passes no edges, matching the commit's plain-grid branch.
// • The front-trim min-start clamp uses the EXACT tick twin
//   (`contentOffsetTicks`, M1b). `trimmedStart` now prefers the SAME twin, so
//   preview and commit agree exactly for every modern region at ANY tempo
//   (including under bio→tempo drift). Only a legacy seconds-only region (twin
//   0, seconds > 0) previews without the clamp and lets the commit apply it —
//   reading the tempo in a leaf BODY for the seconds→ticks conversion is
//   forbidden (bio→tempo modulates it live; a body read would churn every clip
//   leaf at modulation rate).
// • Exact-zero mid-drag frame: with snap on and an off-grid region, the single
//   frame where the finger delta is exactly 0 renders the raw store position
//   (not the snapped preview) — a one-frame ≤half-cell flick. Requires exact
//   CGFloat-zero translation mid-gesture; cosmetic, rare.

import Foundation

public enum TimelineDragMath {

    /// Points per tick at the current zoom. Guarded: a non-positive/degenerate
    /// `ppb` yields 0 so a preview can never divide by zero or go NaN.
    public static func pointsPerTick(ppb: CGFloat) -> CGFloat {
        guard ppb.isFinite, ppb > 0 else { return 0 }
        return ppb / CGFloat(TimelineTime.ticksPerBeat)
    }

    /// Raw finger points → tick delta at the current zoom (0 when ppb is degenerate).
    public static func tickDelta(fromPoints points: CGFloat, ppb: CGFloat) -> Int {
        guard ppb.isFinite, ppb > 0, points.isFinite else { return 0 }
        return Int((points / ppb * CGFloat(TimelineTime.ticksPerBeat)).rounded())
    }

    // MARK: - Move (clip body)

    /// The row-snapped lane shift a vertical finger delta previews/commits
    /// (≥ half a row = next lane) — same rounding as the commit.
    public static func laneShift(fromPoints height: CGFloat, laneHeight: CGFloat) -> Int {
        guard laneHeight.isFinite, laneHeight > 0, height.isFinite else { return 0 }
        return Int((height / laneHeight).rounded())
    }

    /// The drop-acceptance facts of one lane row, as plain VALUES so the region
    /// leaf never reads the document during a drag (freeze law).
    public struct LaneGate: Equatable, Sendable {
        public let kind: ClipKind
        public let isBio: Bool
        public init(kind: ClipKind, isBio: Bool) {
            self.kind = kind
            self.isBio = isBio
        }
    }

    /// Lane-GATE-aware row shift (#56 MEDIUM #2): the raw preview seated a clip
    /// on ANY row — including ones `TimelineStore.moveRegion` refuses (kind
    /// mismatch, out of bounds, bio lane) — so the clip visibly landed there and
    /// JUMPED BACK at release. This mirrors the store's acceptance exactly:
    /// a legal target returns the shift, everything else returns 0 (the store
    /// keeps the lane and applies only the time move — preview == commit).
    public static func gatedLaneShift(fromPoints height: CGFloat, laneHeight: CGFloat,
                                      laneIndex: Int, gates: [LaneGate]) -> Int {
        let raw = laneShift(fromPoints: height, laneHeight: laneHeight)
        guard raw != 0, gates.indices.contains(laneIndex) else { return 0 }
        let target = laneIndex + raw
        guard gates.indices.contains(target),
              gates[target].kind == gates[laneIndex].kind,
              !gates[target].isBio else { return 0 }
        return raw
    }

    /// The horizontal preview delta (points) for a body move: the clip draws at
    /// the grid-snapped start tick its release will commit (`.off` = stepless,
    /// clamped ≥ 0 like the commit).
    ///
    /// Neighbour-edge magnetism (#56 C6): when `neighbourEdges` is supplied (the
    /// raw start/end ticks of the OTHER regions in this lane, self excluded — a
    /// user-rate value captured by the PARENT, never a per-frame store read in
    /// the leaf), the preview magnetizes to a neighbour edge exactly as the
    /// commit does: each edge and `edge - lengthTicks` (so OUR end can kiss an
    /// edge too) is a candidate, and one within `magnetPoints` screen-points that
    /// is at least as close as the grid pull wins. This closes the last residual
    /// release jump (the magnet was previously commit-only). Empty `neighbourEdges`
    /// → pure grid behaviour, unchanged. The caller passes `[]` on a lane change
    /// so the preview matches the commit's plain-grid branch there.
    public static func movePreviewDeltaX(rawDeltaX: CGFloat, startTick: Int,
                                         ppb: CGFloat, snap: SnapResolution,
                                         neighbourEdges: [Int] = [],
                                         lengthTicks: Int = 0,
                                         magnetPoints: CGFloat = 8) -> CGFloat {
        let raw = Swift.max(0, startTick + tickDelta(fromPoints: rawDeltaX, ppb: ppb))
        let committed: Int
        if neighbourEdges.isEmpty || !(ppb.isFinite && ppb > 0) {
            committed = snap == .off ? raw : TimelineSnap.snap(raw, to: snap)
        } else {
            let magnetTicks = Swift.max(0,
                Int((magnetPoints / ppb * CGFloat(TimelineTime.ticksPerBeat)).rounded()))
            let candidates = neighbourEdges.flatMap { [$0, $0 - lengthTicks] }
            committed = TimelineSnap.snapWithEdges(raw, to: snap,
                                                   edges: candidates, magnetTicks: magnetTicks)
        }
        return CGFloat(committed - startTick) * pointsPerTick(ppb: ppb)
    }

    // MARK: - Trailing trim (right edge)

    /// The preview WIDTH delta (points) for a trailing trim: the edge draws at
    /// the snapped length its release will commit, floored at `minTicks`
    /// (the commit floors at one transport step).
    ///
    /// Neighbour-edge magnetism (#56 C7): when `neighbourEdges` is supplied (the
    /// raw start/end ticks of the OTHER regions in this lane, self excluded — the
    /// SAME parent-captured value the move preview uses, never a per-frame store
    /// read), the trailing edge magnetizes so the clip's END kisses a neighbour
    /// edge (butt-join), exactly as the commit does: each edge becomes a LENGTH
    /// candidate `edge - startTick`, and one within `magnetPoints` that is at
    /// least as close as the grid pull wins. Empty `neighbourEdges` → pure grid,
    /// unchanged.
    public static func trailingTrimPreviewDeltaW(rawDeltaX: CGFloat, lengthTicks: Int,
                                                 ppb: CGFloat, snap: SnapResolution,
                                                 minTicks: Int = TimelineTime.ticksPerTransportStep,
                                                 neighbourEdges: [Int] = [],
                                                 startTick: Int = 0,
                                                 magnetPoints: CGFloat = 8)
        -> CGFloat {
        let raw = lengthTicks + tickDelta(fromPoints: rawDeltaX, ppb: ppb)
        let snappedOrEdge: Int
        if neighbourEdges.isEmpty || !(ppb.isFinite && ppb > 0) {
            snappedOrEdge = snap == .off ? raw : TimelineSnap.snap(raw, to: snap)
        } else {
            let magnetTicks = Swift.max(0,
                Int((magnetPoints / ppb * CGFloat(TimelineTime.ticksPerBeat)).rounded()))
            // Neighbour edges as a LENGTH from our start → our END kisses the edge.
            let candidates = neighbourEdges.map { $0 - startTick }
            snappedOrEdge = TimelineSnap.snapWithEdges(raw, to: snap,
                                                       edges: candidates, magnetTicks: magnetTicks)
        }
        let committed = Swift.max(minTicks, snappedOrEdge)
        return CGFloat(committed - lengthTicks) * pointsPerTick(ppb: ppb)
    }

    // MARK: - Front trim (left edge, end fixed)

    /// The preview X/width delta (points) for a front trim: the edge draws at the
    /// snapped start its release will commit, clamped to keep ≥ 1 tick and to
    /// never reveal media before its start (mirrors `trimmedStart`).
    /// Positive = trim (start moves right, width shrinks), negative = extend.
    ///
    /// Media clamp, in the tick domain, mirroring `trimmedStart` exactly (which
    /// now also prefers the twin): an exact tick twin (`contentOffsetTicks` > 0,
    /// M1b) gives the precise floor at ANY tempo; a genuinely zero offset (twin 0
    /// AND seconds 0 — every fresh region, all MIDI) can only trim, never extend
    /// (floor = the current start); ONLY a legacy seconds-only region (seconds >
    /// 0, twin 0) previews without the media floor and lets the commit clamp —
    /// reading the tempo for the seconds→ticks conversion in a leaf BODY is
    /// forbidden (bio→tempo modulates live).
    public static func frontTrimPreviewDeltaX(rawDeltaX: CGFloat, startTick: Int,
                                              endTick: Int, contentOffsetTicks: Int,
                                              contentOffsetSeconds: Double,
                                              ppb: CGFloat, snap: SnapResolution,
                                              neighbourEdges: [Int] = [],
                                              magnetPoints: CGFloat = 8) -> CGFloat {
        let raw = startTick + tickDelta(fromPoints: rawDeltaX, ppb: ppb)
        // #56 C8: the LEADING edge magnetizes to neighbour clip edges (butt-join
        // to the clip on the left), completing the move/trailing/front trilogy.
        // The start tick lands DIRECTLY on a neighbour edge (no length transform),
        // BEFORE the media/end clamps below — so a magnet that would trim past the
        // media floor is clamped identically to the grid path (C4 parity holds for
        // any proposed start). Empty `neighbourEdges` → pure grid, unchanged.
        let snapped: Int
        if neighbourEdges.isEmpty || !(ppb.isFinite && ppb > 0) {
            snapped = snap == .off ? Swift.max(0, raw) : TimelineSnap.snap(raw, to: snap)
        } else {
            let magnetTicks = Swift.max(0,
                Int((magnetPoints / ppb * CGFloat(TimelineTime.ticksPerBeat)).rounded()))
            snapped = TimelineSnap.snapWithEdges(raw, to: snap,
                                                 edges: neighbourEdges, magnetTicks: magnetTicks)
        }
        let minStart: Int
        if contentOffsetTicks > 0 {
            minStart = Swift.max(0, startTick - contentOffsetTicks)
        } else if contentOffsetSeconds <= 0 {
            minStart = startTick   // zero offset: trim only, never front-extend
        } else {
            minStart = 0           // legacy seconds-only: commit applies the clamp
        }
        let committed = Swift.min(Swift.max(snapped, minStart), endTick - 1)
        return CGFloat(committed - startTick) * pointsPerTick(ppb: ppb)
    }
}
