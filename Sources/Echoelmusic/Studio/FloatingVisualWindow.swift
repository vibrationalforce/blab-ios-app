#if canImport(SwiftUI) && canImport(MetalKit) && canImport(UIKit)
import SwiftUI

// FloatingVisualWindow.swift
// Echoel — the immersive visual as a FLOATING, resizable, show/hide window (founder
// 2026-07-02: "als kleines Fenster flexibel groß ein- und ausblendbar machen …
// interessanter aber weniger komplex von den Einstellungen"). The core product is the
// bio-reactive MUSIC; the visual rides along as a calm picture-in-picture you can move,
// grow (S/M/L) and dismiss — no VJ sliders here (the deep controls stay in Studio).
//
// Render safety: this is a LEAF overlay. Its body reads only LOW-frequency @State
// (size, drag position) — never a ~10 Hz bio value — so it can float over any surface
// without rebuilding the surface tree / freezing an open menu (freeze rule). The real
// `MetalBioView` pulls the live bio itself inside its `draw(in:)` loop (off the SwiftUI
// graph). Only ONE `MetalBioView` renders app-wide at a time (GPU rule): this window is
// the single Metal path at the WorkspaceView root.

/// A finished MP4 clip to share (Identifiable so `.sheet(item:)` can present it).
private struct RecordedClip: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
struct FloatingVisualWindow: View {

    /// Show/hide — owned by WorkspaceView (persisted there), toggled from the header.
    @Binding var isPresented: Bool

    // MP4 capture (founder 2026-07-02: "WAV und MP4 sind die Formate der Wahl"). The
    // window's MetalBioView is the single Metal path, so it is the one capture instance;
    // tapping record writes the bio-reactive visual (+ the live audio) to an .mp4 to share.
    #if canImport(AVFoundation)
    @Environment(VisualRecorder.self) private var recorder
    @Environment(AudioEngine.self) private var audioEngine
    // For a fitting MP4 name (founder: "Session Recording für video und auch passender
    // Name") — same convention as the WAV: Echoel_<date>_<Key>_<bpm>_A440_<Genre>.mp4.
    @Environment(SessionContext.self) private var session
    @Environment(Transport.self) private var transport
    @AppStorage("studio.genre") private var genre: MusicStyle = .vaporwave
    @State private var recordedClip: RecordedClip?
    #endif

    // Visual DESIGN (founder: "Visual Design muss schon noch möglich sein"). The look you
    // set in the Visual panel must actually reach THIS window. These are the SHARED
    // (@AppStorage) design keys the panel writes; the floating MetalBioView reads them so
    // the chosen Look + preset show here. (The panel's live fine-tune sliders are @State
    // and not yet shared — a follow-up; the persisted design is the preset, resolved below.)
    @AppStorage("visual.style") private var visualStyle = 0
    @AppStorage("visual.styleB") private var visualStyleB = 0
    @AppStorage("visual.blend") private var visualBlend = 0.0
    @AppStorage("visual.preset") private var visualPresetID = ""

    /// Snap size, persisted so the window reopens the size you left it.
    @AppStorage("visual.floating.size") private var sizeRaw = WindowSize.small.rawValue
    private var windowSize: WindowSize { WindowSize(rawValue: sizeRaw) ?? .medium }

    /// Card CENTRE in the parent's coordinate space. `nil` until first layout → defaults
    /// to the bottom-trailing dock (above the transport / bottom bar). Kept in @State
    /// (per-launch) — a low-frequency value, safe to read in this leaf's body.
    @State private var center: CGPoint?
    /// Drag anchor so a move continues from where the card currently sits.
    @State private var dragAnchor: CGPoint?

    enum WindowSize: Int, CaseIterable {
        case small, medium, large
        var next: WindowSize { WindowSize(rawValue: (rawValue + 1) % WindowSize.allCases.count) ?? .small }
        /// Width / height as a fraction of the available space.
        var fraction: (w: CGFloat, h: CGFloat) {
            switch self {
            case .small:  return (0.38, 0.30)
            case .medium: return (0.62, 0.42)
            case .large:  return (0.92, 0.62)
            }
        }
        var label: String {
            switch self {
            case .small:  return "Small"
            case .medium: return "Medium"
            case .large:  return "Large"
            }
        }
    }

    private let margin: CGFloat = 12
    private let handleHeight: CGFloat = 30

    /// The persisted visual design (energy/form) — the chosen preset if any, else the
    /// neutral defaults. Shared with the Visual panel via `visual.preset`.
    private var design: (intensity: Float, detail: Float, motion: Float, spread: Float) {
        if let p = VisualPreset.factory.first(where: { $0.id == visualPresetID }) {
            return (p.intensity, p.detail, p.motion, p.spread)
        }
        return (1.0, 40, 1.0, 1.0)
    }

    var body: some View {
        GeometryReader { geo in
            let sz = size(in: geo.size)
            let c = clamp(center ?? defaultCenter(in: geo.size, card: sz), in: geo.size, card: sz)
            card(size: sz, in: geo.size)
                .frame(width: sz.width, height: sz.height)
                .position(c)
        }
        .transition(.opacity)
        #if canImport(AVFoundation)
        .sheet(item: $recordedClip) { clip in ShareSheet(url: clip.url) }
        #endif
    }

    // MARK: - Card

    @ViewBuilder
    private func card(size: CGSize, in bounds: CGSize) -> some View {
        VStack(spacing: 0) {
            handleBar(in: bounds, card: size)
            // `capturesVideo: true` → this instance feeds the shared VisualRecorder when
            // recording (it is the only Metal path, so no double-capture). The look params
            // are the SHARED design (style/blend + the resolved preset), so what you set in
            // the Visual panel shows here too.
            MetalBioView(capturesVideo: true,
                         intensity: design.intensity, ringDensity: design.detail,
                         motion: design.motion, spread: design.spread,
                         style: visualStyle, styleB: visualStyleB, blend: Float(visualBlend))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(EchoelTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floating visual")
    }

    /// The only chrome: a drag handle + a size cycle + a close button. Deliberately no
    /// sliders (founder: fewer settings).
    private func handleBar(in bounds: CGSize, card: CGSize) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EchoelTheme.dim)
            Text("Visual").font(EchoelTheme.font(11, .medium)).foregroundStyle(EchoelTheme.dim)
            Spacer(minLength: 0)
            #if canImport(AVFoundation)
            Button { toggleRecording() } label: {
                Image(systemName: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(recorder.isRecording ? Color.red : EchoelTheme.text)
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Record MP4 video")
            #endif
            Button { cycleSize() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resize visual")
            .accessibilityValue(windowSize.label)
            Button { withAnimation(.easeInOut(duration: 0.15)) { isPresented = false } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide visual")
        }
        .padding(.horizontal, 10)
        .frame(height: handleHeight)
        .frame(maxWidth: .infinity)
        .background(EchoelTheme.bg.opacity(0.92))
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    let base = dragAnchor ?? (center ?? defaultCenter(in: bounds, card: card))
                    if dragAnchor == nil { dragAnchor = base }
                    center = CGPoint(x: base.x + value.translation.width,
                                     y: base.y + value.translation.height)
                }
                .onEnded { _ in dragAnchor = nil }
        )
    }

    private func cycleSize() {
        withAnimation(.easeInOut(duration: 0.18)) { sizeRaw = windowSize.next.rawValue }
    }

    #if canImport(AVFoundation)
    /// Start/stop MP4 capture of the visual (with live audio). On stop, present the share
    /// sheet. Tip: size the window up (L) before recording for a higher-resolution clip —
    /// the video is rendered at the window's on-screen size.
    private func toggleRecording() {
        if recorder.isRecording {
            Task { @MainActor in
                if let url = await recorder.stop() {
                    recordedClip = RecordedClip(url: renamedForShare(url))
                }
            }
        } else {
            recorder.start(audio: audioEngine)
        }
    }

    /// Give the recorded clip a fitting name — same convention as the WAV export:
    /// `Echoel_<date>_<Key>_<bpm>_A440_<Genre>.mp4` (key + tempo + tuning + genre). Copies
    /// to a temp file with that name for the share sheet; falls back to the original on
    /// failure so a recording is never lost.
    private func renamedForShare(_ url: URL) -> URL {
        let raw = "\(session.sessionName(bpm: transport.tempo))_\(genre.displayName)"
        let safe = raw.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>| "))
            .filter { !$0.isEmpty }.joined(separator: "-")
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).\(ext)")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return url
        }
    }
    #endif

    // MARK: - Geometry

    private func size(in bounds: CGSize) -> CGSize {
        let f = windowSize.fraction
        let w = max(140, bounds.width * f.w)
        let h = max(120, bounds.height * f.h)
        return CGSize(width: min(w, bounds.width - 2 * margin),
                      height: min(h, bounds.height - 2 * margin))
    }

    private func defaultCenter(in bounds: CGSize, card: CGSize) -> CGPoint {
        CGPoint(x: bounds.width - card.width / 2 - margin,
                y: bounds.height - card.height / 2 - margin)
    }

    /// Keep the whole card on screen (with the margin) whatever the size/drag.
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
