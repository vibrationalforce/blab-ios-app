#if canImport(SwiftUI)
import SwiftUI

// AutomationView.swift
// Echoel — author parameter automation by DRAWING (A3, founder: "Automation
// kenne ich eher so, dass man es zeichnet wie in Ableton"): the canvas shows
// one bar of the lane; tap adds a snapped keyframe, dragging a point moves it,
// a vertical drag between two points BENDS the segment (Ableton's Alt+Drag as
// plain touch), double-tap deletes. The keyframe list below stays for precise
// typed edits (EchoelValueField). Geometry + touch laws live in
// AutomationCanvasMath (pure, unit-tested). Playback rides the shared
// transport (AutomationPlayer.applyStep); the lane stores normalized values.
//
// Cycle 3 (automation-in-track): the sheet is target-GENERIC. Every editable
// target is an AutomationTargetSpec — the three legacy enum targets plus every
// router-bound registry descriptor (placebo law: only parameters that actually
// move audio are offered; today that is the legacy three, the DDSP setters
// bind in a later cycle). One spec, one canvas, one keyframe list — no second
// code path when the catalog widens.

/// Everything the sheet needs to show + edit one automation target, resolved
/// from either a legacy enum target or a bound registry descriptor. Identity =
/// the lane's parameter string (rawValue / keyPath).
private struct AutomationTargetSpec: Identifiable {
    let parameter: String
    let displayName: String
    let unit: String
    let decimals: Int
    let minReal: Double
    let maxReal: Double
    /// normalized 0…1 → real units (the enum keeps its curves, e.g. log filter).
    let toReal: (Double) -> Double
    /// real units → normalized 0…1 (inverse, for typed edits).
    let toNormalized: (Double) -> Double

    var id: String { parameter }

    init(_ target: AutomationTarget) {
        parameter = target.rawValue
        displayName = target.displayName
        unit = target.unit
        decimals = target.decimals
        minReal = target.minValue
        maxReal = target.maxValue
        toReal = { target.value(forNormalized: $0) }
        toNormalized = { target.normalized(forValue: $0) }
    }

    init(_ d: ParameterDescriptor) {
        parameter = d.keyPath
        displayName = d.displayName
        unit = d.unit
        // Wide physical ranges (Hz) read as integers; tight ones need decimals.
        decimals = (d.max - d.min) > 100 ? 0 : 2
        minReal = Double(d.min)
        maxReal = Double(d.max)
        toReal = { Double(d.denormalized(Float($0))) }
        toNormalized = { Double(d.normalized(Float($0))) }
    }
}

@MainActor
struct AutomationView: View {

    @Environment(AutomationPlayer.self) private var automation
    @Environment(\.dismiss) private var dismiss

    @State private var selectedParameter: String = AutomationTarget.masterLevel.rawValue

    /// Legacy targets first (stable muscle memory), then every router-bound
    /// registry parameter. Recomputed per render — pure lookups, no live reads.
    private var specs: [AutomationTargetSpec] {
        AutomationTarget.allCases.map(AutomationTargetSpec.init)
            + automation.extraAutomatableDescriptors.map(AutomationTargetSpec.init)
    }

    private var spec: AutomationTargetSpec {
        specs.first { $0.parameter == selectedParameter }
            ?? AutomationTargetSpec(.masterLevel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    enableRow
                    targetPicker
                    AutomationCanvas(spec: spec)
                    keyframes
                    Text("Automation plays over the loop: each keyframe sets \(spec.displayName.lowercased()) at its beat, gliding (Linear) or stepping (Hold) to the next. Off leaves the parameter alone. On the canvas: tap adds, drag moves, a vertical drag between two points bends the curve, double-tap deletes.")
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                }
                .padding(16)
            }
            .background(EchoelTheme.bg.ignoresSafeArea())
            .navigationTitle("Automation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder private var enableRow: some View {
        @Bindable var auto = automation
        Toggle(isOn: $auto.enabled) {
            Text("Automation on").font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
        }
        .tint(EchoelTheme.accent)
    }

    /// Three targets fit a segmented control (the shipped look); a widened
    /// catalog flips to a menu picker automatically — same selection state.
    @ViewBuilder private var targetPicker: some View {
        let options = specs
        if options.count <= 3 {
            Picker("Target", selection: $selectedParameter) {
                ForEach(options) { s in Text(s.displayName).tag(s.parameter) }
            }
            .pickerStyle(.segmented)
        } else {
            HStack {
                Text("Target").font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.dim)
                Spacer()
                Picker("Target", selection: $selectedParameter) {
                    ForEach(options) { s in Text(s.displayName).tag(s.parameter) }
                }
                .pickerStyle(.menu)
                .tint(EchoelTheme.text)
            }
            .padding(.horizontal, 12).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
    }

    @ViewBuilder private var keyframes: some View {
        let points = automation.points(forParameter: spec.parameter)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Keyframes").font(EchoelTheme.font(11, .bold)).foregroundStyle(EchoelTheme.dim)
                Spacer()
                if !points.isEmpty {
                    Button("Clear") { automation.clear(parameter: spec.parameter) }
                        .font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.danger)
                        .buttonStyle(.plain)
                }
            }
            if points.isEmpty {
                Text("No keyframes. Add one to start shaping \(spec.displayName.lowercased()).")
                    .font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.dim)
                    .padding(.vertical, 4)
            } else {
                ForEach(points) { p in keyframeRow(p) }
            }
            Button {
                let nextBeat = min(Double(AutomationPlayer.beatsPerBar),
                                   (points.last.map { AutomationPlayer.beat(forTick: $0.tick) } ?? -1) + 1)
                automation.addPoint(parameter: spec.parameter, beat: max(0, nextBeat), value: 0.5)
            } label: {
                Label("Add keyframe", systemImage: "plus")
                    .font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    private func keyframeRow(_ p: AutomationPoint) -> some View {
        VStack(spacing: 8) {
            EchoelValueField(label: "Beat", value: beatBinding(p),
                             range: 0...Float(AutomationPlayer.beatsPerBar), unit: "", decimals: 2)
            EchoelValueField(label: "Value", value: valueBinding(p),
                             range: Float(spec.minReal)...Float(spec.maxReal),
                             unit: spec.unit, decimals: spec.decimals)
            HStack(spacing: 8) {
                Picker("Curve", selection: curveBinding(p)) {
                    Text("Linear").tag(AutomationCurve.linear)
                    Text("Hold").tag(AutomationCurve.hold)
                }
                .pickerStyle(.segmented)
                Button {
                    automation.removePoint(parameter: spec.parameter, id: p.id)
                } label: {
                    Image(systemName: "trash").foregroundStyle(EchoelTheme.danger)
                        .frame(width: 40, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete keyframe")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.bg))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    // MARK: - Bindings (edit a keyframe in place via the player's API)

    private func beatBinding(_ p: AutomationPoint) -> Binding<Float> {
        Binding(
            get: { Float(AutomationPlayer.beat(forTick: p.tick)) },
            set: { [parameter = spec.parameter] in
                automation.movePoint(parameter: parameter, id: p.id, toBeat: Double($0))
            }
        )
    }
    private func valueBinding(_ p: AutomationPoint) -> Binding<Float> {
        Binding(
            get: { [toReal = spec.toReal] in Float(toReal(p.value)) },
            set: { [parameter = spec.parameter, toNormalized = spec.toNormalized] in
                automation.setValue(parameter: parameter, id: p.id,
                                    normalized: toNormalized(Double($0)))
            }
        )
    }
    private func curveBinding(_ p: AutomationPoint) -> Binding<AutomationCurve> {
        Binding(
            get: { p.curve },
            set: { [parameter = spec.parameter] in
                automation.setCurve(parameter: parameter, id: p.id, $0)
            }
        )
    }
}

// MARK: - Drawable canvas (A3)

/// One bar of the selected lane as a drawable curve. All geometry/touch rules
/// come from `AutomationCanvasMath`; every edit goes through the player's API
/// (persisted, observable — the keyframe list below updates live).
@MainActor
private struct AutomationCanvas: View {

    let spec: AutomationTargetSpec
    @Environment(AutomationPlayer.self) private var automation

    /// What the current drag is doing — decided once at touch-down. ONE drag
    /// gesture handles everything (a competing TapGesture(count:2) would race
    /// the zero-distance drag and double-add); double-tap is detected from
    /// the event timestamps of two consecutive sub-slop touches.
    private enum DragMode {
        case movePoint(UUID)
        case bendSegment(id: UUID, startCurvature: Double, rising: Bool)
        case tap
    }
    @State private var dragMode: DragMode?
    @State private var lastTapTime: Date?
    @State private var lastTapLocation: CGPoint = .zero

    private static let height = 140.0
    private static let touchRadius = 28.0
    private static let doubleTapWindow: TimeInterval = 0.4

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let points = automation.points(forParameter: spec.parameter)
            let lane = automation.lane(forParameter: spec.parameter)
            Canvas { ctx, size in
                drawGrid(ctx, size)
                drawCurve(ctx, size, lane: lane)
                drawPoints(ctx, size, points: points)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in handleChanged(g, points: points, width: w) }
                .onEnded { g in handleEnded(g, width: w) })
        }
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
        .accessibilityLabel("Automation canvas: tap adds a keyframe, drag moves, double-tap deletes")
    }

    // MARK: Gesture logic

    private func travel(_ g: DragGesture.Value) -> Double {
        Double(g.translation.width * g.translation.width
               + g.translation.height * g.translation.height).squareRoot()
    }

    private func handleChanged(_ g: DragGesture.Value, points: [AutomationPoint], width: CGFloat) {
        let w = Double(width)
        if dragMode == nil {
            // Classify ONCE at the start location: point → move; between two
            // points → bend that segment; anywhere else → tap-in-waiting.
            let sx = Double(g.startLocation.x), sy = Double(g.startLocation.y)
            if let hit = AutomationCanvasMath.nearestPoint(toX: sx, y: sy, points: points,
                                                           width: w, height: Self.height),
               hit.distance <= Self.touchRadius {
                dragMode = .movePoint(hit.id)
            } else if let left = AutomationCanvasMath.segmentLeftPoint(atX: sx, points: points,
                                                                       width: w) {
                let sorted = points.sorted { $0.tick < $1.tick }
                let right = sorted.first { $0.tick > left.tick }
                dragMode = .bendSegment(id: left.id, startCurvature: left.curvature,
                                        rising: (right?.value ?? left.value) > left.value)
            } else {
                dragMode = .tap
            }
        }
        // Below the tap slop nothing edits yet — a plain tap must never move
        // or bend; the decision between tap/double-tap/edit falls in onEnded.
        guard travel(g) > AutomationCanvasMath.tapSlopPoints else { return }
        switch dragMode {
        case .movePoint(let id):
            let tick = AutomationCanvasMath.snappedTick(
                AutomationCanvasMath.tick(forX: Double(g.location.x), width: w))
            automation.movePoint(parameter: spec.parameter, id: id,
                                 toBeat: AutomationPlayer.beat(forTick: tick),
                                 normalized: AutomationCanvasMath.value(forY: Double(g.location.y),
                                                                        height: Self.height))
        case .bendSegment(let id, let start, let rising):
            automation.setCurvature(parameter: spec.parameter, id: id,
                                    AutomationCanvasMath.bentCurvature(
                                        start: start,
                                        dragUpPoints: -Double(g.translation.height),
                                        risingSegment: rising))
        case .tap, .none:
            break
        }
    }

    private func handleEnded(_ g: DragGesture.Value, width: CGFloat) {
        let mode = dragMode
        dragMode = nil
        // Real drags end here — the edit already happened in onChanged.
        guard travel(g) <= AutomationCanvasMath.tapSlopPoints else { lastTapTime = nil; return }

        // Sub-slop release = a tap. Two taps close in time + space = double-tap.
        let dx = Double(g.location.x - lastTapLocation.x)
        let dy = Double(g.location.y - lastTapLocation.y)
        let isDouble = lastTapTime.map {
            g.time.timeIntervalSince($0) <= Self.doubleTapWindow
                && (dx * dx + dy * dy).squareRoot() <= Self.touchRadius * 1.5
        } ?? false

        switch mode {
        case .movePoint(let id):
            // Double-tap ON a point deletes it. (An empty-space double-tap is
            // self-healing: the first tap adds a point, the second lands on it
            // as .movePoint and removes it again — net no change.)
            if isDouble {
                automation.removePoint(parameter: spec.parameter, id: id)
                lastTapTime = nil
                return
            }
        case .tap:
            let tick = AutomationCanvasMath.snappedTick(
                AutomationCanvasMath.tick(forX: Double(g.location.x), width: Double(width)))
            automation.addPoint(parameter: spec.parameter,
                                beat: AutomationPlayer.beat(forTick: tick),
                                value: AutomationCanvasMath.value(forY: Double(g.location.y),
                                                                  height: Self.height))
        case .bendSegment, .none:
            break
        }
        lastTapTime = g.time
        lastTapLocation = g.location
    }

    // MARK: Drawing

    private func drawGrid(_ ctx: GraphicsContext, _ size: CGSize) {
        var grid = Path()
        for beat in 0...AutomationPlayer.beatsPerBar {
            let x = size.width * CGFloat(beat) / CGFloat(AutomationPlayer.beatsPerBar)
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
        }
        grid.move(to: CGPoint(x: 0, y: size.height / 2))
        grid.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        ctx.stroke(grid, with: .color(EchoelTheme.border.opacity(0.6)), lineWidth: 1)
    }

    private func drawCurve(_ ctx: GraphicsContext, _ size: CGSize, lane: AutomationLane?) {
        guard let lane, !lane.isEmpty else {
            let t = Text("Tap to add a keyframe").font(EchoelTheme.font(12))
                .foregroundStyle(EchoelTheme.dim)
            ctx.draw(t, at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }
        // Sample the lane densely — shapedFraction renders the bent segments.
        var path = Path()
        let samples = 128
        for s in 0...samples {
            let tick = AutomationCanvasMath.barTicks * s / samples
            let v = lane.value(atTick: tick) ?? 0
            let pt = CGPoint(x: AutomationCanvasMath.x(forTick: tick, width: size.width),
                             y: AutomationCanvasMath.y(forValue: v, height: size.height))
            if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(EchoelTheme.accent), lineWidth: 2)
    }

    private func drawPoints(_ ctx: GraphicsContext, _ size: CGSize, points: [AutomationPoint]) {
        for p in points {
            let c = CGPoint(x: AutomationCanvasMath.x(forTick: p.tick, width: size.width),
                            y: AutomationCanvasMath.y(forValue: p.value, height: size.height))
            let dot = Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10))
            ctx.fill(dot, with: .color(EchoelTheme.accent))
            ctx.stroke(dot, with: .color(EchoelTheme.bg), lineWidth: 1.5)
        }
    }
}
#endif
