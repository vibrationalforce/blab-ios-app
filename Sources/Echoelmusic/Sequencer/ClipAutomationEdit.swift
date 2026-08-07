// ClipAutomationEdit.swift
// Automation-in-Spur L1 / S2a (Founder REIHENFOLGE item 1): the pure ARRAY-level
// edit brain for a clip's automation lanes. The clip-scoped automation editor
// (S2b, the SwiftUI canvas) turns a tap/drag/delete over a clip-span canvas into
// a whole new `[AutomationLane]` and hands it to `ClipStore.setClipAutomation`
// (S1). This file is that transform — pure, Foundation-only, Linux-CI-testable —
// so the View stays a thin gesture→math→store shell (same doctrine as
// AutomationCanvasMath / RollNoteOps / TimelineAutomationRowMath).
// ⛔ That last name read "TimelineAutomationRow's static helpers" and had been wrong
// since #472 hoisted them into `Sequencer/TimelineAutomationRowMath.swift`; #473 then
// deleted the view entirely, so it was pointing at nothing at all. A doctrine sentence
// that cites a vanished file teaches the doctrine and then discredits it in the same
// breath.
//
// Contract: one lane per parameter. Geometry (tick↔x, value↔y, snapping) is
// AutomationCanvasMath's, span-relative to the CLIP's length (`spanTicks`), so a
// keyframe can never land outside the clip. Value/tick clamping is inherited from
// AutomationLane/AutomationPoint (they clamp on construction + on setValue), so
// this layer never re-clamps.

import Foundation

public enum ClipAutomationEdit {

    /// Index of the lane driving `parameter`, if the clip already has one.
    public static func laneIndex(for parameter: String,
                                 in lanes: [AutomationLane]) -> Int? {
        lanes.firstIndex { $0.parameter == parameter }
    }

    /// Add — or, if a keyframe already sits on the snapped tick, UPDATE — a point
    /// for `parameter` at `tick` (snapped into the clip span) with normalized
    /// `value`. Creates the lane if this parameter has none yet. Returns the whole
    /// new lanes array for `ClipStore.setClipAutomation`. Re-drawing over the same
    /// step replaces that step's value instead of stacking a duplicate point (DAW
    /// behavior); a different step adds a keyframe. The collision test is exact
    /// `==` on the SNAPPED tick — valid because every point this editor inserts is
    /// snapped (upsert here, and `movePoint`), so stored ticks are snap-aligned.
    /// On the update branch only the value changes; `curve` is intentionally kept
    /// (a redraw is a value edit, not a curve reset).
    public static func upsertPoint(_ lanes: [AutomationLane], parameter: String,
                                   tick: Int, value: Double,
                                   curve: AutomationCurve = .linear,
                                   spanTicks: Int) -> [AutomationLane] {
        let snapped = AutomationCanvasMath.snappedTick(tick, spanTicks: spanTicks)
        var out = lanes
        if let i = laneIndex(for: parameter, in: out) {
            if let existing = out[i].points.first(where: { $0.tick == snapped }) {
                out[i].setValue(id: existing.id, value)
            } else {
                out[i].addPoint(tick: snapped, value: value, curve: curve)
            }
        } else {
            var lane = AutomationLane(parameter: parameter)
            lane.addPoint(tick: snapped, value: value, curve: curve)
            out.append(lane)
        }
        return out
    }

    /// Move a keyframe (by id) to a new snapped tick and value — the drag commit.
    /// No-op if no lane holds the id. Returns the whole new lanes array.
    public static func movePoint(_ lanes: [AutomationLane], id: UUID,
                                 toTick tick: Int, value: Double,
                                 spanTicks: Int) -> [AutomationLane] {
        let snapped = AutomationCanvasMath.snappedTick(tick, spanTicks: spanTicks)
        var out = lanes
        for i in out.indices where out[i].points.contains(where: { $0.id == id }) {
            out[i].movePoint(id: id, toTick: snapped)
            out[i].setValue(id: id, value)
        }
        return out
    }

    /// Delete a keyframe (by id) — the double-tap. By default ANY empty lane in
    /// the array is then pruned (whole-array sweep), so a cleared parameter
    /// doesn't linger as a dead empty lane in `clip.automation`. Under the normal
    /// invariant lanes are never empty except the one just emptied, so this only
    /// drops that one; pass `pruneEmptyLanes: false` to keep empties verbatim.
    /// Returns the whole new lanes array.
    public static func removePoint(_ lanes: [AutomationLane], id: UUID,
                                   pruneEmptyLanes: Bool = true) -> [AutomationLane] {
        var out = lanes
        for i in out.indices { out[i].removePoint(id: id) }
        if pruneEmptyLanes { out.removeAll { $0.isEmpty } }
        return out
    }

    /// Bend the segment leaving a keyframe (Ableton-style curvature drag), −1…1.
    /// No-op if no lane holds the id. Returns the whole new lanes array.
    public static func setCurvature(_ lanes: [AutomationLane], id: UUID,
                                    _ curvature: Double) -> [AutomationLane] {
        var out = lanes
        for i in out.indices where out[i].points.contains(where: { $0.id == id }) {
            out[i].setCurvature(id: id, curvature)
        }
        return out
    }
}
