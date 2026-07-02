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

@MainActor
struct FloatingVisualWindow: View {

    /// Show/hide — owned by WorkspaceView (persisted there), toggled from the header.
    @Binding var isPresented: Bool

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

    var body: some View {
        GeometryReader { geo in
            let sz = size(in: geo.size)
            let c = clamp(center ?? defaultCenter(in: geo.size, card: sz), in: geo.size, card: sz)
            card(size: sz, in: geo.size)
                .frame(width: sz.width, height: sz.height)
                .position(c)
        }
        .transition(.opacity)
    }

    // MARK: - Card

    @ViewBuilder
    private func card(size: CGSize, in bounds: CGSize) -> some View {
        VStack(spacing: 0) {
            handleBar(in: bounds, card: size)
            MetalBioView()
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
