import Foundation
import Combine
import simd

/// Coordinates the existing particle and cymatic visualizers with biofeedback
/// and tempo data. The pipeline produces a shared state object that SwiftUI
/// views can observe.
@MainActor
final class HybridVisualizationPipeline: ObservableObject {
    struct VisualizationState {
        var amplitude: Float
        var bpm: Double
        var hrv: Double
        var emotionLabel: String
        var motionVector: SIMD3<Float>
    }

    @Published private(set) var state = VisualizationState(
        amplitude: 0,
        bpm: 120,
        hrv: 0.5,
        emotionLabel: "Neutral",
        motionVector: .zero
    )

    private var cancellables = Set<AnyCancellable>()

    func bind(audioEngine: AudioEngine, bioProvider: BioSignalProvider, microphone: MicrophoneManager, sequencer: SequencerCore) {
        microphone.$audioLevel
            .combineLatest(sequencer.$clock.map { $0.bpm })
            .receive(on: RunLoop.main)
            .sink { [weak self] level, bpm in
                self?.state.amplitude = level
                self?.state.bpm = bpm
            }
            .store(in: &cancellables)

        bioProvider.$vector
            .receive(on: RunLoop.main)
            .sink { [weak self] vector in
                self?.state.hrv = vector.coherence
                self?.state.emotionLabel = vector.emotion.label
            }
            .store(in: &cancellables)
    }

    func updateMotionVector(_ vector: SIMD3<Double>) {
        state.motionVector = SIMD3<Float>(Float(vector.x), Float(vector.y), Float(vector.z))
    }
}
