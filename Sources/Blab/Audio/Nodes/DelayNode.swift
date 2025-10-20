import Foundation
import AVFoundation

/// Delay effect node with bio-reactive parameters
/// HRV → Delay Time (coherence creates rhythmic echoes)
/// Heart Rate → Feedback (tempo-synced repeats)
@MainActor
class DelayNode: BaseBlabNode {

    // MARK: - AVAudioUnit Delay

    private let delayUnit: AVAudioUnitDelay


    // MARK: - Parameters

    private enum Params {
        static let delayTime = "delayTime"
        static let feedback = "feedback"
        static let wetDryMix = "wetDryMix"
        static let lowPassCutoff = "lowPassCutoff"
    }


    // MARK: - Initialization

    init() {
        self.delayUnit = AVAudioUnitDelay()

        super.init(name: "Bio-Reactive Delay", type: .effect)

        // Setup parameters
        parameters = [
            NodeParameter(
                name: Params.delayTime,
                label: "Delay Time",
                value: 0.5,
                min: 0.01,
                max: 2.0,
                defaultValue: 0.5,
                unit: "s",
                isAutomatable: true,
                type: .continuous
            ),
            NodeParameter(
                name: Params.feedback,
                label: "Feedback",
                value: 30.0,
                min: 0.0,
                max: 90.0,
                defaultValue: 30.0,
                unit: "%",
                isAutomatable: true,
                type: .continuous
            ),
            NodeParameter(
                name: Params.wetDryMix,
                label: "Wet/Dry Mix",
                value: 30.0,
                min: 0.0,
                max: 100.0,
                defaultValue: 30.0,
                unit: "%",
                isAutomatable: true,
                type: .continuous
            ),
            NodeParameter(
                name: Params.lowPassCutoff,
                label: "Low Pass Cutoff",
                value: 8000.0,
                min: 1000.0,
                max: 15000.0,
                defaultValue: 8000.0,
                unit: "Hz",
                isAutomatable: true,
                type: .continuous
            )
        ]

        // Configure delay
        delayUnit.delayTime = 0.5  // 500ms
        delayUnit.feedback = 30.0   // 30%
        delayUnit.wetDryMix = 30.0  // 30% wet
        delayUnit.lowPassCutoff = 8000.0  // 8kHz
    }


    // MARK: - Audio Processing

    override func process(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) -> AVAudioPCMBuffer {
        guard !isBypassed, isActive else {
            return buffer
        }

        // Apply delay parameters
        if let delayTime = getParameter(name: Params.delayTime) {
            delayUnit.delayTime = TimeInterval(delayTime)
        }

        if let feedback = getParameter(name: Params.feedback) {
            delayUnit.feedback = feedback
        }

        if let wetDryMix = getParameter(name: Params.wetDryMix) {
            delayUnit.wetDryMix = wetDryMix
        }

        if let cutoff = getParameter(name: Params.lowPassCutoff) {
            delayUnit.lowPassCutoff = cutoff
        }

        // Note: Full implementation would render through AVAudioUnit
        return buffer
    }


    // MARK: - Bio-Reactivity

    override func react(to signal: BioSignal) {
        // Heart Rate → Delay Time (tempo-synced)
        // Convert BPM to delay time for rhythmic echoes
        // 60 BPM = 1.0s delay (quarter note)
        // 120 BPM = 0.5s delay

        let heartRate = signal.heartRate
        let bpm = max(40.0, min(120.0, heartRate))  // Clamp to reasonable range

        // Calculate quarter note duration in seconds
        let quarterNoteDuration = 60.0 / bpm

        // Use eighth note for delay (half of quarter)
        let targetDelayTime = Float(quarterNoteDuration / 2.0)  // Eighth note

        // Smooth transition
        if let currentDelay = getParameter(name: Params.delayTime) {
            let smoothed = currentDelay * 0.95 + targetDelayTime * 0.05
            setParameter(name: Params.delayTime, value: smoothed)
        }

        // HRV Coherence → Feedback Amount
        // Higher coherence = more repeats (creates rhythmic texture)
        let coherence = signal.coherence

        let targetFeedback: Float
        if coherence < 40 {
            // Low coherence: minimal feedback (10-30%)
            targetFeedback = 10.0 + Float(coherence / 40.0) * 20.0
        } else if coherence < 60 {
            // Medium coherence: moderate feedback (30-50%)
            targetFeedback = 30.0 + Float((coherence - 40.0) / 20.0) * 20.0
        } else {
            // High coherence: more feedback (50-70%)
            targetFeedback = 50.0 + Float((coherence - 60.0) / 40.0) * 20.0
        }

        if let currentFeedback = getParameter(name: Params.feedback) {
            let smoothed = currentFeedback * 0.98 + targetFeedback * 0.02
            setParameter(name: Params.feedback, value: smoothed)
        }

        // Audio Level → Wet/Dry Mix
        // More audio = more delay effect
        let audioLevel = signal.audioLevel
        let targetMix = 20.0 + Float(audioLevel) * 40.0  // 20-60%

        if let currentMix = getParameter(name: Params.wetDryMix) {
            let smoothed = currentMix * 0.9 + targetMix * 0.1
            setParameter(name: Params.wetDryMix, value: smoothed)
        }

        // HRV → Low Pass Cutoff (darker = more stressed)
        let targetCutoff = 4000.0 + Float(coherence / 100.0) * 8000.0  // 4-12kHz

        if let currentCutoff = getParameter(name: Params.lowPassCutoff) {
            let smoothed = currentCutoff * 0.95 + targetCutoff * 0.05
            setParameter(name: Params.lowPassCutoff, value: smoothed)
        }
    }


    // MARK: - Lifecycle

    override func prepare(sampleRate: Double, maxFrames: AVAudioFrameCount) {
        // Delay is ready (uses AVAudioUnitDelay)
    }

    override func start() {
        super.start()
        print("🎵 DelayNode started")
    }

    override func stop() {
        super.stop()
        print("🎵 DelayNode stopped")
    }


    // MARK: - Tempo Sync Helpers

    /// Get delay time for musical subdivision
    func setTempoSyncedDelay(bpm: Double, subdivision: MusicalSubdivision) {
        let quarterNoteDuration = 60.0 / bpm
        let delayTime = Float(quarterNoteDuration * subdivision.multiplier)
        setParameter(name: Params.delayTime, value: delayTime)
    }

    enum MusicalSubdivision {
        case whole      // 4 beats
        case half       // 2 beats
        case quarter    // 1 beat
        case eighth     // 1/2 beat
        case sixteenth  // 1/4 beat
        case triplet    // 1/3 beat

        var multiplier: Double {
            switch self {
            case .whole: return 4.0
            case .half: return 2.0
            case .quarter: return 1.0
            case .eighth: return 0.5
            case .sixteenth: return 0.25
            case .triplet: return 1.0 / 3.0
            }
        }
    }
}
