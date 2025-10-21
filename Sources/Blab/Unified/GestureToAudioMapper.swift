import Foundation

/// Maps hand gestures to audio parameters
///
/// This mapper translates gesture data from GestureRecognizer into
/// audio control parameters following BLAB's bio-reactive design.
///
/// **Gesture Mappings:**
/// - **Pinch** (Left) → Filter Cutoff (200-8000 Hz)
/// - **Pinch** (Right) → Filter Resonance (0.5-5.0)
/// - **Spread** (Left) → Reverb Size (0-1)
/// - **Spread** (Right) → Reverb Wetness (0-1)
/// - **Fist** (Left) → MIDI Note Trigger (C4, vel 100)
/// - **Fist** (Right) → MIDI Note Trigger (G4, vel 100)
/// - **Point** → Delay Time (mapped to finger extension)
/// - **Swipe** → Preset change trigger
@MainActor
class GestureToAudioMapper {

    // MARK: - Audio Parameter Result

    struct AudioParameters {
        // Filter parameters
        var filterCutoff: Float?
        var filterResonance: Float?

        // Reverb parameters
        var reverbSize: Float?
        var reverbWetness: Float?

        // Delay parameters
        var delayTime: Float?

        // MIDI events
        var midiNoteOn: MIDINote?
        var presetChange: Int?
    }

    struct MIDINote {
        let note: UInt8
        let velocity: UInt8
        let channel: UInt8
    }

    // MARK: - Configuration

    /// Minimum gesture amount to trigger parameter changes (prevents jitter)
    var minimumGestureAmount: Float = 0.05

    /// Smoothing factor for continuous parameters (0 = no smoothing, 1 = max smoothing)
    var smoothingFactor: Float = 0.3

    // MARK: - State (for smoothing)

    private var lastFilterCutoff: Float = 1000.0
    private var lastFilterResonance: Float = 1.0
    private var lastReverbSize: Float = 0.5
    private var lastReverbWetness: Float = 0.3
    private var lastDelayTime: Float = 0.5

    // For event triggering (prevent rapid re-triggers)
    private var lastFistTriggerTime: [HandTrackingManager.Hand: Date] = [:]
    private let fistTriggerCooldown: TimeInterval = 0.3 // 300ms cooldown

    // MARK: - Mapping Methods

    /// Map gestures from both hands to audio parameters
    func mapToAudio(gestureRecognizer: GestureRecognizer) -> AudioParameters {
        var params = AudioParameters()

        // Left hand mappings
        params = applyLeftHandGesture(
            gesture: gestureRecognizer.leftHandGesture,
            pinchAmount: gestureRecognizer.leftPinchAmount,
            spreadAmount: gestureRecognizer.leftSpreadAmount,
            to: params
        )

        // Right hand mappings
        params = applyRightHandGesture(
            gesture: gestureRecognizer.rightHandGesture,
            pinchAmount: gestureRecognizer.rightPinchAmount,
            spreadAmount: gestureRecognizer.rightSpreadAmount,
            to: params
        )

        return params
    }

    // MARK: - Left Hand Mappings

    private func applyLeftHandGesture(
        gesture: GestureRecognizer.Gesture,
        pinchAmount: Float,
        spreadAmount: Float,
        to params: AudioParameters
    ) -> AudioParameters {
        var result = params

        switch gesture {
        case .pinch:
            // Left Pinch → Filter Cutoff (200-8000 Hz)
            if pinchAmount > minimumGestureAmount {
                let targetCutoff = mapRange(
                    Double(pinchAmount),
                    from: 0...1,
                    to: 200...8000
                )
                result.filterCutoff = smooth(
                    current: lastFilterCutoff,
                    target: Float(targetCutoff),
                    factor: smoothingFactor
                )
                lastFilterCutoff = result.filterCutoff!
            }

        case .spread:
            // Left Spread → Reverb Size (0-1)
            if spreadAmount > minimumGestureAmount {
                let targetSize = spreadAmount
                result.reverbSize = smooth(
                    current: lastReverbSize,
                    target: targetSize,
                    factor: smoothingFactor
                )
                lastReverbSize = result.reverbSize!
            }

        case .fist:
            // Left Fist → MIDI Note (C4)
            if shouldTriggerFist(hand: .left) {
                result.midiNoteOn = MIDINote(note: 60, velocity: 100, channel: 0)
                lastFistTriggerTime[.left] = Date()
            }

        case .point:
            // Point could map to delay time based on finger extension
            break

        case .swipe:
            // Swipe could trigger preset changes
            // result.presetChange = 1 // Next preset
            break

        case .none:
            break
        }

        return result
    }

    // MARK: - Right Hand Mappings

    private func applyRightHandGesture(
        gesture: GestureRecognizer.Gesture,
        pinchAmount: Float,
        spreadAmount: Float,
        to params: AudioParameters
    ) -> AudioParameters {
        var result = params

        switch gesture {
        case .pinch:
            // Right Pinch → Filter Resonance (0.5-5.0)
            if pinchAmount > minimumGestureAmount {
                let targetResonance = mapRange(
                    Double(pinchAmount),
                    from: 0...1,
                    to: 0.5...5.0
                )
                result.filterResonance = smooth(
                    current: lastFilterResonance,
                    target: Float(targetResonance),
                    factor: smoothingFactor
                )
                lastFilterResonance = result.filterResonance!
            }

        case .spread:
            // Right Spread → Reverb Wetness (0-1)
            if spreadAmount > minimumGestureAmount {
                let targetWetness = spreadAmount
                result.reverbWetness = smooth(
                    current: lastReverbWetness,
                    target: targetWetness,
                    factor: smoothingFactor
                )
                lastReverbWetness = result.reverbWetness!
            }

        case .fist:
            // Right Fist → MIDI Note (G4)
            if shouldTriggerFist(hand: .right) {
                result.midiNoteOn = MIDINote(note: 67, velocity: 100, channel: 0)
                lastFistTriggerTime[.right] = Date()
            }

        default:
            break
        }

        return result
    }

    // MARK: - Helper Methods

    /// Check if fist gesture should trigger (cooldown-based)
    private func shouldTriggerFist(hand: HandTrackingManager.Hand) -> Bool {
        guard let lastTrigger = lastFistTriggerTime[hand] else {
            return true // First trigger
        }

        let timeSinceLastTrigger = Date().timeIntervalSince(lastTrigger)
        return timeSinceLastTrigger >= fistTriggerCooldown
    }

    /// Exponential smoothing for continuous parameters
    private func smooth(current: Float, target: Float, factor: Float) -> Float {
        return current * factor + target * (1.0 - factor)
    }

    /// Map value from one range to another
    private func mapRange(
        _ value: Double,
        from: ClosedRange<Double>,
        to: ClosedRange<Double>
    ) -> Double {
        let normalized = (value - from.lowerBound) / (from.upperBound - from.lowerBound)
        let clamped = max(0, min(1, normalized))
        return to.lowerBound + clamped * (to.upperBound - to.lowerBound)
    }
}
