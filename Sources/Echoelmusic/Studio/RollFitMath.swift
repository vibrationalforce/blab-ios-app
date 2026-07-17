// RollFitMath.swift
// Echoel — pure layout math behind the piano roll's ADAPTIVE fit (founder
// 2026-07-17: "Piano Roll passt immer noch nicht in den Bildschirm … adaptives
// Design"). Foundation-only, the same law as RollHitTest / AutomationCanvasMath:
// every boundary is unit-tested on CI without a SwiftUI host. The view feeds
// measured sizes IN and gets clamped cell metrics + scroll targets OUT — no
// view state lives here.
//
// Fit decision (documented per the 2026-07-17 mandate): `PianoRollModel.stepCount`
// is a fixed 16 — the roll is always ONE bar (multi-bar clips edit bar-by-bar
// through ClipEditSession/MelodyBarEdit). So "fit" always means the WHOLE bar:
// 16 × minStepW(16pt) + gutter(42pt) = 298pt, under every iPhone width. A
// partial-bar fit mode for stepCount > 32 is deliberately absent — that count
// cannot occur today.

import Foundation

public enum RollFitMath {

    /// Step width that fits `stepCount` steps into the width left of the pitch
    /// gutter. Clamped to `[minStepW, maxStepW]`; degenerate inputs (zero or
    /// negative usable width, non-finite width, stepCount ≤ 0) fall back to
    /// `minStepW` so the roll always renders.
    public static func fittedStepW(availableWidth: Double, gutterWidth: Double,
                                   stepCount: Int,
                                   minStepW: Double, maxStepW: Double) -> Double {
        guard stepCount > 0, availableWidth.isFinite, gutterWidth.isFinite,
              availableWidth - gutterWidth > 0 else { return minStepW }
        let raw = (availableWidth - gutterWidth) / Double(stepCount)
        return min(max(raw, minStepW), maxStepW)
    }

    /// Row height that shows about `targetRows` pitch rows in the available
    /// height. The full 49-row ladder can never fit a phone legibly — the roll
    /// scrolls vertically BY DESIGN; this only couples row density to the
    /// screen (small screen → denser, tall screen → roomier), clamped to a
    /// readable band.
    public static func fittedRowH(availableHeight: Double, targetRows: Int,
                                  minRowH: Double, maxRowH: Double) -> Double {
        guard targetRows > 0, availableHeight.isFinite, availableHeight > 0
        else { return minRowH }
        let raw = availableHeight / Double(targetRows)
        return min(max(raw, minRowH), maxRowH)
    }

    /// The pitch row the roll vertically centers on when opening: the median
    /// of the take's pitches (lower median for even counts — a real note row,
    /// never an in-between average). Empty clip → `fallback` (the C4 region),
    /// so the editor never opens "somewhere in the void".
    public static func medianPitch(of pitches: [Int], fallback: Int) -> Int {
        guard !pitches.isEmpty else { return fallback }
        let sorted = pitches.sorted()
        return sorted[(sorted.count - 1) / 2]
    }

    /// Content-Y scroll offset that centers `targetCenterY` in the viewport,
    /// clamped so the scroller never overshoots either content edge. Content
    /// that fits entirely (or degenerate viewport) → 0 (top).
    public static func centeredOffsetY(targetCenterY: Double, visibleHeight: Double,
                                       contentHeight: Double) -> Double {
        guard visibleHeight > 0, targetCenterY.isFinite,
              contentHeight > visibleHeight else { return 0 }
        let raw = targetCenterY - visibleHeight / 2
        return min(max(raw, 0), contentHeight - visibleHeight)
    }
}
