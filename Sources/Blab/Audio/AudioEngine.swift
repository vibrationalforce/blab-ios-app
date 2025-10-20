import Foundation
import AVFoundation
import Combine

/// Central audio engine that manages and mixes multiple audio sources
///
/// Coordinates:
/// - Microphone input (for voice/breath capture)
/// - Binaural beat generation (for brainwave entrainment)
/// - Spatial audio with head tracking
/// - Bio-parameter mapping (HRV → Audio)
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

    /// Whether spatial audio is enabled
    @Published var spatialAudioEnabled: Bool = false

    /// Current binaural beat state
    @Published var currentBrainwaveState: BinauralBeatGenerator.BrainwaveState = .alpha

    /// Binaural beat amplitude (0.0 - 1.0)
    @Published var binauralAmplitude: Float = 0.3


    // MARK: - Audio Components

    /// Microphone manager for voice/breath input
    let microphoneManager: MicrophoneManager

    /// Binaural beat generator for healing frequencies
    private let binauralGenerator = BinauralBeatGenerator()

    /// Spatial audio engine for 3D audio
    private var spatialAudioEngine: SpatialAudioEngine?

    /// Bio-parameter mapper (HRV/HR → Audio parameters)
    private let bioParameterMapper = BioParameterMapper()

    /// HealthKit manager for HRV-based adaptations
    private var healthKitManager: HealthKitManager?

    /// Head tracking manager
    private var headTrackingManager: HeadTrackingManager?

    /// Device capabilities
    private var deviceCapabilities: DeviceCapabilities?


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

        // Initialize device capabilities
        deviceCapabilities = DeviceCapabilities()

        // Initialize head tracking if available
        headTrackingManager = HeadTrackingManager()

        // Initialize spatial audio if available (iOS 15+)
        if let headTracking = headTrackingManager,
           let capabilities = deviceCapabilities,
           capabilities.canUseSpatialAudioEngine {
            spatialAudioEngine = SpatialAudioEngine(
                headTrackingManager: headTracking,
                deviceCapabilities: capabilities
            )
        } else {
            print("⚠️  Spatial audio engine requires iOS 15+")
        }

        // Start monitoring device capabilities
        deviceCapabilities?.startMonitoringAudioRoute()

        print("🎵 AudioEngine initialized")
        print("   Spatial Audio: \(deviceCapabilities?.canUseSpatialAudio == true ? "✅" : "❌")")
        print("   Head Tracking: \(headTrackingManager?.isAvailable == true ? "✅" : "❌")")
    }


    // MARK: - Public Methods

    /// Start the audio engine (microphone + optional binaural beats + spatial audio)
    func start() {
        // Start microphone
        microphoneManager.startRecording()

        // Start binaural beats if enabled
        if binauralBeatsEnabled {
            binauralGenerator.start()
        }

        // Start spatial audio if enabled
        if spatialAudioEnabled, let spatial = spatialAudioEngine {
            do {
                try spatial.start()
                print("🎵 Spatial audio started")
            } catch {
                print("❌ Failed to start spatial audio: \(error)")
                spatialAudioEnabled = false
            }
        }

        // Start bio-parameter mapping updates
        startBioParameterMapping()

        isRunning = true
        print("🎵 AudioEngine started")
    }

    /// Stop the audio engine
    func stop() {
        // Stop microphone
        microphoneManager.stopRecording()

        // Stop binaural beats
        binauralGenerator.stop()

        // Stop spatial audio
        spatialAudioEngine?.stop()

        // Stop bio-parameter mapping
        stopBioParameterMapping()

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

    /// Toggle spatial audio on/off
    func toggleSpatialAudio() {
        spatialAudioEnabled.toggle()

        if spatialAudioEnabled {
            if let spatial = spatialAudioEngine {
                do {
                    try spatial.start()
                    print("🎵 Spatial audio enabled")
                } catch {
                    print("❌ Failed to enable spatial audio: \(error)")
                    spatialAudioEnabled = false
                }
            } else {
                print("⚠️  Spatial audio not available")
                spatialAudioEnabled = false
            }
        } else {
            spatialAudioEngine?.stop()
            print("🎵 Spatial audio disabled")
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


    /// Start bio-parameter mapping (HRV/HR → Audio)
    private func startBioParameterMapping() {
        guard let healthKit = healthKitManager else {
            print("⚠️  Bio-parameter mapping: HealthKit not connected")
            return
        }

        // Update bio-parameters every 100ms
        Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateBioParameters()
            }
            .store(in: &cancellables)

        print("🎛️  Bio-parameter mapping started")
    }

    /// Stop bio-parameter mapping
    private func stopBioParameterMapping() {
        // Cancellables will be cleared when engine stops
        print("🎛️  Bio-parameter mapping stopped")
    }

    /// Update bio-parameters from current biometric data
    private func updateBioParameters() {
        guard let healthKit = healthKitManager else { return }

        // Get current biometric data
        let hrvCoherence = healthKit.hrvCoherence
        let heartRate = healthKit.heartRate
        let voicePitch = microphoneManager.currentPitch
        let audioLevel = microphoneManager.audioLevel

        // Update bio-parameter mapper
        bioParameterMapper.updateParameters(
            hrvCoherence: hrvCoherence,
            heartRate: heartRate,
            voicePitch: voicePitch,
            audioLevel: audioLevel
        )

        // Apply mapped parameters to audio engine
        applyBioParameters()
    }

    /// Apply bio-mapped parameters to audio components
    private func applyBioParameters() {
        // Apply reverb to spatial audio engine
        if let spatial = spatialAudioEngine, spatialAudioEnabled {
            spatial.setReverbBlend(bioParameterMapper.reverbWet)

            // Apply spatial positioning based on HRV
            let pos = bioParameterMapper.spatialPosition
            spatial.positionSource(x: pos.x, y: pos.y, z: pos.z)
        }

        // Apply frequency/amplitude to binaural generator
        if binauralBeatsEnabled {
            binauralGenerator.configure(
                carrier: bioParameterMapper.baseFrequency,
                beat: currentBrainwaveState.beatFrequency,
                amplitude: bioParameterMapper.amplitude
            )
        }
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

        if spatialAudioEnabled {
            description += "\nSpatial Audio: Active"
            if let spatial = spatialAudioEngine {
                description += " (\(spatial.spatialMode.rawValue))"
            }
        } else {
            description += "\nSpatial Audio: Off"
        }

        return description
    }

    /// Get device capabilities summary
    var deviceCapabilitiesSummary: String? {
        deviceCapabilities?.capabilitySummary
    }

    /// Get bio-parameter mapping summary
    var bioParameterSummary: String {
        bioParameterMapper.parameterSummary
    }
}
