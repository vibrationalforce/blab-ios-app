//
//  ImmersiveStageView.swift
//  Echoelmusic — Studio
//
//  The Immersive Stage: a top-down "room map" where every track is a puck you drag to
//  place its sound in space. This is the founder's Touch surface ("ein TouchInterface
//  einzubauen, mit dem man Automationen aufnehmen kann … komplexe multidimensionale
//  … Alle Instrumente und Effekte sollen immersiv sein") made visible: each real
//  (non-bio) lane already owns a positioned SpatialObject (ImmersiveObjectDefaults),
//  and dragging its puck moves that object live in the shared SpatialScene.
//
//  The listener sits at the disc centre facing UP: front = top, +90° azimuth = left,
//  the rim = far (distance 1). A 2D move changes azimuth + distance; a track's height
//  (elevation) is preserved. Pure geometry is `ImmersiveStageMath` (Linux-tested); this
//  view is a thin shell that reads the store and writes back moves. View geometry stays
//  in CGFloat; the pure math boundary takes/returns Double.
//
//  Render safety: reads only user-frequency state (the scene changes on drag / lane
//  edits, never at bio rate), so it is safe to read `SpatialSceneStore` in this body.
//  It owns NO `.sheet` — it is presented in ArrangeTimelineView's single sheet slot.
//

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct ImmersiveStageView: View {
    @Environment(TimelineStore.self) private var timeline
    @Environment(SpatialSceneStore.self) private var spatial
    #if canImport(Network)
    @Environment(ADMOSCSender.self) private var admOSC
    #endif
    @Environment(\.dismiss) private var dismiss

    /// The lane whose puck is under the finger (highlighted while dragging).
    @State private var draggingLaneID: UUID?

    private static let stageSpace = "immersive.stage"

    /// The tracks that appear on the stage: real (non-bio) lanes. Bio drives
    /// modulation, not placement (same rule as SpatialSceneStore).
    private var stageLanes: [TimelineLane] {
        timeline.document.lanes.filter { !$0.isBio }
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            if stageLanes.isEmpty {
                emptyState
            } else {
                stage
                #if canImport(Network)
                streamControls
                #endif
            }
            hint
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EchoelTheme.bg)
        .onAppear { spatial.rebuild(from: timeline.document.lanes) }
        .onChange(of: timeline.document.lanes) { _, lanes in
            spatial.rebuild(from: lanes)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Immersive Stage")
                    .font(EchoelTheme.font(17, .semibold))
                    .foregroundStyle(EchoelTheme.text)
                Text("Drag a track to place its sound in the room")
                    .font(EchoelTheme.font(12))
                    .foregroundStyle(EchoelTheme.dim)
            }
            Spacer()
            Button("Done") { dismiss() }
                .font(EchoelTheme.font(13, .medium))
                .foregroundStyle(EchoelTheme.text)
                .buttonStyle(.plain)
        }
    }

    // MARK: Stage disc

    private var stage: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = max(side / 2 - 34, 1)            // room for puck + rim labels
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                backdrop(center: center, radius: radius)
                ForEach(stageLanes) { lane in
                    puck(for: lane, center: center, radius: radius)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(.named(Self.stageSpace))
        }
    }

    /// The room: concentric distance rings, orientation labels, a centre listener mark.
    private func backdrop(center: CGPoint, radius: CGFloat) -> some View {
        ZStack {
            ForEach([0.33, 0.66, 1.0], id: \.self) { r in
                Circle()
                    .strokeBorder(EchoelTheme.border, lineWidth: 1)
                    .frame(width: radius * 2 * CGFloat(r), height: radius * 2 * CGFloat(r))
                    .position(center)
            }
            // Cross-hair through the listener.
            Path { p in
                p.move(to: CGPoint(x: center.x - radius, y: center.y))
                p.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                p.move(to: CGPoint(x: center.x, y: center.y - radius))
                p.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            }
            .stroke(EchoelTheme.border, lineWidth: 1)
            // Listener at centre.
            Circle().fill(EchoelTheme.dim)
                .frame(width: 8, height: 8)
                .position(center)
            // Orientation labels.
            orientationLabel("Front", x: center.x, y: center.y - radius - 12)
            orientationLabel("Back",  x: center.x, y: center.y + radius + 12)
            orientationLabel("Left",  x: center.x - radius - 20, y: center.y)
            orientationLabel("Right", x: center.x + radius + 22, y: center.y)
        }
    }

    private func orientationLabel(_ text: String, x: CGFloat, y: CGFloat) -> some View {
        Text(text)
            .font(EchoelTheme.font(10, .medium))
            .foregroundStyle(EchoelTheme.dim)
            .position(x: x, y: y)
    }

    // MARK: Puck

    @ViewBuilder
    private func puck(for lane: TimelineLane, center: CGPoint, radius: CGFloat) -> some View {
        let object = spatial.object(forLane: lane.id)
        let azimuth = Double(object?.position.azimuth ?? 0)
        let distance = Double(object?.position.distance ?? 1)
        let elevation = object?.position.elevation ?? 0
        let p = ImmersiveStageMath.point(azimuthDeg: azimuth, distance: distance,
                                         center: (x: Double(center.x), y: Double(center.y)),
                                         radius: Double(radius))
        let isDragging = draggingLaneID == lane.id
        puckBody(for: lane, highlighted: isDragging)
            .position(x: CGFloat(p.x), y: CGFloat(p.y))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.stageSpace))
                    .onChanged { value in
                        draggingLaneID = lane.id
                        let ad = ImmersiveStageMath.azimuthDistance(
                            forPoint: (x: Double(value.location.x), y: Double(value.location.y)),
                            center: (x: Double(center.x), y: Double(center.y)),
                            radius: Double(radius))
                        spatial.setPosition(laneID: lane.id,
                            SpatialPosition(azimuth: Float(ad.azimuthDeg),
                                            elevation: elevation,
                                            distance: Float(ad.distance)))
                    }
                    .onEnded { _ in draggingLaneID = nil }
            )
    }

    private func puckBody(for lane: TimelineLane, highlighted: Bool) -> some View {
        let size: CGFloat = highlighted ? 42 : 38
        return VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(highlighted ? EchoelTheme.accent : EchoelTheme.surface)
                    .frame(width: size, height: size)
                Circle()
                    .strokeBorder(highlighted ? EchoelTheme.accent : EchoelTheme.border,
                                  lineWidth: highlighted ? 2 : 1)
                    .frame(width: size, height: size)
                Image(systemName: lane.builtinInstrument?.systemImage ?? "pianokeys")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(highlighted ? EchoelTheme.onPrimary : EchoelTheme.text)
            }
            Text(lane.name)
                .font(EchoelTheme.font(10, .medium))
                .foregroundStyle(EchoelTheme.text)
                .lineLimit(1)
                .fixedSize()
        }
        .contentShape(Rectangle())
    }

    // MARK: Empty / hint

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(EchoelTheme.dim)
            Text("Add a track to place it in space")
                .font(EchoelTheme.font(13))
                .foregroundStyle(EchoelTheme.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hint: some View {
        Text("Centre = at you · rim = far · every instrument is a spatial object")
            .font(EchoelTheme.font(11))
            .foregroundStyle(EchoelTheme.dim)
            .multilineTextAlignment(.center)
    }

    // MARK: Scene egress (#18) — stream the placed objects to an external renderer

    #if canImport(Network)
    /// The one control that turns the placed room into an ADM-OSC object stream.
    /// When on, ADMOSCSender streams every track as `/adm/obj/1…N` (suppressing its
    /// bio→object mode so object 1 never collides). It only reaches the wire once the
    /// "ADM-OSC output" route is enabled in Routing — the status line says so.
    @ViewBuilder private var streamControls: some View {
        @Bindable var sender = admOSC
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $sender.streamsScene) {
                Text("Stream to renderer (ADM-OSC)")
                    .font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
            }
            .tint(EchoelTheme.accent)
            .accessibilityHint("Sends every track's spatial position to an external immersive renderer over the open ADM-OSC standard.")
            Text(streamStatusLine)
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    /// One honest line for every state — off / route-needed / streaming — so it's
    /// never ambiguous whether anything is actually leaving the device.
    private var streamStatusLine: String {
        if !admOSC.streamsScene {
            return "Send every track's position to an immersive renderer over the open ADM-OSC standard."
        }
        if !admOSC.isActive {
            return "Turn on \u{201E}ADM-OSC output\u{201C} in Routing to open the connection — then this streams live."
        }
        let n = admOSC.lastSceneObjectCount
        return "Streaming \(n) object\(n == 1 ? "" : "s") to \(admOSC.host):\(admOSC.port)."
    }
    #endif
}
#endif
