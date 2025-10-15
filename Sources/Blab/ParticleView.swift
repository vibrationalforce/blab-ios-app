import SwiftUI

/// A beautiful particle visualization that responds to audio
/// This will eventually display particles that react to your voice
struct ParticleView: View {

    /// Whether the visualization is active (recording)
    let isActive: Bool

    /// Animation state for the pulsing effect
    @State private var pulseScale: CGFloat = 1.0

    /// Rotation animation
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.3),
                            Color.blue.opacity(0.1),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 20,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .scaleEffect(isActive ? pulseScale : 0.8)
                .opacity(isActive ? 1.0 : 0.3)

            // Rotating rings
            ForEach(0..<3) { index in
                Circle()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.cyan.opacity(0.6),
                                Color.purple.opacity(0.4),
                                Color.pink.opacity(0.6)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: CGFloat(100 + index * 60),
                           height: CGFloat(100 + index * 60))
                    .rotationEffect(.degrees(rotation + Double(index * 120)))
                    .opacity(isActive ? 0.8 : 0.2)
            }

            // Center dot
            Circle()
                .fill(Color.white)
                .frame(width: 20, height: 20)
                .shadow(color: .cyan, radius: isActive ? 10 : 5)
                .scaleEffect(isActive ? pulseScale : 0.5)

            // Particle dots (placeholder for future particle system)
            ForEach(0..<8) { index in
                Circle()
                    .fill(Color.cyan.opacity(0.7))
                    .frame(width: 8, height: 8)
                    .offset(x: isActive ? cos(Double(index) * .pi / 4) * 80 : 0,
                            y: isActive ? sin(Double(index) * .pi / 4) * 80 : 0)
                    .opacity(isActive ? 1.0 : 0.0)
            }
        }
        .onAppear {
            // Start animations when the view appears
            startAnimations()
        }
        .onChange(of: isActive) { newValue in
            if newValue {
                startAnimations()
            }
        }
    }

    /// Start the particle animations
    private func startAnimations() {
        // Pulsing animation
        withAnimation(
            Animation.easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.2
        }

        // Rotation animation
        withAnimation(
            Animation.linear(duration: 10)
                .repeatForever(autoreverses: false)
        ) {
            rotation = 360
        }
    }
}

/// Preview for Xcode canvas
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 40) {
            Text("Inactive State")
                .foregroundColor(.white)
            ParticleView(isActive: false)

            Text("Active State")
                .foregroundColor(.white)
            ParticleView(isActive: true)
        }
    }
}
