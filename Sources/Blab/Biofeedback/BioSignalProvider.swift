import Foundation
import Combine
import CoreMotion

/// Aggregates biometric and motion data into a normalized control vector used by
/// the audio, visual, and metadata subsystems.
@MainActor
final class BioSignalProvider: ObservableObject {
    struct EmotionState {
        var valence: Double
        var arousal: Double
        var label: String
    }

    struct NormalizedVector {
        var hrv: Double
        var heartRate: Double
        var coherence: Double
        var gsrs: Double?
        var eeg: Double?
        var emotion: EmotionState
    }

    @Published private(set) var vector = NormalizedVector(
        hrv: 0.5,
        heartRate: 0.5,
        coherence: 0.5,
        gsrs: nil,
        eeg: nil,
        emotion: EmotionState(valence: 0, arousal: 0, label: "Neutral")
    )

    private var cancellables = Set<AnyCancellable>()
    private let motionManager = CMMotionManager()

    func bind(to healthKit: HealthKitManager) {
        healthKit.$hrvCoherence
            .combineLatest(healthKit.$heartRate, healthKit.$hrvRMSSD)
            .receive(on: RunLoop.main)
            .sink { [weak self] coherence, bpm, hrv in
                self?.update(hrv: hrv, heartRate: bpm, coherence: coherence)
            }
            .store(in: &cancellables)
    }

    func updateAudioMetrics(level: Float, pitch: Float) {
        let arousal = Double(level)
        let valence = min(1.0, Double(pitch / 880.0))
        let label: String

        switch valence {
        case ..<0.2: label = "Calm"
        case ..<0.5: label = "Curious"
        case ..<0.8: label = "Energetic"
        default: label = "Euphoric"
        }

        vector.emotion = EmotionState(valence: valence, arousal: arousal, label: label)
    }

    func updatePeripheral(gsr: Double? = nil, eeg: Double? = nil) {
        if let gsr { vector.gsrs = clamp(gsr) }
        if let eeg { vector.eeg = clamp(eeg) }
    }

    func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion = motion else { return }
            let energy = sqrt(pow(motion.userAcceleration.x, 2) + pow(motion.userAcceleration.y, 2) + pow(motion.userAcceleration.z, 2))
            let clamped = min(1.0, max(0.0, energy * 2))
            let arousal = (self?.vector.emotion.arousal ?? 0) * 0.7 + clamped * 0.3
            self?.vector.emotion.arousal = arousal
        }
    }

    func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }

    private func update(hrv: Double, heartRate: Double, coherence: Double) {
        let normalizedHRV = clamp(hrv / 150.0)
        let normalizedHeart = clamp((heartRate - 40) / 80.0)
        let normalizedCoherence = clamp(coherence / 100.0)

        vector.hrv = normalizedHRV
        vector.heartRate = normalizedHeart
        vector.coherence = normalizedCoherence
    }

    private func clamp(_ value: Double) -> Double {
        return min(1.0, max(0.0, value))
    }
}
