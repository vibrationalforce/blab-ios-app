import Foundation
import AVFoundation
import Combine

/// Central audio engine that manages and mixes multiple audio sources
///
/// Coordinates:
/// - Microphone input (for voice/breath capture)
/// - Binaural beat generation (for brainwave entrainment)
/// - Real-time mixing and effects
///
/// This class acts as the central hub for all audio processing in Blab
@MainActor
class AudioEngine: ObservableObject {

    // MARK: - Published Properties

    /// Whether the audio engine is currently running
    @Published var isRunning: Bool = false

    /// Whether binaural beats are enabled
    @Published var binauralBeatsEnabled: Bool = false

    /// Current binaural beat state
    @Published var currentBrainwaveState: BinauralBeatGenerator.BrainwaveState = .alpha

    /// Binaural beat amplitude (0.0 - 1.0)
    @Published var binauralAmplitude: Float = 0.3


    // MARK: - Audio Components

    /// Microphone manager for voice/breath input
    let microphoneManager: MicrophoneManager

    /// Binaural beat generator for healing frequencies
    private let binauralGenerator = BinauralBeatGenerator()

    /// HealthKit manager for HRV-based adaptations
    private var healthKitManager: HealthKitManager?


    // MARK: - Private Properties

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()


    // MARK: - Initialization

    init(microphoneManager: MicrophoneManager) {
        self.microphoneManager = microphoneManager

        // Configure default binaural beat settings
        binauralGenerator.configure(
            carrier: 432.0,  // Healing frequency
            beat: 10.0,      // Alpha waves (relaxation)
            amplitude: 0.3
        )
    }


    // MARK: - Public Methods

    /// Start the audio engine (microphone + optional binaural beats)
    func start() {
        // Start microphone
        microphoneManager.startRecording()

        // Start binaural beats if enabled
        if binauralBeatsEnabled {
            binauralGenerator.start()
        }

        isRunning = true
        print("🎵 AudioEngine started")
    }

    /// Stop the audio engine
    func stop() {
        // Stop microphone
        microphoneManager.stopRecording()

        // Stop binaural beats
        binauralGenerator.stop()

        isRunning = false
        print("🎵 AudioEngine stopped")
    }

    /// Toggle binaural beats on/off
    func toggleBinauralBeats() {
        binauralBeatsEnabled.toggle()

        if binauralBeatsEnabled {
            binauralGenerator.start()
            print("🔊 Binaural beats enabled")
        } else {
            binauralGenerator.stop()
            print("🔇 Binaural beats disabled")
        }
    }

    /// Set brainwave state for binaural beats
    /// - Parameter state: Target brainwave state (delta, theta, alpha, beta, gamma)
    func setBrainwaveState(_ state: BinauralBeatGenerator.BrainwaveState) {
        currentBrainwaveState = state
        binauralGenerator.configure(state: state)

        // Restart if currently playing
        if binauralBeatsEnabled {
            binauralGenerator.stop()
            binauralGenerator.start()
        }
    }

    /// Set binaural beat amplitude
    /// - Parameter amplitude: Volume (0.0 - 1.0)
    func setBinauralAmplitude(_ amplitude: Float) {
        binauralAmplitude = amplitude
        binauralGenerator.configure(
            carrier: 432.0,
            beat: currentBrainwaveState.beatFrequency,
            amplitude: amplitude
        )

        // Restart if currently playing
        if binauralBeatsEnabled {
            binauralGenerator.stop()
            binauralGenerator.start()
        }
    }

    /// Connect to HealthKit manager for HRV-based adaptations
    /// - Parameter healthKitManager: HealthKit manager instance
    func connectHealthKit(_ healthKitManager: HealthKitManager) {
        self.healthKitManager = healthKitManager

        // Subscribe to HRV coherence changes
        healthKitManager.$hrvCoherence
            .sink { [weak self] coherence in
                self?.adaptToBiofeedback(coherence: coherence)
            }
            .store(in: &cancellables)
    }


    // MARK: - Private Methods

    /// Adapt binaural beat frequency based on HRV coherence
    /// - Parameter coherence: HRV coherence score (0-100)
    private func adaptToBiofeedback(coherence: Double) {
        guard binauralBeatsEnabled else { return }

        // Use HRV to modulate binaural beat frequency
        binauralGenerator.setBeatFrequencyFromHRV(coherence: coherence)

        // Optional: Adjust amplitude based on coherence
        // Higher coherence = can handle higher amplitude
        let adaptiveAmplitude = Float(0.2 + (coherence / 100.0) * 0.3)  // 0.2-0.5 range
        binauralAmplitude = adaptiveAmplitude

        binauralGenerator.configure(
            carrier: 432.0,
            beat: binauralGenerator.beatFrequency,
            amplitude: adaptiveAmplitude
        )
    }


    // MARK: - Utility Methods

    /// Get human-readable description of current state
    var stateDescription: String {
        if !isRunning {
            return "Audio engine stopped"
        }

        var description = "Microphone: Active"

        if binauralBeatsEnabled {
            description += "\nBinaural Beats: \(currentBrainwaveState.rawValue.capitalized) (\(currentBrainwaveState.beatFrequency) Hz)"
        } else {
            description += "\nBinaural Beats: Off"
        }

        return description
    }
}
