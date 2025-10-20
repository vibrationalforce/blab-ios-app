import Foundation
import AVFoundation

/// Reverb effect node with bio-reactive parameters
/// HRV Coherence → Reverb Wetness (higher coherence = more reverb = spacious feeling)
@MainActor
class ReverbNode: BaseBlabNode {

    // MARK: - AVAudioUnit Reverb

    private let reverbUnit: AVAudioUnitReverb


    // MARK: - Parameters

    private enum Params {
        static let wetDry = "wetDry"
        static let smallRoomSize = "smallRoomSize"
        static let mediumRoomSize = "mediumRoomSize"
        static let largeRoomSize = "largeRoomSize"
    }


    // MARK: - Initialization

    init() {
        self.reverbUnit = AVAudioUnitReverb()

        super.init(name: "Bio-Reactive Reverb", type: .effect)

        // Setup parameters
        parameters = [
            NodeParameter(
                name: Params.wetDry,
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
                name: Params.smallRoomSize,
                label: "Small Room Size",
                value: 0.0,
                min: 0.0,
                max: 100.0,
                defaultValue: 0.0,
                unit: "%",
                isAutomatable: true,
                type: .continuous
            ),
            NodeParameter(
                name: Params.mediumRoomSize,
                label: "Medium Room Size",
                value: 50.0,
                min: 0.0,
                max: 100.0,
                defaultValue: 50.0,
                unit: "%",
                isAutomatable: true,
                type: .continuous
            ),
            NodeParameter(
                name: Params.largeRoomSize,
                label: "Large Room Size",
                value: 0.0,
                min: 0.0,
                max: 100.0,
                defaultValue: 0.0,
                unit: "%",
                isAutomatable: true,
                type: .continuous
            )
        ]

        // Configure reverb
        reverbUnit.wetDryMix = 30.0  // 30% wet
        reverbUnit.loadFactoryPreset(.mediumHall)
    }


    // MARK: - Audio Processing

    override func process(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) -> AVAudioPCMBuffer {
        // If bypassed, return original buffer
        guard !isBypassed, isActive else {
            return buffer
        }

        // Apply reverb parameters
        if let wetDry = getParameter(name: Params.wetDry) {
            reverbUnit.wetDryMix = wetDry
        }

        // Note: In a full implementation, we'd render through the AVAudioUnit
        // For now, this is a placeholder showing the architecture
        // Real implementation would use AVAudioEngine or manual DSP

        return buffer
    }


    // MARK: - Bio-Reactivity

    override func react(to signal: BioSignal) {
        // HRV Coherence → Reverb Wetness
        // 0-40: Low coherence (stressed) → Dry (10-30% wet)
        // 40-60: Medium coherence → Medium (30-50% wet)
        // 60-100: High coherence (flow state) → Wet (50-80% wet)

        let coherence = signal.coherence

        let targetWetness: Float
        if coherence < 40 {
            // Stressed: less reverb
            targetWetness = 10.0 + Float(coherence / 40.0) * 20.0  // 10-30%
        } else if coherence < 60 {
            // Transitional: medium reverb
            targetWetness = 30.0 + Float((coherence - 40.0) / 20.0) * 20.0  // 30-50%
        } else {
            // Flow state: more reverb (spacious, expansive feeling)
            targetWetness = 50.0 + Float((coherence - 60.0) / 40.0) * 30.0  // 50-80%
        }

        // Smooth transition
        if let currentWetness = getParameter(name: Params.wetDry) {
            let smoothed = currentWetness * 0.95 + targetWetness * 0.05
            setParameter(name: Params.wetDry, value: smoothed)
        }

        // HRV → Room Size (higher HRV = larger room)
        let targetRoomSize = Float(min(signal.hrv / 100.0, 1.0)) * 100.0  // 0-100%
        if let currentRoomSize = getParameter(name: Params.mediumRoomSize) {
            let smoothed = currentRoomSize * 0.98 + targetRoomSize * 0.02
            setParameter(name: Params.mediumRoomSize, value: smoothed)
        }
    }


    // MARK: - Lifecycle

    override func prepare(sampleRate: Double, maxFrames: AVAudioFrameCount) {
        // Reverb is always ready (uses AVAudioUnitReverb)
    }

    override func start() {
        super.start()
        print("🎵 ReverbNode started")
    }

    override func stop() {
        super.stop()
        print("🎵 ReverbNode stopped")
    }
}
