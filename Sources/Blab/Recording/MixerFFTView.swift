import SwiftUI

/// Real-time FFT visualization for mixer channels
struct MixerFFTView: View {
    let fftMagnitudes: [Float]
    let trackColor: Color

    private let barCount = 32

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard !fftMagnitudes.isEmpty else {
                    drawPlaceholder(context: context, size: size)
                    return
                }

                drawFFTBars(context: context, size: size)
            }
        }
    }

    // MARK: - Drawing

    private func drawPlaceholder(context: GraphicsContext, size: CGSize) {
        // Draw placeholder bars
        let barWidth = (size.width - CGFloat(barCount - 1) * 2) / CGFloat(barCount)

        for i in 0..<barCount {
            let x = CGFloat(i) * (barWidth + 2)
            let height = size.height * 0.1

            var barPath = Path()
            barPath.addRoundedRect(
                in: CGRect(
                    x: x,
                    y: size.height - height,
                    width: barWidth,
                    height: height
                ),
                cornerSize: CGSize(width: 2, height: 2)
            )

            context.fill(barPath, with: .color(.white.opacity(0.1)))
        }
    }

    private func drawFFTBars(context: GraphicsContext, size: CGSize) {
        let barWidth = (size.width - CGFloat(barCount - 1) * 2) / CGFloat(barCount)
        let binRatio = fftMagnitudes.count / barCount

        for i in 0..<barCount {
            // Get average magnitude for this bar
            let startIdx = i * binRatio
            let endIdx = min(startIdx + binRatio, fftMagnitudes.count)

            var sum: Float = 0
            for j in startIdx..<endIdx {
                sum += fftMagnitudes[j]
            }
            let avgMagnitude = sum / Float(endIdx - startIdx)

            // Normalize and scale
            let normalizedHeight = min(CGFloat(avgMagnitude) * 2.0, 1.0)
            let barHeight = size.height * normalizedHeight

            // Position
            let x = CGFloat(i) * (barWidth + 2)
            let y = size.height - barHeight

            // Draw bar
            var barPath = Path()
            barPath.addRoundedRect(
                in: CGRect(x: x, y: y, width: barWidth, height: barHeight),
                cornerSize: CGSize(width: 2, height: 2)
            )

            // Gradient based on frequency (low = warm, high = cool)
            let hue = Double(i) / Double(barCount)
            let gradient = Gradient(colors: [
                trackColor.opacity(0.8),
                trackColor.opacity(0.4)
            ])

            context.fill(
                barPath,
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: x, y: size.height),
                    endPoint: CGPoint(x: x, y: y)
                )
            )

            // Add glow for high levels
            if normalizedHeight > 0.7 {
                context.fill(
                    barPath,
                    with: .color(trackColor.opacity(Double(normalizedHeight - 0.7)))
                )
                .blendMode = .plusLighter
            }
        }
    }
}

/// Compact FFT meter for mixer channel strips
struct CompactFFTMeter: View {
    let fftMagnitudes: [Float]
    let trackColor: Color

    var body: some View {
        MixerFFTView(fftMagnitudes: fftMagnitudes, trackColor: trackColor)
            .frame(height: 60)
    }
}
