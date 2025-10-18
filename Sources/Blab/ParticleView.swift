import SwiftUI

/// Advanced particle visualization with physics simulation and biofeedback integration
/// Features:
/// - Dynamic particle count (10-500) scales with audio level
/// - HRV coherence color mapping (red → yellow → green)
/// - Voice pitch influences particle size
/// - Physics: gravity, turbulence (heart rate), center attractor (coherence)
/// - 60 FPS TimelineView updates
struct ParticleView: View {

    /// Whether the visualization is active (recording)
    let isActive: Bool

    /// Audio level (0.0 to 1.0) - drives particle count and motion intensity
    let audioLevel: Float

    /// Detected frequency in Hz (optional) - changes particle velocity
    let frequency: Float?

    /// Voice pitch in Hz (from YIN detector) - influences particle size
    let voicePitch: Float

    /// HRV coherence score (0-100) - determines color and attractor strength
    let hrvCoherence: Double

    /// Heart rate in BPM - controls turbulence
    let heartRate: Double

    /// Particle system state
    @State private var particles: [Particle] = []

    /// Last update time for physics calculations
    @State private var lastUpdateTime: Date?

    /// Target particle count based on audio level
    private var targetParticleCount: Int {
        let minCount = 10
        let maxCount = 500
        let range = maxCount - minCount
        return minCount + Int(Float(range) * audioLevel)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let now = timeline.date

                // Update physics if active
                if isActive {
                    updateParticles(center: center, currentTime: now, canvasSize: size)
                }

                // Draw all particles
                for particle in particles {
                    drawParticle(particle, in: context, canvasSize: size)
                }
            }
            .background(
                // Background glow that pulses with coherence
                RadialGradient(
                    gradient: Gradient(colors: [
                        coherenceColor.opacity(0.2 * min(hrvCoherence / 100.0, 1.0)),
                        coherenceColor.opacity(0.05 * min(hrvCoherence / 100.0, 1.0)),
                        Color.clear
                    ]),
                    center: .center,
                    startRadius: 20,
                    endRadius: 200
                )
                .scaleEffect(isActive ? 1.0 : 0.5)
                .animation(.easeInOut(duration: 2.0), value: hrvCoherence)
            )
        }
        .onAppear {
            initializeParticles()
        }
        .onChange(of: isActive) { newValue in
            if newValue {
                initializeParticles()
            } else {
                particles.removeAll()
            }
        }
    }


    // MARK: - Particle Management

    /// Initialize particle system
    private func initializeParticles() {
        let count = max(targetParticleCount, 10)
        particles = (0..<count).map { i in
            Particle(
                id: UUID(),
                position: CGPoint(
                    x: CGFloat.random(in: -100...100),
                    y: CGFloat.random(in: -100...100)
                ),
                velocity: CGVector(
                    dx: CGFloat.random(in: -20...20),
                    dy: CGFloat.random(in: -20...20)
                ),
                size: CGFloat.random(in: 2...8),
                color: coherenceColor,
                alpha: Float.random(in: 0.3...0.8),
                lifetime: Double.random(in: 2.0...5.0),
                age: 0.0
            )
        }
        lastUpdateTime = Date()
    }

    /// Update particle physics
    private func updateParticles(center: CGPoint, currentTime: Date, canvasSize: CGSize) {
        guard let lastTime = lastUpdateTime else {
            lastUpdateTime = currentTime
            return
        }

        let deltaTime = currentTime.timeIntervalSince(lastTime)
        guard deltaTime > 0 else { return }

        lastUpdateTime = currentTime

        // Adjust particle count dynamically
        adjustParticleCount()

        // Physics parameters
        let gravity = CGVector(dx: 0, dy: 5.0)  // Subtle downward force
        let turbulence = Float(heartRate) / 60.0  // Normalized heart rate
        let attractorStrength = Float(hrvCoherence) / 100.0  // Coherence influences pull to center

        // Update each particle
        for i in 0..<particles.count {
            var particle = particles[i]

            // Age the particle
            particle.age += deltaTime
            if particle.age >= particle.lifetime {
                // Respawn particle
                particles[i] = spawnNewParticle(near: center)
                continue
            }

            // Calculate distance to center
            let dx = center.x - particle.position.x
            let dy = center.y - particle.position.y
            let distance = sqrt(dx * dx + dy * dy)

            // Center attractor force (stronger with high coherence)
            if distance > 1 {
                let attractorForce = CGVector(
                    dx: (dx / distance) * CGFloat(attractorStrength) * 50.0,
                    dy: (dy / distance) * CGFloat(attractorStrength) * 50.0
                )

                particle.velocity.dx += attractorForce.dx * CGFloat(deltaTime)
                particle.velocity.dy += attractorForce.dy * CGFloat(deltaTime)
            }

            // Gravity
            particle.velocity.dx += gravity.dx * CGFloat(deltaTime)
            particle.velocity.dy += gravity.dy * CGFloat(deltaTime)

            // Turbulence (random jitter based on heart rate)
            let turbulenceForce = CGVector(
                dx: CGFloat.random(in: -1...1) * CGFloat(turbulence) * 30.0,
                dy: CGFloat.random(in: -1...1) * CGFloat(turbulence) * 30.0
            )
            particle.velocity.dx += turbulenceForce.dx * CGFloat(deltaTime)
            particle.velocity.dy += turbulenceForce.dy * CGFloat(deltaTime)

            // Audio level amplifies velocity
            let audioAmplifier = 1.0 + CGFloat(audioLevel) * 2.0
            particle.velocity.dx *= audioAmplifier * CGFloat(deltaTime)
            particle.velocity.dy *= audioAmplifier * CGFloat(deltaTime)

            // Damping (friction)
            particle.velocity.dx *= 0.98
            particle.velocity.dy *= 0.98

            // Update position
            particle.position.x += particle.velocity.dx * CGFloat(deltaTime) * 10.0
            particle.position.y += particle.velocity.dy * CGFloat(deltaTime) * 10.0

            // Voice pitch influences size
            if voicePitch > 0 {
                let pitchFactor = CGFloat(voicePitch) / 440.0  // Normalized to A440
                particle.size = 2.0 + pitchFactor * 6.0
            }

            // Update color based on coherence
            particle.color = coherenceColor

            // Fade in/out based on lifetime
            let lifetimeRatio = particle.age / particle.lifetime
            if lifetimeRatio < 0.1 {
                particle.alpha = Float(lifetimeRatio * 10.0)  // Fade in
            } else if lifetimeRatio > 0.9 {
                particle.alpha = Float((1.0 - lifetimeRatio) * 10.0)  // Fade out
            } else {
                particle.alpha = min(0.8, Float(audioLevel) + 0.3)
            }

            particles[i] = particle
        }
    }

    /// Adjust particle count dynamically
    private func adjustParticleCount() {
        let target = targetParticleCount
        let current = particles.count

        if current < target {
            // Spawn new particles
            let toSpawn = min(target - current, 10)  // Max 10 per frame
            for _ in 0..<toSpawn {
                particles.append(spawnNewParticle(near: CGPoint(x: 0, y: 0)))
            }
        } else if current > target {
            // Remove oldest particles
            let toRemove = min(current - target, 10)  // Max 10 per frame
            particles.sort { $0.age > $1.age }
            particles.removeLast(toRemove)
        }
    }

    /// Spawn a new particle near a point
    private func spawnNewParticle(near point: CGPoint) -> Particle {
        Particle(
            id: UUID(),
            position: CGPoint(
                x: point.x + CGFloat.random(in: -50...50),
                y: point.y + CGFloat.random(in: -50...50)
            ),
            velocity: CGVector(
                dx: CGFloat.random(in: -20...20),
                dy: CGFloat.random(in: -20...20)
            ),
            size: CGFloat.random(in: 2...8),
            color: coherenceColor,
            alpha: 0.0,  // Will fade in
            lifetime: Double.random(in: 2.0...5.0),
            age: 0.0
        )
    }

    /// Draw a single particle
    private func drawParticle(_ particle: Particle, in context: GraphicsContext, canvasSize: CGSize) {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

        let x = center.x + particle.position.x
        let y = center.y + particle.position.y

        // Skip particles outside canvas
        guard x >= -50 && x <= canvasSize.width + 50 &&
              y >= -50 && y <= canvasSize.height + 50 else {
            return
        }

        let rect = CGRect(
            x: x - particle.size / 2,
            y: y - particle.size / 2,
            width: particle.size,
            height: particle.size
        )

        context.fill(
            Circle().path(in: rect),
            with: .color(particle.color.opacity(Double(particle.alpha)))
        )

        // Optional glow effect for high coherence
        if hrvCoherence > 60 {
            context.fill(
                Circle().path(in: rect.insetBy(dx: -2, dy: -2)),
                with: .color(particle.color.opacity(Double(particle.alpha) * 0.2))
            )
        }
    }


    // MARK: - Color Mapping

    /// Map HRV coherence to color (HeartMath zones)
    /// 0-40: Red (low coherence, stress)
    /// 40-60: Yellow (medium coherence, transition)
    /// 60-100: Green (high coherence, optimal state)
    private var coherenceColor: Color {
        if hrvCoherence < 40 {
            return Color(hue: 0.0, saturation: 0.8, brightness: 0.9)  // Red
        } else if hrvCoherence < 60 {
            return Color(hue: 0.15, saturation: 0.9, brightness: 0.95)  // Yellow
        } else {
            return Color(hue: 0.35, saturation: 0.8, brightness: 0.9)  // Green
        }
    }
}


// MARK: - Particle Model

/// Particle with physics properties and lifetime
struct Particle: Identifiable {
    let id: UUID
    var position: CGPoint
    var velocity: CGVector
    var size: CGFloat
    var color: Color
    var alpha: Float
    let lifetime: Double
    var age: Double
}


// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 40) {
            Text("Low Coherence (Red, Stress)")
                .foregroundColor(.white)
                .font(.caption)
            ParticleView(
                isActive: true,
                audioLevel: 0.5,
                frequency: 200,
                voicePitch: 220,
                hrvCoherence: 20,
                heartRate: 80
            )
            .frame(height: 200)

            Text("High Coherence (Green, Optimal)")
                .foregroundColor(.white)
                .font(.caption)
            ParticleView(
                isActive: true,
                audioLevel: 0.8,
                frequency: 440,
                voicePitch: 440,
                hrvCoherence: 85,
                heartRate: 65
            )
            .frame(height: 200)
        }
    }
}
