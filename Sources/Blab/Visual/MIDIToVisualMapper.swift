import Foundation
import SwiftUI
import Combine

/// Maps MIDI/MPE parameters to visual system parameters
/// Cymatics, Mandala, Waveform, Spectral visualizations
/// Integrates with Metal shaders and SwiftUI Canvas
@MainActor
class MIDIToVisualMapper: ObservableObject {

    // MARK: - Published Visual Parameters

    @Published var cymaticsParameters = CymaticsParameters()
    @Published var mandalaParameters = MandalaParameters()
    @Published var waveformParameters = WaveformParameters()
    @Published var spectralParameters = SpectralParameters()
    @Published var particleParameters = ParticleParameters()

    // MARK: - Active Notes Tracking

    private var activeNotes: [UInt8: NoteVisualState] = [:]

    struct NoteVisualState {
        let note: UInt8
        let velocity: Float
        var pitchBend: Float = 0.0
        var brightness: Float = 0.5
        var timbre: Float = 0.5
        let timestamp: Date = Date()
    }

    // MARK: - Visual Parameter Structures

    struct CymaticsParameters {
        var frequency: Float = 440.0          // Note → Chladni pattern frequency
        var amplitude: Float = 0.5            // Velocity → Pattern amplitude
        var hue: Float = 0.5                  // HRV Coherence → Color hue (0-1)
        var patterns: [ChladniPattern] = []   // Active patterns per note

        struct ChladniPattern {
            let frequency: Float
            let amplitude: Float
            let position: SIMD2<Float>
            let phase: Float
        }
    }

    struct MandalaParameters {
        var petalCount: Int = 8               // Note → Petal count (6-12)
        var petalSize: Float = 0.5            // Velocity → Petal size
        var rotationSpeed: Float = 1.0        // Heart rate → Rotation
        var hue: Float = 0.5                  // HRV → Color hue
        var layers: [MandalaLayer] = []       // Multi-layer mandala

        struct MandalaLayer {
            let petalCount: Int
            let petalSize: Float
            let rotationSpeed: Float
            let color: Color
            let depth: Float
        }
    }

    struct WaveformParameters {
        var waveform: [Float] = []            // Audio buffer
        var amplitude: Float = 1.0            // Overall amplitude
        var color: Color = .cyan              // HRV-based color
        var glowIntensity: Float = 0.5        // Audio level → Glow
    }

    struct SpectralParameters {
        var magnitudes: [Float] = []          // FFT magnitudes (32 bars)
        var hue: Float = 0.5                  // HRV → Base hue
        var barGradient: [Color] = []         // Frequency-based gradient
    }

    struct ParticleParameters {
        var particles: [Particle] = []        // Active particles
        var emissionRate: Float = 10.0        // Notes → Emission rate
        var particleColor: Color = .white
        var particleSize: Float = 2.0
        var velocity: SIMD2<Float> = SIMD2(0, 1)

        struct Particle {
            let id: UUID = UUID()
            var position: SIMD2<Float>
            var velocity: SIMD2<Float>
            var lifetime: Float
            var size: Float
            var color: Color
        }
    }

    // MARK: - Biometric Data Structure

    /// Bio-reactive visual data from HealthKit/sensors
    struct BioParameters {
        var hrvCoherence: Double
        var heartRate: Double
        var breathingRate: Double
        var audioLevel: Float
    }

    // MARK: - MIDI → Visual Mapping

    /// Map MIDI note on to visual parameters
    func handleNoteOn(note: UInt8, velocity: Float) {
        let state = NoteVisualState(note: note, velocity: velocity)
        activeNotes[note] = state

        // Update Cymatics
        updateCymaticsFromNote(note: note, velocity: velocity)

        // Update Mandala
        updateMandalaFromNote(note: note, velocity: velocity)

        // Emit particles
        emitParticlesFromNote(note: note, velocity: velocity)

        print("🎨 Visual mapped: Note \(note), Vel \(Int(velocity * 127))")
    }

    /// Map MIDI note off to visual parameters
    func handleNoteOff(note: UInt8) {
        activeNotes.removeValue(forKey: note)

        // Remove Cymatics pattern
        cymaticsParameters.patterns.removeAll { pattern in
            abs(pattern.frequency - midiNoteToFrequency(note)) < 1.0
        }
    }

    /// Map per-note pitch bend to visual parameters
    func handlePitchBend(note: UInt8, bend: Float) {
        guard var state = activeNotes[note] else { return }
        state.pitchBend = bend
        activeNotes[note] = state

        // Bend Cymatics frequency
        updateCymaticsFromNote(note: note, velocity: state.velocity, pitchBend: bend)

        // Rotate Mandala faster/slower
        let bendFactor = 1.0 + (bend * 0.5)  // ±50% rotation speed
        mandalaParameters.rotationSpeed *= bendFactor
    }

    /// Map per-note brightness (CC 74) to visual parameters
    func handleBrightness(note: UInt8, brightness: Float) {
        guard var state = activeNotes[note] else { return }
        state.brightness = brightness
        activeNotes[note] = state

        // Increase Cymatics amplitude
        if let index = cymaticsParameters.patterns.firstIndex(where: { pattern in
            abs(pattern.frequency - midiNoteToFrequency(note)) < 1.0
        }) {
            cymaticsParameters.patterns[index] = CymaticsParameters.ChladniPattern(
                frequency: cymaticsParameters.patterns[index].frequency,
                amplitude: brightness,
                position: cymaticsParameters.patterns[index].position,
                phase: cymaticsParameters.patterns[index].phase
            )
        }

        // Increase particle glow
        particleParameters.particleSize = 2.0 + (brightness * 3.0)
    }

    /// Map per-note timbre (CC 71) to visual parameters
    func handleTimbre(note: UInt8, timbre: Float) {
        guard var state = activeNotes[note] else { return }
        state.timbre = timbre
        activeNotes[note] = state

        // Change Mandala petal count based on timbre
        let petalCount = 6 + Int(timbre * 6.0)  // 6-12 petals
        mandalaParameters.petalCount = petalCount
    }

    // MARK: - Biometric → Visual Mapping

    /// Update visuals from bio-reactive data (UnifiedControlHub interface)
    func updateBioParameters(_ bioParams: BioParameters) {
        updateFromBioSignals(
            hrvCoherence: bioParams.hrvCoherence,
            heartRate: bioParams.heartRate
        )
        updateFromAudioLevel(bioParams.audioLevel)
    }

    /// Map HRV coherence to visual parameters
    func updateFromBioSignals(hrvCoherence: Double, heartRate: Double) {
        // HRV → Color hue (0-100 → 0.0-1.0)
        let hue = Float(hrvCoherence) / 100.0
        cymaticsParameters.hue = hue
        mandalaParameters.hue = hue
        spectralParameters.hue = hue

        // Update waveform color
        waveformParameters.color = Color(hue: Double(hue), saturation: 0.8, brightness: 0.9)

        // Heart rate → Mandala rotation speed
        let rotationSpeed = Float(heartRate) / 60.0  // BPM → rotations/sec
        mandalaParameters.rotationSpeed = rotationSpeed

        // Update particle color
        particleParameters.particleColor = Color(hue: Double(hue), saturation: 1.0, brightness: 1.0)
    }

    /// Map audio level to visual parameters
    func updateFromAudioLevel(_ level: Float) {
        waveformParameters.glowIntensity = level
        cymaticsParameters.amplitude = level
    }

    /// Map audio buffer to waveform
    func updateWaveform(buffer: [Float]) {
        waveformParameters.waveform = buffer
    }

    /// Map FFT magnitudes to spectral view
    func updateSpectral(magnitudes: [Float]) {
        spectralParameters.magnitudes = magnitudes

        // Generate gradient based on frequency
        spectralParameters.barGradient = magnitudes.enumerated().map { index, _ in
            let hue = Double(index) / Double(magnitudes.count)  // 0-1 across spectrum
            return Color(hue: hue, saturation: 0.8, brightness: 0.9)
        }
    }

    // MARK: - Cymatics Mapping

    private func updateCymaticsFromNote(note: UInt8, velocity: Float, pitchBend: Float = 0.0) {
        let baseFrequency = midiNoteToFrequency(note)
        let bentFrequency = baseFrequency * pow(2.0, pitchBend / 12.0)  // ±1 octave per bend unit

        // Map note to position on screen
        let x = (Float(note) - 60.0) / 30.0  // Center at middle C (60)
        let y = velocity - 0.5

        let pattern = CymaticsParameters.ChladniPattern(
            frequency: bentFrequency,
            amplitude: velocity,
            position: SIMD2(x, y),
            phase: 0.0
        )

        // Add or update pattern
        if let index = cymaticsParameters.patterns.firstIndex(where: { pattern in
            abs(pattern.frequency - bentFrequency) < 1.0
        }) {
            cymaticsParameters.patterns[index] = pattern
        } else {
            cymaticsParameters.patterns.append(pattern)
        }

        // Update primary frequency (for single-note mode)
        cymaticsParameters.frequency = bentFrequency
        cymaticsParameters.amplitude = velocity
    }

    // MARK: - Mandala Mapping

    private func updateMandalaFromNote(note: UInt8, velocity: Float) {
        // Map note to petal count (C=6, C#=7, ..., B=11, wrap)
        let petalCount = 6 + Int(note % 12) / 2  // 6-11 petals
        mandalaParameters.petalCount = petalCount

        // Map velocity to petal size
        mandalaParameters.petalSize = velocity

        // Add layer for polyphonic visualization
        let hue = Double(note % 12) / 12.0
        let layer = MandalaParameters.MandalaLayer(
            petalCount: petalCount,
            petalSize: velocity,
            rotationSpeed: mandalaParameters.rotationSpeed,
            color: Color(hue: hue, saturation: 0.8, brightness: 0.9),
            depth: Float(activeNotes.count) * 0.1
        )

        mandalaParameters.layers.append(layer)

        // Keep only last 6 layers
        if mandalaParameters.layers.count > 6 {
            mandalaParameters.layers.removeFirst()
        }
    }

    // MARK: - Particle Emission

    private func emitParticlesFromNote(note: UInt8, velocity: Float) {
        let hue = Double(note % 12) / 12.0
        let color = Color(hue: hue, saturation: 1.0, brightness: 1.0)

        // Emit particles based on velocity
        let particleCount = Int(velocity * 10.0)  // 0-10 particles

        for _ in 0..<particleCount {
            let angle = Float.random(in: 0..<(2.0 * .pi))
            let speed = Float.random(in: 0.5...2.0)

            let particle = ParticleParameters.Particle(
                position: SIMD2(0, 0),  // Center
                velocity: SIMD2(cos(angle) * speed, sin(angle) * speed),
                lifetime: 2.0,
                size: 2.0 + velocity * 3.0,
                color: color
            )

            particleParameters.particles.append(particle)
        }

        // Update emission rate
        particleParameters.emissionRate = Float(activeNotes.count) * 5.0
    }

    /// Update particle system (call every frame)
    func updateParticles(deltaTime: Float) {
        // Update particle positions and lifetimes
        for i in (0..<particleParameters.particles.count).reversed() {
            var particle = particleParameters.particles[i]
            particle.position += particle.velocity * deltaTime
            particle.lifetime -= deltaTime

            if particle.lifetime <= 0 {
                particleParameters.particles.remove(at: i)
            } else {
                particleParameters.particles[i] = particle
            }
        }
    }

    // MARK: - Utility Functions

    /// Convert MIDI note to frequency (Hz)
    private func midiNoteToFrequency(_ note: UInt8) -> Float {
        // A4 (note 69) = 440 Hz
        return 440.0 * pow(2.0, (Float(note) - 69.0) / 12.0)
    }

    /// Convert MIDI note to color
    func noteToColor(_ note: UInt8) -> Color {
        let hue = Double(note % 12) / 12.0
        return Color(hue: hue, saturation: 0.8, brightness: 0.9)
    }

    // MARK: - Preset Visual Modes

    func applyPreset(_ preset: VisualPreset) {
        switch preset {
        case .meditation:
            // Soft, slow-moving visuals
            mandalaParameters.rotationSpeed = 0.5
            cymaticsParameters.amplitude = 0.3
            particleParameters.emissionRate = 5.0

        case .energizing:
            // Fast, bright visuals
            mandalaParameters.rotationSpeed = 2.0
            cymaticsParameters.amplitude = 0.8
            particleParameters.emissionRate = 20.0

        case .healing:
            // Harmonious, balanced visuals
            mandalaParameters.rotationSpeed = 1.0
            cymaticsParameters.amplitude = 0.5
            particleParameters.emissionRate = 10.0

        case .psychedelic:
            // Complex, layered visuals
            mandalaParameters.layers = []  // Reset for full multi-layer
            particleParameters.emissionRate = 30.0
        }

        print("🎨 Visual preset: \(preset.rawValue)")
    }

    enum VisualPreset: String, CaseIterable {
        case meditation = "Meditation"
        case energizing = "Energizing"
        case healing = "Healing"
        case psychedelic = "Psychedelic"
    }

    // MARK: - Debug Info

    var debugInfo: String {
        """
        MIDIToVisualMapper:
        - Active Notes: \(activeNotes.count)
        - Cymatics Patterns: \(cymaticsParameters.patterns.count)
        - Mandala Layers: \(mandalaParameters.layers.count)
        - Particles: \(particleParameters.particles.count)
        - Primary Frequency: \(Int(cymaticsParameters.frequency)) Hz
        - Mandala Petals: \(mandalaParameters.petalCount)
        """
    }
}

// MARK: - Color Extensions

extension Color {
    /// Create color from hue (0-1)
    static func fromHue(_ hue: Float) -> Color {
        Color(hue: Double(hue), saturation: 0.8, brightness: 0.9)
    }

    /// Create color from MIDI note
    static func fromMIDINote(_ note: UInt8) -> Color {
        let hue = Double(note % 12) / 12.0
        return Color(hue: hue, saturation: 0.8, brightness: 0.9)
    }
}
