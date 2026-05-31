#if canImport(SwiftUI)
import SwiftUI

/// Immersive bio-reactive visual — the "multimedial" surface where the body
/// drives the image. Concentric rings pulse at the heart rate, hue tracks
/// coherence, and the breath spreads them. Pure SwiftUI Canvas + TimelineView
/// reading the EngineBus snapshot — no Metal, no deprecated engines.
///
/// Flash-safe: all motion is smooth sinusoidal at ≤2 Hz (heart rate is clamped
/// to [0.5, 2.0] Hz), never a strobe — within the 3 Hz WCAG epilepsy limit.
/// A small legend keeps it science-reflecting (each element maps to real data).
@MainActor
struct BioVisualView: View {

    @Environment(EngineBus.self) private var bus
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    render(into: context, size: size,
                           time: timeline.date.timeIntervalSinceReferenceDate)
                }
                .ignoresSafeArea()
            }

            overlay
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
    }

    private func render(into context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let bio = bus.latestBio
        let hr = bio?.heartRateBPM ?? 60
        let coherence = Double(bio?.coherence ?? 0.5)
        let hrv = Double(bio?.hrvNormalized ?? 0.5)
        let breath = Double(bio?.breathPhase ?? 0.5)

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let pulseHz = min(max(Double(hr) / 60.0, 0.5), 2.0)   // ≤3 Hz, smooth
        let hue = 0.0 + coherence * 0.45                       // red → cyan
        let base = Double(min(size.width, size.height)) * 0.12
        let ringCount = 5 + Int(hrv * 4)                       // 5…9
        let breathScale = 0.85 + breath * 0.3

        for i in 0..<ringCount {
            let phase = Double(i) / Double(ringCount)
            let pulse = 0.5 + 0.5 * sin(2 * .pi * (time * pulseHz - phase))
            let radius = (base + (Double(i) * 28 + pulse * 24)) * breathScale
            let opacity = (1.0 - Double(i) / Double(ringCount)) * (0.35 + 0.5 * pulse)
            let color = Color(hue: hue, saturation: 0.7, brightness: 0.9).opacity(opacity)
            let rect = CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 2)
        }

        // Center disc pulsing on the beat.
        let beat = 0.5 + 0.5 * sin(2 * .pi * time * pulseHz)
        let dotR = base * (0.4 + 0.4 * beat)
        let dotRect = CGRect(x: center.x - dotR, y: center.y - dotR,
                             width: dotR * 2, height: dotR * 2)
        context.fill(Path(ellipseIn: dotRect),
                     with: .color(Color(hue: hue, saturation: 0.6, brightness: 1.0).opacity(0.45)))
    }

    private var overlay: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding()
            }
            Spacer()
            HStack(spacing: 16) {
                legend("rings = heartbeat")
                legend("color = coherence")
                legend("spread = breath")
            }
            .padding(.bottom, 28)
        }
    }

    private func legend(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(.white.opacity(0.5))
    }
}
#endif
