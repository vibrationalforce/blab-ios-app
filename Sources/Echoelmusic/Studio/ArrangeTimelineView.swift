#if canImport(SwiftUI)
import SwiftUI

// ArrangeTimelineView.swift
// Echoel — the beat-grid Arrange surface (approved plan, Stage 1c): bar ruler,
// horizontal lanes, tick-positioned regions, pinch zoom, live playhead. This is
// the foundation the WAV waveform (Stage 2) and touch editing (Stage 3) land on;
// playback stays with the existing bar-granular ArrangementPlayer for now.
//
// Render safety: this body reads ONLY low-frequency state (document edits, zoom).
// The moving playhead lives in its own leaf struct (TimelinePlayhead), exactly
// like ArrangementPlayhead — the ~8 Hz Transport read never churns the grid.

@MainActor
struct ArrangeTimelineView: View {
    @Environment(TimelineStore.self) private var timeline
    @Environment(ArrangementStore.self) private var legacySong
    @Environment(ClipStore.self) private var clips

    /// Zoom: screen points per quarter-note beat (Stage 3 couples snap to this).
    @State private var pointsPerBeat: CGFloat = 24
    @GestureState private var pinch: CGFloat = 1
    /// Snap resolution — persisted; default 1/16 (research: snap ON by default).
    @AppStorage("timeline.snap") private var snapRaw = SnapResolution.sixteenth.rawValue

    private static let laneHeight: CGFloat = 56
    private static let labelWidth: CGFloat = 76
    private static let rulerHeight: CGFloat = 20

    private var ppb: CGFloat { min(96, max(8, pointsPerBeat * pinch)) }
    private var snap: SnapResolution { SnapResolution(rawValue: snapRaw) ?? .sixteenth }

    /// Bars drawn: song end + breathing room, at least 8.
    private var barCount: Int {
        max(8, timeline.document.endTick / TimelineTime.ticksPerBar + 2)
    }
    private var gridWidth: CGFloat {
        CGFloat(barCount * TimelineTime.beatsPerBar) * ppb
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider().overlay(EchoelTheme.border)
            HStack(spacing: 0) {
                laneLabels
                Divider().overlay(EchoelTheme.border)
                ScrollView(.horizontal, showsIndicators: true) {
                    grid
                }
            }
        }
        .background(EchoelTheme.bg)
        .task { timeline.bootstrapIfNeeded(sections: legacySong.sections) }
        .gesture(magnify)
    }

    // MARK: - Toolbar (low-frequency only)

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("Arrange")
                .font(EchoelTheme.font(14, .semibold))
                .foregroundStyle(EchoelTheme.text)
            Spacer(minLength: 0)
            // Snap resolution — the magnet. "Off" = stufenlos everywhere.
            Menu {
                ForEach(SnapResolution.allCases, id: \.self) { res in
                    Button {
                        snapRaw = res.rawValue
                    } label: {
                        if res == snap { Label(res.displayName, systemImage: "checkmark") }
                        else { Text(res.displayName) }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: snap == .off ? "arrow.left.and.right" : "arrow.right.to.line.compact")
                        .font(.system(size: 11, weight: .medium))
                    Text(snap == .off ? "Frei" : "Snap \(snap.displayName)")
                        .font(EchoelTheme.font(12))
                }
                .foregroundStyle(snap == .off ? EchoelTheme.dim : EchoelTheme.text)
                .padding(.horizontal, 10).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .accessibilityLabel("Snap resolution")
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    // MARK: - Lane labels (fixed column, never scrolls away)

    private var laneLabels: some View {
        VStack(spacing: 0) {
            Color.clear.frame(width: Self.labelWidth, height: Self.rulerHeight)
            ForEach(timeline.document.lanes) { lane in
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: lane.kind.systemImage)
                        .font(.system(size: 10))
                        .foregroundStyle(EchoelTheme.dim)
                    Text(lane.name)
                        .font(EchoelTheme.font(10, .medium))
                        .foregroundStyle(EchoelTheme.text)
                        .lineLimit(1)
                }
                .frame(width: Self.labelWidth, height: Self.laneHeight, alignment: .leading)
                .padding(.leading, 10)
                .frame(width: Self.labelWidth, alignment: .leading)
                .overlay(alignment: .bottom) { Divider().overlay(EchoelTheme.border) }
            }
            Spacer(minLength: 0)
        }
        .background(EchoelTheme.bg)
    }

    // MARK: - Grid (ruler + lanes + regions + playhead)

    private var grid: some View {
        VStack(spacing: 0) {
            ruler
            ForEach(timeline.document.lanes) { lane in
                laneRow(lane)
            }
            Spacer(minLength: 0)
        }
        .frame(width: gridWidth, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            TimelinePlayhead(pointsPerBeat: ppb)
        }
    }

    private var ruler: some View {
        ZStack(alignment: .topLeading) {
            EchoelTheme.fill
            ForEach(0..<barCount, id: \.self) { bar in
                Text("\(bar + 1)")
                    .font(EchoelTheme.font(9).monospacedDigit())
                    .foregroundStyle(EchoelTheme.dim)
                    .offset(x: CGFloat(bar * TimelineTime.beatsPerBar) * ppb + 3, y: 3)
            }
        }
        .frame(width: gridWidth, height: Self.rulerHeight, alignment: .topLeading)
    }

    private func laneRow(_ lane: TimelineLane) -> some View {
        ZStack(alignment: .topLeading) {
            // Bar grid lines (light) — beat lines arrive with Stage 3 editing.
            ForEach(0..<barCount, id: \.self) { bar in
                Rectangle()
                    .fill(EchoelTheme.border)
                    .frame(width: 1, height: Self.laneHeight)
                    .offset(x: CGFloat(bar * TimelineTime.beatsPerBar) * ppb)
            }
            ForEach(timeline.document.regions(in: lane.id)) { region in
                regionBlock(region)
            }
        }
        .frame(width: gridWidth, height: Self.laneHeight, alignment: .topLeading)
        .overlay(alignment: .bottom) { Divider().overlay(EchoelTheme.border) }
    }

    private func regionBlock(_ region: TimelineRegion) -> some View {
        let x = CGFloat(region.startTick) / CGFloat(TimelineTime.ticksPerBeat) * ppb
        let w = max(6, CGFloat(region.lengthTicks) / CGFloat(TimelineTime.ticksPerBeat) * ppb - 2)
        let name = clips.clip(id: region.clipID)?.name ?? "Clip"
        return RoundedRectangle(cornerRadius: 6)
            .fill(EchoelTheme.fill)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(EchoelTheme.text.opacity(0.35), lineWidth: 1))
            .overlay(alignment: .bottomLeading) {
                Text(name)
                    .font(EchoelTheme.font(9, .medium))
                    .foregroundStyle(EchoelTheme.text)
                    .lineLimit(1)
                    .padding(.horizontal, 5).padding(.bottom, 3)
            }
            .frame(width: w, height: Self.laneHeight - 8)
            .offset(x: x, y: 4)
            .accessibilityLabel("\(name), bar \(region.startTick / TimelineTime.ticksPerBar + 1)")
    }

    private var magnify: some Gesture {
        MagnificationGesture()
            .updating($pinch) { value, state, _ in state = value }
            .onEnded { value in
                pointsPerBeat = min(96, max(8, pointsPerBeat * value))
            }
    }
}

/// The moving playhead — its OWN leaf so the ~8 Hz Transport read rebuilds only
/// this 2-pt line, never the grid (freeze rule; pattern: ArrangementPlayhead).
@MainActor
private struct TimelinePlayhead: View {
    @Environment(Transport.self) private var transport
    let pointsPerBeat: CGFloat

    var body: some View {
        let pos = transport.position
        let beats = CGFloat(pos.bar * Transport.stepsPerBar + pos.step)
            / CGFloat(Transport.stepsPerBeat)
        Rectangle()
            .fill(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.dim)
            .frame(width: 2)
            .offset(x: beats * pointsPerBeat)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#endif
