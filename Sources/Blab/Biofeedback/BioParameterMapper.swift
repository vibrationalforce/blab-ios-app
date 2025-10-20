import Foundation
import Combine

/// Maps biometric parameters to audio synthesis parameters
/// HRV Coherence → Reverb, Filter, Amplitude
/// Heart Rate → Tempo, Pitch Shift, Frequency
/// Voice Pitch → Base Note, Harmonics
/// Implements exponential smoothing for natural parameter changes
@MainActor
class BioParameterMapper: ObservableObject {

    // MARK: - Published Mapped Parameters

    /// Reverb wet/dry mix (0.0 - 1.0)
    /// Mapped from: HRV Coherence (higher coherence = more reverb)
    @Published var reverbWet: Float = 0.3

    /// Filter cutoff frequency (Hz)
    /// Mapped from: Heart Rate (higher HR = higher cutoff)
    @Published var filterCutoff: Float = 1000.0

    /// Amplitude/volume (0.0 - 1.0)
    /// Mapped from: HRV Coherence + Audio Level
    @Published var amplitude: Float = 0.5

    /// Base note frequency (Hz)
    /// Mapped from: Voice Pitch
    @Published var baseFrequency: Float = 432.0

    /// Tempo (BPM)
    /// Mapped from: Heart Rate (synchronized breathing)
    @Published var tempo: Float = 60.0

    /// Spatial position (X/Y/Z)
    /// Mapped from: HRV Coherence (higher = more centered)
    @Published var spatialPosition: (x: Float, y: Float, z: Float) = (0, 0, 1)

    /// Harmonic richness (number of harmonics)
    /// Mapped from: Voice pitch clarity
    @Published var harmonicCount: Int = 5


    // MARK: - Smoothing Configuration

    /// Smoothing factor (0.0 = no smoothing, 1.0 = max smoothing)
    private let smoothingFactor: Float = 0.85

    /// Fast smoothing for quick changes (e.g., voice pitch)
    private let fastSmoothingFactor: Float = 0.7


    // MARK: - Mapping Ranges

    // HRV Coherence: 0-100 (HeartMath scale)
    private let hrvCoherenceRange = (min: 0.0, max: 100.0)

    // Heart Rate: 40-120 BPM (typical range)
    private let heartRateRange = (min: 40.0, max: 120.0)

    // Voice Pitch: 80-1000 Hz (human voice range)
    private let voicePitchRange = (min: 80.0, max: 1000.0)

    // Reverb: 10-80% wet
    private let reverbRange = (min: 0.1, max: 0.8)

    // Filter: 200-2000 Hz
    private let filterRange = (min: 200.0, max: 2000.0)

    // Amplitude: 0.3-0.8
    private let amplitudeRange = (min: 0.3, max: 0.8)


    // MARK: - Musical Scale Configuration

    /// Musical scale for harmonic generation
    private let healingScale: [Float] = [
        432.0,   // A4 (base healing frequency)
        486.0,   // B4
        512.0,   // C5
        576.0,   // D5
        648.0,   // E5
        729.0,   // F#5
        768.0,   // G5
    ]


    // MARK: - Public Methods

    /// Update all mapped parameters from biometric data
    /// - Parameters:
    ///   - hrvCoherence: HRV coherence score (0-100)
    ///   - heartRate: Heart rate (BPM)
    ///   - voicePitch: Detected voice pitch (Hz)
    ///   - audioLevel: Current audio level (0.0-1.0)
    func updateParameters(
        hrvCoherence: Double,
        heartRate: Double,
        voicePitch: Float,
        audioLevel: Float
    ) {
        // Map HRV Coherence → Reverb Wet
        let targetReverb = mapHRVToReverb(hrvCoherence: hrvCoherence)
        reverbWet = smooth(current: reverbWet, target: targetReverb, factor: smoothingFactor)

        // Map Heart Rate → Filter Cutoff
        let targetFilter = mapHeartRateToFilter(heartRate: heartRate)
        filterCutoff = smooth(current: filterCutoff, target: targetFilter, factor: smoothingFactor)

        // Map HRV + Audio Level → Amplitude
        let targetAmplitude = mapToAmplitude(hrvCoherence: hrvCoherence, audioLevel: audioLevel)
        amplitude = smooth(current: amplitude, target: targetAmplitude, factor: smoothingFactor)

        // Map Voice Pitch → Base Frequency (snap to healing scale)
        let targetFrequency = mapVoicePitchToScale(voicePitch: voicePitch)
        baseFrequency = smooth(current: baseFrequency, target: targetFrequency, factor: fastSmoothingFactor)

        // Map Heart Rate → Tempo (for breathing guidance)
        let targetTempo = mapHeartRateToTempo(heartRate: heartRate)
        tempo = smooth(current: tempo, target: targetTempo, factor: smoothingFactor)

        // Map HRV Coherence → Spatial Position
        spatialPosition = mapHRVToSpatialPosition(hrvCoherence: hrvCoherence)

        // Map Voice Pitch Clarity → Harmonic Count
        harmonicCount = mapVoicePitchToHarmonics(voicePitch: voicePitch, audioLevel: audioLevel)

        #if DEBUG
        logParameters()
        #endif
    }


    // MARK: - Individual Mapping Functions

    /// Map HRV Coherence (0-100) → Reverb Wet (10-80%)
    /// Low coherence (stress) = Less reverb (10%)
    /// High coherence (flow) = More reverb (80%)
    private func mapHRVToReverb(hrvCoherence: Double) -> Float {
        let normalized = normalize(
            value: Float(hrvCoherence),
            from: (Float(hrvCoherenceRange.min), Float(hrvCoherenceRange.max))
        )

        return lerp(
            from: reverbRange.min,
            to: reverbRange.max,
            t: normalized
        )
    }

    /// Map Heart Rate (40-120 BPM) → Filter Cutoff (200-2000 Hz)
    /// Low HR (relaxed) = Lower cutoff (darker sound)
    /// High HR (active) = Higher cutoff (brighter sound)
    private func mapHeartRateToFilter(heartRate: Double) -> Float {
        let normalized = normalize(
            value: Float(heartRate),
            from: (Float(heartRateRange.min), Float(heartRateRange.max))
        )

        return lerp(
            from: filterRange.min,
            to: filterRange.max,
            t: normalized
        )
    }

    /// Map HRV Coherence + Audio Level → Amplitude
    /// Combined mapping for natural volume control
    private func mapToAmplitude(hrvCoherence: Double, audioLevel: Float) -> Float {
        // HRV component (70% weight)
        let hrvNormalized = normalize(
            value: Float(hrvCoherence),
            from: (Float(hrvCoherenceRange.min), Float(hrvCoherenceRange.max))
        )
        let hrvContribution = hrvNormalized * 0.7

        // Audio level component (30% weight)
        let audioContribution = audioLevel * 0.3

        // Combine and map to amplitude range
        let combined = hrvContribution + audioContribution

        return lerp(
            from: amplitudeRange.min,
            to: amplitudeRange.max,
            t: combined
        )
    }

    /// Map Voice Pitch → Musical Scale (healing frequencies)
    /// Snaps detected pitch to nearest note in healing scale
    private func mapVoicePitchToScale(voicePitch: Float) -> Float {
        guard voicePitch > 0 else { return healingScale[0] }

        // Find nearest note in healing scale
        var closestNote = healingScale[0]
        var minDistance = abs(voicePitch - closestNote)

        for note in healingScale {
            let distance = abs(voicePitch - note)
            if distance < minDistance {
                minDistance = distance
                closestNote = note
            }
        }

        return closestNote
    }

    /// Map Heart Rate → Tempo (for breathing guidance)
    /// Typical breathing rate: 4-8 breaths/minute = HR/4
    private func mapHeartRateToTempo(heartRate: Double) -> Float {
        // Convert HR to breathing tempo (roughly HR / 4)
        let breathingRate = Float(heartRate) / 4.0

        // Clamp to reasonable breathing range (4-8 breaths/min)
        return max(4.0, min(8.0, breathingRate))
    }

    /// Map HRV Coherence → Spatial Position
    /// Low coherence = Audio moves around (X/Y variation)
    /// High coherence = Audio centered (0, 0, Z)
    private func mapHRVToSpatialPosition(hrvCoherence: Double) -> (x: Float, y: Float, z: Float) {
        let normalized = normalize(
            value: Float(hrvCoherence),
            from: (Float(hrvCoherenceRange.min), Float(hrvCoherenceRange.max))
        )

        // Low coherence → more spatial movement
        // High coherence → centered position
        let maxDeviation: Float = 1.0 - normalized  // 0.0 (centered) to 1.0 (spread)

        // Create subtle circular motion for low coherence
        let angle = Float(Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6.28))
        let x = cos(angle) * maxDeviation * 0.5
        let y = sin(angle) * maxDeviation * 0.5
        let z: Float = 1.0  // Keep constant distance

        return (x, y, z)
    }

    /// Map Voice Pitch Clarity → Harmonic Count
    /// Clear pitch = More harmonics (rich sound)
    /// Unclear/noisy = Fewer harmonics (simple sound)
    private func mapVoicePitchToHarmonics(voicePitch: Float, audioLevel: Float) -> Int {
        // If no pitch detected or very quiet, use minimal harmonics
        if voicePitch <= 0 || audioLevel < 0.1 {
            return 3
        }

        // Strong signal with clear pitch = more harmonics
        let clarity = audioLevel  // Higher level = clearer signal

        if clarity > 0.6 {
            return 7  // Rich harmonic content
        } else if clarity > 0.3 {
            return 5  // Medium harmonics
        } else {
            return 3  // Basic harmonics
        }
    }


    // MARK: - Utility Functions

    /// Normalize value from input range to 0.0-1.0
    private func normalize(value: Float, from range: (Float, Float)) -> Float {
        let clamped = max(range.0, min(range.1, value))
        return (clamped - range.0) / (range.1 - range.0)
    }

    /// Linear interpolation
    private func lerp(from: Float, to: Float, t: Float) -> Float {
        return from + (to - from) * t
    }

    /// Exponential smoothing
    private func smooth(current: Float, target: Float, factor: Float) -> Float {
        return current * factor + target * (1.0 - factor)
    }

    /// Log current parameters (debug only)
    private func logParameters() {
        let timestamp = Int(Date().timeIntervalSince1970)
        if timestamp % 5 == 0 {  // Every 5 seconds
            print("🎛️  BioParams: Rev:\(Int(reverbWet*100))% Filt:\(Int(filterCutoff))Hz Amp:\(Int(amplitude*100))% Freq:\(Int(baseFrequency))Hz")
        }
    }


    // MARK: - Presets

    /// Apply preset for specific state
    func applyPreset(_ preset: BioPreset) {
        switch preset {
        case .meditation:
            reverbWet = 0.7
            filterCutoff = 500.0
            amplitude = 0.5
            baseFrequency = 432.0
            tempo = 6.0

        case .focus:
            reverbWet = 0.3
            filterCutoff = 1500.0
            amplitude = 0.6
            baseFrequency = 528.0  // Focus frequency
            tempo = 7.0

        case .relaxation:
            reverbWet = 0.8
            filterCutoff = 300.0
            amplitude = 0.4
            baseFrequency = 396.0  // Root chakra frequency
            tempo = 4.0

        case .energize:
            reverbWet = 0.2
            filterCutoff = 2000.0
            amplitude = 0.7
            baseFrequency = 741.0  // Awakening frequency
            tempo = 8.0
        }

        print("🎛️  Applied preset: \(preset.rawValue)")
    }

    enum BioPreset: String, CaseIterable {
        case meditation = "Meditation"
        case focus = "Focus"
        case relaxation = "Deep Relaxation"
        case energize = "Energize"
    }
}


// MARK: - Parameter Validation

extension BioParameterMapper {

    /// Validate that all parameters are in valid ranges
    var isValid: Bool {
        reverbWet >= 0.0 && reverbWet <= 1.0 &&
        filterCutoff >= 20.0 && filterCutoff <= 20000.0 &&
        amplitude >= 0.0 && amplitude <= 1.0 &&
        baseFrequency >= 20.0 && baseFrequency <= 20000.0 &&
        tempo >= 1.0 && tempo <= 20.0
    }

    /// Get parameter summary for debugging
    var parameterSummary: String {
        """
        BioParameter Mapping:
        - Reverb: \(Int(reverbWet * 100))%
        - Filter: \(Int(filterCutoff)) Hz
        - Amplitude: \(Int(amplitude * 100))%
        - Frequency: \(Int(baseFrequency)) Hz
        - Tempo: \(String(format: "%.1f", tempo)) breaths/min
        - Spatial: X:\(String(format: "%.2f", spatialPosition.x)) Y:\(String(format: "%.2f", spatialPosition.y)) Z:\(String(format: "%.2f", spatialPosition.z))
        - Harmonics: \(harmonicCount)
        """
    }
}
