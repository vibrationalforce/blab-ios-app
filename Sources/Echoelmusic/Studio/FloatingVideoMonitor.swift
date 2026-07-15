// FloatingVideoMonitor.swift
// Echoel — the VIDEO MONITOR as a floating, resizable window (founder 2026-07-15,
// red circle on the header film button: "Dort soll der Video Monitor zum anklicken.
// Verschiedene größen einstellbar wie visualiser"). Tapping the header film tile
// shows/hides this window; it renders what the TIMELINE'S VIDEO LANES show at the
// playhead — still images and videos, following play, stop and scrub — so imported
// clips are finally VISIBLE, not just arrangeable blocks.
//
// This is the device half the tested coordinators were waiting for:
//   • WHICH picture — `VideoMonitorSelect` (pure, unit-tested): first unmuted video
//     lane with an active region wins.
//   • WHERE in the media — `VideoRegionSync` (pure, unit-tested).
//   • HOW to stay locked — `VideoResyncPolicy` (pure, unit-tested) applied by
//     `MonitorVideoSink`, the first real `VideoRegionSink` (AVPlayer-backed).
// V1 shows ONE lane's picture; multi-lane compositing/effects are a later cycle.
//
// Render safety: the window body reads only LOW-frequency @State (size, drag). The
// ~10 Hz transport follow lives in `VideoMonitorContent`, its OWN leaf (freeze rule
// 10.76.50) — an open menu in the surface below never tears down. The player is
// MUTED by design: the timeline's SOUND comes from the audio/MIDI lanes; the monitor
// is picture-only (video-clip audio routing is its own future decision).

#if canImport(SwiftUI) && canImport(AVFoundation) && canImport(UIKit) && canImport(MetalKit)
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - AVPlayer sink (the device half of VideoRegionSink)

/// AVPlayer-backed `VideoRegionSink`: presents a file at the expected source time and
/// keeps it locked to the transport via `VideoResyncPolicy` (hold / rate-nudge /
/// hard-seek). Muted — the monitor shows picture only. One instance per monitor.
@MainActor
final class MonitorVideoSink: VideoRegionSink {

    let player = AVPlayer()
    private(set) var currentURL: URL?

    init() {
        player.isMuted = true                     // picture-only by design (see header)
        player.actionAtItemEnd = .pause           // exhausted media holds its last frame
        // The transport is the clock; never let AVPlayer stall waiting to buffer a
        // local file (all media is on-disk App-Group files).
        player.automaticallyWaitsToMinimizeStalling = false
    }

    func present(url: URL, atSourceSeconds sourceSeconds: Double, playing: Bool) {
        let switched = currentURL != url
        if switched {
            currentURL = url
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        let observed = player.currentTime().seconds
        switch VideoResyncPolicy.resolve(expectedSourceSeconds: sourceSeconds,
                                         observedSeconds: observed,
                                         dt: 0.1,
                                         regionSwitchedOrWrapped: switched) {
        case .hold:
            // Inside the deadband → run at nominal (clears any previous nudge).
            if playing, player.rate != 0, player.rate != 1 { player.rate = 1 }
        case .nudgeRate(let rate):
            if playing { player.rate = rate }
        case .hardSeek(let toSeconds):
            player.seek(to: CMTime(seconds: max(0, toSeconds), preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if playing {
            if player.rate == 0 { player.rate = 1 }
        } else {
            player.pause()                        // scrub / hold-frame: show, don't run
        }
    }

    func stop() {
        player.pause()
    }
}

/// Plain AVPlayerLayer host — the monitor's video surface (aspect-fit on black).
private struct MonitorPlayerView: UIViewRepresentable {
    let player: AVPlayer

    final class HostView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
    }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        if let layer = view.layer as? AVPlayerLayer {
            layer.player = player
            layer.videoGravity = .resizeAspect
        }
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        if let layer = uiView.layer as? AVPlayerLayer, layer.player !== player {
            layer.player = player
        }
    }
}

// MARK: - Content leaf (the ~10 Hz transport follow lives HERE, never in a parent)

/// Resolves + renders the timeline's video picture at the playhead. A LEAF: it reads
/// `transport.position` in its own body-adjacent observers, so the per-step churn is
/// confined to this view (freeze rule). Stills render via AsyncImage; videos via the
/// muted AVPlayer sink, drift-corrected each transport step.
@MainActor
private struct VideoMonitorContent: View {
    @Environment(Transport.self) private var transport
    @Environment(TimelineStore.self) private var timeline
    @Environment(ClipStore.self) private var clips

    @State private var sink = MonitorVideoSink()
    /// Non-nil ⇒ the active clip is a STILL image at this URL (AsyncImage branch).
    @State private var stillURL: URL?
    /// True ⇒ the active clip is a VIDEO currently presented by the sink.
    @State private var showsVideo = false

    var body: some View {
        ZStack {
            Color.black
            if let stillURL {
                AsyncImage(url: stillURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
            } else if showsVideo {
                MonitorPlayerView(player: sink.player)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "film")
                        .font(.system(size: 20))
                        .foregroundStyle(EchoelTheme.dim)
                    Text("No video at the playhead")
                        .font(EchoelTheme.font(10))
                        .foregroundStyle(EchoelTheme.dim)
                }
            }
        }
        .onChange(of: transport.position.absoluteStep) { _, step in
            sync(tick: TimelineTime.tick(fromAbsoluteStep: step))
        }
        .onChange(of: transport.isPlaying) { _, _ in syncNow() }
        // Follow edits too (clip moved/trimmed/deleted while the monitor is open) —
        // documents change at user-edit rate, never per frame.
        .onChange(of: timeline.document) { _, _ in syncNow() }
        .onAppear { syncNow() }
        .onDisappear { sink.stop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Video monitor")
        .accessibilityValue(stillURL != nil ? "Showing an image"
                            : showsVideo ? "Showing video" : "No video at the playhead")
    }

    private func syncNow() {
        sync(tick: TimelineTime.tick(fromAbsoluteStep: transport.position.absoluteStep))
    }

    /// One monitor step: pick the picture (pure selector), branch still/video, and
    /// drive the sink with the expected source time. Runs per transport step + on
    /// play-state/document changes — never per rendered frame.
    private func sync(tick: Int) {
        let doc = timeline.document
        guard let active = VideoMonitorSelect.active(
            in: doc, atTick: tick, bpm: transport.tempo,
            nativeDuration: { clips.clip(id: $0)?.nativeDurationSeconds ?? 0 })
        else {
            stillURL = nil
            showsVideo = false
            sink.stop()
            return
        }
        guard let clip = clips.clip(id: active.clipID),
              let url = MediaLibrary.resolveRef(clip.mediaRef) else {
            stillURL = nil
            showsVideo = false
            sink.stop()
            return
        }
        // Same extension routing the import uses (VideoClipView): stills have no
        // playable track — they render as an image, held for the region's span.
        let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
        if isImage {
            if stillURL != url { stillURL = url }
            showsVideo = false
            sink.stop()
            return
        }
        stillURL = nil
        showsVideo = true
        switch active.playback {
        case .play(let sourceSeconds):
            sink.present(url: url, atSourceSeconds: sourceSeconds, playing: transport.isPlaying)
        case .exhausted(let sourceSeconds):
            sink.present(url: url, atSourceSeconds: sourceSeconds, playing: false)
        case .inactive:
            // Filtered by the selector; kept exhaustive for the compiler.
            showsVideo = false
            sink.stop()
        }
    }
}

// MARK: - Floating window

/// The floating video-monitor card: drag by the film handle, cycle S/M/L/Fullscreen
/// (the SAME sizes as the visualizer — founder: "Verschiedene größen einstellbar wie
/// visualiser"), close with ×. Docks bottom-LEADING by default so it coexists with
/// the visual window (which docks bottom-trailing).
@MainActor
struct FloatingVideoMonitor: View {

    /// Show/hide — owned by WorkspaceView (persisted there), toggled from the header
    /// film tile.
    @Binding var isPresented: Bool

    /// Snap size, persisted so the monitor reopens the size you left it. Reuses the
    /// visualizer's size steps so both windows feel identical to resize.
    @AppStorage("video.monitor.size") private var sizeRaw = FloatingVisualWindow.WindowSize.small.rawValue
    private var windowSize: FloatingVisualWindow.WindowSize {
        FloatingVisualWindow.WindowSize(rawValue: sizeRaw) ?? .medium
    }

    /// Card centre in the parent's space; nil until first layout → bottom-leading dock.
    @State private var center: CGPoint?
    @State private var dragAnchor: CGPoint?

    private let margin: CGFloat = 12
    private let handleHeight: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let full = windowSize.isFullscreen
            let sz = size(in: geo.size)
            let c = full
                ? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                : clamp(center ?? defaultCenter(in: geo.size, card: sz), in: geo.size, card: sz)
            card(in: geo.size, card: sz)
                .frame(width: sz.width, height: sz.height)
                .position(c)
        }
        .ignoresSafeArea(edges: windowSize.isFullscreen ? [.bottom, .horizontal] : [])
        .transition(.opacity)
    }

    private func card(in bounds: CGSize, card: CGSize) -> some View {
        VStack(spacing: 0) {
            handleBar(in: bounds, card: card)
            VideoMonitorContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: windowSize.isFullscreen ? 0 : 12))
        .overlay {
            if !windowSize.isFullscreen {
                RoundedRectangle(cornerRadius: 12).strokeBorder(EchoelTheme.border, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(windowSize.isFullscreen ? 0 : 0.35),
                radius: windowSize.isFullscreen ? 0 : 8,
                y: windowSize.isFullscreen ? 0 : 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floating video monitor")
    }

    /// Chrome: film drag-handle · size cycle · close. Same 44 pt targets as the
    /// visual window's bar (AX minimum); drag confined to the handle so the buttons
    /// always receive their taps.
    private func handleBar(in bounds: CGSize, card: CGSize) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "film")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EchoelTheme.text)
                .frame(width: 40, height: handleHeight)
                .contentShape(Rectangle())
                .gesture(
                    // `.global` space — a `.local` drag measures inside the moving
                    // handle and feeds back on itself (the visual window's tremble).
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            let base = dragAnchor ?? (center ?? defaultCenter(in: bounds, card: card))
                            if dragAnchor == nil { dragAnchor = base }
                            center = CGPoint(x: base.x + value.translation.width,
                                             y: base.y + value.translation.height)
                        }
                        .onEnded { _ in dragAnchor = nil }
                )
                .accessibilityLabel("Video monitor — drag to move")
            Spacer(minLength: 0)
            Button { sizeRaw = windowSize.next.rawValue } label: {
                Image(systemName: windowSize.isFullscreen
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 28, height: handleHeight)
                    .contentShape(Rectangle().inset(by: -5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(windowSize.isFullscreen ? "Exit fullscreen" : "Resize video monitor")
            .accessibilityValue(windowSize.label)
            Button { withAnimation(.easeInOut(duration: 0.15)) { isPresented = false } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 28, height: handleHeight)
                    .contentShape(Rectangle().inset(by: -5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide video monitor")
        }
        .padding(.horizontal, 10)
        .frame(height: handleHeight)
        .frame(maxWidth: .infinity)
        .background(EchoelTheme.bg.opacity(0.92))
    }

    // MARK: - Geometry (mirrors the visual window so both feel identical)

    private func size(in bounds: CGSize) -> CGSize {
        if windowSize.isFullscreen { return bounds }
        let f = windowSize.fraction
        let w = max(140, bounds.width * f.w)
        let h = max(120, bounds.height * f.h)
        return CGSize(width: min(w, bounds.width - 2 * margin),
                      height: min(h, bounds.height - 2 * margin))
    }

    /// Bottom-LEADING dock — the visual window docks bottom-trailing, so both
    /// windows can be open without stacking on first show.
    private func defaultCenter(in bounds: CGSize, card: CGSize) -> CGPoint {
        CGPoint(x: card.width / 2 + margin,
                y: bounds.height - card.height / 2 - margin)
    }

    private func clamp(_ p: CGPoint, in bounds: CGSize, card: CGSize) -> CGPoint {
        let minX = card.width / 2 + margin
        let maxX = bounds.width - card.width / 2 - margin
        let minY = card.height / 2 + margin
        let maxY = bounds.height - card.height / 2 - margin
        return CGPoint(x: min(max(p.x, minX), max(minX, maxX)),
                       y: min(max(p.y, minY), max(minY, maxY)))
    }
}
#endif
