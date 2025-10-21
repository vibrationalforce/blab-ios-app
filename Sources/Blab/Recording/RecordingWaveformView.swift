import SwiftUI

/// Real-time waveform visualization during recording
struct RecordingWaveformView: View {
    let waveformData: [Float]
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard !waveformData.isEmpty else {
                    // Draw placeholder when no data
                    drawPlaceholder(context: context, size: size)
                    return
                }

                // Draw waveform
                drawWaveform(context: context, size: size)

                // Draw level indicator
                drawLevelIndicator(context: context, size: size)
            }
        }
    }

    // MARK: - Drawing Methods

    private func drawPlaceholder(context: GraphicsContext, size: CGSize) {
        let midY = size.height / 2

        // Draw center line
        var centerPath = Path()
        centerPath.move(to: CGPoint(x: 0, y: midY))
        centerPath.addLine(to: CGPoint(x: size.width, y: midY))
        context.stroke(centerPath, with: .color(.white.opacity(0.2)), lineWidth: 1)

        // Draw placeholder text
        let text = Text("Waiting for audio...")
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.4))
        context.draw(text, at: CGPoint(x: size.width / 2, y: midY))
    }

    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        let width = size.width
        let height = size.height
        let midY = height / 2

        // Draw center line
        var centerPath = Path()
        centerPath.move(to: CGPoint(x: 0, y: midY))
        centerPath.addLine(to: CGPoint(x: width, y: midY))
        context.stroke(centerPath, with: .color(.white.opacity(0.1)), lineWidth: 1)

        // Draw waveform path
        var waveformPath = Path()
        let pointsPerPixel = max(1, waveformData.count / Int(width))

        for x in 0..<Int(width) {
            let dataIndex = x * pointsPerPixel
            if dataIndex < waveformData.count {
                let amplitude = CGFloat(waveformData[dataIndex])
                let y = midY - (amplitude * height * 0.4) // Scale to 40% of height

                if x == 0 {
                    waveformPath.move(to: CGPoint(x: CGFloat(x), y: y))
                } else {
                    waveformPath.addLine(to: CGPoint(x: CGFloat(x), y: y))
                }
            }
        }

        // Gradient stroke
        let gradient = Gradient(colors: [
            .cyan.opacity(0.8),
            .blue.opacity(0.8)
        ])

        let gradientFill = LinearGradient(
            gradient: gradient,
            startPoint: .leading,
            endPoint: .trailing
        )

        context.stroke(
            waveformPath,
            with: .linearGradient(
                gradient,
                startPoint: .leading,
                endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )

        // Add glow effect based on level
        if level > 0.1 {
            context.stroke(
                waveformPath,
                with: .color(.cyan.opacity(Double(level))),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            )
            .blendMode = .plusLighter
        }
    }

    private func drawLevelIndicator(context: GraphicsContext, size: CGSize) {
        let indicatorWidth: CGFloat = 4
        let indicatorHeight = size.height * 0.8
        let indicatorY = (size.height - indicatorHeight) / 2

        // Background
        var backgroundRect = Path()
        backgroundRect.addRoundedRect(
            in: CGRect(
                x: size.width - 20,
                y: indicatorY,
                width: indicatorWidth,
                height: indicatorHeight
            ),
            cornerSize: CGSize(width: 2, height: 2)
        )
        context.fill(backgroundRect, with: .color(.white.opacity(0.1)))

        // Level fill
        let fillHeight = indicatorHeight * CGFloat(level)
        var fillRect = Path()
        fillRect.addRoundedRect(
            in: CGRect(
                x: size.width - 20,
                y: indicatorY + (indicatorHeight - fillHeight),
                width: indicatorWidth,
                height: fillHeight
            ),
            cornerSize: CGSize(width: 2, height: 2)
        )

        let fillColor: Color = level > 0.8 ? .red : level > 0.6 ? .yellow : .green
        context.fill(fillRect, with: .color(fillColor))
    }
}

/// Preview provider
struct RecordingWaveformView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            // Empty state
            RecordingWaveformView(waveformData: [], level: 0.0)
                .frame(height: 100)
                .background(Color.black)

            // With data
            RecordingWaveformView(
                waveformData: (0..<1000).map { i in
                    sin(Float(i) * 0.1) * 0.5
                },
                level: 0.6
            )
            .frame(height: 100)
            .background(Color.black)
        }
    }
}
