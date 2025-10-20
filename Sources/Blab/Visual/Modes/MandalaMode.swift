import SwiftUI

/// Mandala visualization with radial symmetry
/// Creates sacred geometry patterns that respond to audio and bio-signals
struct MandalaMode: View {
    /// Audio level
    var audioLevel: Float

    /// Frequency
    var frequency: Float

    /// HRV Coherence
    var hrvCoherence: Double

    /// Heart Rate
    var heartRate: Double

    /// Animation time
    @State private var time: Double = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2.5

                // Update time
                let currentTime = timeline.date.timeIntervalSince1970

                // Draw multiple layers
                for layer in 0..<6 {
                    drawMandalaLayer(
                        context: context,
                        center: center,
                        radius: radius * (1.0 - CGFloat(layer) * 0.15),
                        layer: layer,
                        time: currentTime
                    )
                }
            }
        }
        .background(Color.black.opacity(0.5))
    }

    /// Draw a single mandala layer
    private func drawMandalaLayer(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        layer: Int,
        time: Double
    ) {
        // Number of petals based on frequency
        let petalCount = Int(6 + frequency / 100.0 * 6)  // 6-12 petals

        // Rotation based on heart rate
        let rotationSpeed = heartRate / 60.0  // 1 rotation per heartbeat
        let rotation = time * rotationSpeed + Double(layer) * 0.5

        // Color based on HRV
        let hue = hrvCoherence / 100.0 * 0.5
        let color = Color(hue: hue, saturation: 0.7, brightness: 0.8)

        // Draw petals
        for i in 0..<petalCount {
            let angle = (Double(i) / Double(petalCount) * 2.0 * .pi) + rotation

            // Petal position
            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius

            // Petal size modulated by audio
            let petalSize = 20.0 + CGFloat(audioLevel) * 40.0

            // Draw petal
            var path = Path()
            path.addEllipse(in: CGRect(
                x: x - petalSize / 2,
                y: y - petalSize / 2,
                width: petalSize,
                height: petalSize
            ))

            context.fill(path, with: .color(color.opacity(0.3)))
            context.stroke(path, with: .color(color), lineWidth: 1)
        }

        // Draw center circle
        if layer == 0 {
            let centerSize = 30.0 + CGFloat(audioLevel) * 20.0
            var centerPath = Path()
            centerPath.addEllipse(in: CGRect(
                x: center.x - centerSize / 2,
                y: center.y - centerSize / 2,
                width: centerSize,
                height: centerSize
            ))

            context.fill(centerPath, with: .color(color.opacity(0.5)))
            context.stroke(centerPath, with: .color(color), lineWidth: 2)
        }
    }
}
