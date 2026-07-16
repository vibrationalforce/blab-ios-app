// TimelineDragMath.swift
// Echoel — jitter audit #56 C4 ("stepless live preview vs snapped+clamped commit
// → jump at every release"): the PURE live-preview math for the three region
// gestures. During a drag the clip now previews at the SAME snapped/clamped
// position its release will commit, so letting go is a visual no-op instead of
// a half-grid-cell jump.
//
// Foundation-only, no SwiftUI, no store — unit-tested on Linux CI. The view
// keeps its raw @GestureState finger deltas and derives the drawn delta through
// these functions in body (a few integer ops per frame, leaf-local).
//
// HONEST SCOPE (documented deltas from the commit path, both release-safe):
// • Neighbour-edge magnetism (snapWithEdges, ±8 pt) stays COMMIT-ONLY — the
//   live preview would need per-frame store reads for the edge candidates
//   (freeze-law). Residual release motion: at most the small magnet pull,
//   not the half-cell grid jump this slice removes.
// • The front-trim min-start clamp uses the EXACT tick twin
//   (`contentOffsetTicks`, M1b) when present; a legacy region (tick twin 0,
//   seconds-only offset) previews without that clamp and the commit clamps —
//   reading the tempo in a leaf BODY is forbidden (bio→tempo modulates it
//   live; a body read would churn every clip leaf at modulation rate).

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

    /// The horizontal preview delta (points) for a body move: the clip draws at
    /// the grid-snapped start tick its release will commit (`.off` = stepless,
    /// clamped ≥ 0 like the commit). Edge magnetism is commit-only (see header).
    public static func movePreviewDeltaX(rawDeltaX: CGFloat, startTick: Int,
                                         ppb: CGFloat, snap: SnapResolution) -> CGFloat {
        let raw = Swift.max(0, startTick + tickDelta(fromPoints: rawDeltaX, ppb: ppb))
        let committed = snap == .off ? raw : TimelineSnap.snap(raw, to: snap)
        return CGFloat(committed - startTick) * pointsPerTick(ppb: ppb)
    }

    // MARK: - Trailing trim (right edge)

    /// The preview WIDTH delta (points) for a trailing trim: the edge draws at
    /// the snapped length its release will commit, floored at `minTicks`
    /// (the commit floors at one transport step).
    public static func trailingTrimPreviewDeltaW(rawDeltaX: CGFloat, lengthTicks: Int,
                                                 ppb: CGFloat, snap: SnapResolution,
                                                 minTicks: Int = TimelineTime.ticksPerTransportStep)
        -> CGFloat {
        let raw = lengthTicks + tickDelta(fromPoints: rawDeltaX, ppb: ppb)
        let snapped = snap == .off ? raw : TimelineSnap.snap(raw, to: snap)
        let committed = Swift.max(minTicks, snapped)
        return CGFloat(committed - lengthTicks) * pointsPerTick(ppb: ppb)
    }

    // MARK: - Front trim (left edge, end fixed)

    /// The preview X/width delta (points) for a front trim: the edge draws at the
    /// snapped start its release will commit, clamped to keep ≥ 1 tick and to
    /// never reveal media before its start (mirrors `trimmedStart`).
    /// Positive = trim (start moves right, width shrinks), negative = extend.
    ///
    /// Media clamp, in the tick domain: an exact tick twin (`contentOffsetTicks`
    /// > 0, M1b) gives the precise floor; a genuinely zero offset (twin 0 AND
    /// seconds 0 — every fresh region, all MIDI) can only trim, never extend
    /// (floor = the current start, exactly like the commit); ONLY a legacy
    /// seconds-only region (seconds > 0, twin 0) previews without the media
    /// floor and lets the commit clamp — reading the tempo for the seconds→
    /// ticks conversion in a leaf BODY is forbidden (bio→tempo modulates live).
    public static func frontTrimPreviewDeltaX(rawDeltaX: CGFloat, startTick: Int,
                                              endTick: Int, contentOffsetTicks: Int,
                                              contentOffsetSeconds: Double,
                                              ppb: CGFloat, snap: SnapResolution) -> CGFloat {
        let raw = startTick + tickDelta(fromPoints: rawDeltaX, ppb: ppb)
        let snapped = snap == .off ? Swift.max(0, raw) : TimelineSnap.snap(raw, to: snap)
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
