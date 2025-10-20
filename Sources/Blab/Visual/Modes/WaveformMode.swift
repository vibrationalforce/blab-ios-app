import SwiftUI

/// Classic oscilloscope waveform visualization
/// Shows audio waveform in real-time like a traditional oscilloscope
struct WaveformMode: View {
    /// Audio buffer data
    var audioBuffer: [Float]

    /// Audio level (0.0 - 1.0)
    var audioLevel: Float

    /// HRV Coherence for color
    var hrvCoherence: Double

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let centerY = height / 2

            // Draw center line
            var centerPath = Path()
            centerPath.move(to: CGPoint(x: 0, y: centerY))
            centerPath.addLine(to: CGPoint(x: width, y: centerY))

            context.stroke(
                centerPath,
                with: .color(.white.opacity(0.2)),
                lineWidth: 1
            )

            // Draw waveform
            guard !audioBuffer.isEmpty else { return }

            var waveformPath = Path()

            // Sample buffer for display
            let samplesPerPixel = max(1, audioBuffer.count / Int(width))
            let displaySamples = stride(from: 0, to: audioBuffer.count, by: samplesPerPixel)

            for (index, sampleIndex) in displaySamples.enumerated() {
                let x = CGFloat(index) * (width / CGFloat(displaySamples.count))
                let sample = audioBuffer[sampleIndex]
                let y = centerY + CGFloat(sample) * (height * 0.4)  // Scale to 40% of height

                if index == 0 {
                    waveformPath.move(to: CGPoint(x: x, y: y))
                } else {
                    waveformPath.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Color based on HRV Coherence
            let hue = hrvCoherence / 100.0 * 0.5  // 0.0 (red) to 0.5 (cyan)
            let waveColor = Color(hue: hue, saturation: 0.8, brightness: 0.9)

            context.stroke(
                waveformPath,
                with: .color(waveColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            // Add glow effect
            if audioLevel > 0.1 {
                context.stroke(
                    waveformPath,
                    with: .color(waveColor.opacity(0.3)),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .background(Color.black.opacity(0.5))
    }
}
