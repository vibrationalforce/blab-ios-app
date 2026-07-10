#if canImport(SwiftUI)
import SwiftUI

// ArrangeTimelineView.swift
// Echoel — the beat-grid Arrange surface (approved plan, Stage 1c): bar ruler,
// horizontal lanes, tick-positioned regions, pinch zoom, live playhead. This is
// the foundation the WAV waveform (Stage 2) and touch editing (Stage 3) land on;
// playback stays with the existing bar-granular ArrangementPlayer for now.
//
// Stage 3a (One-View convergence, founder 2026-07-09/-10: "alles läuft über die
// Spuren"): track headers are DOORS — tap a lane head for its editor (MIDI →
// Piano Roll, Audio → audio editor), rename, delete-if-empty; "+" adds tracks.
// This view owns ONE .sheet + ONE rename alert — safe here (the ~18-modal
// metadata limit is EchoelStudioView's chain, this view had none). Never drive
// both true at once (each menu action sets exactly one).
//
// Render safety: this body reads ONLY low-frequency state (document edits, zoom).
// The moving playhead lives in its own leaf struct (TimelinePlayhead), exactly
// like ArrangementPlayhead — the ~8 Hz Transport read never churns the grid.

@MainActor
struct ArrangeTimelineView: View {
    @Environment(TimelineStore.self) private var timeline
    @Environment(ArrangementStore.self) private var legacySong
    @Environment(ClipStore.self) private var clips
    @Environment(BeatPlayer.self) private var beatPlayer
    @Environment(PianoRollModel.self) private var pianoRoll

    /// The one editor sheet this surface owns (lane whose editor is open).
    @State private var editorLane: TimelineLane?
    /// Rename flow: which lane + the draft name (alert, not a second sheet).
    @State private var renameLaneID: UUID?
    @State private var renameText = ""

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
        .sheet(item: $editorLane) { lane in
            laneEditor(lane).echoelSheetPanel()
        }
        .alert("Rename track", isPresented: renameAlertShown) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let id = renameLaneID {
                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { timeline.renameLane(id: id, to: trimmed) }
                }
                renameLaneID = nil
            }
            Button("Cancel", role: .cancel) { renameLaneID = nil }
        }
    }

    // MARK: - Track doors (Stage 3a)

    /// The editor behind a lane's door. Only kinds with a real engine offer a
    /// door (menu builders below) — no placeholder screens.
    @ViewBuilder
    private func laneEditor(_ lane: TimelineLane) -> some View {
        switch lane.kind {
        case .midi:  PianoRollView(pattern: beatPlayer.pattern, model: pianoRoll)
        case .audio: AudioClipView()
        case .video, .visual: EmptyView()   // no engine yet — no door offered
        }
    }

    private var renameAlertShown: Binding<Bool> {
        Binding(
            get: { renameLaneID != nil },
            set: { if !$0 { renameLaneID = nil } }
        )
    }

    // MARK: - Toolbar (low-frequency only)

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("Arrange")
                .font(EchoelTheme.font(14, .semibold))
                .foregroundStyle(EchoelTheme.text)
            Spacer(minLength: 0)
            // Add track — MIDI/Audio only (the kinds with a real engine today).
            Menu {
                Button { timeline.addLane(kind: .midi) } label: {
                    Label("MIDI track", systemImage: ClipKind.midi.systemImage)
                }
                Button { timeline.addLane(kind: .audio) } label: {
                    Label("Audio track", systemImage: ClipKind.audio.systemImage)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .accessibilityLabel("Add track")
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
                laneHeader(lane)
            }
            Spacer(minLength: 0)
        }
        .background(EchoelTheme.bg)
    }

    /// One track head — a DOOR (Stage 3a): tap for editor / rename / delete.
    private func laneHeader(_ lane: TimelineLane) -> some View {
        Menu {
            if !lane.isBio, lane.kind == .midi {
                Button { editorLane = lane } label: {
                    Label("Open Piano Roll", systemImage: ClipKind.midi.systemImage)
                }
            }
            if !lane.isBio, lane.kind == .audio {
                Button { editorLane = lane } label: {
                    Label("Open audio editor", systemImage: ClipKind.audio.systemImage)
                }
            }
            Button {
                renameText = lane.name
                renameLaneID = lane.id
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            if timeline.document.regions(in: lane.id).isEmpty,
               timeline.document.lanes.count > 1 {
                Button(role: .destructive) {
                    timeline.removeLaneIfEmpty(id: lane.id)
                } label: {
                    Label("Delete empty track", systemImage: "trash")
                }
            }
        } label: {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: lane.kind.systemImage)
                        .font(.system(size: 10))
                        .foregroundStyle(EchoelTheme.dim)
                    Text(lane.name)
                        .font(EchoelTheme.font(10, .medium))
                        .foregroundStyle(EchoelTheme.text)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(EchoelTheme.dim)
                    .padding(.trailing, 4)
            }
            .padding(.leading, 10)
            .frame(width: Self.labelWidth, height: Self.laneHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .overlay(alignment: .bottom) { Divider().overlay(EchoelTheme.border) }
        .accessibilityLabel("\(lane.name), \(lane.kind.displayName) track")
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
        let clip = clips.clip(id: region.clipID)
        let name = clip?.name ?? "Clip"
        return RoundedRectangle(cornerRadius: 6)
            .fill(EchoelTheme.fill)
            .overlay {
                // Audio regions show their waveform (Stage 2) the moment the
                // clip references a real file — recording/import (Stage A/3)
                // feeds this; MIDI/empty regions stay plain blocks.
                if let clip, clip.kind == .audio, let url = Self.mediaURL(clip) {
                    FileWaveformView(url: url, tint: EchoelTheme.text)
                        .padding(.horizontal, 3).padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
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

    /// Resolve a clip's `mediaRef` to an existing file (absolute path today;
    /// nothing writes relative refs yet — extend here when import lands).
    private static func mediaURL(_ clip: Clip) -> URL? {
        guard let ref = clip.mediaRef, !ref.isEmpty else { return nil }
        let url = URL(fileURLWithPath: ref)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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
