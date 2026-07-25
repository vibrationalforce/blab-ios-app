// TimelineAutomationRow.swift
// Echoel — T1 of the timeline-automation plan (founder 2026-07-17: "Automations
// Sektionen sollten in der Timeline direkt sein oder? Das man im Verlauf des
// Tracks automatisieren kann."): the fold-out automation ROW under a track,
// drawing the song-absolute curve on the SAME tick→x scale as the clip row
// (x = tick · pxPerTick, pxPerTick = ppb / 480), with the A3 canvas gesture law
// (tap adds, drag moves, double-tap deletes). The precision-editor sheet that
// once complemented this row (typed values, curve/hold, segment bend) was deleted
// with the DAW UI (#121, Slice 4 / 4d); this row itself is now unmounted too and
// retires in the Slice 6 cleanup — only `TimelineAutomationRowMath` stays (live,
// read by `Core/TimelineStore.swift`).
//
// DATA MODEL (honest): timeline automation lives in `TimelineDocument.automation`
// — parameter-keyed, DOCUMENT-wide, song-absolute. GLOBAL targets (master level,
// tempo, router-bound registry params) are one curve shared across tracks by
// design. L2/L4: a SECONDARY lane may additionally pick a PER-TRACK target — the
// rack-voice params namespaced as `track.<laneID>.<base>` — so drawing on that
// track moves only that track's voice (the shared-curve debt is resolved where it
// matters). The picker offers per-track targets only for lanes that own a rack
// slot (never the roll lane / a global-only param).
//
// Render safety: the row reads only edit-frequency state (document points,
// zoom). No playhead / bio read anywhere in these bodies — the shared
// TimelinePlayhead overlay already sweeps across this row from the grid above.
// Edits COMMIT once per gesture (tap / drag-release), never per drag frame: a
// TimelineStore persist is a structural change and a playing song relocates on
// it (HARNESS_LEDGER 2026-07-16 — relocate storms). The live drag previews
// through @GestureState (auto-reset on a stolen/cancelled drag, jitter audit
// #56 C2).
//
// The geometry/touch law is pure (`TimelineAutomationRowMath`, Foundation-only,
// Linux-CI-tested — pattern: RollFitMath / AutomationCanvasMath); value↔y reuses
// AutomationCanvasMath's tested mapping.

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
    public static func sameParameter(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard let ta = AutomationTarget.forParameter(a) else { return false }
        return ta == AutomationTarget.forParameter(b)
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// One selectable automation target for the row's compact picker: the three
/// legacy enum targets plus every router-BOUND registry descriptor (placebo law —
/// only parameters that actually move audio are listed;
/// `extraAutomatableDescriptors` enforces it).
struct TimelineAutomationTargetOption: Identifiable {
    let parameter: String
    let displayName: String
    var id: String { parameter }

    /// Build the catalog from the shared AutomationPlayer — one source, no
    /// second list to drift from the sheet's picker.
    ///
    /// `perTrackLaneID` (L2/L4): when non-nil, ALSO offer this lane's own per-track
    /// targets — the rack-voice-automatable params namespaced as
    /// `track.<laneID>.<base>`, so drawing on THIS track moves only THIS track's
    /// voice (resolving the shared-curve debt). Pass it ONLY for a SECONDARY lane
    /// that owns a rack slot (the roll lane owns none → its per-track keyPath is a
    /// dead no-op, so it is never offered — placebo law).
    @MainActor
    static func catalog(_ automation: AutomationPlayer,
                        perTrackLaneID: UUID? = nil,
                        laneLabel: String = "") -> [TimelineAutomationTargetOption] {
        let global = AutomationTarget.allCases.map {
            TimelineAutomationTargetOption(parameter: $0.rawValue, displayName: $0.displayName)
        }
        + automation.extraAutomatableDescriptors.map {
            TimelineAutomationTargetOption(parameter: $0.keyPath, displayName: $0.displayName)
        }
        guard let laneID = perTrackLaneID else { return global }
        // Only the rack-voice-automatable params (PolySynthVoice.automatableBases)
        // resolve to a per-track write; namespace exactly those for this lane.
        let eligible = automation.extraAutomatableDescriptors.filter {
            PolySynthVoice.automatableBases.contains($0.keyPath)
        }
        let perTrack = PerTrackParameterKeyPath
            .descriptors(for: laneID, laneLabel: laneLabel, from: eligible)
            .map { TimelineAutomationTargetOption(parameter: $0.keyPath, displayName: $0.displayName) }
        return global + perTrack
    }
}

/// The label-column cell of an open automation row (sits under the track head,
/// fixed width, never scrolls horizontally): compact target picker (Menu — the
/// existing catalog), the "⋯" door to the precision sheet (the caller routes it
/// into the EXISTING `.automation` modal slot — no new sheet, metadata law),
/// and the fold-up chevron.
@MainActor
struct TimelineAutomationHeadCell: View {
    let laneName: String
    @Binding var selectedParameter: String
    /// When non-nil, the picker also offers this lane's per-track targets (L2/L4).
    /// Pass ONLY for a secondary lane that owns a rack slot (never the roll lane).
    var perTrackLaneID: UUID? = nil
    /// Opened the precision-editor sheet (deleted in #121 Slice 4/4d); no
    /// caller remains — this cell retires in the Slice 6 cleanup.
    let onOpenEditor: () -> Void
    /// Folds the row back up.
    let onClose: () -> Void
    /// Width of the head column — MUST match the lane head's adaptive `headWidth`
    /// (162 iPhone / 184 iPad) so this open-automation-row cell stays pixel-aligned
    /// under the track head. Declared last so the memberwise init keeps it trailing;
    /// defaults to 140 only for back-compat / previews.
    var columnWidth: CGFloat = 140

    @Environment(AutomationPlayer.self) private var automation

    var body: some View {
        let options = TimelineAutomationTargetOption.catalog(
            automation, perTrackLaneID: perTrackLaneID, laneLabel: laneName)
        let current = options.first {
            TimelineAutomationRowMath.sameParameter($0.parameter, selectedParameter)
        }
        VStack(alignment: .leading, spacing: 3) {
            Menu {
                ForEach(options) { option in
                    Button {
                        selectedParameter = option.parameter
                    } label: {
                        if current?.parameter == option.parameter {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Text(option.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(EchoelTheme.dim)
                    Text(current?.displayName ?? "Automation")
                        .font(EchoelTheme.font(10, .medium))
                        .foregroundStyle(EchoelTheme.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(EchoelTheme.dim)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Automation target for \(laneName)")
            HStack(spacing: 3) {
                Button(action: onOpenEditor) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(EchoelTheme.dim)
                        .frame(width: 26, height: 22)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                            .fill(EchoelTheme.fill))
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                            .strokeBorder(EchoelTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open the automation editor")
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(EchoelTheme.dim)
                        .frame(width: 26, height: 22)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                            .fill(EchoelTheme.fill))
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                            .strokeBorder(EchoelTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide automation for \(laneName)")
            }
        }
        .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 6)
        .frame(width: columnWidth, height: TimelineAutomationRow.rowHeight)
        .overlay(alignment: .bottom) { Divider().overlay(EchoelTheme.border) }
    }
}

/// The grid-column canvas of an open automation row: the selected parameter's
/// song-absolute curve over the whole song width, bar grid behind it, edited
/// with the A3 touch law (tap adds a snapped keyframe, dragging a point moves
/// it, double-tap deletes). Segment BEND and typed values stay in the sheet —
/// this row is the fast lane, not a second precision editor.
@MainActor
struct TimelineAutomationRow: View {
    /// The selected parameter's timeline lane points ([] = empty state).
    let points: [AutomationPoint]
    /// Zoom: screen points per quarter-note beat — the parent's `ppb`, so the
    /// x-scale equals the clip row's by construction.
    let ppb: CGFloat
    /// Bars drawn (the parent's `barCount`) — row width = grid width.
    let barCount: Int
    /// The surface's snap magnet (`.off` = stepless), applied to added/moved ticks.
    let snap: SnapResolution
    /// Commit callbacks — the parent routes them into TimelineStore's
    /// automation API (one persisted command per finished gesture).
    let onAdd: (_ tick: Int, _ value: Double) -> Void
    let onMove: (_ id: UUID, _ tick: Int, _ value: Double) -> Void
    let onDelete: (_ id: UUID) -> Void

    static let rowHeight: CGFloat = 64

    /// Live drag preview — @GestureState so a drag the ScrollView steals
    /// auto-resets (jitter audit #56 C2); nothing commits until release.
    private struct DragPreview {
        var movingID: UUID?
        var location: CGPoint
        var travel: Double
    }
    @GestureState private var drag: DragPreview?

    /// Double-tap detection (A3 pattern — one drag gesture handles everything;
    /// a competing TapGesture(count: 2) would race the zero-distance drag).
    @State private var lastTapTime: Date?
    @State private var lastTapLocation: CGPoint = .zero
    private static let doubleTapWindow: TimeInterval = 0.4

    private var pxPerTick: Double { Double(ppb) / Double(TimelineTime.ticksPerBeat) }
    private var spanTicks: Int { max(1, barCount) * TimelineTime.ticksPerBar }
    private var rowWidth: CGFloat { CGFloat(max(1, barCount) * TimelineTime.beatsPerBar) * ppb }

    var body: some View {
        Canvas { ctx, size in
            drawGrid(ctx, size)
            drawCurveAndPoints(ctx, size)
        }
        .frame(width: rowWidth, height: Self.rowHeight, alignment: .topLeading)
        .background(EchoelTheme.fill.opacity(0.5))
        .contentShape(Rectangle())
        .gesture(editGesture)
        .overlay(alignment: .bottom) { Divider().overlay(EchoelTheme.border) }
        .accessibilityLabel("Automation curve: tap adds a keyframe, drag moves it, double-tap deletes")
    }

    // MARK: Gesture (commit once per gesture — never per drag frame)

    private var editGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($drag) { g, state, _ in
                if state == nil {
                    // Classify ONCE at the start location (pure, re-derivable).
                    let id = TimelineAutomationRowMath.hitPointID(
                        atX: Double(g.startLocation.x), y: Double(g.startLocation.y),
                        points: points, pxPerTick: pxPerTick,
                        height: Double(Self.rowHeight))
                    state = DragPreview(movingID: id, location: g.location, travel: 0)
                } else {
                    state?.location = g.location
                }
                state?.travel = Double((g.translation.width * g.translation.width
                    + g.translation.height * g.translation.height)).squareRoot()
            }
            .onEnded { g in handleEnded(g) }
    }

    /// Snapped song tick for a canvas x (the surface's magnet; `.off` = stepless).
    private func committedTick(forX x: Double) -> Int {
        let raw = TimelineAutomationRowMath.tick(forX: x, pxPerTick: pxPerTick,
                                                 maxTick: spanTicks)
        return snap == .off ? raw : min(TimelineSnap.snap(raw, to: snap), spanTicks)
    }

    private func handleEnded(_ g: DragGesture.Value) {
        // Re-derive the touch-down classification (deterministic — @GestureState
        // may already be reset when onEnded runs).
        let hitID = TimelineAutomationRowMath.hitPointID(
            atX: Double(g.startLocation.x), y: Double(g.startLocation.y),
            points: points, pxPerTick: pxPerTick, height: Double(Self.rowHeight))
        let travel = Double((g.translation.width * g.translation.width
            + g.translation.height * g.translation.height)).squareRoot()
        let tick = committedTick(forX: Double(g.location.x))
        let value = AutomationCanvasMath.value(forY: Double(g.location.y),
                                               height: Double(Self.rowHeight))

        if travel > TimelineAutomationRowMath.tapSlopPoints {
            // A real drag: commit the move ONCE (only when it started on a point).
            if let id = hitID { onMove(id, tick, value) }
            lastTapTime = nil
            return
        }

        // Sub-slop release = a tap. Two taps close in time + space = double-tap.
        let dx = Double(g.location.x - lastTapLocation.x)
        let dy = Double(g.location.y - lastTapLocation.y)
        let isDouble = lastTapTime.map {
            g.time.timeIntervalSince($0) <= Self.doubleTapWindow
                && (dx * dx + dy * dy).squareRoot()
                    <= TimelineAutomationRowMath.touchRadius * 1.5
        } ?? false

        if let id = hitID {
            // Double-tap ON a point deletes it (an empty-space double-tap is
            // self-healing, A3 law: tap 1 adds, tap 2 lands on it and removes).
            if isDouble {
                onDelete(id)
                lastTapTime = nil
                return
            }
        } else {
            onAdd(tick, value)
        }
        lastTapTime = g.time
        lastTapLocation = g.location
    }

    // MARK: Drawing

    private func drawGrid(_ ctx: GraphicsContext, _ size: CGSize) {
        var grid = Path()
        for bar in 0...max(1, barCount) {
            let x = CGFloat(bar * TimelineTime.beatsPerBar) * ppb
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
        }
        ctx.stroke(grid, with: .color(EchoelTheme.text.opacity(0.10)), lineWidth: 1)
        var mid = Path()
        mid.move(to: CGPoint(x: 0, y: size.height / 2))
        mid.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        ctx.stroke(mid, with: .color(EchoelTheme.border), lineWidth: 1)
    }

    private func drawCurveAndPoints(_ ctx: GraphicsContext, _ size: CGSize) {
        // Mid-drag: render the moving point at its live (snapped) preview spot.
        var shown = points
        if let drag, let id = drag.movingID,
           drag.travel > TimelineAutomationRowMath.tapSlopPoints {
            shown = TimelineAutomationRowMath.displayPoints(
                points, movingID: id,
                toTick: committedTick(forX: Double(drag.location.x)),
                value: AutomationCanvasMath.value(forY: Double(drag.location.y),
                                                  height: Double(Self.rowHeight)))
        }
        guard !shown.isEmpty else {
            let t = Text("Tap to add automation").font(EchoelTheme.font(11))
                .foregroundStyle(EchoelTheme.dim)
            // Anchor the hint near the left edge — the row can be many screens
            // wide, and a horizontally centered hint would sit off-screen.
            ctx.draw(t, at: CGPoint(x: 90, y: size.height / 2))
            return
        }

        // Evaluate through the lane's own tested interpolation (hold / linear /
        // curvature) — segment-wise sampling, bounded work per segment.
        let lane = AutomationLane(parameter: "row.preview", points: shown)
        var path = Path()
        func pt(_ tick: Int) -> CGPoint {
            CGPoint(x: TimelineAutomationRowMath.x(forTick: tick, pxPerTick: pxPerTick),
                    y: AutomationCanvasMath.y(forValue: lane.value(atTick: tick) ?? 0,
                                              height: Double(size.height)))
        }
        let sorted = lane.points
        guard let first = sorted.first, let last = sorted.last else { return }
        path.move(to: CGPoint(x: 0, y: AutomationCanvasMath.y(forValue: first.value,
                                                              height: Double(size.height))))
        path.addLine(to: pt(first.tick))
        for (p0, p1) in zip(sorted, sorted.dropFirst()) {
            let span = p1.tick - p0.tick
            if span <= 0 { continue }
            if p0.curve == .hold || p0.curvature == 0 {
                // Step or straight line — exact with 2 anchors.
                path.addLine(to: pt(max(p0.tick, p1.tick - 1)))
                path.addLine(to: pt(p1.tick))
            } else {
                let samples = 16
                for s in 1...samples {
                    path.addLine(to: pt(p0.tick + span * s / samples))
                }
            }
        }
        path.addLine(to: CGPoint(x: size.width,
                                 y: AutomationCanvasMath.y(forValue: last.value,
                                                           height: Double(size.height))))
        ctx.stroke(path, with: .color(EchoelTheme.accent), lineWidth: 2)

        for p in sorted {
            let c = pt(p.tick)
            let dot = Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
            ctx.fill(dot, with: .color(EchoelTheme.accent))
            ctx.stroke(dot, with: .color(EchoelTheme.bg), lineWidth: 1.5)
        }
    }
}
#endif
