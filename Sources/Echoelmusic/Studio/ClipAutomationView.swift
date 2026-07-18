// ClipAutomationView.swift
// Automation-in-Spur L1 / S2b (Founder REIHENFOLGE item 1, "im Clip … man zeichnet
// wie in Ableton"): the DRAW-into-the-clip automation editor. A clip already
// CARRIES + PLAYS `Clip.automation` (setClipAutomation from every launch path);
// this is the drawing surface that authors it. Presented from the region
// long-press menu via the single `ArrangeModal.clipAutomation` case (NO new
// `.sheet` — the metadata law).
//
// The gesture + drawing law is `AutomationView.AutomationCanvas`'s, re-pointed:
//   • geometry is span-relative to the CLIP (`spanTicks`), not one bar,
//   • every edit goes through the pure, tested `ClipAutomationEdit` (whole
//     [AutomationLane] in/out) → `ClipStore.setClipAutomation` (persist, next-
//     onset audible),
//   • targets are the router-bound EchoelParameterRegistry params (per-instrument
//     "alle Parameter via Registry"), NOT the global master/tempo enum.
// Values are normalized [0…1] on the canvas; the clip lane stores normalized.
//
// This is a presented modal (not the always-on root), and it reads ClipStore
// (which changes only on user edits, never at 10 Hz) — the menu-freeze law
// (10 Hz bio read in an ancestor) does not apply here.

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct ClipAutomationView: View {

    let clipID: UUID
    let spanTicks: Int

    @Environment(ClipStore.self) private var clips
    @Environment(AutomationPlayer.self) private var automation
    @Environment(\.dismiss) private var dismiss

    @State private var selectedParameter: String = ""

    /// Router-bound registry params (the ones with a live setter — no dead
    /// lanes). Pure lookups, no live reads.
    private var targets: [ParameterDescriptor] { automation.extraAutomatableDescriptors }

    private var currentLanes: [AutomationLane] { clips.clip(id: clipID)?.automation ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if targets.isEmpty {
                        Text("No automatable parameters are available yet.")
                            .font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.dim)
                    } else {
                        targetPicker
                        ClipAutomationCanvas(clipID: clipID, spanTicks: spanTicks,
                                             parameter: resolvedParameter)
                        clearRow
                        Text("Draw the parameter over the clip: tap adds a point, drag moves it, a vertical drag between two points bends the curve, double-tap deletes. The curve plays whenever the clip plays — it travels with the clip.")
                            .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                    }
                }
                .padding(16)
            }
            .background(EchoelTheme.bg.ignoresSafeArea())
            .navigationTitle("Clip Automation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear {
            if selectedParameter.isEmpty { selectedParameter = targets.first?.keyPath ?? "" }
        }
    }

    /// The selected keyPath, defaulting to the first target (until onAppear runs).
    private var resolvedParameter: String {
        selectedParameter.isEmpty ? (targets.first?.keyPath ?? "") : selectedParameter
    }

    @ViewBuilder private var targetPicker: some View {
        HStack {
            Text("Parameter").font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.dim)
            Spacer()
            // Drive selection from `resolvedParameter` so it ALWAYS matches a
            // live tag (falls back to targets.first) — no transient "" selection
            // that SwiftUI logs as an invalid/unmatched tag on first appearance.
            Picker("Parameter", selection: Binding(
                get: { resolvedParameter },
                set: { selectedParameter = $0 }
            )) {
                ForEach(targets, id: \.keyPath) { d in Text(d.displayName).tag(d.keyPath) }
            }
            .pickerStyle(.menu)
            .tint(EchoelTheme.text)
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    @ViewBuilder private var clearRow: some View {
        let has = currentLanes.contains { $0.parameter == resolvedParameter && !$0.isEmpty }
        if has {
            Button("Clear this parameter") {
                let kept = currentLanes.filter { $0.parameter != resolvedParameter }
                _ = clips.setClipAutomation(id: clipID, lanes: kept)
            }
            .font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.danger)
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Drawable clip canvas (mirrors AutomationView.AutomationCanvas, clip-scoped)

@MainActor
private struct ClipAutomationCanvas: View {

    let clipID: UUID
    let spanTicks: Int
    let parameter: String

    @Environment(ClipStore.self) private var clips

    private enum DragMode {
        case movePoint(UUID)
        case bendSegment(id: UUID, startCurvature: Double, rising: Bool)
        case tap
    }
    @State private var dragMode: DragMode?
    @State private var lastTapTime: Date?
    @State private var lastTapLocation: CGPoint = .zero
    /// In-flight working copy during a move/bend drag. Holds the edit in memory
    /// so the canvas redraws every frame, but `ClipStore.setClipAutomation`
    /// (a synchronous full-`[Clip?]` JSON encode + encrypted disk write on the
    /// MainActor) fires ONCE on drag-end — not per `onChanged` frame (which would
    /// re-serialize the whole clip document dozens of times/sec → drag jank).
    @State private var draft: [AutomationLane]?

    private static let height = 140.0
    private static let touchRadius = 28.0
    private static let doubleTapWindow: TimeInterval = 0.4

    /// The clip's WHOLE lanes array — what ClipAutomationEdit transforms and
    /// ClipStore.setClipAutomation persists. During a drag it reflects the
    /// in-memory `draft` so drawing tracks the finger without touching disk.
    private var currentLanes: [AutomationLane] { draft ?? (clips.clip(id: clipID)?.automation ?? []) }
    private var lane: AutomationLane? { currentLanes.first { $0.parameter == parameter } }
    /// The selected lane's points — for hit-testing + drawing only.
    private var points: [AutomationPoint] { lane?.points ?? [] }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Canvas { ctx, size in
                drawGrid(ctx, size)
                drawCurve(ctx, size)
                drawPoints(ctx, size)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in handleChanged(g, width: w) }
                .onEnded { g in handleEnded(g, width: w) })
        }
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
        .accessibilityLabel("Clip automation canvas: tap adds a keyframe, drag moves, double-tap deletes")
    }

    // MARK: Gesture logic (edits go through the pure ClipAutomationEdit)

    private func travel(_ g: DragGesture.Value) -> Double {
        Double(g.translation.width * g.translation.width
               + g.translation.height * g.translation.height).squareRoot()
    }

    private func commit(_ lanes: [AutomationLane]) {
        _ = clips.setClipAutomation(id: clipID, lanes: lanes)
    }

    private func handleChanged(_ g: DragGesture.Value, width: CGFloat) {
        let w = Double(width)
        let pts = points
        if dragMode == nil {
            let sx = Double(g.startLocation.x), sy = Double(g.startLocation.y)
            if let hit = AutomationCanvasMath.nearestPoint(toX: sx, y: sy, points: pts,
                                                           width: w, height: Self.height,
                                                           spanTicks: spanTicks),
               hit.distance <= Self.touchRadius {
                dragMode = .movePoint(hit.id)
            } else if let left = AutomationCanvasMath.segmentLeftPoint(atX: sx, points: pts,
                                                                       width: w, spanTicks: spanTicks) {
                let sorted = pts.sorted { $0.tick < $1.tick }
                let right = sorted.first { $0.tick > left.tick }
                dragMode = .bendSegment(id: left.id, startCurvature: left.curvature,
                                        rising: (right?.value ?? left.value) > left.value)
            } else {
                dragMode = .tap
            }
        }
        guard travel(g) > AutomationCanvasMath.tapSlopPoints else { return }
        // Move/bend update the in-memory draft only — no disk write until drag-end.
        switch dragMode {
        case .movePoint(let id):
            let tick = AutomationCanvasMath.tick(forX: Double(g.location.x), width: w, spanTicks: spanTicks)
            let value = AutomationCanvasMath.value(forY: Double(g.location.y), height: Self.height)
            draft = ClipAutomationEdit.movePoint(currentLanes, id: id, toTick: tick,
                                                 value: value, spanTicks: spanTicks)
        case .bendSegment(let id, let start, let rising):
            let c = AutomationCanvasMath.bentCurvature(start: start,
                                                       dragUpPoints: -Double(g.translation.height),
                                                       risingSegment: rising)
            draft = ClipAutomationEdit.setCurvature(currentLanes, id: id, c)
        case .tap, .none:
            break
        }
    }

    private func handleEnded(_ g: DragGesture.Value, width: CGFloat) {
        let mode = dragMode
        let pendingDraft = draft
        dragMode = nil
        draft = nil
        // A move/bend drag: persist the accumulated draft ONCE here.
        if let pendingDraft, case .movePoint = mode { commit(pendingDraft) }
        if let pendingDraft, case .bendSegment = mode { commit(pendingDraft) }
        guard travel(g) <= AutomationCanvasMath.tapSlopPoints else { lastTapTime = nil; return }

        let dx = Double(g.location.x - lastTapLocation.x)
        let dy = Double(g.location.y - lastTapLocation.y)
        let isDouble = lastTapTime.map {
            g.time.timeIntervalSince($0) <= Self.doubleTapWindow
                && (dx * dx + dy * dy).squareRoot() <= Self.touchRadius * 1.5
        } ?? false

        switch mode {
        case .movePoint(let id):
            if isDouble {
                commit(ClipAutomationEdit.removePoint(currentLanes, id: id))
                lastTapTime = nil
                return
            }
        case .tap:
            let tick = AutomationCanvasMath.tick(forX: Double(g.location.x), width: Double(width), spanTicks: spanTicks)
            let value = AutomationCanvasMath.value(forY: Double(g.location.y), height: Self.height)
            commit(ClipAutomationEdit.upsertPoint(currentLanes, parameter: parameter,
                                                  tick: tick, value: value, spanTicks: spanTicks))
        case .bendSegment, .none:
            break
        }
        lastTapTime = g.time
        lastTapLocation = g.location
    }

    // MARK: Drawing

    private func drawGrid(_ ctx: GraphicsContext, _ size: CGSize) {
        // Bar lines across the clip span + a mid value line.
        var grid = Path()
        let bars = max(1, spanTicks / AutomationCanvasMath.barTicks)
        for bar in 0...bars {
            let x = size.width * CGFloat(bar) / CGFloat(bars)
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
        }
        grid.move(to: CGPoint(x: 0, y: size.height / 2))
        grid.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        ctx.stroke(grid, with: .color(EchoelTheme.border.opacity(0.6)), lineWidth: 1)
    }

    private func drawCurve(_ ctx: GraphicsContext, _ size: CGSize) {
        guard let lane, !lane.isEmpty else {
            let t = Text("Tap to add a keyframe").font(EchoelTheme.font(12))
                .foregroundStyle(EchoelTheme.dim)
            ctx.draw(t, at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }
        var path = Path()
        let samples = 128
        for s in 0...samples {
            let tick = spanTicks * s / samples
            let v = lane.value(atTick: tick) ?? 0
            let pt = CGPoint(x: AutomationCanvasMath.x(forTick: tick, width: size.width, spanTicks: spanTicks),
                             y: AutomationCanvasMath.y(forValue: v, height: size.height))
            if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(EchoelTheme.accent), lineWidth: 2)
    }

    private func drawPoints(_ ctx: GraphicsContext, _ size: CGSize) {
        for p in points {
            let c = CGPoint(x: AutomationCanvasMath.x(forTick: p.tick, width: size.width, spanTicks: spanTicks),
                            y: AutomationCanvasMath.y(forValue: p.value, height: size.height))
            let dot = Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10))
            ctx.fill(dot, with: .color(EchoelTheme.accent))
            ctx.stroke(dot, with: .color(EchoelTheme.bg), lineWidth: 1.5)
        }
    }
}
#endif
