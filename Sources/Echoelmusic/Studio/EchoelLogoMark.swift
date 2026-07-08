#if canImport(SwiftUI)
import SwiftUI

// EchoelLogoMark.swift
// Echoel — the brand mark, drawn (not an imported asset) so it scales crisply and
// follows the theme. It reproduces the app icon / website logo (docs/app-icon.svg):
// a bold "E" over three stacked waves of decreasing opacity, grayscale on black.
// Coordinates mirror the 100×100 SVG viewBox so it matches the icon exactly.

struct EchoelLogoMark: View {
    /// Mark colour (the CI grayscale = EchoelTheme.text by default).
    var color: Color = EchoelTheme.text

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100.0

            // Three waves at y = 60 / 70 / 80 (SVG), opacity 0.8 / 0.4 / 0.2.
            func wave(_ dy: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: 24 * s, y: (60 + dy) * s))
                p.addCurve(to: CGPoint(x: 42 * s, y: (60 + dy) * s),
                           control1: CGPoint(x: 29 * s, y: (54 + dy) * s),
                           control2: CGPoint(x: 37 * s, y: (54 + dy) * s))
                p.addCurve(to: CGPoint(x: 58 * s, y: (60 + dy) * s),
                           control1: CGPoint(x: 47 * s, y: (66 + dy) * s),
                           control2: CGPoint(x: 53 * s, y: (66 + dy) * s))
                p.addCurve(to: CGPoint(x: 76 * s, y: (60 + dy) * s),
                           control1: CGPoint(x: 63 * s, y: (54 + dy) * s),
                           control2: CGPoint(x: 71 * s, y: (54 + dy) * s))
                return p
            }
            for (dy, op) in [(0.0, 0.8), (10.0, 0.4), (20.0, 0.2)] {
                ctx.stroke(wave(dy), with: .color(color.opacity(op)),
                           style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
            }

            // The "E" (bold), centred to sit above the waves. Resolve + set shading
            // so the colour is explicit (no deprecated Text.foregroundColor).
            var e = ctx.resolve(Text("E").font(.system(size: 52 * s, weight: .bold)))
            e.shading = .color(color)
            ctx.draw(e, at: CGPoint(x: 50 * s, y: 30 * s), anchor: .center)
        }
        .foregroundStyle(color)
        .accessibilityLabel("Echoelmusic")
    }
}
#endif
