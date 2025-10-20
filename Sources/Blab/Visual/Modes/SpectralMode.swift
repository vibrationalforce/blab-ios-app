import SwiftUI

/// Spectral analyzer visualization
/// Shows frequency spectrum as vertical bars (like a spectrum analyzer)
struct SpectralMode: View {
    /// FFT magnitude data (frequency bins)
    var fftMagnitudes: [Float]

    /// Audio level
    var audioLevel: Float

    /// HRV Coherence for color
    var hrvCoherence: Double

    /// Number of bars to display
    private let barCount = 32

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: geometry.size.width / CGFloat(barCount) * 0.2) {
                ForEach(0..<barCount, id: \.self) { index in
                    SpectrumBar(
                        magnitude: magnitude(for: index),
                        index: index,
                        totalBars: barCount,
                        hrvCoherence: hrvCoherence
                    )
                }
            }
            .padding(.horizontal, 20)
        }
        .background(Color.black.opacity(0.5))
    }

    /// Get magnitude for bar index
    private func magnitude(for index: Int) -> Float {
        guard !fftMagnitudes.isEmpty else { return 0 }

        // Map bar index to FFT bin
        let binIndex = Int(Float(index) / Float(barCount) * Float(fftMagnitudes.count))
        let clampedIndex = min(binIndex, fftMagnitudes.count - 1)

        return fftMagnitudes[clampedIndex]
    }
}

/// Single spectrum bar
struct SpectrumBar: View {
    var magnitude: Float
    var index: Int
    var totalBars: Int
    var hrvCoherence: Double

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()

                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [
                                barColor.opacity(0.8),
                                barColor
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: barHeight(maxHeight: geometry.size.height))
            }
        }
    }

    /// Calculate bar height based on magnitude
    private func barHeight(maxHeight: CGFloat) -> CGFloat {
        let normalizedMagnitude = CGFloat(min(magnitude, 1.0))
        return max(4, normalizedMagnitude * maxHeight)
    }

    /// Bar color based on frequency (low = red, high = blue)
    private var barColor: Color {
        // Base hue from HRV
        let baseHue = hrvCoherence / 100.0 * 0.5

        // Shift hue based on frequency (bar index)
        let frequencyHue = Double(index) / Double(totalBars) * 0.3  // 0-0.3 hue shift

        let finalHue = baseHue + frequencyHue

        return Color(hue: finalHue, saturation: 0.8, brightness: 0.9)
    }
}
