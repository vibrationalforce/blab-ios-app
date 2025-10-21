import Foundation
import simd

/// Maps MIDI/MPE parameters to spatial audio (Stereo, 3D, 4D, AFA Sound)
///
/// **Spatial Audio Modes:**
/// - **Stereo**: Pan (L/R)
/// - **3D (X/Y/Z)**: Azimuth, Elevation, Distance
/// - **4D (X/Y/Z/Time)**: 3D + Temporal evolution
/// - **AFA Sound (Algorithmic Field Array)**: Multi-source field with phase relationships
///
/// **MIDI → Spatial Mappings:**
/// - **Note Number** → Azimuth (pitch → direction)
/// - **Velocity** → Distance (soft = far, loud = near)
/// - **CC 10 (Pan)** → Azimuth override
/// - **CC 74 (Brightness)** → Elevation
/// - **Pitch Bend** → Orbital motion (circular/spiral paths)
/// - **CC 91 (Reverb)** → Space size
/// - **Aftertouch** → Z-axis modulation
///
/// **AFA Sound:**
/// - Multiple sound sources arranged in geometric patterns
/// - Phase-coherent synthesis
/// - Bio-reactive field morphing
@MainActor
class MIDIToSpatialMapper: ObservableObject {

    // MARK: - Published State

    @Published var spatialMode: SpatialMode = .stereo
    @Published var currentPosition: SpatialPosition = SpatialPosition(x: 0, y: 0, z: 1)
    @Published var afaField: AFAField?

    // MARK: - Spatial Modes

    enum SpatialMode {
        case stereo         // Simple L/R panning
        case surround_3d    // X/Y/Z (azimuth/elevation/distance)
        case surround_4d    // X/Y/Z + temporal evolution
        case afa            // Algorithmic Field Array (multi-source)
        case binaural       // HRTF-based binaural
        case ambisonics     // Higher-order ambisonics (HOA)
    }

    // MARK: - Spatial Position

    struct SpatialPosition {
        var x: Float   // Left (-1) to Right (+1)
        var y: Float   // Back (-1) to Front (+1)
        var z: Float   // Down (-1) to Up (+1), or distance
        var time: Float = 0.0  // For 4D temporal evolution

        /// Convert to spherical coordinates (azimuth, elevation, distance)
        var spherical: (azimuth: Float, elevation: Float, distance: Float) {
            let distance = sqrt(x*x + y*y + z*z)
            let azimuth = atan2(y, x) // Radians
            let elevation = asin(z / max(distance, 0.001))
            return (azimuth, elevation, distance)
        }

        /// Convert from spherical to Cartesian
        static func fromSpherical(azimuth: Float, elevation: Float, distance: Float) -> SpatialPosition {
            let x = distance * cos(elevation) * cos(azimuth)
            let y = distance * cos(elevation) * sin(azimuth)
            let z = distance * sin(elevation)
            return SpatialPosition(x: x, y: y, z: z)
        }
    }

    // MARK: - AFA Field (Algorithmic Field Array)

    struct AFAField {
        var sources: [AFASource]
        var fieldGeometry: FieldGeometry
        var phaseCoherence: Float = 1.0  // 0.0 = chaotic, 1.0 = perfectly coherent

        enum FieldGeometry {
            case circle(radius: Float, sourceCount: Int)
            case sphere(radius: Float, sourceCount: Int)
            case spiral(turns: Int, sourceCount: Int)
            case grid(rows: Int, cols: Int, spacing: Float)
            case fibonacci(sourceCount: Int)  // Fibonacci sphere
        }
    }

    struct AFASource {
        let id: UUID
        var position: SpatialPosition
        var amplitude: Float
        var frequency: Float
        var phase: Float
        var color: (r: Float, g: Float, b: Float)  // For visualization
    }

    // MARK: - Mapping Configuration

    /// Note-to-azimuth mapping range (in radians)
    private let noteAzimuthRange: ClosedRange<Float> = (-Float.pi)...(Float.pi)  // Full circle

    /// Velocity-to-distance mapping
    private let velocityDistanceRange: ClosedRange<Float> = 0.5...3.0  // Near to far

    /// Brightness-to-elevation mapping
    private let brightnessElevationRange: ClosedRange<Float> = (-Float.pi/4)...(Float.pi/4)  // ±45°

    // MARK: - Stereo Mapping

    /// Map MIDI parameters to stereo pan (-1 = left, +1 = right)
    func mapToStereo(note: UInt8, velocity: Float, pan: Float? = nil) -> Float {
        if let panOverride = pan {
            return (panOverride * 2.0) - 1.0  // Convert 0-1 to -1 to +1
        }

        // Map note number to pan position
        // Low notes = left, high notes = right
        let normalizedNote = Float(note) / 127.0
        return (normalizedNote * 2.0) - 1.0
    }

    // MARK: - 3D Mapping

    /// Map MIDI parameters to 3D spatial position
    /// - Parameters:
    ///   - note: MIDI note number (affects azimuth)
    ///   - velocity: Velocity (affects distance)
    ///   - brightness: CC 74 (affects elevation)
    ///   - pan: CC 10 (overrides azimuth)
    /// - Returns: 3D spatial position
    func mapTo3D(note: UInt8, velocity: Float, brightness: Float = 0.5, pan: Float? = nil) -> SpatialPosition {
        // Calculate azimuth (horizontal angle)
        let azimuth: Float
        if let panValue = pan {
            // Use pan for azimuth
            azimuth = mapRange(
                Double(panValue),
                from: 0...1,
                to: Double(noteAzimuthRange.lowerBound)...Double(noteAzimuthRange.upperBound)
            )
        } else {
            // Use note number for azimuth
            azimuth = mapRange(
                Double(note),
                from: 0...127,
                to: Double(noteAzimuthRange.lowerBound)...Double(noteAzimuthRange.upperBound)
            )
        }

        // Calculate elevation (vertical angle) from brightness
        let elevation = mapRange(
            Double(brightness),
            from: 0...1,
            to: Double(brightnessElevationRange.lowerBound)...Double(brightnessElevationRange.upperBound)
        )

        // Calculate distance from velocity (soft = far, loud = near)
        let distance = mapRange(
            Double(1.0 - velocity),  // Invert: loud = near
            from: 0...1,
            to: Double(velocityDistanceRange.lowerBound)...Double(velocityDistanceRange.upperBound)
        )

        return SpatialPosition.fromSpherical(
            azimuth: Float(azimuth),
            elevation: Float(elevation),
            distance: Float(distance)
        )
    }

    // MARK: - 4D Mapping (3D + Time)

    /// Map MIDI parameters to 4D spatial position (3D + temporal evolution)
    /// - Parameters:
    ///   - note: MIDI note number
    ///   - velocity: Velocity
    ///   - brightness: CC 74
    ///   - pitchBend: Pitch bend (-1 to +1, controls orbital motion)
    ///   - time: Current time (for evolution)
    /// - Returns: 4D spatial position with temporal evolution
    func mapTo4D(note: UInt8, velocity: Float, brightness: Float = 0.5,
                 pitchBend: Float = 0.0, time: Float = 0.0) -> SpatialPosition {
        // Start with 3D position
        var position = mapTo3D(note: note, velocity: velocity, brightness: brightness)

        // Add orbital motion from pitch bend
        let orbitalSpeed = abs(pitchBend) * 2.0  // Radians per second
        let orbitalDirection: Float = pitchBend < 0 ? -1.0 : 1.0

        // Apply orbital rotation around Z-axis
        let angle = orbitalSpeed * time * orbitalDirection
        let newX = position.x * cos(angle) - position.y * sin(angle)
        let newY = position.x * sin(angle) + position.y * cos(angle)

        position.x = newX
        position.y = newY
        position.time = time

        return position
    }

    // MARK: - AFA Field Mapping

    /// Create AFA (Algorithmic Field Array) from multiple MIDI voices
    /// - Parameters:
    ///   - voices: Array of active MPE voices
    ///   - geometry: Field geometry
    /// - Returns: AFA field with positioned sources
    func mapToAFA(voices: [MPEVoiceData], geometry: AFAField.FieldGeometry) -> AFAField {
        var sources: [AFASource] = []

        for (index, voice) in voices.enumerated() {
            // Calculate position based on geometry
            let position = calculateAFAPosition(index: index, total: voices.count, geometry: geometry)

            // Map voice parameters to source
            let source = AFASource(
                id: voice.id,
                position: position,
                amplitude: voice.velocity,
                frequency: midiNoteToFrequency(voice.note),
                phase: Float(index) * (2.0 * .pi / Float(voices.count)),  // Evenly distributed phase
                color: noteToColor(voice.note)
            )

            sources.append(source)
        }

        return AFAField(
            sources: sources,
            fieldGeometry: geometry,
            phaseCoherence: 1.0  // Start with perfect coherence
        )
    }

    /// Calculate position for AFA source based on geometry
    private func calculateAFAPosition(index: Int, total: Int, geometry: AFAField.FieldGeometry) -> SpatialPosition {
        switch geometry {
        case .circle(let radius, _):
            let angle = (2.0 * .pi * Float(index)) / Float(total)
            return SpatialPosition(
                x: radius * cos(angle),
                y: radius * sin(angle),
                z: 0
            )

        case .sphere(let radius, _):
            // Fibonacci sphere distribution
            let phi = .pi * (3.0 - sqrt(5.0))  // Golden angle
            let y = 1.0 - (Float(index) / Float(total - 1)) * 2.0
            let radiusAtY = sqrt(1.0 - y * y)
            let theta = phi * Float(index)

            return SpatialPosition(
                x: radius * cos(theta) * radiusAtY,
                y: radius * y,
                z: radius * sin(theta) * radiusAtY
            )

        case .spiral(let turns, _):
            let t = Float(index) / Float(total)
            let angle = Float(turns) * 2.0 * .pi * t
            let radius = t  // Expand outward

            return SpatialPosition(
                x: radius * cos(angle),
                y: radius * sin(angle),
                z: t * 2.0 - 1.0  // Z evolves from -1 to +1
            )

        case .grid(let rows, let cols, let spacing):
            let row = index / cols
            let col = index % cols
            return SpatialPosition(
                x: (Float(col) - Float(cols) / 2.0) * spacing,
                y: (Float(row) - Float(rows) / 2.0) * spacing,
                z: 0
            )

        case .fibonacci(_):
            // Same as sphere case
            let phi = .pi * (3.0 - sqrt(5.0))
            let y = 1.0 - (Float(index) / Float(total - 1)) * 2.0
            let radiusAtY = sqrt(1.0 - y * y)
            let theta = phi * Float(index)

            return SpatialPosition(
                x: cos(theta) * radiusAtY,
                y: y,
                z: sin(theta) * radiusAtY
            )
        }
    }

    // MARK: - Utility Functions

    /// Map value from one range to another
    private func mapRange(
        _ value: Double,
        from: ClosedRange<Double>,
        to: ClosedRange<Double>
    ) -> Float {
        let normalized = (value - from.lowerBound) / (from.upperBound - from.lowerBound)
        let clamped = max(0, min(1, normalized))
        let mapped = to.lowerBound + clamped * (to.upperBound - to.lowerBound)
        return Float(mapped)
    }

    /// Convert MIDI note to frequency
    private func midiNoteToFrequency(_ note: UInt8) -> Float {
        // A4 (note 69) = 440 Hz
        return 440.0 * pow(2.0, (Float(note) - 69.0) / 12.0)
    }

    /// Convert MIDI note to color (for visualization)
    private func noteToColor(_ note: UInt8) -> (r: Float, g: Float, b: Float) {
        let hue = Float(note) / 127.0
        return hsvToRgb(h: hue, s: 0.8, v: 0.9)
    }

    /// HSV to RGB conversion
    private func hsvToRgb(h: Float, s: Float, v: Float) -> (r: Float, g: Float, b: Float) {
        let c = v * s
        let x = c * (1.0 - abs((h * 6.0).truncatingRemainder(dividingBy: 2.0) - 1.0))
        let m = v - c

        var r: Float = 0, g: Float = 0, b: Float = 0

        let segment = Int(h * 6.0)
        switch segment {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }

        return (r + m, g + m, b + m)
    }
}

// MARK: - MPE Voice Data (for AFA)

struct MPEVoiceData {
    let id: UUID
    let note: UInt8
    let velocity: Float
    let pitchBend: Float
    let brightness: Float
}
