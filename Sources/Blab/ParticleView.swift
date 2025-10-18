import SwiftUI

/// Advanced particle visualization that reacts to audio input
/// Now with 150+ particles, frequency-reactive colors, and amplitude-driven motion
struct ParticleView: View {

    /// Whether the visualization is active (recording)
    let isActive: Bool

    /// Audio level (0.0 to 1.0) - drives particle size and motion intensity
    let audioLevel: Float

    /// Detected frequency in Hz (optional) - changes particle colors
    let frequency: Float?

    /// Animation state for the pulsing effect
    @State private var pulseScale: CGFloat = 1.0

    /// Rotation animation
    @State private var rotation: Double = 0

    /// Individual particle data for advanced rendering
    @State private var particles: [ParticleData] = []

    /// Number of particles to render
    private let particleCount = 150

    var body: some View {
        ZStack {
            // Background circle - pulses with audio
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.3 * Double(audioLevel)),
                            Color.blue.opacity(0.1 * Double(audioLevel)),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 20,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .scaleEffect(isActive ? (1.0 + CGFloat(audioLevel) * 0.5) : 0.8)
                .opacity(isActive ? 1.0 : 0.3)

            // Rotating rings - speed varies with audio level
            ForEach(0..<3) { index in
                Circle()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                frequencyColor.opacity(0.6),
                                Color.purple.opacity(0.4),
                                Color.pink.opacity(0.6)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2 + CGFloat(audioLevel) * 3
                    )
                    .frame(width: CGFloat(100 + index * 60),
                           height: CGFloat(100 + index * 60))
                    .rotationEffect(.degrees(rotation + Double(index * 120)))
                    .opacity(isActive ? 0.8 : 0.2)
            }

            // Center dot - size pulses with audio
            Circle()
                .fill(Color.white)
                .frame(width: 20 + CGFloat(audioLevel) * 30,
                       height: 20 + CGFloat(audioLevel) * 30)
                .shadow(color: frequencyColor, radius: isActive ? 10 + CGFloat(audioLevel) * 20 : 5)
                .scaleEffect(isActive ? pulseScale : 0.5)

            // Main particle system - 150 particles!
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                // Initialize particles if needed
                if particles.isEmpty {
                    particles = (0..<particleCount).map { i in
                        ParticleData(
                            angle: Double(i) * (360.0 / Double(particleCount)) * .pi / 180.0,
                            distance: CGFloat.random(in: 50...150),
                            speed: CGFloat.random(in: 0.5...2.0),
                            size: CGFloat.random(in: 2...6),
                            phase: CGFloat.random(in: 0...(2 * .pi))
                        )
                    }
                }

                // Draw all particles
                for particle in particles {
                    let animatedDistance = particle.distance * (1.0 + CGFloat(audioLevel) * 0.8)
                    let x = center.x + cos(particle.angle + Double(rotation) * .pi / 180.0) * animatedDistance
                    let y = center.y + sin(particle.angle + Double(rotation) * .pi / 180.0) * animatedDistance

                    let animatedSize = particle.size * (1.0 + CGFloat(audioLevel) * 2.0)

                    let rect = CGRect(
                        x: x - animatedSize / 2,
                        y: y - animatedSize / 2,
                        width: animatedSize,
                        height: animatedSize
                    )

                    let opacity = isActive ? 0.6 + Double(audioLevel) * 0.4 : 0.0

                    context.fill(
                        Circle().path(in: rect),
                        with: .color(frequencyColor.opacity(opacity))
                    )
                }
            }
        }
        .onAppear {
            if isActive {
                startAnimations()
            }
        }
        .onChange(of: isActive) { newValue in
            if newValue {
                startAnimations()
            }
        }
    }

    /// Color changes based on detected frequency
    private var frequencyColor: Color {
        guard let freq = frequency, freq > 0 else {
            return Color.cyan
        }

        // Map frequency to hue
        // Low frequencies (50-200 Hz) = blue
        // Mid frequencies (200-500 Hz) = cyan/green
        // High frequencies (500-2000 Hz) = yellow/orange
        let normalizedFreq = min(max((freq - 50) / 1950, 0), 1)
        return Color(hue: 0.5 + Double(normalizedFreq) * 0.3, saturation: 0.8, brightness: 0.9)
    }

    /// Start the particle animations
    private func startAnimations() {
        // Pulsing animation
        withAnimation(
            Animation.easeInOut(duration: 1.0)
                .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.2
        }

        // Rotation animation - speed varies with audio
        let rotationSpeed = 8.0 - Double(audioLevel) * 3.0 // Faster when louder
        withAnimation(
            Animation.linear(duration: rotationSpeed)
                .repeatForever(autoreverses: false)
        ) {
            rotation = 360
        }
    }
}

/// Data structure for individual particle
struct ParticleData: Identifiable {
    let id = UUID()
    let angle: Double
    let distance: CGFloat
    let speed: CGFloat
    let size: CGFloat
    let phase: CGFloat
}

/// Preview for Xcode canvas
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 40) {
            Text("Quiet (0.1)")
                .foregroundColor(.white)
            ParticleView(isActive: true, audioLevel: 0.1, frequency: 100)

            Text("Medium (0.5)")
                .foregroundColor(.white)
            ParticleView(isActive: true, audioLevel: 0.5, frequency: 440)

            Text("Loud (1.0)")
                .foregroundColor(.white)
            ParticleView(isActive: true, audioLevel: 1.0, frequency: 1000)
        }
    }
}
