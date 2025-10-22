import Foundation
import ARKit

/// Maps ARKit face tracking data to audio parameters
///
/// **Mappings:**
/// - Jaw Open → Filter Cutoff (closed = 200 Hz, open = 8000 Hz)
/// - Smile → Stereo Width (no smile = narrow, big smile = wide)
/// - Eyebrow Raise → Reverb Size (neutral = small, raised = large)
/// - Mouth Funnel ("O" shape) → Resonance/Q Factor
///
/// **Usage:**
/// ```swift
/// let mapper = FaceToAudioMapper()
/// let params = mapper.mapToAudio(faceExpression: expression)
/// audioEngine.setFilterCutoff(params.filterCutoff)
/// ```
public class FaceToAudioMapper {

    // MARK: - Configuration

    /// Minimum jaw open value to trigger mapping (prevents noise)
    public var jawOpenThreshold: Float = 0.05

    /// Smoothing factor for parameter changes (0.0 = no smoothing, 1.0 = max smoothing)
    public var smoothingFactor: Float = 0.85 {
        didSet {
            if smoothingFactor > 1 {
                smoothingFactor = 1
            } else if smoothingFactor < 0 {
                smoothingFactor = 0
            }

            if smoothingFactor == 0 {
                smoothedParams = nil
            }
        }
    }

    // MARK: - State

    private var smoothedParams: AudioParameters?

    // MARK: - Public Methods

    /// Map face expression to audio parameters
    /// - Parameter faceExpression: Current face expression from ARKit
    /// - Returns: Audio parameters to apply
    public func mapToAudio(faceExpression: FaceExpression) -> AudioParameters {
        var params = AudioParameters()

        // 1. Jaw Open → Filter Cutoff
        params.filterCutoff = mapJawToFilterCutoff(faceExpression.jawOpen)

        // 2. Smile → Stereo Width
        params.stereoWidth = mapSmileToStereoWidth(faceExpression.smile)

        // 3. Eyebrow Raise → Reverb Size
        params.reverbSize = mapBrowToReverbSize(faceExpression.browRaise)

        // 4. Mouth Funnel → Resonance
        params.filterResonance = mapFunnelToResonance(faceExpression.mouthFunnel)

        // 5. Mouth Pucker → Modulation depth
        params.modulationDepth = Double(faceExpression.mouthPucker)

        guard smoothingFactor > 0 else {
            smoothedParams = params
            return params
        }

        let current = smoothedParams ?? params
        let smoothed = applySmoothing(current: current, target: params)
        smoothedParams = smoothed

        return smoothed
    }

    // MARK: - Individual Mappings

    /// Map jaw opening to filter cutoff frequency
    /// - Closed mouth (0.0): 200 Hz (dark, muffled)
    /// - Half open (0.5): 2000 Hz (balanced)
    /// - Fully open (1.0): 8000 Hz (bright, open)
    private func mapJawToFilterCutoff(_ jawOpen: Float) -> Double {
        // Apply threshold to prevent noise
        let threshold = max(0.0, min(Double(jawOpenThreshold), 0.99))
        let jawValue = max(0.0, min(Double(jawOpen), 1.0))
        let span = max(0.01, 1.0 - threshold)
        let normalizedInput = max(0, jawValue - threshold)
        let normalized = min(max(normalizedInput / span, 0), 1)
        let minFreq = 200.0
        let maxFreq = 8000.0

        // Exponential curve: freq = min * (max/min)^normalized
        let cutoff = minFreq * pow(maxFreq / minFreq, normalized)

        return cutoff.clamped(to: minFreq...maxFreq)
    }

    /// Map smile to stereo width
    /// - No smile (0.0): Narrow (0.5 = mono-ish)
    /// - Full smile (1.0): Wide (2.0 = super wide)
    private func mapSmileToStereoWidth(_ smile: Float) -> Double {
        let minWidth = 0.5
        let maxWidth = 2.0

        return mapLinear(Double(smile), from: 0...1, to: minWidth...maxWidth)
    }

    /// Map eyebrow raise to reverb size
    /// - Neutral (0.0): Small room (0.5)
    /// - Raised (1.0): Cathedral (5.0)
    private func mapBrowToReverbSize(_ browRaise: Float) -> Double {
        let minSize = 0.5
        let maxSize = 5.0

        return mapLinear(Double(browRaise), from: 0...1, to: minSize...maxSize)
    }

    /// Map mouth funnel ("O" shape) to filter resonance/Q factor
    /// - Normal (0.0): Low resonance (0.707 = Butterworth)
    /// - Funnel (1.0): High resonance (5.0 = singing, ringing quality)
    private func mapFunnelToResonance(_ funnel: Float) -> Double {
        let minQ = 0.707
        let maxQ = 5.0

        return mapLinear(Double(funnel), from: 0...1, to: minQ...maxQ)
    }

    // MARK: - Smoothing

    /// Apply exponential smoothing to prevent abrupt parameter changes
    private func applySmoothing(
        current: AudioParameters,
        target: AudioParameters
    ) -> AudioParameters {
        let clampedFactor = max(0.0, min(1.0, Double(smoothingFactor)))
        let alpha = 1.0 - clampedFactor  // 0.15 for smoothingFactor 0.85

        return AudioParameters(
            filterCutoff: lerp(current.filterCutoff, target.filterCutoff, alpha),
            filterResonance: lerp(current.filterResonance, target.filterResonance, alpha),
            stereoWidth: lerp(current.stereoWidth, target.stereoWidth, alpha),
            reverbSize: lerp(current.reverbSize, target.reverbSize, alpha),
            modulationDepth: lerp(current.modulationDepth, target.modulationDepth, alpha)
        )
    }

    // MARK: - Utilities

    private func mapLinear(
        _ value: Double,
        from: ClosedRange<Double>,
        to: ClosedRange<Double>
    ) -> Double {
        let normalized = (value - from.lowerBound) / (from.upperBound - from.lowerBound)
        let range = from.upperBound - from.lowerBound
        guard range != 0 else { return to.lowerBound }

        let clamped = max(0, min(1, normalized))
        return to.lowerBound + clamped * (to.upperBound - to.lowerBound)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        return a + (b - a) * t
    }
}

// MARK: - Audio Parameters

/// Audio parameters derived from face tracking
public struct AudioParameters: Equatable {
    public var filterCutoff: Double       // Hz (200 - 8000)
    public var filterResonance: Double    // Q factor (0.707 - 5.0)
    public var stereoWidth: Double        // 0.5 (narrow) - 2.0 (wide)
    public var reverbSize: Double         // 0.5 (small) - 5.0 (large)
    public var modulationDepth: Double    // 0.0 - 1.0

    public init(
        filterCutoff: Double = 1000.0,
        filterResonance: Double = 0.707,
        stereoWidth: Double = 1.0,
        reverbSize: Double = 1.0,
        modulationDepth: Double = 0.0
    ) {
        self.filterCutoff = filterCutoff
        self.filterResonance = filterResonance
        self.stereoWidth = stereoWidth
        self.reverbSize = reverbSize
        self.modulationDepth = modulationDepth
    }
}

// MARK: - Extensions

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
